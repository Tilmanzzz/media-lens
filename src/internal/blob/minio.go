package blob

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"strings"
	"time"

	"github.com/minio/minio-go/v7"
	"github.com/minio/minio-go/v7/pkg/credentials"
)

// Bucket wraps the MinIO client and a specific bucket name.
type Bucket struct {
	client *minio.Client
	name   string
}

// initializes the MinIO client and ensures the target bucket exists.
func NewBucket(endpoint, user, pass, name string) (*Bucket, error) {
	client, err := minio.New(endpoint, &minio.Options{
		Creds:  credentials.NewStaticV4(user, pass, ""),
		Secure: false, // Set to true if using HTTPS/Production
	})
	if err != nil {
		return nil, fmt.Errorf("failed to create minio client: %w", err)
	}

	// check if bucket exists/create it
	ctx := context.Background()
	exists, err := client.BucketExists(ctx, name)
	if err != nil {
		return nil, fmt.Errorf("failed to check bucket existence: %w", err)
	}
	if !exists {
		err = client.MakeBucket(ctx, name, minio.MakeBucketOptions{})
		if err != nil {
			return nil, fmt.Errorf("failed to create bucket %s: %w", name, err)
		}
	}

	return &Bucket{
		client: client,
		name:   name,
	}, nil
}

// UploadAudio streams an audio file to MinIO with date-based partitioning.
func (b *Bucket) UploadAudio(
	ctx context.Context,
	podcastID string,
	episodeGUID string,
	contentType string,
	body io.Reader,
	size int64,
	sourceURL string,
) (string, error) {
	// determine extension
	ext := extensionFromContentType(contentType)

	// generate date partitions (YYYY/MM/DD)
	now := time.Now().UTC()
	datePart := now.Format("2006/01/02") // Go's weird but helpful date formatting

	// construct the partitioned path
	// structure: audio/YYYY/MM/DD/podcastID/episodeGUID/original.mp3
	objectKey := fmt.Sprintf("audio/%s/%s/%s/original%s",
		datePart,
		podcastID,
		episodeGUID,
		ext,
	)

	// prepare metadata
	opts := minio.PutObjectOptions{
		ContentType: contentType,
		UserMetadata: map[string]string{
			"source-url":   sourceURL,
			"fetched-at":   now.Format(time.RFC3339),
			"podcast-id":   podcastID,
			"episode-guid": episodeGUID,
		},
	}

	// upload
	_, err := b.client.PutObject(ctx, b.name, objectKey, body, size, opts)
	if err != nil {
		return "", fmt.Errorf("failed to upload to minio: %w", err)
	}

	return objectKey, nil
}

// UploadJSON serializes data to JSON and uploads it to the bucket.
func (b *Bucket) UploadJSON(ctx context.Context, objectKey string, data any) error {
	// 1. Serialize the data
	payload, err := json.Marshal(data)
	if err != nil {
		return fmt.Errorf("failed to marshal json: %w", err)
	}

	// 2. Wrap in a reader
	reader := bytes.NewReader(payload)
	size := int64(len(payload))

	// 3. Upload with JSON content type
	opts := minio.PutObjectOptions{
		ContentType: "application/json",
	}

	_, err = b.client.PutObject(ctx, b.name, objectKey, reader, size, opts)
	if err != nil {
		return fmt.Errorf("failed to upload json to minio: %w", err)
	}

	return nil
}

// retrieves a file from MinIO as a stream.
// caller is responsible for closing the returned reader.
func (b *Bucket) Download(ctx context.Context, objectKey string) (io.ReadCloser, error) {
	// returns a *minio.Object which implements io.ReadCloser
	obj, err := b.client.GetObject(ctx, b.name, objectKey, minio.GetObjectOptions{})
	if err != nil {
		return nil, fmt.Errorf("failed to get object from minio: %w", err)
	}

	// check if file is missing
	_, err = obj.Stat()
	if err != nil {
		return nil, fmt.Errorf("object not found or inaccessible: %w", err)
	}

	return obj, nil
}

// Internal helper to map MIME types to file extensions.
func extensionFromContentType(ct string) string {
	ct = strings.ToLower(ct)
	switch {
	case strings.Contains(ct, "audio/mpeg"), strings.Contains(ct, "audio/mp3"):
		return ".mp3"
	case strings.Contains(ct, "audio/mp4"), strings.Contains(ct, "audio/x-m4a"):
		return ".m4a"
	case strings.Contains(ct, "audio/ogg"):
		return ".ogg"
	case strings.Contains(ct, "audio/opus"):
		return ".opus"
	default:
		return ".audio" // Fallback
	}
}
