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

func fetchSourceUpdatesStub(ctx context.Context, store *db.Store, podcastID string) error {
	return store.SetPodcastSourceUpdatedAt(ctx, podcastID)
}

func main() {
	ctx := context.Background()

	loadMode := os.Getenv("LOAD_MODE")
	if loadMode != "full" && loadMode != "incremental" {
		loadMode = "incremental"
	}

	store, err := db.NewStore(ctx, os.Getenv("POSTGRES_URL"))
	if err != nil {
		log.Fatalf("DB connection failed: %v", err)
	}
	defer store.Close()

	bronze, err := blob.NewBucket(
		os.Getenv("MINIO_ENDPOINT"),
		os.Getenv("MINIO_USER"),
		os.Getenv("MINIO_PASS"),
		"bronze",
	)
	if err != nil {
		log.Fatalf("MinIO connection failed: %v", err)
	}

	q, err := queue.NewClient(os.Getenv("REDIS_ADDR"))
	if err != nil {
		log.Fatalf("Queue connection failed: %v", err)
	}

	// 1. Initialize Pipeline Batch Ledger Entry
	batchID, err := store.CreatePipelineBatch(ctx, "ingestion", loadMode)
	if err != nil {
		log.Fatalf("Failed to initialize pipeline batch: %v", err)
	}
	fmt.Printf("Started Pipeline Batch [%s] Mode: %s\n", batchID, loadMode)

	if loadMode == "incremental" {
		allPodcasts, err := store.GetPodcastsForIngestion(ctx, "full")
		if err == nil {
			for _, p := range allPodcasts {
				_ = fetchSourceUpdatesStub(ctx, store, p.ID)
			}
		}
	}

	podcasts, err := store.GetPodcastsForIngestion(ctx, loadMode)
	if err != nil {
		log.Fatalf("Failed to fetch target podcasts: %v", err)
	}

	fp := gofeed.NewParser()
	httpClient := &http.Client{Timeout: 30 * time.Minute}

	// Global batch accumulator for all processed episodes across all feeds
	var globalEpisodesToUpsert []db.Episode

	for _, p := range podcasts {
		fmt.Printf("Processing Feed: %s\n", p.FeedURL)

		feed, err := fp.ParseURLWithContext(p.FeedURL, ctx)
		if err != nil {
			log.Printf("Skip: Parse error for %s: %v", p.FeedURL, err)
			continue
		}

		guid := feed.Link
		if feed.Extensions["itunes"] != nil && len(feed.Extensions["itunes"]["author"]) > 0 {
			guid = feed.Extensions["itunes"]["author"][0].Value + feed.Title
		}

		err = store.UpdatePodcastMetadata(ctx, p.ID, guid, feed.Title, feed.Description, batchID)
		if err != nil {
			log.Printf("Failed to update podcast metadata %s: %v", p.ID, err)
			continue
		}

		existingEps, err := store.GetEpisodeMap(ctx, p.ID)
		if err != nil {
			log.Printf("Failed to fetch existing eps for %s: %v", p.ID, err)
			continue
		}

		items := feed.Items
		if p.MaxEpisodes != nil {
			limit := *p.MaxEpisodes
			if len(items) > limit {
				fmt.Printf("Limiting %s to latest %d episodes\n", feed.Title, limit)
				items = items[:limit]
			}
		}

		for _, item := range items {
			if len(item.Enclosures) == 0 {
				continue
			}

			enclosureURL := item.Enclosures[0].URL
			isChanged := false

			existingEp, exists := existingEps[item.GUID]
			if !exists {
				isChanged = true
			} else {
				if existingEp.EnclosureURL != enclosureURL {
					isChanged = true
				}
				if item.PublishedParsed != nil && existingEp.PublishedAt != nil {
					if item.PublishedParsed.After(*existingEp.PublishedAt) {
						isChanged = true
					}
				}
			}

			if !isChanged {
				continue
			}

			// Stream media instantly to MinIO to keep memory low
			audioKey, err := func() (string, error) {
				req, err := http.NewRequestWithContext(ctx, "GET", enclosureURL, nil)
				if err != nil {
					return "", err
				}
				req.Header.Set("User-Agent", "Mozilla/5.0 (compatible; PodcastBot/1.0)")
				req.Header.Set("Accept", "audio/mpeg, audio/*;q=0.9, */*;q=0.8")

				resp, err := httpClient.Do(req)
				if err != nil {
					return "", err
				}
				defer resp.Body.Close()

				if resp.StatusCode != http.StatusOK {
					return "", fmt.Errorf("bad status: %d", resp.StatusCode)
				}

				return bronze.UploadAudio(
					ctx, p.ID, item.GUID, resp.Header.Get("Content-Type"),
					resp.Body, resp.ContentLength, enclosureURL,
				)
			}()
			if err != nil {
				log.Printf("Failed media storage step for %s: %v", item.GUID, err)
				continue
			}

			// Add metadata configuration to the global write pipeline list
			globalEpisodesToUpsert = append(globalEpisodesToUpsert, db.Episode{
				PodcastID:    p.ID,
				GUID:         item.GUID,
				Title:        item.Title,
				AudioKey:     audioKey,
				PublishedAt:  item.PublishedParsed,
				EnclosureURL: enclosureURL,
				BatchID:      batchID,
			})
		}
		fmt.Printf("Finished file processing loop for feed: %s\n", feed.Title)
	}

	// 3. Single Relational Operations Block per Pipeline Run
	if len(globalEpisodesToUpsert) > 0 {
		fmt.Printf("Flushing global batch: writing %d episodes to database...\n", len(globalEpisodesToUpsert))
		insertedIDs, err := store.BulkUpsertEpisodes(ctx, globalEpisodesToUpsert)
		if err != nil {
			log.Fatalf("Critical: Global database batch flush failed: %v", err)
		}

		// Enqueue IDs down to Redis stream worker pipeline
		for _, episodeID := range insertedIDs {
			if err := q.EnqueueTranscription(ctx, episodeID); err != nil {
				log.Printf("Warning: Failed to enqueue %s to Redis: %v", episodeID, err)
			}
		}
	}

	// 4. Complete batch entry and broadcast NOTIFY transcription_ready
	err = store.CompletePipelineBatch(ctx, batchID, "success")
	if err != nil {
		log.Fatalf("Failed to close pipeline batch: %v", err)
	}
	fmt.Printf("Successfully completed pipeline execution run %s\n", batchID)
}
