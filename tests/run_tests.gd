extends SceneTree
## Headless tests for the core model. Run with:
##   godot --headless --path . --script res://tests/run_tests.gd

var _failures := 0
var _count := 0


var _ran := false


## Runs on the first frame so nodes added to the tree (WorldView) are ready.
func _process(_delta: float) -> bool:
	if _ran:
		return true
	_ran = true
	_run()
	return true


func _run() -> void:
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
	test_pack_dedupes_and_appends()
	test_pack_survives_truncated_append()
	test_pack_compacts_garbage()
	test_loads_and_converts_v1_folder()
	test_loads_hand_formatted_objects_json()
	test_outline_builds_rows_lazily()
	test_corner_reparent()
	test_reparent_keeps_world_position()
	test_remove_and_prune()
	test_gradient_words()
	test_burst_collect()
	test_recording_off()
	test_outline_drop_rules()
	test_corner_depth_limit()
	test_corner_wide_and_empty()
	test_corner_rotation_and_far_offsets()
	test_corner_delete_used_object()
	test_corner_names_and_history()
	test_corner_import_existing_id()
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
	check(not FileAccess.get_file_as_string(dir.path_join("objects.json")).contains(spare.id), "deleted object's entry removed")
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


func _fresh_dir(name: String) -> String:
	var dir := ProjectSettings.globalize_path("user://test_projects/" + name)
	if DirAccess.dir_exists_absolute(dir):
		for sub in ["", "objects"]:
			var d := dir.path_join(sub)
			if not DirAccess.dir_exists_absolute(d):
				continue
			for f in DirAccess.get_files_at(d):
				DirAccess.remove_absolute(d.path_join(f))
	return dir


func _pack_of(dir: String) -> String:
	for f in DirAccess.get_files_at(dir):
		if f.begins_with("chunks-") and f.ends_with(".pack"):
			return dir.path_join(f)
	return ""


func _same_objects(a: Project, b: Project) -> bool:
	if b == null or a.defs.size() != b.defs.size():
		return false
	for id in a.defs:
		if not b.defs.has(id) or JSON.stringify(a.defs[id].to_dict()) != JSON.stringify(b.defs[id].to_dict()):
			return false
	return true


func test_pack_dedupes_and_appends() -> void:
	var p := Project.create_empty(0.01)
	for i in 50:
		var d := p.create_def("Crate %d" % i, 1)
		d.grid.fill_box(Vector3i.ZERO, Vector3i(10, 10, 10), 3)
		p.root().children.append(Demo._inst(p, d.id, Vector3i(i * 20, 0, 0), 0))
	var dir := _fresh_dir("pack.ourcraft")
	p.save_dir(dir)
	var pack: Dictionary = ChunkPack.read(_pack_of(dir))
	check(pack.size() == 1, "50 identical crates store one chunk (%d)" % pack.size())
	var size_before := FileAccess.get_file_as_bytes(_pack_of(dir)).size()
	p.edit_box(p.defs.keys()[1], Vector3i(0, 0, 0), Vector3i(1, 1, 1), 5)
	p.save_dir(dir)
	check(ChunkPack.read(_pack_of(dir)).size() == 2, "an edit appends one new chunk")
	check(FileAccess.get_file_as_bytes(_pack_of(dir)).size() > size_before, "pack grew by appending")
	check(_same_objects(p, Project.load_dir(dir)), "deduplicated pack loads back identical")
	var lines := FileAccess.get_file_as_string(dir.path_join("objects.json")).split("\n", false)
	check(lines.size() == p.defs.size() + 2, "objects.json has one line per object")


func test_pack_survives_truncated_append() -> void:
	var p := Demo.build(0.01)
	var dir := _fresh_dir("trunc.ourcraft")
	p.save_dir(dir)
	var path := _pack_of(dir)
	var f := FileAccess.open(path, FileAccess.READ_WRITE)
	f.seek_end()
	f.store_buffer(PackedByteArray([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 255, 255, 0, 0, 9]))
	f.close()
	check(_same_objects(p, Project.load_dir(dir)), "a torn append at the end of the pack is ignored")


