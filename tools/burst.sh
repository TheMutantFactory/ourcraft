#!/usr/bin/env bash
# The burst scenario: platforms with gradient-coloured words that burst into
# flying cubes. Runs on its own scratch project (only saved with Ctrl+S).
#   tools/burst.sh                 watch it (B bursts the selected/aimed object)
#   tools/burst.sh --soak=60       run 60 s, check invariants, report, quit
set -euo pipefail
source "$(dirname "$0")/_godot.sh"
native_hint
ensure_imported
exec "$GODOT_BIN" --path "$ROOT" -- --scenario=burst --project=user://projects/burst-scratch.ourcraft "$@"
