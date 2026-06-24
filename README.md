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

Voir [`server/README.md`](server/README.md). Service Go (binaire statique, SQLite pur-Go), endpoints `/v1/wines/search`, `/v1/enrich`, `/v1/db/latest`, `/credits`, `/v1/billing/*`.

## 🚀 Mise en ligne

- Déploiement **serveur** (API + Stripe, HTTPS) : **[DEPLOY.md](DEPLOY.md)**
- Publication **App Store** pas à pas (App Store Connect, signing, TestFlight, fiche, soumission) : **[APP_STORE_CONNECT.md](APP_STORE_CONNECT.md)**

## Fonctionnalités (CDC couvert)

**v1 (MVP)** — inventaire CRUD, emplacements multi-niveaux + drag & drop, recherche/filtres, moteur d'apogée, notifications locales, scan d'étiquette Vision (OCR + parsing), export CSV, base vin embarquée, StoreKit 2 (freemium + Lifetime).

**v2** — sync CloudKit (activable) + statut de synchronisation, analytics de cave (Swift Charts), code-barres EAN, enrichissement API opt-in (serveur Go), codes erreur matériel HH/LL/EE + relevés de température & alertes.

**v3** — partage de cave (CloudKit/CKShare + repli texte), carnet de dégustation WSET avancé + photos, accords mets-vins, iPad adaptatif (NavigationSplitView), widget WidgetKit (App Group), matching visuel on-device (Vision feature print).

> Scan caméra, code-barres, achats StoreKit et sync CloudKit se vérifient sur **appareil réel** (le simulateur ne les expose pas) ; le code gère les fallbacks. La sync iCloud et le partage social nécessitent un compte iCloud et un profil de provisioning avec les entitlements fournis.

## Abonnement Stripe (web)

En complément des achats in-app StoreKit, CaveOS Pro peut être souscrit via **Stripe** (abonnement web). Le serveur Go gère Checkout (`mode: subscription`), le webhook signé et le Customer Portal ; l'app n'embarque **aucune clé** et interroge `/v1/billing/status` pour débloquer Pro.

La clé Stripe et les secrets vivent **uniquement** sur le VPS dans `/home/ubuntu/caveos-server/.env` (`chmod 600`, hors git), chargés via `EnvironmentFile` systemd :

```
STRIPE_SECRET_KEY=sk_test_…      # jamais commité
STRIPE_PRICE_ID=price_…
STRIPE_WEBHOOK_SECRET=whsec_…
PUBLIC_BASE_URL=https://caveos.152.228.136.49.sslip.io
```

Un hook `scripts/check-secrets.sh` (installé en `pre-commit`) bloque tout commit contenant une clé. Le serveur est exposé en HTTPS via Caddy + sslip.io. En production, préférer une **clé restreinte (`rk_`)** et régénérer toute clé ayant transité en clair.

## Licences des données

| Source | Données | Licence |
|---|---|---|
| Wikidata | cépages, régions | CC0 (domaine public) |
| INAO (via data.gouv.fr) | appellations AOC/AOP | Licence Ouverte v1.0 |
| LWIN / Liv-ex | identifiants vin | Creative Commons |

## Licence du code

MIT — voir [LICENSE](LICENSE).
