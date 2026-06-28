package embedder

import "context"

// Embedder abstracts embedding providers (Ollama, Gemini, ...).
type Embedder interface {
	Embed(ctx context.Context, text string) ([]float64, error)
	HealthCheck(ctx context.Context) error
}