func test_pack_compacts_garbage() -> void:
	var p := Project.create_empty(0.01)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var ids := []
	for i in 40:
		var d := p.create_def("Noise %d" % i, 1)
		for k in 400:
			d.grid.set_cell(Vector3i(rng.randi_range(0, 31), rng.randi_range(0, 31), rng.randi_range(0, 31)), rng.randi_range(1, 9))
		ids.append(d.id)
	p.compact_min_garbage = 0
	var dir := _fresh_dir("compact.ourcraft")
	p.save_dir(dir)
	var first := _pack_of(dir)
	for i in 35:
		p.delete_def(ids[i])
	p.save_dir(dir)
	var second := _pack_of(dir)
	check(second != first and not FileAccess.file_exists(first), "mostly-garbage pack rewritten as a new pack")
	check(ChunkPack.read(second).size() == 5, "compacted pack keeps only live chunks")
	check(_same_objects(p, Project.load_dir(dir)), "compacted project loads back identical")


## Version 1 folders (objects/<id>.json) load, and the next save converts them.
func test_loads_and_converts_v1_folder() -> void:
	var p := Demo.build(0.01)
	var dir := _fresh_dir("v1.ourcraft")
	DirAccess.make_dir_recursive_absolute(dir.path_join("objects"))
	var m := p.manifest()
	m.version = 1
	m.erase("objects_file")
	var ids := p.defs.keys()
	ids.sort()
	m.objects = ids
	FileAccess.open(dir.path_join("manifest.json"), FileAccess.WRITE).store_string(JSON.stringify(m))
	for id in ids:
		FileAccess.open(dir.path_join("objects").path_join(id + ".json"), FileAccess.WRITE).store_string(JSON.stringify(p.defs[id].to_dict()))
	var q := Project.load_dir(dir)
	check(_same_objects(p, q), "version 1 folder loads")
	q.save_dir(dir)
	check(q.last_save_written == q.defs.size(), "saving a version 1 folder writes everything")
	check(not DirAccess.dir_exists_absolute(dir.path_join("objects")), "conversion removes the old objects folder")
	check(_same_objects(p, Project.load_dir(dir)), "converted folder loads identical")


func test_loads_hand_formatted_objects_json() -> void:
	var p := Demo.build(0.01)
	var dir := _fresh_dir("pretty.ourcraft")
	p.save_dir(dir)
	var whole = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join("objects.json")))
	FileAccess.open(dir.path_join("objects.json"), FileAccess.WRITE).store_string(JSON.stringify(whole, "    "))
	var q := Project.load_dir(dir)
	check(_same_objects(p, q), "reformatted objects.json still loads")
	q.save_dir(dir)
	check(q.last_save_written == q.defs.size(), "objects from a reformatted file are rewritten")


func test_outline_builds_rows_lazily() -> void:
	var hud := Hud.new()
	root.add_child(hud)
	var p := Demo.build(0.01)
	hud.refresh_outline(p, PackedStringArray(), null)
	var world := hud.outline.get_root()
	var street := world.get_first_child()
	check(street.collapsed and street.get_child_count() == 1 and street.get_first_child().get_metadata(0) == null,
		"closed rows hold only a placeholder")
	street.collapsed = false
	check(street.get_child_count() == 3 and street.get_first_child().get_metadata(0) != null,
		"expanding a row builds its real children (%d)" % street.get_child_count())
	# Selecting a deep path opens its branch.
	var path := PackedStringArray()
	var def := p.root()
	while not def.children.is_empty():
		path.append(def.children[-1].id)
		def = p.defs[def.children[-1].def_id]
	hud.refresh_outline(p, PackedStringArray(), path)
	var sel := hud.outline.get_selected()
	check(sel != null and sel.get_metadata(0) == path, "the selected deep row is built and selected")
	hud.free()


## A WorldView attached to the running tree.
func _test_view(p: Project) -> WorldView:
	var view := WorldView.new()
	root.add_child(view)
	view.set_project(p)
	view.flush()
	return view


