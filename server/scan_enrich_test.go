package main

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
)

// fakeEnrichProvider est un fournisseur de passe 2 contrôlable. Défini ici une
// seule fois ; scan_test.go le réutilise (pas de duplication de helper).
type fakeEnrichProvider struct {
	nm   string
	conf bool
	out  enrichOutput
	err  error
}

func (f fakeEnrichProvider) name() string     { return f.nm }
func (f fakeEnrichProvider) configured() bool { return f.conf }
func (f fakeEnrichProvider) enrich(_ context.Context, _ enrichInput) (enrichOutput, error) {
	return f.out, f.err
}

// newTestServerFull construit un serveur avec fournisseurs de lecture ET de
// déduction injectés. La DB reste nil : les tests qui exercent localWindow
// passent par newSeededServer.
func newTestServerFull(scan []scanProvider, enrich []enrichProvider) *server {
	reg := map[string]scanProvider{}
	order := make([]string, 0, len(scan))
	for _, p := range scan {
		reg[p.name()] = p
		order = append(order, p.name())
	}
	return &server{
		logger:          slog.New(slog.NewTextHandler(io.Discard, nil)),
		scanProviders:   reg,
		enrichProviders: enrich,
		pass1Order:      order,
	}
}

// newSeededServer ajoute une DB temporaire seedée (région Bordeaux, appellation
// Margaux) pour tester la réconciliation localWindow.
func newSeededServer(t *testing.T, enrich ...enrichProvider) *server {
	t.Helper()
	db, err := openDB(filepath.Join(t.TempDir(), "test.db"))
	if err != nil {
		t.Fatalf("ouverture db: %v", err)
	}
	t.Cleanup(func() { _ = db.Close() })
	if err := initSchema(db); err != nil {
		t.Fatalf("schéma: %v", err)
	}
	if _, err := db.Exec("INSERT INTO regions(name,country,quality_tier) VALUES(?,?,?)", "Bordeaux", "France", 2); err != nil {
		t.Fatalf("seed region: %v", err)
	}
	if _, err := db.Exec("INSERT INTO appellations(name,region_name) VALUES(?,?)", "Margaux", "Bordeaux"); err != nil {
		t.Fatalf("seed appellation: %v", err)
	}
	srv := newTestServerFull(nil, enrich)
	srv.db = db
	return srv
}

// containsString est un petit utilitaire de test partagé.
func containsString(list []string, want string) bool {
	for _, v := range list {
		if v == want {
			return true
		}
	}
	return false
}

func TestApplyPass2MarksInferred(t *testing.T) {
	srv := newTestServerFull(nil, []enrichProvider{fakeEnrichProvider{
		nm: "gemini", conf: true,
		out: enrichOutput{
			Color:       "red",
			Region:      "Bordeaux",
			GrapesGuess: []string{"Merlot"},
			PeakFrom:    2024,
			PeakTo:      2035,
		},
	}})
	// Vintage 0 ⇒ localWindow court-circuité (pas de DB).
	in := ScanResult{Producer: "Château X", Grapes: []string{"Cabernet Sauvignon"}}
	got := srv.applyPass2(context.Background(), in)

	if got.Color != "red" || got.Region != "Bordeaux" || got.PeakFrom != 2024 || got.PeakTo != 2035 {
		t.Fatalf("champs déduits inattendus: %+v", got)
	}
	if !reflect.DeepEqual(got.GrapesGuess, []string{"Merlot"}) {
		t.Fatalf("grapesGuess inattendu: %v", got.GrapesGuess)
	}
	want := []string{"color", "grapesGuess", "peakFrom", "peakTo", "region"}
	if !reflect.DeepEqual(got.InferredFields, want) {
		t.Fatalf("inferredFields=%v, attendu %v", got.InferredFields, want)
	}
	// Aucun champ LU ne doit jamais figurer comme inféré.
	for _, lu := range []string{"producer", "wineName", "vintage", "appellation", "grapes", "format", "abv"} {
		if containsString(got.InferredFields, lu) {
			t.Fatalf("champ LU %q marqué inféré à tort", lu)
		}
	}
	if got.Producer != "Château X" {
		t.Fatalf("champ LU producer altéré: %q", got.Producer)
	}
}

