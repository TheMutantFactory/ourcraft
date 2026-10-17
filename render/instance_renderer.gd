class_name InstanceRenderer
extends Node3D
## Draws placements with GPU instancing. All copies of an object at the same
## tree depth form a group; each of the object's chunk meshes is drawn once
## per group with a MultiMesh holding every copy's transform. Node count
## scales with objects × chunks, not with the number of copies, and editing an
## object updates every copy because they share the mesh.

## Groups with fewer copies than this use plain MeshInstance3Ds: a MultiMesh
## per copy costs more than a mesh instance (measured: 10,000 unique objects
## ran at 10 fps as one-copy MultiMeshes vs 45 fps as mesh instances).
const MULTIMESH_MIN := 4

## Returns the ShaderMaterial for a tree depth (see voxel.gdshader).
var material_for_depth: Callable

## "def_id|depth" -> {def_id, depth, members: Array[int], buffer:
## PackedFloat32Array, nodes: {Vector3i -> Array of nodes}}. A chunk's node
## list holds one MultiMeshInstance3D, or one MeshInstance3D per member for
## small groups.
var _groups: Dictionary = {}
## def_id -> Array of group keys
var _groups_by_def: Dictionary = {}
## placement index -> [group key, slot]
var _slots: Dictionary = {}
var _placements: Array = []


## Rebuilds all groups from scratch. visible(i) says whether placement i is
## drawn; meshes is WorldView._meshes.
func set_placements(placements: Array, visible: Callable, meshes: Dictionary) -> void:
	clear()
	_placements = placements
	for i in placements.size():
		if not visible.call(i):
			continue
		var pl: Dictionary = placements[i]
		var gk := "%s|%d" % [pl.def_id, pl.depth]
		var g: Dictionary = _groups.get(gk, {})
		if g.is_empty():
			g = {"def_id": pl.def_id, "depth": pl.depth, "members": [], "nodes": {}}
			_groups[gk] = g
			_groups_by_def.get_or_add(pl.def_id, []).append(gk)
		_slots[i] = [gk, g.members.size()]
		g.members.append(i)
	for gk in _groups:
		var g: Dictionary = _groups[gk]
		var buf := PackedFloat32Array()
		buf.resize(g.members.size() * 12)
		for slot in g.members.size():
			_write(buf, slot, placements[g.members[slot]].xform)
		g.buffer = buf
		var entries: Dictionary = meshes.get(g.def_id, {})
		for key in entries:
			_add_node(g, key, entries[key].mesh)


func clear() -> void:
	for g in _groups.values():
		for list in g.nodes.values():
			for n in list:
				n.free()
	_groups.clear()
	_groups_by_def.clear()
	_slots.clear()


## A definition gained a chunk mesh.
func chunk_added(def_id: String, key: Vector3i, mesh: Mesh) -> void:
	for gk in _groups_by_def.get(def_id, []):
		_add_node(_groups[gk], key, mesh)


## A definition lost a chunk mesh.
func chunk_removed(def_id: String, key: Vector3i) -> void:
	for gk in _groups_by_def.get(def_id, []):
		var g: Dictionary = _groups[gk]
		for n in g.nodes.get(key, []):
			n.free()
		g.nodes.erase(key)


## Pushes new transforms for some placements (e.g. while dragging).
func update(indices: Array) -> void:
	for i in indices:
		var s = _slots.get(i)
		if s == null:
			continue
		var g: Dictionary = _groups[s[0]]
		var t: Transform3D = _placements[i].xform
		_write(g.buffer, s[1], t)
		for list in g.nodes.values():
			if list.size() == 1 and list[0] is MultiMeshInstance3D:
				list[0].multimesh.set_instance_transform(s[1], t)
			else:
				list[s[1]].transform = t


func node_count() -> int:
	var n := 0
	for g in _groups.values():
		for list in g.nodes.values():
			n += list.size()
	return n


func _add_node(g: Dictionary, key: Vector3i, mesh: Mesh) -> void:
	if g.nodes.has(key) or g.members.is_empty():
		return
	# Deeper objects win where faces are coplanar (see voxel.gdshader).
	var mat: Material = material_for_depth.call(g.depth)
	if g.members.size() < MULTIMESH_MIN:
		var list := []
		for i in g.members:
			var mi := MeshInstance3D.new()
			mi.mesh = mesh
			mi.material_override = mat
			mi.transform = _placements[i].xform
			add_child(mi)
			list.append(mi)
		g.nodes[key] = list
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = g.members.size()
	mm.buffer = g.buffer
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	add_child(mmi)
	g.nodes[key] = [mmi]


## MultiMesh 3D transforms are 12 floats: the basis rows, each followed by
## that row's origin component.
static func _write(buf: PackedFloat32Array, slot: int, t: Transform3D) -> void:
	var o := slot * 12
	var b := t.basis
	buf[o] = b.x.x
	buf[o + 1] = b.y.x
	buf[o + 2] = b.z.x
	buf[o + 3] = t.origin.x
	buf[o + 4] = b.x.y
	buf[o + 5] = b.y.y
	buf[o + 6] = b.z.y
	buf[o + 7] = t.origin.y
	buf[o + 8] = b.x.z
	buf[o + 9] = b.y.z
	buf[o + 10] = b.z.z
	buf[o + 11] = t.origin.z
