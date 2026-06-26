# Design — Scan de carte des vins au restaurant

- **Date** : 2026-06-26
- **Statut** : validé (en attente de relecture utilisateur avant plan d'implémentation)
- **Branche** : `feat/scan-ia`

## 1. Objectif

Permettre à l'utilisateur de photographier la **carte des vins d'un restaurant** et d'obtenir,
pour chaque vin lisible : un **score d'accord** avec son plat (optionnel), un **signal de rapport
qualité-prix**, un statut **« à boire maintenant »**, et un **croisement avec sa cave / ses notes
personnelles**.

Cette feature étend le moteur de scan existant (étiquette → 1 vin) vers le cas **carte → N vins**.
Elle réutilise au maximum l'existant : pipeline de scan 2 passes (Mistral + Gemini),
`PairingEngine`, `ApogeeEngine`, tiers de qualité région, données SwiftData locales.

### Décisions produit (cadrage validé)

- **Output v1** : accord avec le plat **+** signal rapport qualité-prix.
- **Référence de valeur** : heuristique **déterministe** (tier région/appellation × prix carte),
  pas d'API externe, pas d'estimation LLM — cohérent avec la logique anti-hallucination du projet.
- **Croisement cave** : oui — « déjà en cave (X bouteilles) » + « déjà noté Y/100 par toi ».
- **Saisie du plat** : **optionnelle**. Sans plat → tri par valeur + « à boire maintenant ».
  Avec plat → tri par accord (texte libre ou catégories rapides du `PairingEngine`).
- **Freemium** : 1 scan de carte = **1 crédit IA** (quota des 25 scans gratuits, illimité pour Pro).

## 2. Architecture & composants

### 2.1 Serveur (Go)

Nouveau fichier `server/scan_list.go`.

**Endpoint** : `POST /v1/scan/list`
- Requête (identique au scan mono-vin) :
  ```go
  type scanListRequest struct {
      Image    string // base64 brut (sans préfixe data:)
      MimeType string // défaut "image/jpeg"
  }
  ```
- **Passe 1-liste** : appel Gemini (primaire, JSON structuré) + Mistral OCR (cartes coriaces) en
  parallèle, avec un *prompt « liste »* qui renvoie un tableau d'entrées de carte. Fusion par ligne.
  **Plafond `maxListWines = 60`** (borne latence/coût) ; au-delà, tronqué et signalé via `truncated`.
- **Garde-fou `isWineList`** : rejette une image qui n'est pas une carte des vins (pendant de
  `isWineLabel`). En cas de rejet → `{ wines: [], count: 0, notWineList: true }`.
