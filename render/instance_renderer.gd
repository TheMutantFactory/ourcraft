class_name InstanceRenderer
extends Node3D
## Draws placements with GPU instancing. All copies of an object at the same
## tree depth form a group; each of the object's chunk meshes is drawn once
## per group with a MultiMesh holding every copy's transform. Node count
## scales with objects × chunks, not with the number of copies, and editing an
## object updates every copy because they share the mesh.
##
## Distance level-of-detail: groups with many copies are split into CELL-sized
## cells of space so they can be culled. Each cell draws its copies with one
## MultiMesh per detail level: the object's chunk meshes merged into one
## nearby, then coarse meshes (its voxels grouped 4³ and 16³ into one), then
## nothing once the object would be a couple of pixels tall. Godot's
## visibility ranges switch between the levels per cell.

## Groups with fewer copies than this use plain MeshInstance3Ds: a MultiMesh
## per copy costs more than a mesh instance (measured: 10,000 unique objects
## ran at 10 fps as one-copy MultiMeshes vs 45 fps as mesh instances).
const MULTIMESH_MIN := 4

## Groups with at least this many copies get cells and detail levels.
const LOD_MIN := 16
## Cell edge length in metres. Visibility ranges are measured to the cell,
## so each range is widened by about half a cell to keep every copy at least
## as detailed as it should be. Smaller cells cull better but mean more
## nodes: on Metal, ~14,000 MultiMesh nodes made whole frames come out
## black (no error), while a few hundred were fine.
const CELL := 256.0
## Coarse levels: voxels grouped f³ into one.
const LOD_FACTORS := [4, 16]
## Switch to a coarser level once a voxel would be this many pixels tall...
const VOXEL_PIXELS := 1.5
## ...and stop drawing once the whole object would be this many.
const OBJECT_PIXELS := 2.0
## Pixels per radian at the centre of the screen (75° vertical field of
## view, 1,710 px tall: 855 / tan(37.5°)).
const PIXELS_PER_RADIAN := 1114.0
## Seconds an object must stay unchanged before its merged and coarse
## meshes are rebuilt (they're rebuilt from the whole object).
const LOD_REBUILD_DELAY := 0.5

## Returns the ShaderMaterial for a tree depth (see voxel.gdshader).
var material_for_depth: Callable
## (def_id, f) -> Mesh or null: the object's voxels grouped f³ into one.
var coarse_mesh: Callable
## def_id -> [voxel size, longest extent] in metres.
var size_of: Callable

## "def_id|depth" -> {def_id, depth, members: Array[int], ranges: Array of
## [begin, end] per level (empty for groups without levels), cells:
## {Vector3i -> cell}}. A cell is {origin: Vector3, members: Array[int],
## buffer: PackedFloat32Array, nodes: {chunk key -> Array of nodes},
## levels: Array of nodes}. Groups with levels draw through `levels` (one
## MultiMeshInstance3D per level); the others through `nodes` (per chunk,
## one MultiMeshInstance3D or one MeshInstance3D per member) and have a
## single cell at the origin.
var _groups: Dictionary = {}
## def_id -> Array of group keys
var _groups_by_def: Dictionary = {}
## placement index -> [group key, cell key, slot]
var _slots: Dictionary = {}
var _placements: Array = []
## def_id -> {chunk key -> Mesh}, the live chunk meshes.
var _chunk_meshes: Dictionary = {}
## def_id -> {f -> Mesh or null}; f = 1 is the merged full-detail mesh.
var _level_meshes: Dictionary = {}
## def_id -> seconds since it last changed
var _stale: Dictionary = {}


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
			g = {"def_id": pl.def_id, "depth": pl.depth, "members": [], "cells": {}, "ranges": []}
			_groups[gk] = g
			_groups_by_def.get_or_add(pl.def_id, []).append(gk)
		g.members.append(i)
	for def_id in _groups_by_def:
		var known := {}
		var entries: Dictionary = meshes.get(def_id, {})
		for key in entries:
			if entries[key].mesh != null:
				known[key] = entries[key].mesh
		_chunk_meshes[def_id] = known
	for gk in _groups:
		var g: Dictionary = _groups[gk]
		if g.members.size() >= LOD_MIN:
			g.ranges = _ranges(g.def_id)
		var split: bool = not g.ranges.is_empty()
		for i in g.members:
			var ck := Vector3i.ZERO
			if split:
				var o: Vector3 = placements[i].xform.origin
				ck = Vector3i((o / CELL).floor())
			var c: Dictionary = g.cells.get(ck, {})
			if c.is_empty():
				var origin := (Vector3(ck) + Vector3.ONE * 0.5) * CELL if split else Vector3.ZERO
				c = {"origin": origin, "members": [], "nodes": {}, "levels": []}
				g.cells[ck] = c
			_slots[i] = [gk, ck, c.members.size()]
			c.members.append(i)
		for c in g.cells.values():
			var buf := PackedFloat32Array()
			buf.resize(c.members.size() * 12)
			for slot in c.members.size():
				_write(buf, slot, _local(c, placements[c.members[slot]].xform))
			c.buffer = buf
		if split:
			_add_levels(g)
		else:
			var known: Dictionary = _chunk_meshes[g.def_id]
			for c in g.cells.values():
				for key in known:
					_add_node(g, c, key, known[key])


