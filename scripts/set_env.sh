#!/usr/bin/env bash
# Met à jour (upsert) une variable du fichier .env du serveur CaveOS sur le VPS,
# depuis le PC, puis redémarre le service pour appliquer.
#
# La valeur (secrète) transite par STDIN ou par une saisie masquée : elle
# n'apparaît jamais dans les arguments de commande (donc ni dans `ps`, ni dans
# l'historique du shell) et n'est jamais affichée ni journalisée.
#
# Usage :
#   ./scripts/set_env.sh MISTRAL_API_KEY                # demande la valeur (saisie masquée)
#   ./scripts/set_env.sh GEMINI_API_KEY "la-valeur"     # valeur en argument (moins sûr : historique)
#   pbpaste | ./scripts/set_env.sh MISTRAL_API_KEY -    # valeur lue sur STDIN ("-")
#   ./scripts/set_env.sh GEMINI_MODEL gemini-2.5-flash --no-restart
#   ./scripts/set_env.sh --list                         # liste les clés présentes (sans les valeurs)
#   ./scripts/set_env.sh --unset CAVEOS_SCAN_KEY        # supprime une clé
set -euo pipefail

VPS_USER=ubuntu
VPS_HOST=152.228.136.49
SSH_KEY="${SSH_KEY:-$HOME/.ssh/vps_ovh}"
REMOTE_DIR=/home/ubuntu/caveos-server
ENV_FILE="$REMOTE_DIR/.env"
SERVICE=caveos-server

SSH=(ssh -i "$SSH_KEY" -o ConnectTimeout=15 "$VPS_USER@$VPS_HOST")

die() { echo "Erreur : $*" >&2; exit 1; }

usage() {
  sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

# --- Sous-commandes sans secret ----------------------------------------------

case "${1:-}" in
  -h|--help|"")
    usage 0
    ;;
  --list)
    echo "==> Clés présentes dans $ENV_FILE (valeurs masquées) :"
    "${SSH[@]}" "grep -oE '^[A-Za-z_][A-Za-z0-9_]*=' '$ENV_FILE' 2>/dev/null | sed 's/=$//' | sort || echo '(.env absent ou vide)'"
    exit 0
    ;;
  --unset)
    KEY="${2:-}"
    [[ "$KEY" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || die "nom de clé invalide : '${KEY}'"
    "${SSH[@]}" "set -eu
      umask 077
      [ -f '$ENV_FILE' ] || { echo '(.env absent)'; exit 0; }
      TMP=\$(mktemp)
      grep -v '^$KEY=' '$ENV_FILE' > \"\$TMP\" 2>/dev/null || true
      mv \"\$TMP\" '$ENV_FILE'
      chmod 600 '$ENV_FILE'
      echo 'OK : clé $KEY supprimée'"
    RESTART=1
    shift 2 || true
    ;;
esac

# --- Upsert d'une clé ---------------------------------------------------------

if [[ "${KEY:-}" == "" ]]; then
  KEY="${1:-}"
  [[ "$KEY" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || die "nom de clé invalide : '${KEY}'. Attendu : LETTRES_MAJUSCULES."
  shift || true

  RESTART=1
  VALUE=""
  VALUE_SET=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --no-restart) RESTART=0 ;;
      -) VALUE="$(cat)"; VALUE_SET=1 ;;          # valeur lue sur STDIN
      *) VALUE="$1"; VALUE_SET=1 ;;              # valeur en argument
    esac
    shift
  done

  # Saisie masquée si la valeur n'a pas été fournie autrement.
  if [ "$VALUE_SET" -eq 0 ]; then
    printf 'Valeur pour %s (saisie masquée) : ' "$KEY" >&2
    IFS= read -rs VALUE
    echo >&2
  fi
  [ -n "$VALUE" ] || die "valeur vide pour $KEY (utilisez --unset pour supprimer une clé)."

  # Le script distant lit KEY (argument sûr) et la valeur sur STDIN.
  REMOTE_SCRIPT="set -eu
umask 077
touch '$ENV_FILE'
VALUE=\"\$(cat)\"
TMP=\"\$(mktemp)\"
grep -v '^$KEY=' '$ENV_FILE' 2>/dev/null > \"\$TMP\" || true
printf '%s=%s\n' '$KEY' \"\$VALUE\" >> \"\$TMP\"
mv \"\$TMP\" '$ENV_FILE'
chmod 600 '$ENV_FILE'
echo \"OK : clé $KEY enregistrée (\${#VALUE} caractères) dans $ENV_FILE\""

  printf '%s' "$VALUE" | "${SSH[@]}" "$REMOTE_SCRIPT"
fi

# --- Redémarrage du service ---------------------------------------------------

if [ "${RESTART:-1}" -eq 1 ]; then
  echo "==> Redémarrage de $SERVICE pour appliquer le changement"
  "${SSH[@]}" "sudo systemctl restart $SERVICE && sleep 1 && \
    systemctl is-active $SERVICE && curl -s http://127.0.0.1:8080/health && echo"
else
  echo "==> Service NON redémarré (--no-restart). Pensez à : sudo systemctl restart $SERVICE"
fi
