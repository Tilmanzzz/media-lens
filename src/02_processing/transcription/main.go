package main

import (
	"context"
	"fmt"
	"log"
	"os"
	"os/signal"
	"syscall"

	"github.com/tilmanzzz/audio-lens/internal/blob"

	"github.com/tilmanzzz/audio-lens/internal/db"

	"github.com/tilmanzzz/audio-lens/internal/queue"
)

func main() {
	//_ = godotenv.Load("../../.env")

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	// 1. Initialize the new Queue client instead of raw Redis
	q, err := queue.NewClient(os.Getenv("REDIS_ADDR"))
	if err != nil {
		log.Fatalf("Could not connect to Queue: %v", err)
	}

	store, err := db.NewStore(ctx, os.Getenv("POSTGRES_URL"))
	if err != nil {
		log.Fatalf("Failed to initialize store: %v", err)
	}

	fmt.Printf("MINIO ENDPOINT: %v", os.Getenv("MINIO_ENDPOINT"))
	bronze, err := blob.NewBucket(os.Getenv("MINIO_ENDPOINT"), os.Getenv("MINIO_USER"), os.Getenv("MINIO_PASS"), "bronze")
	if err != nil {
		log.Fatalf("Failed to initialize bronze bucket: %v", err)
	}

	silver, err := blob.NewBucket(os.Getenv("MINIO_ENDPOINT"), os.Getenv("MINIO_USER"), os.Getenv("MINIO_PASS"), "silver")
	if err != nil {
		log.Fatalf("Failed to initialize silver bucket: %v", err)
	}

	log.Println("Transcription Worker online. Waiting for tasks...")

	for {
		select {
		case <-ctx.Done():
			log.Println("Shutting down worker...")
			return
		default:
			// 2. Use the simplified Dequeue method
			// This still blocks until a task is available
			episodeID, err := q.DequeueTranscription(ctx)
			if err != nil {
				// We check for ctx.Done here because BRPop might return an error
				// when the connection closes during shutdown
				if ctx.Err() == nil {
					log.Printf("Queue error: %v", err)
				}
				continue
			}

			log.Printf("Processing Episode ID: %s", episodeID)

			if err := process(ctx, episodeID, store, bronze, silver); err != nil {
				log.Printf("Processing failed for %s: %v", episodeID, err)
			}
		}
	}
}

func process(ctx context.Context, id string, store *db.Store, bronze, silver *blob.Bucket) error {
	// 1. Get DB record
	ep, err := store.GetEpisodeByID(ctx, id)
	if err != nil {
		return err
	}

	// 2. Download from Bronze
	audio, err := bronze.Download(ctx, ep.AudioKey)
	if err != nil {
		return err
	}
	defer audio.Close()

	// 3. Transcribe (Placeholder)
	transcript := "Insert Transcript for " + ep.Title

	// 4. Save to Silver Bucket
	transcriptKey := ep.AudioKey + ".json"
	if err := silver.UploadJSON(ctx, transcriptKey, transcript); err != nil {
		return err
	}

	// 5. Update Status in DB
	return store.MarkTranscribed(ctx, id, transcriptKey)
}
