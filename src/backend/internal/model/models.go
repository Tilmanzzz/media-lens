package model

import (
	"database/sql"
	"time"
)

// Episode maps to the episodes table
type Episode struct {
	ID          string       `json:"id" example:"550e8400-e29b-41d4-a716-446655440000"`
	Title       string       `json:"title" example:"The Daily - Monday, April 7"`
	PodcastID   string       `json:"podcast_id" example:"the-daily"`
	PublishedAt sql.NullTime `json:"published_at" swaggertype:"string" example:"2026-04-07T00:00:00Z"`
	AudioPath   string       `json:"audio_path" example:"bronze/audio/abc/def/original.mp3"`
	XMLPath     string       `json:"xml_path" example:"bronze/podcasts/ep123.xml"`
	IngestedAt  time.Time    `json:"ingested_at"`
}

// PodcastSection maps to the podcast_sections table
type PodcastSection struct {
	ID             string    `json:"id" example:"660e8400-e29b-41d4-a716-446655440000"`
	EpisodeID      string    `json:"episode_id" example:"550e8400-e29b-41d4-a716-446655440000"`
	SectionIdx     int       `json:"section_idx" example:"1"`
	Text           string    `json:"text" example:"Today we discuss..."`
	Sentiment      string    `json:"sentiment" example:"neutral"`
	SentimentScore float64   `json:"sentiment_score" example:"0.5"`
	Topics         []string  `json:"topics" example:"unknown"`
	ProcessedAt    time.Time `json:"processed_at"`
}

// EpisodeWithSections is a composite response
type EpisodeWithSections struct {
	Episode  Episode          `json:"episode"`
	Sections []PodcastSection `json:"sections"`
}

// PodcastSummary aggregates info for a distinct podcast_id
type PodcastSummary struct {
	PodcastID     string    `json:"podcast_id" example:"the-daily"`
	EpisodeCount  int       `json:"episode_count" example:"42"`
	LatestEpisode time.Time `json:"latest_episode"`
}

// SearchResult represents a text search match across sections
type SearchResult struct {
	EpisodeID    string  `json:"episode_id" example:"550e8400-e29b-41d4-a716-446655440000"`
	EpisodeTitle string  `json:"episode_title" example:"The Daily - Monday, April 7"`
	SectionIdx   int     `json:"section_idx" example:"2"`
	Snippet      string  `json:"snippet" example:"...match found in the transcript..."`
	Sentiment    string  `json:"sentiment" example:"neutral"`
	Score        float64 `json:"score" example:"0.95"`
}

// HealthStatus represents the health check response
type HealthStatus struct {
	Status   string `json:"status" example:"UP"`
	Database string `json:"database" example:"UP"`
	MinIO    string `json:"minio" example:"UP"`
}

// AudioURLResponse wraps a presigned URL
type AudioURLResponse struct {
	URL       string `json:"url" example:"https://minio:9000/bronze/audio/...?X-Amz-Signature=..."`
	ExpiresIn string `json:"expires_in" example:"1h"`
}
