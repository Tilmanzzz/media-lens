package ingestor

import (
	"context"
	"fmt"
	"os"

	"github.com/jjgmckenzie/podcastindex"
)

// returns podcast index json metadata
func FetchPodcastEpisodeMetadata(pod_name string) podcastindex.Episode {
	// err := godotenv.Load("../../.env")
	// if err != nil {
	// 	log.Fatal("Error loading .env file")
	// }
	key := os.Getenv("PODCAST_INDEX_KEY")
	secret := os.Getenv("PODCAST_INDEX_SECRET")
	fmt.Printf("\nKEY: %s\nSECRET: %s\n", key, secret)
	userAgent := "audio_lens_debug"
	client := podcastindex.NewClient(podcastindex.NewClientOptions{
		UserAgent: userAgent,
		APIKey:    key,
		APISecret: secret,
	})
	ctx := context.Background()
	podcasts, err := client.SearchPodcastsByTitle(ctx, pod_name, nil)
	if err != nil {
		fmt.Printf("failed to search podcasts: %v", err)
	}
	p := podcasts[0]
	episodes, err := client.GetEpisodes(ctx, *p, nil)
	if err != nil {
		fmt.Printf("failed to get episodes: %v", err)
	}
	e := (*episodes)[0]
	return e
}
