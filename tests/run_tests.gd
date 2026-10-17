extends SceneTree
## Headless tests for the core model. Run with:
##   godot --headless --path . --script res://tests/run_tests.gd

var _failures := 0
var _count := 0


func _init() -> void:
	print("native extension: %s" % ("loaded" if Native.available() else "not built (GDScript paths)"))
	test_grid_fill_and_counts()
	test_negative_coordinates()
	test_mesher_merges_faces()
	test_mesher_matches_brute_force()
	test_mesher_uniform_chunk_with_partial_neighbour()
	test_native_matches_gdscript()
	test_cycle_detection()
	test_paths_and_bounds()
	test_undo_redo()
	test_fork()
	test_save_load_round_trip()
	test_bundle_export_import()
	test_incremental_save()
	test_loads_legacy_deflate_chunks()
	test_chunks_stored_compressed()
	test_demo_tree_depth()
	print("%d checks, %d failed" % [_count, _failures])
	quit(1 if _failures > 0 else 0)


func check(cond: bool, msg: String) -> void:
	_count += 1
	if not cond:
		_failures += 1
		push_error("FAIL: " + msg)
		print("FAIL: " + msg)


func test_grid_fill_and_counts() -> void:
	var g := VoxelGrid.new()
	g.fill_box(Vector3i(0, 0, 0), Vector3i(40, 2, 3), 5)
	check(g.solid_count() == 40 * 2 * 3, "fill count")
	check(g.chunk_count() == 2, "fill spans two chunks")
	check(g.get_cell(Vector3i(39, 1, 2)) == 5, "cell value")
	g.fill_box(Vector3i(0, 0, 0), Vector3i(40, 2, 3), 0)
	check(g.is_empty(), "erasing frees chunks")
	g.fill_box(Vector3i(0, 0, 0), Vector3i(64, 32, 32), 1)
	check(g.solid_count() == 64 * 32 * 32, "full chunk fill")
	check(g.bounds() == AABB(Vector3.ZERO, Vector3(64, 32, 32)), "bounds")


func test_negative_coordinates() -> void:
	var g := VoxelGrid.new()
	g.set_cell(Vector3i(-1, -1, -1), 3)
	check(VoxelGrid.chunk_of(Vector3i(-1, -1, -1)) == Vector3i(-1, -1, -1), "negative chunk key")
	check(g.get_cell(Vector3i(-1, -1, -1)) == 3, "negative cell")
	check(g.get_cell(Vector3i(31, 31, 31)) == 0, "no aliasing")
	check(g.bounds() == AABB(Vector3(-1, -1, -1), Vector3.ONE), "negative bounds")