func test_corner_reparent() -> void:
	var p := Project.create_empty(0.01)
	var a := p.create_def("A")
	var b := p.create_def("B")
	var c := p.create_def("C")
	var ia := p.add_instance(p.root_id, a.id, Vector3i.ZERO)
	var ib := p.add_instance(a.id, b.id, Vector3i(5, 0, 0))
	p.add_instance(b.id, c.id, Vector3i.ZERO)
	check(not p.reparent_instance(p.root_id, ia.id, b.id, Vector3i.ZERO), "can't move A into its own descendant B")
	check(not p.reparent_instance(a.id, ib.id, b.id, Vector3i.ZERO), "can't move B into itself")
	check(p.reparent_instance(a.id, ib.id, a.id, Vector3i(9, 0, 0)) and ib.offset == Vector3i(9, 0, 0), "moving within the same parent works")
	check(p.reparent_instance(a.id, ib.id, p.root_id, Vector3i(1, 2, 3)), "move B up to the world")
	check(a.children.is_empty() and p.root().find_child(ib.id) == ib, "B left A and joined the world with the same id")
	p.undo()
	check(a.find_child(ib.id) != null and p.root().find_child(ib.id) == null, "undo puts B back in A")


func test_reparent_keeps_world_position() -> void:
	var p := Project.create_empty(0.01)
	var house := p.create_def("House", 10)
	var room := p.create_def("Room", 5)
	var lamp := p.create_def("Lamp", 1)
	var ih := p.add_instance(p.root_id, house.id, Vector3i(1000, 0, -300), 1)
	var ir := p.add_instance(house.id, room.id, Vector3i(40, 10, 70), 2)
	var il := p.add_instance(room.id, lamp.id, Vector3i(13, 5, -8), 3)
	var lamp_path := PackedStringArray([ih.id, ir.id, il.id])
	var world := p.path_transform(lamp_path)
	check(p.reparent_path(lamp_path, PackedStringArray()) == "", "move the lamp up to the world")
	var up := PackedStringArray([il.id])
	check(p.path_transform(up).is_equal_approx(world), "the lamp stayed in place in the world")
	check(p.reparent_path(up, PackedStringArray([ih.id])) == "", "move it into the rotated house")
	check(p.path_transform(PackedStringArray([ih.id, il.id])).is_equal_approx(world), "still in place inside the rotated house")
	check(p.reparent_path(PackedStringArray([ih.id]), PackedStringArray([ih.id, ir.id])) != "", "can't move the house into its own room")
	check(p.reparent_path(PackedStringArray(), PackedStringArray([ih.id])) != "", "the world can't be moved")
	p.undo()
	check(p.root().find_child(il.id) != null, "undo brings the lamp back to the world")


func test_remove_and_prune() -> void:
	var p := Project.create_empty(0.01)
	var trees := WordTrees.new(3)
	var a := trees.build(p, 3, 3)
	var shared := p.create_def("Shared")
	a.children.append(Demo._inst(p, shared.id, Vector3i.ZERO, 0))
	var keep := p.create_def("Keeper")
	keep.children.append(Demo._inst(p, shared.id, Vector3i.ZERO, 0))
	p.add_instance(p.root_id, keep.id, Vector3i.ZERO)
	var ia := p.add_instance(p.root_id, a.id, Vector3i(500, 0, 0))
	var tree_defs := p.dependencies(a.id).size()
	var deleted := p.remove_and_prune(p.root_id, ia.id)
	check(deleted == tree_defs - 1, "pruning deletes the tree's objects but not the shared one (%d of %d)" % [deleted, tree_defs])
	check(p.defs.has(shared.id) and p.defs.has(keep.id) and not p.defs.has(a.id), "shared and unrelated objects survive")
	var dangling := false
	for d in p.defs.values():
		for inst in d.children:
			if not p.defs.has(inst.def_id):
				dangling = true
	check(not dangling, "no dangling instances after pruning")


func test_gradient_words() -> void:
	var p := Project.create_empty(0.01)
	var base := PaletteRamps.ensure(p)
	check(p.palette.size() == 10 + PaletteRamps.RAMPS.size() * PaletteRamps.STEPS and PaletteRamps.ensure(p) == base,
		"ramps are added to the palette once")
	var cols := PaletteRamps.letter_colours(base, 2, 4)
	check(cols.size() == 4 and cols[0] == base + 2 * PaletteRamps.STEPS and cols[3] == base + 3 * PaletteRamps.STEPS - 1,
		"letters span a ramp from its first to its last step")
	var g := VoxelGrid.new()
	BlockFont.write(g, "IO", 1, 1, PackedByteArray([cols[0], cols[3]]))
	check(g.get_cell(Vector3i(2, 6, 0)) == cols[0] and g.get_cell(Vector3i(7, 6, 0)) == cols[3], "each letter gets its own colour")


