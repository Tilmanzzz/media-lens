package main

import (
	"context"
	"fmt"
	"log"
	"net/http"
	"os"
	"time"

	"github.com/mmcdole/gofeed"
	"github.com/tilmanzzz/audio-lens/internal/go/blob"
	"github.com/tilmanzzz/audio-lens/internal/go/db"
	"github.com/tilmanzzz/audio-lens/internal/go/queue"
)

// worker groups shared external clients
type worker struct {
	store      *db.Store
	bronze     *blob.Bucket
	queue      *queue.Client
	httpClient *http.Client
	feedParser *gofeed.Parser
}

func main() {
	ctx := context.Background()

	// init infrastructure
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

	// mock trigger for legacy updates
	if loadMode == "delta" {
		if all, err := w.store.GetPodcastsForIngestion(ctx, "full"); err == nil {
			for _, p := range all {
				_ = w.store.SetPodcastSourceUpdatedAt(ctx, p.ID)
			}
		}
	}

	podcasts, err := w.store.GetPodcastsForIngestion(ctx, loadMode)
	if err != nil {
		log.Fatalf("failed to fetch target podcasts: %v", err)
	}

	var allEpisodes []db.Episode

	// process all feeds sequentially
	for _, p := range podcasts {
		fmt.Printf("processing feed: %s\n", p.FeedURL)

		eps, err := w.processPodcast(ctx, p, loadMode, batchID)
		if err != nil {
			log.Printf("skipping podcast %s: %v", p.ID, err)
			continue
		}
		allEpisodes = append(allEpisodes, eps...)
	}

	// bulk flush results
	if len(allEpisodes) > 0 {
		fmt.Printf("flushing global batch: writing %d episodes...\n", len(allEpisodes))
		if err := w.flushEpisodes(ctx, allEpisodes); err != nil {
			log.Fatalf("critical database flush failed: %v", err)
		}
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

	q, err := queue.NewClient(os.Getenv("REDIS_ADDR"))
	if err != nil {
		log.Fatalf("queue connection failed: %v", err)
	}

	return &worker{
		store:      store,
		bronze:     bronze,
		queue:      q,
		httpClient: &http.Client{Timeout: 15 * time.Minute},
		feedParser: gofeed.NewParser(),
	}
}

func (w *worker) processPodcast(ctx context.Context, p db.Podcast, loadMode, batchID string) ([]db.Episode, error) {
	feed, err := w.feedParser.ParseURLWithContext(p.FeedURL, ctx)
	if err != nil {
		return nil, fmt.Errorf("feed parse error: %w", err)
	}

	// determine canonical guid (prefer itunes author override)
	guid := feed.Link
	if itunes := feed.Extensions["itunes"]; itunes != nil && len(itunes["author"]) > 0 {
		guid = itunes["author"][0].Value + feed.Title
	}

	if err := w.store.UpdatePodcastMetadata(ctx, p.ID, guid, feed.Title, feed.Description, batchID); err != nil {
		return nil, fmt.Errorf("metadata update failed: %w", err)
	}

	// pull existing state for delta checks
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
	// ignore items without an actual audio file
	if len(item.Enclosures) == 0 {
		return nil, nil
	}
	enclosureURL := item.Enclosures[0].URL

	// check if we need to process this episode based on delta rules
	existingEp, exists := existingEps[item.GUID]
	isChanged := loadMode == "full" || !exists

	if !isChanged {
		if existingEp.EnclosureURL != enclosureURL {
			isChanged = true
		}
		if item.PublishedParsed != nil && existingEp.PublishedAt != nil && item.PublishedParsed.After(*existingEp.PublishedAt) {
			isChanged = true
		}
	}

	if !isChanged {
		return nil, nil
	}

	// clean up stale processing locks
	if exists && existingEp.BatchID != "" {
		_ = w.store.StopPreviousBatchIfNeeded(ctx, existingEp.BatchID)
	}

	// upload audio (required)
	audioKey, err := w.uploadMedia(ctx, p.ID, item.GUID, "audio", "original", enclosureURL, "audio/mpeg, audio/*;q=0.9, */*;q=0.8")
	if err != nil {
		return nil, fmt.Errorf("audio upload failed: %w", err)
	}

	// find and upload cover image (optional)
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

	return &db.Episode{
		PodcastID:    p.ID,
		GUID:         item.GUID,
		Title:        item.Title,
		AudioKey:     audioKey,
		CoverKey:     coverKey,
		PublishedAt:  item.PublishedParsed,
		EnclosureURL: enclosureURL,
		BatchID:      batchID,
	}, nil
}

// uploadMedia handles the actual fetching and minio streaming
func (w *worker) uploadMedia(
	ctx context.Context,
	podcastID, episodeGUID, assetType, filename, url, acceptHeader string,
) (string, error) {
	req, err := http.NewRequestWithContext(ctx, "GET", url, nil)
	if err != nil {
		return "", err
	}

	// mimic a real browser to bypass basic cdn blocks
	req.Header.Set("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36")
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
	insertedIDs, err := w.store.BulkUpsertEpisodes(ctx, eps)
	if err != nil {
		return err
	}

	for _, id := range insertedIDs {
		if err := w.queue.EnqueueTranscription(ctx, id); err != nil {
			log.Printf("warning: failed to queue %s: %v", id, err)
		}
	}
	return nil
}

// extractImageURL checks standard elements and itunes extensions
func extractImageURL(item *gofeed.Item) string {
	if item.Image != nil {
		return item.Image.URL
	}
	if itunes, ok := item.Extensions["itunes"]; ok {
		if img, ok := itunes["image"]; ok && len(img) > 0 {
			// Use Attrs instead of Attributes
			return img[0].Attrs["href"]
		}
	}
	return ""
}
