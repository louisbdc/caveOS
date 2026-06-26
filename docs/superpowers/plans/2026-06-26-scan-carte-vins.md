# Scan de carte des vins — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Photographier la carte des vins d'un restaurant et obtenir, par vin, un score d'accord avec le plat, un signal rapport qualité-prix déterministe, un statut « à boire maintenant » et un croisement avec la cave / les notes perso.

**Architecture:** Nouvel endpoint serveur `POST /v1/scan/list` qui réutilise la passe 1 (Mistral+Gemini) avec un prompt « liste » et la passe 2 d'enrichissement existante (`applyPass2`) en fan-out concurrent ; il renvoie un tableau de vins enrichis. Tous les calculs de conseil (valeur, accord, apogée, croisement cave) sont faits **on-device** à partir des données SwiftData locales. Repli device (Vision OCR) si serveur indisponible.

**Tech Stack:** Go (serveur, `net/http`, tests `testing` table-driven) · Swift / SwiftUI / SwiftData (app iOS) · StoreKit (freemium).

## Global Constraints

- **Immutabilité** : créer de nouveaux objets, jamais muter (règle projet).
- **Fichiers focalisés** : 200–400 lignes typiques, 800 max ; many small files.
- **Pas de `print`/`console.log`** résiduel ; pas de valeurs hardcodées dispersées (constantes nommées).
- **Best-effort serveur** : `/v1/scan/list` ne renvoie jamais 5xx sur le chemin nominal (comme `/v1/scan`).
- **Anti-hallucination** : un signal non fiable est masqué (`unknown`), jamais inventé.
- **Auth** : header `X-CaveOS-Key` vérifié via `checkScanSecret` existant.
- **Freemium** : 1 scan de carte = 1 crédit IA (`StoreManager`, `freeScanLimit = 25`, illimité Pro).
- **Plafond** : `maxListWines = 60`. **Rate-limit liste** : 6 req/min/IP.
- **Commit** : sans ligne d'attribution (attribution désactivée globalement).
- **Réf. spec** : `docs/superpowers/specs/2026-06-26-scan-carte-vins-design.md`.

> Note exécutant : avant d'écrire le code d'une tâche, lire le(s) fichier(s) listés en `Modify` et le fichier voisin nommé en exemple pour copier les conventions réelles (noms exacts, style). Le code des steps montre l'intention et les signatures ; aligne-toi sur l'existant si un détail diffère.

> Commande tests Go : `cd server && go test ./... -run <TestName> -v`.
> Commande tests Swift : `xcodebuild test -scheme CaveOS -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:CaveOSTests/<TestClass>` (ajuster scheme/simulateur au projet).

---

## Phase A — Serveur

### Task 1: Types de réponse liste + garde `isWineList`

**Files:**
- Create: `server/scan_list_types.go`
- Create: `server/scan_list_guard.go`
- Test: `server/scan_list_guard_test.go`

**Interfaces:**
- Consumes: `ScanResult` (existant, `server/scan.go`).
- Produces:
  - `type ScanListItem struct { ScanResult; Price *float64; Currency string; ByGlass bool; PriceGlass *float64; LineIndex int }`
  - `type ScanListResponse struct { Wines []ScanListItem; Count int; Provider string; Truncated bool; NotWineList bool }`
  - `func isWineList(items []ScanListItem) bool`
  - `const maxListWines = 60`

- [ ] **Step 1: Écrire les types (pas de test, scaffolding de la tâche)**

`server/scan_list_types.go` :
```go
package main

const maxListWines = 60

// ScanListItem = un vin lu sur une carte, enrichi comme un scan mono-vin + infos prix.
type ScanListItem struct {
	ScanResult
	Price      *float64 `json:"price,omitempty"`
	Currency   string   `json:"currency,omitempty"`
	ByGlass    bool     `json:"byGlass,omitempty"`
	PriceGlass *float64 `json:"priceGlass,omitempty"`
	LineIndex  int      `json:"lineIndex"`
}

// ScanListResponse = réponse de POST /v1/scan/list.
type ScanListResponse struct {
	Wines       []ScanListItem `json:"wines"`
	Count       int            `json:"count"`
	Provider    string         `json:"provider"`
	Truncated   bool           `json:"truncated,omitempty"`
	NotWineList bool           `json:"notWineList,omitempty"`
}
```

- [ ] **Step 2: Écrire le test de la garde (FAIL)**

`server/scan_list_guard_test.go` :
```go
package main

import "testing"

func TestIsWineList(t *testing.T) {
	cases := []struct {
		name string
		in   []ScanListItem
		want bool
	}{
		{"vide", nil, false},
		{"une entrée sans nom ni producteur", []ScanListItem{{}}, false},
		{
			"deux vins nommés",
			[]ScanListItem{
				{ScanResult: ScanResult{WineName: "Cahors", Producer: "Clos La Coutale"}},
				{ScanResult: ScanResult{WineName: "Chinon"}},
			},
			true,
		},
		{
			"une seule entrée nommée (ressemble à une étiquette, pas une carte)",
			[]ScanListItem{{ScanResult: ScanResult{WineName: "Cahors", Producer: "X"}}},
			false,
		},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			if got := isWineList(c.in); got != c.want {
				t.Fatalf("isWineList = %v, want %v", got, c.want)
			}
		})
	}
}
```

- [ ] **Step 3: Lancer le test (FAIL)**

Run: `cd server && go test ./... -run TestIsWineList -v`
Expected: FAIL — `undefined: isWineList`.

- [ ] **Step 4: Implémenter la garde (PASS)**

`server/scan_list_guard.go` :
```go
package main

// isWineList: heuristique simple — au moins 2 entrées portant un nom ou un producteur.
// Une seule entrée = probablement une étiquette unique, pas une carte.
func isWineList(items []ScanListItem) bool {
	named := 0
	for _, it := range items {
		if it.WineName != "" || it.Producer != "" {
			named++
		}
	}
	return named >= 2
}
```

- [ ] **Step 5: Lancer le test (PASS)**

Run: `cd server && go test ./... -run TestIsWineList -v`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add server/scan_list_types.go server/scan_list_guard.go server/scan_list_guard_test.go
git commit -m "feat(scan): types réponse liste + garde isWineList"
```

---

### Task 2: Parsing de la réponse « liste » (passe 1)

**Files:**
- Create: `server/scan_list_parse.go`
- Test: `server/scan_list_parse_test.go`

**Interfaces:**
- Consumes: `ScanListItem`, `maxListWines` (Task 1).
- Produces:
  - `func parseListPayload(raw []byte) ([]ScanListItem, bool, error)` — retourne (items, truncated, err). Parse le JSON renvoyé par le LLM (`{"wines":[{producer,wineName,vintage,appellation,price,currency,byGlass,priceGlass}]}`), borne à `maxListWines`, affecte `LineIndex` par ordre.

- [ ] **Step 1: Écrire le test (FAIL)**

`server/scan_list_parse_test.go` :
```go
package main

