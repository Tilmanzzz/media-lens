package main

import (
	"context"
	"fmt"
	"log"
	"net/http"
	"os"
	"time"

	"github.com/mmcdole/gofeed"
	"github.com/tilmanzzz/audio-lens/internal/blob"
	"github.com/tilmanzzz/audio-lens/internal/db"
	"github.com/tilmanzzz/audio-lens/internal/queue"
)

func main() {
	//_ = godotenv.Load("../../.env")

	ctx := context.Background()

	// initialize Postgres client
	store, err := db.NewStore(ctx, os.Getenv("POSTGRES_URL"))
	if err != nil {
		log.Fatalf("DB connection failed: %v", err)
	}
	defer store.Close()

	// initialize MinIO client
	bronze, err := blob.NewBucket(
		os.Getenv("MINIO_ENDPOINT"),
		os.Getenv("MINIO_USER"),
		os.Getenv("MINIO_PASS"),
		"bronze",
	)
	if err != nil {
		log.Fatalf("MinIO connection failed: %v", err)
	}

	// initialize Redis client
	q, err := queue.NewClient(os.Getenv("REDIS_ADDR"))
	if err != nil {
		log.Fatalf("Queue connection failed: %v", err)
	}

	podcasts, err := store.GetUnfetchedPodcasts(ctx)
	if err != nil {
		log.Fatalf("Failed to fetch target podcasts: %v", err)
	}

	fp := gofeed.NewParser()
	httpClient := &http.Client{Timeout: 30 * time.Minute}

	for _, p := range podcasts {
		fmt.Printf("Processing Feed: %s\n", p.FeedURL)

		feed, err := fp.ParseURLWithContext(p.FeedURL, ctx)
		if err != nil {
			log.Printf("Skip: Parse error for %s: %v", p.FeedURL, err)
			continue
		}

		existingEps, err := store.GetEpisodeMap(ctx, p.ID)
		if err != nil {
			log.Printf("Failed to fetch existing eps for %s: %v", p.ID, err)
			continue
		}

		items := feed.Items
		fmt.Printf("FOUND %d episodes\n", len(items))

		if p.MaxEpisodes != nil {
			limit := *p.MaxEpisodes

			if len(items) > limit {
				fmt.Printf("Limiting %s to latest %d episodes\n", feed.Title, limit)
				items = items[:limit] // Take only the top N items
			}
		}

		for _, item := range items {
			if len(item.Enclosures) == 0 {
				continue
			}

			enclosureURL := item.Enclosures[0].URL

			// diff check
			if existingEp, exists := existingEps[item.GUID]; exists {
				isChanged := false

				// check for url change
				if existingEp.EnclosureURL != enclosureURL {
					isChanged = true
				}
				// check for release_date update
				if item.PublishedParsed != nil && existingEp.PublishedAt != nil {
					if item.PublishedParsed.After(*existingEp.PublishedAt) {
						isChanged = true
					}
				}

				if !isChanged {
					continue
				}
				fmt.Printf("Update detected for episode: %s\n", item.Title)
			}

			// bundled db operation - first minio, postgres after
			err := func() error {
				req, err := http.NewRequestWithContext(ctx, "GET", enclosureURL, nil)
				if err != nil {
					return err
				}
				req.Header.Set("User-Agent", "Mozilla/5.0 (compatible; PodcastBot/1.0)")
				req.Header.Set("Accept", "audio/mpeg, audio/*;q=0.9, */*;q=0.8")

				resp, err := httpClient.Do(req)
				if err != nil {
					return err
				}
				defer resp.Body.Close()

				if resp.StatusCode != http.StatusOK {
					return fmt.Errorf("bad status: %d", resp.StatusCode)
				}

				// OPERATION A: Upload to MinIO
				audioKey, err := bronze.UploadAudio(
					ctx, p.ID, item.GUID, resp.Header.Get("Content-Type"),
					resp.Body, resp.ContentLength, enclosureURL,
				)
				if err != nil {
					return fmt.Errorf("minio upload failed: %w", err)
				}

				// OPERATION B: Write to Postgres
				episodeID, err := store.UpsertEpisode(ctx, db.Episode{
					PodcastID:    p.ID,
					GUID:         item.GUID,
					Title:        item.Title,
					AudioKey:     audioKey,
					Status:       "pending_transcription",
					PublishedAt:  item.PublishedParsed,
					EnclosureURL: enclosureURL,
				})
				if err != nil {
					// Edge Case: MinIO succeeded, but DB failed.
					// TODO add removal from minio later
					return fmt.Errorf("db upsert failed: %w", err)
				}

				// OPERATION C: Push to Redis Stream
				err = q.EnqueueTranscription(ctx, episodeID)
				if err != nil {
					// Logged but not failed. A scheduled job can sweep the DB for
					// "pending_transcription" records not present in the stream.
					log.Printf("Warning: Failed to enqueue %s: %v", item.GUID, err)
				}

				return nil
			}()
			if err != nil {
				log.Printf("Failed to process episode %s: %v", item.GUID, err)
			}
		}

		err = store.MarkPodcastFetched(ctx, p.ID)
		if err != nil {
			log.Printf("Failed to mark Podcast as fetched %s: %v", p.ID, err)
		}
		fmt.Printf("Completed: %s\n", feed.Title)
	}
}
