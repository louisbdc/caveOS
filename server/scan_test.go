package main

import (
	"context"
	"encoding/json"
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

func TestHandleScanUnknownProvider(t *testing.T) {
	srv := newTestServer(fakeProvider{nm: "mistral", conf: true})
	rec := postScan(t, srv, `{"provider":"openai","image":"abc"}`, nil)
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("attendu 400, obtenu %d", rec.Code)
	}
}

func TestHandleScanProviderNotConfigured(t *testing.T) {
	srv := newTestServer(fakeProvider{nm: "gemini", conf: false})
	rec := postScan(t, srv, `{"provider":"gemini","image":"abc"}`, nil)
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

func TestHandleScanSuccessSetsProvider(t *testing.T) {
	srv := newTestServer(fakeProvider{
		nm: "mistral", conf: true,
		result: ScanResult{Producer: "Château Test", Vintage: 2015},
	})
	rec := postScan(t, srv, `{"provider":"mistral","image":"abc"}`, nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("attendu 200, obtenu %d", rec.Code)
	}
	var got ScanResult
	if err := json.Unmarshal(rec.Body.Bytes(), &got); err != nil {
		t.Fatalf("réponse illisible: %v", err)
	}
	if got.Provider != "mistral" || got.Producer != "Château Test" || got.Vintage != 2015 {
		t.Fatalf("résultat inattendu: %+v", got)
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
