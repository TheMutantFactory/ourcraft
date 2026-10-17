#!/usr/bin/env bash
# Run the stress test and write docs/perf/stress-latest.md.
#   tools/stress.sh [heavy|many|all] [--max=N]    (N: largest power of ten, default 5)
# Opens a window: frame times are measured with real rendering, vsync off.
set -euo pipefail
source "$(dirname "$0")/_godot.sh"
native_hint
ensure_imported
suite="${1:-all}"
shift || true
exec "$GODOT_BIN" --path "$ROOT" res://scenes/stress.tscn -- --suite="$suite" "$@"
