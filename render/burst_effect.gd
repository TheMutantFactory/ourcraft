class_name BurstEffect
extends Node3D
## An object breaking into irregular pieces of real voxels that fly out,
## spin, fall, bounce off the ground and nearby objects, and fade away; then
## the effect frees itself.
##
## BurstEffect.collect() slices the object (and everything in it) into
## pieces: random flood-fill regions grown from seed voxels (see slice), each
## greedy-meshed with Mesher in its own colours. setup() flies them as rigid
## bodies, simulated on the CPU and drawn as RenderingServer instances (no
## nodes). Pieces bounce off the voxels of objects near the burst, looked up
## directly in their grids, so it works where no physics bodies exist.

const LIFETIME := 2.6
## Fraction of the lifetime at the end over which pieces fade out.
const FADE := 0.35
const GRAVITY := 9.8
const BOUNCE := 0.35
const FRICTION := 0.7
## Most voxels a burst slices; bigger objects are grouped into chunk³
## blocks (most common colour) first.
const VOXEL_BUDGET := 40000
## Most cells in one object's slicing box (sparse objects with far-apart
## blocks are grouped further).
const BOX_BUDGET := 1 << 20
## Objects within this many metres of a burst are obstacles for its pieces.
const REACH := 8.0

static var _material: ShaderMaterial

var _meshes: Array = []
var _rids: Array[RID] = []
var _pos := PackedVector3Array()
var _vel := PackedVector3Array()
var _axis := PackedVector3Array()
var _spin := PackedFloat32Array()
var _angle := PackedFloat32Array()
var _radius := PackedFloat32Array()
var _com := PackedVector3Array()
var _basis: Array[Basis] = []
## [{aabb (world), inv (world -> grid cells), grid, cache: {key -> chunk or null}}]
var _obstacles: Array = []
var _age := 0.0


## How many pieces an object of `cells` voxels breaks into (before
## unconnected bits, which become pieces of their own).
static func piece_target(cells: int) -> int:
	return mini(cells, clampi(roundi(sqrt(cells) * 0.8), 5, 60))


## Slices the object at `path` and everything inside it into pieces:
## {pieces, center, cells, chunk, obstacles}. Each piece is {surfaces (mesh
## arrays), origin (Transform3D of its corner in the world), com (centre of
## mass, local metres), radius, cells}; with keep_voxels also {voxels: chunk
## key -> PackedByteArray, lo: its corner in slicing cells}. At most
## `budget` pieces are made.
static func collect(project: Project, view: WorldView, path: PackedStringArray, budget := 1500,
		keep_voxels := false) -> Dictionary:
	var placements := []
	var total := 0
	for pl in view._placements:
		if CollisionField._has_prefix(pl.path, path) and project.defs.has(pl.def_id):
			var n: int = project.defs[pl.def_id].grid.solid_count()
			if n > 0:
				placements.append([n, pl])
				total += n
	# Biggest first, so they still get pieces if the budget runs out.
	placements.sort_custom(func(a, b): return a[0] > b[0])
	var chunk := 1
	while total / float(chunk * chunk * chunk) > VOXEL_BUDGET:
		chunk *= 2
	var target := mini(budget, piece_target(ceili(total / float(chunk * chunk * chunk))))
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var pieces := []
	var biggest := chunk
	for k in placements.size():
		var left := budget - pieces.size()
		if left < 1:
			break
		var n: int = placements[k][0]
		var pl: Dictionary = placements[k][1]
		var def: ObjectDef = project.defs[pl.def_id]
		var box := voxel_box(def.grid, chunk)
		biggest = maxi(biggest, box.c)
		var seeds := maxi(1, roundi(target * n / float(total)))
		var cut := slice(box.cells, box.dims, seeds, maxi(1, left - (placements.size() - k - 1)), rng.randi())
		var cell_m := project.voxel_size * def.unit
		pieces.append_array(_mesh_pieces(box, cut, project.palette, cell_m, pl.xform, keep_voxels))
	var sum := Vector3.ZERO
	var weight := 0
	for p in pieces:
		sum += p.origin * p.com * p.cells
		weight += p.cells
	var center := sum / maxf(1.0, weight)
	return {"pieces": pieces, "center": center, "cells": total, "chunk": biggest,
		"obstacles": _find_obstacles(project, view, path, center)}


