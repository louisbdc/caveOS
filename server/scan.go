package main

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/http"
	"os"
	"strconv"
	"strings"
	"sync"
	"time"
)

// --- Scan: extraction structurée d'étiquette par un fournisseur d'IA ----------
//
// L'endpoint POST /v1/scan reçoit une image (base64) et la confie au fournisseur
// d'IA demandé (Mistral OCR, Gemini, …) qui renvoie les champs structurés de
// l'étiquette. L'ajout d'un nouveau fournisseur se limite à implémenter
// `scanProvider` et à l'enregistrer dans `newScanProviders`.

// ScanResult est la charge utile normalisée renvoyée à l'app, quel que soit le
// fournisseur. Les champs vides sont omis pour alléger la réponse.
type ScanResult struct {
	Producer    string   `json:"producer,omitempty"`
	WineName    string   `json:"wineName,omitempty"`
	Vintage     int      `json:"vintage,omitempty"`
	Appellation string   `json:"appellation,omitempty"`
	Grapes      []string `json:"grapes,omitempty"`
	Format      string   `json:"format,omitempty"`
	ABV         string   `json:"abv,omitempty"`
	Provider    string   `json:"provider"`
}

// scanRequest est le corps JSON attendu sur POST /v1/scan.
type scanRequest struct {
	Provider string `json:"provider"`
	Image    string `json:"image"`    // base64 brut (sans préfixe data:)
	MimeType string `json:"mimeType"` // ex. "image/jpeg" ; défaut image/jpeg
}

// scanProvider abstrait un moteur d'extraction. Chaque fournisseur lit sa propre
// clé d'API et expose son état de configuration.
type scanProvider interface {
	name() string
	configured() bool
	scan(ctx context.Context, imageBase64, mimeType string) (ScanResult, error)
}

// labelFields décrit les champs à extraire ; partagé par tous les fournisseurs
// pour garantir une sortie homogène.
var labelFields = []string{"producer", "wineName", "vintage", "appellation", "grapes", "format", "abv"}

// labelInstruction est l'invite commune décrivant la tâche d'extraction.
const labelInstruction = "Tu analyses la photo d'une étiquette de bouteille de vin. " +
	"Extrais les champs suivants en respectant strictement le schéma JSON fourni : " +
	"producer (domaine/château), wineName (nom de la cuvée), vintage (millésime, année sur 4 chiffres en entier), " +
	"appellation, grapes (liste des cépages), format (ex. \"75 cl\", \"Magnum (1,5 L)\"), abv (degré, ex. \"13,5 %\"). " +
	"Laisse un champ vide (ou 0 pour vintage) si l'information est absente. N'invente jamais de valeur."

// --- Handler -----------------------------------------------------------------

// newScanProviders construit le registre des fournisseurs disponibles. Pour en
// ajouter un, instancier ici sa structure (qui lira sa clé via os.Getenv).
func newScanProviders() map[string]scanProvider {
	providers := map[string]scanProvider{}
	for _, p := range []scanProvider{newMistralProvider(), newGeminiProvider()} {
		providers[p.name()] = p
	}
	return providers
}

