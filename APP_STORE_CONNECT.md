# Publier CaveOS sur l'App Store — guide App Store Connect (pas à pas)

Toutes les étapes, de l'inscription au programme Apple jusqu'à la mise en vente. Suis-les dans l'ordre. Les valeurs propres à CaveOS sont indiquées (bundle id, conteneurs, etc.).

> Repères CaveOS : bundle app `com.louisbdc.caveos` · widget `com.louisbdc.caveos.widget` · watch `com.louisbdc.caveos.watchkitapp` · App Group `group.com.louisbdc.caveos` · conteneur iCloud `iCloud.com.louisbdc.caveos`.

---

## Étape 0 — Compte & accès

1. **S'inscrire à l'Apple Developer Program** : <https://developer.apple.com/programs/> (99 $/an). Validation 24–48 h (vérification d'identité possible).
2. Accepter le **Program License Agreement** dans App Store Connect au premier login.
3. **App Store Connect** : <https://appstoreconnect.apple.com>.
4. Avoir l'**authentification à deux facteurs** activée sur ton Apple ID (obligatoire).

---

## Étape 1 — Contrats, banque, fiscalité (obligatoire pour vendre)

> Sans ça, **aucun achat (StoreKit ou abonnement) ne fonctionne** et l'app payante ne peut pas être validée.

1. App Store Connect → **Business** (Accords) → signer le **Paid Applications Agreement**.
2. Renseigner les **coordonnées bancaires** (compte qui recevra les revenus).
3. Renseigner les **informations fiscales** (formulaires US W-8BEN/W-8BEN-E, TVA, etc.).
4. Désigner les contacts (financier, technique, juridique).

> Si tu vends **uniquement via Stripe** (abonnement web) et que l'app est **gratuite** sur l'App Store, ces étapes restent recommandées mais l'app peut être publiée gratuitement. Attention aux règles 3.1.1 (voir Étape 9).

---

## Étape 2 — Déclarer les identifiants (Identifiers)

Sur <https://developer.apple.com/account> → **Certificates, Identifiers & Profiles**.

### 2.1 App Group
- **Identifiers → App Groups → +** → `group.com.louisbdc.caveos` (description « CaveOS shared »).

### 2.2 Conteneur iCloud
- **Identifiers → iCloud Containers → +** → `iCloud.com.louisbdc.caveos`.

### 2.3 App IDs (un par cible)
Créer 3 **App IDs** (type App) :
- `com.louisbdc.caveos` (app) — activer : **iCloud (CloudKit)** + sélectionner le conteneur, **App Groups** + sélectionner le groupe, **Push Notifications**, **In-App Purchase** (si StoreKit).
- `com.louisbdc.caveos.widget` (widget) — activer **App Groups**.
- `com.louisbdc.caveos.watchkitapp` (watch) — activer **App Groups** si l'app montre utilise WatchConnectivity (suffisant sans App Group).

> Avec le **signing automatique** de Xcode (recommandé), Xcode crée App IDs et profils tout seul ; tu n'as à créer **manuellement** que l'App Group et le conteneur iCloud, puis à cocher les capacités dans Xcode (Étape 4).

---

## Étape 3 — Créer l'app dans App Store Connect

