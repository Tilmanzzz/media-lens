package main

import (
	"context"
	"log"
	"net/http"
	"os"

	"github.com/joho/godotenv"
	minio "github.com/minio/minio-go/v7"
	"github.com/minio/minio-go/v7/pkg/credentials"
)

func main() {
	// 1. Load variables from .env
	_ = godotenv.Load("../../../.env") // Path depends on where you run this

	endpoint := "minio:9000" // Use "minio:9000" if running INSIDE Docker
	accessKey := os.Getenv("MINIO_USER")
	secretKey := os.Getenv("MINIO_PASS")
	bucketName := "bronze"

	// 2. Initialize MinIO Client
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

	// 4. STREAMING TEST: Download a sample RSS feed
	// Using a reliable sample feed (The Daily by NYT)
	rssURL := "https://feeds.simplecast.com/54nAGpEC"
	resp, err := http.Get(rssURL)
	if err != nil {
		log.Fatalln("Failed to fetch RSS:", err)
	}
	defer resp.Body.Close()

	// 5. Pipe the stream directly to MinIO
	objectName := "test/sample_podcast.xml"
	_, err = minioClient.PutObject(ctx, bucketName, objectName, resp.Body, resp.ContentLength, minio.PutObjectOptions{
		ContentType: "text/xml",
	})
	if err != nil {
		log.Fatalln("Failed to upload to MinIO:", err)
	}

	log.Printf("Successfully ingested %s to %s/%s\n", rssURL, bucketName, objectName)
}
