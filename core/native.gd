class_name Native
extends RefCounted
## Access to the optional native extension (native/, built with
## tools/build-native.sh). Without it the GDScript implementations are used.

static var _kernels: Object = null
static var _checked := false
## Set to false to force the GDScript paths (used by tests to compare).
static var enabled := true


## Returns the VoxelKernels helper or null. Call once from the main thread
## before using it from workers.
static func kernels() -> Object:
	if not _checked:
		_checked = true
		if ClassDB.class_exists("VoxelKernels") and OS.get_environment("OURCRAFT_NO_NATIVE") == "":
			_kernels = ClassDB.instantiate("VoxelKernels")
	return _kernels if enabled else null


static func available() -> bool:
	return kernels() != null