func test_burst_collect() -> void:
	var p := Project.create_empty(0.01)
	var word := p.create_def("word", 1)
	BlockFont.write(word.grid, "AB", 3, 2)
	var big := p.create_def("big", 1)
	big.grid.fill_box(Vector3i.ZERO, Vector3i(64, 64, 64), 4)
	var iw := p.add_instance(p.root_id, word.id, Vector3i(100, 0, 0))
	var ib := p.add_instance(p.root_id, big.id, Vector3i(0, 0, 300))
	var view := _test_view(p)
	var small := BurstEffect.collect(p, view, PackedStringArray([iw.id]), 1500, 0.01)
	check(small.chunk == 1 and small.points.size() == word.grid.solid_count(), "small objects burst block by block")
	var sized := BurstEffect.collect(p, view, PackedStringArray([iw.id]), 1500, 0.04)
	check(sized.chunk == 4 and sized.points.size() < small.points.size(), "a minimum cube size groups blocks (chunk %d)" % sized.chunk)
	var huge := BurstEffect.collect(p, view, PackedStringArray([ib.id]), 1500, 0.01)
	check(huge.points.size() <= 1500 and huge.chunk == 8, "a big object is grouped to stay within budget (%d cubes, chunk %d)" % [huge.points.size(), huge.chunk])
	check(huge.colors[0] == p.palette[3], "cubes take the object's colour")
	view.free()


func test_recording_off() -> void:
	var p := Project.create_empty(0.01)
	p.edit_box(p.root_id, Vector3i.ZERO, Vector3i.ONE, 1)
	p.set_recording(false)
	check(not p.can_undo(), "turning recording off clears history")
	p.edit_box(p.root_id, Vector3i(5, 0, 0), Vector3i(6, 1, 1), 1)
	var d := p.create_def("Thing")
	p.add_instance(p.root_id, d.id, Vector3i.ZERO)
	check(not p.can_undo() and p.root().grid.solid_count() == 2, "changes apply but aren't recorded")
	p.begin_step("drag")
	var i := p.add_instance(p.root_id, d.id, Vector3i(9, 0, 0))
	p.cancel_step()
	check(p.root().find_child(i.id) == null, "cancel still reverts without recording")
	p.set_recording(true)
	p.edit_box(p.root_id, Vector3i(7, 0, 0), Vector3i(8, 1, 1), 1)
	check(p.can_undo(), "recording resumes")


func test_outline_drop_rules() -> void:
	var hud := Hud.new()
	root.add_child(hud)
	var p := Demo.build(0.01)
	hud.refresh_outline(p, PackedStringArray(), null)
	var path := PackedStringArray()
	var def := p.root()
	while not def.children.is_empty():
		path.append(def.children[-1].id)
		def = p.defs[def.children[-1].def_id]
	# path: Street > House > Kitchen > Table > Fork
	check(hud.can_move(path, PackedStringArray()), "a fork can be dropped on the world")
	check(not hud.can_move(path, path.slice(0, path.size() - 1)), "dropping on its own parent does nothing")
	check(not hud.can_move(path.slice(0, 2), path.slice(0, 3)), "a house can't be dropped into its own kitchen")
	check(not hud.can_move(PackedStringArray(), path), "the world can't be dragged")
	hud.free()


## Paths deeper than Project.MAX_DEPTH (32) aren't rendered. This pins the
## current behaviour: a 40-deep chain renders its first 33 levels, without
## errors, and the data keeps all 40.
func test_corner_depth_limit() -> void:
	var p := Project.create_empty(0.01)
	var parent := p.root()
	for i in 40:
		var d := p.create_def("L%d" % i)
		d.grid.set_cell(Vector3i.ZERO, 1)
		p.add_instance(parent.id, d.id, Vector3i(0, 0, 2))
		parent = d
	var view := _test_view(p)
	check(view._placements.size() == Project.MAX_DEPTH + 1, "deep chain renders %d levels (limit %d)" % [view._placements.size(), Project.MAX_DEPTH])
	check(p.dependencies(p.root_id).size() == 41, "the data keeps all 40 levels")
	view.free()


