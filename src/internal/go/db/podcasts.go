package db

import (
	"context"
	"fmt"
	"time"

	"github.com/georgysavva/scany/v2/pgxscan"
)

func (s *Store) CreatePipelineBatch(ctx context.Context, stage string, mode string) (string, error) {
	var id string
	query := `
		INSERT INTO pipeline_batches (stage, load_mode, status, start_ts, fin_ts)
		VALUES ($1, $2, 'pending', NOW(), NOW())
		RETURNING id`
	err := s.Pool.QueryRow(ctx, query, stage, mode).Scan(&id)
	return id, err
}

func (s *Store) CompletePipelineBatch(ctx context.Context, batchID string, status string) error {
	// 1. Update the technical batch ledger status
	query := `
		UPDATE pipeline_batches
		SET status = $1, fin_ts = NOW()
		WHERE id = $2`
	_, err := s.Pool.Exec(ctx, query, status, batchID)
	if err != nil {
		return fmt.Errorf("failed to update pipeline batch status: %w", err)
	}

	// 2. If ingestion succeeded, emit the event payload to pg_notify
	if status == "success" {
		payload := fmt.Sprintf(`{"batch_id": "%s"}`, batchID)

		// Using pg_notify function is safer and cleaner than raw string interpolation inside the NOTIFY statement
		_, err = s.Pool.Exec(ctx, "SELECT pg_notify('transcription_ready', $1)", payload)
		if err != nil {
			return fmt.Errorf("failed to emit pg_notify event: %w", err)
		}
		fmt.Printf("Broadcasted 'transcription_ready' event for batch: %s\n", batchID)
	}

	return nil
}

func (s *Store) InsertPodcast(
	ctx context.Context,
	guid string,
	persons *string,
	feedURL string,
	title string,
	description *string,
	episodeCount *int,
	categories []string,
	imageURL *string,
	publishedAt *time.Time,
	maxEpisodes *int,
) error {
	_, err := s.Pool.Exec(
		ctx,
		`
		INSERT INTO podcasts (
			guid,
			persons,
			feed_url,
			title,
			description,
			episode_count,
			categories,
			image_url,
			published_at,
			max_episodes
		)
		VALUES (
			$1, $2, $3, $4, $5,
			$6, $7, $8, $9, $10, $11
		)
		ON CONFLICT (feed_url) DO NOTHING
		`,
		guid,
		persons,
		feedURL,
		title,
		description,
		episodeCount,
		categories,
		imageURL,
		publishedAt,
		maxEpisodes,
	)

	return err
}

func (s *Store) GetPodcastsForIngestion(ctx context.Context, mode string) ([]Podcast, error) {
	var pp []Podcast
	var query string

	if mode == "full" {
		query = `SELECT id, guid, feed_url, title, ingested_at, updated_at, max_episodes FROM podcasts`
	} else {
		// Incremental: Include never-fetched podcasts OR where source update timestamp mismatches ingestion timestamp
		query = `
			SELECT id, guid, feed_url, title, ingested_at, updated_at, max_episodes 
			FROM podcasts 
			WHERE updated_at IS NULL OR updated_at != ingested_at`
	}

	err := pgxscan.Select(ctx, s.Pool, &pp, query)
	return pp, err
}

func (s *Store) UpdatePodcastMetadata(ctx context.Context, id string, guid string, title string, description string, batchID string) error {
	query := `
		UPDATE podcasts
		SET guid = $1, title = $2, description = $3, batch_id = $4, ingested_at = NOW()
		WHERE id = $5`
	_, err := s.Pool.Exec(ctx, query, guid, title, description, batchID, id)
	return err
}

func (s *Store) SetPodcastSourceUpdatedAt(ctx context.Context, id string) error {
	// Technical helper to simulate/write the last modified timestamp from the source feed boundary
	query := `UPDATE podcasts SET updated_at = NOW() WHERE id = $1`
	_, err := s.Pool.Exec(ctx, query, id)
	return err
}