func TestPass2GracefulWhenDown(t *testing.T) {
	srv := newTestServerFull(nil, []enrichProvider{
		fakeEnrichProvider{nm: "gemini", conf: true, err: errors.New("indisponible")},
	})
	in := ScanResult{Producer: "Château X", Grapes: []string{"Cabernet Sauvignon"}}
	got := srv.applyPass2(context.Background(), in)

	if got.Producer != "Château X" {
		t.Fatalf("les champs lus doivent être préservés: %+v", got)
	}
	if got.Color != "" || got.Region != "" {
		t.Fatalf("aucune déduction attendue: %+v", got)
	}
	if len(got.InferredFields) != 0 {
		t.Fatalf("inferredFields doit être vide: %v", got.InferredFields)
	}
}

func TestPass2FallbackToSecondary(t *testing.T) {
	srv := newTestServerFull(nil, []enrichProvider{
		fakeEnrichProvider{nm: "gemini", conf: true, err: errors.New("primaire KO")},
		fakeEnrichProvider{nm: "mistral", conf: true, out: enrichOutput{Color: "white"}},
	})
	got := srv.applyPass2(context.Background(), ScanResult{WineName: "Test"})
	if got.Color != "white" {
		t.Fatalf("repli non utilisé: %+v", got)
	}
	if !containsString(got.InferredFields, "color") {
		t.Fatalf("color doit être marqué inféré: %v", got.InferredFields)
	}
}

func TestSubtractGrapesGuess(t *testing.T) {
	got := subtract(
		[]string{"Merlot", "Cabernet Sauvignon", "merlot", "Petit Verdot", " "},
		[]string{"merlot"},
	)
	want := []string{"Cabernet Sauvignon", "Petit Verdot"}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("subtract=%v, attendu %v", got, want)
	}
}

func TestKeepIfEnum(t *testing.T) {
	cases := []struct {
		v    string
		set  map[string]bool
		want string
	}{
		{"Red", wineColors, "red"}, // normalise la casse
		{"  white ", wineColors, "white"},
		{"purple", wineColors, ""}, // hors-liste
		{"rosé", wineColors, ""},   // accentué hors-liste (l'enum est "rose")
		{"STILL", wineTypes, "still"},
		{"frizzante", wineTypes, ""}, // hors-liste
	}
	for _, c := range cases {
		if got := keepIfEnum(c.v, c.set); got != c.want {
			t.Errorf("keepIfEnum(%q)=%q, attendu %q", c.v, got, c.want)
		}
	}
}

func TestLocalWindowOverridesLLM(t *testing.T) {
	srv := newSeededServer(t, fakeEnrichProvider{
		nm: "gemini", conf: true,
		out: enrichOutput{Region: "Région LLM", Country: "Pays LLM", PeakFrom: 2000, PeakTo: 2001},
	})
	got := srv.applyPass2(context.Background(), ScanResult{Appellation: "Margaux", Vintage: 2015})

	if got.Region != "Bordeaux" {
		t.Errorf("région DB attendue (Bordeaux), obtenu %q", got.Region)
	}
	if got.Country != "France" {
		t.Errorf("pays DB attendu (France), obtenu %q", got.Country)
	}
	// Aucun cépage matché ⇒ fenêtre rouge moyen par défaut (3/8/15), tier2 ×1.0.
	if got.PeakFrom != 2018 || got.Peak != 2023 || got.PeakTo != 2030 {
		t.Errorf("fenêtre DB inattendue: from=%d peak=%d to=%d", got.PeakFrom, got.Peak, got.PeakTo)
	}
	if !containsString(got.InferredFields, "peak") {
		t.Errorf("peak doit être marqué inféré: %v", got.InferredFields)
	}
}