func clear() -> void:
	for g in _groups.values():
		for c in g.cells.values():
			for list in c.nodes.values():
				for n in list:
					n.free()
			for n in c.levels:
				n.free()
	_groups.clear()
	_groups_by_def.clear()
	_slots.clear()
	_chunk_meshes.clear()


## A definition gained a chunk mesh.
func chunk_added(def_id: String, key: Vector3i, mesh: Mesh) -> void:
	if _chunk_meshes.has(def_id):
		_chunk_meshes[def_id][key] = mesh
	for gk in _groups_by_def.get(def_id, []):
		var g: Dictionary = _groups[gk]
		if g.ranges.is_empty():
			_add_node(g, g.cells.values()[0], key, mesh)
	voxels_changed(def_id)


## A definition lost a chunk mesh.
func chunk_removed(def_id: String, key: Vector3i) -> void:
	if _chunk_meshes.has(def_id):
		_chunk_meshes[def_id].erase(key)
	for gk in _groups_by_def.get(def_id, []):
		for c in _groups[gk].cells.values():
			for n in c.nodes.get(key, []):
				n.free()
			c.nodes.erase(key)
	voxels_changed(def_id)


## A definition's voxels changed: its merged and coarse meshes are rebuilt
## once it has been left alone for LOD_REBUILD_DELAY.
func voxels_changed(def_id: String) -> void:
	if _level_meshes.has(def_id):
		_stale[def_id] = 0.0


func _process(delta: float) -> void:
	for def_id in _stale.keys():
		_stale[def_id] += delta
		if _stale[def_id] < LOD_REBUILD_DELAY:
			continue
		_stale.erase(def_id)
		_level_meshes.erase(def_id)
		for gk in _groups_by_def.get(def_id, []):
			var g: Dictionary = _groups[gk]
			if g.ranges.is_empty():
				continue
			g.ranges = _ranges(def_id)
			for c in g.cells.values():
				for n in c.levels:
					n.free()
				c.levels = []
			_add_levels(g)


## Pushes new transforms for some placements (e.g. while dragging).
func update(indices: Array) -> void:
	for i in indices:
		var s = _slots.get(i)
		if s == null:
			continue
		var c: Dictionary = _groups[s[0]].cells[s[1]]
		var t := _local(c, _placements[i].xform)
		_write(c.buffer, s[2], t)
		for list in c.nodes.values():
			if list.size() == 1 and list[0] is MultiMeshInstance3D:
				list[0].multimesh.set_instance_transform(s[2], t)
			else:
				list[s[2]].transform = _placements[i].xform
		for n in c.levels:
			n.multimesh.set_instance_transform(s[2], t)


## Placement indices currently drawn, for consistency checks.
func drawn_placements() -> Array:
	var out := []
	for g in _groups.values():
		out.append_array(g.members)
	return out


func node_count() -> int:
	var n := 0
	for g in _groups.values():
		for c in g.cells.values():
			for list in c.nodes.values():
				n += list.size()
			n += c.levels.size()
	return n


## Cells across all groups (1 per group without levels).
func cell_count() -> int:
	var n := 0
	for g in _groups.values():
		n += g.cells.size()
	return n


