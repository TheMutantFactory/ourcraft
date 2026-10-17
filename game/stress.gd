extends Node3D
## Stress test. Builds scenes of increasing size, renders them with the
## game's lighting, and reports build, frame, memory and edit costs.
##
##   tools/stress.sh [heavy|many|all] [--max=N]
##
## heavy: one object at 1 cm resolution, carved by many random brush cuts
##        (like a block sculpted with mixed brush sizes), plus random noise as
##        the worst case for meshing.
## many:  many small objects, as instances of one object and as unique
##        objects.
## A series stops early when the next step is projected to be too slow or to
## use too much memory.

const BRUSHES := [1, 2, 5, 10, 25]
const MEASURE_FRAMES := 120
const WARMUP_FRAMES := 20
## Stop a series once a build takes longer than this (ms)...
const MAX_BUILD_MS := 60000.0
## ...or the next step is projected past this many quads.
const MAX_PROJECTED_QUADS := 6_000_000
## ...or past this much static memory (bytes).
const MAX_PROJECTED_MEM := 2_500_000_000

var view: WorldView
var cam: Camera3D
var rows: Array = []
var _report: PackedStringArray = []


func _ready() -> void:
	var win := get_window()
	var usable := DisplayServer.screen_get_usable_rect(win.current_screen)
	win.size = Vector2i(Vector2(usable.size) * 0.9)
	win.position = usable.position + (usable.size - win.size) / 2
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	Scenery.add_to(self)
	view = WorldView.new()
	add_child(view)
	cam = Camera3D.new()
	cam.far = 1500.0
	add_child(cam)
	cam.make_current()

	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else ""
	var suite: String = args.get("suite", "all")
	var max_exp := int(args.get("max", "5"))
	await get_tree().process_frame

	_line("# Ourcraft stress test")
	_line("")
	_line("- Date: %s" % Time.get_datetime_string_from_system(false, true))
	_line("- Godot %s, %s, %s, %d cores" % [Engine.get_version_info().string, OS.get_name(),
		RenderingServer.get_video_adapter_name(), OS.get_processor_count()])
	_line("- Render size %dx%d, vsync off, native extension %s" % [get_viewport().size.x,
		get_viewport().size.y, "on" if Native.available() else "OFF (GDScript)"])
	_line("- Minimum block 1 cm. Frame times are averages over %d frames with everything in view." % MEASURE_FRAMES)

	if suite in ["heavy", "all"]:
		await _series("Carved 2 m block (1 cm cells, random cuts of 1–25 cm)", "cuts", max_exp,
			func(n): return _carved(n))
		await _series("Random noise cube (50% filled 1 cm cells; worst case for meshing)", "cells", mini(max_exp + 2, 7),
			func(n): return _noise(n), 4)
	if suite in ["many", "all"]:
		await _series("Many instances of one 10 cm object", "instances", max_exp,
			func(n): return _many(n, false))
		await _series("Many unique 10 cm objects", "objects", max_exp,
			func(n): return _many(n, true))

	var path := ProjectSettings.globalize_path("res://docs/perf/stress-latest.md")
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("\n".join(_report) + "\n")
	f.close()
	print("\nReport written to %s" % path)
	get_tree().quit()


func _line(text: String) -> void:
	_report.append(text)
	print(text)


## Runs a scenario at 10^start .. 10^max_exp, stopping on budget.
func _series(title: String, unit: String, max_exp: int, make: Callable, start := 1) -> void:
	_line("")
	_line("## " + title)
	_line("")
	_line("| %s | generate ms | mesh + nodes ms | chunks | quads | nodes | regions | bodies | draw calls | frame ms (cpu / gpu) | fps | 1 edit ms | save ms / MB | load ms | +RAM MB | +VRAM MB |" % unit)
	_line("|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|")
	var prev := {}
	for e in range(start, max_exp + 1):
		var n := int(pow(10, e))
		if not prev.is_empty():
			var reason := _over_budget(prev)
			if reason != "":
				_line("| %s | skipped: %s |" % [_fmt_int(n), reason])
				break
		var r: Dictionary = await _measure(n, make)
		prev = r
		_line("| %s | %s | %s | %s | %s | %s | %s | %s | %s | %.1f / %s | %d | %s | %s / %.1f | %s | %d | %d |" % [
			_fmt_int(n), _fmt_ms(r.gen_ms), _fmt_ms(r.build_ms), _fmt_int(r.chunks), _fmt_int(r.quads), _fmt_int(r.nodes),
			_fmt_int(r.regions), _fmt_int(r.bodies), _fmt_int(r.draw_calls), r.cpu_ms, ("%.1f" % r.gpu_ms) if r.gpu_ms > 0.0 else "n/a", r.fps, _fmt_ms(r.edit_ms),
			_fmt_ms(r.save_ms), r.save_mb, _fmt_ms(r.load_ms), r.ram_mb, r.vram_mb])


