class_name Mesher
extends RefCounted
## Greedy mesher for one VoxelGrid chunk. Faces between a solid cell and an
## empty one are merged into maximal same-colour rectangles per slice.
##
## Meshing works on a snapshot of the chunk and its six neighbours (see
## gather), so build_from can run on a worker thread while the grid keeps
## changing on the main thread.
##
## The work is arranged so native PackedByteArray operations do most of it:
## slices along y and z are cut with slice(), identical neighbouring slices
## (no faces between them) are skipped with one comparison, and a chunk that
## is one solid colour only looks at its six outer faces.

const S := VoxelGrid.SIZE
const AREA := S * S
# Mild per-direction tint so faces stay readable even in flat light.
const SHADE := [0.88, 0.94, 1.0, 0.72, 0.82, 0.9] # +x -x +y -y +z -z
# Slice layout per axis d: the in-slice axes (u, v) with index u + v * S,
# chosen so y and z slices are contiguous rows. flip is true when u x v
# points along -d, which reverses the triangle winding.
const AXES := [[1, 2, false], [0, 2, true], [0, 1, false]]


## Snapshot of the chunk and its neighbours: [own, -x, +x, -y, +y, -z, +z],
## with null for missing chunks. The copies keep a worker's input stable
## while the main thread goes on editing.
static func gather(grid: VoxelGrid, key: Vector3i) -> Array:
	var out := [grid.get_chunk_copy(key)]
	for d in 3:
		for side in [-1, 1]:
			var nk := key
			nk[d] += side
			out.append(grid.get_chunk_copy(nk))
	return out


static func build(grid: VoxelGrid, key: Vector3i, palette: Array, cell_m: float) -> Dictionary:
	return build_from(gather(grid, key), key, palette, cell_m)


## Returns {} for a chunk with no visible faces, otherwise
## {"arrays": Array (Mesh.ARRAY_MAX), "faces": PackedVector3Array}.
static func build_from(input: Array, key: Vector3i, palette: Array, cell_m: float) -> Dictionary:
	var native := Native.kernels()
	if native != null:
		return native.mesh_chunk(input, key, palette, cell_m)
	return build_gdscript(input, key, palette, cell_m)


## The GDScript mesher, used when the native extension isn't built and as
## the reference the native one is tested against.
static func build_gdscript(input: Array, key: Vector3i, palette: Array, cell_m: float) -> Dictionary:
	var data = input[0]
	if data == null:
		return {}
	var uniform := _uniform_value(data)
	var full := PackedByteArray()
	if uniform != 0:
		full.resize(AREA)
		full.fill(uniform)
	var out := {
		"verts": PackedVector3Array(), "normals": PackedVector3Array(),
		"colors": PackedColorArray(), "indices": PackedInt32Array(),
		"faces": PackedVector3Array(),
	}
	var origin := Vector3(key * S)
	var pos_mask := PackedInt32Array()
	var neg_mask := PackedInt32Array()
	pos_mask.resize(AREA)
	neg_mask.resize(AREA)

	for d in 3:
		var neg = input[1 + d * 2]
		var pos = input[2 + d * 2]
		var below: PackedByteArray = _slice(neg, d, S - 1) if neg != null else _empty()
		var layers: Array = [0, S] if uniform != 0 else range(S + 1)
		for i in layers:
			var above: PackedByteArray
			if i == S:
				above = _slice(pos, d, 0) if pos != null else _empty()
			elif uniform != 0:
				above = full
			else:
				above = _slice(data, d, i)
			if uniform != 0 and i == S:
				below = full
			if below == above:
				below = above
				continue
			var any := false
			for j in AREA:
				var a: int = below[j]
				var b: int = above[j]
				if a != 0 and b == 0:
					pos_mask[j] = a
					neg_mask[j] = 0
					any = true
				elif b != 0 and a == 0:
					neg_mask[j] = b
					pos_mask[j] = 0
					any = true
				else:
					pos_mask[j] = 0
					neg_mask[j] = 0
			# Boundary planes only carry this chunk's own faces; the neighbour
			# chunk emits the faces of its cells.
			if any and i > 0:
				_greedy(pos_mask, d, i, 1, origin, palette, cell_m, out)
			if any and i < S:
				_greedy(neg_mask, d, i, -1, origin, palette, cell_m, out)
			below = above

	if out.indices.is_empty():
		return {}
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = out.verts
	arrays[Mesh.ARRAY_NORMAL] = out.normals
	arrays[Mesh.ARRAY_COLOR] = out.colors
	arrays[Mesh.ARRAY_INDEX] = out.indices
	return {"arrays": arrays, "faces": out.faces}


