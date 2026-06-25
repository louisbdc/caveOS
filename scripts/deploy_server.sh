#!/usr/bin/env bash
# Déploiement du serveur CaveOS sur le VPS.
# Usage: ./scripts/deploy_server.sh
set -euo pipefail

VPS_USER=ubuntu
VPS_HOST=152.228.136.49
SSH_KEY="${SSH_KEY:-$HOME/.ssh/vps_ovh}"
REMOTE_DIR=/home/ubuntu/caveos-server
GO_BIN=/usr/local/go/bin/go

SSH="ssh -i $SSH_KEY -o ConnectTimeout=15 $VPS_USER@$VPS_HOST"
SCP="scp -i $SSH_KEY"

echo "==> Préparation du dossier distant"
$SSH "mkdir -p $REMOTE_DIR"

echo "==> Copie des sources du serveur (le fichier .env du VPS n'est jamais copié)"
# Tous les .go de production sont copiés automatiquement ; les *_test.go restent
# locaux (non nécessaires en prod). Ajouter un nouveau fichier .go ne demande
# donc aucune modification de ce script.
GO_SOURCES=$(ls server/*.go | grep -v '_test\.go$')
$SCP $GO_SOURCES server/go.mod server/seed.json server/README.md server/caveos-server.service \
     "$VPS_USER@$VPS_HOST:$REMOTE_DIR/"
# go.sum si présent
[ -f server/go.sum ] && $SCP server/go.sum "$VPS_USER@$VPS_HOST:$REMOTE_DIR/" || true

echo "==> Retrait de l'ancien billing.go côté VPS (paiement désormais 100 % StoreKit)"
$SSH "rm -f $REMOTE_DIR/billing.go"

echo "==> Build sur le VPS"
$SSH "cd $REMOTE_DIR && $GO_BIN env -w GOFLAGS=-mod=mod && $GO_BIN mod tidy && $GO_BIN build -o caveos-server . && echo 'build OK'"

echo "==> Installation du service systemd"
$SSH "sudo cp $REMOTE_DIR/caveos-server.service /etc/systemd/system/caveos-server.service && \
      sudo systemctl daemon-reload && \
      sudo systemctl enable caveos-server && \
      sudo systemctl restart caveos-server && \
      sleep 1 && sudo systemctl --no-pager status caveos-server | head -8"

echo "==> Vérification de l'endpoint /health"
$SSH "curl -s http://127.0.0.1:8080/health || true"
echo
echo "Déploiement terminé."
