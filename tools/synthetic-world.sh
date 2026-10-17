#!/usr/bin/env bash
# Build a synthetic deep-and-wide tree of random words, flat on the ground.
#   tools/synthetic-world.sh [--seed=1] [--depth=14] [--width=5] [--roots=12]
#       [--share=0.2] [--max=6000] [--mutations=0] [--out=user://projects/synthetic.ourcraft]
# Uses WordNet nouns if tools/fetch-wordnet.sh has run, else made-up words.
set -euo pipefail
source "$(dirname "$0")/_godot.sh"
ensure_imported
exec "$GODOT_BIN" --headless --path "$ROOT" --script res://tools/gen/synthetic_world.gd -- "$@"
