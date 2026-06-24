# CaveOS 🍷

**La cave à vin dans la poche, qui marche partout, instantanément, et pour toujours.**

Application iOS native (100 % Swift / SwiftUI), **offline-first**, agnostique du matériel, avec reconnaissance d'étiquettes locale via le framework Vision (sans Vivino), un modèle de données local SwiftData et une sync CloudKit prévue en tâche de fond.

CaveOS est l'« anti-Vinotag » : rapide, honnête, qui fonctionne hors-ligne et n'appartient à aucun fabricant de cave.

## Principes directeurs

1. **Offline-first absolu** — consultation / ajout / déplacement / recherche fonctionnent sans réseau.
2. **Aucune dépendance critique à un service tiers** — si CloudKit ou une API meurt, l'app continue en local.
3. **Honnêteté du modèle économique** — ce que l'utilisateur saisit lui appartient et reste exportable gratuitement.
4. **Natif et rapide** — Swift / SwiftUI, zéro web wrapper.

## Architecture

- **UI** : SwiftUI + MVVM + `@Observable` (iOS 17+)
- **Persistance** : SwiftData (`@Model`) via une couche `CaveRepository` (sauvegardes explicites, repli Core Data possible)
- **Scan** : Vision / VisionKit (`DataScannerViewController`, `RecognizeTextRequest`) → OCR + parsing en champs structurés
- **Apogée** : moteur heuristique (cépage × qualité région × qualité stockage)
- **Monétisation** : StoreKit 2 — freemium honnête + déblocage *Lifetime*
- **Données vin embarquées** : cépages (Wikidata CC0), régions, appellations FR (INAO Licence Ouverte v1.0), LWIN (Liv-ex CC)

```
CaveOS/
├── App/            # point d'entrée, ModelContainer, navigation
├── Models/         # enums + modèles SwiftData
├── Persistence/    # CaveRepository, SeedImporter
├── Features/       # Inventory, Locations, Search, Scan, Apogee, Tasting, Export, Paywall, Settings
├── Services/       # NotificationService
├── Support/        # DesignSystem
└── Resources/      # base vin embarquée (winedata.json)
server/             # API Go (données vin + enrichissement) déployée sur VPS
```

## Build (app iOS)

Prérequis : Xcode 26+, [XcodeGen](https://github.com/yonsm/XcodeGen).

```bash
xcodegen generate          # génère CaveOS.xcodeproj depuis project.yml
open CaveOS.xcodeproj       # puis Run sur un simulateur iOS 17+
```

## Serveur (API données vin)

Voir [`server/README.md`](server/README.md). Service Go (binaire statique, SQLite pur-Go), endpoints `/v1/wines/search`, `/v1/enrich`, `/v1/db/latest`, `/credits`.

## Licences des données

| Source | Données | Licence |
|---|---|---|
| Wikidata | cépages, régions | CC0 (domaine public) |
| INAO (via data.gouv.fr) | appellations AOC/AOP | Licence Ouverte v1.0 |
| LWIN / Liv-ex | identifiants vin | Creative Commons |

## Licence du code

MIT — voir [LICENSE](LICENSE).
