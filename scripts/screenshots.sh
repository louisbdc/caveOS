#!/usr/bin/env bash
# Génère les captures d'écran App Store en pilotant l'app de démo via XCUITest.
#
# Pré-requis : Xcode + XcodeGen. L'app démarre sur SampleData (DEBUG) : les écrans
# sont déjà peuplés. Le test `CaveOSUITests/ScreenshotUITests` parcourt les onglets
# et joint les captures au .xcresult ; on les extrait ensuite côté hôte.
#
# Usage : ./scripts/screenshots.sh
# Sortie : AppStore/screenshots/<appareil>/<NN-Ecran>.png
set -euo pipefail

cd "$(dirname "$0")/.."
PROJECT=CaveOS.xcodeproj
SCHEME=CaveOS
DD=build/dd
OUT=AppStore/screenshots

xcodegen generate >/dev/null

# run_device <label> <nom-simulateur> <os> [rotation_sips]
# rotation_sips : degrés clockwise à appliquer aux PNG (iPad capturé en paysage =>
# XCUIScreen rend le buffer natif portrait ; 270 le redresse en paysage upright).
run_device() {
  local label="$1" name="$2" os="$3" rotate="${4:-}"
  echo "==> ${label}  (${name}, iOS ${os})"

  local id
  id=$(xcrun simctl list devices | grep -F "${name} (" | grep -oE "[0-9A-F-]{36}" | head -1)
  if [ -z "${id}" ]; then
    echo "   ⚠️  simulateur introuvable : ${name} — créez-le puis relancez." >&2
    return 1
  fi

  xcrun simctl boot "${id}" 2>/dev/null || true
  xcrun simctl bootstatus "${id}" 2>/dev/null || true
  # Barre d'état figée (convention App Store : 9:41, batterie pleine, signal complet).
  xcrun simctl status_bar "${id}" override \
    --time "09:41" --batteryState charged --batteryLevel 100 \
    --cellularBars 4 --cellularMode active --wifiBars 3 --wifiMode active 2>/dev/null || true

  local result="build/results/${label}.xcresult"
  rm -rf "${result}"
  xcodebuild test \
    -project "${PROJECT}" -scheme "${SCHEME}" \
    -destination "platform=iOS Simulator,id=${id}" \
    -derivedDataPath "${DD}" \
    -resultBundlePath "${result}" \
    -only-testing:CaveOSUITests \
    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO

  local raw="build/results/${label}-raw"
  rm -rf "${raw}"
  xcrun xcresulttool export attachments --path "${result}" --output-path "${raw}"

  local dest="${OUT}/${label}"
  rm -rf "${dest}"
  python3 scripts/_rename_screens.py "${raw}" "${dest}"

  if [ -n "${rotate}" ]; then
    echo "   redressement des captures (${rotate}°)"
    for f in "${dest}"/*.png; do sips -r "${rotate}" "$f" >/dev/null; done
  fi
}

run_device "iphone-6.5" "iPhone 11 Pro Max"      "26.0"
run_device "ipad-13"    "iPad Pro 13-inch (M4)"  "26.0"

echo
echo "✅ Captures dans ${OUT}/"
find "${OUT}" -name '*.png' | sort