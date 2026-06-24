package main

import (
	"bytes"
	"context"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"strconv"
	"strings"
	"time"

	"github.com/mmcdole/gofeed"
	"github.com/tilmanzzz/media-lens/internal/go/blob"
	"github.com/tilmanzzz/media-lens/internal/go/db"
)

type worker struct {
	store      *db.Store
	bronze     *blob.Bucket
	httpClient *http.Client
	feedParser *gofeed.Parser
}

func main() {
	ctx := context.Background()

	w := setupWorker(ctx)
	defer w.store.Close()

	loadMode := os.Getenv("LOAD_MODE")
	if loadMode != "full" && loadMode != "delta" {
		loadMode = "delta"
	}

	batchID, err := w.store.CreatePipelineBatch(ctx, "ingestion", loadMode)
	if err != nil {
		log.Fatalf("failed to start batch: %v", err)
	}
	fmt.Printf("started pipeline batch [%s] mode: %s\n", batchID, loadMode)

	podcasts, err := w.store.GetPodcastsForIngestion(ctx, loadMode)
	if err != nil {
		log.Fatalf("failed to fetch target podcasts: %v", err)
	}

	var allEpisodes []db.Episode

	for _, p := range podcasts {
		fmt.Printf("processing feed episodes: %s\n", p.FeedURL)

		eps, err := w.processPodcast(ctx, p, loadMode, batchID)
		if err != nil {
			log.Printf("skipping podcast %s: %v", p.ID, err)
			continue
		}
		allEpisodes = append(allEpisodes, eps...)
	}

	if len(allEpisodes) > 0 {
		fmt.Printf("flushing global batch: writing %d episodes...\n", len(allEpisodes))
		if err := w.flushEpisodes(ctx, allEpisodes); err != nil {
			log.Fatalf("critical database flush failed: %v", err)
		}
	} else {
		fmt.Println("no episodes required ingestion")
	}

	if err := w.store.CompletePipelineBatch(ctx, batchID, "success"); err != nil {
		log.Fatalf("failed to close batch: %v", err)
	}
	fmt.Printf("successfully completed batch %s\n", batchID)
}

func setupWorker(ctx context.Context) *worker {
	store, err := db.NewStore(ctx, os.Getenv("POSTGRES_URL"))
	if err != nil {
		log.Fatalf("db connection failed: %v", err)
	}

	bronze, err := blob.NewBucket(
		os.Getenv("MINIO_ENDPOINT"),
		os.Getenv("MINIO_USER"),
		os.Getenv("MINIO_PASS"),
		"bronze",
	)
	if err != nil {
		log.Fatalf("minio connection failed: %v", err)
	}

	return &worker{
		store:      store,
		bronze:     bronze,
		httpClient: &http.Client{Timeout: 15 * time.Minute},
		feedParser: gofeed.NewParser(),
	}
}

func (w *worker) processPodcast(ctx context.Context, p db.Podcast, loadMode, batchID string) ([]db.Episode, error) {
	// fetch raw xml for storage
	req, err := http.NewRequestWithContext(ctx, "GET", p.FeedURL, nil)
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %w", err)
	}

	// impersonate Apple Podcasts to avoid being blocked by CDNs
	req.Header.Set("User-Agent", "AppleCoreMedia/1.0.0.19E266 (iPhone; U; CPU OS 15_4_1 like Mac OS X; en_us)")
	req.Header.Set("Accept", "application/rss+xml, application/xml, text/xml;q=0.9, */*;q=0.8")
	req.Header.Set("Accept-Language", "en-US,en;q=0.9")

	resp, err := w.httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("failed to fetch feed: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("bad http status: %d", resp.StatusCode)
	}

	bodyBytes, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("failed to read response body: %w", err)
	}

	// upload feed snapshot to minio
	xmlKey, err := w.bronze.UploadPodcastMetadata(
		ctx,
		p.ID,
		"metadata",
		"feed",
		"application/xml",
		bytes.NewReader(bodyBytes),
		int64(len(bodyBytes)),
		p.FeedURL,
	)
	if err != nil {
		return nil, fmt.Errorf("failed to upload xml to minio: %w", err)
	}

	// parse feed from downloaded bytes
	feed, err := w.feedParser.Parse(bytes.NewReader(bodyBytes))
	if err != nil {
		return nil, fmt.Errorf("feed parse error: %w", err)
	}

	// mark ingested and save the xml path
	if err := w.store.MarkPodcastIngested(ctx, p.ID, batchID, xmlKey); err != nil {
		return nil, fmt.Errorf("failed to link batch to podcast record: %w", err)
	}

	existingEps, err := w.store.GetEpisodeMap(ctx, p.ID)
	if err != nil {
		return nil, fmt.Errorf("failed fetching state map: %w", err)
	}

	items := feed.Items
	if p.MaxEpisodes != nil && len(items) > *p.MaxEpisodes {
		items = items[:*p.MaxEpisodes]
	}

	var processed []db.Episode
	for _, item := range items {
		ep, err := w.processEpisode(ctx, p, item, existingEps, loadMode, batchID)
		if err != nil {
			log.Printf("skipping item %s: %v", item.GUID, err)
			continue
		}
		if ep != nil {
			processed = append(processed, *ep)
		}
	}

	return processed, nil
}

