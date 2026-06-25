# caveos-server

API Go pour les données de référence vin de **caveOS** (cépages, régions, appellations) et l'enrichissement heuristique des bouteilles (fenêtre d'apogée estimée).

Le VPS héberge ce service. L'app iOS reste **offline-first** (CloudKit pour la sync perso) ; elle peut télécharger la base SQLite via `/v1/db/latest` pour fonctionner hors-ligne.

## Caractéristiques

- **Go modules**, stdlib `net/http` (pas de framework lourd).
- **SQLite pur-Go** via `modernc.org/sqlite` (**PAS de CGO**) → binaire statique.
- Logs structurés (`log/slog`, JSON), middleware de log et CORS permissif (GET + POST).
- Au démarrage : ouvre/crée `wine.db`, crée les tables si absentes, seed depuis `seed.json` si la base est vide.
- **Scan d'étiquette par IA** (`POST /v1/scan`) : proxy multi-fournisseurs (Mistral OCR, Google Gemini) ; les clés d'API restent côté serveur (`.env`).

## Build & Run

```sh
# Récupérer les dépendances
go mod tidy

# Build (binaire statique, sans CGO)
CGO_ENABLED=0 go build -o caveos-server

# Lancer
./caveos-server
```

Le serveur écoute sur le port défini par `PORT` (défaut `8080`).

```sh
PORT=9090 ./caveos-server
```

`wine.db` et `seed.json` doivent se trouver dans le répertoire de travail.

## Cross-compilation pour le VPS (Linux amd64)

```sh
CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o caveos-server
```

## Endpoints

Tous les endpoints renvoient du JSON (sauf `/v1/db/latest` et `/credits`).

| Méthode | Chemin | Description |
|---|---|---|
| GET | `/health` | `{"status":"ok"}` |
| GET | `/v1/wines/search?q=...` | Recherche `LIKE` sur appellations + cépages + régions. Renvoie `{grapes:[],appellations:[],regions:[]}`. |
| GET | `/v1/grapes` | Liste complète des cépages. |
| GET | `/v1/regions` | Liste complète des régions. |
| GET | `/v1/appellations` | Liste complète des appellations. |
| GET | `/v1/enrich?name=...&vintage=YYYY` | Heuristique d'apogée. Renvoie `{drinkFrom,peak,drinkBy,...}`. |
| POST | `/v1/scan` | Scan d'étiquette par IA. Body `{provider,image,mimeType}`. Renvoie les champs structurés (voir ci-dessous). |
| GET | `/v1/db/latest` | Sert `wine.db` (`application/octet-stream`) pour distribution hors-ligne. |
| GET | `/credits` | Texte d'attribution des licences (Wikidata CC0, INAO Licence Ouverte, LWIN CC). |

### Heuristique d'enrichissement

Pour `/v1/enrich`, le service :

1. tente de matcher une **appellation** (→ sa région parente) ou une **région** dans le nom ;
2. tente de matcher un **cépage** dans le nom (sinon, valeurs par défaut rouge médium si une région est trouvée) ;
3. calcule la fenêtre : `vintage + (apogeeMin/Peak/Max du cépage × multiplicateur du tier de la région)`.

Multiplicateur par tier de qualité de région : tier 3 → ×1.3, tier 2 → ×1.1, tier 1 → ×0.9.

C'est la **même heuristique** que celle embarquée dans l'app iOS.

### Scan d'étiquette par IA (`POST /v1/scan`)

Reçoit une image (base64) et la confie au fournisseur d'IA demandé, qui renvoie les
champs structurés de l'étiquette. L'app garde par défaut l'analyse 100 % locale
(Apple Vision) ; ce mode IA est opt-in et réservé aux abonnés Pro côté app.

**Requête** (`Content-Type: application/json`) :

```json
{
  "provider": "mistral",          // ou "gemini"
  "image": "<base64 de l'image>", // sans préfixe data:
  "mimeType": "image/jpeg"        // optionnel, défaut image/jpeg
}
```

**Réponse** (champs vides omis) :

```json
{
  "producer": "Château Margaux",
  "wineName": "Pavillon Rouge",
  "vintage": 2015,
  "appellation": "Margaux",
  "grapes": ["Cabernet Sauvignon", "Merlot"],
  "format": "75 cl",
  "abv": "13,5 %",
  "provider": "mistral"
}
```

**Variables d'environnement** (fichier `.env` du VPS, chmod 600, hors git) :

| Variable | Rôle |
|---|---|
| `MISTRAL_API_KEY` | Active le fournisseur `mistral`. Absente → `503` pour ce fournisseur. |
| `GEMINI_API_KEY` | Active le fournisseur `gemini`. Absente → `503` pour ce fournisseur. |
| `MISTRAL_OCR_MODEL` | Optionnel. Modèle Mistral (défaut `mistral-ocr-latest`). |
| `GEMINI_MODEL` | Optionnel. Modèle Gemini (défaut `gemini-2.5-flash`). |
| `CAVEOS_SCAN_KEY` | Optionnel. Secret partagé : si défini, l'en-tête `X-CaveOS-Key` est exigé. Absent → endpoint ouvert (pratique pour tester). |

Ajouter un nouveau fournisseur = implémenter `scanProvider` et l'enregistrer dans
`newScanProviders` (`scan.go`). Limite anti-abus : 20 requêtes/minute par IP.

### Exemples

```sh
curl 'http://localhost:8080/health'
curl 'http://localhost:8080/v1/wines/search?q=saint'
curl 'http://localhost:8080/v1/enrich?name=Barolo%20Nebbiolo&vintage=2018'
curl -O 'http://localhost:8080/v1/db/latest'
curl 'http://localhost:8080/credits'

# Scan IA (image encodée en base64)
B64=$(base64 -i etiquette.jpg)
curl -X POST 'http://localhost:8080/v1/scan' \
  -H 'Content-Type: application/json' \
  -d "{\"provider\":\"mistral\",\"image\":\"$B64\",\"mimeType\":\"image/jpeg\"}"
```

## Déploiement (VPS, systemd)

```sh
# 1. Construire pour Linux
CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o caveos-server

# 2. Copier les artefacts sur le VPS
scp caveos-server seed.json ubuntu@VPS:/home/ubuntu/caveos-server/

# 3. Installer le service systemd
scp caveos-server.service ubuntu@VPS:/tmp/
ssh ubuntu@VPS 'sudo mv /tmp/caveos-server.service /etc/systemd/system/ \
  && sudo systemctl daemon-reload \
  && sudo systemctl enable --now caveos-server'

# 4. Vérifier
ssh ubuntu@VPS 'systemctl status caveos-server'
ssh ubuntu@VPS 'journalctl -u caveos-server -f'
```

`wine.db` est créé automatiquement au premier démarrage à partir de `seed.json`.

Placez un reverse-proxy (nginx/Caddy) devant le service pour le TLS si nécessaire.

## Licences des données

Voir l'endpoint `/credits` : Wikidata (CC0), INAO (Licence Ouverte / Etalab), LWIN (CC).
