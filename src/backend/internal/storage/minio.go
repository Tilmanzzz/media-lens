package storage

import (
	"context"
	"fmt"
	"net/url"
	"time"

	"github.com/minio/minio-go/v7"
	"github.com/minio/minio-go/v7/pkg/credentials"
	"media-lens/backend/internal/config"
)

func NewMinioClient(cfg *config.Config) (*minio.Client, error) {
	client, err := minio.New(cfg.MinioEndpoint, &minio.Options{
		Creds:        credentials.NewStaticV4(cfg.MinioUser, cfg.MinioPass, ""),
		Secure:       cfg.MinioUseSSL,
		BucketLookup: minio.BucketLookupPath,
	})
	if err != nil {
		return nil, fmt.Errorf("failed to create minio client: %w", err)
	}
	return client, nil
}

func GeneratePresignedURL(ctx context.Context, client *minio.Client, bucket, objectPath string, expiry time.Duration) (*url.URL, error) {
	reqParams := make(url.Values)
	presignedURL, err := client.PresignedGetObject(ctx, bucket, objectPath, expiry, reqParams)
	if err != nil {
		return nil, fmt.Errorf("failed to generate presigned URL: %w", err)
	}
	return presignedURL, nil
}
