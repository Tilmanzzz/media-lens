package db

import "time"

type Podcast struct {
	ID          string     `db:"id"`
	GUID        string     `db:"guid"`
	FeedURL     string     `db:"feed_url"`
	Title       string     `db:"title"`
	IngestedAt  time.Time  `db:"ingested_at"`
	UpdatedAt   *time.Time `db:"updated_at"`
	MaxEpisodes *int       `db:"max_episodes"`
}

type Episode struct {
	ID           string     `db:"id"`
	PodcastID    string     `db:"podcast_id"`
	GUID         string     `db:"guid"`
	Title        string     `db:"title"`
	AudioKey     string     `db:"audio_key"`
	PublishedAt  *time.Time `db:"published_at"`
	EnclosureURL string     `db:"enclosure_url"`
	BatchID      string     `db:"batch_id"`
}
