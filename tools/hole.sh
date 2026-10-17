#!/usr/bin/env bash
# The hole scenario: clouds drop word trees into a hole that destroys what
# touches it. Runs on its own scratch project (user://projects/hole.ourcraft
# is not saved unless you press Ctrl+S).
#   tools/hole.sh                 watch it
#   tools/hole.sh --soak=120      run 120 s, check invariants, report, quit
set -euo pipefail
source "$(dirname "$0")/_godot.sh"
native_hint
ensure_imported
exec "$GODOT_BIN" --path "$ROOT" -- --scenario=hole --project=user://projects/hole-scratch.ourcraft "$@"