import "testing"

func TestParseListPayload(t *testing.T) {
	raw := []byte(`{"wines":[
		{"producer":"Clos La Coutale","wineName":"Cahors","vintage":2018,"price":38,"currency":"EUR"},
		{"wineName":"Chinon","vintage":2020,"price":34,"byGlass":true,"priceGlass":8}
	]}`)
	items, truncated, err := parseListPayload(raw)
	if err != nil {
		t.Fatalf("err inattendue: %v", err)
	}
	if truncated {
		t.Fatalf("truncated = true, want false")
	}
	if len(items) != 2 {
		t.Fatalf("len = %d, want 2", len(items))
	}
	if items[0].Producer != "Clos La Coutale" || items[0].LineIndex != 0 {
		t.Fatalf("item0 inattendu: %+v", items[0])
	}
	if items[1].LineIndex != 1 || !items[1].ByGlass || items[1].PriceGlass == nil || *items[1].PriceGlass != 8 {
		t.Fatalf("item1 inattendu: %+v", items[1])
	}
}

func TestParseListPayloadTruncates(t *testing.T) {
	// Construit maxListWines+5 entrées.
	b := []byte(`{"wines":[`)
	for i := 0; i < maxListWines+5; i++ {
		if i > 0 {
			b = append(b, ',')
		}
		b = append(b, []byte(`{"wineName":"V"}`)...)
	}
	b = append(b, []byte(`]}`)...)
	items, truncated, err := parseListPayload(b)
	if err != nil {
		t.Fatalf("err: %v", err)
	}
	if !truncated || len(items) != maxListWines {
		t.Fatalf("len=%d truncated=%v, want %d/true", len(items), truncated, maxListWines)
	}
}
```

- [ ] **Step 2: Lancer (FAIL)**

Run: `cd server && go test ./... -run TestParseListPayload -v`
Expected: FAIL — `undefined: parseListPayload`.

- [ ] **Step 3: Implémenter (PASS)**

`server/scan_list_parse.go` :
```go
package main

import "encoding/json"

type listPayload struct {
	Wines []struct {
		Producer    string   `json:"producer"`
		WineName    string   `json:"wineName"`
		Vintage     int      `json:"vintage"`
		Appellation string   `json:"appellation"`
		Grapes      []string `json:"grapes"`
		Price       *float64 `json:"price"`
		Currency    string   `json:"currency"`
		ByGlass     bool     `json:"byGlass"`
		PriceGlass  *float64 `json:"priceGlass"`
	} `json:"wines"`
}

// parseListPayload transforme le JSON LLM en []ScanListItem, borné à maxListWines.
func parseListPayload(raw []byte) ([]ScanListItem, bool, error) {
	var p listPayload
	if err := json.Unmarshal(raw, &p); err != nil {
		return nil, false, err
	}
	truncated := false
	src := p.Wines
	if len(src) > maxListWines {
		src = src[:maxListWines]
		truncated = true
	}
	items := make([]ScanListItem, 0, len(src))
	for i, w := range src {
		items = append(items, ScanListItem{
			ScanResult: ScanResult{
				Producer:    w.Producer,
				WineName:    w.WineName,
				Vintage:     w.Vintage,
				Appellation: w.Appellation,
				Grapes:      w.Grapes,
			},
			Price:      w.Price,
			Currency:   w.Currency,
			ByGlass:    w.ByGlass,
			PriceGlass: w.PriceGlass,
			LineIndex:  i,
		})
	}
	return items, truncated, nil
}
```

- [ ] **Step 4: Lancer (PASS)**

Run: `cd server && go test ./... -run TestParseListPayload -v`
Expected: PASS (les 2 tests).

- [ ] **Step 5: Commit**

```bash
git add server/scan_list_parse.go server/scan_list_parse_test.go
git commit -m "feat(scan): parsing de la réponse liste (passe 1)"
```

---

### Task 3: Handler `/v1/scan/list` + fan-out passe 2 + route + rate-limit

**Files:**
- Create: `server/scan_list.go`
- Modify: `server/main.go` (enregistrement de route + nouveau limiter — lire le fichier pour copier le pattern de `scanLimiter` et de l'enregistrement de `/v1/scan`)
- Test: `server/scan_list_enrich_test.go`

**Interfaces:**
- Consumes: `parseListPayload` (Task 2), `isWineList` (Task 1), `applyPass2` (`server/scan_enrich.go`), `runListPass1` (défini ici), `checkScanSecret` + `scanLimiter` pattern (`server/scan.go`).
- Produces:
  - `func (s *server) handleScanList(w http.ResponseWriter, r *http.Request)`
  - `func enrichListItems(ctx context.Context, s *server, items []ScanListItem) []ScanListItem` — applique `applyPass2` à chaque item en pool borné, best-effort.
  - `var listScanLimiter = newRateLimiter(6, time.Minute)` (adapter au constructeur réel du limiter existant).

> L'appel LLM réel (`runListPass1`) suit le pattern de `runPass1` dans `server/scan.go` mais avec le prompt « liste » ci-dessous ; il n'est pas testé unitairement (I/O réseau). Le test cible `enrichListItems` avec une fonction d'enrichissement injectée.

- [ ] **Step 1: Écrire le test de fan-out best-effort (FAIL)**

`server/scan_list_enrich_test.go` :
```go
package main

import (
	"context"
	"errors"
	"testing"
)

func TestEnrichListItemsBestEffort(t *testing.T) {
	items := []ScanListItem{
		{ScanResult: ScanResult{WineName: "OK"}, LineIndex: 0},
		{ScanResult: ScanResult{WineName: "FAIL"}, LineIndex: 1},
	}
	// enrichisseur injecté : ajoute Color sauf pour "FAIL" qui renvoie une erreur.
	enrich := func(ctx context.Context, in ScanResult) (ScanResult, error) {
		if in.WineName == "FAIL" {
			return in, errors.New("boom")
		}
		out := in
		out.Color = "red"
		return out, nil
	}
	got := enrichListItemsWith(context.Background(), items, enrich)
	if len(got) != 2 {
		t.Fatalf("len = %d, want 2", len(got))
	}
	// L'ordre (LineIndex) doit être préservé.
	byLine := map[int]ScanListItem{}
	for _, it := range got {
		byLine[it.LineIndex] = it
	}
	if byLine[0].Color != "red" {
		t.Fatalf("item0 non enrichi: %+v", byLine[0])
	}
	if byLine[1].Color != "" {
		t.Fatalf("item1 aurait dû rester non enrichi: %+v", byLine[1])
	}
}
```

- [ ] **Step 2: Lancer (FAIL)**

Run: `cd server && go test ./... -run TestEnrichListItemsBestEffort -v`
Expected: FAIL — `undefined: enrichListItemsWith`.

- [ ] **Step 3: Implémenter le handler + fan-out (PASS)**

`server/scan_list.go` :
```go
package main

import (
	"context"
	"encoding/json"
	"net/http"
	"sort"
	"sync"
)

