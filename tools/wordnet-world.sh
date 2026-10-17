#!/usr/bin/env bash
# Build a test world from Open English WordNet's part-of relations: every
# object is its word written in blocks, and its parts are smaller words in
# front of it. Downloads WordNet on first use (tools/fetch-wordnet.sh).
#   tools/wordnet-world.sh [out folder]   (default user://projects/wordnet.ourcraft)
# Then open it with: tools/run.sh --project=user://projects/wordnet.ourcraft
set -euo pipefail
source "$(dirname "$0")/_godot.sh"
"$ROOT/tools/fetch-wordnet.sh"
ensure_imported
out="${1:-user://projects/wordnet.ourcraft}"
"$GODOT_BIN" --headless --path "$ROOT" --script res://tools/gen/wordnet_world.gd -- --out="$out"
echo "Open it with: tools/run.sh --project=$out"
