package main

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

// fakeProvider est un fournisseur contrôlable pour tester le handler isolément.
type fakeProvider struct {
	nm     string
	conf   bool
	result ScanResult
	err    error
}

func (f fakeProvider) name() string     { return f.nm }
func (f fakeProvider) configured() bool { return f.conf }
func (f fakeProvider) scan(_ context.Context, _, _ string) (ScanResult, error) {
	return f.result, f.err
}

func newTestServer(providers ...scanProvider) *server {
	reg := map[string]scanProvider{}
	for _, p := range providers {
		reg[p.name()] = p
	}
	return &server{
		logger:        slog.New(slog.NewTextHandler(io.Discard, nil)),
		scanProviders: reg,
	}
}

func postScan(t *testing.T, srv *server, body string, headers map[string]string) *httptest.ResponseRecorder {
	t.Helper()
	req := httptest.NewRequest(http.MethodPost, "/v1/scan", strings.NewReader(body))
	for k, v := range headers {
		req.Header.Set(k, v)
	}
	rec := httptest.NewRecorder()
	srv.handleScan(rec, req)
	return rec
}

func TestHandleScanRejectsBadSecret(t *testing.T) {
	t.Setenv("CAVEOS_SCAN_KEY", "topsecret")
	srv := newTestServer(fakeProvider{nm: "mistral", conf: true})

	rec := postScan(t, srv, `{"provider":"mistral","image":"abc"}`, nil)
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("attendu 401, obtenu %d", rec.Code)
	}

	rec = postScan(t, srv, `{"provider":"mistral","image":"abc"}`,
		map[string]string{"X-CaveOS-Key": "topsecret"})
	if rec.Code != http.StatusOK {
		t.Fatalf("avec le bon secret, attendu 200, obtenu %d", rec.Code)
	}
}

// Le champ "provider" est déprécié et ignoré : un ancien client qui l'envoie (ou
// envoie une valeur inconnue) déclenche quand même la passe 1 et obtient 200.
func TestHandleScanIgnoresProviderField(t *testing.T) {
	srv := newTestServer(fakeProvider{nm: "mistral", conf: true})
	rec := postScan(t, srv, `{"provider":"openai","image":"abc"}`, nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("attendu 200 (provider ignoré), obtenu %d", rec.Code)
	}
}

// Aucun fournisseur de lecture configuré ⇒ 503.
func TestHandleScanNoProviderConfigured(t *testing.T) {
	srv := newTestServer(fakeProvider{nm: "gemini", conf: false})
	rec := postScan(t, srv, `{"image":"abc"}`, nil)
	if rec.Code != http.StatusServiceUnavailable {
		t.Fatalf("attendu 503, obtenu %d", rec.Code)
	}
}

func TestHandleScanMissingImage(t *testing.T) {
	srv := newTestServer(fakeProvider{nm: "mistral", conf: true})
	rec := postScan(t, srv, `{"provider":"mistral","image":""}`, nil)
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("attendu 400, obtenu %d", rec.Code)
	}
}

// Deux fournisseurs en succès ⇒ provider concaténé "mistral+gemini".
func TestHandleScanSuccessSetsProvider(t *testing.T) {
	srv := newTestServer(
		fakeProvider{nm: "mistral", conf: true, result: ScanResult{Producer: "Château Test"}},
		fakeProvider{nm: "gemini", conf: true, result: ScanResult{Producer: "Château Test"}},
	)
	rec := postScan(t, srv, `{"image":"abc"}`, nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("attendu 200, obtenu %d", rec.Code)
	}
	var got ScanResult
	if err := json.Unmarshal(rec.Body.Bytes(), &got); err != nil {
		t.Fatalf("réponse illisible: %v", err)
	}
	if got.Provider != "mistral+gemini" || got.Producer != "Château Test" {
		t.Fatalf("résultat inattendu: %+v", got)
	}
}

