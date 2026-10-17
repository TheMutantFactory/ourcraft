#!/usr/bin/env bash
# Random object-tree manipulation with invariant checks (tests/tree_fuzz.gd).
#   tools/fuzz.sh [--seeds=N] [--steps=M] [--seed=S] [--no-view] [--verbose]
set -euo pipefail
source "$(dirname "$0")/_godot.sh"
ensure_imported
# Script errors don't stop Godot, so treat any as a failure.
log="$(mktemp)"
trap 'rm -f "$log"' EXIT
status=0
"$GODOT_BIN" --headless --path "$ROOT" --script res://tests/fuzz.gd -- "$@" 2>&1 | tee "$log" || status=$?
if grep -q "SCRIPT ERROR" "$log"; then
	echo "Script errors during fuzzing (see above)." >&2
	exit 1
fi
exit "$status"