func _over_budget(prev: Dictionary) -> String:
	var total: float = prev.gen_ms + prev.build_ms + prev.save_ms + prev.load_ms
	if total * 10.0 > MAX_BUILD_MS:
		return "next step projected at %ds" % int(total * 10.0 / 1000.0)
	if prev.quads * 10 > MAX_PROJECTED_QUADS:
		return "next step projected at %s quads" % _fmt_int(prev.quads * 10)
	if prev.ram_mb * 1_000_000.0 * 10.0 > MAX_PROJECTED_MEM:
		return "next step projected at %d GB RAM" % int(prev.ram_mb * 10 / 1000)
	if prev.fps < 10:
		return "fps already below 10"
	return ""


func _measure(n: int, make: Callable) -> Dictionary:
	# Release the previous scene before measuring memory for this one.
	view.set_project(Project.create_empty(0.01))
	view.flush()
	for i in 3:
		await get_tree().process_frame
	var base_ram := OS.get_static_memory_usage()
	var base_vram := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED)
	var t0 := Time.get_ticks_usec()
	var built: Dictionary = make.call(n)
	var p: Project = built.project
	var gen_ms := (Time.get_ticks_usec() - t0) / 1000.0
	t0 = Time.get_ticks_usec()
	view.set_project(p)
	view.set_edit_def(built.edit_def)
	view.flush()
	var build_ms := (Time.get_ticks_usec() - t0) / 1000.0

	var r := {"gen_ms": gen_ms, "build_ms": build_ms}
	var chunks := 0
	var quads := 0
	for def_id in view._meshes:
		for key in view._meshes[def_id]:
			chunks += 1
			var mesh: ArrayMesh = view._meshes[def_id][key].mesh
			quads += mesh.surface_get_array_index_len(0) / 6
	r.chunks = chunks
	r.quads = quads
	r.nodes = get_tree().get_node_count()
	r.regions = view.baked_region_count() if view.has_method("baked_region_count") else 0

	# Collision as if a player stood in the middle of the scene.
	var b: AABB = built.bounds
	view.set_focus(b.get_center(), 10.0)
	_frame(b)
	await get_tree().physics_frame
	await get_tree().physics_frame
	r.bodies = view.collision.active_count() if view.collision != null else -1
	for i in WARMUP_FRAMES:
		await get_tree().process_frame
	var vp := get_viewport().get_viewport_rid()
	var cpu := 0.0
	var gpu := 0.0
	var t1 := Time.get_ticks_usec()
	for i in MEASURE_FRAMES:
		await get_tree().process_frame
		cpu += RenderingServer.viewport_get_measured_render_time_cpu(vp)
		gpu += RenderingServer.viewport_get_measured_render_time_gpu(vp)
	var wall := (Time.get_ticks_usec() - t1) / 1000.0 / MEASURE_FRAMES
	r.cpu_ms = cpu / MEASURE_FRAMES
	r.gpu_ms = gpu / MEASURE_FRAMES
	r.fps = int(1000.0 / maxf(wall, 0.001))
	r.draw_calls = RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	# Memory this scene added on top of the empty scene.
	r.ram_mb = int((OS.get_static_memory_usage() - base_ram) / 1_000_000)
	r.vram_mb = int((RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED) - base_vram) / 1_000_000)

	# One 10 cm cut at the surface of the edited object, through to meshed.
	var edit_def: ObjectDef = p.defs[built.edit_def]
	var c: Vector3i = built.edit_at
	var t2 := Time.get_ticks_usec()
	p.edit_box(edit_def.id, c, c + Vector3i.ONE * 10, 0)
	view.flush()
	r.edit_ms = (Time.get_ticks_usec() - t2) / 1000.0

	var dir := ProjectSettings.globalize_path("user://stress/run.ourcraft")
	_remove_dir(dir)
	var t3 := Time.get_ticks_usec()
	p.save_dir(dir)
	r.save_ms = (Time.get_ticks_usec() - t3) / 1000.0
	r.save_mb = _dir_size(dir) / 1_000_000.0
	var t4 := Time.get_ticks_usec()
	Project.load_dir(dir)
	r.load_ms = (Time.get_ticks_usec() - t4) / 1000.0
	_remove_dir(dir)
	return r


## Points the camera at bounds (metres) so everything is in view.
func _frame(b: AABB) -> void:
	var center := b.get_center()
	var radius := maxf(b.size.length() * 0.5, 0.5)
	var dir := Vector3(0.6, 0.7, 1.0).normalized()
	cam.position = center + dir * radius * 1.9
	cam.look_at(center)