// La passe 1 fusionne les champs complémentaires des deux fournisseurs et
// concatène les noms. Millésime 0 ⇒ la passe 2 locale (DB) est court-circuitée.
func TestHandleScanRunsBothProviders(t *testing.T) {
	srv := newTestServer(
		fakeProvider{nm: "mistral", conf: true, result: ScanResult{
			Producer: "Château Margaux", Grapes: []string{"Merlot"},
		}},
		fakeProvider{nm: "gemini", conf: true, result: ScanResult{
			Appellation: "Margaux", Grapes: []string{"Cabernet Sauvignon"},
		}},
	)
	rec := postScan(t, srv, `{"image":"abc"}`, nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("attendu 200, obtenu %d", rec.Code)
	}
	var got ScanResult
	if err := json.Unmarshal(rec.Body.Bytes(), &got); err != nil {
		t.Fatalf("réponse illisible: %v", err)
	}
	if got.Provider != "mistral+gemini" {
		t.Fatalf("provider attendu mistral+gemini, obtenu %q", got.Provider)
	}
	if got.Producer != "Château Margaux" || got.Appellation != "Margaux" {
		t.Fatalf("fusion incomplète: %+v", got)
	}
	if len(got.Grapes) != 2 {
		t.Fatalf("union des cépages attendue (2), obtenu %v", got.Grapes)
	}
}

// Un fournisseur échoue, l'autre réussit ⇒ 200 avec les données du survivant et
// son nom seul dans provider.
func TestHandleScanOneProviderFails(t *testing.T) {
	srv := newTestServer(
		fakeProvider{nm: "mistral", conf: true, err: errors.New("OCR indisponible")},
		fakeProvider{nm: "gemini", conf: true, result: ScanResult{Producer: "Domaine Survivant"}},
	)
	rec := postScan(t, srv, `{"image":"abc"}`, nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("attendu 200, obtenu %d", rec.Code)
	}
	var got ScanResult
	if err := json.Unmarshal(rec.Body.Bytes(), &got); err != nil {
		t.Fatalf("réponse illisible: %v", err)
	}
	if got.Provider != "gemini" || got.Producer != "Domaine Survivant" {
		t.Fatalf("résultat inattendu: %+v", got)
	}
}

// Tous les fournisseurs configurés échouent ⇒ 502.
func TestHandleScanBothFail(t *testing.T) {
	srv := newTestServer(
		fakeProvider{nm: "mistral", conf: true, err: errors.New("boom")},
		fakeProvider{nm: "gemini", conf: true, err: errors.New("boom")},
	)
	rec := postScan(t, srv, `{"image":"abc"}`, nil)
	if rec.Code != http.StatusBadGateway {
		t.Fatalf("attendu 502, obtenu %d", rec.Code)
	}
}

// Handler double-passe complet : la passe 2 enrichit la réponse JSON avec les
// champs déduits et inferredFields. Utilise newTestServerFull + fakeEnrichProvider
// (helpers définis dans scan_enrich_test.go). Vintage 0 ⇒ pas d'accès DB.
func TestHandleScanIncludesInferredFields(t *testing.T) {
	srv := newTestServerFull(
		[]scanProvider{
			fakeProvider{nm: "mistral", conf: true, result: ScanResult{Producer: "Domaine X"}},
			fakeProvider{nm: "gemini", conf: true, result: ScanResult{Producer: "Domaine X"}},
		},
		[]enrichProvider{fakeEnrichProvider{
			nm: "gemini", conf: true,
			out: enrichOutput{Color: "red", Region: "Bordeaux"},
		}},
	)
	rec := postScan(t, srv, `{"image":"abc"}`, nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("attendu 200, obtenu %d", rec.Code)
	}
	var got ScanResult
	if err := json.Unmarshal(rec.Body.Bytes(), &got); err != nil {
		t.Fatalf("réponse illisible: %v", err)
	}
	if got.Provider != "mistral+gemini" || got.Color != "red" || got.Region != "Bordeaux" {
		t.Fatalf("résultat double-passe inattendu: %+v", got)
	}
	if !containsString(got.InferredFields, "color") || !containsString(got.InferredFields, "region") {
		t.Fatalf("inferredFields incomplet: %v", got.InferredFields)
	}
}

