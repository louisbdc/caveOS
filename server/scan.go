package main

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
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

// --- Scan: extraction structurée d'étiquette par double passe IA --------------
//
// L'endpoint POST /v1/scan reçoit une image (base64) et lance EN PARALLÈLE tous
// les fournisseurs de lecture configurés (passe 1 : Mistral OCR + Gemini). Les
// résultats sont fusionnés champ par champ, puis une passe 2 (modèle texte, sans
// image) DÉDUIT les champs absents de l'étiquette (couleur, type, région, pays,
// cépages probables, fenêtre d'apogée). La passe 2 est best-effort : si elle
// échoue, la passe 1 fusionnée est renvoyée telle quelle.
//
// L'ajout d'un fournisseur de lecture se limite à implémenter `scanProvider` et à
// l'enregistrer dans `newScanProviders`.

// ScanResult est la charge utile normalisée renvoyée à l'app. La frontière entre
// champs LUS (passe 1) et champs DÉDUITS (passe 2 / DB locale) est explicite :
// `inferredFields` liste les clés JSON produites par déduction. Les champs vides
// sont omis pour alléger la réponse.
type ScanResult struct {
	// --- LU sur l'étiquette (passe 1, fusion mistral+gemini) -------------
	Producer    string   `json:"producer,omitempty"`
	WineName    string   `json:"wineName,omitempty"`
	Vintage     int      `json:"vintage,omitempty"`
	Appellation string   `json:"appellation,omitempty"`
	Grapes      []string `json:"grapes,omitempty"`
	Format      string   `json:"format,omitempty"`
	ABV         string   `json:"abv,omitempty"`

	// --- DÉDUIT (passe 2 / DB locale, jamais lu directement) ------------
	Color       string   `json:"color,omitempty"`    // red|white|rose|sparkling|sweet|fortified|orange (WineColor.rawValue)
	WineType    string   `json:"wineType,omitempty"` // still|sparkling|fortified|sweet (WineType.rawValue)
	Country     string   `json:"country,omitempty"`
	Region      string   `json:"region,omitempty"`
	GrapesGuess []string `json:"grapesGuess,omitempty"` // cépages PROBABLES de l'appellation (hors `grapes` lus)
	PeakFrom    int      `json:"peakFrom,omitempty"`    // début fenêtre d'apogée (année civile)
	Peak        int      `json:"peak,omitempty"`        // apogée idéale (si fenêtre locale)
	PeakTo      int      `json:"peakTo,omitempty"`      // fin fenêtre d'apogée

	// --- Méta -----------------------------------------------------------
	Provider       string   `json:"provider"`                 // ex. "mistral+gemini"
	InferredFields []string `json:"inferredFields,omitempty"` // clés JSON ci-dessus produites par déduction

	// IsWineLabel : le fournisseur a-t-il reconnu une étiquette de vin lisible ?
	// Interne (jamais sérialisé), sert au garde-fou anti-hallucination du handler.
	// nil = non renseigné par le fournisseur (on suppose alors une étiquette).
	IsWineLabel *bool `json:"-"`
}