const listEnrichWorkers = 6

// enrichFunc = signature d'un enrichisseur passe 2 (testable par injection).
type enrichFunc func(ctx context.Context, in ScanResult) (ScanResult, error)

// enrichListItemsWith applique enrich à chaque item dans un pool borné, best-effort,
// en préservant l'ordre (LineIndex).
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

// enrichListItems = adaptateur production : branche applyPass2 existant.
func enrichListItems(ctx context.Context, s *server, items []ScanListItem) []ScanListItem {
	return enrichListItemsWith(ctx, items, func(ctx context.Context, in ScanResult) (ScanResult, error) {
		return applyPass2(ctx, in) // signature réelle à confirmer dans scan_enrich.go ; adapter si besoin
	})
}

func (s *server) handleScanList(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	if !checkScanSecret(r) {
		http.Error(w, "unauthorized", http.StatusUnauthorized)
		return
	}
	if !listScanLimiter.allow(clientIP(r)) { // réutiliser l'extraction d'IP existante
		http.Error(w, "rate limited", http.StatusTooManyRequests)
		return
	}

	var req scanRequest // {Image, MimeType} — réutiliser le type existant de scan.go
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "bad request", http.StatusBadRequest)
		return
	}

	ctx := r.Context()
	raw, provider := runListPass1(ctx, req.Image, mimeOrDefault(req.MimeType)) // pattern de runPass1
	items, truncated, err := parseListPayload(raw)
	if err != nil {
		items = nil
	}
	if !isWineList(items) {
		writeJSON(w, ScanListResponse{Wines: []ScanListItem{}, Count: 0, Provider: provider, NotWineList: true})
		return
	}
	enriched := enrichListItems(ctx, s, items)
	writeJSON(w, ScanListResponse{
		Wines:     enriched,
		Count:     len(enriched),
		Provider:  provider,
		Truncated: truncated,
	})
}
```

> `runListPass1`, `mimeOrDefault`, `clientIP`, `writeJSON` : créer/aligner sur les helpers réels de `scan.go`. `runListPass1` réutilise le client Mistral/Gemini avec ce **prompt liste** (system) :
> « Tu reçois la photo d'une carte des vins de restaurant. Renvoie UNIQUEMENT un JSON `{"wines":[…]}`. Pour chaque vin lisible : `producer`, `wineName`, `vintage` (int, 0 si absent), `appellation`, `grapes` (array), `price` (number, prix bouteille), `currency` (ISO, ex EUR), `byGlass` (bool), `priceGlass` (number si proposé au verre). N'invente aucun vin absent de la carte. Ignore les sections non-vin (eaux, softs, cocktails). »

- [ ] **Step 4: Lancer le test de fan-out (PASS)**

Run: `cd server && go test ./... -run TestEnrichListItemsBestEffort -v`
Expected: PASS.

- [ ] **Step 5: Enregistrer la route + le limiter dans `main.go`**

Dans `server/main.go`, à côté de l'enregistrement de `/v1/scan`, ajouter :
```go
mux.HandleFunc("/v1/scan/list", srv.handleScanList)
```
Et près de `scanLimiter` :
```go
var listScanLimiter = newRateLimiter(6, time.Minute) // adapter au constructeur réel
```
(Si le limiter existant n'est pas un constructeur `newRateLimiter`, répliquer exactement la déclaration de `scanLimiter`.)

- [ ] **Step 6: Vérifier que tout compile + tests passent**

Run: `cd server && go build ./... && go test ./... -v`
Expected: build OK, tous tests PASS.

- [ ] **Step 7: Commit**

```bash
git add server/scan_list.go server/main.go server/scan_list_enrich_test.go
git commit -m "feat(scan): endpoint /v1/scan/list (fan-out passe 2, rate-limit, route)"
```

---

## Phase B — Client : fondations & refactors

### Task 4: Modèles client `ScannedMenuWine` + `MenuScanResult` + décodage

**Files:**
- Create: `CaveOS/Features/ScanMenu/ScannedMenuWine.swift`
- Test: `CaveOSTests/ScanMenu/MenuScanDecodingTests.swift`

**Interfaces:**
- Consumes: `WineColor`, `WineType` (`CaveOS/Models/Enums.swift`).
- Produces:
  - `struct ScannedMenuWine: Identifiable` (champs ci-dessous).
  - `struct MenuScanResult: Decodable { let wines: [ScannedMenuWine]; let truncated: Bool; let notWineList: Bool }`

- [ ] **Step 1: Écrire le test de décodage (FAIL)**

`CaveOSTests/ScanMenu/MenuScanDecodingTests.swift` :
```swift
import XCTest
@testable import CaveOS

final class MenuScanDecodingTests: XCTestCase {
    func testDecodeListResponse() throws {
        let json = """
        {"wines":[
          {"producer":"Clos La Coutale","wineName":"Cahors","vintage":2018,
           "color":"red","region":"Sud-Ouest","price":38,"currency":"EUR","lineIndex":0},
          {"wineName":"Chinon","vintage":2020,"byGlass":true,"priceGlass":8,"lineIndex":1}
        ],"count":2,"provider":"mistral+gemini","truncated":false}
        """.data(using: .utf8)!
        let result = try JSONDecoder().decode(MenuScanResult.self, from: json)
        XCTAssertEqual(result.wines.count, 2)
        XCTAssertFalse(result.notWineList)
        XCTAssertEqual(result.wines[0].producer, "Clos La Coutale")
        XCTAssertEqual(result.wines[0].price, 38)
        XCTAssertEqual(result.wines[0].color, .red)
        XCTAssertTrue(result.wines[1].byGlass)
        XCTAssertEqual(result.wines[1].priceGlass, 8)
    }

    func testDecodeNotWineList() throws {
        let json = #"{"wines":[],"count":0,"provider":"gemini","notWineList":true}"#.data(using: .utf8)!
        let result = try JSONDecoder().decode(MenuScanResult.self, from: json)
        XCTAssertTrue(result.notWineList)
        XCTAssertTrue(result.wines.isEmpty)
    }
}
```

- [ ] **Step 2: Lancer (FAIL)**

Run: `xcodebuild test -scheme CaveOS -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:CaveOSTests/MenuScanDecodingTests`
Expected: FAIL — types inconnus.

- [ ] **Step 3: Implémenter les modèles (PASS)**

`CaveOS/Features/ScanMenu/ScannedMenuWine.swift` :
```swift
import Foundation

struct ScannedMenuWine: Identifiable, Decodable {
    var id: Int { lineIndex }

    let producer: String?
    let wineName: String?
    let vintage: Int?
    let appellation: String?
    let grapes: [String]?
    let color: WineColor?
    let wineType: WineType?
    let region: String?
    let country: String?
    let peakFrom: Int?
    let peakTo: Int?
    let price: Double?
    let currency: String?
    let byGlass: Bool
    let priceGlass: Double?
    let lineIndex: Int

