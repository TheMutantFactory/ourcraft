class_name GridPainter
extends RefCounted
## Paints cells into raw chunk arrays and commits them to a VoxelGrid in one
## go: one compression per chunk instead of one per edit, which matters when
## generators write hundreds of thousands of cells.

var _raw := {}


func set_cell(p: Vector3i, value: int) -> void:
	var key := VoxelGrid.chunk_of(p)
	var data: PackedByteArray = _raw.get(key, PackedByteArray())
	if data.is_empty():
		data.resize(VoxelGrid.VOLUME)
		_raw[key] = data
	data[VoxelGrid.index(p.x & VoxelGrid.MASK, p.y & VoxelGrid.MASK, p.z & VoxelGrid.MASK)] = value


## Fills [lo, hi) with value.
func fill_box(lo: Vector3i, hi: Vector3i, value: int) -> void:
	for z in range(lo.z, hi.z):
		for y in range(lo.y, hi.y):
			for x in range(lo.x, hi.x):
				set_cell(Vector3i(x, y, z), value)


## A horizontal run of cells [x0, x1) at row (y, z).
func fill_row(x0: int, x1: int, y: int, z: int, value: int) -> void:
	for x in range(x0, x1):
		set_cell(Vector3i(x, y, z), value)


## A thick straight line from a to b (cell units, floats) `width` cells wide
## across and `height` cells tall, starting at y.
func line(a: Vector2, b: Vector2, width: float, y: int, height: int, value: int) -> void:
	var d := b - a
	var length := d.length()
	if length == 0.0:
		return
	var along := d / length
	var across := Vector2(-along.y, along.x)
	var t := 0.0
	while t <= length:
		var w := -width * 0.5
		while w <= width * 0.5:
			var p := a + along * t + across * w
			for k in height:
				set_cell(Vector3i(floori(p.x), y + k, floori(p.y)), value)
			w += 0.5
		t += 0.5


func commit(grid: VoxelGrid) -> void:
	for key in _raw:
		grid.set_chunk(key, _raw[key])
	_raw.clear()
