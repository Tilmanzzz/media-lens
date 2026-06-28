package embedder

import (
	"context"
	"fmt"

	"google.golang.org/genai"
)

type GeminiEmbedder struct {
	client    *genai.Client
	model     string
	dimension int32
}

func NewGeminiEmbedder(ctx context.Context, apiKey, model string, dimension int) (*GeminiEmbedder, error) {
	client, err := genai.NewClient(ctx, &genai.ClientConfig{
		APIKey:  apiKey,
		Backend: genai.BackendGeminiAPI,
	})
	if err != nil {
		return nil, fmt.Errorf("create gemini embedding client: %w", err)
	}

	return &GeminiEmbedder{
		client:    client,
		model:     model,
		dimension: int32(dimension),
	}, nil
}

func (g *GeminiEmbedder) Embed(ctx context.Context, text string) ([]float64, error) {
	prompted := taskInstruction + text

	contents := []*genai.Content{
		genai.NewContentFromText(prompted, genai.RoleUser),
	}

	dim := g.dimension
	result, err := g.client.Models.EmbedContent(ctx, g.model, contents, &genai.EmbedContentConfig{
		OutputDimensionality: &dim,
	})
	if err != nil {
		return nil, fmt.Errorf("gemini embed call: %w", err)
	}

	if len(result.Embeddings) == 0 || len(result.Embeddings[0].Values) == 0 {
		return nil, fmt.Errorf("gemini returned empty embedding")
	}

	f32 := result.Embeddings[0].Values
	f64 := make([]float64, len(f32))
	for i, v := range f32 {
		f64[i] = float64(v)
	}
	return f64, nil
}

func (g *GeminiEmbedder) HealthCheck(ctx context.Context) error {
	// Lightweight check: embed a single token to verify the API is reachable.
	_, err := g.Embed(ctx, "ping")
	return err
}