func test_mesher_merges_faces() -> void:
	var pal: Array = Project.DEFAULT_PALETTE
	var g := VoxelGrid.new()
	g.set_cell(Vector3i(3, 3, 3), 1)
	var m := Mesher.build(g, Vector3i.ZERO, pal, 1.0)
	check(m.arrays[Mesh.ARRAY_INDEX].size() == 6 * 6, "single cell has 6 quads")
	g.fill_box(Vector3i(0, 0, 0), Vector3i(32, 32, 32), 2)
	m = Mesher.build(g, Vector3i.ZERO, pal, 1.0)
	check(m.arrays[Mesh.ARRAY_INDEX].size() == 6 * 6, "full chunk merges to 6 quads")
	g.fill_box(Vector3i(32, 0, 0), Vector3i(64, 32, 32), 2)
	m = Mesher.build(g, Vector3i.ZERO, pal, 1.0)
	check(m.arrays[Mesh.ARRAY_INDEX].size() == 5 * 6, "shared face with neighbour culled")
	# Winding: first +x face triangle normal should point along +x for
	# Godot's clockwise-front convention (cross of (b-a),(c-a) points inward).
	var g2 := VoxelGrid.new()
	g2.set_cell(Vector3i.ZERO, 1)
	var m2 := Mesher.build(g2, Vector3i.ZERO, pal, 1.0)
	var verts: PackedVector3Array = m2.arrays[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = m2.arrays[Mesh.ARRAY_NORMAL]
	var idx: PackedInt32Array = m2.arrays[Mesh.ARRAY_INDEX]
	var ok := true
	for t in range(0, idx.size(), 3):
		var a := verts[idx[t]]
		var b := verts[idx[t + 1]]
		var c := verts[idx[t + 2]]
		if (b - a).cross(c - a).dot(norms[idx[t]]) >= 0.0:
			ok = false
	check(ok, "triangles are clockwise seen from outside")


## Total face area (in cells) of a mesh result, per normal direction.
func _face_area(m: Dictionary) -> float:
	if m.is_empty():
		return 0.0
	var faces: PackedVector3Array = m.faces
	var area := 0.0
	for t in range(0, faces.size(), 3):
		area += (faces[t + 1] - faces[t]).cross(faces[t + 2] - faces[t]).length() * 0.5
	return area


## Exposed faces of the cells inside one chunk, counted cell by cell.
func _brute_faces(g: VoxelGrid, key: Vector3i) -> int:
	var n := 0
	var o := key * VoxelGrid.SIZE
	for z in VoxelGrid.SIZE:
		for y in VoxelGrid.SIZE:
			for x in VoxelGrid.SIZE:
				var p := o + Vector3i(x, y, z)
				if g.get_cell(p) == 0:
					continue
				for dir in [Vector3i.LEFT, Vector3i.RIGHT, Vector3i.UP, Vector3i.DOWN, Vector3i.FORWARD, Vector3i.BACK]:
					if g.get_cell(p + dir) == 0:
						n += 1
	return n


func test_mesher_matches_brute_force() -> void:
	seed(1234)
	var g := VoxelGrid.new()
	for i in 6000:
		var p := Vector3i(randi_range(-8, 40), randi_range(-8, 40), randi_range(-8, 40))
		g.set_cell(p, randi_range(1, 3))
	g.fill_box(Vector3i(4, 4, 4), Vector3i(20, 9, 30), 2)
	var total := 0.0
	var expected := 0
	for key in g.keys():
		total += _face_area(Mesher.build(g, key, Project.DEFAULT_PALETTE, 1.0))
		expected += _brute_faces(g, key)
	check(is_equal_approx(total, float(expected)), "mesh area %s == exposed faces %d" % [total, expected])


func test_mesher_uniform_chunk_with_partial_neighbour() -> void:
	var g := VoxelGrid.new()
	g.fill_box(Vector3i.ZERO, Vector3i(32, 32, 32), 4)
	g.set_cell(Vector3i(32, 5, 7), 1)
	g.set_cell(Vector3i(-1, 0, 0), 1)
	var own := _face_area(Mesher.build(g, Vector3i.ZERO, Project.DEFAULT_PALETTE, 1.0))
	check(is_equal_approx(own, 6.0 * 1024.0 - 2.0), "uniform chunk leaves holes where neighbours touch: %s" % own)


## Runs the same edits and meshing through both implementations and
## requires identical results.
func test_native_matches_gdscript() -> void:
	if not Native.available():
		print("skipping native comparison: extension not built")
		return
	var grids := []
	for use_native in [true, false]:
		Native.enabled = use_native
		seed(99)
		var g := VoxelGrid.new()
		for i in 400:
			var a := Vector3i(randi_range(-20, 50), randi_range(-20, 50), randi_range(-20, 50))
			var size := Vector3i(randi_range(1, 30), randi_range(1, 30), randi_range(1, 30))
			g.fill_box(a, a + size, randi_range(0, 4))
		grids.append(g)
	Native.enabled = true
	var gn: VoxelGrid = grids[0]
	var gs: VoxelGrid = grids[1]
	check(gn.keys() == gs.keys() and gn.counts == gs.counts, "native fill matches GDScript")
	var same := true
	for key in gn.keys():
		if gn.get_chunk(key) != gs.get_chunk(key):
			same = false
	check(same, "native fill cell data matches")
	var pal: Array = Project.DEFAULT_PALETTE
	var mesh_same := true
	for key in gn.keys():
		var input := Mesher.gather(gn, key)
		var a: Dictionary = Native.kernels().mesh_chunk(input, key, pal, 0.01)
		var b := Mesher.build_gdscript(input, key, pal, 0.01)
		if a.is_empty() != b.is_empty():
			mesh_same = false
			continue
		if a.is_empty():
			continue
		for k in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_INDEX]:
			if a.arrays[k] != b.arrays[k]:
				mesh_same = false
		var ca: PackedColorArray = a.arrays[Mesh.ARRAY_COLOR]
		var cb: PackedColorArray = b.arrays[Mesh.ARRAY_COLOR]
		for i in ca.size():
			if not ca[i].is_equal_approx(cb[i]):
				mesh_same = false
				break
	check(mesh_same, "native mesh matches GDScript mesh")


