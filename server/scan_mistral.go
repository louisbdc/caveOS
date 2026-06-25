package main

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"strings"
)

// mistralProvider utilise l'API OCR de Mistral (mistral-ocr-latest) avec une
// annotation de document structurée pour extraire les champs de l'étiquette en
// un seul appel.
type mistralProvider struct {
	apiKey  string
	model   string
	baseURL string // injectable pour les tests
}

func newMistralProvider() *mistralProvider {
	model := strings.TrimSpace(os.Getenv("MISTRAL_OCR_MODEL"))
	if model == "" {
		model = "mistral-ocr-latest"
	}
	return &mistralProvider{
		apiKey:  strings.TrimSpace(os.Getenv("MISTRAL_API_KEY")),
		model:   model,
		baseURL: "https://api.mistral.ai/v1/ocr",
	}
}

func (p *mistralProvider) name() string     { return "mistral" }
func (p *mistralProvider) configured() bool { return p.apiKey != "" }

// mistralLabelSchema : schéma JSON (style OpenAPI standard) décrivant les champs
// vin attendus dans document_annotation.
var mistralLabelSchema = map[string]any{
	"type":  "object",
	"title": "WineLabel",
	"properties": map[string]any{
		"producer":    map[string]any{"type": "string"},
		"wineName":    map[string]any{"type": "string"},
		"vintage":     map[string]any{"type": "integer"},
		"appellation": map[string]any{"type": "string"},
		"grapes":      map[string]any{"type": "array", "items": map[string]any{"type": "string"}},
		"format":      map[string]any{"type": "string"},
		"abv":         map[string]any{"type": "string"},
	},
	"required":             labelFields,
	"additionalProperties": false,
}

type mistralDocument struct {
	Type     string `json:"type"`
	ImageURL string `json:"image_url"`
}

type mistralOCRRequest struct {
	Model                    string          `json:"model"`
	Document                 mistralDocument `json:"document"`
	DocumentAnnotationFormat any             `json:"document_annotation_format"`
}

type mistralOCRResponse struct {
	DocumentAnnotation string `json:"document_annotation"`
	Pages              []struct {
		Markdown string `json:"markdown"`
	} `json:"pages"`
}

func (p *mistralProvider) scan(ctx context.Context, imageBase64, mimeType string) (ScanResult, error) {
	payload := mistralOCRRequest{
		Model: p.model,
		Document: mistralDocument{
			Type:     "image_url",
			ImageURL: dataURL(mimeType, imageBase64),
		},
		DocumentAnnotationFormat: map[string]any{
			"type": "json_schema",
			"json_schema": map[string]any{
				"name":   "wine_label",
				"schema": mistralLabelSchema,
			},
		},
	}

	raw, err := postJSON(ctx, p.baseURL, map[string]string{
		"Authorization": "Bearer " + p.apiKey,
	}, payload)
	if err != nil {
		return ScanResult{}, err
	}

	var resp mistralOCRResponse
	if err := json.Unmarshal(raw, &resp); err != nil {
		return ScanResult{}, fmt.Errorf("décodage réponse Mistral: %w", err)
	}
	if strings.TrimSpace(resp.DocumentAnnotation) == "" {
		return ScanResult{}, fmt.Errorf("réponse Mistral sans annotation structurée")
	}
	return decodeAILabel(resp.DocumentAnnotation)
}