    private enum CodingKeys: String, CodingKey {
        case producer, wineName, vintage, appellation, grapes, color, wineType
        case region, country, peakFrom, peakTo, price, currency, byGlass, priceGlass, lineIndex
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        producer = try c.decodeIfPresent(String.self, forKey: .producer)
        wineName = try c.decodeIfPresent(String.self, forKey: .wineName)
        vintage = try c.decodeIfPresent(Int.self, forKey: .vintage)
        appellation = try c.decodeIfPresent(String.self, forKey: .appellation)
        grapes = try c.decodeIfPresent([String].self, forKey: .grapes)
        color = (try c.decodeIfPresent(String.self, forKey: .color)).flatMap(WineColor.init(rawValue:))
        wineType = (try c.decodeIfPresent(String.self, forKey: .wineType)).flatMap(WineType.init(rawValue:))
        region = try c.decodeIfPresent(String.self, forKey: .region)
        country = try c.decodeIfPresent(String.self, forKey: .country)
        peakFrom = try c.decodeIfPresent(Int.self, forKey: .peakFrom)
        peakTo = try c.decodeIfPresent(Int.self, forKey: .peakTo)
        price = try c.decodeIfPresent(Double.self, forKey: .price)
        currency = try c.decodeIfPresent(String.self, forKey: .currency)
        byGlass = (try c.decodeIfPresent(Bool.self, forKey: .byGlass)) ?? false
        priceGlass = try c.decodeIfPresent(Double.self, forKey: .priceGlass)
        lineIndex = (try c.decodeIfPresent(Int.self, forKey: .lineIndex)) ?? 0
    }
}

struct MenuScanResult: Decodable {
    let wines: [ScannedMenuWine]
    let truncated: Bool
    let notWineList: Bool

    private enum CodingKeys: String, CodingKey {
        case wines, truncated, notWineList
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        wines = (try c.decodeIfPresent([ScannedMenuWine].self, forKey: .wines)) ?? []
        truncated = (try c.decodeIfPresent(Bool.self, forKey: .truncated)) ?? false
        notWineList = (try c.decodeIfPresent(Bool.self, forKey: .notWineList)) ?? false
    }
}
```

> Vérifier que `WineColor`/`WineType` ont bien des `init(rawValue:)` avec les raw `red/white/rose/orange` et `still/sparkling/fortified/sweet`. Sinon, mapper explicitement.

- [ ] **Step 4: Lancer (PASS)**

Run: `xcodebuild test -scheme CaveOS -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:CaveOSTests/MenuScanDecodingTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add CaveOS/Features/ScanMenu/ScannedMenuWine.swift CaveOSTests/ScanMenu/MenuScanDecodingTests.swift
git commit -m "feat(scan): modèles client ScannedMenuWine + MenuScanResult"
```

---

### Task 5: `MenuScanService` (appel réseau)

**Files:**
- Create: `CaveOS/Features/ScanMenu/MenuScanService.swift`

**Interfaces:**
- Consumes: `MenuScanResult` (Task 4), `EnrichmentService.baseURL` + compression JPEG du pattern `AIScanService` (`CaveOS/Services/AIScanService.swift`).
- Produces: `static func scanList(image: UIImage) async throws -> MenuScanResult`

> Pas de test unitaire réseau ici (le décodage est couvert en Task 4). Lire `AIScanService.swift` pour copier exactement : compression (maxDim 1600, q 0.7), header `X-CaveOS-Key` depuis `Info.plist` (`CaveOSScanKey`), construction de l'URL.

- [ ] **Step 1: Implémenter le service**

`CaveOS/Features/ScanMenu/MenuScanService.swift` :
```swift
import UIKit

enum MenuScanService {
    static var baseURL: URL { EnrichmentService.baseURL }

    static func scanList(image: UIImage) async throws -> MenuScanResult {
        guard let jpeg = AIScanService.jpegData(for: image) else {  // réutiliser le helper de compression existant
            throw URLError(.cannotDecodeContentData)
        }
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/scan/list"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let key = AIScanService.scanKey {  // réutiliser l'accès à CaveOSScanKey existant
            request.setValue(key, forHTTPHeaderField: "X-CaveOS-Key")
        }
        let body = ["image": jpeg.base64EncodedString(), "mimeType": "image/jpeg"]
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(MenuScanResult.self, from: data)
    }
}
```

> Si `AIScanService.jpegData(for:)` / `AIScanService.scanKey` ne sont pas exposés, extraire ces helpers en `internal static` dans `AIScanService.swift` (petit refactor DRY) plutôt que dupliquer la compression.

- [ ] **Step 2: Vérifier la compilation**

Run: `xcodebuild build -scheme CaveOS -destination 'platform=iOS Simulator,name=iPhone 16'`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add CaveOS/Features/ScanMenu/MenuScanService.swift CaveOS/Services/AIScanService.swift
git commit -m "feat(scan): MenuScanService (appel /v1/scan/list)"
```

---

### Task 6: Refactor `ApogeeEngine` — fonction pure `window(vintage:…)`

**Files:**
- Modify: `CaveOS/Features/Apogee/ApogeeEngine.swift`
- Test: `CaveOSTests/Apogee/ApogeeEngineWindowTests.swift`

**Interfaces:**
- Consumes: `QualityTier`, `StorageQuality` (`CaveOS/Models/Enums.swift`).
- Produces:
  - `static func window(vintage: Int?, grapes: [String], regionTier: QualityTier?, storage: StorageQuality) -> Window?`
  - `window(for bottle:)` existant délègue à la nouvelle fonction.

- [ ] **Step 1: Écrire le test de la fonction pure (FAIL)**

`CaveOSTests/Apogee/ApogeeEngineWindowTests.swift` :
```swift
import XCTest
@testable import CaveOS

final class ApogeeEngineWindowTests: XCTestCase {
    func testWindowFromRawFieldsReturnsOrderedYears() {
        let w = ApogeeEngine.window(vintage: 2018, grapes: ["Malbec"], regionTier: .mid, storage: .good)
        XCTAssertNotNil(w)
        guard let w else { return }
        XCTAssertLessThanOrEqual(w.drinkFrom, w.peak)
        XCTAssertLessThanOrEqual(w.peak, w.drinkBy)
        XCTAssertGreaterThanOrEqual(w.drinkFrom, 2018)
    }

    func testWindowNilWhenNoVintage() {
        XCTAssertNil(ApogeeEngine.window(vintage: nil, grapes: ["Malbec"], regionTier: .mid, storage: .good))
    }
}
```

- [ ] **Step 2: Lancer (FAIL)**

Run: `xcodebuild test -scheme CaveOS -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:CaveOSTests/ApogeeEngineWindowTests`
Expected: FAIL — surcharge `window(vintage:…)` inexistante.

- [ ] **Step 3: Extraire la logique pure**

