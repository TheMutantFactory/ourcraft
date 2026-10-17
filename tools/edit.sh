#!/usr/bin/env bash
# Open the project in the Godot editor.
set -euo pipefail
source "$(dirname "$0")/_godot.sh"
exec "$GODOT_BIN" --path "$ROOT" --editor
