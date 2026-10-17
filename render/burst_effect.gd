class_name BurstEffect
extends MultiMeshInstance3D
## Coloured cubes flying out from a burst object: they spin, fall, bounce on
## the ground and shrink away, then the effect frees itself. Simulated on the
## CPU into one MultiMesh (one draw call per burst).
##
## BurstEffect.collect() turns an object (and everything in it) into
## particles; big objects are grouped into larger cubes to stay within a
## particle budget.

const LIFETIME := 2.4
const GRAVITY := 9.8
const BOUNCE := 0.35
const FRICTION := 0.7

var _pos := PackedVector3Array()
var _vel := PackedVector3Array()
var _axis := PackedVector3Array()
var _spin := PackedFloat32Array()
var _size := PackedFloat32Array()
var _colors := PackedColorArray()
var _age := 0.0
var _buffer := PackedFloat32Array()


## Collects particles for the object at `path` and everything inside it:
## {points, colors, sizes, center, cells, chunk}. Cells are grouped into
## chunk³ blocks, each becoming one cube in its most common colour: chunk
## grows (2, 4, 8…) until there are at most `budget` cubes, and is at least
## big enough for cubes of `min_size` metres, since 1 cm cubes are specks
## from a few metres away.
static func collect(project: Project, view: WorldView, path: PackedStringArray, budget := 1500, min_size := 0.04) -> Dictionary:
	var placements := []
	var total := 0
	for pl in view._placements:
		if CollisionField._has_prefix(pl.path, path) and project.defs.has(pl.def_id):
			placements.append(pl)
			total += project.defs[pl.def_id].grid.solid_count()
	var chunk := 1
	while total / float(chunk * chunk * chunk) > budget:
		chunk *= 2
	var smallest := INF
	for pl in placements:
		smallest = minf(smallest, project.voxel_size * project.defs[pl.def_id].unit)
	if smallest < INF:
		chunk = maxi(chunk, ceili(min_size / smallest - 0.001))
	var points := PackedVector3Array()
	var colors := PackedColorArray()
	var sizes := PackedFloat32Array()
	var sum := Vector3.ZERO
	for pl in placements:
		var def: ObjectDef = project.defs[pl.def_id]
		var cell_m := project.voxel_size * def.unit
		# cluster key -> {value -> count}, and cluster key -> cell count
		var clusters := {}
		for key: Vector3i in def.grid.keys():
			var data = def.grid.get_chunk(key)
			if data == null:
				continue
			var b := def.grid._chunk_bounds(key)
			var lo := Vector3i(b.position) - key * VoxelGrid.SIZE
			var hi := Vector3i(b.end) - key * VoxelGrid.SIZE
			for z in range(lo.z, hi.z):
				for y in range(lo.y, hi.y):
					for x in range(lo.x, hi.x):
						var v: int = data[VoxelGrid.index(x, y, z)]
						if v == 0:
							continue
						var cell := key * VoxelGrid.SIZE + Vector3i(x, y, z)
						var ck := Vector3i(floori(cell.x / float(chunk)), floori(cell.y / float(chunk)), floori(cell.z / float(chunk)))
						var votes: Dictionary = clusters.get_or_add(ck, {})
						votes[v] = int(votes.get(v, 0)) + 1
		for ck in clusters:
			var votes: Dictionary = clusters[ck]
			var best := 0
			var best_n := -1
			for v in votes:
				if votes[v] > best_n:
					best = v
					best_n = votes[v]
			var local := (Vector3(ck) + Vector3.ONE * 0.5) * chunk * cell_m
			var world: Vector3 = pl.xform * local
			points.append(world)
			colors.append(project.palette[(best - 1) % project.palette.size()])
			sizes.append(chunk * cell_m * 0.92)
			sum += world
	var center := sum / maxf(1.0, points.size())
	return {"points": points, "colors": colors, "sizes": sizes, "center": center, "cells": total, "chunk": chunk}


## Starts the effect from collect()'s result.
func setup(parts: Dictionary, strength := 3.0) -> void:
	var n: int = parts.points.size()
	_pos = parts.points.duplicate()
	_colors = parts.colors
	_size = parts.sizes
	_vel.resize(n)
	_axis.resize(n)
	_spin.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var center: Vector3 = parts.center
	for i in n:
		var out := (_pos[i] - center)
		out = out.normalized() if out.length() > 0.001 else Vector3.UP
		var jitter := Vector3(rng.randf_range(-0.5, 0.5), rng.randf_range(0.2, 1.0), rng.randf_range(-0.5, 0.5))
		_vel[i] = (out + jitter).normalized() * strength * rng.randf_range(0.5, 1.4)
		_axis[i] = Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized()
		_spin[i] = rng.randf_range(-12.0, 12.0)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = BoxMesh.new()
	mm.instance_count = n
	multimesh = mm
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.roughness = 0.8
	material_override = mat
	_buffer.resize(n * 16)
	_write(0.0)


func _process(dt: float) -> void:
	_age += dt
	if _age >= LIFETIME:
		queue_free()
		return
	var g := GRAVITY * dt
	for i in _pos.size():
		var v := _vel[i]
		v.y -= g
		var p := _pos[i] + v * dt
		var half := _size[i] * 0.5
		if p.y < half and v.y < 0.0:
			p.y = half
			v = Vector3(v.x * FRICTION, -v.y * BOUNCE, v.z * FRICTION)
		_pos[i] = p
		_vel[i] = v
	_write(dt)


## Writes every cube's transform and colour into the MultiMesh buffer in one
## go (12 transform floats + 4 colour floats per cube).
func _write(_dt: float) -> void:
	var shrink := clampf((LIFETIME - _age) / (LIFETIME * 0.35), 0.0, 1.0)
	for i in _pos.size():
		var b := Basis(_axis[i], _spin[i] * _age).scaled(Vector3.ONE * _size[i] * shrink)
		var o := i * 16
		var p := _pos[i]
		_buffer[o] = b.x.x
		_buffer[o + 1] = b.y.x
		_buffer[o + 2] = b.z.x
		_buffer[o + 3] = p.x
		_buffer[o + 4] = b.x.y
		_buffer[o + 5] = b.y.y
		_buffer[o + 6] = b.z.y
		_buffer[o + 7] = p.y
		_buffer[o + 8] = b.x.z
		_buffer[o + 9] = b.y.z
		_buffer[o + 10] = b.z.z
		_buffer[o + 11] = p.z
		var c := _colors[i]
		_buffer[o + 12] = c.r
		_buffer[o + 13] = c.g
		_buffer[o + 14] = c.b
		_buffer[o + 15] = 1.0
	multimesh.buffer = _buffer