# --- Scenarios -------------------------------------------------------------

func _carved(cuts: int) -> Dictionary:
	var p := Project.create_empty(0.01)
	var block := p.create_def("Block", 1)
	block.grid.fill_box(Vector3i.ZERO, Vector3i(200, 200, 200), 1)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in cuts:
		var s: int = BRUSHES[rng.randi_range(0, BRUSHES.size() - 1)]
		var at := Vector3i(rng.randi_range(-s + 1, 199), rng.randi_range(-s + 1, 199), rng.randi_range(-s + 1, 199))
		# Mostly cuts; some paint so faces don't all merge into one colour.
		var value := 0 if rng.randf() < 0.75 else rng.randi_range(2, 9)
		block.grid.fill_box(at, at + Vector3i.ONE * s, value)
	p.root().children.append(Demo._inst(p, block.id, Vector3i(0, 0, 0), 0))
	return {"project": p, "bounds": AABB(Vector3.ZERO, Vector3.ONE * 2.0),
		"edit_def": block.id, "edit_at": Vector3i(95, 190, 95)}


func _noise(cells: int) -> Dictionary:
	var side := maxi(1, roundi(pow(cells, 1.0 / 3.0)))
	var p := Project.create_empty(0.01)
	var def := p.create_def("Noise", 1)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	# A few random chunk templates reused across chunks: meshing cost is the
	# same as fully unique noise, generation is much faster.
	var templates := []
	for t in 6:
		var data := PackedByteArray()
		data.resize(VoxelGrid.VOLUME)
		for i in VoxelGrid.VOLUME:
			if rng.randf() < 0.5:
				data[i] = rng.randi_range(1, 9)
		templates.append(data)
	var kmax := (side - 1) / VoxelGrid.SIZE
	var t := 0
	for kz in kmax + 1:
		for ky in kmax + 1:
			for kx in kmax + 1:
				def.grid.set_chunk(Vector3i(kx, ky, kz), templates[t % templates.size()].duplicate())
				t += 1
	# Trim to the requested side length.
	var big := (kmax + 1) * VoxelGrid.SIZE
	def.grid.fill_box(Vector3i(side, 0, 0), Vector3i(big, big, big), 0)
	def.grid.fill_box(Vector3i(0, side, 0), Vector3i(side, big, big), 0)
	def.grid.fill_box(Vector3i(0, 0, side), Vector3i(side, side, big), 0)
	p.root().children.append(Demo._inst(p, def.id, Vector3i.ZERO, 0))
	return {"project": p, "bounds": AABB(Vector3.ZERO, Vector3.ONE * side * 0.01),
		"edit_def": def.id, "edit_at": Vector3i(side / 2, maxi(side - 10, 0), side / 2)}


func _many(n: int, unique: bool) -> Dictionary:
	var p := Project.create_empty(0.01)
	var shared: ObjectDef = null
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var side := ceili(sqrt(n))
	var spacing := 20
	for i in n:
		var def := shared
		if def == null or unique:
			def = p.create_def("Crate %d" % i, 1)
			def.grid.fill_box(Vector3i.ZERO, Vector3i(10, 10, 10), rng.randi_range(1, 9))
			def.grid.fill_box(Vector3i(2, 10, 2), Vector3i(8, 11, 8), rng.randi_range(1, 9))
			if shared == null:
				shared = def
		var at := Vector3i((i % side) * spacing, 0, (i / side) * spacing)
		p.root().children.append(Demo._inst(p, def.id, at, 0))
	var extent := side * spacing * 0.01
	return {"project": p, "bounds": AABB(Vector3.ZERO, Vector3(extent, 0.11, extent)),
		"edit_def": shared.id, "edit_at": Vector3i(0, 0, 0)}


# --- Helpers ---------------------------------------------------------------

static func _dir_size(path: String) -> int:
	var total := 0
	var dir := DirAccess.open(path)
	if dir == null:
		return 0
	for f in dir.get_files():
		var fa := FileAccess.open(path.path_join(f), FileAccess.READ)
		if fa != null:
			total += fa.get_length()
	for d in dir.get_directories():
		total += _dir_size(path.path_join(d))
	return total


static func _remove_dir(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for d in dir.get_directories():
		_remove_dir(path.path_join(d))
	for f in dir.get_files():
		dir.remove(f)
	DirAccess.remove_absolute(path)


static func _fmt_int(v: int) -> String:
	var s := str(v)
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return s + out


static func _fmt_ms(v: float) -> String:
	if v >= 100.0:
		return _fmt_int(roundi(v))
	return "%.1f" % v
