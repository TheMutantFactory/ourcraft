#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/vector3i.hpp>

namespace ourcraft {

// Native versions of the hot voxel loops. Each method mirrors a GDScript
// function (VoxelGrid._fill_rows and Mesher.build_gdscript) and returns the
// same data, so the GDScript versions stay as a fallback and a reference.
// The methods keep no state; GDScript calls them on one shared instance
// (see core/native.gd), from the main thread and from mesh workers.
class VoxelKernels : public godot::RefCounted {
	GDCLASS(VoxelKernels, godot::RefCounted)

protected:
	static void _bind_methods();

public:
	// Sets cells in [lmin, lmax) of a 32^3 chunk to value. Returns
	// [PackedByteArray data, int solid_count_delta, bool changed].
	godot::Array fill_chunk(const godot::PackedByteArray &data, const godot::Vector3i &lmin,
			const godot::Vector3i &lmax, int64_t value);

	// Greedy-meshes one chunk from a snapshot [own, -x, +x, -y, +y, -z, +z]
	// (null for missing chunks). Returns {} when nothing is visible, else
	// {"arrays": Array(Mesh.ARRAY_MAX), "faces": PackedVector3Array}.
	godot::Dictionary mesh_chunk(const godot::Array &input, const godot::Vector3i &key,
			const godot::Array &palette, double cell_m);
};

} // namespace ourcraft