// handleScan traite POST /v1/scan : vérifie le secret partagé, limite le débit,
// sélectionne le fournisseur et renvoie le résultat normalisé.
func (s *server) handleScan(w http.ResponseWriter, r *http.Request) {
	if !checkScanSecret(r) {
		writeError(w, http.StatusUnauthorized, "clé d'accès invalide")
		return
	}
	if !scanLimiter.allow(clientIP(r)) {
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

	provider, ok := s.scanProviders[strings.ToLower(strings.TrimSpace(req.Provider))]
	if !ok {
		writeError(w, http.StatusBadRequest, "fournisseur inconnu (attendu: mistral, gemini)")
		return
	}
	if !provider.configured() {
		writeError(w, http.StatusServiceUnavailable,
			fmt.Sprintf("le fournisseur %q n'est pas configuré sur le serveur", provider.name()))
		return
	}

	ctx, cancel := context.WithTimeout(r.Context(), 45*time.Second)
	defer cancel()

	result, err := provider.scan(ctx, req.Image, mime)
	if err != nil {
		s.logger.Error("scan provider failed", "provider", provider.name(), "error", err)
		writeError(w, http.StatusBadGateway, "le fournisseur d'IA n'a pas pu analyser l'image")
		return
	}
	result.Provider = provider.name()
	// Trace le moteur réellement utilisé et un aperçu non sensible du résultat
	// (l'image et le texte d'étiquette ne sont jamais journalisés).
	s.logger.Info("scan ok",
		"provider", provider.name(),
		"vintage", result.Vintage,
		"hasProducer", result.Producer != "",
		"hasWineName", result.WineName != "",
		"grapes", len(result.Grapes),
	)
	writeJSON(w, http.StatusOK, result)
}

// --- Sécurité & débit --------------------------------------------------------

// checkScanSecret vérifie l'en-tête X-CaveOS-Key contre CAVEOS_SCAN_KEY. Si la
// variable n'est pas définie côté serveur, la vérification est désactivée (mode
// ouvert, pratique pour les tests).
func checkScanSecret(r *http.Request) bool {
	expected := strings.TrimSpace(os.Getenv("CAVEOS_SCAN_KEY"))
	if expected == "" {
		return true
	}
	return r.Header.Get("X-CaveOS-Key") == expected
}

// clientIP extrait l'IP de l'appelant (X-Forwarded-For en priorité derrière un
// reverse-proxy, sinon RemoteAddr).
func clientIP(r *http.Request) string {
	if fwd := r.Header.Get("X-Forwarded-For"); fwd != "" {
		if i := strings.IndexByte(fwd, ','); i >= 0 {
			return strings.TrimSpace(fwd[:i])
		}
		return strings.TrimSpace(fwd)
	}
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		return r.RemoteAddr
	}
	return host
}

// rateLimiter est un limiteur très simple par IP : N requêtes par fenêtre.
type rateLimiter struct {
	mu     sync.Mutex
	hits   map[string][]time.Time
	limit  int
	window time.Duration
}

func newRateLimiter(limit int, window time.Duration) *rateLimiter {
	return &rateLimiter{hits: map[string][]time.Time{}, limit: limit, window: window}
}

func (l *rateLimiter) allow(key string) bool {
	l.mu.Lock()
	defer l.mu.Unlock()
	now := time.Now()
	cutoff := now.Add(-l.window)
	kept := l.hits[key][:0]
	for _, t := range l.hits[key] {
		if t.After(cutoff) {
			kept = append(kept, t)
		}
	}
	if len(kept) >= l.limit {
		l.hits[key] = kept
		return false
	}
	l.hits[key] = append(kept, now)
	return true
}

// scanLimiter : 20 scans IA par minute et par IP (anti-abus opportuniste).
var scanLimiter = newRateLimiter(20, time.Minute)

// --- Décodage tolérant de la sortie du modèle --------------------------------

// aiLabel reçoit la sortie JSON brute du modèle. vintage est typé `any` pour
// tolérer un entier, un flottant, une chaîne ("2015") ou null indifféremment.
type aiLabel struct {
	Producer    string   `json:"producer"`
	WineName    string   `json:"wineName"`
	Vintage     any      `json:"vintage"`
	Appellation string   `json:"appellation"`
	Grapes      []string `json:"grapes"`
	Format      string   `json:"format"`
	ABV         string   `json:"abv"`
}

// anyToString réduit une valeur JSON décodée (json.Number, string, float64, nil)
// en chaîne exploitable par parseVintage.
func anyToString(v any) string {
	switch x := v.(type) {
	case nil:
		return ""
	case string:
		return x
	case json.Number:
		return x.String()
	case float64:
		return strconv.FormatFloat(x, 'f', -1, 64)
	default:
		return fmt.Sprintf("%v", x)
	}
}