## The grid's solid cells as a dense box: {cells: PackedByteArray (x fastest),
## dims, origin (Vector3i, grid cells), c}, with c³ cells grouped into one
## in their most common colour (c starts at `chunk` and grows to keep
## within BOX_BUDGET).
static func voxel_box(grid: VoxelGrid, chunk := 1) -> Dictionary:
	var b := grid.bounds()
	var lo := Vector3i(b.position)
	var hi := Vector3i(b.end)
	var c := chunk
	var olo: Vector3i
	var dims: Vector3i
	while true:
		olo = Vector3i(floori(lo.x / float(c)), floori(lo.y / float(c)), floori(lo.z / float(c)))
		var ohi := Vector3i(ceili(hi.x / float(c)), ceili(hi.y / float(c)), ceili(hi.z / float(c)))
		dims = ohi - olo
		if dims.x * dims.y * dims.z <= BOX_BUDGET:
			break
		c *= 2
	var cells := PackedByteArray()
	cells.resize(dims.x * dims.y * dims.z)
	var native := Native.kernels()
	if native != null and native.has_method("gather_box") and c <= VoxelGrid.SIZE:
		# In batches, so a huge object isn't all decompressed at once.
		var keys := grid.keys()
		for start in range(0, keys.size(), 64):
			var datas := []
			var bases := []
			for key: Vector3i in keys.slice(start, start + 64):
				var data = grid.get_chunk(key)
				if data != null:
					datas.append(data)
					bases.append(key * VoxelGrid.SIZE)
			cells = native.gather_box(cells, dims, olo, c, datas, bases)
		return {"cells": cells, "dims": dims, "origin": olo * c, "c": c}
	var votes := {}
	for key: Vector3i in grid.keys():
		var data = grid.get_chunk(key)
		if data == null:
			continue
		var cb := grid._chunk_bounds(key)
		var base := key * VoxelGrid.SIZE
		var clo := Vector3i(cb.position) - base
		var chi := Vector3i(cb.end) - base
		for z in range(clo.z, chi.z):
			for y in range(clo.y, chi.y):
				var row := VoxelGrid.index(0, y, z)
				for x in range(clo.x, chi.x):
					var v: int = data[row + x]
					if v == 0:
						continue
					var cell := base + Vector3i(x, y, z)
					if c == 1:
						var q := cell - olo
						cells[q.x + dims.x * (q.y + dims.y * q.z)] = v
					else:
						var q := Vector3i(floori(cell.x / float(c)), floori(cell.y / float(c)), floori(cell.z / float(c))) - olo
						var tally: Dictionary = votes.get_or_add(q.x + dims.x * (q.y + dims.y * q.z), {})
						tally[v] = int(tally.get(v, 0)) + 1
	for i in votes:
		var tally: Dictionary = votes[i]
		var best := 0
		var best_n := -1
		for v in tally:
			if tally[v] > best_n:
				best = v
				best_n = tally[v]
		cells[i] = best
	return {"cells": cells, "dims": dims, "origin": olo * c, "c": c}


## Splits the solid cells of a dense box into connected pieces:
## {labels: PackedInt32Array (piece per cell, -1 for empty), count}.
## `seeds` random solid cells grow into their neighbours in random order
## (so borders are ragged) until they meet; bits no seed reaches become
## pieces of their own, up to max_pieces (later bits join the last piece).
static func slice(cells: PackedByteArray, dims: Vector3i, seeds: int, max_pieces: int, rng_seed: int) -> Dictionary:
	var native := Native.kernels()
	# has_method: an extension built before slice_pieces existed still loads.
	if native != null and native.has_method("slice_pieces"):
		var r: Array = native.slice_pieces(cells, dims, seeds, max_pieces, rng_seed)
		return {"labels": r[0], "count": r[1]}
	return slice_gdscript(cells, dims, seeds, max_pieces, rng_seed)


## The GDScript slicer, used without the native extension and as the
## reference the native one is tested against.
static func slice_gdscript(cells: PackedByteArray, dims: Vector3i, seeds: int, max_pieces: int,
		rng_seed: int) -> Dictionary:
	var n := cells.size()
	var labels := PackedInt32Array()
	labels.resize(n)
	labels.fill(-1)
	var solid := PackedInt32Array()
	for i in n:
		if cells[i] != 0:
			solid.append(i)
	if solid.is_empty():
		return {"labels": labels, "count": 0}
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	var count := 0
	var frontier := PackedInt32Array()
	for k in mini(seeds, max_pieces):
		var i := solid[rng.randi_range(0, solid.size() - 1)]
		if labels[i] < 0:
			labels[i] = count
			count += 1
			frontier.append(i)
	_grow(cells, dims, labels, frontier, rng)
	for i in solid:
		if labels[i] < 0:
			if count < max_pieces:
				count += 1
			labels[i] = count - 1
			frontier.append(i)
			_grow(cells, dims, labels, frontier, rng)
	return {"labels": labels, "count": count}