- **Passe 2-enrichissement** : la fonction `applyPass2` existante appliquée à chaque vin
  (couleur, type, pays, région, cépages probables, fenêtre d'apogée), en **fan-out concurrent borné**
  (pool de workers, ex. 6, timeout 12 s par vin), **best-effort** : un échec laisse les champs
  passe 1 intacts. Région/tier résolus via `regionByName` (DB SQLite locale serveur), comme aujourd'hui.
- **Auth** : `checkScanSecret` (header `X-CaveOS-Key`), réutilisé tel quel.
- **Rate-limit** : nouveau `listScanLimiter` à **6 req/min/IP** (plus strict que le 12/min mono-vin,
  car requête plus lourde). Même extraction d'IP (`X-Forwarded-For` / `RemoteAddr`).
- **Timeout global** relevé à ~90 s (passe 1 + fan-out passe 2).
- **Jamais de 5xx** sur le chemin nominal : best-effort, comme `/v1/scan`.

**Réponse** :
```go
type ScanListItem struct {
    ScanResult            // réutilise tous les champs existants (producer, wineName, vintage,
                          // appellation, grapes, color, wineType, region, country, peakFrom/To, …)
    Price      *float64 `json:"price,omitempty"`      // prix bouteille lu sur la carte
    Currency   string   `json:"currency,omitempty"`   // ex. "EUR"
    ByGlass    bool     `json:"byGlass,omitempty"`     // proposé au verre
    PriceGlass *float64 `json:"priceGlass,omitempty"`  // prix au verre si lu
    LineIndex  int      `json:"lineIndex"`             // ordre d'apparition sur la carte
}

type ScanListResponse struct {
    Wines       []ScanListItem `json:"wines"`
    Count       int            `json:"count"`
    Provider    string         `json:"provider"`            // ex. "mistral+gemini"
    Truncated   bool           `json:"truncated,omitempty"` // si > maxListWines
    NotWineList bool           `json:"notWineList,omitempty"`
}
```

Fichiers réutilisés : `server/scan_enrich.go` (`applyPass2`), `server/scan_merge.go`,
`server/main.go` (enregistrement de la route).

### 2.2 Client (SwiftUI)

Nouveau dossier `CaveOS/Features/ScanMenu/` (séparé du scan d'étiquette — principe « many small files ») :

| Fichier | Rôle |
|---------|------|
| `MenuScanService.swift` | `static func scanList(image: UIImage) async throws -> MenuScanResult` — compression JPEG (maxDim 1600, q 0.7), `POST /v1/scan/list`, header `X-CaveOS-Key`, décodage. |
| `ScannedMenuWine.swift` | Modèles décodés : `ScannedMenuWine` (champs de `ScannedLabel` + `price`, `currency`, `byGlass`, `priceGlass`, `lineIndex`) **et** le wrapper `MenuScanResult` (`wines: [ScannedMenuWine]`, `truncated`, `notWineList`). |
| `MenuScanView.swift` | Capture / import de la photo de carte, état de chargement, garde freemium. |
| `MenuResultsView.swift` | Liste de résultats, champ plat optionnel, sélecteur de tri. |
| `MenuWineRow.swift` | Rendu d'une ligne + badges. |
| `MenuValueEngine.swift` | Heuristique de valeur déterministe (pure). |
| `MenuRankingEngine.swift` | Tri composite (accord / valeur / prix) + calcul des badges. |

## 3. Flux de données

1. `MenuScanView` capture/importe une image → vérifie `StoreManager.canUseAIScan()`.
   - Si `false` (pas Pro & 0 crédit) → propose le repli device (cf. §6) ou le paywall.
2. `MenuScanService.scanList` → `/v1/scan/list` → `MenuScanResult` (liste de `ScannedMenuWine`).
   - Sur succès serveur (IA) : `StoreManager.consumeFreeScan()` (**1 crédit**).
3. Pour chaque `ScannedMenuWine`, calculs **100 % locaux** :
   - **Valeur** : `MenuValueEngine.verdict(tier:price:)` → `{ goodValue, fair, expensive, unknown }`.
   - **Accord** (si plat saisi) : `PairingEngine.suggest(forDish:)` → score
     `{ perfect, good, ok, poor }` à partir des couleurs conseillées + style.
   - **À boire maintenant** : `ApogeeEngine.window(vintage:grapes:regionTier:storage:)` → statut.
   - **Croisement cave** : `CaveRepository.findWine(producer:name:vintage:)` → quantité en cave +
     meilleure note `TastingNote`.
4. `MenuResultsView` affiche et trie selon le sélecteur (Accord | Valeur | Prix).

## 4. Heuristique de valeur (déterministe)

`MenuValueEngine` (pur, testable isolément) :
- **Entrée** : `QualityTier` (premium / mid / entry), couleur/type, `price`.
- **Bandes de prix resto attendues** par tier = constantes paramétrables (ex. mid : 28–45 €).
  Comparaison du prix carte à la bande → verdict.
- **Tier inconnu ⇒ `unknown`** (badge masqué). Aucune invention.
- Volontairement grossier (limite assumée du choix déterministe ; ne distingue pas deux vins
  d'une même appellation).

Les bandes sont définies comme constantes dans `MenuValueEngine` pour rester ajustables sans
toucher à la logique. (Pas de hardcode dispersé.)

## 5. Écran de résultats (UX)

- **En-tête** : champ **plat optionnel** (texte libre + catégories rapides réutilisées du
  `PairingEngine`) + sélecteur de tri (Accord | Valeur | Prix). Accord grisé tant qu'aucun plat n'est saisi.
- **Ligne** (`MenuWineRow`) : nom · producteur · millésime · prix ; badges :
  - Accord : ★ (perfect) / ◐ (good/ok) — masqué si pas de plat.
  - Valeur : « bon Q/P » / « cher » — masqué si `unknown`.
  - « À boire maintenant » selon apogée.
  - Cave : « 3 en cave » / « déjà noté 92/100 ».
- **Vins non enrichis** : affichés quand même (nom + prix), sans badges déduits.
- **v1 en lecture seule** (outil de conseil) : pas d'ajout à la cave depuis les résultats.

## 6. Gestion d'erreurs & dégradation

| Cas | Comportement |
|-----|--------------|
| Serveur injoignable | Repli **device** : Vision OCR local → `LabelParser` par ligne (sans valeur/enrichissement avancé) + bannière « mode dégradé ». |
| Pas Pro & 0 crédit | Proposer repli device gratuit **ou** paywall. |
| `notWineList = true` | Message « Ça ne ressemble pas à une carte des vins. » |
| Parsing partiel | Afficher les vins lus ; best-effort. |
| Passe 2 partielle | Vins concernés affichés sans badges déduits. |

Le serveur ne renvoie jamais 5xx sur le chemin nominal (best-effort, comme `/v1/scan`).

## 7. Refactors ciblés (inclus dans le périmètre)

1. **`ApogeeEngine`** : extraire une fonction pure
   `window(vintage:grapes:regionTier:storage:) -> Window?` ; l'actuelle `window(for bottle:)`
   y délègue. Nécessaire car un vin de carte n'est pas un `Bottle` persisté.
2. **`CaveRepository.findWine(producer:name:vintage:) -> Wine?`** : matching flou
   (normalisation accents/casse, comparaison producteur + nom, millésime exact ou nil). **Absent
   aujourd'hui** — requis pour le croisement cave.
3. **Lookup `Region` par nom côté client** : récupérer le `qualityTier` d'un vin hors-cave
   (le tier n'est aujourd'hui accessible que via `Bottle.wine?.region?.qualityTier`).

## 8. Tests (TDD, cible 80 %)

**Serveur (Go, table-driven)** :
- Parsing/fusion de la réponse liste (lignes multiples, prix, au verre).
- Garde `isWineList` (carte vs non-carte vs étiquette).
- Fan-out enrichissement (best-effort, échec partiel).
- Forme exacte de `ScanListResponse` (sérialisation JSON, troncature, `notWineList`).

**Client (Swift)** :
- `MenuValueEngine` : bandes par tier, masquage `unknown`, devises.
- Scoring d'accord (couleur/style vs plat).
- `CaveRepository.findWine` : matchs exacts, flous, négatifs.
- `ApogeeEngine.window(vintage:…)` pur (équivalence avec `window(for:)`).
- Décodage `ScannedMenuWine` / `MenuScanResult` depuis JSON serveur.

## 9. Hors scope v1 (YAGNI)

- API de prix / notes critiques externes (Vivino, Wine-Searcher, Parker…).
- Ajout à la cave / wishlist depuis les résultats.
- Scan d'étiquettes **par lot** (feature distincte).
- Sauvegarde / historique des cartes scannées.
- Reconnaissance de cartes manuscrites au-delà de ce que gère Mistral OCR.

## 10. Découpage d'implémentation (indicatif)

1. Serveur : endpoint `/v1/scan/list`, prompt liste, garde `isWineList`, fan-out passe 2, tests Go.
2. Client — fondations : `ScannedMenuWine`, `MenuScanService`, décodage + tests.
3. Refactors : `ApogeeEngine` pur, `CaveRepository.findWine`, lookup `Region` + tests.
4. Moteurs : `MenuValueEngine`, scoring accord, `MenuRankingEngine` + tests.
5. UI : `MenuScanView`, `MenuResultsView`, `MenuWineRow`, intégration onglet/scan.
6. Dégradation device + freemium (`StoreManager`) + bannières d'erreur.
