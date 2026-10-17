class_name VoxelGrid
extends RefCounted
## Sparse voxel storage made of fixed-size chunks.
##
## Coordinates are integer cells in the owning object's grid. A cell value of
## 0 is empty; any other value is a palette index. Only chunks that contain at
## least one solid cell are allocated.
##
## Chunks are kept zstd-compressed in memory (a mostly empty 32 KB chunk packs
## to ~130 bytes). Reads decompress a temporary copy and writes recompress,
## about 25 µs per chunk. Packed bytes are never modified in place, so copies
## of a grid, undo snapshots and save files can share them.

const SIZE := 32
const SHIFT := 5
const MASK := SIZE - 1
const AREA := SIZE * SIZE
const VOLUME := SIZE * SIZE * SIZE

const CODEC := FileAccess.COMPRESSION_ZSTD

## Vector3i chunk key -> zstd-compressed PackedByteArray of VOLUME cells.
var _packed: Dictionary = {}
## Vector3i chunk key -> number of solid cells.
var counts: Dictionary = {}
## Vector3i chunk key -> AABB of solid cells in grid coordinates (lazy).
var _bounds: Dictionary = {}


static func chunk_of(p: Vector3i) -> Vector3i:
	return Vector3i(p.x >> SHIFT, p.y >> SHIFT, p.z >> SHIFT)


static func index(lx: int, ly: int, lz: int) -> int:
	return lx + (ly << SHIFT) + (lz << (SHIFT * 2))


func is_empty() -> bool:
	return _packed.is_empty()


func keys() -> Array:
	return _packed.keys()


func has_chunk(key: Vector3i) -> bool:
	return _packed.has(key)


func chunk_count() -> int:
	return _packed.size()


func get_cell(p: Vector3i) -> int:
	var data = get_chunk(chunk_of(p))
	if data == null:
		return 0
	return data[index(p.x & MASK, p.y & MASK, p.z & MASK)]


## The chunk's cells as a fresh PackedByteArray (safe to modify), or null.
func get_chunk(key: Vector3i):
	var packed = _packed.get(key)
	if packed == null:
		return null
	var data := (packed as PackedByteArray).decompress(VOLUME, CODEC)
	if data.size() != VOLUME:
		# Loaded without checking (see set_packed_trusted) and it's corrupt.
		push_error("Corrupt chunk %s; treating it as empty" % key)
		_erase_chunk(key)
		return null
	return data


## The chunk's compressed bytes (shared; don't modify), or null.
func get_packed(key: Vector3i):
	return _packed.get(key)


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
	var data = get_chunk(key)
	if data == null:
		if value == 0:
			return false
		data = PackedByteArray()
		data.resize(VOLUME)
	if full:
		if value == 0:
			_erase_chunk(key)
		else:
			data.fill(value)
			_store(key, data, VOLUME)
		return true
	var count: int = counts.get(key, 0)
	var changed := false
	var native := Native.kernels()
	if native != null:
		var r: Array = native.fill_chunk(data, lmin, lmax, value)
		data = r[0]
		count += int(r[1])
		changed = r[2]
	else:
		changed = _fill_rows(data, lmin, lmax, value)
		count = data.size() - data.count(0)
	if not changed:
		return false
	if count == 0:
		_erase_chunk(key)
	else:
		_store(key, data, count)
	return true


func _store(key: Vector3i, data: PackedByteArray, count: int) -> void:
	_packed[key] = data.compress(CODEC)
	counts[key] = count
	_bounds.erase(key)


## GDScript fallback for VoxelKernels.fill_chunk. Edits data in place.
static func _fill_rows(data: PackedByteArray, lmin: Vector3i, lmax: Vector3i, value: int) -> bool:
	var changed := false
	for z in range(lmin.z, lmax.z):
		for y in range(lmin.y, lmax.y):
			var row := (y << SHIFT) + (z << (SHIFT * 2))
			for x in range(lmin.x, lmax.x):
				var i := row + x
				if data[i] != value:
					data[i] = value
					changed = true
	return changed


func _erase_chunk(key: Vector3i) -> void:
	_packed.erase(key)
	counts.erase(key)
	_bounds.erase(key)


## Replaces a whole chunk with raw cells. null or all-empty removes it.
func set_chunk(key: Vector3i, data) -> void:
	if data == null:
		_erase_chunk(key)
		return
	var count: int = data.size() - data.count(0)
	if count == 0:
		_erase_chunk(key)
		return
	_store(key, data, count)


## Stores compressed bytes and their solid count without decompressing them
## (fast loading). Corrupt data is caught the first time the chunk is read.
func set_packed_trusted(key: Vector3i, packed: PackedByteArray, count: int) -> void:
	if count <= 0:
		_erase_chunk(key)
		return
	_packed[key] = packed
	counts[key] = count
	_bounds.erase(key)


## Replaces a whole chunk with compressed bytes (from get_packed, undo or a
## save file). Returns false if they don't decode to a chunk.
func set_packed(key: Vector3i, packed) -> bool:
	if packed == null:
		_erase_chunk(key)
		return true
	var data: PackedByteArray = (packed as PackedByteArray).decompress(VOLUME, CODEC)
	if data.size() != VOLUME:
		return false
	var count: int = VOLUME - data.count(0)
	if count == 0:
		_erase_chunk(key)
		return true
	_packed[key] = packed
	counts[key] = count
	_bounds.erase(key)
	return true


## Tight bounds of solid cells in grid coordinates. Empty grid -> size zero.
func bounds() -> AABB:
	var result := AABB()
	var first := true
	for key in _packed:
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
	var data: PackedByteArray = get_chunk(key)
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
	# Packed bytes are immutable, so the copy can share them.
	g._packed = _packed.duplicate()
	g.counts = counts.duplicate()
	return g


func solid_count() -> int:
	var total := 0
	for key in counts:
		total += counts[key]
	return total