## Grows the labels of the frontier cells into unlabelled solid neighbours,
## picking the next cell to grow from at random.
static func _grow(cells: PackedByteArray, dims: Vector3i, labels: PackedInt32Array,
		frontier: PackedInt32Array, rng: RandomNumberGenerator) -> void:
	var sx := dims.x
	var sxy := dims.x * dims.y
	while not frontier.is_empty():
		var j := rng.randi_range(0, frontier.size() - 1)
		var i := frontier[j]
		frontier[j] = frontier[frontier.size() - 1]
		frontier.resize(frontier.size() - 1)
		var label := labels[i]
		var x := i % sx
		var y := (i / sx) % dims.y
		var z := i / sxy
		for nb in [i - 1 if x > 0 else -1, i + 1 if x < sx - 1 else -1,
				i - sx if y > 0 else -1, i + sx if y < dims.y - 1 else -1,
				i - sxy if z > 0 else -1, i + sxy if z < dims.z - 1 else -1]:
			if nb >= 0 and cells[nb] != 0 and labels[nb] < 0:
				labels[nb] = label
				frontier.append(nb)


## Meshes each piece of a sliced box on its own (cells relative to the
## piece's corner, so most pieces fit one mesher chunk).
static func _mesh_pieces(box: Dictionary, cut: Dictionary, palette: Array, cell_m: float,
		xform: Transform3D, keep_voxels: bool) -> Array:
	var count: int = cut.count
	var labels: PackedInt32Array = cut.labels
	var cells: PackedByteArray = box.cells
	var dims: Vector3i = box.dims
	var c: int = box.c
	var piece_m := cell_m * c
	var lists := []
	var lo := []
	var hi := []
	for k in count:
		lists.append(PackedInt32Array())
		lo.append(Vector3i.ONE * (1 << 30))
		hi.append(-Vector3i.ONE)
	var sx := dims.x
	var sxy := dims.x * dims.y
	for i in labels.size():
		var k := labels[i]
		if k < 0:
			continue
		var p := Vector3i(i % sx, (i / sx) % dims.y, i / sxy)
		lists[k].append(i)
		lo[k] = (lo[k] as Vector3i).min(p)
		hi[k] = (hi[k] as Vector3i).max(p)
	var out := []
	for k in count:
		var list: PackedInt32Array = lists[k]
		if list.is_empty():
			continue
		var corner: Vector3i = lo[k]
		var chunks := {}
		var sum := Vector3.ZERO
		for i in list:
			var q := Vector3i(i % sx, (i / sx) % dims.y, i / sxy) - corner
			var key := VoxelGrid.chunk_of(q)
			var data = chunks.get(key)
			if data == null:
				data = PackedByteArray()
				data.resize(VoxelGrid.VOLUME)
				chunks[key] = data
			data[VoxelGrid.index(q.x & VoxelGrid.MASK, q.y & VoxelGrid.MASK, q.z & VoxelGrid.MASK)] = cells[i]
			sum += Vector3(q)
		var surfaces := []
		for key: Vector3i in chunks:
			var input := [chunks[key]]
			for d in 3:
				for side in [-1, 1]:
					var nk := key
					nk[d] += side
					input.append(chunks.get(nk))
			var built := Mesher.build_from(input, key, palette, piece_m)
			if not built.is_empty():
				surfaces.append(built.arrays)
		var extent := Vector3((hi[k] as Vector3i) - corner + Vector3i.ONE) * piece_m
		var piece := {
			"surfaces": surfaces,
			"origin": xform * Transform3D(Basis(), Vector3(box.origin + corner * c) * cell_m),
			"com": (sum / list.size() + Vector3.ONE * 0.5) * piece_m,
			"radius": maxf(piece_m * 0.5, minf(extent.x, minf(extent.y, extent.z)) * 0.5),
			"cells": list.size(),
		}
		if keep_voxels:
			piece.voxels = chunks
			piece.lo = corner
		out.append(piece)
	return out


