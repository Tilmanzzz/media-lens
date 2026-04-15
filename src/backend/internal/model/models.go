package model

import (
	"database/sql"
	"time"
)

// Episode maps to the episodes table
type Episode struct {
	ID              string       `json:"id" example:"550e8400-e29b-41d4-a716-446655440000"`
	Title           string       `json:"title" example:"The Daily - Monday, April 7"`
	PodcastID       string       `json:"podcast_id" example:"the-daily"`
	PodcastName     string       `json:"podcast_name" example:"The Daily"`
	PublishedAt     sql.NullTime `json:"published_at" swaggertype:"string" example:"2026-04-07T00:00:00Z"`
	DurationSeconds *int         `json:"duration_seconds,omitempty" example:"3738"`
	AudioPath       string       `json:"audio_path" example:"bronze/audio/abc/def/original.mp3"`
	XMLPath         string       `json:"xml_path" example:"bronze/podcasts/ep123.xml"`
	CoverPath       string       `json:"cover_path,omitempty" example:"bronze/covers/ep-421.jpg"`
	IngestedAt      time.Time    `json:"ingested_at"`
}

// --- API Contract Response Models ---

// EpisodeCard is displayed in the episode list
type EpisodeCard struct {
	ID              string `json:"id"`
	Title           string `json:"title" example:"KI & die Grenzen des Verstehens"`
	PodcastName     string `json:"podcast_name" example:"Lex Fridman Podcast"`
	DurationSeconds int    `json:"duration_seconds" example:"3738"`
	PublishedAt     string `json:"published_at" example:"2024-03-15"`
	CoverURL        string `json:"cover_url" example:"https://minio.audiolens.dev/covers/ep-421.jpg"`
}

// EpisodeListResponse is the paginated list of episodes
type EpisodeListResponse struct {
	Items      []EpisodeCard `json:"items"`
	NextCursor *string       `json:"next_cursor"`
	Total      int           `json:"total"`
}

// EpisodeDetail is the detail view above the tabs
type EpisodeDetail struct {
	ID              string `json:"id"`
	Title           string `json:"title"`
	PodcastName     string `json:"podcast_name"`
	DurationSeconds int    `json:"duration_seconds"`
	PublishedAt     string `json:"published_at"`
	CoverURL        string `json:"cover_url"`
}

// EpisodeDetailResponse wraps EpisodeDetail
type EpisodeDetailResponse struct {
	Episode EpisodeDetail `json:"episode"`
}

// TopicCard represents a topic segment
type TopicCard struct {
	ID        string `json:"id"`
	Topic     string `json:"topic" example:"KI & Bewusstsein"`
	StartTime int    `json:"start_time" example:"724"`
	Emotion   string `json:"emotion" example:"neutral"`
	Summary   string `json:"summary" example:"Diskussion über die philosophischen Grenzen von LLMs."`
}

// TopicsResponse wraps the topics list
type TopicsResponse struct {
	EpisodeID string      `json:"episode_id"`
	Topics    []TopicCard `json:"topics"`
}

// TranscriptLine is a single line in the transcript
type TranscriptLine struct {
	ID          string `json:"id"`
	StartTime   int    `json:"start_time" example:"724"`
	Text        string `json:"text" example:"Wann hört Simulation auf und beginnt echtes Verständnis?"`
	HasFactFlag bool   `json:"has_fact_flag"`
}

// TranscriptResponse wraps the transcript lines
type TranscriptResponse struct {
	EpisodeID string           `json:"episode_id"`
	Lines     []TranscriptLine `json:"lines"`
}

// FactCheckClaim is a fact-check entry in the sidebar
type FactCheckClaim struct {
	ID          string   `json:"id"`
	StartTime   int      `json:"start_time" example:"1110"`
	Claim       string   `json:"claim" example:"KI-Systeme ersetzen bis 2025 über 80% aller Bürojobs."`
	Verdict     string   `json:"verdict" example:"FALSE"`
	Explanation string   `json:"explanation" example:"Diese These ist durch aktuelle Studien nicht belegt."`
	Sources     []string `json:"sources"`
}

// FactChecksResponse wraps the fact-check claims
type FactChecksResponse struct {
	EpisodeID string           `json:"episode_id"`
	Claims    []FactCheckClaim `json:"claims"`
}

// CreateConversationRequest starts a new chat session
type CreateConversationRequest struct {
	EpisodeID string `json:"episode_id" binding:"required,uuid"`
}

// CreateConversationResponse returns the new conversation ID
type CreateConversationResponse struct {
	ConversationID string `json:"conversation_id"`
}

// SendMessageRequest contains the user's chat message
type SendMessageRequest struct {
	Text    string              `json:"text" binding:"required"`
	Context *SendMessageContext `json:"context,omitempty"`
}

// SendMessageContext provides optional playback context
type SendMessageContext struct {
	CurrentTime *int `json:"current_time,omitempty"`
}

// ChatStreamChunk is a single line in the NDJSON stream
type ChatStreamChunk struct {
	Type    string `json:"type"`
	Delta   string `json:"delta,omitempty"`
	Message string `json:"message,omitempty"`
}

// SSEPositionEvent is pushed on segment changes
type SSEPositionEvent struct {
	CurrentTime            int     `json:"current_time" example:"724"`
	ActiveTranscriptLineID string  `json:"active_transcript_line_id"`
	ProgressPercent        float64 `json:"progress_percent" example:"19.3"`
}

// SSEAnalysisReadyEvent is pushed when analysis completes
type SSEAnalysisReadyEvent struct {
	EpisodeID string `json:"episode_id"`
}

// ApiError is the standardized error response
type ApiError struct {
	Error   string `json:"error" example:"episode_not_found"`
	Message string `json:"message" example:"Episode mit dieser ID existiert nicht."`
	Status  int    `json:"status" example:"404"`
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

// EpisodeWithSections is a composite response (legacy)
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
