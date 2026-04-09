package repository

import (
	"context"
	"database/sql"
	"fmt"

	"github.com/lib/pq"
	"media-lens/backend/internal/model"
)

type EpisodeRepository interface {
	ListAll(ctx context.Context) ([]model.Episode, error)
	GetByID(ctx context.Context, id string) (*model.Episode, error)
	ListByPodcastID(ctx context.Context, podcastID string) ([]model.Episode, error)
	ListDistinctPodcasts(ctx context.Context) ([]model.PodcastSummary, error)
}

type postgresEpisodeRepo struct {
	db *sql.DB
}

func NewEpisodeRepository(db *sql.DB) EpisodeRepository {
	return &postgresEpisodeRepo{db: db}
}

func (r *postgresEpisodeRepo) ListAll(ctx context.Context) ([]model.Episode, error) {
	rows, err := r.db.QueryContext(ctx, `
		SELECT id, title, COALESCE(podcast_id, ''), published_at, 
		       COALESCE(audio_path, ''), COALESCE(xml_path, ''), ingested_at
		FROM episodes
		ORDER BY ingested_at DESC
	`)
	if err != nil {
		return nil, fmt.Errorf("query episodes: %w", err)
	}
	defer rows.Close()

	return scanEpisodes(rows)
}

func (r *postgresEpisodeRepo) GetByID(ctx context.Context, id string) (*model.Episode, error) {
	row := r.db.QueryRowContext(ctx, `
		SELECT id, title, COALESCE(podcast_id, ''), published_at,
		       COALESCE(audio_path, ''), COALESCE(xml_path, ''), ingested_at
		FROM episodes
		WHERE id = $1
	`, id)

	var ep model.Episode
	err := row.Scan(&ep.ID, &ep.Title, &ep.PodcastID, &ep.PublishedAt,
		&ep.AudioPath, &ep.XMLPath, &ep.IngestedAt)
	if err == sql.ErrNoRows {
		return nil, nil
	}
	if err != nil {
		return nil, fmt.Errorf("scan episode: %w", err)
	}
	return &ep, nil
}

func (r *postgresEpisodeRepo) ListByPodcastID(ctx context.Context, podcastID string) ([]model.Episode, error) {
	rows, err := r.db.QueryContext(ctx, `
		SELECT id, title, COALESCE(podcast_id, ''), published_at,
		       COALESCE(audio_path, ''), COALESCE(xml_path, ''), ingested_at
		FROM episodes
		WHERE podcast_id = $1
		ORDER BY ingested_at DESC
	`, podcastID)
	if err != nil {
		return nil, fmt.Errorf("query episodes by podcast_id: %w", err)
	}
	defer rows.Close()

	return scanEpisodes(rows)
}

func (r *postgresEpisodeRepo) ListDistinctPodcasts(ctx context.Context) ([]model.PodcastSummary, error) {
	rows, err := r.db.QueryContext(ctx, `
		SELECT COALESCE(podcast_id, 'unknown'), COUNT(*), MAX(ingested_at)
		FROM episodes
		GROUP BY podcast_id
		ORDER BY MAX(ingested_at) DESC
	`)
	if err != nil {
		return nil, fmt.Errorf("query distinct podcasts: %w", err)
	}
	defer rows.Close()

	var summaries []model.PodcastSummary
	for rows.Next() {
		var s model.PodcastSummary
		if err := rows.Scan(&s.PodcastID, &s.EpisodeCount, &s.LatestEpisode); err != nil {
			return nil, fmt.Errorf("scan podcast summary: %w", err)
		}
		summaries = append(summaries, s)
	}
	return summaries, rows.Err()
}

func scanEpisodes(rows *sql.Rows) ([]model.Episode, error) {
	var episodes []model.Episode
	for rows.Next() {
		var ep model.Episode
		if err := rows.Scan(&ep.ID, &ep.Title, &ep.PodcastID, &ep.PublishedAt,
			&ep.AudioPath, &ep.XMLPath, &ep.IngestedAt); err != nil {
			return nil, fmt.Errorf("scan episode row: %w", err)
		}
		episodes = append(episodes, ep)
	}
	return episodes, rows.Err()
}

// SectionRepository

type SectionRepository interface {
	ListByEpisodeID(ctx context.Context, episodeID string) ([]model.PodcastSection, error)
	SearchText(ctx context.Context, query string, limit int) ([]model.SearchResult, error)
}

type postgresSectionRepo struct {
	db *sql.DB
}

func NewSectionRepository(db *sql.DB) SectionRepository {
	return &postgresSectionRepo{db: db}
}

func (r *postgresSectionRepo) ListByEpisodeID(ctx context.Context, episodeID string) ([]model.PodcastSection, error) {
	rows, err := r.db.QueryContext(ctx, `
		SELECT id, episode_id, section_idx, COALESCE(text, ''),
		       COALESCE(sentiment, ''), COALESCE(sentiment_score, 0),
		       COALESCE(topics, '{}'), processed_at
		FROM podcast_sections
		WHERE episode_id = $1
		ORDER BY section_idx ASC
	`, episodeID)
	if err != nil {
		return nil, fmt.Errorf("query sections: %w", err)
	}
	defer rows.Close()

	var sections []model.PodcastSection
	for rows.Next() {
		var s model.PodcastSection
		if err := rows.Scan(&s.ID, &s.EpisodeID, &s.SectionIdx, &s.Text,
			&s.Sentiment, &s.SentimentScore,
			pq.Array(&s.Topics), &s.ProcessedAt); err != nil {
			return nil, fmt.Errorf("scan section row: %w", err)
		}
		sections = append(sections, s)
	}
	return sections, rows.Err()
}

func (r *postgresSectionRepo) SearchText(ctx context.Context, query string, limit int) ([]model.SearchResult, error) {
	if limit <= 0 || limit > 100 {
		limit = 20
	}

	rows, err := r.db.QueryContext(ctx, `
		SELECT s.episode_id, e.title, s.section_idx, s.text, 
		       COALESCE(s.sentiment, ''), 1.0 as score
		FROM podcast_sections s
		JOIN episodes e ON e.id = s.episode_id
		WHERE s.text ILIKE '%' || $1 || '%'
		ORDER BY s.processed_at DESC
		LIMIT $2
	`, query, limit)
	if err != nil {
		return nil, fmt.Errorf("search sections: %w", err)
	}
	defer rows.Close()

	var results []model.SearchResult
	for rows.Next() {
		var r model.SearchResult
		if err := rows.Scan(&r.EpisodeID, &r.EpisodeTitle, &r.SectionIdx,
			&r.Snippet, &r.Sentiment, &r.Score); err != nil {
			return nil, fmt.Errorf("scan search result: %w", err)
		}
		results = append(results, r)
	}
	return results, rows.Err()
}
