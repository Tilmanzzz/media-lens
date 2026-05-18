package db

import (
	"context"
	"fmt"
	"time"

	"github.com/georgysavva/scany/v2/pgxscan"
)

// pre-fetches all episodes for a podcast into a fast lookup map
func (s *Store) GetEpisodeMap(ctx context.Context, podcastID string) (map[string]Episode, error) {
	var episodes []Episode
	query := `SELECT id, podcast_id, guid, title, audio_key, published_at, enclosure_url, COALESCE(batch_id::text, '') as batch_id
	          FROM episodes WHERE podcast_id = $1`

	err := pgxscan.Select(ctx, s.Pool, &episodes, query, podcastID)
	if err != nil {
		return nil, err
	}

	epMap := make(map[string]Episode)
	for _, ep := range episodes {
		epMap[ep.GUID] = ep
	}
	return epMap, nil
}

// fetches a single episode by its primary key (UUID).
func (s *Store) GetEpisodeByID(ctx context.Context, id string) (Episode, error) {
	var ep Episode
	query := `SELECT id, podcast_id, guid, title, audio_key, status, published_at, enclosure_url 
	          FROM episodes WHERE id = $1`

	// fetches single row
	err := pgxscan.Get(ctx, s.Pool, &ep, query, id)
	if err != nil {
		return Episode{}, err
	}
	return ep, nil
}

func (s *Store) MarkPendingSectioning(ctx context.Context, id string) error {
	query := `
		UPDATE episodes
		SET status = 'pending_sectioning'
		WHERE id = $1
	`
	result, err := s.Pool.Exec(ctx, query, id)
	if err != nil {
		return fmt.Errorf("failed to update episode status: %w", err)
	}
	// check if the episode existed
	if result.RowsAffected() == 0 {
		return fmt.Errorf("no episode found with id: %s", id)
	}
	return nil
}

func (s *Store) MarkPendingTranscription(ctx context.Context, id string) error {
	query := `
		UPDATE episodes
		SET status = 'pending_transcription'
		WHERE id = $1
	`
	result, err := s.Pool.Exec(ctx, query, id)
	if err != nil {
		return fmt.Errorf("failed to update episode status: %w", err)
	}
	// check if the episode existed
	if result.RowsAffected() == 0 {
		return fmt.Errorf("no episode found with id: %s", id)
	}
	return nil
}

// sets the transcriptKey
func (s *Store) SetTranscriptKey(ctx context.Context, id string, transcriptKey string) error {
	query := `
		UPDATE episodes 
		SET transcript_key = $1
		WHERE id = $2`

	result, err := s.Pool.Exec(ctx, query, transcriptKey, id)
	if err != nil {
		return fmt.Errorf("failed to update episode status: %w", err)
	}

	// check if the episode existed
	if result.RowsAffected() == 0 {
		return fmt.Errorf("no episode found with id: %s", id)
	}

	return nil
}

func (s *Store) UpsertEpisode(ctx context.Context, ep Episode) (string, error) {
	query := `INSERT INTO episodes (podcast_id, guid, title, audio_key, published_at, enclosure_url, batch_id) 
	          VALUES ($1, $2, $3, $4, $5, $6, $7) 
	          ON CONFLICT (podcast_id, guid) DO UPDATE SET 
	          	title = EXCLUDED.title,
	          	audio_key = EXCLUDED.audio_key,
	          	published_at = EXCLUDED.published_at,
	          	enclosure_url = EXCLUDED.enclosure_url,
	          	batch_id = EXCLUDED.batch_id
		RETURNING id`

	var id string
	err := s.Pool.QueryRow(
		ctx,
		query,
		ep.PodcastID,
		ep.GUID,
		ep.Title,
		ep.AudioKey,
		ep.PublishedAt,
		ep.EnclosureURL,
		ep.BatchID,
	).Scan(&id)
	if err != nil {
		return "", fmt.Errorf("upsert failed: %w", err)
	}

	return id, nil
}

// executes a single batch operation to insert/update multiple episodes.
func (s *Store) BulkUpsertEpisodes(ctx context.Context, eps []Episode) ([]string, error) {
	if len(eps) == 0 {
		return nil, nil
	}

	// 1. Deconstruct the struct slice into parallel flat primitive arrays
	podcastIDs := make([]string, len(eps))
	guids := make([]string, len(eps))
	titles := make([]string, len(eps))
	audioKeys := make([]string, len(eps))
	publishedAts := make([]*time.Time, len(eps))
	enclosureURLs := make([]string, len(eps))
	batchIDs := make([]string, len(eps))

	for i, ep := range eps {
		podcastIDs[i] = ep.PodcastID
		guids[i] = ep.GUID
		titles[i] = ep.Title
		audioKeys[i] = ep.AudioKey
		publishedAts[i] = ep.PublishedAt
		enclosureURLs[i] = ep.EnclosureURL
		batchIDs[i] = ep.BatchID
	}

	// 2. Stream all values inside a single unnest matrix expression
	query := `
		INSERT INTO episodes (podcast_id, guid, title, audio_key, published_at, enclosure_url, batch_id) 
		SELECT * FROM unnest(
			$1::uuid[], 
			$2::text[], 
			$3::text[], 
			$4::text[], 
			$5::timestamptz[], 
			$6::text[], 
			$7::uuid[]
		)
		ON CONFLICT (podcast_id, guid) DO UPDATE SET 
			title = EXCLUDED.title,
			audio_key = EXCLUDED.audio_key,
			published_at = EXCLUDED.published_at,
			enclosure_url = EXCLUDED.enclosure_url,
			batch_id = EXCLUDED.batch_id
		RETURNING id`

	// 3. Collect the returning database UUIDs back into a simple string array via scany
	var ids []string
	err := pgxscan.Select(ctx, s.Pool, &ids, query,
		podcastIDs,
		guids,
		titles,
		audioKeys,
		publishedAts,
		enclosureURLs,
		batchIDs,
	)
	if err != nil {
		return nil, fmt.Errorf("bulk upsert failed: %w", err)
	}

	return ids, nil
}
