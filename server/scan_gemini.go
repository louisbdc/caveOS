package main

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"strings"
)

// geminiProvider utilise l'API generateContent de Google Gemini avec une sortie
// JSON structurée (responseSchema) pour lire l'image et extraire les champs vin
// en un seul appel. Modèle configurable via GEMINI_MODEL (défaut gemini-2.5-flash),
// ce qui permet de suivre les évolutions de l'offre gratuite sans recompiler.
type geminiProvider struct {
	apiKey  string
	model   string
	baseURL string // injectable pour les tests
}

func newGeminiProvider() *geminiProvider {
	model := strings.TrimSpace(os.Getenv("GEMINI_MODEL"))
	if model == "" {
		model = "gemini-2.5-flash"
	}
	return &geminiProvider{
		apiKey:  strings.TrimSpace(os.Getenv("GEMINI_API_KEY")),
		model:   model,
		baseURL: "https://generativelanguage.googleapis.com/v1beta",
	}
}

func (p *geminiProvider) name() string     { return "gemini" }
func (p *geminiProvider) configured() bool { return p.apiKey != "" }

// geminiLabelSchema : même schéma vin, au format attendu par Gemini (types en
// MAJUSCULES). propertyOrdering stabilise l'ordre de génération.
var geminiLabelSchema = map[string]any{
	"type": "OBJECT",
	"properties": map[string]any{
		"producer":    map[string]any{"type": "STRING"},
		"wineName":    map[string]any{"type": "STRING"},
		"vintage":     map[string]any{"type": "INTEGER"},
		"appellation": map[string]any{"type": "STRING"},
		"grapes":      map[string]any{"type": "ARRAY", "items": map[string]any{"type": "STRING"}},
		"format":      map[string]any{"type": "STRING"},
		"abv":         map[string]any{"type": "STRING"},
	},
	"propertyOrdering": labelFields,
}

type geminiInlineData struct {
	MimeType string `json:"mimeType"`
	Data     string `json:"data"`
}

type geminiPart struct {
	Text       string            `json:"text,omitempty"`
	InlineData *geminiInlineData `json:"inlineData,omitempty"`
}

type geminiContent struct {
	Parts []geminiPart `json:"parts"`
}

// geminiThinkingConfig pilote le budget de « réflexion » des modèles Gemini 3.x
// (activé par défaut depuis I/O 2026). Pour une déduction déterministe on le met
// à 0 afin d'éviter latence et tokens superflus.
type geminiThinkingConfig struct {
	ThinkingBudget int `json:"thinkingBudget"`
}

type geminiGenerationConfig struct {
	ResponseMimeType string                `json:"responseMimeType"`
	ResponseSchema   any                   `json:"responseSchema"`
	ThinkingConfig   *geminiThinkingConfig `json:"thinkingConfig,omitempty"`
}

type geminiRequest struct {
	Contents         []geminiContent        `json:"contents"`
	GenerationConfig geminiGenerationConfig `json:"generationConfig"`
}

type geminiResponse struct {
	Candidates []struct {
		Content struct {
			Parts []struct {
				Text string `json:"text"`
			} `json:"parts"`
		} `json:"content"`
	} `json:"candidates"`
}

func (p *geminiProvider) scan(ctx context.Context, imageBase64, mimeType string) (ScanResult, error) {
	url := fmt.Sprintf("%s/models/%s:generateContent", strings.TrimRight(p.baseURL, "/"), p.model)

	payload := geminiRequest{
		Contents: []geminiContent{{
			Parts: []geminiPart{
				{InlineData: &geminiInlineData{MimeType: mimeType, Data: imageBase64}},
				{Text: labelInstruction},
			},
		}},
		GenerationConfig: geminiGenerationConfig{
			ResponseMimeType: "application/json",
			ResponseSchema:   geminiLabelSchema,
		},
	}

	raw, err := postJSON(ctx, url, map[string]string{
		"x-goog-api-key": p.apiKey,
	}, payload)
	if err != nil {
		return ScanResult{}, err
	}

	var resp geminiResponse
	if err := json.Unmarshal(raw, &resp); err != nil {
		return ScanResult{}, fmt.Errorf("décodage réponse Gemini: %w", err)
	}
	text := geminiFirstText(resp)
	if strings.TrimSpace(text) == "" {
		return ScanResult{}, fmt.Errorf("réponse Gemini vide")
	}
	return decodeAILabel(text)
}

// geminiFirstText renvoie le texte du premier candidat (concaténé si plusieurs
// parts), ou une chaîne vide.
func geminiFirstText(resp geminiResponse) string {
	if len(resp.Candidates) == 0 {
		return ""
	}
	var b strings.Builder
	for _, part := range resp.Candidates[0].Content.Parts {
		b.WriteString(part.Text)
	}
	return b.String()
}