func (w *worker) processEpisode(
	ctx context.Context,
	p db.Podcast,
	item *gofeed.Item,
	existingEps map[string]db.Episode,
	loadMode, batchID string,
) (*db.Episode, error) {
	if len(item.Enclosures) == 0 {
		return nil, nil
	}
	enclosureURL := item.Enclosures[0].URL

	// extract reliable timestamp
	episodeUpdated := extractEpisodeTimestamp(item)

	existingEp, exists := existingEps[item.GUID]
	isChanged := loadMode == "full" || !exists

	// tier 2 delta check: did this specific episode change?
	if !isChanged {
		if existingEp.EnclosureURL != enclosureURL {
			isChanged = true
		}
		if existingEp.SourceSystemUpdatedAt.Before(episodeUpdated) {
			isChanged = true
		}
	}

	if !isChanged {
		return nil, nil
	}

	// stop previous pipeline runs if replacing an episode
	if exists && existingEp.BatchID != "" {
		_ = w.store.StopPreviousBatchIfNeeded(ctx, existingEp.BatchID)
	}

	audioKey, err := w.uploadMedia(ctx, p.ID, item.GUID, "audio", "original", enclosureURL, "audio/mpeg, audio/*;q=0.9, */*;q=0.8")
	if err != nil {
		return nil, fmt.Errorf("audio upload failed: %w", err)
	}

	imageURL := extractImageURL(item)
	var coverKey string
	if imageURL != "" {
		key, err := w.uploadMedia(ctx, p.ID, item.GUID, "cover", "image", imageURL, "image/webp,image/apng,image/*,*/*;q=0.8")
		if err != nil {
			log.Printf("warning: cover upload failed for %s: %v", item.GUID, err)
		} else {
			coverKey = key
		}
	}

	var duration *int
	if itunes, ok := item.Extensions["itunes"]; ok && len(itunes["duration"]) > 0 {
		duration = parseDuration(itunes["duration"][0].Value)
	}

	return &db.Episode{
		PodcastID:             p.ID,
		GUID:                  item.GUID,
		Title:                 item.Title,
		AudioKey:              audioKey,
		CoverKey:              coverKey,
		PublishedAt:           item.PublishedParsed,
		DurationSeconds:       duration,
		EnclosureURL:          enclosureURL,
		BatchID:               batchID,
		SourceSystemUpdatedAt: &episodeUpdated,
	}, nil
}

func (w *worker) uploadMedia(
	ctx context.Context,
	podcastID, episodeGUID, assetType, filename, url, acceptHeader string,
) (string, error) {
	req, err := http.NewRequestWithContext(ctx, "GET", url, nil)
	if err != nil {
		return "", err
	}

	// impersonate Apple Podcasts to bypass CDNs
	req.Header.Set("User-Agent", "AppleCoreMedia/1.0.0.19E266 (iPhone; U; CPU OS 15_4_1 like Mac OS X; en_us)")
	req.Header.Set("Accept", acceptHeader)
	req.Header.Set("Accept-Language", "en-US,en;q=0.9")

	resp, err := w.httpClient.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return "", fmt.Errorf("bad http status: %d", resp.StatusCode)
	}

	return w.bronze.UploadAsset(
		ctx,
		podcastID,
		episodeGUID,
		assetType,
		filename,
		resp.Header.Get("Content-Type"),
		resp.Body,
		resp.ContentLength,
		url,
	)
}

func (w *worker) flushEpisodes(ctx context.Context, eps []db.Episode) error {
	_, err := w.store.BulkUpsertEpisodes(ctx, eps)
	return err
}

func extractEpisodeTimestamp(item *gofeed.Item) time.Time {
	// 1. try standard parsed fields first
	if item.UpdatedParsed != nil {
		return item.UpdatedParsed.Truncate(time.Second)
	}
	if item.PublishedParsed != nil {
		return item.PublishedParsed.Truncate(time.Second)
	}

	// 2. fallback to raw string
	rawDate := item.Updated
	if rawDate == "" {
		rawDate = item.Published
	}

	// 3. aggressively force parse against common formats
	if rawDate != "" {
		formats := []string{
			time.RFC1123Z, time.RFC1123, time.RFC822Z, time.RFC822,
			time.RFC3339, time.RFC3339Nano,
			"Mon, 2 Jan 2006 15:04:05 -0700",
			"2006-01-02T15:04:05-0700",
		}

		for _, format := range formats {
			if parsed, err := time.Parse(format, strings.TrimSpace(rawDate)); err == nil {
				return parsed.Truncate(time.Second)
			}
		}
		log.Printf("[Warning] Failed to parse custom date format: %s", rawDate)
	}

	// 4. absolute fallback prevents infinite delta loops
	return time.Unix(0, 0)
}

func extractImageURL(item *gofeed.Item) string {
	if item.Image != nil {
		return item.Image.URL
	}
	if itunes, ok := item.Extensions["itunes"]; ok {
		if img, ok := itunes["image"]; ok && len(img) > 0 {
			return img[0].Attrs["href"]
		}
	}
	return ""
}

func parseDuration(val string) *int {
	if val == "" {
		return nil
	}
	parts := strings.Split(val, ":")
	var total int
	if len(parts) == 3 {
		h, _ := strconv.Atoi(parts[0])
		m, _ := strconv.Atoi(parts[1])
		s, _ := strconv.Atoi(parts[2])
		total = h*3600 + m*60 + s
	} else if len(parts) == 2 {
		m, _ := strconv.Atoi(parts[0])
		s, _ := strconv.Atoi(parts[1])
		total = m*60 + s
	} else {
		total, _ = strconv.Atoi(val)
	}

	if total == 0 {
		return nil
	}
	return &total
}