func TestMistralProviderScan(t *testing.T) {
	ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if got := r.Header.Get("Authorization"); got != "Bearer test-key" {
			t.Errorf("Authorization manquant/incorrect: %q", got)
		}
		annotation := `{"producer":"Château Margaux","wineName":"Pavillon Rouge","vintage":2015,` +
			`"appellation":"Margaux","grapes":["Cabernet Sauvignon","Merlot"],"format":"75 cl","abv":"13,5 %"}`
		resp, _ := json.Marshal(mistralOCRResponse{DocumentAnnotation: annotation})
		w.Write(resp)
	}))
	defer ts.Close()

	p := &mistralProvider{apiKey: "test-key", model: "mistral-ocr-latest", baseURL: ts.URL}
	got, err := p.scan(context.Background(), "ZmFrZQ==", "image/jpeg")
	if err != nil {
		t.Fatalf("scan a échoué: %v", err)
	}
	if got.Producer != "Château Margaux" || got.Vintage != 2015 || len(got.Grapes) != 2 {
		t.Fatalf("résultat inattendu: %+v", got)
	}
}

func TestGeminiProviderScan(t *testing.T) {
	ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if got := r.Header.Get("x-goog-api-key"); got != "test-key" {
			t.Errorf("clé API manquante/incorrecte: %q", got)
		}
		if !strings.Contains(r.URL.Path, ":generateContent") {
			t.Errorf("chemin inattendu: %q", r.URL.Path)
		}
		text := `{"producer":"Domaine Test","wineName":"Cuvée IA","vintage":2019,` +
			`"appellation":"Chablis","grapes":["Chardonnay"],"format":"75 cl","abv":"12,5 %"}`
		body := `{"candidates":[{"content":{"parts":[{"text":` + jsonString(text) + `}]}}]}`
		w.Write([]byte(body))
	}))
	defer ts.Close()

	p := &geminiProvider{apiKey: "test-key", model: "gemini-2.5-flash", baseURL: ts.URL}
	got, err := p.scan(context.Background(), "ZmFrZQ==", "image/jpeg")
	if err != nil {
		t.Fatalf("scan a échoué: %v", err)
	}
	if got.WineName != "Cuvée IA" || got.Vintage != 2019 || got.Appellation != "Chablis" {
		t.Fatalf("résultat inattendu: %+v", got)
	}
}

// jsonString encode une chaîne en littéral JSON (guillemets + échappements).
func jsonString(s string) string {
	b, _ := json.Marshal(s)
	return string(b)
}

func TestDecodeAILabelTolerant(t *testing.T) {
	cases := map[string]string{
		"nu":             `{"producer":"A","vintage":2010,"grapes":["X"]}`,
		"fence markdown": "```json\n{\"producer\":\"A\",\"vintage\":2010,\"grapes\":[\"X\"]}\n```",
		"vintage chaîne": `{"producer":"A","vintage":"2010","grapes":["X"]}`,
		"vintage float":  `{"producer":"A","vintage":2010.0,"grapes":["X"]}`,
	}
	for label, in := range cases {
		got, err := decodeAILabel(in)
		if err != nil {
			t.Fatalf("%s: erreur %v", label, err)
		}
		if got.Producer != "A" || got.Vintage != 2010 || len(got.Grapes) != 1 {
			t.Fatalf("%s: résultat inattendu %+v", label, got)
		}
	}
}

func TestParseVintage(t *testing.T) {
	cases := map[string]int{
		"2015":   2015,
		"2015.0": 2015,
		"":       0,
		"N/A":    0,
		"1700":   0, // hors plage
		"3000":   0, // futur improbable
	}
	for in, want := range cases {
		if got := parseVintage(in); got != want {
			t.Errorf("parseVintage(%q) = %d, attendu %d", in, got, want)
		}
	}
}

