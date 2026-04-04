package main

import (
	"bytes"
	"context"
	"fmt"
	"log"
	"net/http"
	"os"
	"strings"
	"time"

	minio "github.com/minio/minio-go/v7"
	"github.com/minio/minio-go/v7/pkg/credentials"
	"github.com/tilmanzzz/audio-lens/ingestion/internal/ingestor"
)

func main() {
	// provide podcast name
	const pod_name = "Somna med henrik"
	fmt.Printf("fetching first episode of podcast %s", pod_name)
	// query podcast index
	episode := ingestor.FetchPodcastEpisodeMetadata(pod_name)

	// store json metadata
	json_metadata, err := episode.MarshalJSON()
	if err != nil {
		fmt.Printf("Error marshalling metadata for Episode %s", episode.Title)
	}
	// get guid
	guid := string(episode.GUID)

	_ = json_metadata
	_ = guid

	fmt.Printf("done fetching podcast")

	// dump into datalake
	//_ = godotenv.Load("../../../.env")

	endpoint := "minio:9000"
	accessKey := os.Getenv("MINIO_USER")
	secretKey := os.Getenv("MINIO_PASS")
	bucketName := "bronze"
	minioClient, err := minio.New(endpoint, &minio.Options{
		Creds:  credentials.NewStaticV4(accessKey, secretKey, ""),
		Secure: false, // Set to true if using HTTPS
	})
	if err != nil {
		log.Fatalln("Error initializing MinIO:", err)
	}

	// 3. Ensure the "bronze" bucket exists
	ctx := context.Background()
	exists, _ := minioClient.BucketExists(ctx, bucketName)
	if !exists {
		_ = minioClient.MakeBucket(ctx, bucketName, minio.MakeBucketOptions{})
		log.Println("Created bucket:", bucketName)
	}

	// store json metadata
	objectName := fmt.Sprintf("podcast_index/%s/%s.json", guid, time.Now().UTC().Format(time.RFC3339))
	reader := bytes.NewReader(json_metadata)
	size := int64(len(json_metadata))
	_, err = minioClient.PutObject(ctx, bucketName, objectName, reader, size, minio.PutObjectOptions{
		ContentType: "application/json",
	})
	if err != nil {
		log.Fatalln("Failed to upload to MinIO:", err)
	}
	// use rss feed and uuid to pipe podcast into datalake
	enclosureUrl := episode.EnclosureURL.String()
	_ = episode.EnclosureLength
	fmt.Printf("URL: %s", enclosureUrl)
	err = streamAudioToMinIO(ctx, minioClient, enclosureUrl, string(episode.FeedGUID), guid)
	if err != nil {
		log.Fatalf("Audio Streaming failed: %s", err)
	}
}

func streamAudioToMinIO(ctx context.Context, mc *minio.Client, enclosureUrl, podcastGuid, episodeGuid string) error {
	client := &http.Client{Timeout: 30 * time.Minute}
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, enclosureUrl, nil)
	if err != nil {
		return fmt.Errorf("error creating request: %w", err)
	}

	req.Header.Set("User-Agent", "Mozilla/5.0 (compatible; PodcastBot/1.0)")
	req.Header.Set("Accept", "audio/mpeg, audio/*;q=0.9, */*;q=0.8")

	resp, err := client.Do(req)
	if err != nil {
		return fmt.Errorf("error fetching audio: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK && resp.StatusCode != http.StatusPartialContent {
		return fmt.Errorf("unexpected status: %d", resp.StatusCode)
	}

	ext := extensionFromContentType(resp.Header.Get("Content-Type"))

	objectKey := fmt.Sprintf("audio/%s/%s/original%s", podcastGuid, episodeGuid, ext)

	_, err = mc.PutObject(ctx, "bronze", objectKey, resp.Body, resp.ContentLength, minio.PutObjectOptions{
		ContentType: resp.Header.Get("Content-Type"),
		UserMetadata: map[string]string{
			"source-url":   enclosureUrl,
			"fetched-at":   time.Now().UTC().Format(time.RFC3339),
			"podcast-guid": podcastGuid,
			"episode-guid": episodeGuid,
		},
	})
	return err
}

func extensionFromContentType(ct string) string {
	switch {
	case strings.Contains(ct, "mpeg"):
		return ".mp3"
	case strings.Contains(ct, "mp4"), strings.Contains(ct, "m4a"):
		return ".m4a"
	case strings.Contains(ct, "ogg"):
		return ".ogg"
	case strings.Contains(ct, "opus"):
		return ".opus"
	default:
		return ".audio"
	}
}