// toResult normalise la sortie du modèle en ScanResult propre.
func (l aiLabel) toResult() ScanResult {
	grapes := make([]string, 0, len(l.Grapes))
	for _, g := range l.Grapes {
		if g = strings.TrimSpace(g); g != "" {
			grapes = append(grapes, g)
		}
	}
	return ScanResult{
		Producer:    strings.TrimSpace(l.Producer),
		WineName:    strings.TrimSpace(l.WineName),
		Vintage:     parseVintage(anyToString(l.Vintage)),
		Appellation: strings.TrimSpace(l.Appellation),
		Grapes:      grapes,
		Format:      strings.TrimSpace(l.Format),
		ABV:         strings.TrimSpace(l.ABV),
	}
}

// parseVintage extrait une année plausible d'une chaîne libre. Renvoie 0 si rien
// d'exploitable.
func parseVintage(raw string) int {
	raw = strings.TrimSpace(raw)
	if raw == "" {
		return 0
	}
	if dot := strings.IndexByte(raw, '.'); dot >= 0 {
		raw = raw[:dot] // "2015.0" -> "2015"
	}
	year, err := strconv.Atoi(raw)
	if err != nil || year < 1900 || year > time.Now().Year()+1 {
		return 0
	}
	return year
}

// decodeAILabel décode une chaîne JSON produite par un modèle en ScanResult, en
// tolérant un éventuel encadrement ```json … ```.
func decodeAILabel(jsonText string) (ScanResult, error) {
	jsonText = stripJSONFence(jsonText)
	dec := json.NewDecoder(strings.NewReader(jsonText))
	dec.UseNumber()
	var label aiLabel
	if err := dec.Decode(&label); err != nil {
		return ScanResult{}, fmt.Errorf("décodage de la sortie du modèle: %w", err)
	}
	return label.toResult(), nil
}

// stripJSONFence retire un éventuel bloc Markdown ```json … ``` autour du JSON.
func stripJSONFence(s string) string {
	s = strings.TrimSpace(s)
	if !strings.HasPrefix(s, "```") {
		return s
	}
	if i := strings.IndexByte(s, '\n'); i >= 0 {
		s = s[i+1:]
	}
	s = strings.TrimSuffix(strings.TrimSpace(s), "```")
	return strings.TrimSpace(s)
}

// --- HTTP partagé ------------------------------------------------------------

// scanHTTPClient est réutilisé par les fournisseurs (timeout généreux car les
// modèles peuvent mettre plusieurs secondes à répondre).
var scanHTTPClient = &http.Client{Timeout: 40 * time.Second}

// postJSON envoie un corps JSON et renvoie le corps de réponse brut, ou une
// erreur incluant le statut et un extrait du corps en cas d'échec.
func postJSON(ctx context.Context, url string, headers map[string]string, payload any) ([]byte, error) {
	body, err := json.Marshal(payload)
	if err != nil {
		return nil, fmt.Errorf("encodage requête: %w", err)
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, url, bytes.NewReader(body))
	if err != nil {
		return nil, fmt.Errorf("construction requête: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")
	for k, v := range headers {
		req.Header.Set(k, v)
	}
	resp, err := scanHTTPClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("appel HTTP: %w", err)
	}
	defer resp.Body.Close()
	raw, err := io.ReadAll(io.LimitReader(resp.Body, 4<<20))
	if err != nil {
		return nil, fmt.Errorf("lecture réponse: %w", err)
	}
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return nil, fmt.Errorf("statut %d: %s", resp.StatusCode, truncate(string(raw), 300))
	}
	return raw, nil
}

func truncate(s string, n int) string {
	if len(s) <= n {
		return s
	}
	return s[:n] + "…"
}

// dataURL construit une data URL base64 (format attendu par Mistral).
func dataURL(mime, base64Image string) string {
	return "data:" + mime + ";base64," + base64Image
}
