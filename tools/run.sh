#!/usr/bin/env bash
# Launch the game. Extra arguments go to the game after "--", e.g.
#   tools/run.sh --demo                 start from a fresh demo street
#   tools/run.sh --shot=out.png         save a screenshot and quit
set -euo pipefail
source "$(dirname "$0")/_godot.sh"
native_hint
ensure_imported
if [[ $# -gt 0 ]]; then
	exec "$GODOT_BIN" --path "$ROOT" -- "$@"
fi
exec "$GODOT_BIN" --path "$ROOT"
