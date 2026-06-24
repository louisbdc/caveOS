package main

import (
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"strconv"
	"strings"
	"time"

	_ "modernc.org/sqlite"
)

const (
	dbFile   = "wine.db"
	seedFile = "seed.json"
)

// --- Domain types -----------------------------------------------------------

// Grape is a grape variety with its estimated ageing window (years after vintage).
type Grape struct {
	Name       string `json:"name"`
	Color      string `json:"color"`
	ApogeeMin  int    `json:"apogeeMin"`
	ApogeePeak int    `json:"apogeePeak"`
	ApogeeMax  int    `json:"apogeeMax"`
}

// Region is a wine region with a quality tier (1=basic .. 3=premium) used as a
// longevity multiplier in the enrichment heuristic.
type Region struct {
	Name        string `json:"name"`
	Country     string `json:"country"`
	QualityTier int    `json:"qualityTier"`
}

// Appellation belongs to a region.
type Appellation struct {
	Name       string `json:"name"`
	RegionName string `json:"regionName"`
}

type seedData struct {
	Grapes       []Grape       `json:"grapes"`
	Regions      []Region      `json:"regions"`
	Appellations []Appellation `json:"appellations"`
}

// SearchResult is the payload for /v1/wines/search.
type SearchResult struct {
	Grapes       []Grape       `json:"grapes"`
	Appellations []Appellation `json:"appellations"`
	Regions      []Region      `json:"regions"`
}

// EnrichResult is the estimated drinking window for /v1/enrich.
type EnrichResult struct {
	Name        string `json:"name"`
	Vintage     int    `json:"vintage"`
	MatchedOn   string `json:"matchedOn"`
	GrapeName   string `json:"grapeName,omitempty"`
	RegionName  string `json:"regionName,omitempty"`
	QualityTier int    `json:"qualityTier,omitempty"`
	DrinkFrom   int    `json:"drinkFrom"`
	Peak        int    `json:"peak"`
	DrinkBy     int    `json:"drinkBy"`
}

// --- Server -----------------------------------------------------------------

type server struct {
	db     *sql.DB
	logger *slog.Logger
}

func main() {
	logger := slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{Level: slog.LevelInfo}))

	db, err := openDB(dbFile)
	if err != nil {
		logger.Error("failed to open database", "error", err)
		os.Exit(1)
	}
	defer db.Close()

	if err := initSchema(db); err != nil {
		logger.Error("failed to init schema", "error", err)
		os.Exit(1)
	}

	if err := seedIfEmpty(db, seedFile, logger); err != nil {
		logger.Error("failed to seed database", "error", err)
		os.Exit(1)
	}

	srv := &server{db: db, logger: logger}

	mux := http.NewServeMux()
	mux.HandleFunc("GET /health", srv.handleHealth)
	mux.HandleFunc("GET /v1/wines/search", srv.handleSearch)
	mux.HandleFunc("GET /v1/grapes", srv.handleGrapes)
	mux.HandleFunc("GET /v1/regions", srv.handleRegions)
	mux.HandleFunc("GET /v1/appellations", srv.handleAppellations)
	mux.HandleFunc("GET /v1/enrich", srv.handleEnrich)
	mux.HandleFunc("GET /v1/db/latest", srv.handleDBLatest)
	mux.HandleFunc("GET /credits", srv.handleCredits)

	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}
	addr := ":" + port

	handler := corsMiddleware(logMiddleware(logger, mux))

	httpSrv := &http.Server{
		Addr:              addr,
		Handler:           handler,
		ReadHeaderTimeout: 10 * time.Second,
		ReadTimeout:       30 * time.Second,
		WriteTimeout:      60 * time.Second,
		IdleTimeout:       120 * time.Second,
	}

	logger.Info("caveos-server starting", "addr", addr)
	if err := httpSrv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
		logger.Error("server stopped", "error", err)
		os.Exit(1)
	}
}

// --- Database ---------------------------------------------------------------

func openDB(path string) (*sql.DB, error) {
	db, err := sql.Open("sqlite", path+"?_pragma=busy_timeout(5000)&_pragma=journal_mode(WAL)")
	if err != nil {
		return nil, fmt.Errorf("open db: %w", err)
	}
	if err := db.Ping(); err != nil {
		return nil, fmt.Errorf("ping db: %w", err)
	}
	return db, nil
}

func initSchema(db *sql.DB) error {
	const ddl = `
CREATE TABLE IF NOT EXISTS grapes (
	name        TEXT PRIMARY KEY,
	color       TEXT NOT NULL,
	apogee_min  INTEGER NOT NULL,
	apogee_peak INTEGER NOT NULL,
	apogee_max  INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS regions (
	name         TEXT PRIMARY KEY,
	country      TEXT NOT NULL,
	quality_tier INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS appellations (
	name        TEXT PRIMARY KEY,
	region_name TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_appellations_region ON appellations(region_name);
`
	if _, err := db.Exec(ddl); err != nil {
		return fmt.Errorf("create schema: %w", err)
	}
	return nil
}

