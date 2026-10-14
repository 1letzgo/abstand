#!/bin/bash
# Erzeugt die Abgleich-Goldens mit dem unveränderten iOS-Code (macOS + Swift nötig):
#   alignment/<fall>.json, alignment/tokenization.json, alignment/unicode_tables.json
# und prüft, dass iOS die vom Kotlin-Writer geschriebenen transcript_cache/-Dateien identisch liest.
# Aufruf aus beliebigem Verzeichnis: shared/fixtures/alignment/generator/generate.sh
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../../../.." && pwd)"
OUT="$ROOT/shared/fixtures/alignment"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Abgleich + Tokenisierung: EbookAudioAlignment.swift (bis vor „Speicher") + ReadAlongText.
{ echo "import Foundation"
  sed -n '2,/^\/\/ MARK: - Speicher/p' "$ROOT/abstand/EbookAudioAlignment.swift" | sed '$d'
  sed -n '/^nonisolated enum ReadAlongText/,/^}/p' "$ROOT/abstand/EbookReadAlong.swift"
  cat "$HERE/gen_main.swift"; } > "$TMP/main.swift"
swiftc -O "$TMP/main.swift" -o "$TMP/gen"
"$TMP/gen" "$HERE/cases" "$OUT"

swiftc -O "$HERE/unicode_table.swift" -o "$TMP/unicode_table"
"$TMP/unicode_table" "$OUT/unicode_tables.json"

# iOS liest die Kotlin-Dateien (nur EbookTrackAlignment aus dem iOS-Code).
{ echo "import Foundation"; echo "import CryptoKit"
  sed -n '/^nonisolated struct EbookTrackAlignment/,/^}/p' "$ROOT/abstand/EbookAudioAlignment.swift"
  grep -v '^import CryptoKit' "$HERE/verify_main.swift"; } > "$TMP/verify.swift"
swiftc "$TMP/verify.swift" -o "$TMP/verify"
"$TMP/verify" "$ROOT/shared/fixtures/transcript_cache"