func test_cycle_detection() -> void:
	var p := Project.create_empty(0.01)
	var a := p.create_def("A")
	var b := p.create_def("B")
	check(p.add_instance(a.id, b.id, Vector3i.ZERO) != null, "A contains B")
	check(p.add_instance(b.id, a.id, Vector3i.ZERO) == null, "B cannot contain A")
	check(p.add_instance(a.id, a.id, Vector3i.ZERO) == null, "A cannot contain A")


func test_paths_and_bounds() -> void:
	var p := Project.create_empty(0.01)
	var cup := p.create_def("Cup", 1)
	cup.grid.fill_box(Vector3i.ZERO, Vector3i(4, 6, 4), 1)
	var shelf := p.create_def("Shelf", 10)
	shelf.grid.fill_box(Vector3i.ZERO, Vector3i(10, 1, 3), 3)
	var ci := p.add_instance(shelf.id, cup.id, Vector3i(5, 10, 5))
	var si := p.add_instance(p.root_id, shelf.id, Vector3i(100, 0, 0), 1)
	var path := PackedStringArray([si.id, ci.id])
	check(p.def_at(path) == cup, "resolve path")
	check(p.path_label(path) == "World › Shelf › Cup", "path label")
	check(p.def_bounds(shelf.id) == AABB(Vector3.ZERO, Vector3(100, 16, 30)), "nested bounds in min units")
	var world_origin := p.path_transform(path) * Vector3.ZERO
	check(world_origin.is_equal_approx(Vector3(105, 10, -5)), "rotated path transform: %s" % world_origin)
	check(not p.is_valid_path(PackedStringArray(["nope"])), "invalid path")


func test_undo_redo() -> void:
	var p := Project.create_empty(0.01)
	var r := p.root()
	p.edit_box(r.id, Vector3i.ZERO, Vector3i(3, 3, 3), 2)
	p.edit_box(r.id, Vector3i(1, 1, 1), Vector3i(2, 2, 2), 0)
	check(r.grid.solid_count() == 26, "edits applied")
	p.undo()
	check(r.grid.solid_count() == 27, "undo restores")
	p.undo()
	check(r.grid.is_empty(), "undo to empty")
	p.redo()
	check(r.grid.solid_count() == 27, "redo")
	var d := p.create_def("Thing")
	var inst := p.add_instance(r.id, d.id, Vector3i(1, 2, 3))
	p.set_instance_transform(r.id, inst.id, Vector3i(9, 9, 9), 2)
	p.undo()
	check(r.find_child(inst.id).offset == Vector3i(1, 2, 3), "undo move")
	p.undo()
	check(r.find_child(inst.id) == null, "undo add")
	p.begin_step("drag")
	p.add_instance(r.id, d.id, Vector3i.ZERO)
	p.cancel_step()
	check(r.children.is_empty(), "cancelled step reverts")


func test_fork() -> void:
	var p := Project.create_empty(0.01)
	var a := p.create_def("Chair", 2)
	a.grid.set_cell(Vector3i.ZERO, 4)
	var i1 := p.add_instance(p.root_id, a.id, Vector3i.ZERO)
	p.add_instance(p.root_id, a.id, Vector3i(50, 0, 0))
	check(p.usage_count(a.id) == 2, "two instances share a def")
	var f := p.fork_def(a.id)
	p.set_instance_def(p.root_id, i1.id, f.id)
	f.grid.set_cell(Vector3i(1, 0, 0), 4)
	check(a.grid.solid_count() == 1 and f.grid.solid_count() == 2, "fork is independent")
	check(f.forked_from == a.id and f.unit == 2, "fork keeps lineage and unit")


func test_save_load_round_trip() -> void:
	var p := Demo.build(0.01)
	var dir := ProjectSettings.globalize_path("user://test_projects/rt.ourcraft")
	check(p.save_dir(dir) == OK, "save")
	var q := Project.load_dir(dir)
	check(q != null, "load")
	if q == null:
		return
	check(q.defs.size() == p.defs.size(), "same object count")
	for id in p.defs:
		var a: ObjectDef = p.defs[id]
		var b: ObjectDef = q.defs[id]
		check(a.name == b.name and a.unit == b.unit, "def fields %s" % a.name)
		check(a.grid.solid_count() == b.grid.solid_count(), "voxels %s" % a.name)
		check(JSON.stringify(a.to_dict()) == JSON.stringify(b.to_dict()), "identical serialisation %s" % a.name)
	check(q.voxel_size == p.voxel_size, "min block size")


