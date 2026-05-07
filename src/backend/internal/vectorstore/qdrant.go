package vectorstore

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"time"
)

type QdrantClient struct {
	baseURL    string
	collection string
	client     *http.Client
}

func NewQdrantClient(baseURL, collection string) *QdrantClient {
	return &QdrantClient{
		baseURL:    baseURL,
		collection: collection,
		client:     &http.Client{Timeout: 10 * time.Second},
	}
}

type EpisodeHit struct {
	EpisodeID    string  `json:"episode_id"`
	EpisodeTitle string  `json:"episode_title"`
	PodcastName  string  `json:"podcast_name"`
	CoverPath    string  `json:"cover_path"`
	Score        float64 `json:"score"`
}

type ChunkHit struct {
	EpisodeID string  `json:"episode_id"`
	Text      string  `json:"text"`
	StartTime int     `json:"start_time"`
	Score     float64 `json:"score"`
}

type searchRequest struct {
	Vector []float64     `json:"vector"`
	Filter *searchFilter `json:"filter,omitempty"`
	Limit  int           `json:"limit"`
	Params *searchParams `json:"params,omitempty"`
	With   bool          `json:"with_payload"`
	Score  *float64      `json:"score_threshold,omitempty"`
}

type searchFilter struct {
	Must []filterCondition `json:"must"`
}

type filterCondition struct {
	Key   string      `json:"key"`
	Match *matchValue `json:"match,omitempty"`
}

type matchValue struct {
	Value any `json:"value,omitempty"`
	Any   []string    `json:"any,omitempty"`
}

type searchParams struct {
	Exact bool `json:"exact"`
}

type searchResponse struct {
	Result []searchHit `json:"result"`
}

type searchHit struct {
	Score   float64                `json:"score"`
	Payload map[string]any `json:"payload"`
}

func (c *QdrantClient) SearchEpisodes(ctx context.Context, vector []float64, limit int, minScore float64) ([]EpisodeHit, error) {
	body := searchRequest{
		Vector: vector,
		Limit:  limit,
		With:   true,
		Filter: &searchFilter{
			Must: []filterCondition{
				{Key: "embedding_level", Match: &matchValue{Value: "episode"}},
			},
		},
	}
	if minScore > 0 {
		body.Score = &minScore
	}

	hits, err := c.doSearch(ctx, body)
	if err != nil {
		return nil, err
	}

	episodes := make([]EpisodeHit, 0, len(hits))
	for _, h := range hits {
		episodes = append(episodes, EpisodeHit{
			EpisodeID:    payloadString(h.Payload, "episode_id"),
			EpisodeTitle: payloadString(h.Payload, "episode_title"),
			PodcastName:  payloadString(h.Payload, "podcast_name"),
			CoverPath:    payloadString(h.Payload, "cover_path"),
			Score:        h.Score,
		})
	}
	return episodes, nil
}

func (c *QdrantClient) SearchChunks(ctx context.Context, vector []float64, episodeIDs []string, limit int, minScore float64) ([]ChunkHit, error) {
	body := searchRequest{
		Vector: vector,
		Limit:  limit,
		With:   true,
		Filter: &searchFilter{
			Must: []filterCondition{
				{Key: "embedding_level", Match: &matchValue{Value: "chunk"}},
				{Key: "episode_id", Match: &matchValue{Any: episodeIDs}},
			},
		},
	}
	if minScore > 0 {
		body.Score = &minScore
	}

	hits, err := c.doSearch(ctx, body)
	if err != nil {
		return nil, err
	}

	chunks := make([]ChunkHit, 0, len(hits))
	for _, h := range hits {
		chunks = append(chunks, ChunkHit{
			EpisodeID: payloadString(h.Payload, "episode_id"),
			Text:      payloadString(h.Payload, "text"),
			StartTime: payloadInt(h.Payload, "start_time"),
			Score:     h.Score,
		})
	}
	return chunks, nil
}

func (c *QdrantClient) HealthCheck(ctx context.Context) error {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, c.baseURL+"/healthz", nil)
	if err != nil {
		return err
	}
	resp, err := c.client.Do(req)
	if err != nil {
		return err
	}
	resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("qdrant health: status %d", resp.StatusCode)
	}
	return nil
}

func (c *QdrantClient) doSearch(ctx context.Context, body searchRequest) ([]searchHit, error) {
	payload, err := json.Marshal(body)
	if err != nil {
		return nil, fmt.Errorf("marshal search request: %w", err)
	}

	url := fmt.Sprintf("%s/collections/%s/points/search", c.baseURL, c.collection)
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, url, bytes.NewReader(payload))
	if err != nil {
		return nil, fmt.Errorf("create search request: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")

	resp, err := c.client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("qdrant search call: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("qdrant returned status %d", resp.StatusCode)
	}

	var result searchResponse
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return nil, fmt.Errorf("decode search response: %w", err)
	}

	return result.Result, nil
}

func payloadString(p map[string]any, key string) string {
	if v, ok := p[key]; ok {
		if s, ok := v.(string); ok {
			return s
		}
	}
	return ""
}

func payloadInt(p map[string]any, key string) int {
	if v, ok := p[key]; ok {
		switch n := v.(type) {
		case float64:
			return int(n)
		case int:
			return n
		}
	}
	return 0
}
