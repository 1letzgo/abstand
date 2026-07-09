#!/bin/zsh

# ci_post_clone.sh — Xcode Cloud
#
# Setzt CURRENT_PROJECT_VERSION automatisch auf die Xcode-Cloud-Build-Nummer,
# damit jeder CI-Build eine eindeutige, monoton steigende Build-Nummer hat.
# Der lokal in project.pbxproj hinterlegte Wert (z. B. „1") bleibt unangetastet —
# das Skript überschreibt ihn nur im frisch geklonten CI-Checkout.
#
# Doku: https://developer.apple.com/documentation/xcode/setting-the-next-build-number-for-xcode-cloud-builds

set -euo pipefail

# Build-Nummer aus dem Xcode-Cloud-Umfeld; Fallback für lokale Tests.
build_number="${CI_BUILD_NUMBER:-1}"

echo "ci_post_clone: setze CURRENT_PROJECT_VERSION auf ${build_number}"

cd "$CI_PRIMARY_REPOSITORY_PATH"

# Alle Vorkommen von CURRENT_PROJECT_VERSION ersetzen (Debug + Release).
sed -i '' -e "s/CURRENT_PROJECT_VERSION = .*/CURRENT_PROJECT_VERSION = ${build_number};/" abstand.xcodeproj/project.pbxproj

echo "ci_post_clone: fertig"
