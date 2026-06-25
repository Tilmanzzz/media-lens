package model

import (
	"database/sql"
	"time"
)

type Episode struct {
	ID                 string       `json:"id"`
	Title              string       `json:"title"`
	PodcastID          string       `json:"podcast_id"`
	PodcastName        string       `json:"podcast_name"`
	PublishedAt        sql.NullTime `json:"published_at" swaggertype:"string"`
	DurationSeconds    *int         `json:"duration_seconds,omitempty"`
	AudioKey           string       `json:"audio_key"`
	CoverKey           string       `json:"cover_key,omitempty"`
	Summary            string       `json:"summary,omitempty"`
	IngestedAt         time.Time    `json:"ingested_at"`
	PodcastImageURL    string       `json:"-"`
	ProcessingComplete bool         `json:"processing_complete"`
}

type EpisodeCard struct {
	ID                 string `json:"id"`
	Title              string `json:"title"`
	PodcastName        string `json:"podcast_name"`
	DurationSeconds    int    `json:"duration_seconds"`
	PublishedAt        string `json:"published_at"`
	CoverURL           string `json:"cover_url"`
	Summary            string `json:"summary"`
	ProcessingComplete bool   `json:"processing_complete"`
}

type EpisodeListResponse struct {
	Items      []EpisodeCard `json:"items"`
	NextCursor *string       `json:"next_cursor"`
	Total      int           `json:"total"`
}

type EpisodeDetail struct {
	ID                 string `json:"id"`
	Title              string `json:"title"`
	PodcastName        string `json:"podcast_name"`
	DurationSeconds    int    `json:"duration_seconds"`
	PublishedAt        string `json:"published_at"`
	CoverURL           string `json:"cover_url"`
	AudioURL           string `json:"audio_url,omitempty"`
	Summary            string `json:"summary"`
	ProcessingComplete bool   `json:"processing_complete"`
}

type EpisodeDetailResponse struct {
	Episode EpisodeDetail `json:"episode"`
}

type ChapterCard struct {
	ID         string  `json:"id"`
	ChapterIdx int     `json:"chapter_idx"`
	Title      string  `json:"title"`
	Summary    string  `json:"summary"`
	StartTime  float64 `json:"start_time"`
	EndTime    float64 `json:"end_time"`
}

type ChaptersResponse struct {
	EpisodeID string        `json:"episode_id"`
	Chapters  []ChapterCard `json:"chapters"`
}

type TranscriptLine struct {
	ID           string  `json:"id"`
	ChapterID    string  `json:"chapter_id"`
	StartTime    float64 `json:"start_time"`
	EndTime      float64 `json:"end_time"`
	Text         string  `json:"text"`
	Emotion      string  `json:"emotion"`
	EmotionScore float64 `json:"emotion_score"`
	HasFactFlag  bool    `json:"has_fact_flag"`
}

type TranscriptResponse struct {
	EpisodeID string           `json:"episode_id"`
	Lines     []TranscriptLine `json:"lines"`
}

type FactCheckClaim struct {
	ID          string   `json:"id"`
	ChapterID   string   `json:"chapter_id"`
	ClaimIdx    int      `json:"claim_idx"`
	Claim       string   `json:"claim"`
	Verdict     string   `json:"verdict"`
	Explanation string   `json:"explanation"`
	Sources     []string `json:"sources"`
}

type FactChecksResponse struct {
	EpisodeID string           `json:"episode_id"`
	Claims    []FactCheckClaim `json:"claims"`
}

type ChatRequest struct {
	Question string `json:"question" binding:"required,max=10000"`
}

type ChatResponse struct {
	Answer string `json:"answer"`
}

type SSEPositionEvent struct {
	CurrentTime            int     `json:"current_time"`
	ActiveTranscriptLineID string  `json:"active_transcript_line_id"`
	ProgressPercent        float64 `json:"progress_percent"`
}

type SSEAnalysisReadyEvent struct {
	EpisodeID string `json:"episode_id"`
}

type SearchHighlight struct {
	Text      string  `json:"text"`
	StartTime float64 `json:"start_time"`
	Score     float64 `json:"score"`
}

type SearchResultItem struct {
	EpisodeID   string            `json:"episode_id"`
	Title       string            `json:"title"`
	PodcastName string            `json:"podcast_name"`
	CoverURL    string            `json:"cover_url"`
	Score       float64           `json:"score"`
	Highlights  []SearchHighlight `json:"highlights"`
}

type SearchResponse struct {
	Query string             `json:"query"`
	Items []SearchResultItem `json:"items"`
	Total int                `json:"total"`
}

type ApiError struct {
	Error   string `json:"error"`
	Message string `json:"message"`
	Status  int    `json:"status"`
}

type HealthStatus struct {
	Status   string `json:"status"`
	Database string `json:"database"`
	MinIO    string `json:"minio"`
	Ollama   string `json:"ollama"`
}