1. App Store Connect → **Apps → + → Nouvelle app**.
2. Plateforme : **iOS**.
3. **Nom** (unique sur l'App Store) : `CaveOS — Gestion de cave` (ou `CaveOS`).
4. **Langue principale** : Français.
5. **Bundle ID** : sélectionner `com.louisbdc.caveos`.
6. **SKU** : identifiant interne libre, ex. `CAVEOS-IOS-001`.
7. **Accès utilisateur** : Accès complet.

---

## Étape 4 — Signer l'app dans Xcode

```bash
xcodegen generate
open CaveOS.xcodeproj
```

Pour **chaque cible** (CaveOS, CaveOSWidget, CaveOSWatch) → onglet **Signing & Capabilities** :

1. Cocher **Automatically manage signing**.
2. Choisir ta **Team** (renseigne `DEVELOPMENT_TEAM`).
3. Vérifier le **Bundle Identifier** (les 3 ci-dessus).
4. Cible **CaveOS** — ajouter les **Capabilities** (bouton + Capability), cohérentes avec `CaveOS/CaveOS.entitlements` :
   - **iCloud** → cocher **CloudKit** → conteneur `iCloud.com.louisbdc.caveos`
   - **App Groups** → `group.com.louisbdc.caveos`
   - **Push Notifications**
   - **In-App Purchase** (si tu gardes StoreKit)
5. Cible **CaveOSWidget** — **App Groups** (même groupe).
6. Laisser Xcode générer certificats et profils (il demandera de se connecter à ton compte).

---

## Étape 5 — Achats in-app (seulement si tu gardes StoreKit)

> CaveOS propose l'abonnement via **Stripe (web)** : dans ce cas, **rien à faire ici**. Ne configure les produits StoreKit que si tu veux aussi l'achat in-app Apple.

App Store Connect → ta fiche app → **Monétisation → Achats intégrés / Abonnements** :

1. **Non-consommable** `com.louisbdc.caveos.pro.lifetime` (« CaveOS Pro à vie ») → prix.
2. **Abonnement auto-renouvelable** : créer un **groupe d'abonnement** « CaveOS Pro », puis l'abonnement `com.louisbdc.caveos.pro.yearly` (annuel) → prix, durée, localisations.
3. Pour chaque produit : nom affiché, description, capture de l'écran de paiement (review).
4. Tester d'abord avec un **Sandbox Tester** (Users and Access → Sandbox).

---

## Étape 6 — Préparer le build (version & numéro)

- Dans `project.yml` : `MARKETING_VERSION` (ex. `1.0`) et `CURRENT_PROJECT_VERSION` (build, ex. `1`).
- Chaque upload doit avoir un **build number unique** et croissant.
- **Encryption** : l'app n'utilise que du chiffrement standard (HTTPS). Ajouter dans l'Info.plist `ITSAppUsesNonExemptEncryption = NO` pour éviter le questionnaire export à chaque build (sinon tu répondras « non » dans App Store Connect).

---

## Étape 7 — Archiver et envoyer le build

### Via Xcode (le plus simple)
1. Sélectionner le scheme **CaveOS** + destination **Any iOS Device (arm64)**.
2. **Product → Archive**.
3. Dans l'**Organizer** : **Distribute App → App Store Connect → Upload**.
4. Laisser les options par défaut (signing automatique). Attendre « Upload successful ».

### Via ligne de commande (CI)
```bash
xcodebuild -project CaveOS.xcodeproj -scheme CaveOS -configuration Release \
  -archivePath build/CaveOS.xcarchive archive
xcodebuild -exportArchive -archivePath build/CaveOS.xcarchive \
  -exportOptionsPlist ExportOptions.plist -exportPath build/export
xcrun altool --upload-app -f build/export/CaveOS.ipa -t ios \
  --apiKey <KEY_ID> --apiIssuer <ISSUER_ID>   # ou Transporter.app
```

> Le build mettra **5–30 min** à apparaître (statut « En cours de traitement ») dans App Store Connect → TestFlight.

---

## Étape 8 — TestFlight (tests avant publication)

1. App Store Connect → ta fiche → **TestFlight**.
2. Compléter les **informations de test** (coordonnées, infos de connexion si nécessaire — ici aucune, l'app est offline-first).
3. **Testeurs internes** (jusqu'à 100, membres de l'équipe) : disponibles immédiatement.
4. **Testeurs externes** (jusqu'à 10 000) : nécessitent une **revue Beta** d'Apple (24–48 h).
5. À tester en priorité sur **appareil réel** :
   - **Scan** d'étiquette + code-barres (caméra absente du simulateur)
   - **Paiement** (carte de test `4242 4242 4242 4242` pour Stripe ; Sandbox pour StoreKit)
   - **Sync iCloud** entre 2 appareils
   - **Précision OCR sur 50+ étiquettes réelles** (mesure clé du CDC)

---

## Étape 9 — Fiche App Store (page produit)

App Store Connect → ta fiche → **Distribution / iOS App** → version `1.0`.

### 9.1 Métadonnées (ASO — voir le CDC)
- **Nom (30 car.)** : `CaveOS — Gestion de cave`
- **Sous-titre (30 car.)** : `Inventaire vin hors-ligne & apogée`
- **Mots-clés (100 car.)** : `cave,vin,dégustation,apogée,millésime,cépage,inventaire,sommelier,bouteille,étiquette,scanner,sansabonnement`
- **Description** : raconter l'angle « l'app honnête, sans abonnement obligatoire, qui marche hors-ligne » ; lister les fonctions (scan natif, plan de cave drag&drop, apogée, export, dégustation).
- **Nouveautés de cette version** : « Première version. »
- **URL marketing / support** : page web (ou lien GitHub / mail support).

### 9.2 Visuels
- **Captures d'écran** obligatoires aux tailles iPhone 6,9" et 6,5" (et iPad 12,9" si app iPad) :
  - écran d'**onboarding**, **scan** d'étiquette, **plan de cave** drag&drop, **statut d'apogée**, **recherche/filtres**.
- **Icône** : fournie automatiquement depuis l'asset `AppIcon` (1024×1024, déjà dans le projet).
- **App preview** (vidéo, optionnel) : démo du scan + plan de cave.

### 9.3 Catégorie & classification
- **Catégorie principale** : `Style de vie` (secondaire possible : `Productivité` / `Nourriture et boissons`).
- **Classification par âge** : remplir le questionnaire → probablement **17+** (références à l'alcool) ; répondre honnêtement à « Alcool, tabac, drogues ».

### 9.4 Confidentialité (App Privacy)
- **Politique de confidentialité (URL)** : obligatoire. Héberger une page (ex. `https://caveos.152.228.136.49.sslip.io/privacy` ou GitHub Pages).
- **Nutrition labels** : déclarer les données collectées. CaveOS est offline-first :
  - Données stockées **localement / iCloud privé de l'utilisateur** → souvent « **Données non collectées** » (l'éditeur ne les reçoit pas).
  - Si **Stripe** : email/paiement sont traités par Stripe (déclarer « Informations financières » via un tiers, non liées à l'identité côté éditeur).
- **Camera** : justifié par le scan (chaîne `NSCameraUsageDescription` déjà dans l'Info.plist).

### 9.5 Tarif & disponibilité
- **Prix** : `Gratuit` (les fonctions Pro passent par Stripe et/ou StoreKit).
- **Disponibilité** : pays/régions (par défaut, tous).

---

## Étape 10 — Soumettre pour examen

1. Dans la version : **sélectionner le build** TestFlight validé.
2. Remplir **Informations de revue** : coordonnées, **compte de démo non requis** (offline-first) — le préciser dans les notes.
3. **Notes pour l'examen** : expliquer que l'app fonctionne sans compte, que le scan nécessite la caméra, et — si Stripe — décrire le flux d'abonnement web.
4. **Export Compliance** : répondre « non » au chiffrement non exempté (voir Étape 6).
5. **Soumettre pour examen**. Délai habituel : **24–48 h**.

---

## Étape 11 — Après acceptation

- Choisir **publication manuelle** ou **automatique** dès l'approbation.
- Surveiller **avis & notes** ; solliciter un avis au bon moment dans l'app (`SKStoreReviewController`, après 10 bouteilles ajoutées — voir CDC).
- Itérer l'ASO via les **tests A/B natifs** (App Store Connect, jusqu'à 3 variantes d'icône/captures).

---

## Pièges fréquents (motifs de rejet)

- **Guideline 3.1.1** : abonnement débloquant des fonctions in-app via paiement **externe (Stripe)** → risque de rejet selon la région ; garder la voie **StoreKit** in-app, ou cadrer les *external purchase links*.
- **Politique de confidentialité manquante** ou URL morte.
- **Captures non représentatives** ou aux mauvaises tailles.
- **Classification d'âge** incohérente avec le thème alcool.
- **Achats non testables** par l'examinateur (fournir un chemin de test clair).
- **Métadonnées** mentionnant d'autres plateformes/prix incohérents.

---

Voir aussi : déploiement serveur dans [DEPLOY.md](DEPLOY.md), contexte produit dans [README.md](README.md), spécifications dans [cdc_caveos.md](cdc_caveos.md).
