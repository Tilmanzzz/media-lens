package queue

import (
	"context"
	"fmt"
	"strings"
	"time"

	"github.com/redis/go-redis/v9"
)

const (
	TranscriptionStream = "transcription_stream"
	TranscriptionGroup  = "transcription_workers"

	SectioningStream = "sectioning_stream"
	SectioningGroup  = "sectioning_workers"
)

type Client struct {
	rdb *redis.Client
}

// NewClient initializes Redis and ensures both consumer groups exist.
func NewClient(addr string) (*Client, error) {
	rdb := redis.NewClient(&redis.Options{
		Addr: addr,
	})

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	if err := rdb.Ping(ctx).Err(); err != nil {
		return nil, fmt.Errorf("failed to connect to redis: %w", err)
	}

	// Initialize Transcription Group
	err := rdb.XGroupCreateMkStream(ctx, TranscriptionStream, TranscriptionGroup, "0").Err()
	if err != nil && !strings.Contains(err.Error(), "BUSYGROUP") {
		return nil, fmt.Errorf("failed to create transcription group: %w", err)
	}

	// Initialize Sectioning Group
	err = rdb.XGroupCreateMkStream(ctx, SectioningStream, SectioningGroup, "0").Err()
	if err != nil && !strings.Contains(err.Error(), "BUSYGROUP") {
		return nil, fmt.Errorf("failed to create sectioning group: %w", err)
	}

	return &Client{rdb: rdb}, nil
}

// ==========================================
// TRANSCRIPTION QUEUE METHODS
// ==========================================

func (c *Client) EnqueueTranscription(ctx context.Context, episodeID string) error {
	args := &redis.XAddArgs{
		Stream: TranscriptionStream,
		Values: map[string]interface{}{"episode_id": episodeID},
	}
	return c.rdb.XAdd(ctx, args).Err()
}

func (c *Client) DequeueTranscription(ctx context.Context, consumerID string) (string, string, error) {
	return c.dequeue(ctx, TranscriptionStream, TranscriptionGroup, consumerID)
}

func (c *Client) AckTranscription(ctx context.Context, messageID string) error {
	return c.rdb.XAck(ctx, TranscriptionStream, TranscriptionGroup, messageID).Err()
}

// ==========================================
// SECTIONING QUEUE METHODS
// ==========================================

func (c *Client) EnqueueSectioning(ctx context.Context, episodeID string) error {
	args := &redis.XAddArgs{
		Stream: SectioningStream,
		Values: map[string]interface{}{"episode_id": episodeID},
	}
	return c.rdb.XAdd(ctx, args).Err()
}

func (c *Client) DequeueSectioning(ctx context.Context, consumerID string) (string, string, error) {
	return c.dequeue(ctx, SectioningStream, SectioningGroup, consumerID)
}

func (c *Client) AckSectioning(ctx context.Context, messageID string) error {
	return c.rdb.XAck(ctx, SectioningStream, SectioningGroup, messageID).Err()
}

// ==========================================
// INTERNAL HELPER
// ==========================================

// dequeue abstracts the XReadGroup logic to prevent code duplication
func (c *Client) dequeue(ctx context.Context, stream, group, consumerID string) (string, string, error) {
	args := &redis.XReadGroupArgs{
		Group:    group,
		Consumer: consumerID,
		Streams:  []string{stream, ">"},
		Count:    1,
		Block:    0,
	}

	results, err := c.rdb.XReadGroup(ctx, args).Result()
	if err != nil {
		return "", "", fmt.Errorf("xreadgroup error on %s: %w", stream, err)
	}

	if len(results) == 0 || len(results[0].Messages) == 0 {
		return "", "", fmt.Errorf("no messages returned")
	}

	msg := results[0].Messages[0]
	messageID := msg.ID

	episodeID, ok := msg.Values["episode_id"].(string)
	if !ok {
		return messageID, "", fmt.Errorf("episode_id not found or invalid in message")
	}

	return messageID, episodeID, nil
}
