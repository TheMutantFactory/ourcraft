class_name RegionBaker
extends Node3D
## Merges placements that aren't being edited into one mesh per region of
## space ("baking"), so a street of unique objects costs a handful of draw
## calls instead of one per object chunk. Each region is a single surface;
## every vertex carries its tree depth in UV.x so deeper objects still win
## where faces are coplanar.
##
## Baked copies don't share memory with their object, and a region must be
## rebaked when anything in it changes; WorldView keeps the object being
## edited (and anything heavily instanced) out of the baker for that reason.

## Region edge length in metres.
const REGION := 8.0

## The material for baked meshes (reads the depth from UV.x).
var material: Material
## Returns a definition's chunk bounds in local metres.
var bounds_of: Callable
## Returns mesh arrays for (def_id, chunk key), or null if nothing visible.
var arrays_for: Callable

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


## Placement indices currently baked, for consistency checks.
func baked_placements() -> Array:
	var out := []
	for r in _regions.values():
		out.append_array(r.members)
	return out


func pending() -> int:
	return _dirty.size()


func region_count() -> int:
	return _regions.size()


func quad_count() -> int:
	var n := 0
	for r in _regions.values():
		if r.node != null and r.node.mesh != null:
			for si in r.node.mesh.get_surface_count():
				n += r.node.mesh.surface_get_array_index_len(si) / 6
	return n


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
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	# Objects appear several times in a region; mesh each chunk once.
	var cache := {}
	for i in r.members:
		var pl: Dictionary = _placements[i]
		var entries: Dictionary = meshes.get(pl.def_id, {})
		if entries.is_empty():
			continue
		var xform: Transform3D = pl.xform
		var rot := Transform3D(xform.basis, Vector3.ZERO)
		var depth_uv := Vector2(pl.depth, 0)
		for chunk_key in entries:
			var ck := "%s|%s" % [pl.def_id, chunk_key]
			if not cache.has(ck):
				cache[ck] = arrays_for.call(pl.def_id, chunk_key)
			if cache[ck] == null:
				continue
			var arrays: Array = cache[ck]
			var base := verts.size()
			var src: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			# Transform3D * PackedVector3Array runs natively.
			verts.append_array(xform * src)
			normals.append_array(rot * (arrays[Mesh.ARRAY_NORMAL] as PackedVector3Array))
			colors.append_array(arrays[Mesh.ARRAY_COLOR])
			var depth_fill := PackedVector2Array()
			depth_fill.resize(src.size())
			depth_fill.fill(depth_uv)
			uvs.append_array(depth_fill)
			var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			var start := indices.size()
			indices.resize(start + idx.size())
			for k in idx.size():
				indices[start + k] = idx[k] + base
	var mesh := ArrayMesh.new()
	if not indices.is_empty():
		var out := []
		out.resize(Mesh.ARRAY_MAX)
		out[Mesh.ARRAY_VERTEX] = verts
		out[Mesh.ARRAY_NORMAL] = normals
		out[Mesh.ARRAY_COLOR] = colors
		out[Mesh.ARRAY_TEX_UV] = uvs
		out[Mesh.ARRAY_INDEX] = indices
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out)
		mesh.surface_set_material(0, material)
	if r.node == null:
		r.node = MeshInstance3D.new()
		add_child(r.node)
	r.node.mesh = mesh if mesh.get_surface_count() > 0 else null