Dans `ApogeeEngine.swift` : déplacer le calcul de `window(for bottle:)` vers la nouvelle fonction pure, puis faire déléguer l'ancienne. Schéma :
```swift
static func window(vintage: Int?, grapes: [String], regionTier: QualityTier?, storage: StorageQuality) -> Window? {
    guard let vintage else { return nil }
    let tierMultiplier = (regionTier ?? .mid).multiplier
    let storageMultiplier = storage.multiplier        // utiliser le facteur réel existant
    let base = baseYears(forGrapes: grapes)            // réutiliser la table cépages existante
    let from = vintage + Int((base.min * tierMultiplier).rounded())
    let peak = vintage + Int((base.peak * tierMultiplier * storageMultiplier).rounded())
    let to = vintage + Int((base.max * tierMultiplier * storageMultiplier).rounded())
    return Window(drinkFrom: from, peak: peak, drinkBy: to)
}

static func window(for bottle: Bottle) -> Window? {
    // overrides bouteille/vin prioritaires (logique existante conservée), sinon :
    return window(
        vintage: bottle.vintage,
        grapes: bottle.wine?.grapes.map(\.name) ?? [],
        regionTier: bottle.wine?.region?.qualityTier,
        storage: bottle.storageQuality
    )
}
```
> Conserver intégralement la logique d'override (override bouteille > override vin > calcul). Adapter `base`, `baseYears`, et les multiplicateurs aux noms réels du fichier.

- [ ] **Step 4: Lancer le test + non-régression**

Run: `xcodebuild test -scheme CaveOS -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:CaveOSTests/ApogeeEngineWindowTests`
Puis la suite Apogée existante si présente. Expected: PASS, pas de régression.

- [ ] **Step 5: Commit**

```bash
git add CaveOS/Features/Apogee/ApogeeEngine.swift CaveOSTests/Apogee/ApogeeEngineWindowTests.swift
git commit -m "refactor(apogee): fonction pure window(vintage:grapes:regionTier:storage:)"
```

---

### Task 7: `CaveRepository.findWine` (matching flou) + lookup `Region` par nom

**Files:**
- Modify: `CaveOS/Persistence/CaveRepository.swift`
- Create: `CaveOS/Features/ScanMenu/MenuMatching.swift` (normalisation pure, testable sans SwiftData)
- Test: `CaveOSTests/ScanMenu/MenuMatchingTests.swift`

**Interfaces:**
- Produces:
  - `enum MenuMatching { static func normalize(_ s: String) -> String; static func matches(candidateProducer: String?, candidateName: String?, wineProducer: String?, wineName: String?) -> Bool }`
  - `func findWine(producer: String?, name: String?, vintage: Int?) -> Wine?` (sur `CaveRepository`)
  - `func region(named name: String) -> Region?` (sur `CaveRepository`)

> La logique floue testable est isolée dans `MenuMatching` (pas de dépendance SwiftData). `findWine`/`region` ne sont que des requêtes + filtre via `MenuMatching`.

- [ ] **Step 1: Écrire le test de matching (FAIL)**

`CaveOSTests/ScanMenu/MenuMatchingTests.swift` :
```swift
import XCTest
@testable import CaveOS

final class MenuMatchingTests: XCTestCase {
    func testNormalizeStripsAccentsAndCase() {
        XCTAssertEqual(MenuMatching.normalize("Château Margaux"), "chateau margaux")
    }

    func testMatchesIgnoresAccentsAndCase() {
        XCTAssertTrue(MenuMatching.matches(
            candidateProducer: "clos la coutale", candidateName: "Cahors",
            wineProducer: "Clos La Coutale", wineName: "CAHORS"))
    }

    func testDoesNotMatchDifferentWine() {
        XCTAssertFalse(MenuMatching.matches(
            candidateProducer: "Domaine A", candidateName: "Chinon",
            wineProducer: "Domaine B", wineName: "Sancerre"))
    }
}
```

- [ ] **Step 2: Lancer (FAIL)**

Run: `xcodebuild test -scheme CaveOS -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:CaveOSTests/MenuMatchingTests`
Expected: FAIL — `MenuMatching` inconnu.

- [ ] **Step 3: Implémenter `MenuMatching` (PASS)**

`CaveOS/Features/ScanMenu/MenuMatching.swift` :
```swift
import Foundation

enum MenuMatching {
    static func normalize(_ s: String) -> String {
        s.folding(options: .diacriticInsensitive, locale: .current)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Match si le nom correspond (égalité ou inclusion normalisée) et,
    /// quand les deux producteurs sont présents, qu'ils correspondent aussi.
    static func matches(candidateProducer: String?, candidateName: String?,
                        wineProducer: String?, wineName: String?) -> Bool {
        guard let cName = candidateName.map(normalize), !cName.isEmpty,
              let wName = wineName.map(normalize), !wName.isEmpty else { return false }
        let nameOK = cName == wName || cName.contains(wName) || wName.contains(cName)
        guard nameOK else { return false }
        if let cp = candidateProducer.map(normalize), !cp.isEmpty,
           let wp = wineProducer.map(normalize), !wp.isEmpty {
            return cp == wp || cp.contains(wp) || wp.contains(cp)
        }
        return true
    }
}
```

- [ ] **Step 4: Lancer (PASS)**

Run: `xcodebuild test -scheme CaveOS -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:CaveOSTests/MenuMatchingTests`
Expected: PASS.

- [ ] **Step 5: Ajouter `findWine` + `region(named:)` dans `CaveRepository`**

Dans `CaveRepository.swift` :
```swift
func findWine(producer: String?, name: String?, vintage: Int?) -> Wine? {
    let wines = fetchWines()
    return wines.first { wine in
        MenuMatching.matches(
            candidateProducer: producer, candidateName: name,
            wineProducer: wine.producer?.name, wineName: wine.name)
    }
}

func region(named name: String) -> Region? {
    let target = MenuMatching.normalize(name)
    // adapter au type de fetch existant pour Region
    return fetchAllRegions().first { MenuMatching.normalize($0.name) == target }
}
```
> Si aucune méthode `fetchAllRegions()` n'existe, ajouter un `fetch` SwiftData minimal pour `Region` en suivant le pattern de `fetchWines()`.

- [ ] **Step 6: Vérifier compilation + tests**

Run: `xcodebuild test -scheme CaveOS -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:CaveOSTests/MenuMatchingTests`
Expected: BUILD SUCCEEDED + PASS.

- [ ] **Step 7: Commit**

```bash
git add CaveOS/Persistence/CaveRepository.swift CaveOS/Features/ScanMenu/MenuMatching.swift CaveOSTests/ScanMenu/MenuMatchingTests.swift
git commit -m "feat(scan): findWine flou + lookup Region par nom"
```

---

## Phase C — Client : moteurs de conseil

### Task 8: `MenuValueEngine` (heuristique de valeur déterministe)

**Files:**
- Create: `CaveOS/Features/ScanMenu/MenuValueEngine.swift`
- Test: `CaveOSTests/ScanMenu/MenuValueEngineTests.swift`

