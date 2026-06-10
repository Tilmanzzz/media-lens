package llm

import (
	"context"
	"fmt"

	"google.golang.org/genai"
)

const systemPrompt = `You are a podcast analysis assistant. You answer questions about a podcast episode based ONLY on its transcript provided below.

Rules:
- Answer exclusively based on the transcript content
- If the transcript does not contain enough information to answer the question, say so clearly
- Be concise and direct
- When relevant, reference specific parts of the transcript
- Answer in the same language the question was asked in`

type GeminiClient struct {
	client *genai.Client
	model  string
}

func NewGeminiClient(ctx context.Context, apiKey string) (*GeminiClient, error) {
	client, err := genai.NewClient(ctx, &genai.ClientConfig{
		APIKey:  apiKey,
		Backend: genai.BackendGeminiAPI,
	})
	if err != nil {
		return nil, fmt.Errorf("create gemini client: %w", err)
	}

	return &GeminiClient{
		client: client,
		model:  "gemini-3.5-flash",
	}, nil
}

func (g *GeminiClient) Ask(ctx context.Context, transcript string, question string) (string, error) {
	userMessage := fmt.Sprintf("TRANSCRIPT:\n%s\n\nQUESTION:\n%s", transcript, question)

	result, err := g.client.Models.GenerateContent(ctx,
		g.model,
		genai.Text(userMessage),
		&genai.GenerateContentConfig{
			SystemInstruction: &genai.Content{
				Parts: []*genai.Part{{Text: systemPrompt}},
			},
		},
	)
	if err != nil {
		return "", fmt.Errorf("gemini generate content: %w", err)
	}

	if len(result.Candidates) == 0 || result.Candidates[0].Content == nil || len(result.Candidates[0].Content.Parts) == 0 {
		return "", fmt.Errorf("gemini returned empty response")
	}

	return result.Candidates[0].Content.Parts[0].Text, nil
}
