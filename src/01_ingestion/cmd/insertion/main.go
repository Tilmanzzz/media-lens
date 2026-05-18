package main

import (
	"context"
	"log"
	"os"
	"time"

	"github.com/google/uuid"
	"github.com/mmcdole/gofeed"

	"github.com/tilmanzzz/audio-lens/internal/go/db"
)

func strPtr(s string) *string {
	if s == "" {
		return nil
	}
	return &s
}

func intPtr(i int) *int {
	return &i
}

func main() {
	var rssURL string

	if len(os.Args) < 2 {
		rssURL = "https://feeds.acast.com/public/shows/93574422-e184-439d-9318-7e9ce0fb0a25"
	} else {
		rssURL = os.Args[1]
	}

	ctx := context.Background()

	store, err := db.NewStore(ctx, os.Getenv("POSTGRES_URL"))
	if err != nil {
		log.Fatalf("Failed to connect: %v", err)
	}
	defer store.Close()

	parser := gofeed.NewParser()

	feed, err := parser.ParseURL(rssURL)
	if err != nil {
		log.Fatalf("Failed to parse RSS feed: %v", err)
	}

	// Feed GUID fallback strategy
	guid := feed.FeedLink
	if guid == "" {
		guid = feed.Link
	}
	if guid == "" {
		guid = rssURL
	}
	if guid == "" {
		guid = uuid.NewString()
	}

	var imageURL *string
	if feed.Image != nil {
		imageURL = strPtr(feed.Image.URL)
	}

	var publishedAt *time.Time
	if feed.PublishedParsed != nil {
		publishedAt = feed.PublishedParsed
	}

	episodeCount := len(feed.Items)

	maxEpisodes := 3

	err = store.InsertPodcast(
		ctx,
		guid,
		nil, // persons
		rssURL,
		feed.Title,
		strPtr(feed.Description),
		intPtr(episodeCount),
		feed.Categories,
		imageURL,
		publishedAt,
		&maxEpisodes,
	)
	if err != nil {
		log.Fatalf("Could not insert podcast: %v", err)
	}

	log.Printf("Successfully added podcast:")
	log.Printf("Title: %s", feed.Title)
	log.Printf("Episodes discovered: %d", episodeCount)
	log.Printf("Feed URL: %s", rssURL)
}
