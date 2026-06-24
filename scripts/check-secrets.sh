#!/usr/bin/env bash
# Bloque tout commit contenant une clé secrète (Stripe ou autre).
# Installé comme hook : ln -sf ../../scripts/check-secrets.sh .git/hooks/pre-commit
set -euo pipefail

# Motifs de secrets à interdire dans le code versionné.
PATTERN='sk_live_[0-9A-Za-z]|sk_test_[0-9A-Za-z]|rk_live_[0-9A-Za-z]|rk_test_[0-9A-Za-z]|whsec_[0-9A-Za-z]|-----BEGIN [A-Z ]*PRIVATE KEY-----'

# Fichiers indexés (ou tout le dépôt si exécuté manuellement).
if git rev-parse --verify HEAD >/dev/null 2>&1; then
  files=$(git diff --cached --name-only --diff-filter=ACM)
else
  files=$(git diff --cached --name-only --diff-filter=ACM 2>/dev/null || true)
fi

found=0
for f in $files; do
  [ -f "$f" ] || continue
  # Le script de détection contient les motifs par nature : on l'ignore.
  case "$f" in scripts/check-secrets.sh) continue;; esac
  if grep -nIE "$PATTERN" "$f" >/dev/null 2>&1; then
    echo "⛔ Secret potentiel détecté dans: $f"
    grep -nIE "$PATTERN" "$f" | sed 's/\(....\).*/\1…(masqué)/'
    found=1
  fi
done

if [ "$found" -ne 0 ]; then
  echo "Commit bloqué. Les secrets ne doivent JAMAIS être versionnés (utilisez une variable d'environnement)."
  exit 1
fi
exit 0
