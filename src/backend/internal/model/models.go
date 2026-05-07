package model

import (
	"database/sql"
	"time"
)

// Episode maps to the episodes table (internal DB model).
type Episode struct {
	ID              string       `json:"id"`
	Title           string       `json:"title"`
	PodcastID       string       `json:"podcast_id"`
	PodcastName     string       `json:"podcast_name"`
	PublishedAt     sql.NullTime `json:"published_at" swaggertype:"string"`
	DurationSeconds *int         `json:"duration_seconds,omitempty"`
	AudioPath       string       `json:"audio_path"`
	XMLPath         string       `json:"xml_path"`
	CoverPath       string       `json:"cover_path,omitempty"`
	IngestedAt      time.Time    `json:"ingested_at"`
}

// --- API Contract Response Models ---

// EpisodeCard is displayed in the episode list.
type EpisodeCard struct {
	ID              string `json:"id"`
	Title           string `json:"title"`
	PodcastName     string `json:"podcast_name"`
	DurationSeconds int    `json:"duration_seconds"`
	PublishedAt     string `json:"published_at"`
	CoverURL        string `json:"cover_url"`
}

// EpisodeListResponse is the paginated list of episodes.
type EpisodeListResponse struct {
	Items      []EpisodeCard `json:"items"`
	NextCursor *string       `json:"next_cursor"`
	Total      int           `json:"total"`
}

// EpisodeDetail is the detail view above the tabs.
type EpisodeDetail struct {
	ID              string `json:"id"`
	Title           string `json:"title"`
	PodcastName     string `json:"podcast_name"`
	DurationSeconds int    `json:"duration_seconds"`
	PublishedAt     string `json:"published_at"`
	CoverURL        string `json:"cover_url"`
}

// EpisodeDetailResponse wraps EpisodeDetail.
type EpisodeDetailResponse struct {
	Episode EpisodeDetail `json:"episode"`
}

// TopicCard represents a topic segment.
type TopicCard struct {
	ID        string `json:"id"`
	Topic     string `json:"topic"`
	StartTime int    `json:"start_time"`
	Emotion   string `json:"emotion"`
	Summary   string `json:"summary"`
}

// TopicsResponse wraps the topics list.
type TopicsResponse struct {
	EpisodeID string      `json:"episode_id"`
	Topics    []TopicCard `json:"topics"`
}

// TranscriptLine is a single line in the transcript.
type TranscriptLine struct {
	ID          string `json:"id"`
	StartTime   int    `json:"start_time"`
	Text        string `json:"text"`
	HasFactFlag bool   `json:"has_fact_flag"`
}

// TranscriptResponse wraps the transcript lines.
type TranscriptResponse struct {
	EpisodeID string           `json:"episode_id"`
	Lines     []TranscriptLine `json:"lines"`
}

// FactCheckClaim is a fact-check entry in the sidebar.
type FactCheckClaim struct {
	ID          string   `json:"id"`
	StartTime   int      `json:"start_time"`
	Claim       string   `json:"claim"`
	Verdict     string   `json:"verdict"`
	Explanation string   `json:"explanation"`
	Sources     []string `json:"sources"`
}

// FactChecksResponse wraps the fact-check claims.
type FactChecksResponse struct {
	EpisodeID string           `json:"episode_id"`
	Claims    []FactCheckClaim `json:"claims"`
}

// CreateConversationRequest starts a new chat session.
type CreateConversationRequest struct {
	EpisodeID string `json:"episode_id" binding:"required,uuid"`
}

// CreateConversationResponse returns the new conversation ID.
type CreateConversationResponse struct {
	ConversationID string `json:"conversation_id"`
}

// SendMessageRequest contains the user's chat message.
type SendMessageRequest struct {
	Text    string              `json:"text" binding:"required,max=10000"`
	Context *SendMessageContext `json:"context,omitempty"`
}

// SendMessageContext provides optional playback context.
type SendMessageContext struct {
	CurrentTime *int `json:"current_time,omitempty"`
}

// ChatStreamChunk is a single line in the NDJSON stream.
type ChatStreamChunk struct {
	Type    string `json:"type"`
	Delta   string `json:"delta,omitempty"`
	Message string `json:"message,omitempty"`
}

// SSEPositionEvent is pushed on segment changes.
type SSEPositionEvent struct {
	CurrentTime            int     `json:"current_time"`
	ActiveTranscriptLineID string  `json:"active_transcript_line_id"`
	ProgressPercent        float64 `json:"progress_percent"`
}

// SSEAnalysisReadyEvent is pushed when analysis completes.
type SSEAnalysisReadyEvent struct {
	EpisodeID string `json:"episode_id"`
}

// SearchHighlight is a matching transcript chunk.
type SearchHighlight struct {
	Text      string  `json:"text"`
	StartTime int     `json:"start_time"`
	Score     float64 `json:"score"`
}

// SearchResultItem is a single episode match.
type SearchResultItem struct {
	EpisodeID   string            `json:"episode_id"`
	Title       string            `json:"title"`
	PodcastName string            `json:"podcast_name"`
	CoverURL    string            `json:"cover_url"`
	Score       float64           `json:"score"`
	Highlights  []SearchHighlight `json:"highlights"`
}

// SearchResponse wraps semantic search results.
type SearchResponse struct {
	Query string             `json:"query"`
	Items []SearchResultItem `json:"items"`
	Total int                `json:"total"`
}

// ApiError is the standardized error response.
type ApiError struct {
	Error   string `json:"error"`
	Message string `json:"message"`
	Status  int    `json:"status"`
}

// HealthStatus represents the health check response.
type HealthStatus struct {
	Status   string `json:"status"`
	Database string `json:"database"`
	MinIO    string `json:"minio"`
	Qdrant   string `json:"qdrant"`
	Ollama   string `json:"ollama"`
}
