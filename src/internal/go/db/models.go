package db

import (
	"database/sql"
	"time"
)

type Podcast struct {
	ID                    string       `db:"id"`
	GUID                  string       `db:"guid"`
	FeedURL               string       `db:"feed_url"`
	Title                 string       `db:"title"`
	MaxEpisodes           *int         `db:"max_episodes"`
	SourceSystemUpdatedAt sql.NullTime `db:"source_system_updated_at`
	XMLKey                *string      `db:"xml_key"`
}

type Episode struct {
	ID                    string     `db:"id"`
	PodcastID             string     `db:"podcast_id"`
	GUID                  string     `db:"guid"`
	Title                 string     `db:"title"`
	AudioKey              string     `db:"audio_key"`
	CoverKey              string     `db:"cover_key"`
	PublishedAt           *time.Time `db:"published_at"`
	DurationSeconds       *int       `db:"duration_seconds"`
	EnclosureURL          string     `db:"enclosure_url"`
	BatchID               string     `db:"batch_id"`
	SourceSystemUpdatedAt *time.Time `db:"source_system_updated_at"`
}
