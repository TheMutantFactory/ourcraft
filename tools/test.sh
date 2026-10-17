#!/usr/bin/env bash
# Run the headless core tests. Exits non-zero if any check fails.
set -euo pipefail
source "$(dirname "$0")/_godot.sh"
native_hint
ensure_imported
# Script errors don't stop Godot, so treat any as a failure.
log="$(mktemp)"
trap 'rm -f "$log"' EXIT
status=0
"$GODOT_BIN" --headless --path "$ROOT" --script res://tests/run_tests.gd 2>&1 | tee "$log" || status=$?
if grep -q "SCRIPT ERROR" "$log"; then
	echo "Script errors during tests (see above)." >&2
	exit 1
fi
exit "$status"
