#!/usr/bin/env bash
# A Katamari Damacy-style demo: roll up things smaller than the ball until
# it can roll up big things. Each object size is its own block size and
# colour. Starts on a fresh world every time (Ctrl+S saves it to
# user://projects/katamari-scratch.ourcraft).
#   tools/katamari.sh             WASD roll · mouse turns · P autopilot
#   tools/katamari.sh --auto      start on autopilot
#   tools/katamari.sh --soak=60   autopilot for 60 s, check, report, quit
set -euo pipefail
source "$(dirname "$0")/_godot.sh"
native_hint
ensure_imported
exec "$GODOT_BIN" --path "$ROOT" -- --scenario=katamari "$@"
