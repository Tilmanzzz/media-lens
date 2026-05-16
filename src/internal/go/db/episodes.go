package db

import (
	"context"
	"fmt"

	"github.com/georgysavva/scany/v2/pgxscan"
)

// pre-fetches all episodes for a podcast into a fast lookup map
func (s *Store) GetEpisodeMap(ctx context.Context, podcastID string) (map[string]Episode, error) {
	var episodes []Episode
	query := `SELECT podcast_id, guid, title, audio_key, status, published_at, enclosure_url 
	          FROM episodes WHERE podcast_id = $1`

	err := pgxscan.Select(ctx, s.Pool, &episodes, query, podcastID)
	if err != nil {
		return nil, err
	}

	// Convert slice to a map keyed by GUID for instant O(1) lookups
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

// Inserts new episode or updates existing rows if the audio was re-downloaded
func (s *Store) UpsertEpisode(ctx context.Context, ep Episode) (string, error) {
	query := `INSERT INTO episodes (podcast_id, guid, title, audio_key, status, published_at, enclosure_url) 
	        VALUES ($1, $2, $3, $4, $5, $6, $7) 
	        ON CONFLICT (podcast_id, guid) DO UPDATE SET 
	        	title = EXCLUDED.title,
	        	audio_key = EXCLUDED.audio_key,
	        	status = EXCLUDED.status,
	        	published_at = EXCLUDED.published_at,
	        	enclosure_url = EXCLUDED.enclosure_url
		RETURNING ID`

	var id string
	err := s.Pool.QueryRow(
		ctx,
		query,
		ep.PodcastID,
		ep.GUID,
		ep.Title,
		ep.AudioKey,
		ep.Status,
		ep.PublishedAt,
		ep.EnclosureURL,
	).Scan(&id)
	if err != nil {
		return "", fmt.Errorf("upsert failed: %w", err)
	}

	return id, nil
}
