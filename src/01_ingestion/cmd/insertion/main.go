package main

import (
	"context"
	"log"
	"os"
	"os/signal"
	"regexp"
	"strings"
	"syscall"
	"time"

	"github.com/mmcdole/gofeed"

	"github.com/tilmanzzz/media-lens/internal/go/db"
)

const (
	discoveryInterval = 1 * time.Minute
	pollingInterval   = 1 * time.Minute
	maxDiscoveryTicks = 2
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

func stripHTMLTags(input string) string {
	re := regexp.MustCompile(`<[^>]*>`)
	return re.ReplaceAllString(input, "")
}

func extractHosts(feed *gofeed.Feed) string {
	var hosts []string
	if len(feed.Authors) > 0 {
		for _, a := range feed.Authors {
			if a.Name != "" {
				hosts = append(hosts, a.Name)
			}
		}
	} else if itunes := feed.Extensions["itunes"]; itunes != nil && len(itunes["author"]) > 0 {
		for _, a := range itunes["author"] {
			if a.Value != "" {
				hosts = append(hosts, a.Value)
			}
		}
	}
	return strings.Join(hosts, ", ")
}

func main() {
	var seedURLs []string

	if len(os.Args) < 2 {
		seedURLs = []string{
			"https://feeds.megaphone.fm/ADL5417720568",
			"https://rss.buzzsprout.com/1032730.rss",
			"https://feeds.captivate.fm/thebest5minutewine/",
			"https://feeds.transistor.fm/5-minute-morning-show",
			"https://feed.podbean.com/themicropodcast/feed.xml",
		}
	} else {
		seedURLs = os.Args[1:]
	}

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	store, err := db.NewStore(ctx, os.Getenv("POSTGRES_URL"))
	if err != nil {
		log.Fatalf("Failed to connect to database: %v", err)
	}
	defer store.Close()

	parser := gofeed.NewParser()

	go startDiscoveryLoop(ctx, store, parser, seedURLs, discoveryInterval, maxDiscoveryTicks)
	go startPollingLoop(ctx, store, parser, pollingInterval)

	log.Printf("Metadata module successfully started. Polling interval: %v | Discovery interval: %v", pollingInterval, discoveryInterval)

	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, os.Interrupt, syscall.SIGTERM)
	<-sigChan

	log.Println("Termination signal received. Shutting down metadata module operations...")
}

func startDiscoveryLoop(ctx context.Context, store *db.Store, parser *gofeed.Parser, seedURLs []string, interval time.Duration, maxDiscoverPerTick int) {
	ticker := time.NewTicker(interval)
	defer ticker.Stop()

	runDiscoveryPass(ctx, store, parser, seedURLs, maxDiscoverPerTick)

	for {
		select {
		case <-ctx.Done():
			log.Println("Discovery loop stopped cleanly.")
			return
		case <-ticker.C:
			runDiscoveryPass(ctx, store, parser, seedURLs, maxDiscoverPerTick)
		}
	}
}

