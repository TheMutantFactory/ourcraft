#!/usr/bin/env bash
# Run the headless core tests. Exits non-zero if any check fails.
set -euo pipefail
source "$(dirname "$0")/_godot.sh"
ensure_imported
exec "$GODOT_BIN" --headless --path "$ROOT" --script res://tests/run_tests.gd
