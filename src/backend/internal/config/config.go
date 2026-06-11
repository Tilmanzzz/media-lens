package config

import (
	"fmt"
	"os"
	"strings"
)

type Config struct {
	ServerPort     string
	PostgresURL    string
	MinioEndpoint  string
	MinioUser      string
	MinioPass      string
	MinioUseSSL    bool
	MinioBucket    string
	CORSOrigins    []string
	OllamaURL      string
	EmbeddingModel string
	GeminiAPIKey   string
}

func Load() (*Config, error) {
	cfg := &Config{
		ServerPort:     getEnvOrDefault("BACKEND_PORT", ":8080"),
		PostgresURL:    os.Getenv("POSTGRES_URL"),
		MinioEndpoint:  getEnvOrDefault("MINIO_ENDPOINT", "minio:9000"),
		MinioUser:      os.Getenv("MINIO_USER"),
		MinioPass:      os.Getenv("MINIO_PASS"),
		MinioUseSSL:    os.Getenv("MINIO_USE_SSL") == "true",
		MinioBucket:    getEnvOrDefault("MINIO_BUCKET", "bronze"),
		CORSOrigins:    strings.Split(getEnvOrDefault("CORS_ORIGINS", "http://localhost:3000"), ","),
		OllamaURL:      getEnvOrDefault("OLLAMA_URL", "http://ollama:11434"),
		EmbeddingModel: getEnvOrDefault("EMBEDDING_MODEL", "qwen3-embedding:4b"),
		GeminiAPIKey:   os.Getenv("GEMINI_API_KEY"),
	}

	if cfg.PostgresURL == "" {
		return nil, fmt.Errorf("POSTGRES_URL is required")
	}
	if cfg.MinioUser == "" {
		return nil, fmt.Errorf("MINIO_USER is required")
	}
	if cfg.MinioPass == "" {
		return nil, fmt.Errorf("MINIO_PASS is required")
	}
	if cfg.GeminiAPIKey == "" {
		return nil, fmt.Errorf("GEMINI_API_KEY is required")
	}

	return cfg, nil
}

func getEnvOrDefault(key, fallback string) string {
	if val := os.Getenv(key); val != "" {
		return val
	}
	return fallback
}
