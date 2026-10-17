class_name Demo
extends RefCounted
## Builds the starter world: a street of instanced houses whose kitchens hold
## a table set with plates and forks, so the object tree is several levels
## deep from the first minute. Sizes assume a 1 cm minimum block.

enum { STONE = 1, PLASTER, OAK, WALNUT, BRICK, LEAF, BLUE, BRASS, CHARCOAL, STEEL }


static func build(voxel_size_m: float) -> Project:
	var p := Project.create_empty(voxel_size_m)
	p.title = "Small street"

	var fork := p.create_def("Fork", 1)
	_box(fork, 2, 0, 0, 1, 1, 12, STEEL)
	_box(fork, 0, 0, 12, 5, 1, 2, STEEL)
	for x in [0, 2, 4]:
		_box(fork, x, 0, 14, 1, 1, 5, STEEL)

	var plate := p.create_def("Plate", 1)
	for x in range(-11, 12):
		for z in range(-11, 12):
			var r := sqrt(x * x + z * z)
			if r <= 11.0:
				_box(plate, x, 0, z, 1, 1, 1, PLASTER)
			if r >= 9.0 and r <= 11.0:
				_box(plate, x, 1, z, 1, 1, 1, PLASTER)

	var table := p.create_def("Table", 2)
	_box(table, 0, 36, 0, 60, 2, 40, OAK)
	for c in [Vector2i(1, 1), Vector2i(56, 1), Vector2i(1, 36), Vector2i(56, 36)]:
		_box(table, c.x, 0, c.y, 3, 36, 3, WALNUT)
	table.children.append(_inst(p, plate.id, Vector3i(30, 76, 40), 0))
	table.children.append(_inst(p, fork.id, Vector3i(44, 76, 31), 0))
	table.children.append(_inst(p, plate.id, Vector3i(90, 76, 40), 0))
	table.children.append(_inst(p, fork.id, Vector3i(76, 76, 49), 2))

	var kitchen := p.create_def("Kitchen", 5)
	_box(kitchen, 0, 0, 0, 48, 17, 12, WALNUT)
	_box(kitchen, 0, 17, 0, 48, 1, 12, STONE)
	_box(kitchen, 50, 0, 0, 14, 36, 14, STEEL)
	kitchen.children.append(_inst(p, table.id, Vector3i(60, 0, 140), 0))

	var house := p.create_def("House", 10)
	_box(house, 0, 0, 0, 60, 1, 50, OAK)
	_box(house, 0, 1, 0, 60, 26, 1, PLASTER)
	_box(house, 0, 1, 49, 60, 26, 1, PLASTER)
	_box(house, 0, 1, 0, 1, 26, 50, PLASTER)
	_box(house, 59, 1, 0, 1, 26, 50, PLASTER)
	_box(house, 25, 1, 49, 10, 21, 1, 0)       # door
	_box(house, 8, 10, 49, 10, 8, 1, 0)        # front windows
	_box(house, 42, 10, 49, 10, 8, 1, 0)
	_box(house, 0, 10, 15, 1, 8, 20, 0)        # side windows
	_box(house, 59, 10, 15, 1, 8, 20, 0)
	_box(house, -1, 27, -1, 62, 1, 52, BRICK)  # roof
	_box(house, 24, 22, 50, 12, 1, 1, WALNUT)  # door lintel
	house.children.append(_inst(p, kitchen.id, Vector3i(10, 10, 10), 0))

	var street := p.create_def("Street", 10)
	_box(street, 0, 0, 0, 300, 1, 60, CHARCOAL)
	for x in range(5, 300, 20):
		_box(street, x, 0, 29, 10, 1, 2, PLASTER)
	street.children.append(_inst(p, house.id, Vector3i(200, 0, -520), 0))
	street.children.append(_inst(p, house.id, Vector3i(1000, 0, -520), 0))
	street.children.append(_inst(p, house.id, Vector3i(2400, 0, 1120), 2))

	p.root().children.append(_inst(p, street.id, Vector3i(-1500, 0, 0), 0))
	return p


static func _box(def: ObjectDef, x: int, y: int, z: int, sx: int, sy: int, sz: int, color: int) -> void:
	def.grid.fill_box(Vector3i(x, y, z), Vector3i(x + sx, y + sy, z + sz), color)


static func _inst(p: Project, def_id: String, offset: Vector3i, rot: int) -> ObjectInstance:
	var inst := ObjectInstance.new()
	inst.id = Project.new_id()
	inst.def_id = def_id
	inst.offset = offset
	inst.rot = rot
	return inst
