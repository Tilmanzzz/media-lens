package model

import "time"

// Podcast represents a podcast series
type Podcast struct {
	ID          string    `json:"id" example:"p1"`
	Title       string    `json:"title" example:"The Go Programming Podcast"`
	Description string    `json:"description" example:"A podcast about the Go programming language."`
	RSSURL      string    `json:"rss_url" example:"https://example.com/rss"`
	CreatedAt   time.Time `json:"created_at"`
}

// Episode represents a single episode of a podcast
type Episode struct {
	ID          string    `json:"id" example:"e1"`
	PodcastID   string    `json:"podcast_id" example:"p1"`
	Title       string    `json:"title" example:"Introduction to Gin"`
	PublishedAt time.Time `json:"published_at"`
	Status      string    `json:"status" example:"transcribed" enums:"pending,downloading,transcribing,transcribed,failed"`
	Transcript  string    `json:"transcript,omitempty"`
}

// SearchResult represents a match in the transcripts
type SearchResult struct {
	EpisodeID string  `json:"episode_id" example:"e1"`
	Snippet   string  `json:"snippet" example:"...and that's how you use Gin for routing..."`
	Score     float64 `json:"score" example:"0.95"`
}
