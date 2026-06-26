package main

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"sort"
	"strings"
	"sync"
	"time"
)

const (
	listEnrichWorkers = 6
	listScanBudget    = 90 * time.Second
)

// listScanLimiter : 6 scans de carte des vins par minute et par IP.
var listScanLimiter = newRateLimiter(6, time.Minute)

// enrichFunc = signature d'un enrichisseur passe 2 (testable par injection).
type enrichFunc func(ctx context.Context, in ScanResult) (ScanResult, error)

// enrichListItemsWith applique enrich à chaque item dans un pool borné, best-effort,
// en préservant l'ordre (LineIndex). Les erreurs de l'enrichisseur sont silencieuses :
// l'item original est conservé tel quel.
func enrichListItemsWith(ctx context.Context, items []ScanListItem, enrich enrichFunc) []ScanListItem {
	out := make([]ScanListItem, len(items))
	copy(out, items)
	sem := make(chan struct{}, listEnrichWorkers)
	var wg sync.WaitGroup
	for i := range out {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			sem <- struct{}{}
			defer func() { <-sem }()
			if res, err := enrich(ctx, out[i].ScanResult); err == nil {
				out[i].ScanResult = res
			}
		}(i)
	}
	wg.Wait()
	sort.SliceStable(out, func(a, b int) bool { return out[a].LineIndex < out[b].LineIndex })
	return out
}

// enrichListItems = adaptateur production : appelle s.applyPass2 (best-effort, jamais d'erreur).
func enrichListItems(ctx context.Context, s *server, items []ScanListItem) []ScanListItem {
	return enrichListItemsWith(ctx, items, func(ctx context.Context, in ScanResult) (ScanResult, error) {
		return s.applyPass2(ctx, in), nil
	})
}

// listPrompt est l'invite système envoyée aux fournisseurs pour l'analyse d'une carte des vins.
const listPrompt = "Tu reçois la photo d'une carte des vins de restaurant. Renvoie UNIQUEMENT un JSON {\"wines\":[…]}. " +
	"Pour chaque vin lisible : producer, wineName, vintage (int, 0 si absent), appellation, grapes (array), " +
	"price (number, prix bouteille), currency (ISO ex EUR), byGlass (bool), priceGlass (number si proposé au verre). " +
	"N'invente aucun vin absent de la carte. Ignore les sections non-vin (eaux, softs, cocktails)."

// geminiListSchema : schéma JSON structuré (format Gemini) pour une liste de vins.
var geminiListSchema = map[string]any{
	"type": "OBJECT",
	"properties": map[string]any{
		"wines": map[string]any{
			"type": "ARRAY",
			"items": map[string]any{
				"type": "OBJECT",
				"properties": map[string]any{
					"producer":    map[string]any{"type": "STRING"},
					"wineName":    map[string]any{"type": "STRING"},
					"vintage":     map[string]any{"type": "INTEGER"},
					"appellation": map[string]any{"type": "STRING"},
					"grapes":      map[string]any{"type": "ARRAY", "items": map[string]any{"type": "STRING"}},
					"price":       map[string]any{"type": "NUMBER"},
					"currency":    map[string]any{"type": "STRING"},
					"byGlass":     map[string]any{"type": "BOOLEAN"},
					"priceGlass":  map[string]any{"type": "NUMBER"},
				},
			},
		},
	},
}

// mistralListSchema : schéma JSON (style OpenAPI) pour Mistral OCR (liste de vins).
var mistralListSchema = map[string]any{
	"type":  "object",
	"title": "WineList",
	"properties": map[string]any{
		"wines": map[string]any{
			"type": "array",
			"items": map[string]any{
				"type": "object",
				"properties": map[string]any{
					"producer":    map[string]any{"type": "string"},
					"wineName":    map[string]any{"type": "string"},
					"vintage":     map[string]any{"type": "integer"},
					"appellation": map[string]any{"type": "string"},
					"grapes":      map[string]any{"type": "array", "items": map[string]any{"type": "string"}},
					"price":       map[string]any{"type": "number"},
					"currency":    map[string]any{"type": "string"},
					"byGlass":     map[string]any{"type": "boolean"},
					"priceGlass":  map[string]any{"type": "number"},
				},
			},
		},
	},
}

// runListPass1 appelle le premier fournisseur de vision configuré (selon s.pass1Order)
// avec le prompt liste et renvoie le JSON brut + nom du fournisseur. Best-effort :
// les échecs sont journalisés et le fournisseur suivant est tenté. Renvoie un
// tableau vide si aucun fournisseur ne répond.
func (s *server) runListPass1(ctx context.Context, image, mime string) ([]byte, string) {
	for _, name := range s.pass1Order {
		p, ok := s.scanProviders[name]
		if !ok || !p.configured() {
			continue
		}
		pctx, cancel := context.WithTimeout(ctx, pass1Timeout)
		raw, err := callProviderList(pctx, name, image, mime)
		cancel()
		if err != nil {
			s.logger.Warn("list scan provider failed", "provider", name, "error", err)
			continue
		}
		return raw, name
	}
	return []byte(`{"wines":[]}`), "none"
}

