package queue

import (
	"context"
	"fmt"
	"time"

	"github.com/redis/go-redis/v9"
)

type Client struct {
	rdb *redis.Client
}

// NewClient initializes the Redis connection
func NewClient(addr string) (*Client, error) {
	rdb := redis.NewClient(&redis.Options{
		Addr: addr,
	})

	// Quick ping to ensure connectivity at startup
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	if err := rdb.Ping(ctx).Err(); err != nil {
		return nil, fmt.Errorf("failed to connect to redis: %w", err)
	}

	return &Client{rdb: rdb}, nil
}

// EnqueueTranscription adds an episode ID to the work queue (Ingestor uses this)
func (c *Client) EnqueueTranscription(ctx context.Context, episodeID string) error {
	return c.rdb.LPush(ctx, "transcription_tasks", episodeID).Err()
}

// DequeueTranscription waits for and retrieves an episode ID (Worker uses this)
// It blocks until a task is available.
func (c *Client) DequeueTranscription(ctx context.Context) (string, error) {
	// BRPOP returns [key_name, value]. We only want the value.
	// 0 means block indefinitely until a message arrives.
	results, err := c.rdb.BRPop(ctx, 0, "transcription_tasks").Result()
	if err != nil {
		return "", err
	}

	if len(results) < 2 {
		return "", fmt.Errorf("unexpected redis result format")
	}

	return results[1], nil
}
