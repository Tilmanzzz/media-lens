package db

import (
	"context"

	"github.com/georgysavva/scany/v2/pgxscan"
)

func (s *Store) GetUnfetchedPodcasts(ctx context.Context) ([]Podcast, error) {
	var pp []Podcast
	err := pgxscan.Select(ctx, s.Pool, &pp, `SELECT id, feed_url, max_episodes FROM podcasts WHERE last_fetched_at IS NULL`)
	return pp, err
}

func (s *Store) InsertPodcast(ctx context.Context, url string, max_episodes int) error {
	_, err := s.Pool.Exec(ctx, "INSERT INTO podcasts (feed_url, max_episodes) VALUES ($1, $2) ON CONFLICT DO NOTHING", url, max_episodes)
	return err
}

func (s *Store) MarkPodcastFetched(ctx context.Context, id string) error {
	_, err := s.Pool.Exec(ctx, "UPDATE podcasts SET last_fetched_at = NOW() WHERE id = $1", id)
	return err
}