## Objects near the burst (other than the burst object and what's in it)
## that pieces bounce off.
static func _find_obstacles(project: Project, view: WorldView, path: PackedStringArray, center: Vector3) -> Array:
	var area := AABB(center - Vector3.ONE * REACH, Vector3.ONE * REACH * 2.0)
	var out := []
	for pl in view._placements:
		if CollisionField._has_prefix(pl.path, path):
			continue
		var def: ObjectDef = project.defs.get(pl.def_id)
		if def == null or def.grid.is_empty():
			continue
		var to_world: Transform3D = pl.xform * Transform3D(Basis().scaled(Vector3.ONE * pl.cell_m), Vector3.ZERO)
		if not (pl.xform * view._chunk_bounds(pl.def_id)).intersects(area):
			continue
		out.append({"aabb": to_world * def.grid.bounds(), "inv": to_world.affine_inverse(),
			"grid": def.grid, "cache": {}})
	return out


## Starts the effect from collect()'s result. Add the node to the tree
## first.
func setup(parts: Dictionary, strength := 3.5) -> void:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = load("res://render/voxel.gdshader")
	_obstacles = parts.obstacles
	var scenario := get_world_3d().scenario
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var center: Vector3 = parts.center
	for piece in parts.pieces:
		if piece.surfaces.is_empty():
			continue
		var mesh := ArrayMesh.new()
		for arrays in piece.surfaces:
			mesh.add_surface_from_arrays(Mesher.PRIMITIVE, arrays)
			mesh.surface_set_material(mesh.get_surface_count() - 1, _material)
		_meshes.append(mesh)
		_rids.append(RenderingServer.instance_create2(mesh.get_rid(), scenario))
		var origin: Transform3D = piece.origin
		var pos: Vector3 = origin * piece.com
		var out := pos - center
		out = out.normalized() if out.length() > 0.001 else Vector3.UP
		var jitter := Vector3(rng.randf_range(-0.5, 0.5), rng.randf_range(0.2, 1.0), rng.randf_range(-0.5, 0.5))
		_pos.append(pos)
		_vel.append((out + jitter).normalized() * strength * rng.randf_range(0.5, 1.4))
		_axis.append(Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized())
		_spin.append(rng.randf_range(-9.0, 9.0))
		_angle.append(0.0)
		_radius.append(piece.radius)
		_com.append(piece.com)
		_basis.append(origin.basis)
	_write()


func piece_count() -> int:
	return _rids.size()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		for rid in _rids:
			RenderingServer.free_rid(rid)
		_rids.clear()


func _process(dt: float) -> void:
	_age += dt
	if _age >= LIFETIME:
		queue_free()
		return
	dt = minf(dt, 0.05)
	for i in _pos.size():
		var v := _vel[i]
		v.y -= GRAVITY * dt
		var p := _pos[i]
		var r := _radius[i]
		# A piece that starts inside something (it was touching the burst
		# object's neighbours) passes through rather than getting stuck.
		var free := not _solid(p)
		for d in 3:
			var step := v[d] * dt
			if step == 0.0:
				continue
			var np := p
			np[d] += step
			var probe := np
			probe[d] += r if step > 0.0 else -r
			var ground := d == 1 and step < 0.0 and probe.y < 0.0
			if ground or (free and _solid(probe)):
				v[d] = -v[d] * BOUNCE
				for e in 3:
					if e != d:
						v[e] *= FRICTION
				_spin[i] *= 0.6
				if ground:
					np.y = r
				else:
					np = p
			p = np
		_pos[i] = p
		_vel[i] = v
		_angle[i] += _spin[i] * dt
	_write()


## Whether a world point is inside a solid voxel of an obstacle.
func _solid(q: Vector3) -> bool:
	for o in _obstacles:
		if not (o.aabb as AABB).has_point(q):
			continue
		var c := Vector3i((o.inv * q).floor())
		var key := VoxelGrid.chunk_of(c)
		var cache: Dictionary = o.cache
		if not cache.has(key):
			cache[key] = (o.grid as VoxelGrid).get_chunk(key)
		var data = cache[key]
		if data != null and data[VoxelGrid.index(c.x & VoxelGrid.MASK, c.y & VoxelGrid.MASK, c.z & VoxelGrid.MASK)] != 0:
			return true
	return false


func _write() -> void:
	var fade := clampf((_age - LIFETIME * (1.0 - FADE)) / (LIFETIME * FADE), 0.0, 1.0)
	for i in _rids.size():
		var t := Transform3D(Basis(_axis[i], _angle[i]) * _basis[i], _pos[i]) * Transform3D(Basis(), -_com[i])
		RenderingServer.instance_set_transform(_rids[i], t)
		RenderingServer.instance_geometry_set_transparency(_rids[i], fade)
