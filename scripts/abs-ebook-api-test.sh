#!/usr/bin/env bash
# Audiobookshelf: eBook-Struktur eines Library-Items prüfen.
#
# In abstand gibt es zwei Fälle:
#   1) Reines E-Book (Katalog-Filter ebooks.ebook) — oft nur EPUB/PDF, wenig/kein Audio
#   2) Supplementär (ebooks.supplementary) — Hörbuch + EPUB als Zusatzdatei
#      → media.ebookFile, media.ebookFormat und/oder libraryFiles[].isSupplementary
#
# Voraussetzung: jq, curl
#
# Nutzung:
#   export ABS_BASE_URL="https://abs.example.com"
#   export ABS_TOKEN="eyJhbGciOiJI6IkpXVCJ9..."
#   export ABS_ITEM_ID="li_8gch9ve09orgn4fdz8"
#   # optional: Katalog-Vergleich (erste Treffer je Filter)
#   export ABS_LIBRARY_ID="lib_xxxxxxxx"
#   ./scripts/abs-ebook-api-test.sh
#
# Einzeiler (wie in deinem Beispiel):
#   ABS_BASE_URL=... ABS_TOKEN=... ABS_ITEM_ID=li_... ./scripts/abs-ebook-api-test.sh

set -euo pipefail

: "${ABS_BASE_URL:?ABS_BASE_URL setzen (ohne trailing slash)}"
: "${ABS_TOKEN:?ABS_TOKEN setzen}"
: "${ABS_ITEM_ID:?ABS_ITEM_ID setzen}"

ABS_BASE_URL="${ABS_BASE_URL%/}"
OUT_DIR="${OUT_DIR:-/tmp/abs-ebook-test}"
mkdir -p "$OUT_DIR"

if ! command -v jq >/dev/null 2>&1; then
  echo "jq fehlt (brew install jq)" >&2
  exit 1
fi

auth_header() {
  printf 'Authorization: Bearer %s' "$ABS_TOKEN"
}

fetch_item() {
  local expanded="$1"
  local include="$2"
  local out="$3"
  local query="expanded=${expanded}"
  if [[ -n "$include" ]]; then
    query="${query}&include=${include}"
  fi
  curl -sS -f \
    -H "$(auth_header)" \
    -H "Accept: application/json" \
    "${ABS_BASE_URL}/api/items/${ABS_ITEM_ID}?${query}" \
    -o "$out"
}

echo "==> Item ${ABS_ITEM_ID}"
echo "    Server: ${ABS_BASE_URL}"

RAW_EXPANDED="${OUT_DIR}/item-expanded.json"
RAW_MIN="${OUT_DIR}/item-minified.json"

echo "==> GET expanded=1 include=progress,rssfeed,authors"
fetch_item 1 "progress,rssfeed,authors" "$RAW_EXPANDED"
echo "    gespeichert: $RAW_EXPANDED"

echo "==> GET expanded=0 (Vergleich / minified)"
fetch_item 0 "" "$RAW_MIN" || true
if [[ -f "$RAW_MIN" ]]; then
  echo "    gespeichert: $RAW_MIN"
fi

# --- Kompakte Auswertung (Felder, die abstand/ABSModels.swift nutzt) ---
echo ""
echo "=== eBook-Zusammenfassung (expandiert) ==="
jq -r '
  def audiobookish:
    ((.media.numTracks // 0) > 0) or ((.media.duration // 0) > 0);
  def has_ebook_file: (.media.ebookFile != null);
  def has_ebook_format: ((.media.ebookFormat // "") | length) > 0;
  def library_ebooks:
    [.libraryFiles[]? | select(
      (.metadata.format? // "" | ascii_downcase) == "epub"
      or (.metadata.ext? // "" | ascii_downcase | test("epub"))
      or (.metadata.filename? // "" | ascii_downcase | endswith(".epub"))
      or (.metadata.format? // "" | ascii_downcase) == "pdf"
      or (.metadata.filename? // "" | ascii_downcase | endswith(".pdf"))
      or (.fileType? // "" | ascii_downcase | test("ebook"))
    )];
  def classify:
    if audiobookish and (has_ebook_file or has_ebook_format or (library_ebooks | length) > 0) then
      "hoerbuch_mit_ebook_zusatz (supplementary)"
    elif audiobookish then
      "nur_hoerbuch"
    elif (has_ebook_file or has_ebook_format or (library_ebooks | length) > 0) then
      "reines_ebook (ebooks.ebook)"
    else
      "kein_erkennbares_ebook"
    end;
  {
    id,
    libraryId,
    mediaId,
    title: .media.metadata.title,
    author: (.media.metadata.authorName // .media.metadata.author // null),
    classify: classify,
    audiobookish: audiobookish,
    numTracks: .media.numTracks,
    durationSec: .media.duration,
    media_ebookFormat: .media.ebookFormat,
    media_ebookFile: .media.ebookFile,
    libraryFiles_ebook: library_ebooks,
    progress: .userMediaProgress // nur wenn include=progress
  }
' "$RAW_EXPANDED"

echo ""
echo "=== libraryFiles (alle) ==="
jq '.libraryFiles // []' "$RAW_EXPANDED"

echo ""
echo "=== media.ebookFile / media.ebookFormat ==="
jq '{ ebookFile: .media.ebookFile, ebookFormat: .media.ebookFormat }' "$RAW_EXPANDED"

echo ""
echo "=== Roh-JSON Ausschnitt media (metadata + ebook) ==="
jq '.media | { metadata: .metadata, duration, numTracks, size, ebookFile, ebookFormat }' "$RAW_EXPANDED"

# --- Optional: Katalog-Filter wie in AppModel ---
if [[ -n "${ABS_LIBRARY_ID:-}" ]]; then
  FILTER_EBOOK="ebooks.ZWJvb2s="
  FILTER_SUPP="ebooks.c3VwcGxlbWVudGFyeQ=="
  echo ""
  echo "=== Katalog-Vergleich library=${ABS_LIBRARY_ID} (limit=5, minified=0) ==="
  for entry in "primary:${FILTER_EBOOK}" "supplementary:${FILTER_SUPP}"; do
    name="${entry%%:*}"
    f="${entry##*:}"
    out="${OUT_DIR}/catalog-${name}.json"
    curl -sS -f \
      -H "$(auth_header)" \
      "${ABS_BASE_URL}/api/libraries/${ABS_LIBRARY_ID}/items?minified=0&limit=5&page=0&filter=${f}" \
      -o "$out"
    echo "--- filter ${name} (${f}) → ${out}"
    jq '[.results[]? | {
      id,
      title: .media.metadata.title,
      numTracks: .media.numTracks,
      duration: .media.duration,
      ebookFormat: .media.ebookFormat,
      hasEbookFile: (.media.ebookFile != null)
    }]' "$out"
  done
fi

echo ""
echo "=== Diff expanded vs minified (ebook-relevant) ==="
if [[ -f "$RAW_MIN" ]]; then
  jq -n --slurpfile a "$RAW_EXPANDED" --slurpfile b "$RAW_MIN" '
    def pick: {
      ebookFile: .media.ebookFile,
      ebookFormat: .media.ebookFormat,
      libraryFilesCount: (.libraryFiles | length // 0)
    };
    { expanded: pick($a[0]), minified: pick($b[0]) }
  '
else
  echo "(minified nicht geladen)"
fi

echo ""
echo "Fertig. Vollständige Antwort: $RAW_EXPANDED"
echo "Pretty-print: jq . \"$RAW_EXPANDED\" | less"