func TestRateLimiter(t *testing.T) {
	l := newRateLimiter(2, time.Minute)
	if !l.allow("ip") || !l.allow("ip") {
		t.Fatal("les 2 premières requêtes doivent passer")
	}
	if l.allow("ip") {
		t.Fatal("la 3e requête doit être bloquée")
	}
	if !l.allow("autre-ip") {
		t.Fatal("une autre IP doit avoir son propre quota")
	}
}

func boolPtr(b bool) *bool { return &b }

func TestHandleScanReturnsEmptyWhenNoWineLabel(t *testing.T) {
	// Les deux fournisseurs disent explicitement « pas une étiquette de vin » :
	// le handler doit renvoyer 200 avec un résultat VIDE (anti-hallucination),
	// jamais le vin que le modèle aurait inventé.
	srv := newTestServer(
		fakeProvider{nm: "mistral", conf: true,
			result: ScanResult{Producer: "Château Inventé", Vintage: 2018, IsWineLabel: boolPtr(false)}},
		fakeProvider{nm: "gemini", conf: true,
			result: ScanResult{Producer: "Domaine Hallucination", IsWineLabel: boolPtr(false)}},
	)
	rec := postScan(t, srv, `{"image":"abc"}`, nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("attendu 200, obtenu %d", rec.Code)
	}
	var got ScanResult
	if err := json.Unmarshal(rec.Body.Bytes(), &got); err != nil {
		t.Fatalf("réponse illisible: %v", err)
	}
	if got.Producer != "" || got.Vintage != 0 {
		t.Fatalf("résultat devait être vide (anti-hallucination), obtenu: %+v", got)
	}
}

func TestHandleScanKeepsResultWhenOneProviderSeesLabel(t *testing.T) {
	// Un seul fournisseur reconnaît une étiquette → on garde le résultat fusionné.
	srv := newTestServer(
		fakeProvider{nm: "mistral", conf: true,
			result: ScanResult{Producer: "Château Réel", Vintage: 2015, IsWineLabel: boolPtr(true)}},
		fakeProvider{nm: "gemini", conf: true,
			result: ScanResult{IsWineLabel: boolPtr(false)}},
	)
	rec := postScan(t, srv, `{"image":"abc"}`, nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("attendu 200, obtenu %d", rec.Code)
	}
	var got ScanResult
	_ = json.Unmarshal(rec.Body.Bytes(), &got)
	if got.Producer != "Château Réel" {
		t.Fatalf("résultat réel attendu, obtenu: %+v", got)
	}
}

func TestClientIPUsesRightmostForwarded(t *testing.T) {
	// IP falsifiée en tête par le client ; le proxy de confiance ajoute la vraie à
	// droite. clientIP doit retenir la dernière (réelle), pas la première (spoof).
	req := httptest.NewRequest(http.MethodPost, "/v1/scan", nil)
	req.Header.Set("X-Forwarded-For", "1.2.3.4, 203.0.113.7")
	if got := clientIP(req); got != "203.0.113.7" {
		t.Fatalf("clientIP = %q, attendu 203.0.113.7", got)
	}
}

func TestHandleScanRejectsUnusableImageUpfront(t *testing.T) {
	// Image 1x1 (inexploitable) + garde-fou activé : réponse vide et les
	// fournisseurs ne sont jamais appelés (ni hallucination, ni appel payant).
	srv := newTestServer(
		fakeProvider{nm: "mistral", conf: true, result: ScanResult{Producer: "Château Inventé"}},
	)
	srv.imageUnusable = isUnusableImage
	rec := postScan(t, srv, `{"image":"`+tinyImageB64(t)+`"}`, nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("attendu 200, obtenu %d", rec.Code)
	}
	var got ScanResult
	_ = json.Unmarshal(rec.Body.Bytes(), &got)
	if got.Producer != "" {
		t.Fatalf("résultat devait être vide (garde-fou image), obtenu: %+v", got)
	}
}
