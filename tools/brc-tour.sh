#!/usr/bin/env bash
# Walk a cube along every intersection of Black Rock City's streets once (a
# Hamiltonian path), from Center Camp, leaving a magenta-to-chartreuse trail.
# Builds the city first if it isn't there yet (tools/black-rock-city.sh).
#   tools/brc-tour.sh                    watch ([ ] speed, P pause, V camera)
#   tools/brc-tour.sh --speed=80         start faster (m/s; default 20)
#   tools/brc-tour.sh --soak=30 --speed=320   run 30 s, check, report, quit
set -euo pipefail
source "$(dirname "$0")/_godot.sh"
native_hint
ensure_imported
project="user://projects/black-rock-city.ourcraft"
# Godot's user:// folder (macOS, then Linux).
manifest="projects/black-rock-city.ourcraft/manifest.json"
user_dir="$HOME/Library/Application Support/Godot/app_userdata/Ourcraft"
[ -d "$user_dir" ] || user_dir="${XDG_DATA_HOME:-$HOME/.local/share}/godot/app_userdata/Ourcraft"
if ! grep -q '"roads"' "$user_dir/$manifest" 2>/dev/null; then
  echo "Building Black Rock City (with its street grid) first..."
  "$GODOT_BIN" --headless --path "$ROOT" --script res://tools/gen/black_rock_city.gd -- --out="$project"
fi
exec "$GODOT_BIN" --path "$ROOT" -- --scenario=tour --project="$project" "$@"