func _add_node(g: Dictionary, c: Dictionary, key: Vector3i, mesh: Mesh) -> void:
	if c.nodes.has(key) or c.members.is_empty():
		return
	if g.members.size() < MULTIMESH_MIN:
		var mat: Material = material_for_depth.call(g.depth)
		var list := []
		for i in c.members:
			var mi := MeshInstance3D.new()
			mi.mesh = mesh
			mi.material_override = mat
			mi.transform = _placements[i].xform
			add_child(mi)
			list.append(mi)
		c.nodes[key] = list
		return
	c.nodes[key] = [_multimesh(g, c, mesh)]


## A MultiMeshInstance3D drawing mesh for every copy in a cell.
func _multimesh(g: Dictionary, c: Dictionary, mesh: Mesh) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = c.members.size()
	mm.buffer = c.buffer
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	# Deeper objects win where faces are coplanar (see voxel.gdshader).
	mmi.material_override = material_for_depth.call(g.depth)
	mmi.position = c.origin
	add_child(mmi)
	return mmi


## One node per detail level in every cell of a group with levels.
func _add_levels(g: Dictionary) -> void:
	for level in g.ranges.size():
		var mesh := _level_mesh(g.def_id, 1 if level == 0 else LOD_FACTORS[level - 1])
		if mesh == null:
			continue
		for c in g.cells.values():
			var mmi := _multimesh(g, c, mesh)
			mmi.visibility_range_begin = g.ranges[level][0]
			mmi.visibility_range_end = g.ranges[level][1]
			c.levels.append(mmi)


## The merged full-detail mesh (f = 1) or a coarse mesh of an object.
func _level_mesh(def_id: String, f: int) -> Mesh:
	var cache: Dictionary = _level_meshes.get_or_add(def_id, {})
	if not cache.has(f):
		if f == 1:
			var arrays := []
			for mesh: Mesh in _chunk_meshes.get(def_id, {}).values():
				arrays.append(mesh.surface_get_arrays(0))
			cache[f] = merge(arrays)
		else:
			cache[f] = coarse_mesh.call(def_id, f) if coarse_mesh.is_valid() else null
	return cache[f]


## [begin, end] distances for full detail and each coarse level: a level is
## used until its voxels would be VOXEL_PIXELS tall; the last one until the
## object would be OBJECT_PIXELS. Empty if sizes aren't known.
func _ranges(def_id: String) -> Array:
	if not size_of.is_valid():
		return []
	var size: Array = size_of.call(def_id)
	var voxel: float = size[0]
	var extent: float = size[1]
	if voxel <= 0.0 or extent <= 0.0:
		return []
	var margin := CELL * 0.75
	var out := []
	var begin := 0.0
	var factors := [1]
	for f in LOD_FACTORS:
		if voxel * f < extent:
			factors.append(f)
	for k in factors.size():
		var end: float = voxel * factors[k] * PIXELS_PER_RADIAN / VOXEL_PIXELS
		if k == factors.size() - 1:
			end = maxf(end, extent * PIXELS_PER_RADIAN / OBJECT_PIXELS)
		end += margin
		out.append([begin, end])
		begin = end
	return out


## One single-surface mesh from several Mesher outputs (Mesh.ARRAY_MAX
## arrays with vertices, normals, colours and indices). Null if empty.
static func merge(list: Array) -> ArrayMesh:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	for arrays: Array in list:
		var base := verts.size()
		verts.append_array(arrays[Mesh.ARRAY_VERTEX])
		normals.append_array(arrays[Mesh.ARRAY_NORMAL])
		colors.append_array(arrays[Mesh.ARRAY_COLOR])
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		if base > 0:
			for k in idx.size():
				idx[k] += base
		indices.append_array(idx)
	if indices.is_empty():
		return null
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	out[Mesh.ARRAY_VERTEX] = verts
	out[Mesh.ARRAY_NORMAL] = normals
	out[Mesh.ARRAY_COLOR] = colors
	out[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out)
	return mesh


## A placement's transform relative to its cell's node.
static func _local(c: Dictionary, t: Transform3D) -> Transform3D:
	return Transform3D(t.basis, t.origin - c.origin)


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
