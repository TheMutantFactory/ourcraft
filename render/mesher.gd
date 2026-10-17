class_name Mesher
extends RefCounted
## Greedy mesher for one VoxelGrid chunk. Faces between a solid cell and an
## empty one are merged into maximal same-colour rectangles per slice.

const S := VoxelGrid.SIZE
# Mild per-direction tint so faces stay readable even in flat light.
const SHADE := [0.88, 0.94, 1.0, 0.72, 0.82, 0.9] # +x -x +y -y +z -z


## Returns {} for a chunk with no visible faces, otherwise
## {"arrays": Array (Mesh.ARRAY_MAX), "faces": PackedVector3Array}.
static func build(grid: VoxelGrid, key: Vector3i, palette: Array, cell_m: float) -> Dictionary:
	var data = grid.chunks.get(key)
	if data == null:
		return {}
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var faces := PackedVector3Array()
	var origin := Vector3(key * S)
	var pos_mask := PackedInt32Array()
	var neg_mask := PackedInt32Array()
	pos_mask.resize(S * S)
	neg_mask.resize(S * S)

	for d in 3:
		var u := (d + 1) % 3
		var v := (d + 2) % 3
		var below = _neighbour_slice(grid, key, d, -1)
		for i in S + 1:
			var above: PackedByteArray
			if i < S:
				above = _slice(data, d, i)
			else:
				var n = _neighbour_slice(grid, key, d, 1)
				above = n
			var any := false
			for j in S * S:
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
			if any:
				_greedy(pos_mask, d, u, v, i, 1, origin, palette, cell_m, verts, normals, colors, indices, faces)
				_greedy(neg_mask, d, u, v, i, -1, origin, palette, cell_m, verts, normals, colors, indices, faces)
			below = above

	if indices.is_empty():
		return {}
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	return {"arrays": arrays, "faces": faces}


## Extracts layer i along axis d as a S*S array indexed [u + v*S].
static func _slice(data: PackedByteArray, d: int, i: int) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(S * S)
	var strides := [1, S, S * S]
	var sd: int = strides[d]
	var su: int = strides[(d + 1) % 3]
	var sv: int = strides[(d + 2) % 3]
	var base := i * sd
	var j := 0
	for vv in S:
		var idx := base + vv * sv
		for uu in S:
			out[j] = data[idx]
			idx += su
			j += 1
	return out


static func _neighbour_slice(grid: VoxelGrid, key: Vector3i, d: int, side: int) -> PackedByteArray:
	var nk := key
	nk[d] += side
	var nd = grid.chunks.get(nk)
	if nd == null:
		var empty := PackedByteArray()
		empty.resize(S * S)
		return empty
	return _slice(nd, d, S - 1 if side < 0 else 0)


static func _greedy(mask: PackedInt32Array, d: int, u: int, v: int, i: int, dir: int,
		origin: Vector3, palette: Array, cell_m: float,
		verts: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray,
		indices: PackedInt32Array, faces: PackedVector3Array) -> void:
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
			_quad(p * cell_m, du * cell_m, dv * cell_m, dir, normal, col, verts, normals, colors, indices, faces)
			uu += w


static func _quad(p: Vector3, du: Vector3, dv: Vector3, dir: int, normal: Vector3, col: Color,
		verts: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray,
		indices: PackedInt32Array, faces: PackedVector3Array) -> void:
	var base := verts.size()
	var a := p
	var b := p + du
	var c := p + du + dv
	var e := p + dv
	verts.append_array([a, b, c, e])
	for k in 4:
		normals.append(normal)
		colors.append(col)
	# Godot treats clockwise triangles as front-facing. u x v points along +d,
	# so a->b->c is counter-clockwise seen from +d.
	if dir > 0:
		indices.append_array([base, base + 3, base + 2, base, base + 2, base + 1])
		faces.append_array([a, e, c, a, c, b])
	else:
		indices.append_array([base, base + 1, base + 2, base, base + 2, base + 3])
		faces.append_array([a, b, c, a, c, e])