func runDiscoveryPass(ctx context.Context, store *db.Store, parser *gofeed.Parser, seedURLs []string, maxDiscover int) {
	log.Println("[Discovery] Starting discovery cycle...")

	tracked, err := store.GetPodcastsForIngestion(ctx, "full")
	if err != nil {
		log.Printf("[Discovery] Error fetching tracked podcasts for deduplication: %v", err)
		return
	}

	trackedMap := make(map[string]bool)
	for _, p := range tracked {
		trackedMap[p.FeedURL] = true
	}

	discoveredCount := 0
	for _, rssURL := range seedURLs {
		if discoveredCount >= maxDiscover {
			break
		}

		if trackedMap[rssURL] {
			continue
		}

		log.Printf("[Discovery] New untracked feed discovered: %s", rssURL)

		feed, err := parser.ParseURLWithContext(rssURL, ctx)
		if err != nil {
			log.Printf("[Discovery] Failed to parse discovered feed %s: %v", rssURL, err)
			continue
		}

		guid := feed.Link
		if itunes := feed.Extensions["itunes"]; itunes != nil && len(itunes["author"]) > 0 {
			guid = itunes["author"][0].Value + feed.Title
		}
		if guid == "" {
			guid = rssURL
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

		var remoteUpdateTime *time.Time
		if feed.UpdatedParsed != nil {
			remoteUpdateTime = feed.UpdatedParsed
		} else if feed.PublishedParsed != nil {
			remoteUpdateTime = feed.PublishedParsed
		} else if len(feed.Items) > 0 && feed.Items[0].PublishedParsed != nil {
			remoteUpdateTime = feed.Items[0].PublishedParsed
		}

		// set source_updated_at to now if none has been found
		if remoteUpdateTime == nil {
			now := time.Now()
			remoteUpdateTime = &now
		}

		// truncate to seconds
		if remoteUpdateTime != nil {
			truncated := remoteUpdateTime.Truncate(time.Second)
			remoteUpdateTime = &truncated
		}

		hosts := extractHosts(feed)
		cleanDescription := stripHTMLTags(feed.Description)

		err = store.InsertPodcast(
			ctx,
			guid,
			strPtr(hosts),
			rssURL,
			feed.Title,
			strPtr(cleanDescription),
			intPtr(episodeCount),
			feed.Categories,
			imageURL,
			publishedAt,
			&maxEpisodes,
			remoteUpdateTime,
		)
		if err != nil {
			log.Printf("[Discovery] Database insertion failed for %s: %v", rssURL, err)
			continue
		}

		log.Printf("[Discovery] Successfully inserted and initialized: %s", feed.Title)
		discoveredCount++
	}

	log.Printf("[Discovery] Cycle finished. Registered %d new podcast targets.", discoveredCount)
}

func startPollingLoop(ctx context.Context, store *db.Store, parser *gofeed.Parser, interval time.Duration) {
	ticker := time.NewTicker(interval)
	defer ticker.Stop()

	runPollingPass(ctx, store, parser)

	for {
		select {
		case <-ctx.Done():
			log.Println("Polling loop stopped cleanly.")
			return
		case <-ticker.C:
			runPollingPass(ctx, store, parser)
		}
	}
}

func runPollingPass(ctx context.Context, store *db.Store, parser *gofeed.Parser) {
	log.Println("[Poller] Starting change-detection polling cycle...")

	podcasts, err := store.GetPodcastsForIngestion(ctx, "full")
	if err != nil {
		log.Printf("[Poller] Error retrieving podcasts for tracking sync: %v", err)
		return
	}

	if len(podcasts) == 0 {
		log.Println("[Poller] No tracked podcasts found in database. Skipping cycle.")
		return
	}

	for _, p := range podcasts {
		select {
		case <-ctx.Done():
			return
		default:
		}

		feed, err := parser.ParseURLWithContext(p.FeedURL, ctx)
		if err != nil {
			log.Printf("[Poller] Network/Parsing failure for feed %s: %v", p.FeedURL, err)
			continue
		}

		var remoteUpdateTime *time.Time
		if feed.UpdatedParsed != nil {
			remoteUpdateTime = feed.UpdatedParsed
		} else if feed.PublishedParsed != nil {
			remoteUpdateTime = feed.PublishedParsed
		} else if len(feed.Items) > 0 && feed.Items[0].PublishedParsed != nil {
			remoteUpdateTime = feed.Items[0].PublishedParsed
		}

		if remoteUpdateTime == nil {
			now := time.Now()
			remoteUpdateTime = &now
		}

		guid := feed.Link
		if itunes := feed.Extensions["itunes"]; itunes != nil && len(itunes["author"]) > 0 {
			guid = itunes["author"][0].Value + feed.Title
		}

		hosts := extractHosts(feed)
		cleanDescription := stripHTMLTags(feed.Description)

		err = store.SyncPodcastMetadata(ctx, p.ID, guid, feed.Title, cleanDescription, hosts, remoteUpdateTime)
		if err != nil {
			log.Printf("[Poller] Failed to sync metadata for ID %s: %v", p.ID, err)
			continue
		}

		log.Printf("[Poller] Synced metadata and source_system_updated_at for '%s'", p.Title)
	}

	log.Println("[Poller] Change-detection polling cycle complete.")
}