// scanRequest est le corps JSON attendu sur POST /v1/scan.
type scanRequest struct {
	// Deprecated: ignoré. On lance toujours tous les fournisseurs configurés
	// (mistral+gemini). Conservé pour la rétro-compatibilité des anciens clients
	// qui envoient encore "provider":"mistral" ; encoding/json ignore de toute
	// façon les clés inconnues.
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
	"appellation, grapes (liste des cépages), format (ex. \"75 cl\", \"Magnum (1,5 L)\"), abv (degré, ex. \"13,5 %\"), " +
	"isWineLabel (true UNIQUEMENT si l'image montre réellement une étiquette de vin lisible). " +
	"Laisse un champ vide (ou 0 pour vintage) si l'information est absente. N'invente jamais de valeur. " +
	"Si l'image est illisible, floue, vide, ou n'est pas une étiquette de vin, mets isWineLabel=false et laisse " +
	"TOUS les autres champs vides — n'invente JAMAIS un vin connu (par ex. ne réponds pas \"Château Margaux\")."

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

// pass1Order fixe l'ordre déterministe des fournisseurs de lecture. Il sert aussi
// de priorité de tie-break dans la fusion (le premier l'emporte à valeur égale) :
// Mistral OCR d'abord car il lit les chiffres et accents littéralement.
var pass1Order = []string{"mistral", "gemini"}

const (
	pass1Timeout = 35 * time.Second // budget par fournisseur image (passe 1)
	pass2Timeout = 12 * time.Second // budget de l'appel texte (passe 2)
	scanBudget   = 50 * time.Second // budget total du handler
)

// errNoScanProvider signale qu'aucun fournisseur de lecture n'est configuré.
var errNoScanProvider = errors.New("aucun fournisseur de scan configuré")

// providerResult porte le résultat (ou l'erreur) d'un fournisseur de la passe 1.
type providerResult struct {
	name   string
	result ScanResult
	err    error
}

// handleScan traite POST /v1/scan : vérifie le secret partagé, limite le débit,
// lance la passe 1 en parallèle, fusionne, applique la passe 2 (best-effort) et
// renvoie le résultat normalisé. Le champ req.Provider est ignoré (déprécié).
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

	// Garde-fou anti-hallucination en amont : une image minuscule, vide ou unie
	// fait inventer un vin connu aux modèles (et ils s'en disent confiants). On
	// répond directement un résultat vide, sans appel upstream.
	if s.imageUnusable != nil && s.imageUnusable(req.Image) {
		s.logger.Info("scan: image inexploitable (trop petite ou unie) — analyse ignorée")
		writeJSON(w, http.StatusOK, ScanResult{})
		return
	}

	ctx, cancel := context.WithTimeout(r.Context(), scanBudget)
	defer cancel()

	// --- PASSE 1 (parallèle) ---
	pass1, err := s.runPass1(ctx, req.Image, mime)
	if errors.Is(err, errNoScanProvider) {
		writeError(w, http.StatusServiceUnavailable, "le scan IA n'est pas configuré sur le serveur")
		return
	}

	ok := make([]ScanResult, 0, len(pass1))
	var failed []string
	for _, pr := range pass1 {
		if pr.err != nil {
			failed = append(failed, pr.name)
			s.logger.Warn("scan provider failed", "provider", pr.name, "error", pr.err)
			continue
		}
		ok = append(ok, pr.result)
	}
	if len(ok) == 0 {
		writeError(w, http.StatusBadGateway, "le scan IA n'a pas pu analyser l'image")
		return
	}
	// --- Garde-fou anti-hallucination ---
	// Si AUCUN fournisseur n'a reconnu une étiquette de vin lisible (tous renvoient
	// explicitement isWineLabel=false), on ne renvoie pas un vin inventé : on répond
	// un résultat vide et l'app affiche « aucune information détectée ».
	names := make([]string, 0, len(ok))
	labelSeen := false
	for _, r := range ok {
		names = append(names, r.Provider)
		if r.IsWineLabel == nil || *r.IsWineLabel {
			labelSeen = true
		}
	}
	provider := strings.Join(names, "+")
	if !labelSeen {
		s.logger.Info("scan: aucune étiquette de vin lisible détectée", "providers", provider)
		writeJSON(w, http.StatusOK, ScanResult{Provider: provider})
		return
	}

	result := mergePass1(ok) // result.Provider = "mistral+gemini" (ou le survivant)

	// --- PASSE 2 (best-effort, ne renvoie jamais d'erreur) ---
	result = s.applyPass2(ctx, result)

	// Trace non sensible : ni l'image ni le texte d'étiquette ne sont journalisés.
	s.logger.Info("scan ok",
		"providers", result.Provider,
		"degraded", len(failed) > 0,
		"vintage", result.Vintage,
		"hasProducer", result.Producer != "",
		"color", result.Color,
		"inferred", len(result.InferredFields),
	)
	writeJSON(w, http.StatusOK, result)
}

// runPass1 lance en parallèle tous les fournisseurs de lecture configurés (selon
// pass1Order) et renvoie un résultat par fournisseur. Chaque goroutine écrit dans
// son propre index out[i] : aucune course. La fusion se fait après wg.Wait().
// Renvoie errNoScanProvider si aucun fournisseur n'est configuré.
func (s *server) runPass1(ctx context.Context, image, mime string) ([]providerResult, error) {
	providers := make([]scanProvider, 0, len(pass1Order))
	for _, n := range pass1Order {
		if p, ok := s.scanProviders[n]; ok && p.configured() {
			providers = append(providers, p)
		}
	}
	if len(providers) == 0 {
		return nil, errNoScanProvider
	}

	out := make([]providerResult, len(providers))
	var wg sync.WaitGroup
	for i, p := range providers {
		wg.Add(1)
		go func(i int, p scanProvider) {
			defer wg.Done()
			pctx, cancel := context.WithTimeout(ctx, pass1Timeout)
			defer cancel()
			res, err := p.scan(pctx, image, mime)
			res.Provider = p.name()
			out[i] = providerResult{name: p.name(), result: res, err: err}
		}(i, p)
	}
	wg.Wait()
	return out, nil
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
	// Derrière notre unique reverse-proxy de confiance : on prend la DERNIÈRE entrée
	// de X-Forwarded-For (celle ajoutée par le proxy = l'IP réellement vue par lui).
	// Les entrées de gauche sont fournies par le client, donc falsifiables : les lire
	// laisserait contourner le rate-limit en variant l'en-tête à chaque requête.
	if fwd := r.Header.Get("X-Forwarded-For"); fwd != "" {
		parts := strings.Split(fwd, ",")
		if last := strings.TrimSpace(parts[len(parts)-1]); last != "" {
			return last
		}
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

// scanLimiter : 12 scans IA par minute et par IP. Abaissé de 20 à 12 car chaque
// scan déclenche désormais 3 appels upstream payants (2 OCR passe 1 + 1 texte
// passe 2) et reste une action volontaire mono-photo (pas de scan continu).
var scanLimiter = newRateLimiter(12, time.Minute)

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
	IsWineLabel *bool    `json:"isWineLabel"`
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
		IsWineLabel: l.IsWineLabel,
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
