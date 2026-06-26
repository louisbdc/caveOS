package main

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"strings"
)

// mistralChatEnrichProvider est le fournisseur de REPLI de la passe 2 : modèle de
// chat (l'OCR ne fait pas de chat) via /v1/chat/completions, format compatible
// OpenAI. Modèle via MISTRAL_ENRICH_MODEL (défaut mistral-small-latest), même clé
// MISTRAL_API_KEY que la passe 1.
type mistralChatEnrichProvider struct {
	apiKey  string
	model   string
	baseURL string // injectable pour les tests
}

func newMistralEnrichProvider() *mistralChatEnrichProvider {
	model := strings.TrimSpace(os.Getenv("MISTRAL_ENRICH_MODEL"))
	if model == "" {
		model = "mistral-small-latest"
	}
	return &mistralChatEnrichProvider{
		apiKey:  strings.TrimSpace(os.Getenv("MISTRAL_API_KEY")),
		model:   model,
		baseURL: "https://api.mistral.ai/v1/chat/completions",
	}
}

func (p *mistralChatEnrichProvider) name() string     { return "mistral" }
func (p *mistralChatEnrichProvider) configured() bool { return p.apiKey != "" }

// nullableStringEnum construit un type nullable contraint à un ensemble de
// valeurs + null, comme l'exige le mode strict de Mistral (json_schema).
func nullableStringEnum(values []string) map[string]any {
	enum := make([]any, 0, len(values)+1)
	for _, v := range values {
		enum = append(enum, v)
	}
	enum = append(enum, nil)
	return map[string]any{
		"type": []string{"string", "null"},
		"enum": enum,
	}
}

// mistralEnrichSchema : schéma JSON strict. Mistral impose en mode strict que
// TOUTES les propriétés soient dans `required` (les facultatives sont nullables)
// et `additionalProperties:false` sur l'objet.
var mistralEnrichSchema = map[string]any{
	"type":                 "object",
	"additionalProperties": false,
	"properties": map[string]any{
		"color":       nullableStringEnum(scanColorList),
		"wineType":    nullableStringEnum(wineTypeList),
		"country":     map[string]any{"type": []string{"string", "null"}},
		"region":      map[string]any{"type": []string{"string", "null"}},
		"grapesGuess": map[string]any{"type": "array", "items": map[string]any{"type": "string"}},
		"peakFrom":    map[string]any{"type": []string{"integer", "null"}},
		"peakTo":      map[string]any{"type": []string{"integer", "null"}},
	},
	"required": []string{"color", "wineType", "country", "region", "grapesGuess", "peakFrom", "peakTo"},
}

type mistralChatMessage struct {
	Role    string `json:"role"`
	Content string `json:"content"`
}

type mistralChatRequest struct {
	Model          string               `json:"model"`
	Messages       []mistralChatMessage `json:"messages"`
	ResponseFormat any                  `json:"response_format"`
}

type mistralChatResponse struct {
	Choices []struct {
		Message struct {
			Content string `json:"content"`
		} `json:"message"`
	} `json:"choices"`
}

func (p *mistralChatEnrichProvider) enrich(ctx context.Context, in enrichInput) (enrichOutput, error) {
	userText, err := enrichUserText(in)
	if err != nil {
		return enrichOutput{}, err
	}
	payload := mistralChatRequest{
		Model: p.model,
		Messages: []mistralChatMessage{
			{Role: "system", Content: enrichInstruction},
			{Role: "user", Content: userText},
		},
		ResponseFormat: map[string]any{
			"type": "json_schema",
			"json_schema": map[string]any{
				"name":   "wine_enrichment",
				"strict": true,
				"schema": mistralEnrichSchema,
			},
		},
	}

	raw, err := postJSON(ctx, p.baseURL, map[string]string{
		"Authorization": "Bearer " + p.apiKey,
	}, payload)
	if err != nil {
		return enrichOutput{}, err
	}

	var resp mistralChatResponse
	if err := json.Unmarshal(raw, &resp); err != nil {
		return enrichOutput{}, fmt.Errorf("décodage réponse Mistral (enrich): %w", err)
	}
	if len(resp.Choices) == 0 || strings.TrimSpace(resp.Choices[0].Message.Content) == "" {
		return enrichOutput{}, fmt.Errorf("réponse Mistral (enrich) vide")
	}
	return decodeEnrichOutput(resp.Choices[0].Message.Content)
}
