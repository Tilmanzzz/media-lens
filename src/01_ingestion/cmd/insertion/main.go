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
	var rssURLs []string

	if len(os.Args) < 2 {
		rssURLs = []string{
			"https://feeds.megaphone.fm/ADL5417720568",
			"https://rss.buzzsprout.com/1032730.rss",
			"https://feeds.captivate.fm/thebest5minutewine/",
			"https://feeds.transistor.fm/5-minute-morning-show",
			"https://feed.podbean.com/themicropodcast/feed.xml",
		}
	} else {
		// Take all command-line arguments as URLs
		rssURLs = os.Args[1:]
	}

	ctx := context.Background()

	store, err := db.NewStore(ctx, os.Getenv("POSTGRES_URL"))
	if err != nil {
		log.Fatalf("Failed to connect: %v", err)
	}
	defer store.Close()

	parser := gofeed.NewParser()

	for _, rssURL := range rssURLs {
		log.Printf("Processing feed: %s", rssURL)

		feed, err := parser.ParseURL(rssURL)
		if err != nil {
			log.Printf("Failed to parse RSS feed %s: %v", rssURL, err)
			continue // Skip to the next feed
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
			log.Printf("Could not insert podcast %s: %v", rssURL, err)
			continue // Skip to the next feed
		}

		log.Printf("Successfully added podcast:")
		log.Printf("Title: %s", feed.Title)
		log.Printf("Episodes discovered: %d", episodeCount)
		log.Printf("Feed URL: %s\n", rssURL)
	}
}
