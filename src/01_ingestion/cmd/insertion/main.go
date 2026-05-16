package main

import (
	"context"
	"log"
	"os"

	"github.com/tilmanzzz/audio-lens/internal/go/db"
)

func main() {
	var rssURL string
	if len(os.Args) < 2 {
		// log.Fatal("Usage: go run cmd/insert/main.go <rss_url>")
		rssURL = "https://feeds.acast.com/public/shows/93574422-e184-439d-9318-7e9ce0fb0a25"
	} else {
		rssURL = os.Args[1]
	}
	ctx := context.Background()

	// 1. Initialize Store (the NewStore logic we discussed in client.go/store.go)
	store, err := db.NewStore(ctx, os.Getenv("POSTGRES_URL"))
	if err != nil {
		log.Fatalf("Failed to connect: %v", err)
	}
	defer store.Close()

	// 2. Call the podcast-specific logic
	err = store.InsertPodcast(ctx, rssURL, 3)
	if err != nil {
		log.Fatalf("Could not insert podcast: %v", err)
	}

	log.Printf("Successfully added: %s", rssURL)
}