// callProviderList aiguille l'appel vers le fournisseur nommé avec le prompt liste.
func callProviderList(ctx context.Context, providerName, image, mime string) ([]byte, error) {
	switch providerName {
	case "gemini":
		return callGeminiList(ctx, image, mime)
	case "mistral":
		return callMistralList(ctx, image, mime)
	default:
		return nil, fmt.Errorf("fournisseur liste inconnu: %s", providerName)
	}
}

// callGeminiList appelle Gemini generateContent avec le prompt liste et le schéma de carte.
func callGeminiList(ctx context.Context, image, mime string) ([]byte, error) {
	apiKey := strings.TrimSpace(os.Getenv("GEMINI_API_KEY"))
	model := strings.TrimSpace(os.Getenv("GEMINI_MODEL"))
	if model == "" {
		model = "gemini-2.5-flash"
	}
	url := fmt.Sprintf("https://generativelanguage.googleapis.com/v1beta/models/%s:generateContent", model)

	payload := geminiRequest{
		Contents: []geminiContent{{
			Parts: []geminiPart{
				{InlineData: &geminiInlineData{MimeType: mime, Data: image}},
				{Text: listPrompt},
			},
		}},
		GenerationConfig: geminiGenerationConfig{
			ResponseMimeType: "application/json",
			ResponseSchema:   geminiListSchema,
		},
	}

	raw, err := postJSON(ctx, url, map[string]string{"x-goog-api-key": apiKey}, payload)
	if err != nil {
		return nil, err
	}
	var resp geminiResponse
	if err := json.Unmarshal(raw, &resp); err != nil {
		return nil, fmt.Errorf("décodage réponse Gemini liste: %w", err)
	}
	text := geminiFirstText(resp)
	if strings.TrimSpace(text) == "" {
		return nil, fmt.Errorf("réponse Gemini liste vide")
	}
	return []byte(stripJSONFence(text)), nil
}

// callMistralList appelle Mistral OCR avec le schéma JSON de liste.
func callMistralList(ctx context.Context, image, mime string) ([]byte, error) {
	apiKey := strings.TrimSpace(os.Getenv("MISTRAL_API_KEY"))
	model := strings.TrimSpace(os.Getenv("MISTRAL_OCR_MODEL"))
	if model == "" {
		model = "mistral-ocr-latest"
	}
	const mistralOCRURL = "https://api.mistral.ai/v1/ocr"

	payload := mistralOCRRequest{
		Model: model,
		Document: mistralDocument{
			Type:     "image_url",
			ImageURL: dataURL(mime, image),
		},
		DocumentAnnotationFormat: map[string]any{
			"type": "json_schema",
			"json_schema": map[string]any{
				"name":   "wine_list",
				"schema": mistralListSchema,
			},
		},
	}

	raw, err := postJSON(ctx, mistralOCRURL, map[string]string{"Authorization": "Bearer " + apiKey}, payload)
	if err != nil {
		return nil, err
	}
	var resp mistralOCRResponse
	if err := json.Unmarshal(raw, &resp); err != nil {
		return nil, fmt.Errorf("décodage réponse Mistral liste: %w", err)
	}
	if strings.TrimSpace(resp.DocumentAnnotation) == "" {
		return nil, fmt.Errorf("réponse Mistral liste sans annotation structurée")
	}
	return []byte(resp.DocumentAnnotation), nil
}

// handleScanList traite POST /v1/scan/list : vérifie le secret partagé, limite le
// débit, lance la passe 1 liste, enrichit les vins par passe 2 (best-effort) et
// renvoie la réponse normalisée. Ne renvoie jamais de 5xx sur le chemin nominal.
func (s *server) handleScanList(w http.ResponseWriter, r *http.Request) {
	if !checkScanSecret(r) {
		writeError(w, http.StatusUnauthorized, "clé d'accès invalide")
		return
	}
	if !listScanLimiter.allow(clientIP(r)) {
		writeError(w, http.StatusTooManyRequests, "trop de requêtes, réessayez dans un instant")
		return
	}

	var req scanRequest
	if err := json.NewDecoder(io.LimitReader(r.Body, 12<<20)).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "corps JSON invalide")
		return
	}
	if strings.TrimSpace(req.Image) == "" {
		writeError(w, http.StatusBadRequest, "champ 'image' manquant")
		return
	}
	mime := strings.TrimSpace(req.MimeType)
	if mime == "" {
		mime = "image/jpeg"
	}

	ctx, cancel := context.WithTimeout(r.Context(), listScanBudget)
	defer cancel()

	raw, provider := s.runListPass1(ctx, req.Image, mime)
	items, truncated, err := parseListPayload(raw)
	if err != nil {
		items = nil
	}
	if !isWineList(items) {
		writeJSON(w, http.StatusOK, ScanListResponse{
			Wines:       []ScanListItem{},
			Count:       0,
			Provider:    provider,
			NotWineList: true,
		})
		return
	}
	enriched := enrichListItems(ctx, s, items)
	writeJSON(w, http.StatusOK, ScanListResponse{
		Wines:     enriched,
		Count:     len(enriched),
		Provider:  provider,
		Truncated: truncated,
	})
}