func test_corner_wide_and_empty() -> void:
	var p := Project.create_empty(0.01)
	var leaf := p.create_def("Leaf")
	leaf.grid.set_cell(Vector3i.ZERO, 2)
	var hub := p.create_def("Hub")
	for i in 1000:
		hub.children.append(Demo._inst(p, leaf.id, Vector3i(i * 3, 0, 0), i % 4))
	var empty := p.create_def("Empty")
	p.add_instance(p.root_id, hub.id, Vector3i.ZERO)
	p.add_instance(p.root_id, empty.id, Vector3i(0, 0, 50))
	var view := _test_view(p)
	check(view._placements.size() == 1003, "1000 children render (%d placements)" % view._placements.size())
	check(view._renderer.drawn_placements().size() + view._baker.baked_placements().size() == 1003, "every placement drawn once")
	check(p.def_bounds(empty.id).size == Vector3.ZERO, "an empty object has zero bounds")
	view.free()
	var dir := _fresh_dir("wide.ourcraft")
	p.save_dir(dir)
	var q := Project.load_dir(dir)
	check(q != null and q.defs.size() == p.defs.size() and q.defs[empty.id].grid.is_empty(), "empty and wide objects round-trip")


## Quarter turns compose exactly; integer offsets stay exact up to the
## float limit (2^24 smallest blocks, ~168 km at 1 cm).
func test_corner_rotation_and_far_offsets() -> void:
	var b := Basis.IDENTITY
	for i in 4:
		b = b * ObjectInstance.basis_for(1)
	check(b == Basis.IDENTITY, "four quarter turns are exactly the identity")
	var p := Project.create_empty(0.01)
	var a := p.create_def("Far")
	var ok := true
	for off in [Vector3i(8_000_000, 0, -8_000_000), Vector3i(16_777_215, 3, 1)]:
		var inst := p.add_instance(p.root_id, a.id, off)
		var o := p.path_transform(PackedStringArray([inst.id])).origin
		if Vector3i(o) != off:
			ok = false
	check(ok, "offsets up to 2^24 blocks stay exact")
	var beyond := p.add_instance(p.root_id, a.id, Vector3i(16_777_217, 0, 0))
	var o2 := p.path_transform(PackedStringArray([beyond.id])).origin
	check(int(o2.x) != 16_777_217, "beyond 2^24 blocks positions round (known limit)")


func test_corner_delete_used_object() -> void:
	var p := Demo.build(0.01)
	var fork: ObjectDef
	for d in p.defs.values():
		if d.name == "Fork":
			fork = d
	var uses := p.usage_count(fork.id)
	check(uses == 2, "fork used twice in the demo")
	p.edit_box(p.root_id, Vector3i.ZERO, Vector3i.ONE, 3)
	check(p.delete_def(fork.id), "delete a used object")
	check(not p.can_undo(), "deleting an object clears undo history")
	var dangling := false
	for d in p.defs.values():
		for inst in d.children:
			if inst.def_id == fork.id:
				dangling = true
	check(not dangling and not p.delete_def(p.root_id), "no dangling instances; the world can't be deleted")


func test_corner_names_and_history() -> void:
	var p := Project.create_empty(0.01)
	var d := p.create_def("Thing")
	p.rename_def(d.id, "   ")
	check(d.name == "Thing", "a blank name is ignored")
	p.rename_def(d.id, "  naïve café  ")
	check(d.name == "naïve café", "names are trimmed and keep accents")
	var e := p.create_def("Thing")
	check(e.name == "Thing" and p.unique_name("Thing") == "Thing 2", "duplicate names are allowed; unique_name numbers them")
	for i in Project.MAX_HISTORY + 20:
		p.edit_box(d.id, Vector3i(i, 0, 0), Vector3i(i + 1, 1, 1), 1)
	check(p._undo.size() == Project.MAX_HISTORY, "undo history is capped at %d" % Project.MAX_HISTORY)


## Importing a bundle whose object id already exists keeps the local
## object, even if the bundle's version differs (documented behaviour).
func test_corner_import_existing_id() -> void:
	var p := Demo.build(0.01)
	var table: ObjectDef
	for d in p.defs.values():
		if d.name == "Table":
			table = d
	var file := ProjectSettings.globalize_path("user://test_projects/table2.ourobj.json")
	p.export_object(table.id, file)
	table.grid.set_cell(Vector3i(0, 50, 0), 9)
	var before := table.grid.solid_count()
	check(p.import_bundle(file) == table.id and table.grid.solid_count() == before, "importing an existing id keeps the local version")


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
