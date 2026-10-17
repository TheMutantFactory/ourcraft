class_name RegionBaker
extends Node3D
## Merges placements that aren't being edited into one mesh per region of
## space ("baking"), so a street of unique objects costs a handful of draw
## calls instead of one per object chunk. Each region mesh has one surface
## per tree depth so deeper objects still win where faces are coplanar.
##
## Baked copies don't share memory with their object, and a region must be
## rebaked when anything in it changes; WorldView keeps the object being
## edited (and anything heavily instanced) out of the baker for that reason.

## Region edge length in metres.
const REGION := 8.0

## Returns the ShaderMaterial for a tree depth.
var material_for_depth: Callable
## Returns a definition's chunk bounds in local metres.
var bounds_of: Callable

## Vector3i region -> {members: Array[int], sig: String, node: MeshInstance3D}
var _regions: Dictionary = {}
## def_id -> {region key -> true}
var _by_def: Dictionary = {}
## region key -> true
var _dirty: Dictionary = {}
var _placements: Array = []


## Re-assigns baked placements to regions. include(i) says whether
## placement i is baked. Only regions whose contents changed are rebaked.
func set_placements(placements: Array, include: Callable) -> void:
	_placements = placements
	_by_def.clear()
	var members := {}
	var sigs := {}
	var centers := {}
	for i in placements.size():
		if not include.call(i):
			continue
		var pl: Dictionary = placements[i]
		if not centers.has(pl.def_id):
			centers[pl.def_id] = (bounds_of.call(pl.def_id) as AABB).get_center()
		var c: Vector3 = pl.xform * (centers[pl.def_id] as Vector3)
		var key := Vector3i((c / REGION).floor())
		members.get_or_add(key, []).append(i)
		sigs.get_or_add(key, PackedStringArray()).append("%s|%s|%s" % ["/".join(pl.path), pl.def_id, pl.xform])
		_by_def.get_or_add(pl.def_id, {})[key] = true
	for key in _regions.keys():
		if not members.has(key):
			var node: Node = _regions[key].node
			if node != null:
				node.free()
			_regions.erase(key)
			_dirty.erase(key)
	for key in members:
		var sig := "\n".join(sigs[key])
		var r: Dictionary = _regions.get_or_add(key, {"node": null, "sig": ""})
		r.members = members[key]
		if r.sig != sig:
			r.sig = sig
			_dirty[key] = true


## A definition's meshes changed; rebake the regions that contain it.
func def_changed(def_id: String) -> void:
	for key in _by_def.get(def_id, {}):
		_dirty[key] = true


func has_def(def_id: String) -> bool:
	return _by_def.has(def_id)


func pending() -> int:
	return _dirty.size()


func region_count() -> int:
	return _regions.size()


## Rebakes dirty regions, spending at most budget_usec (0 = all).
func process(meshes: Dictionary, budget_usec: int) -> void:
	var start := Time.get_ticks_usec()
	for key in _dirty.keys():
		_dirty.erase(key)
		_bake(key, meshes)
		if budget_usec > 0 and Time.get_ticks_usec() - start > budget_usec:
			return


func clear() -> void:
	for r in _regions.values():
		if r.node != null:
			r.node.free()
	_regions.clear()
	_by_def.clear()
	_dirty.clear()


func _bake(key: Vector3i, meshes: Dictionary) -> void:
	var r: Dictionary = _regions.get(key, {})
	if r.is_empty():
		return
	# depth -> [verts, normals, colors, indices]
	var parts := {}
	for i in r.members:
		var pl: Dictionary = _placements[i]
		var entries: Dictionary = meshes.get(pl.def_id, {})
		if entries.is_empty():
			continue
		var part: Array = parts.get(pl.depth, [])
		if part.is_empty():
			part = [PackedVector3Array(), PackedVector3Array(), PackedColorArray(), PackedInt32Array()]
			parts[pl.depth] = part
		var xform: Transform3D = pl.xform
		var rot := Transform3D(xform.basis, Vector3.ZERO)
		for chunk in entries.values():
			# Meshes of objects that only just became baked have no CPU copy.
			if not chunk.has("arrays"):
				chunk.arrays = (chunk.mesh as ArrayMesh).surface_get_arrays(0)
			var arrays: Array = chunk.arrays
			var base: int = part[0].size()
			# Transform3D * PackedVector3Array runs natively.
			part[0].append_array(xform * (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array))
			part[1].append_array(rot * (arrays[Mesh.ARRAY_NORMAL] as PackedVector3Array))
			part[2].append_array(arrays[Mesh.ARRAY_COLOR])
			var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			var out: PackedInt32Array = part[3]
			var start := out.size()
			out.resize(start + idx.size())
			for k in idx.size():
				out[start + k] = idx[k] + base
	var mesh := ArrayMesh.new()
	var depths := parts.keys()
	depths.sort()
	for depth in depths:
		var part: Array = parts[depth]
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = part[0]
		arrays[Mesh.ARRAY_NORMAL] = part[1]
		arrays[Mesh.ARRAY_COLOR] = part[2]
		arrays[Mesh.ARRAY_INDEX] = part[3]
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(mesh.get_surface_count() - 1, material_for_depth.call(depth))
	if r.node == null:
		r.node = MeshInstance3D.new()
		add_child(r.node)
	r.node.mesh = mesh if mesh.get_surface_count() > 0 else null