func TestGeminiEnrichProvider(t *testing.T) {
	ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if got := r.Header.Get("x-goog-api-key"); got != "test-key" {
			t.Errorf("clé API manquante/incorrecte: %q", got)
		}
		if !strings.Contains(r.URL.Path, ":generateContent") {
			t.Errorf("chemin inattendu: %q", r.URL.Path)
		}
		raw, _ := io.ReadAll(r.Body)
		var req geminiRequest
		if err := json.Unmarshal(raw, &req); err != nil {
			t.Fatalf("requête illisible: %v", err)
		}
		if req.GenerationConfig.ThinkingConfig == nil || req.GenerationConfig.ThinkingConfig.ThinkingBudget != 0 {
			t.Errorf("thinkingConfig.thinkingBudget==0 attendu, obtenu %+v", req.GenerationConfig.ThinkingConfig)
		}
		if req.GenerationConfig.ResponseSchema == nil {
			t.Errorf("responseSchema manquant")
		}
		for _, c := range req.Contents {
			for _, p := range c.Parts {
				if p.InlineData != nil {
					t.Errorf("la passe 2 ne doit pas envoyer d'image (inlineData)")
				}
			}
		}
		text := `{"color":"red","wineType":"still","country":"France","region":"Bordeaux",` +
			`"grapesGuess":["Merlot"],"peakFrom":2024,"peakTo":2035}`
		body := `{"candidates":[{"content":{"parts":[{"text":` + jsonString(text) + `}]}}]}`
		w.Write([]byte(body))
	}))
	defer ts.Close()

	p := &geminiEnrichProvider{apiKey: "test-key", model: "gemini-3.1-flash-lite", baseURL: ts.URL}
	got, err := p.enrich(context.Background(), enrichInput{Appellation: "Margaux", Vintage: 2018})
	if err != nil {
		t.Fatalf("enrich a échoué: %v", err)
	}
	if got.Color != "red" || got.Region != "Bordeaux" || got.PeakFrom != 2024 || len(got.GrapesGuess) != 1 {
		t.Fatalf("résultat inattendu: %+v", got)
	}
}

func TestMistralChatEnrichProvider(t *testing.T) {
	ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if got := r.Header.Get("Authorization"); got != "Bearer test-key" {
			t.Errorf("Authorization incorrect: %q", got)
		}
		raw, _ := io.ReadAll(r.Body)
		var body map[string]any
		if err := json.Unmarshal(raw, &body); err != nil {
			t.Fatalf("requête illisible: %v", err)
		}
		rf, _ := body["response_format"].(map[string]any)
		js, _ := rf["json_schema"].(map[string]any)
		if js["strict"] != true {
			t.Errorf("response_format.json_schema.strict==true attendu")
		}
		schema, _ := js["schema"].(map[string]any)
		if schema["additionalProperties"] != false {
			t.Errorf("additionalProperties==false attendu")
		}
		required, _ := schema["required"].([]any)
		if len(required) != 7 {
			t.Errorf("7 champs requis attendus, obtenu %d", len(required))
		}
		content := `{"color":"white","wineType":"still","country":"France","region":"Bourgogne",` +
			`"grapesGuess":["Chardonnay"],"peakFrom":2023,"peakTo":2030}`
		resp := `{"choices":[{"message":{"content":` + jsonString(content) + `}}]}`
		w.Write([]byte(resp))
	}))
	defer ts.Close()

	p := &mistralChatEnrichProvider{apiKey: "test-key", model: "mistral-small-latest", baseURL: ts.URL}
	got, err := p.enrich(context.Background(), enrichInput{Appellation: "Chablis", Vintage: 2020})
	if err != nil {
		t.Fatalf("enrich a échoué: %v", err)
	}
	if got.Color != "white" || got.Region != "Bourgogne" || got.PeakTo != 2030 || len(got.GrapesGuess) != 1 {
		t.Fatalf("résultat inattendu: %+v", got)
	}
}

func TestDecodeEnrichOutputTolerant(t *testing.T) {
	cases := map[string]string{
		"peakFrom chaîne": `{"color":"red","grapesGuess":[],"peakFrom":"2030","peakTo":2040}`,
		"peakFrom float":  `{"color":"red","grapesGuess":[],"peakFrom":2030.0,"peakTo":2040}`,
		"fence markdown":  "```json\n{\"color\":\"red\",\"grapesGuess\":[],\"peakFrom\":2030,\"peakTo\":2040}\n```",
	}
	for label, in := range cases {
		got, err := decodeEnrichOutput(in)
		if err != nil {
			t.Fatalf("%s: erreur %v", label, err)
		}
		if got.PeakFrom != 2030 || got.PeakTo != 2040 || got.Color != "red" {
			t.Fatalf("%s: résultat inattendu %+v", label, got)
		}
	}

	// peakFrom null ⇒ 0 (champ absent).
	got, err := decodeEnrichOutput(`{"color":"red","grapesGuess":[],"peakFrom":null,"peakTo":null}`)
	if err != nil {
		t.Fatalf("null: erreur %v", err)
	}
	if got.PeakFrom != 0 || got.PeakTo != 0 {
		t.Fatalf("null: peak attendu 0, obtenu from=%d to=%d", got.PeakFrom, got.PeakTo)
	}
}
