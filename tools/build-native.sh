#!/usr/bin/env bash
# Build the native extension (bin/libourcraft.*) from native/.
#   tools/build-native.sh            debug build (used by the editor and tools/run.sh)
#   tools/build-native.sh release    release build (for exports)
# Needs SCons (python3 -m pip install --user scons) and a C++ compiler. The
# game still runs without it, using the slower GDScript code paths.
set -euo pipefail
source "$(dirname "$0")/_godot.sh"

target="template_debug"
if [[ "${1:-}" == "release" ]]; then
	target="template_release"
fi

if command -v scons >/dev/null 2>&1; then
	SCONS=(scons)
elif python3 -c "import SCons" >/dev/null 2>&1; then
	SCONS=(python3 -m SCons)
else
	echo "SCons not found. Install it with: python3 -m pip install --user scons" >&2
	exit 1
fi

cd "$ROOT/native"
if [[ ! -f godot-cpp/SConstruct ]]; then
	git -C "$ROOT" submodule update --init native/godot-cpp
fi
# Build the bindings against the API of the Godot that will load them.
"$GODOT_BIN" --headless --dump-extension-api >/dev/null 2>&1
jobs="$(sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo 4)"
"${SCONS[@]}" -j"$jobs" target="$target" custom_api_file=extension_api.json
