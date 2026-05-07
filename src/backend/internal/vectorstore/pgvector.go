package vectorstore

import (
	"context"
	"database/sql"
	"fmt"
	"strings"

	pgvector "github.com/pgvector/pgvector-go"
)

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

type PgVectorClient struct {
	db *sql.DB
}

func NewPgVectorClient(db *sql.DB) *PgVectorClient {
	return &PgVectorClient{db: db}
}

func (c *PgVectorClient) SearchEpisodes(ctx context.Context, vector []float64, limit int, minScore float64) ([]EpisodeHit, error) {
	vec := pgvector.NewVector(toFloat32(vector))

	rows, err := c.db.QueryContext(ctx, `
		SELECT episode_id, episode_title, podcast_name, cover_path,
		       1 - (embedding <=> $1::vector) AS score
		FROM embeddings
		WHERE embedding_level = 'episode'
		  AND 1 - (embedding <=> $1::vector) >= $2
		ORDER BY embedding <=> $1::vector
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
		if err := rows.Scan(&h.EpisodeID, &h.EpisodeTitle, &h.PodcastName, &h.CoverPath, &h.Score); err != nil {
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

	vec := pgvector.NewVector(toFloat32(vector))

	placeholders := make([]string, len(episodeIDs))
	args := []any{vec, minScore}
	for i, id := range episodeIDs {
		placeholders[i] = fmt.Sprintf("$%d", i+3)
		args = append(args, id)
	}
	args = append(args, limit)
	limitPlaceholder := fmt.Sprintf("$%d", len(args))

	query := fmt.Sprintf(`
		SELECT episode_id, text, start_time,
		       1 - (embedding <=> $1::vector) AS score
		FROM embeddings
		WHERE embedding_level = 'chunk'
		  AND episode_id::text IN (%s)
		  AND 1 - (embedding <=> $1::vector) >= $2
		ORDER BY embedding <=> $1::vector
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

func (c *PgVectorClient) HealthCheck(ctx context.Context) error {
	var result int
	err := c.db.QueryRowContext(ctx, "SELECT 1 FROM pg_extension WHERE extname = 'vector'").Scan(&result)
	if err != nil {
		return fmt.Errorf("pgvector health: %w", err)
	}
	return nil
}

func toFloat32(f64 []float64) []float32 {
	f32 := make([]float32, len(f64))
	for i, v := range f64 {
		f32[i] = float32(v)
	}
	return f32
}
