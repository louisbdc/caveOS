package main

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"strings"
)

// geminiEnrichProvider est le fournisseur PRIMAIRE de la passe 2 : il déduit les
// champs manquants à partir du seul texte (sans image). Il réutilise les types et
// helpers de scan_gemini.go (geminiRequest/geminiResponse/geminiFirstText). Modèle
// via GEMINI_ENRICH_MODEL (défaut gemini-3.1-flash-lite), même clé GEMINI_API_KEY.
type geminiEnrichProvider struct {
	apiKey  string
	model   string
	baseURL string // injectable pour les tests
}

func newGeminiEnrichProvider() *geminiEnrichProvider {
	model := strings.TrimSpace(os.Getenv("GEMINI_ENRICH_MODEL"))
	if model == "" {
		model = "gemini-3.1-flash-lite"
	}
	return &geminiEnrichProvider{
		apiKey:  strings.TrimSpace(os.Getenv("GEMINI_API_KEY")),
		model:   model,
		baseURL: "https://generativelanguage.googleapis.com/v1beta",
	}
}

func (p *geminiEnrichProvider) name() string     { return "gemini" }
func (p *geminiEnrichProvider) configured() bool { return p.apiKey != "" }

// geminiEnrichSchema : schéma plat des champs DÉDUITS, au format Gemini (types en
// MAJUSCULES, nullable, propertyOrdering pour stabiliser l'ordre).
var geminiEnrichSchema = map[string]any{
	"type": "OBJECT",
	"properties": map[string]any{
		"color":       map[string]any{"type": "STRING", "enum": scanColorList, "nullable": true},
		"wineType":    map[string]any{"type": "STRING", "enum": wineTypeList, "nullable": true},
		"country":     map[string]any{"type": "STRING", "nullable": true},
		"region":      map[string]any{"type": "STRING", "nullable": true},
		"grapesGuess": map[string]any{"type": "ARRAY", "items": map[string]any{"type": "STRING"}},
		"peakFrom":    map[string]any{"type": "INTEGER", "nullable": true},
		"peakTo":      map[string]any{"type": "INTEGER", "nullable": true},
	},
	"propertyOrdering": []string{"color", "wineType", "country", "region", "grapesGuess", "peakFrom", "peakTo"},
}

func (p *geminiEnrichProvider) enrich(ctx context.Context, in enrichInput) (enrichOutput, error) {
	userText, err := enrichUserText(in)
	if err != nil {
		return enrichOutput{}, err
	}
	url := fmt.Sprintf("%s/models/%s:generateContent", strings.TrimRight(p.baseURL, "/"), p.model)

	payload := geminiRequest{
		Contents: []geminiContent{{
			Parts: []geminiPart{
				{Text: enrichInstruction + "\n" + userText},
			},
		}},
		GenerationConfig: geminiGenerationConfig{
			ResponseMimeType: "application/json",
			ResponseSchema:   geminiEnrichSchema,
			// Déduction déterministe : on coupe la « réflexion » (latence/tokens).
			ThinkingConfig: &geminiThinkingConfig{ThinkingBudget: 0},
		},
	}

	raw, err := postJSON(ctx, url, map[string]string{"x-goog-api-key": p.apiKey}, payload)
	if err != nil {
		return enrichOutput{}, err
	}

	var resp geminiResponse
	if err := json.Unmarshal(raw, &resp); err != nil {
		return enrichOutput{}, fmt.Errorf("décodage réponse Gemini (enrich): %w", err)
	}
	text := geminiFirstText(resp)
	if strings.TrimSpace(text) == "" {
		return enrichOutput{}, fmt.Errorf("réponse Gemini (enrich) vide")
	}
	return decodeEnrichOutput(text)
}
