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
	query := `
		UPDATE pipeline_batches
		SET status = $1, fin_ts = NOW()
		WHERE id = $2`
	_, err := s.Pool.Exec(ctx, query, status, batchID)
	if err != nil {
		return fmt.Errorf("failed to update pipeline batch status: %w", err)
	}

	if status == "success" {
		payload := fmt.Sprintf(`{"batch_id": "%s"}`, batchID)
		_, err = s.Pool.Exec(ctx, "SELECT pg_notify('transcription_ready', $1)", payload)
		if err != nil {
			return fmt.Errorf("failed to emit pg_notify event: %w", err)
		}
		fmt.Printf("Broadcasted 'transcription_ready' event for batch: %s\n", batchID)
	}

	return nil
}

func (s *Store) StopPreviousBatchIfNeeded(ctx context.Context, batchID string) error {
	query := `
		UPDATE pipeline_batches
		SET status = 'stopped'
		WHERE id = $1
		  AND NOT (
		      (stage = 'processing' AND status = 'success')
		      OR status IN ('failed', 'stopped', 'consumed')
		  )`
	_, err := s.Pool.Exec(ctx, query, batchID)
	return err
}

func (s *Store) InsertPodcast(
	ctx context.Context,
	guid string,
	hosts *string,
	feedURL string,
	title string,
	description *string,
	episodeCount *int,
	categories []string,
	imageURL *string,
	publishedAt *time.Time,
	maxEpisodes *int,
	sourceSystemUpdatedAt *time.Time,
) error {
	_, err := s.Pool.Exec(
		ctx,
		`
		INSERT INTO podcasts (
			guid,
			hosts,
			feed_url,
			title,
			description,
			episode_count,
			categories,
			image_url,
			published_at,
			max_episodes,
			source_system_updated_at
		)
		VALUES (
			$1, $2, $3, $4, $5,
			$6, $7, $8, $9, $10, $11
		)
		ON CONFLICT (feed_url) DO NOTHING
		`,
		guid, hosts, feedURL, title, description,
		episodeCount, categories, imageURL, publishedAt, maxEpisodes, sourceSystemUpdatedAt,
	)
	return err
}

func (s *Store) GetPodcastsForIngestion(ctx context.Context, mode string) ([]Podcast, error) {
	var pp []Podcast
	var query string

	if mode == "full" {
		query = `SELECT id, guid, feed_url, title, source_system_updated_at, max_episodes FROM podcasts`
	} else {
		query = `
			SELECT id, guid, feed_url, title, source_system_updated_at, max_episodes 
			FROM podcasts 
			WHERE ingested_at IS NULL OR source_system_updated_at > ingested_at`
	}

	err := pgxscan.Select(ctx, s.Pool, &pp, query)
	return pp, err
}

// SyncPodcastMetadata is used by the Metadata module (Insertion) to overwrite show-level data
func (s *Store) SyncPodcastMetadata(
	ctx context.Context,
	id, guid, title, description, hosts string,
	sourceSystemUpdatedAt *time.Time,
) error {
	query := `
		UPDATE podcasts
		SET guid = $2,
		    title = $3,
		    description = $4,
		    hosts = $5, 
		    source_system_updated_at = $6
		WHERE id = $1::uuid`

	_, err := s.Pool.Exec(ctx, query, id, guid, title, description, hosts, sourceSystemUpdatedAt)
	return err
}

// MarkPodcastIngested is used by the Ingestion worker to track pipeline batches
func (s *Store) MarkPodcastIngested(ctx context.Context, id string, batchID string) error {
	query := `
		UPDATE podcasts
		SET batch_id = $2::uuid,
		    ingested_at = NOW()
		WHERE id = $1::uuid`

	_, err := s.Pool.Exec(ctx, query, id, batchID)
	return err
}