**Interfaces:**
- Consumes: `QualityTier`.
- Produces:
  - `enum ValueVerdict { case goodValue, fair, expensive, unknown }`
  - `enum MenuValueEngine { static func verdict(tier: QualityTier?, price: Double?) -> ValueVerdict }`

- [ ] **Step 1: Écrire le test (FAIL)**

`CaveOSTests/ScanMenu/MenuValueEngineTests.swift` :
```swift
import XCTest
@testable import CaveOS

final class MenuValueEngineTests: XCTestCase {
    func testUnknownWhenTierMissing() {
        XCTAssertEqual(MenuValueEngine.verdict(tier: nil, price: 40), .unknown)
    }
    func testUnknownWhenPriceMissing() {
        XCTAssertEqual(MenuValueEngine.verdict(tier: .mid, price: nil), .unknown)
    }
    func testMidBands() {
        // bande mid attendue : 28–45 €
        XCTAssertEqual(MenuValueEngine.verdict(tier: .mid, price: 24), .goodValue)
        XCTAssertEqual(MenuValueEngine.verdict(tier: .mid, price: 35), .fair)
        XCTAssertEqual(MenuValueEngine.verdict(tier: .mid, price: 60), .expensive)
    }
}
```

- [ ] **Step 2: Lancer (FAIL)**

Run: `xcodebuild test -scheme CaveOS -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:CaveOSTests/MenuValueEngineTests`
Expected: FAIL.

- [ ] **Step 3: Implémenter (PASS)**

`CaveOS/Features/ScanMenu/MenuValueEngine.swift` :
```swift
import Foundation

enum ValueVerdict { case goodValue, fair, expensive, unknown }

enum MenuValueEngine {
    /// Bandes de prix resto attendues par tier (€). Calibrables ici, nulle part ailleurs.
    private struct Band { let low: Double; let high: Double }
    private static func band(for tier: QualityTier) -> Band {
        switch tier {
        case .entry:   return Band(low: 18, high: 30)
        case .mid:     return Band(low: 28, high: 45)
        case .premium: return Band(low: 50, high: 90)
        }
    }

    static func verdict(tier: QualityTier?, price: Double?) -> ValueVerdict {
        guard let tier, let price, price > 0 else { return .unknown }
        let b = band(for: tier)
        if price < b.low { return .goodValue }
        if price > b.high { return .expensive }
        return .fair
    }
}
```

- [ ] **Step 4: Lancer (PASS)**

Run: `xcodebuild test -scheme CaveOS -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:CaveOSTests/MenuValueEngineTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add CaveOS/Features/ScanMenu/MenuValueEngine.swift CaveOSTests/ScanMenu/MenuValueEngineTests.swift
git commit -m "feat(scan): MenuValueEngine (heuristique valeur déterministe)"
```

---

### Task 9: Scoring d'accord `MenuPairingScorer`

**Files:**
- Create: `CaveOS/Features/ScanMenu/MenuPairingScorer.swift`
- Test: `CaveOSTests/ScanMenu/MenuPairingScorerTests.swift`

**Interfaces:**
- Consumes: `PairingEngine.PairingSuggestion`, `WineColor`.
- Produces:
  - `enum PairingScore: Int { case poor = 0, ok = 1, good = 2, perfect = 3 }`
  - `enum MenuPairingScorer { static func score(wineColor: WineColor?, suggestion: PairingEngine.PairingSuggestion) -> PairingScore }`

- [ ] **Step 1: Écrire le test (FAIL)**

`CaveOSTests/ScanMenu/MenuPairingScorerTests.swift` :
```swift
import XCTest
@testable import CaveOS

final class MenuPairingScorerTests: XCTestCase {
    func testRedWineMatchesRedMeatSuggestion() {
        let s = PairingEngine.suggest(forDish: "magret de canard")
        let score = MenuPairingScorer.score(wineColor: .red, suggestion: s)
        XCTAssertGreaterThanOrEqual(score.rawValue, PairingScore.good.rawValue)
    }
    func testUnknownColorIsPoor() {
        let s = PairingEngine.suggest(forDish: "magret de canard")
        XCTAssertEqual(MenuPairingScorer.score(wineColor: nil, suggestion: s), .poor)
    }
}
```

- [ ] **Step 2: Lancer (FAIL)**

Run: `xcodebuild test -scheme CaveOS -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:CaveOSTests/MenuPairingScorerTests`
Expected: FAIL.

- [ ] **Step 3: Implémenter (PASS)**

`CaveOS/Features/ScanMenu/MenuPairingScorer.swift` :
```swift
import Foundation

enum PairingScore: Int { case poor = 0, ok = 1, good = 2, perfect = 3 }

enum MenuPairingScorer {
    static func score(wineColor: WineColor?, suggestion: PairingEngine.PairingSuggestion) -> PairingScore {
        guard let wineColor else { return .poor }
        guard suggestion.colors.contains(wineColor) else { return .ok == .ok ? .poor : .poor }
        // Couleur dans les couleurs conseillées : perfect si unique conseil, sinon good.
        return suggestion.colors.count == 1 ? .perfect : .good
    }
}
```
> Simplifier la ligne `suggestion.colors.contains` : si la couleur n'est pas conseillée → `.poor`. La condition ternaire ci-dessus est volontairement à nettoyer en `return .poor`.

- [ ] **Step 4: Nettoyer + lancer (PASS)**

Remplacer la ligne douteuse par un simple `return .poor` quand la couleur n'est pas conseillée.
Run: `xcodebuild test -scheme CaveOS -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:CaveOSTests/MenuPairingScorerTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add CaveOS/Features/ScanMenu/MenuPairingScorer.swift CaveOSTests/ScanMenu/MenuPairingScorerTests.swift
git commit -m "feat(scan): scoring d'accord MenuPairingScorer"
```

---

### Task 10: `MenuRankingEngine` (badges + tri composite)

**Files:**
- Create: `CaveOS/Features/ScanMenu/MenuRankingEngine.swift`
- Test: `CaveOSTests/ScanMenu/MenuRankingEngineTests.swift`

**Interfaces:**
- Consumes: `ScannedMenuWine`, `ValueVerdict`, `PairingScore`, `MenuValueEngine`, `MenuPairingScorer`, `ApogeeEngine.window`, `QualityTier`.
- Produces:
  - `struct RankedMenuWine: Identifiable { let wine: ScannedMenuWine; let value: ValueVerdict; let pairing: PairingScore?; let drinkNow: Bool; let cellarCount: Int; let personalScore: Int? ; var id: Int { wine.lineIndex } }`
  - `enum MenuSort { case pairing, value, price }`
  - `enum MenuRankingEngine { static func rank(_ wines: [ScannedMenuWine], dish: String?, tierLookup: (String?) -> QualityTier?, cellarLookup: (ScannedMenuWine) -> (count: Int, score: Int?), now: Int) -> [RankedMenuWine]; static func sort(_ ranked: [RankedMenuWine], by: MenuSort) -> [RankedMenuWine] }`

