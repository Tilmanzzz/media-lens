package vectorstore

import (
	"context"
	"database/sql"
	"fmt"
	"strings"

	pgvector "github.com/pgvector/pgvector-go"
)

type EpisodeHit struct {
	EpisodeID       string  `json:"episode_id"`
	Title           string  `json:"title"`
	PodcastName     string  `json:"podcast_name"`
	CoverKey        string  `json:"cover_key"`
	PodcastImageURL string  `json:"-"`
	Score           float64 `json:"score"`
}

type ChunkHit struct {
	EpisodeID string  `json:"episode_id"`
	Text      string  `json:"text"`
	StartTime float64 `json:"start_time"`
	Score     float64 `json:"score"`
}

type PgVectorClient struct {
	db *sql.DB
}

func NewPgVectorClient(db *sql.DB) *PgVectorClient {
	return &PgVectorClient{db: db}
}

func (c *PgVectorClient) SearchEpisodes(ctx context.Context, vector []float64, limit int, minScore float64) ([]EpisodeHit, error) {
	vec := pgvector.NewHalfVector(toFloat32(vector))

	rows, err := c.db.QueryContext(ctx, `
		SELECT e.id, e.title, p.title, COALESCE(e.cover_key, ''),
		       COALESCE(p.image_url, ''),
		       1 - (emb.embedding <=> $1::halfvec) AS score
		FROM embeddings emb
		JOIN episodes e ON e.id = emb.episode_id
		JOIN podcasts p ON p.id = e.podcast_id
		WHERE emb.level = 'episode'
		  AND 1 - (emb.embedding <=> $1::halfvec) >= $2
		ORDER BY emb.embedding <=> $1::halfvec
		LIMIT $3`,
		vec, minScore, limit,
	)
	if err != nil {
		return nil, fmt.Errorf("search episodes: %w", err)
	}
	defer rows.Close()

	var episodes []EpisodeHit
	for rows.Next() {
		var h EpisodeHit
		if err := rows.Scan(&h.EpisodeID, &h.Title, &h.PodcastName, &h.CoverKey, &h.PodcastImageURL, &h.Score); err != nil {
			return nil, fmt.Errorf("scan episode hit: %w", err)
		}
		episodes = append(episodes, h)
	}
	return episodes, rows.Err()
}

func (c *PgVectorClient) SearchChunks(ctx context.Context, vector []float64, episodeIDs []string, limit int, minScore float64) ([]ChunkHit, error) {
	if len(episodeIDs) == 0 {
		return nil, nil
	}

	vec := pgvector.NewHalfVector(toFloat32(vector))

	placeholders := make([]string, len(episodeIDs))
	args := []any{vec, minScore}
	for i, id := range episodeIDs {
		placeholders[i] = fmt.Sprintf("$%d", i+3)
		args = append(args, id)
	}
	args = append(args, limit)
	limitPlaceholder := fmt.Sprintf("$%d", len(args))

	query := fmt.Sprintf(`
		SELECT ch.episode_id, COALESCE(ch.transcript, ''), ch.start_time,
		       1 - (emb.embedding <=> $1::halfvec) AS score
		FROM embeddings emb
		JOIN chapters ch ON ch.id = emb.chapter_id
		WHERE emb.level = 'chapter'
		  AND ch.episode_id IN (%s)
		  AND 1 - (emb.embedding <=> $1::halfvec) >= $2
		ORDER BY emb.embedding <=> $1::halfvec
		LIMIT %s`,
		strings.Join(placeholders, ","), limitPlaceholder,
	)

	rows, err := c.db.QueryContext(ctx, query, args...)
	if err != nil {
		return nil, fmt.Errorf("search chunks: %w", err)
	}
	defer rows.Close()

	var chunks []ChunkHit
	for rows.Next() {
		var ch ChunkHit
		if err := rows.Scan(&ch.EpisodeID, &ch.Text, &ch.StartTime, &ch.Score); err != nil {
			return nil, fmt.Errorf("scan chunk hit: %w", err)
		}
		chunks = append(chunks, ch)
	}
	return chunks, rows.Err()
}

func toFloat32(f64 []float64) []float32 {
	f32 := make([]float32, len(f64))
	for i, v := range f64 {
		f32[i] = float32(v)
	}
	return f32
}
