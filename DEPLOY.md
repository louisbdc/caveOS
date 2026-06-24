# Mise en ligne de CaveOS

Guide complet pour mettre **l'app iOS** sur l'App Store et **le serveur** (API données vin + abonnement Stripe) en production. Inspiré du déploiement Vide-Grenier, adapté à l'infra réellement en place.

---

## 0. Prérequis

- **Mac** avec Xcode 26+ et [XcodeGen](https://github.com/yonsm/XcodeGen) (`brew install xcodegen`).
- **Compte Apple Developer** payant (99 $/an) pour publier sur l'App Store.
- **VPS OVH** `ubuntu@152.228.136.49` (Ubuntu 26.04), accès SSH avec la clé `~/.ssh/vps_ovh`.
  - **Aucun domaine à acheter** : on utilise **sslip.io** (`caveos.152.228.136.49.sslip.io` → IP), dont Caddy tire un certificat Let's Encrypt gratuit.
- **Compte Stripe** (clé de test pour valider, clé live pour la prod).

---

## 1. Déployer le serveur (API + Stripe) sur le VPS

Le serveur Go (`server/`) sert les données vin, l'enrichissement et l'abonnement Stripe. Il tourne en **systemd** sur le port `8080`, exposé en **HTTPS par le conteneur Caddy** déjà présent sur le VPS.

### 1.1 Secrets (`.env`, jamais committé)

Sur le VPS, dans `/home/ubuntu/caveos-server/.env` (`chmod 600`) :

```ini
STRIPE_SECRET_KEY=sk_live_…            # clé LIVE en prod (rk_ restreinte recommandée)
STRIPE_PRICE_ID=price_…               # abonnement annuel (30 €/an)
STRIPE_LIFETIME_PRICE_ID=price_…      # achat à vie (50 €)
STRIPE_WEBHOOK_SECRET=whsec_…         # secret du webhook (voir §2)
PUBLIC_BASE_URL=https://caveos.152.228.136.49.sslip.io
PORT=8080
```

> ⚠️ Ne **jamais** committer la clé. Le hook `scripts/check-secrets.sh` (pre-commit) bloque tout `sk_`/`rk_`/`whsec_` dans le code versionné.

### 1.2 Build + service

Depuis le Mac, à la racine du repo :

```bash
SSH_KEY=~/.ssh/vps_ovh ./scripts/deploy_server.sh
```

Le script copie les sources, fait `go mod tidy && go build`, installe l'unité systemd (`caveos-server.service`, qui charge `.env` via `EnvironmentFile`), redémarre le service et vérifie `/health`.

```bash
# Vérifications
curl https://caveos.152.228.136.49.sslip.io/health        # {"status":"ok"}
ssh -i ~/.ssh/vps_ovh ubuntu@152.228.136.49 'sudo systemctl status caveos-server'
```

### 1.3 HTTPS (déjà configuré)

Les ports 80/443 sont occupés par un conteneur Caddy existant (`server-caddy-1`). Un **bloc additif** a été ajouté à son `Caddyfile` (`/home/ubuntu/vide-grenier/Server/Caddyfile`) :

```caddy
caveos.152.228.136.49.sslip.io {
    reverse_proxy 172.18.0.1:8080
}
```

Recharger après modif : `sudo docker exec server-caddy-1 caddy reload --config /etc/caddy/Caddyfile`.

---

## 2. Configurer Stripe

### 2.1 Produits & prix

Créés une fois via l'API (ou le Dashboard). Exemple (clé en variable, jamais en clair dans un fichier) :

```bash
# Produit
curl https://api.stripe.com/v1/products -u "$STRIPE_KEY:" -d name="CaveOS Pro"
# Abonnement annuel 30 €
curl https://api.stripe.com/v1/prices -u "$STRIPE_KEY:" \
  -d product=prod_xxx -d unit_amount=3000 -d currency=eur -d "recurring[interval]=year"
# Achat à vie 50 € (paiement unique)
curl https://api.stripe.com/v1/prices -u "$STRIPE_KEY:" \
  -d product=prod_xxx -d unit_amount=5000 -d currency=eur
```

Reporter les `price_…` dans `.env` (`STRIPE_PRICE_ID`, `STRIPE_LIFETIME_PRICE_ID`).

### 2.2 Webhook

```bash
curl https://api.stripe.com/v1/webhook_endpoints -u "$STRIPE_KEY:" \
  -d url="https://caveos.152.228.136.49.sslip.io/v1/billing/webhook" \
  -d "enabled_events[]=checkout.session.completed" \
  -d "enabled_events[]=customer.subscription.updated" \
  -d "enabled_events[]=customer.subscription.deleted"
```

Mettre le `whsec_…` renvoyé dans `STRIPE_WEBHOOK_SECRET`, puis `sudo systemctl restart caveos-server`.

### 2.3 Passage en LIVE

1. Basculer le Dashboard en mode **Live**, recréer produit/prix/webhook en live.
2. Remplacer `STRIPE_SECRET_KEY`/`…PRICE…`/`…WEBHOOK…` par les valeurs live dans `.env`.
3. Idéalement, créer une **clé restreinte (`rk_`)** limitée à Checkout/Billing/Webhooks.

---

## 3. Publier l'app iOS sur l'App Store

### 3.1 Générer le projet

```bash
xcodegen generate
open CaveOS.xcodeproj
```

### 3.2 Signing & capabilities

Dans Xcode → cible **CaveOS** → *Signing & Capabilities* :

- **Team** : sélectionner ton équipe Apple Developer (remplit `DEVELOPMENT_TEAM`).
- **Bundle identifier** : `com.louisbdc.caveos` (ajuste le préfixe si besoin dans `project.yml`).
- Capacités à activer (cohérentes avec `CaveOS/CaveOS.entitlements`) :
  - **iCloud → CloudKit** (conteneur `iCloud.com.louisbdc.caveos`) — sync v2
  - **App Groups** (`group.com.louisbdc.caveos`) — widget
  - **Push Notifications** (`aps-environment`)
  - **In-App Purchase** (si tu conserves la voie StoreKit en plus de Stripe)
- Cibles **CaveOSWidget** et **CaveOSWatch** : leur attribuer un bundle id sous le même préfixe et la même Team.

> Crée les identifiants App ID / App Group / conteneur iCloud correspondants dans [developer.apple.com](https://developer.apple.com) → *Certificates, Identifiers & Profiles*.

### 3.3 StoreKit (optionnel)

L'app propose aussi l'abonnement via **Stripe (web)**, qui ne nécessite **aucun produit App Store Connect**. Si tu veux garder les achats **in-app StoreKit** (« Débloquer à vie » / « Abonnement annuel » via Apple) :

1. Crée les produits dans **App Store Connect → Monétisation** :
   - Non-consommable `com.louisbdc.caveos.pro.lifetime`
   - Abonnement auto-renouvelable `com.louisbdc.caveos.pro.yearly` (groupe « CaveOS Pro »)
2. Renseigne les tarifs et descriptions.

> ⚠️ **Règles App Store** : un abonnement qui débloque des fonctions in-app doit normalement passer par l'achat in-app Apple (guideline 3.1.1). La voie Stripe (lien web externe) relève des *external purchase links*, dont l'éligibilité dépend de la région. Vérifie ta cible avant soumission.

### 3.4 Archive & envoi

Via Xcode : *Product → Archive* → *Distribute App → App Store Connect → Upload*.

Ou en ligne de commande :

```bash
xcodebuild -project CaveOS.xcodeproj -scheme CaveOS \
  -configuration Release -archivePath build/CaveOS.xcarchive archive
xcodebuild -exportArchive -archivePath build/CaveOS.xcarchive \
  -exportOptionsPlist ExportOptions.plist -exportPath build/export
```

> Le build de prod doit pointer la **base persistante** : le bloc `#if DEBUG` de `CaveOSApp.swift` utilise des données d'exemple en mémoire — en `Release`, c'est `AppContainer.makeContainer()` (persistant) qui est utilisé, rien à changer.

### 3.5 TestFlight

Une fois le build traité dans **App Store Connect → TestFlight**, ajoute des testeurs internes/externes. C'est le moment de **mesurer l'OCR sur 50+ étiquettes réelles** et de tester le paiement Stripe (carte de test `4242 4242 4242 4242`).

### 3.6 Fiche App Store & ASO

Dans App Store Connect → *Distribution* :

- **Titre (30 car.)** : `CaveOS — Gestion de cave`
- **Sous-titre (30 car.)** : `Inventaire vin hors-ligne & apogée`
- **Mots-clés (100 car.)** : `cave,vin,dégustation,apogée,millésime,cépage,inventaire,sommelier,bouteille,étiquette,scanner,sansabonnement`
- **Captures** : scan natif, plan de cave drag&drop, statut d'apogée, onboarding.
- **Confidentialité** : déclarer la caméra (scan), aucune collecte de données (offline-first), iCloud privé.
- **Vie privée des données** : préciser que les données restent locales/iCloud privé, pas de revente.

### 3.7 Soumission

Remplir la version, sélectionner le build TestFlight, répondre au questionnaire (chiffrement : usage standard HTTPS), puis **Soumettre pour examen**.

---

## 4. Checklist go-live

- [ ] `curl https://caveos.152.228.136.49.sslip.io/health` → `ok`
- [ ] Stripe en **live** (clé, produits, prix, webhook) ; webhook reçoit les events
- [ ] Clé Stripe restreinte `rk_` + clé de test régénérée
- [ ] App signée (Team + bundle ids widget/watch), capacités iCloud/AppGroup/Push OK
- [ ] Archive uploadée, build TestFlight validé sur appareil réel (scan, achat, sync)
- [ ] Fiche App Store remplie (titre/sous-titre/mots-clés/captures/confidentialité)
- [ ] Précision OCR mesurée sur 50+ étiquettes réelles
- [ ] Soumis pour examen

---

Pour le contexte produit et l'architecture, voir [README.md](README.md) et le cahier des charges [cdc_caveos.md](cdc_caveos.md).
