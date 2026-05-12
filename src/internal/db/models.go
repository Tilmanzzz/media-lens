package db

import "time"

type Podcast struct {
	ID               string  `db:"id"`
	FeedURL          string  `db:"feed_url"`
	FeedEtag         *string `db:"feed_etag"`
	FeedLastModified *string `db:"feed_last_modified"`
	MaxEpisodes      *int    `db:"max_episodes"`
}

type Episode struct {
	ID           string     `db:"id"`
	PodcastID    string     `db:"podcast_id"`
	GUID         string     `db:"guid"`
	Title        string     `db:"title"`
	AudioKey     string     `db:"audio_key"`
	Status       string     `db:"status"`
	PublishedAt  *time.Time // Added to track changes
	EnclosureURL string     // Added to track file changes
}
