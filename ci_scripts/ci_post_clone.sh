#!/bin/zsh

# ci_post_clone.sh — Xcode Cloud
#
# Setzt CURRENT_PROJECT_VERSION auf einen zeitstempelbasierten Build-Code
# (YYJJJMMTTSS), der garantiert eindeutig und monoton steigend ist — unabhängig
# davon, was bereits in App Store Connect / TestFlight hochgeladen wurde.
#
# `CI_BUILD_NUMBER` beginnt bei einem neuen Workflow bei 1 und ist damit oft
# NIEDRIGER als bereits hochgeladene Builds → Validierungsfehler
# „bundle version must be higher than the previously uploaded version".
# Ein Zeitstempel umgeht das Problem dauerhaft.
#
# Doku: https://developer.apple.com/documentation/xcode/setting-the-next-build-number-for-xcode-cloud-builds

set -euo pipefail

# Zeitstempel-basierter Build-Code: YYJJJMMTTSS (z. B. 261907091438).
# Fallback auf CI_BUILD_NUMBER, falls der Zeitstempel leer bleibt (lokaler Test).
build_number="$(date -u +%y%Y%m%d%H%M)"
if [[ -z "$build_number" || "$build_number" -lt 1 ]]; then
  build_number="${CI_BUILD_NUMBER:-1}"
fi

echo "ci_post_clone: setze CURRENT_PROJECT_VERSION auf ${build_number}"

cd "$CI_PRIMARY_REPOSITORY_PATH"

# Alle Vorkommen von CURRENT_PROJECT_VERSION ersetzen (Debug + Release).
sed -i '' -e "s/CURRENT_PROJECT_VERSION = .*/CURRENT_PROJECT_VERSION = ${build_number};/" abstand.xcodeproj/project.pbxproj

echo "ci_post_clone: fertig"