## The single value filling the whole chunk, or 0 if it is mixed.
static func _uniform_value(data: PackedByteArray) -> int:
	var v := data[0]
	if v != 0 and data.count(v) == VoxelGrid.VOLUME:
		return v
	return 0


static func _empty() -> PackedByteArray:
	var e := PackedByteArray()
	e.resize(AREA)
	return e


## Extracts layer i along axis d in the AXES layout.
static func _slice(data: PackedByteArray, d: int, i: int) -> PackedByteArray:
	if d == 2:
		return data.slice(i * AREA, (i + 1) * AREA)
	if d == 1:
		var rows := PackedByteArray()
		for z in S:
			var start := i * S + z * AREA
			rows.append_array(data.slice(start, start + S))
		return rows
	var out := PackedByteArray()
	out.resize(AREA)
	var j := 0
	for z in S:
		var idx := i + z * AREA
		for y in S:
			out[j] = data[idx]
			idx += S
			j += 1
	return out


static func _greedy(mask: PackedInt32Array, d: int, i: int, dir: int,
		origin: Vector3, palette: Array, cell_m: float, out: Dictionary) -> void:
	var u: int = AXES[d][0]
	var v: int = AXES[d][1]
	var winding := -dir if AXES[d][2] else dir
	var normal := Vector3.ZERO
	normal[d] = dir
	var shade: float = SHADE[d * 2 + (0 if dir > 0 else 1)]
	for vv in S:
		var uu := 0
		while uu < S:
			var c := mask[uu + vv * S]
			if c == 0:
				uu += 1
				continue
			var w := 1
			while uu + w < S and mask[uu + w + vv * S] == c:
				w += 1
			var h := 1
			var grow := true
			while grow and vv + h < S:
				var row := (vv + h) * S
				for k in w:
					if mask[uu + k + row] != c:
						grow = false
						break
				if grow:
					h += 1
			for hv in h:
				var row := (vv + hv) * S
				for k in w:
					mask[uu + k + row] = 0
			var p := origin
			p[d] += i
			p[u] += uu
			p[v] += vv
			var du := Vector3.ZERO
			du[u] = w
			var dv := Vector3.ZERO
			dv[v] = h
			var col: Color = palette[(c - 1) % palette.size()] * shade
			col.a = 1.0
			_quad(p * cell_m, du * cell_m, dv * cell_m, winding, normal, col, out)
			uu += w


static func _quad(p: Vector3, du: Vector3, dv: Vector3, winding: int, normal: Vector3, col: Color,
		out: Dictionary) -> void:
	var verts: PackedVector3Array = out.verts
	var base := verts.size()
	var a := p
	var b := p + du
	var c := p + du + dv
	var e := p + dv
	out.verts.append_array([a, b, c, e])
	for k in 4:
		out.normals.append(normal)
		out.colors.append(col)
	# Godot treats clockwise triangles as front-facing. When u x v points
	# along the normal, a->b->c is counter-clockwise seen from outside.
	if winding > 0:
		out.indices.append_array([base, base + 3, base + 2, base, base + 2, base + 1])
		out.faces.append_array([a, e, c, a, c, b])
	else:
		out.indices.append_array([base, base + 1, base + 2, base, base + 2, base + 3])
		out.faces.append_array([a, b, c, a, c, e])
