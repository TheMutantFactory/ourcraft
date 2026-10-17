#!/usr/bin/env bash
# Download Open English WordNet (2025, JSON export, CC-BY 4.0) into
# data/wordnet/, which is git-ignored. See docs/bibliography.md.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
URL="https://en-word.net/downloads/english-wordnet-2025-json.zip"
DEST="$ROOT/data/wordnet"
if [[ -d "$DEST/json" ]] && [[ -n "$(ls -A "$DEST/json" 2>/dev/null)" ]]; then
	echo "WordNet already in $DEST/json"
	exit 0
fi
mkdir -p "$DEST"
curl -fL --retry 3 -o "$DEST/english-wordnet-2025-json.zip" "$URL"
rm -rf "$DEST/json"
mkdir -p "$DEST/json"
unzip -q "$DEST/english-wordnet-2025-json.zip" -d "$DEST/json"
echo "WordNet unpacked into $DEST/json"