func seedIfEmpty(db *sql.DB, path string, logger *slog.Logger) error {
	var count int
	if err := db.QueryRow("SELECT COUNT(*) FROM grapes").Scan(&count); err != nil {
		return fmt.Errorf("count grapes: %w", err)
	}
	if count > 0 {
		logger.Info("database already seeded", "grapes", count)
		return nil
	}

	raw, err := os.ReadFile(path)
	if err != nil {
		return fmt.Errorf("read seed file %q: %w", path, err)
	}

	var data seedData
	if err := json.Unmarshal(raw, &data); err != nil {
		return fmt.Errorf("parse seed file: %w", err)
	}

	tx, err := db.Begin()
	if err != nil {
		return fmt.Errorf("begin tx: %w", err)
	}
	defer tx.Rollback()

	for _, g := range data.Grapes {
		if _, err := tx.Exec(
			"INSERT INTO grapes(name,color,apogee_min,apogee_peak,apogee_max) VALUES(?,?,?,?,?)",
			g.Name, g.Color, g.ApogeeMin, g.ApogeePeak, g.ApogeeMax,
		); err != nil {
			return fmt.Errorf("insert grape %q: %w", g.Name, err)
		}
	}
	for _, r := range data.Regions {
		if _, err := tx.Exec(
			"INSERT INTO regions(name,country,quality_tier) VALUES(?,?,?)",
			r.Name, r.Country, r.QualityTier,
		); err != nil {
			return fmt.Errorf("insert region %q: %w", r.Name, err)
		}
	}
	for _, a := range data.Appellations {
		if _, err := tx.Exec(
			"INSERT INTO appellations(name,region_name) VALUES(?,?)",
			a.Name, a.RegionName,
		); err != nil {
			return fmt.Errorf("insert appellation %q: %w", a.Name, err)
		}
	}

	if err := tx.Commit(); err != nil {
		return fmt.Errorf("commit seed: %w", err)
	}

	logger.Info("database seeded",
		"grapes", len(data.Grapes),
		"regions", len(data.Regions),
		"appellations", len(data.Appellations),
	)
	return nil
}

// --- Queries ----------------------------------------------------------------

func (s *server) allGrapes() ([]Grape, error) {
	rows, err := s.db.Query("SELECT name,color,apogee_min,apogee_peak,apogee_max FROM grapes ORDER BY name")
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	return scanGrapes(rows)
}