func test_incremental_save() -> void:
	var p := Demo.build(0.01)
	var dir := ProjectSettings.globalize_path("user://test_projects/inc.ourcraft")
	check(p.save_dir(dir) == OK, "first save")
	check(p.last_save_written == p.defs.size(), "first save writes every object")
	p.save_dir(dir)
	check(p.last_save_written == 0, "unchanged save writes nothing")
	var fork: ObjectDef
	var table: ObjectDef
	for d in p.defs.values():
		if d.name == "Fork": fork = d
		if d.name == "Table": table = d
	p.edit_box(fork.id, Vector3i(0, 5, 0), Vector3i(3, 6, 3), 4)
	p.set_instance_transform(table.id, table.children[0].id, Vector3i(31, 76, 40), 1)
	p.rename_def(p.root_id, "Renamed world")
	p.save_dir(dir)
	check(p.last_save_written == 3, "only edited, moved-in and renamed objects rewritten: %d" % p.last_save_written)
	p.undo()
	p.save_dir(dir)
	check(p.last_save_written == 1, "undo marks its object changed")
	var spare := p.create_def("Spare")
	p.save_dir(dir)
	p.delete_def(spare.id)
	p.save_dir(dir)
	check(not FileAccess.file_exists(dir.path_join("objects").path_join(spare.id + ".json")), "deleted object's file removed")
	var q := Project.load_dir(dir)
	var same := q != null and q.defs.size() == p.defs.size()
	if same:
		for id in p.defs:
			if JSON.stringify(p.defs[id].to_dict()) != JSON.stringify(q.defs[id].to_dict()):
				same = false
	check(same, "incremental saves load back identical")
	q.save_dir(dir)
	check(q.last_save_written == 0, "a freshly loaded project saves nothing back")


## Version 1 object files stored chunks as deflate; they must still load.
func test_loads_legacy_deflate_chunks() -> void:
	var def := ObjectDef.new()
	def.id = "legacy"
	def.name = "Legacy"
	def.grid.fill_box(Vector3i(-3, 0, 0), Vector3i(40, 5, 7), 6)
	var d := def.to_dict()
	d.version = 1
	d.chunk_format = ObjectDef.LEGACY_CHUNK_FORMAT
	for c in d.chunks:
		var k: Array = c.key
		var raw: PackedByteArray = def.grid.get_chunk(Vector3i(k[0], k[1], k[2]))
		c.data = Marshalls.raw_to_base64(raw.compress(FileAccess.COMPRESSION_DEFLATE))
	var back := ObjectDef.from_dict(JSON.parse_string(JSON.stringify(d)))
	check(back.grid.solid_count() == 43 * 5 * 7 and back.grid.get_cell(Vector3i(-3, 4, 6)) == 6, "legacy deflate chunks load")


func test_chunks_stored_compressed() -> void:
	var g := VoxelGrid.new()
	g.fill_box(Vector3i.ZERO, Vector3i(10, 10, 10), 3)
	var packed: PackedByteArray = g.get_packed(Vector3i.ZERO)
	check(packed.size() < 1024, "a mostly empty chunk is stored small (%d bytes)" % packed.size())
	var copy := g.copy()
	copy.fill_box(Vector3i.ZERO, Vector3i(1, 1, 1), 0)
	check(g.solid_count() == 1000 and copy.solid_count() == 999, "copies don't share edits")


func test_bundle_export_import() -> void:
	var p := Demo.build(0.01)
	var table: ObjectDef
	for d in p.defs.values():
		if d.name == "Table":
			table = d
	var file := ProjectSettings.globalize_path("user://test_projects/table.ourobj.json")
	check(p.export_object(table.id, file) == OK, "export")
	var q := Project.create_empty(0.01)
	var id := q.import_bundle(file)
	check(id == table.id, "import returns root")
	check(q.defs.size() == 1 + 3, "table + plate + fork imported")


func test_demo_tree_depth() -> void:
	var p := Demo.build(0.01)
	var path := PackedStringArray()
	var def := p.root()
	while not def.children.is_empty():
		path.append(def.children[-1].id)
		def = p.defs[def.children[-1].def_id]
	check(p.path_label(path) == "World › Street › House › Kitchen › Table › Fork", "demo depth: " + p.path_label(path))
