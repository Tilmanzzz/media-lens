package main

import (
	"context"
	"fmt"
	"log"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/tilmanzzz/audio-lens/internal/blob"
	"github.com/tilmanzzz/audio-lens/internal/db"
	"github.com/tilmanzzz/audio-lens/internal/queue"
)

func main() {
	//_ = godotenv.Load("../../.env")

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	// 1. Initialize the new Queue client
	q, err := queue.NewClient(os.Getenv("REDIS_ADDR"))
	if err != nil {
		log.Fatalf("Could not connect to Queue: %v", err)
	}

	store, err := db.NewStore(ctx, os.Getenv("POSTGRES_URL"))
	if err != nil {
		log.Fatalf("Failed to initialize store: %v", err)
	}

	bronze, err := blob.NewBucket(os.Getenv("MINIO_ENDPOINT"), os.Getenv("MINIO_USER"), os.Getenv("MINIO_PASS"), "bronze")
	if err != nil {
		log.Fatalf("Failed to initialize bronze bucket: %v", err)
	}

	silver, err := blob.NewBucket(os.Getenv("MINIO_ENDPOINT"), os.Getenv("MINIO_USER"), os.Getenv("MINIO_PASS"), "silver")
	if err != nil {
		log.Fatalf("Failed to initialize silver bucket: %v", err)
	}

	// 2. Generate a Unique Consumer ID for this specific Docker container
	consumerID, err := os.Hostname()
	if err != nil {
		// Fallback if hostname is unavailable
		consumerID = fmt.Sprintf("worker-%d", time.Now().UnixNano())
	}

	log.Printf("Transcription Worker [%s] online. Waiting for tasks...", consumerID)

	for {
		select {
		case <-ctx.Done():
			log.Println("Shutting down worker...")
			return
		default:
			// 3. Dequeue using the Consumer Group
			messageID, episodeID, err := q.DequeueTranscription(ctx, consumerID)
			if err != nil {
				if ctx.Err() == nil && err.Error() != "no messages returned" {
					log.Printf("Queue error: %v", err)
					time.Sleep(1 * time.Second) // Prevent tight loop on Redis connection issues
				}
				continue
			}

			log.Printf("Processing Episode ID: %s (Message ID: %s)", episodeID, messageID)

			// 4. Execute the core compute task
			if err := process(ctx, episodeID, store, bronze, silver); err != nil {
				log.Printf("Processing failed for %s: %v", episodeID, err)
				// CRITICAL: We DO NOT acknowledge the message here.
				// It remains in the Pending Entries List (PEL) for retry.
				continue
			}

			// 5. Hand-off to the Sectioning Service
			if err := q.EnqueueSectioning(ctx, episodeID); err != nil {
				log.Printf("Failed to enqueue sectioning for %s: %v", episodeID, err)
				// If we fail to pass the baton, we do not ack. The task will be retried.
				continue
			}

			// 6. Acknowledge Completion
			if err := q.AckTranscription(ctx, messageID); err != nil {
				log.Printf("Failed to ack transcription %s: %v", messageID, err)
			} else {
				log.Printf("Successfully completed and acked Episode ID: %s", episodeID)
			}
		}
	}
}

func process(ctx context.Context, id string, store *db.Store, bronze, silver *blob.Bucket) error {
	ep, err := store.GetEpisodeByID(ctx, id)
	if err != nil {
		return err
	}

	audio, err := bronze.Download(ctx, ep.AudioKey)
	if err != nil {
		return err
	}
	defer audio.Close()

	// Transcribe (Placeholder)
	transcript := "Insert Transcript for " + ep.Title

	transcriptKey := ep.AudioKey + ".json"
	if err := silver.UploadJSON(ctx, transcriptKey, transcript); err != nil {
		return err
	}

	// Consider renaming this DB method to reflect the pipeline progression
	// e.g., store.MarkPendingSectioning(ctx, id, transcriptKey)
	if err := store.MarkPendingSectioning(ctx, id); err != nil {
		return err
	}
	return store.SetTranscriptKey(ctx, id, transcriptKey)
}