> Les dépendances SwiftData (tier région, cave) sont injectées en closures pour rendre le moteur testable sans base.

- [ ] **Step 1: Écrire le test (FAIL)**

`CaveOSTests/ScanMenu/MenuRankingEngineTests.swift` :
```swift
import XCTest
@testable import CaveOS

final class MenuRankingEngineTests: XCTestCase {
    private func wine(_ name: String, color: WineColor?, region: String?, price: Double?, line: Int) -> ScannedMenuWine {
        let json = """
        {"wineName":"\(name)","color":\(color.map { "\"\($0.rawValue)\"" } ?? "null"),
         "region":\(region.map { "\"\($0)\"" } ?? "null"),
         "price":\(price.map(String.init) ?? "null"),"lineIndex":\(line)}
        """.data(using: .utf8)!
        return try! JSONDecoder().decode(ScannedMenuWine.self, from: json)
    }

    func testSortByValuePutsGoodValueFirst() {
        let wines = [
            wine("Cher", color: .red, region: "R", price: 120, line: 0),
            wine("BonQP", color: .red, region: "R", price: 20, line: 1),
        ]
        let ranked = MenuRankingEngine.rank(
            wines, dish: nil,
            tierLookup: { _ in .mid },
            cellarLookup: { _ in (0, nil) },
            now: 2026)
        let sorted = MenuRankingEngine.sort(ranked, by: .value)
        XCTAssertEqual(sorted.first?.wine.wineName, "BonQP")
    }

    func testSortByPriceAscending() {
        let wines = [
            wine("B", color: .red, region: "R", price: 50, line: 0),
            wine("A", color: .red, region: "R", price: 30, line: 1),
        ]
        let ranked = MenuRankingEngine.rank(wines, dish: nil, tierLookup: { _ in .mid },
                                            cellarLookup: { _ in (0, nil) }, now: 2026)
        let sorted = MenuRankingEngine.sort(ranked, by: .price)
        XCTAssertEqual(sorted.first?.wine.wineName, "A")
    }
}
```

- [ ] **Step 2: Lancer (FAIL)**

Run: `xcodebuild test -scheme CaveOS -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:CaveOSTests/MenuRankingEngineTests`
Expected: FAIL.

- [ ] **Step 3: Implémenter (PASS)**

`CaveOS/Features/ScanMenu/MenuRankingEngine.swift` :
```swift
import Foundation

struct RankedMenuWine: Identifiable {
    let wine: ScannedMenuWine
    let value: ValueVerdict
    let pairing: PairingScore?
    let drinkNow: Bool
    let cellarCount: Int
    let personalScore: Int?
    var id: Int { wine.lineIndex }
}

enum MenuSort { case pairing, value, price }

enum MenuRankingEngine {
    static func rank(_ wines: [ScannedMenuWine],
                     dish: String?,
                     tierLookup: (String?) -> QualityTier?,
                     cellarLookup: (ScannedMenuWine) -> (count: Int, score: Int?),
                     now: Int) -> [RankedMenuWine] {
        let suggestion = (dish?.isEmpty == false) ? PairingEngine.suggest(forDish: dish!) : nil
        return wines.map { w in
            let tier = tierLookup(w.region)
            let value = MenuValueEngine.verdict(tier: tier, price: w.price)
            let pairing = suggestion.map { MenuPairingScorer.score(wineColor: w.color, suggestion: $0) }
            let window = ApogeeEngine.window(vintage: w.vintage, grapes: w.grapes ?? [],
                                             regionTier: tier, storage: .good)
            let drinkNow = window.map { now >= $0.drinkFrom && now <= $0.drinkBy } ?? false
            let cellar = cellarLookup(w)
            return RankedMenuWine(wine: w, value: value, pairing: pairing,
                                  drinkNow: drinkNow, cellarCount: cellar.count, personalScore: cellar.score)
        }
    }

    static func sort(_ ranked: [RankedMenuWine], by: MenuSort) -> [RankedMenuWine] {
        switch by {
        case .pairing:
            return ranked.sorted { ($0.pairing?.rawValue ?? -1) > ($1.pairing?.rawValue ?? -1) }
        case .value:
            return ranked.sorted { valueRank($0.value) > valueRank($1.value) }
        case .price:
            return ranked.sorted { ($0.wine.price ?? .greatestFiniteMagnitude) < ($1.wine.price ?? .greatestFiniteMagnitude) }
        }
    }

    private static func valueRank(_ v: ValueVerdict) -> Int {
        switch v { case .goodValue: return 3; case .fair: return 2; case .expensive: return 1; case .unknown: return 0 }
    }
}
```

- [ ] **Step 4: Lancer (PASS)**

Run: `xcodebuild test -scheme CaveOS -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:CaveOSTests/MenuRankingEngineTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add CaveOS/Features/ScanMenu/MenuRankingEngine.swift CaveOSTests/ScanMenu/MenuRankingEngineTests.swift
git commit -m "feat(scan): MenuRankingEngine (badges + tri composite)"
```

---

## Phase D — Client : UI & intégration

### Task 11: `MenuScanView` (capture/import + garde freemium)

