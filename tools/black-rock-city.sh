#!/usr/bin/env bash
# Build a roughly 1:1 Black Rock City (Burning Man) test level: the Man,
# Temple, Esplanade and lettered streets, radials, plazas, Center Camp,
# street signs, thousands of instanced camps, playa art and the trash fence.
#   tools/black-rock-city.sh [--seed=1] [--density=0.35] [--out=user://projects/black-rock-city.ourcraft]
# Then open it with: tools/run.sh --project=user://projects/black-rock-city.ourcraft
set -euo pipefail
source "$(dirname "$0")/_godot.sh"
ensure_imported
"$GODOT_BIN" --headless --path "$ROOT" --script res://tools/gen/black_rock_city.gd -- "$@"
