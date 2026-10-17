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

# Global script classes are registered by an import pass, so import when the
# cache is missing (fresh checkout) or older than any script.
ensure_imported() {
	local cache="$ROOT/.godot/global_script_class_cache.cfg"
	if [[ ! -f "$cache" ]] || [[ -n "$(find "$ROOT" -path "$ROOT/native" -prune -o \( -name '*.gd' -o -name '*.gdextension' \) -newer "$cache" -print -quit)" ]]; then
		echo "Importing project..." >&2
		# Godot 4.7 can crash while exiting the first import that registers the
		# native extension; the import itself completes, so retry once.
		"$GODOT_BIN" --headless --path "$ROOT" --import >/dev/null 2>&1 ||
			"$GODOT_BIN" --headless --path "$ROOT" --import >/dev/null 2>&1 || true
	fi
}

# Points at the native build when it's missing; the game still runs without it.
native_hint() {
	if ! ls "$ROOT"/bin/libourcraft.* >/dev/null 2>&1; then
		echo "Note: native extension not built; using slower GDScript paths. Run tools/build-native.sh" >&2
	fi
}