func (s *server) searchGrapes(q string) ([]Grape, error) {
	rows, err := s.db.Query(
		"SELECT name,color,apogee_min,apogee_peak,apogee_max FROM grapes WHERE name LIKE ? ORDER BY name",
		"%"+q+"%",
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	return scanGrapes(rows)
}

func scanGrapes(rows *sql.Rows) ([]Grape, error) {
	grapes := make([]Grape, 0)
	for rows.Next() {
		var g Grape
		if err := rows.Scan(&g.Name, &g.Color, &g.ApogeeMin, &g.ApogeePeak, &g.ApogeeMax); err != nil {
			return nil, err
		}
		grapes = append(grapes, g)
	}
	return grapes, rows.Err()
}

func (s *server) allRegions() ([]Region, error) {
	rows, err := s.db.Query("SELECT name,country,quality_tier FROM regions ORDER BY name")
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	return scanRegions(rows)
}

func (s *server) searchRegions(q string) ([]Region, error) {
	rows, err := s.db.Query(
		"SELECT name,country,quality_tier FROM regions WHERE name LIKE ? OR country LIKE ? ORDER BY name",
		"%"+q+"%", "%"+q+"%",
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	return scanRegions(rows)
}

func scanRegions(rows *sql.Rows) ([]Region, error) {
	regions := make([]Region, 0)
	for rows.Next() {
		var r Region
		if err := rows.Scan(&r.Name, &r.Country, &r.QualityTier); err != nil {
			return nil, err
		}
		regions = append(regions, r)
	}
	return regions, rows.Err()
}

func (s *server) allAppellations() ([]Appellation, error) {
	rows, err := s.db.Query("SELECT name,region_name FROM appellations ORDER BY name")
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	return scanAppellations(rows)
}

func (s *server) searchAppellations(q string) ([]Appellation, error) {
	rows, err := s.db.Query(
		"SELECT name,region_name FROM appellations WHERE name LIKE ? OR region_name LIKE ? ORDER BY name",
		"%"+q+"%", "%"+q+"%",
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	return scanAppellations(rows)
}

func scanAppellations(rows *sql.Rows) ([]Appellation, error) {
	apps := make([]Appellation, 0)
	for rows.Next() {
		var a Appellation
		if err := rows.Scan(&a.Name, &a.RegionName); err != nil {
			return nil, err
		}
		apps = append(apps, a)
	}
	return apps, rows.Err()
}

// regionByName returns the region or sql.ErrNoRows.
func (s *server) regionByName(name string) (Region, error) {
	var r Region
	err := s.db.QueryRow(
		"SELECT name,country,quality_tier FROM regions WHERE name = ?", name,
	).Scan(&r.Name, &r.Country, &r.QualityTier)
	return r, err
}

// --- Handlers ---------------------------------------------------------------

func (s *server) handleHealth(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

func (s *server) handleSearch(w http.ResponseWriter, r *http.Request) {
	q := strings.TrimSpace(r.URL.Query().Get("q"))
	if q == "" {
		writeError(w, http.StatusBadRequest, "missing query parameter 'q'")
		return
	}

	grapes, err := s.searchGrapes(q)
	if err != nil {
		s.serverError(w, "search grapes", err)
		return
	}
	apps, err := s.searchAppellations(q)
	if err != nil {
		s.serverError(w, "search appellations", err)
		return
	}
	regions, err := s.searchRegions(q)
	if err != nil {
		s.serverError(w, "search regions", err)
		return
	}

	writeJSON(w, http.StatusOK, SearchResult{
		Grapes:       grapes,
		Appellations: apps,
		Regions:      regions,
	})
}

func (s *server) handleGrapes(w http.ResponseWriter, _ *http.Request) {
	grapes, err := s.allGrapes()
	if err != nil {
		s.serverError(w, "list grapes", err)
		return
	}
	writeJSON(w, http.StatusOK, grapes)
}

func (s *server) handleRegions(w http.ResponseWriter, _ *http.Request) {
	regions, err := s.allRegions()
	if err != nil {
		s.serverError(w, "list regions", err)
		return
	}
	writeJSON(w, http.StatusOK, regions)
}

func (s *server) handleAppellations(w http.ResponseWriter, _ *http.Request) {
	apps, err := s.allAppellations()
	if err != nil {
		s.serverError(w, "list appellations", err)
		return
	}
	writeJSON(w, http.StatusOK, apps)
}

func (s *server) handleEnrich(w http.ResponseWriter, r *http.Request) {
	name := strings.TrimSpace(r.URL.Query().Get("name"))
	if name == "" {
		writeError(w, http.StatusBadRequest, "missing query parameter 'name'")
		return
	}

	vintageStr := strings.TrimSpace(r.URL.Query().Get("vintage"))
	vintage, err := strconv.Atoi(vintageStr)
	if err != nil || vintage < 1900 || vintage > time.Now().Year()+1 {
		writeError(w, http.StatusBadRequest, "invalid or missing 'vintage' (expected a 4-digit year)")
		return
	}

	result, err := s.enrich(name, vintage)
	if err != nil {
		if errors.Is(err, errNoMatch) {
			writeError(w, http.StatusNotFound, "no grape or region matched the given name")
			return
		}
		s.serverError(w, "enrich", err)
		return
	}

	writeJSON(w, http.StatusOK, result)
}

func (s *server) handleDBLatest(w http.ResponseWriter, r *http.Request) {
	info, err := os.Stat(dbFile)
	if err != nil {
		s.serverError(w, "stat db file", err)
		return
	}
	w.Header().Set("Content-Type", "application/octet-stream")
	w.Header().Set("Content-Disposition", `attachment; filename="wine.db"`)
	w.Header().Set("Content-Length", strconv.FormatInt(info.Size(), 10))
	http.ServeFile(w, r, dbFile)
}

func (s *server) handleCredits(w http.ResponseWriter, _ *http.Request) {
	const credits = `caveOS — Data Attribution & Licences

Wine reference data in this service is derived from openly-licensed sources:

  • Wikidata — grape varieties, regions, appellations
    Licence: CC0 1.0 (public domain dedication)
    https://www.wikidata.org/

  • INAO (Institut national de l'origine et de la qualité) — French AOC/AOP appellations
    Licence: Licence Ouverte / Open Licence (Etalab)
    https://www.inao.gouv.fr/

  • LWIN (Liv-ex Wine Identification Number) — wine naming reference
    Licence: Creative Commons (CC)
    https://www.liv-ex.com/lwin/

This service ("caveos-server") and its derived database are provided as-is.
Apogee/drinking-window estimates are heuristic and for guidance only.
`
	w.Header().Set("Content-Type", "text/plain; charset=utf-8")
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write([]byte(credits))
}

// --- Enrichment heuristic ---------------------------------------------------

var errNoMatch = errors.New("no match")

// tierMultiplier maps a region quality tier to a longevity multiplier applied
// to the grape's ageing window. This mirrors the heuristic used in the iOS app.
func tierMultiplier(tier int) float64 {
	switch tier {
	case 3:
		return 1.3
	case 2:
		return 1.1
	case 1:
		return 0.9
	default:
		return 1.0
	}
}

// enrich estimates a drinking window for a wine named `name` of the given
// vintage. It first tries to match an appellation (-> its region) or a region
// directly, then matches a grape; the grape's min/peak/max ageing years are
// scaled by the region quality-tier multiplier and added to the vintage.
func (s *server) enrich(name string, vintage int) (EnrichResult, error) {
	lower := strings.ToLower(name)

	region, matchedRegion := s.matchRegion(lower)
	grape, matchedGrape := s.matchGrape(lower)

	if !matchedGrape {
		// Fall back to a sensible default ageing window when no grape is found
		// but a region/appellation is. Use medium-bodied red defaults.
		if matchedRegion {
			grape = Grape{Name: "", ApogeeMin: 3, ApogeePeak: 8, ApogeeMax: 15}
		} else {
			return EnrichResult{}, errNoMatch
		}
	}

	mult := tierMultiplier(region.QualityTier)
	if !matchedRegion {
		mult = 1.0
	}

	from := vintage + scale(grape.ApogeeMin, mult)
	peak := vintage + scale(grape.ApogeePeak, mult)
	by := vintage + scale(grape.ApogeeMax, mult)

	matchedOn := "grape"
	switch {
	case matchedGrape && matchedRegion:
		matchedOn = "grape+region"
	case matchedRegion:
		matchedOn = "region"
	}

	return EnrichResult{
		Name:        name,
		Vintage:     vintage,
		MatchedOn:   matchedOn,
		GrapeName:   grape.Name,
		RegionName:  region.Name,
		QualityTier: region.QualityTier,
		DrinkFrom:   from,
		Peak:        peak,
		DrinkBy:     by,
	}, nil
}

func scale(years int, mult float64) int {
	return int(float64(years)*mult + 0.5)
}

// matchRegion resolves a region from a lowercased wine name by checking
// appellations first (returning the parent region) then regions directly.
func (s *server) matchRegion(lower string) (Region, bool) {
	apps, err := s.allAppellations()
	if err == nil {
		for _, a := range apps {
			if strings.Contains(lower, strings.ToLower(a.Name)) {
				if region, err := s.regionByName(a.RegionName); err == nil {
					return region, true
				}
			}
		}
	}

	regions, err := s.allRegions()
	if err == nil {
		for _, r := range regions {
			if strings.Contains(lower, strings.ToLower(r.Name)) {
				return r, true
			}
		}
	}
	return Region{}, false
}

// matchGrape resolves a grape variety from a lowercased wine name.
func (s *server) matchGrape(lower string) (Grape, bool) {
	grapes, err := s.allGrapes()
	if err != nil {
		return Grape{}, false
	}
	for _, g := range grapes {
		if strings.Contains(lower, strings.ToLower(g.Name)) {
			return g, true
		}
	}
	return Grape{}, false
}

// --- Middleware & helpers ---------------------------------------------------

func corsMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.Header().Set("Access-Control-Allow-Methods", "GET, OPTIONS")
		w.Header().Set("Access-Control-Allow-Headers", "Content-Type")
		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusNoContent)
			return
		}
		next.ServeHTTP(w, r)
	})
}

type statusRecorder struct {
	http.ResponseWriter
	status int
}

func (rec *statusRecorder) WriteHeader(code int) {
	rec.status = code
	rec.ResponseWriter.WriteHeader(code)
}

func logMiddleware(logger *slog.Logger, next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		rec := &statusRecorder{ResponseWriter: w, status: http.StatusOK}
		next.ServeHTTP(rec, r)
		logger.Info("request",
			"method", r.Method,
			"path", r.URL.Path,
			"query", r.URL.RawQuery,
			"status", rec.status,
			"duration_ms", time.Since(start).Milliseconds(),
			"remote", r.RemoteAddr,
		)
	})
}

func (s *server) serverError(w http.ResponseWriter, op string, err error) {
	s.logger.Error("internal error", "op", op, "error", err)
	writeError(w, http.StatusInternalServerError, "internal server error")
}

func writeJSON(w http.ResponseWriter, status int, payload any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	if err := json.NewEncoder(w).Encode(payload); err != nil {
		// Response is already partially written; nothing actionable remains.
		return
	}
}

func writeError(w http.ResponseWriter, status int, msg string) {
	writeJSON(w, status, map[string]string{"error": msg})
}
