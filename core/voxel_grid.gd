class_name VoxelGrid
extends RefCounted
## Sparse voxel storage made of fixed-size dense chunks.
##
## Coordinates are integer cells in the owning object's grid. A cell value of
## 0 is empty; any other value is a palette index. Only chunks that contain at
## least one solid cell are allocated.

const SIZE := 32
const SHIFT := 5
const MASK := SIZE - 1
const AREA := SIZE * SIZE
const VOLUME := SIZE * SIZE * SIZE

## Vector3i chunk key -> PackedByteArray of VOLUME cells.
var chunks: Dictionary = {}
## Vector3i chunk key -> number of solid cells.
var counts: Dictionary = {}
## Vector3i chunk key -> AABB of solid cells in grid coordinates (lazy).
var _bounds: Dictionary = {}


static func chunk_of(p: Vector3i) -> Vector3i:
	return Vector3i(p.x >> SHIFT, p.y >> SHIFT, p.z >> SHIFT)


static func index(lx: int, ly: int, lz: int) -> int:
	return lx + (ly << SHIFT) + (lz << (SHIFT * 2))


func is_empty() -> bool:
	return chunks.is_empty()


func get_cell(p: Vector3i) -> int:
	var data = chunks.get(chunk_of(p))
	if data == null:
		return 0
	return data[index(p.x & MASK, p.y & MASK, p.z & MASK)]


func set_cell(p: Vector3i, value: int) -> Dictionary:
	return fill_box(p, p + Vector3i.ONE, value)


## Fills cells in [cmin, cmax) with value. Returns the set of chunk keys whose
## mesh must be rebuilt (edited chunks plus neighbours whose shared face
## changed) as a Dictionary used as a set.
func fill_box(cmin: Vector3i, cmax: Vector3i, value: int) -> Dictionary:
	var affected := {}
	if cmax.x <= cmin.x or cmax.y <= cmin.y or cmax.z <= cmin.z:
		return affected
	var kmin := chunk_of(cmin)
	var kmax := chunk_of(cmax - Vector3i.ONE)
	for kz in range(kmin.z, kmax.z + 1):
		for ky in range(kmin.y, kmax.y + 1):
			for kx in range(kmin.x, kmax.x + 1):
				var key := Vector3i(kx, ky, kz)
				var origin := key * SIZE
				var lmin := (cmin - origin).clamp(Vector3i.ZERO, Vector3i.ONE * SIZE)
				var lmax := (cmax - origin).clamp(Vector3i.ZERO, Vector3i.ONE * SIZE)
				if _fill_chunk(key, lmin, lmax, value):
					affected[key] = true
					if lmin.x == 0: affected[key + Vector3i(-1, 0, 0)] = true
					if lmin.y == 0: affected[key + Vector3i(0, -1, 0)] = true
					if lmin.z == 0: affected[key + Vector3i(0, 0, -1)] = true
					if lmax.x == SIZE: affected[key + Vector3i(1, 0, 0)] = true
					if lmax.y == SIZE: affected[key + Vector3i(0, 1, 0)] = true
					if lmax.z == SIZE: affected[key + Vector3i(0, 0, 1)] = true
	return affected


func _fill_chunk(key: Vector3i, lmin: Vector3i, lmax: Vector3i, value: int) -> bool:
	var full := lmin == Vector3i.ZERO and lmax == Vector3i.ONE * SIZE
	if not chunks.has(key):
		if value == 0:
			return false
		var fresh := PackedByteArray()
		fresh.resize(VOLUME)
		chunks[key] = fresh
		counts[key] = 0
	if full:
		if value == 0:
			_erase_chunk(key)
		else:
			var data: PackedByteArray = chunks[key]
			data.fill(value)
			chunks[key] = data
			counts[key] = VOLUME
			_bounds.erase(key)
		return true
	var data: PackedByteArray = chunks[key]
	var count: int = counts[key]
	var changed := false
	for z in range(lmin.z, lmax.z):
		for y in range(lmin.y, lmax.y):
			var row := (y << SHIFT) + (z << (SHIFT * 2))
			for x in range(lmin.x, lmax.x):
				var i := row + x
				var old := data[i]
				if old == value:
					continue
				changed = true
				if old == 0:
					count += 1
				elif value == 0:
					count -= 1
				data[i] = value
	if not changed:
		if count == 0:
			_erase_chunk(key)
		return false
	if count == 0:
		_erase_chunk(key)
	else:
		chunks[key] = data
		counts[key] = count
		_bounds.erase(key)
	return true


func _erase_chunk(key: Vector3i) -> void:
	chunks.erase(key)
	counts.erase(key)
	_bounds.erase(key)


## Replaces a whole chunk (used by undo and loading). null or an all-empty
## array removes it.
func set_chunk(key: Vector3i, data) -> void:
	if data == null:
		_erase_chunk(key)
		return
	var count := 0
	for v in data:
		if v != 0:
			count += 1
	if count == 0:
		_erase_chunk(key)
		return
	chunks[key] = data
	counts[key] = count
	_bounds.erase(key)


func get_chunk_copy(key: Vector3i):
	var data = chunks.get(key)
	return null if data == null else data.duplicate()


## Tight bounds of solid cells in grid coordinates. Empty grid -> size zero.
func bounds() -> AABB:
	var result := AABB()
	var first := true
	for key in chunks:
		var b := _chunk_bounds(key)
		if first:
			result = b
			first = false
		else:
			result = result.merge(b)
	return result


func _chunk_bounds(key: Vector3i) -> AABB:
	if _bounds.has(key):
		return _bounds[key]
	var data: PackedByteArray = chunks[key]
	var lo := Vector3i.ONE * SIZE
	var hi := Vector3i.ZERO
	var i := 0
	for z in SIZE:
		for y in SIZE:
			for x in SIZE:
				if data[i] != 0:
					lo = lo.min(Vector3i(x, y, z))
					hi = hi.max(Vector3i(x + 1, y + 1, z + 1))
				i += 1
	var origin := key * SIZE
	var b := AABB(Vector3(origin + lo), Vector3(hi - lo))
	_bounds[key] = b
	return b


func copy() -> VoxelGrid:
	var g := VoxelGrid.new()
	for key in chunks:
		g.chunks[key] = chunks[key].duplicate()
		g.counts[key] = counts[key]
	return g


func solid_count() -> int:
	var total := 0
	for key in counts:
		total += counts[key]
	return total
