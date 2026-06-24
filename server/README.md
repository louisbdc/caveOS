# caveos-server

API Go pour les données de référence vin de **caveOS** (cépages, régions, appellations) et l'enrichissement heuristique des bouteilles (fenêtre d'apogée estimée).

Le VPS héberge ce service. L'app iOS reste **offline-first** (CloudKit pour la sync perso) ; elle peut télécharger la base SQLite via `/v1/db/latest` pour fonctionner hors-ligne.

## Caractéristiques

- **Go modules**, stdlib `net/http` (pas de framework lourd).
- **SQLite pur-Go** via `modernc.org/sqlite` (**PAS de CGO**) → binaire statique.
- Logs structurés (`log/slog`, JSON), middleware de log et CORS permissif (GET).
- Au démarrage : ouvre/crée `wine.db`, crée les tables si absentes, seed depuis `seed.json` si la base est vide.

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
| GET | `/v1/db/latest` | Sert `wine.db` (`application/octet-stream`) pour distribution hors-ligne. |
| GET | `/credits` | Texte d'attribution des licences (Wikidata CC0, INAO Licence Ouverte, LWIN CC). |

### Heuristique d'enrichissement

Pour `/v1/enrich`, le service :

1. tente de matcher une **appellation** (→ sa région parente) ou une **région** dans le nom ;
2. tente de matcher un **cépage** dans le nom (sinon, valeurs par défaut rouge médium si une région est trouvée) ;
3. calcule la fenêtre : `vintage + (apogeeMin/Peak/Max du cépage × multiplicateur du tier de la région)`.

Multiplicateur par tier de qualité de région : tier 3 → ×1.3, tier 2 → ×1.1, tier 1 → ×0.9.

C'est la **même heuristique** que celle embarquée dans l'app iOS.

### Exemples

```sh
curl 'http://localhost:8080/health'
curl 'http://localhost:8080/v1/wines/search?q=saint'
curl 'http://localhost:8080/v1/enrich?name=Barolo%20Nebbiolo&vintage=2018'
curl -O 'http://localhost:8080/v1/db/latest'
curl 'http://localhost:8080/credits'
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