**Files:**
- Create: `CaveOS/Features/ScanMenu/MenuScanView.swift`
- Modify: navigation/onglet où vit le scan actuel (lire `CaveOS/App/ContentView.swift` et la barre d'action de `InventoryView.swift` pour copier le point d'entrée du scan d'étiquette).

**Interfaces:**
- Consumes: `MenuScanService.scanList`, `StoreManager.canUseAIScan/consumeFreeScan`, `MenuScanResult`.
- Produces: une vue présentée en sheet qui, sur succès, pousse `MenuResultsView` (Task 12) avec `[ScannedMenuWine]`.

> UI : vérification manuelle (pas de test unitaire de vue). La logique testable étant déjà couverte par les Tasks 8–10.

- [ ] **Step 1: Implémenter la vue (état: idle / scanning / error / done)**

Structure : bouton « Scanner une carte » → `PhotosPicker` ou caméra → `Task { }` appelle `MenuScanService.scanList`. Avant l'appel : `guard storeManager.canUseAIScan() else { showPaywallOrDeviceFallback() }`. Sur succès : `storeManager.consumeFreeScan()` puis navigation vers `MenuResultsView`. Sur `result.notWineList` : message dédié.

- [ ] **Step 2: Brancher le point d'entrée**

Ajouter une action « Scanner une carte des vins » à côté du scan d'étiquette existant (menu/bouton dans `InventoryView` ou l'écran Accords selon ergonomie — privilégier l'écran Accords car la feature est orientée accord mets-vins).

- [ ] **Step 3: Vérifier compilation + run simulateur**

Run: `xcodebuild build -scheme CaveOS -destination 'platform=iOS Simulator,name=iPhone 16'`
Expected: BUILD SUCCEEDED. Vérifier manuellement l'ouverture de la sheet.

- [ ] **Step 4: Commit**

```bash
git add CaveOS/Features/ScanMenu/MenuScanView.swift CaveOS/App/ContentView.swift
git commit -m "feat(scan): MenuScanView (capture carte + garde freemium)"
```

---

### Task 12: `MenuResultsView` + `MenuWineRow` (résultats, plat, tri, badges)

**Files:**
- Create: `CaveOS/Features/ScanMenu/MenuResultsView.swift`
- Create: `CaveOS/Features/ScanMenu/MenuWineRow.swift`

**Interfaces:**
- Consumes: `MenuRankingEngine.rank/sort`, `RankedMenuWine`, `CaveRepository.findWine/region`, `PairingEngine` (catégories rapides), `@Environment` repository.
- Produces: l'écran final affiché à l'utilisateur.

- [ ] **Step 1: Implémenter `MenuResultsView`**

État : `@State dish: String`, `@State sort: MenuSort = .value`. Calcule `ranked` via `MenuRankingEngine.rank(wines, dish:, tierLookup: { name in name.flatMap { repo.region(named: $0)?.qualityTier } }, cellarLookup: { w in let wine = repo.findWine(producer: w.producer, name: w.wineName, vintage: w.vintage); return (wine?.bottles.filter { $0.state == .inCellar }.reduce(0){ $0 + $1.quantity } ?? 0, bestScore(wine)) }, now: Calendar.current.component(.year, from: .now))`. En-tête : `TextField` plat + chips catégories rapides + `Picker` de tri. Liste : `ForEach(MenuRankingEngine.sort(ranked, by: sort)) { MenuWineRow(item: $0) }`.

> `bestScore(wine)` = meilleure note `TastingNote` liée (helper local). Accord grisé si `dish` vide.

- [ ] **Step 2: Implémenter `MenuWineRow`**

Affiche nom · producteur · millésime · prix + badges conditionnels :
- accord (★ perfect / ◐ good|ok) — masqué si `item.pairing == nil`.
- valeur — masqué si `.unknown` ; libellé « bon Q/P » (goodValue) / « cher » (expensive).
- « à boire maintenant » si `item.drinkNow`.
- cave : « \(count) en cave » si `count > 0` ; « noté \(score)/100 » si `personalScore != nil`.

- [ ] **Step 3: Vérifier compilation + run simulateur (vérif visuelle)**

Run: `xcodebuild build -scheme CaveOS -destination 'platform=iOS Simulator,name=iPhone 16'`
Expected: BUILD SUCCEEDED ; vérifier l'affichage avec une carte de test.

- [ ] **Step 4: Commit**

```bash
git add CaveOS/Features/ScanMenu/MenuResultsView.swift CaveOS/Features/ScanMenu/MenuWineRow.swift
git commit -m "feat(scan): écran de résultats carte (plat, tri, badges)"
```

---

### Task 13: Dégradation device + bannières d'erreur

**Files:**
- Modify: `CaveOS/Features/ScanMenu/MenuScanView.swift`
- Create: `CaveOS/Features/ScanMenu/MenuDeviceFallback.swift`

**Interfaces:**
- Consumes: Apple Vision + `LabelParser.parse(lines:knownAppellations:knownGrapes:)` (existant), `ScannedMenuWine`.
- Produces: `enum MenuDeviceFallback { static func scan(image: UIImage, knownAppellations: [String], knownGrapes: [String]) -> [ScannedMenuWine] }` — OCR local, découpe en lignes, `LabelParser` par bloc, sans prix ni enrichissement avancé.

- [ ] **Step 1: Implémenter le repli device**

Vision `VNRecognizeTextRequest` → lignes → regrouper par entrée → `LabelParser.parse` par entrée → mapper en `ScannedMenuWine` (sans price/region fiable). Renseigner `lineIndex` par ordre.

- [ ] **Step 2: Brancher la dégradation dans `MenuScanView`**

Si `MenuScanService.scanList` throw (réseau) → bannière « mode dégradé » + appel `MenuDeviceFallback.scan(...)` → `MenuResultsView` (badges valeur/accord limités mais croisement cave OK). Si pas de crédit → proposer ce repli gratuit ou le paywall.

- [ ] **Step 3: Vérifier compilation**

Run: `xcodebuild build -scheme CaveOS -destination 'platform=iOS Simulator,name=iPhone 16'`
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Commit**

```bash
git add CaveOS/Features/ScanMenu/MenuScanView.swift CaveOS/Features/ScanMenu/MenuDeviceFallback.swift
git commit -m "feat(scan): repli device (Vision) + bannières d'erreur carte"
```

---

### Task 14: Vérification de bout en bout + suite complète

**Files:** aucun nouveau (vérification).

- [ ] **Step 1: Suite serveur complète**

Run: `cd server && go test ./... -v`
Expected: tous PASS.

- [ ] **Step 2: Suite client complète**

Run: `xcodebuild test -scheme CaveOS -destination 'platform=iOS Simulator,name=iPhone 16'`
Expected: tous PASS.

- [ ] **Step 3: Test manuel du flux réel**

Démarrer le serveur local (ou pointer vers le VPS), scanner une vraie carte des vins, saisir un plat, vérifier tri/badges/croisement cave, couper le réseau pour vérifier le repli device, vérifier la décrémentation d'un crédit IA (compte gratuit).

- [ ] **Step 4: Commit final si ajustements**

```bash
git add -A
git commit -m "test(scan): vérification de bout en bout scan de carte des vins"
```

---

## Self-Review (rempli par l'auteur du plan)

**1. Spec coverage :**
- §2.1 endpoint/passe1-liste/garde/passe2/auth/rate-limit/réponse → Tasks 1,2,3 ✅
- §2.2 fichiers client → Tasks 4,5,8,9,10,11,12 ✅
- §3 flux → Tasks 11,12 ✅
- §4 heuristique valeur → Task 8 ✅
- §5 UX résultats → Task 12 ✅
- §6 dégradation/erreurs → Task 13 ✅
- §7 refactors (ApogeeEngine pur, findWine, Region lookup) → Tasks 6,7 ✅
- §8 tests → couverts par tâche-à-tâche + Task 14 ✅
- §9 hors scope → respecté (pas de tâche d'ajout cave/wishlist, pas d'API externe) ✅

**2. Placeholder scan :** aucun « TBD ». Les notes « adapter au nom réel » sont des consignes d'alignement sur l'existant, pas des placeholders de logique. Code fourni pour chaque step de code.

**3. Type consistency :** `ScanListItem`/`ScanListResponse` (Go) ↔ `ScannedMenuWine`/`MenuScanResult` (Swift) cohérents sur les noms JSON. `ValueVerdict`, `PairingScore`, `RankedMenuWine`, `MenuSort` utilisés de façon cohérente entre Tasks 8→10→12. `ApogeeEngine.window(vintage:grapes:regionTier:storage:)` défini en Task 6, consommé en Task 10. `MenuMatching.matches(...)` défini en Task 7, consommé via `findWine`.
