#!/usr/bin/env bash
# Shared setup for the tools/ scripts: locates the project root and a Godot 4
# binary. Override the binary with GODOT=/path/to/godot.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

find_godot() {
	if [[ -n "${GODOT:-}" ]]; then
		echo "$GODOT"
		return
	fi
	local candidate
	for candidate in godot godot4; do
		if command -v "$candidate" >/dev/null 2>&1; then
			command -v "$candidate"
			return
		fi
	done
	for candidate in \
		"/Applications/Godot.app/Contents/MacOS/Godot" \
		"$HOME/Applications/Godot.app/Contents/MacOS/Godot" \
		"$HOME/Downloads/Godot.app/Contents/MacOS/Godot"; do
		if [[ -x "$candidate" ]]; then
			echo "$candidate"
			return
		fi
	done
	echo "Godot 4 not found. Install it or set GODOT=/path/to/godot." >&2
	exit 1
}

GODOT_BIN="$(find_godot)"

# A fresh checkout has no .godot/ cache yet; global script classes are only
# registered after an import pass.
ensure_imported() {
	if [[ ! -f "$ROOT/.godot/global_script_class_cache.cfg" ]]; then
		echo "Importing project (first run)..." >&2
		"$GODOT_BIN" --headless --path "$ROOT" --import >/dev/null 2>&1 || true
	fi
}
