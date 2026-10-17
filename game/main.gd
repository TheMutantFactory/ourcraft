extends Node3D
## Game controller: owns the project, the view, the player and the HUD, and
## turns input into edits.
##
## Key ideas:
## - edit_path is the object being edited ("entered"); blocks are placed into
##   and broken from that object only.
## - selected is an instance path below edit_path. Pressing Q on an object
##   selects the deepest object under the crosshair; pressing Q again walks
##   up the tree one level at a time.

const PROJECT_PATH := "user://projects/default.ourcraft"
const BRUSHES := [1, 2, 5, 10, 25, 50, 100] # in minimum blocks

var project: Project
var view: WorldView
var player: Player
var hud: Hud
var overlay: Overlay

var edit_path := PackedStringArray()
var selected = null # PackedStringArray or null
var isolated := false
var color := 1
var brush_idx := 3
var clipboard := ""
## Place/break flush against the aimed surface (true) or snap to the brush
## grid on all axes (false). T toggles.
var on_surface := true

var _aim := {}
var _grab := {}
var _outline_dirty := true


func _ready() -> void:
	_setup_window()
	_setup_input()
	_setup_environment()
	view = WorldView.new()
	add_child(view)
	overlay = Overlay.new()
	add_child(overlay)
	player = Player.new()
	add_child(player)
	hud = Hud.new()
	add_child(hud)
	_connect_hud()

	var loaded := Project.load_dir(ProjectSettings.globalize_path(PROJECT_PATH))
	if loaded != null:
		_use_project(loaded)
		hud.toast("Loaded %s" % loaded.title)
	else:
		_use_project(Demo.build(Settings.min_block_m()))
		hud.toast("Welcome! H shows the controls.", 8.0)
	_reset_player()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_run_debug_args()


## Development hook: `godot --path . -- --pose=x,y,z,yaw,pitch --q=2 --shot=out.png`
## positions the player, presses Q n times, saves a screenshot and quits.
func _run_debug_args() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else ""
	if args.is_empty():
		return
	if args.has("demo"):
		_use_project(Demo.build(Settings.min_block_m()))
	if args.has("coplanar"):
		# Three nested objects whose top faces share one plane.
		var p := Project.create_empty(0.01)
		var a := p.create_def("Red", 1)
		a.grid.fill_box(Vector3i(0, 0, 0), Vector3i(200, 1, 200), 5)
		var b := p.create_def("Blue", 1)
		b.grid.fill_box(Vector3i(0, 0, 0), Vector3i(120, 1, 120), 7)
		var c := p.create_def("Green", 1)
		c.grid.fill_box(Vector3i(0, 0, 0), Vector3i(50, 1, 50), 6)
		p.root().grid.fill_box(Vector3i(-100, 0, -100), Vector3i(100, 1, 100), 5)
		b.children.append(Demo._inst(p, c.id, Vector3i(35, 0, 35), 0))
		p.root().children.append(Demo._inst(p, b.id, Vector3i(-60, 0, -60), 0))
		_use_project(p)
	if args.has("nobias"):
		view.material.set_shader_parameter("bias_per_layer", 0.0)
	if args.has("pose"):
		var v := str(args.pose).split_floats(",")
		player.global_position = Vector3(v[0], v[1], v[2])
		player.rotation.y = deg_to_rad(v[3])
		player.look(Vector2(0, -deg_to_rad(v[4]) / player.mouse_sensitivity))
	if args.has("size"):
		player.set_size(float(args.size))
	if args.has("fly"):
		player.flying = true
	if args.has("shot"):
		for i in 10:
			await get_tree().physics_frame
		view.flush()
		for i in 5:
			await get_tree().physics_frame
		for i in int(args.get("q", "0")):
			_select(false)
		if args.has("edit"):
			_run_command("edit")
		if args.has("isolate"):
			_run_command("isolate")
		if args.has("help"):
			hud.toggle_help()
		if args.has("panel"):
			_toggle_panel(true)
		if args.has("grid"):
			on_surface = false
		if args.has("brush"):
			brush_idx = maxi(0, BRUSHES.find(int(args.brush)))
		if args.has("place"):
			_update_aim()
			var t0 := Time.get_ticks_msec()
			_place()
			while view.pending_chunks() > 0:
				await get_tree().process_frame
			print("place+mesh ms=%d" % (Time.get_ticks_msec() - t0))
		for i in int(args.get("wait", "20")):
			await get_tree().process_frame
		print("fps=%d chunks_pending=%d" % [Engine.get_frames_per_second(), view.pending_chunks()])
		get_viewport().get_texture().get_image().save_png(str(args.shot))
		get_tree().quit()


## Sizes the window to most of the screen and applies the interface scale.
func _setup_window() -> void:
	var win := get_window()
	if DisplayServer.get_name() != "headless" and win.mode == Window.MODE_WINDOWED:
		var usable := DisplayServer.screen_get_usable_rect(win.current_screen)
		win.size = Vector2i(Vector2(usable.size) * 0.9)
		win.position = usable.position + (usable.size - win.size) / 2
	win.content_scale_factor = Settings.ui_scale()


func set_ui_scale(value: float) -> void:
	value = clampf(snappedf(value, 0.25), 1.0, 8.0)
	get_window().content_scale_factor = value
	Settings.set_ui_scale(value)
	hud.set_ui_scale_value(value)
	hud.toast("Text size %s×" % Hud._fmt(value))


func _setup_input() -> void:
	var keys := {
		"move_forward": KEY_W, "move_back": KEY_S, "move_left": KEY_A, "move_right": KEY_D,
		"jump": KEY_SPACE, "descend": KEY_SHIFT,
	}
	for action in keys:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
			var ev := InputEventKey.new()
			ev.physical_keycode = keys[action]
			InputMap.action_add_event(action, ev)


func _setup_environment() -> void:
	var env := Environment.new()
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color("#3f7fd0")
	sky_mat.sky_horizon_color = Color("#bcd6ee")
	sky_mat.ground_horizon_color = Color("#bcd6ee")
	sky_mat.ground_bottom_color = Color("#5a6b52")
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 1.0
	env.ambient_light_color = Color("#e6dfd2")
	env.ambient_light_sky_contribution = 0.45
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.ssao_enabled = true
	env.ssao_radius = 0.6
	env.ssao_intensity = 1.6
	env.fog_enabled = true
	env.fog_light_color = Color("#bcd6ee")
	env.fog_density = 0.004
	env.fog_sky_affect = 0.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -35, 0)
	sun.light_energy = 1.25
	sun.light_color = Color("#fff4e0")
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 60.0
	sun.shadow_bias = 0.02
	add_child(sun)

	var ground := StaticBody3D.new()
	ground.set_meta("ground", true)
	var gmesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(400, 400)
	gmesh.mesh = plane
	var gmat := ShaderMaterial.new()
	gmat.shader = load("res://render/ground.gdshader")
	gmesh.material_override = gmat
	ground.add_child(gmesh)
	var gshape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(400, 2, 400)
	gshape.shape = box
	gshape.position.y = -1
	ground.add_child(gshape)
	add_child(ground)


func _connect_hud() -> void:
	hud.command.connect(_run_command)
	hud.outline_selected.connect(func(path):
		selected = null if path.is_empty() else path
		if selected != null and not Hud._is_prefix(edit_path, selected):
			edit_path = selected.slice(0, selected.size() - 1)
			_after_context_change()
		_outline_dirty = true)
	hud.outline_activated.connect(func(path):
		edit_path = path
		selected = null
		_after_context_change())
	hud.place_object.connect(_place_from_library)
	hud.rename_object.connect(func(id, n): project.rename_def(id, n))
	hud.delete_object.connect(_delete_def)
	hud.export_object.connect(func(id, path):
		var err := project.export_object(id, path)
		hud.toast("Exported to %s" % path if err == OK else "Export failed (%s)" % error_string(err)))
	hud.import_object.connect(func(path):
		var id := project.import_bundle(path)
		if id == "":
			hud.toast("Not an Ourcraft object file")
		else:
			hud.toast("Imported %s — pick it in the library and press Place" % project.defs[id].name))
	hud.min_block_changed.connect(func(cm):
		project.voxel_size = cm / 100.0
		Settings.set_min_block_m(project.voxel_size)
		view.remesh_all()
		_refresh_hud_static())
	hud.ui_scale_changed.connect(set_ui_scale)
	hud.set_ui_scale_value(get_window().content_scale_factor)
	hud.object_unit_changed.connect(func(u):
		project.set_def_unit(_edit_def().id, u)
		_refresh_hud_static())


func _use_project(p: Project) -> void:
	if project != null:
		project.structure_changed.disconnect(_mark_outline)
		project.library_changed.disconnect(_mark_outline)
	project = p
	project.structure_changed.connect(_mark_outline)
	project.library_changed.connect(_mark_outline)
	edit_path = PackedStringArray()
	selected = null
	isolated = false
	_grab = {}
	view.set_project(project)
	view.set_isolation(null)
	_refresh_hud_static()


func _mark_outline() -> void:
	_outline_dirty = true


func _reset_player() -> void:
	player.global_position = Vector3(-2, 0.2, 3.0)
	player.rotation = Vector3.ZERO
	player.velocity = Vector3.ZERO


# --- Helpers ---------------------------------------------------------------

func _edit_def() -> ObjectDef:
	return project.def_at(edit_path)


func _brush_cells(def: ObjectDef) -> int:
	return maxi(1, roundi(float(BRUSHES[brush_idx]) / def.unit))


## World transform of an object's local min units (for drawing boxes).
func _world_xform(path: PackedStringArray) -> Transform3D:
	return Transform3D(Basis.from_scale(Vector3.ONE * project.voxel_size), Vector3.ZERO) * project.path_transform(path)


## Converts a world point to a cell in the object at path.
func _cell_at(path: PackedStringArray, def: ObjectDef, world: Vector3) -> Vector3i:
	var local := _world_xform(path).affine_inverse() * world
	return Vector3i((local / def.unit).floor())


func _floor_div(a: Vector3i, b: int) -> Vector3i:
	return Vector3i(floori(float(a.x) / b), floori(float(a.y) / b), floori(float(a.z) / b))


func _cm(min_units: float) -> String:
	return Hud._fmt(min_units * project.voxel_size * 100.0) + " cm"


# --- Per-frame -------------------------------------------------------------

func _physics_process(_delta: float) -> void:
	_update_aim()
	if not _grab.is_empty():
		_update_grab()


func _process(_delta: float) -> void:
	if not project.is_valid_path(edit_path):
		edit_path = PackedStringArray()
		_after_context_change()
	if selected != null and not project.is_valid_path(selected):
		selected = null
	if _outline_dirty and hud.panel_open():
		hud.refresh_outline(project, edit_path, selected)
		hud.refresh_library(project)
		_outline_dirty = false
	_draw_overlay()
	_refresh_hud_dynamic()


func _update_aim() -> void:
	_aim = {}
	var cam := player.camera
	var from := cam.global_position
	var to := from - cam.global_transform.basis.z * player.reach()
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.exclude = [player.get_rid()] + (_grab.get("exclude", []) as Array)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return
	var body: Object = hit.collider
	_aim = {
		"pos": hit.position,
		"normal": hit.normal,
		"path": body.get_meta("path") if body.has_meta("path") else null,
		"def_id": body.get_meta("def_id") if body.has_meta("def_id") else "",
	}


func _eps() -> float:
	return project.voxel_size * 0.1


## Brush box (cell min, cell max) in the edited object for placing or
## breaking, or [] if there is no valid target.
func _brush_target(place: bool) -> Array:
	if _aim.is_empty():
		return []
	var def := _edit_def()
	if not place and _aim.path != edit_path:
		return []
	var p: Vector3 = _aim.pos + _aim.normal * (_eps() if place else -_eps())
	var b := _brush_cells(def)
	var hit := _cell_at(edit_path, def, p)
	var lo := _floor_div(hit, b) * b
	if on_surface:
		# Along the surface normal, sit flush against the surface instead of
		# snapping to the brush grid; across it, keep the grid so rows line up.
		var n := _world_xform(edit_path).basis.inverse() * Vector3(_aim.normal)
		var axis := n.abs().max_axis_index()
		var outward := n[axis] > 0.0
		if place == outward:
			lo[axis] = hit[axis]
		else:
			lo[axis] = hit[axis] - b + 1
	return [lo, lo + Vector3i.ONE * b]


func _draw_overlay() -> void:
	overlay.clear()
	var def := _edit_def()
	var xf := _world_xform(edit_path)
	var unit_xf := xf * Transform3D(Basis.from_scale(Vector3.ONE * def.unit), Vector3.ZERO)
	if not edit_path.is_empty():
		var eb := project.def_bounds(def.id)
		if eb.size == Vector3.ZERO:
			eb = AABB(Vector3.ZERO, Vector3.ONE * def.unit * 4)
		overlay.box(xf, eb, Color(0.5, 0.85, 1.0, 0.55), def.unit * 0.5)
	if _grab.is_empty() and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var t := _brush_target(true)
		if not t.is_empty():
			overlay.box(unit_xf, AABB(Vector3(t[0]), Vector3(t[1] - t[0])), Color(1, 1, 1, 0.7))
	if selected != null:
		var sdef := project.def_at(selected)
		if sdef != null:
			var sb := project.def_bounds(sdef.id)
			if sb.size == Vector3.ZERO:
				sb = AABB(Vector3.ZERO, Vector3.ONE * sdef.unit * 4)
			var sx := _world_xform(selected)
			overlay.box(sx, sb, Color("#ffd75e"), sdef.unit * 0.3)
			overlay.fill(sx, sb.grow(sdef.unit * 0.3), Color(1.0, 0.84, 0.37, 0.12))
	overlay.commit()


func _refresh_hud_static() -> void:
	hud.set_palette(project.palette, color)
	hud.set_settings(project.voxel_size * 100.0, _edit_def().unit)
	_outline_dirty = true


func _refresh_hud_dynamic() -> void:
	var def := _edit_def()
	var ctx := "Editing  " + project.path_label(edit_path)
	if isolated:
		ctx += "   [isolated]"
	hud.context_label.text = ctx
	if not _grab.is_empty():
		hud.selection_label.text = "Moving %s · click drop · R rotate · Esc cancel" % project.def_at(_grab.path).name
	elif selected != null and project.is_valid_path(selected):
		var depth: int = selected.size() - edit_path.size()
		hud.selection_label.text = "Selected  %s%s  ·  Q up · Enter edit" % [
			project.def_at(selected).name, "  ↑%d" % (depth - 1) if depth > 1 else ""]
	else:
		hud.selection_label.text = ""
	var want: int = BRUSHES[brush_idx]
	var got := _brush_cells(def) * def.unit
	var txt := "Brush %s" % _cm(got)
	if got != want:
		txt += " (object grid; N for finer)"
	txt += "  ·  on surface" if on_surface else "  ·  grid"
	txt += "   ·   You: %sx%s" % [Hud._fmt(player.size), "   ·   flying" if player.flying else ""]
	hud.brush_label.text = txt
	var pending := view.pending_chunks()
	hud.status_label.text = ("Meshing %d chunks…" % pending) if pending > 0 else "%d fps\nH: controls" % Engine.get_frames_per_second()


# --- Input -----------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if event is InputEventMouseMotion and captured:
		player.look(event.relative)
		return
	if event is InputEventMouseButton and event.pressed:
		if not captured:
			if not hud.panel_open():
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			return
		_on_click(event)
		return
	if event is InputEventKey and event.pressed and not event.echo:
		_on_key(event)


func _on_click(event: InputEventMouseButton) -> void:
	if not _grab.is_empty():
		if event.button_index == MOUSE_BUTTON_LEFT:
			_end_grab(true)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_end_grab(false)
		return
	match event.button_index:
		MOUSE_BUTTON_LEFT:
			_break()
		MOUSE_BUTTON_RIGHT:
			_place()
		MOUSE_BUTTON_MIDDLE:
			_pick_color()
		MOUSE_BUTTON_WHEEL_UP:
			brush_idx = mini(brush_idx + 1, BRUSHES.size() - 1)
		MOUSE_BUTTON_WHEEL_DOWN:
			brush_idx = maxi(brush_idx - 1, 0)


func _on_key(event: InputEventKey) -> void:
	var ctrl := event.ctrl_pressed or event.meta_pressed
	var k := event.keycode
	if ctrl:
		match k:
			KEY_Z: _run_command("redo" if event.shift_pressed else "undo")
			KEY_Y: _run_command("redo")
			KEY_C: _run_command("copy")
			KEY_V: _run_command("paste")
			KEY_D: _run_command("duplicate")
			KEY_S: _run_command("save")
			KEY_O: _run_command("load")
			KEY_EQUAL, KEY_PLUS, KEY_KP_ADD: set_ui_scale(get_window().content_scale_factor + 0.5)
			KEY_MINUS, KEY_KP_SUBTRACT: set_ui_scale(get_window().content_scale_factor - 0.5)
			KEY_0: set_ui_scale(2.0 * DisplayServer.screen_get_scale())
		return
	if k >= KEY_0 and k <= KEY_9:
		var n := 10 if k == KEY_0 else k - KEY_0
		if n <= project.palette.size():
			color = n
			hud.set_palette(project.palette, color)
		return
	match k:
		KEY_ESCAPE:
			if not _grab.is_empty():
				_end_grab(false)
			else:
				_toggle_panel(false)
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		KEY_TAB: _toggle_panel(not hud.panel_open())
		KEY_H: hud.toggle_help()
		KEY_F:
			player.flying = not player.flying
			player.velocity = Vector3.ZERO
		KEY_COMMA: _resize_player(-1)
		KEY_PERIOD: _resize_player(1)
		KEY_MINUS: brush_idx = maxi(brush_idx - 1, 0)
		KEY_EQUAL: brush_idx = mini(brush_idx + 1, BRUSHES.size() - 1)
		KEY_Q: _select(event.shift_pressed)
		KEY_ENTER, KEY_KP_ENTER: _run_command("edit")
		KEY_BACKSPACE: _run_command("leave")
		KEY_I: _run_command("isolate")
		KEY_N: _new_object()
		KEY_G: _run_command("grab")
		KEY_R:
			if not _grab.is_empty():
				var gi: ObjectInstance = _grab.inst
				project.set_instance_transform(_grab.parent.id, gi.id, gi.offset, gi.rot + 1, false)
				view.refresh_instance(gi)
			else:
				_run_command("rotate")
		KEY_DELETE, KEY_X: _run_command("delete")
		KEY_U: _run_command("unique")
		KEY_T:
			on_surface = not on_surface
			hud.toast("Placing on the surface" if on_surface else "Placing on the brush grid")


func _toggle_panel(on: bool) -> void:
	hud.show_panel(on)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if on else Input.MOUSE_MODE_CAPTURED
	_outline_dirty = true


func _resize_player(dir: int) -> void:
	var i := Player.SCALES.find(player.size)
	i = clampi(i + dir, 0, Player.SCALES.size() - 1)
	player.set_size(Player.SCALES[i])
	hud.toast("You are now %s tall" % Hud._fmt(Player.HEIGHT * player.size * 100.0) + " cm")


# --- Block editing ---------------------------------------------------------

func _break() -> void:
	if _aim.is_empty():
		return
	if _aim.path == null:
		return
	if _aim.path != edit_path:
		var inside := Hud._is_prefix(edit_path, _aim.path)
		if inside:
			var owner_path: PackedStringArray = _aim.path.slice(0, edit_path.size() + 1)
			hud.toast("That block belongs to %s. Q to select it, Enter to edit it." % project.def_at(owner_path).name)
		else:
			hud.toast("That's outside %s. Backspace to go up a level." % _edit_def().name)
		return
	var t := _brush_target(false)
	project.edit_box(_edit_def().id, t[0], t[1], 0)


func _place() -> void:
	var t := _brush_target(true)
	if t.is_empty():
		return
	project.edit_box(_edit_def().id, t[0], t[1], color)


func _pick_color() -> void:
	if _aim.is_empty() or _aim.path == null:
		return
	var def: ObjectDef = project.defs.get(_aim.def_id)
	if def == null:
		return
	var v := def.grid.get_cell(_cell_at(_aim.path, def, _aim.pos - _aim.normal * _eps()))
	if v > 0:
		color = v
		hud.set_palette(project.palette, color)


# --- Objects ---------------------------------------------------------------

func _select(down: bool) -> void:
	if _aim.is_empty() or _aim.path == null or not Hud._is_prefix(edit_path, _aim.path) or _aim.path == edit_path:
		if not _aim.is_empty() and _aim.path != null and not Hud._is_prefix(edit_path, _aim.path):
			hud.toast("That's outside %s. Backspace to go up a level." % _edit_def().name)
		selected = null
		_outline_dirty = true
		return
	var leaf: PackedStringArray = _aim.path
	if selected != null and Hud._is_prefix(selected, leaf):
		if down:
			if selected.size() < leaf.size():
				selected = leaf.slice(0, selected.size() + 1)
		elif selected.size() > edit_path.size() + 1:
			selected = selected.slice(0, selected.size() - 1)
		else:
			selected = leaf
	else:
		selected = leaf
	hud.toast(project.path_label(selected), 2.5)
	_outline_dirty = true


func _after_context_change() -> void:
	if isolated:
		view.set_isolation(edit_path)
	_refresh_hud_static()


func _run_command(cmd: String) -> void:
	match cmd:
		"undo", "redo":
			if not _grab.is_empty():
				return
			var label := project.undo() if cmd == "undo" else project.redo()
			hud.toast(("Undid " if cmd == "undo" else "Redid ") + label if label != "" else "Nothing to " + cmd)
		"edit":
			if selected != null:
				edit_path = selected
				selected = null
				_after_context_change()
				hud.toast("Editing %s. Blocks you place go into it. Backspace to leave." % _edit_def().name)
		"leave":
			if not edit_path.is_empty():
				selected = edit_path
				edit_path = edit_path.slice(0, edit_path.size() - 1)
				_after_context_change()
		"isolate":
			isolated = not isolated
			view.set_isolation(edit_path if isolated else null)
			if isolated and not player.flying:
				player.flying = true
				player.velocity = Vector3.ZERO
		"grab":
			if selected != null:
				_start_grab(selected, false)
		"rotate":
			_rotate_selected()
		"delete":
			if selected != null:
				var nm := project.def_at(selected).name
				project.remove_instance(project.def_at(selected.slice(0, selected.size() - 1)).id, selected[-1])
				selected = null
				hud.toast("Deleted %s (Ctrl+Z to undo)" % nm)
		"unique":
			if selected != null:
				var parent := project.def_at(selected.slice(0, selected.size() - 1))
				var fork := project.fork_def(project.def_at(selected).id)
				project.set_instance_def(parent.id, selected[-1], fork.id)
				hud.toast("This copy is now its own object: %s" % fork.name)
		"copy":
			if selected != null:
				clipboard = project.def_at(selected).id
				hud.toast("Copied %s. Ctrl+V places another instance of it." % project.defs[clipboard].name)
		"paste":
			if project.defs.has(clipboard):
				_place_from_library(clipboard)
		"duplicate":
			if selected != null:
				clipboard = project.def_at(selected).id
				_place_from_library(clipboard)
		"save":
			var err := project.save_dir(ProjectSettings.globalize_path(PROJECT_PATH))
			hud.toast("Saved" if err == OK else "Save failed: %s" % error_string(err))
		"load":
			var p := Project.load_dir(ProjectSettings.globalize_path(PROJECT_PATH))
			if p == null:
				hud.toast("No saved world yet (Ctrl+S to save)")
			else:
				_use_project(p)
				hud.toast("Reloaded the saved world")
		"new_world":
			_use_project(Project.create_empty(project.voxel_size))
			_reset_player()
			hud.toast("Empty world. Right click to place blocks.")
		"demo":
			_use_project(Demo.build(project.voxel_size))
			_reset_player()


func _new_object() -> void:
	var parent := _edit_def()
	var want: int = BRUSHES[brush_idx]
	var t := _brush_target(true)
	var offset := Vector3i.ZERO
	if not t.is_empty():
		offset = t[0] * parent.unit
	else:
		var p := player.global_position - player.global_transform.basis.z * 1.5
		offset = Vector3i((_world_xform(edit_path).affine_inverse() * p).floor())
	var def := project.create_def(project.unique_name("Object"), want)
	var inst := project.add_instance(parent.id, def.id, offset, 0)
	edit_path.append(inst.id)
	selected = null
	_after_context_change()
	hud.toast("Created %s with %s blocks — you're editing it now. Backspace when done." % [def.name, _cm(want)], 5.0)


func _place_from_library(def_id: String) -> void:
	var parent := _edit_def()
	if project.would_cycle(parent.id, def_id):
		hud.toast("Can't put %s inside itself" % project.defs[def_id].name)
		return
	project.begin_step("Place object")
	var inst := project.add_instance(parent.id, def_id, Vector3i.ZERO, 0)
	var path := edit_path.duplicate()
	path.append(inst.id)
	view.rebuild_tree()
	_start_grab(path, true)
	if hud.panel_open():
		_toggle_panel(false)


func _rotate_selected() -> void:
	if selected == null:
		return
	var inst := project.instance_at(selected)
	var parent := project.def_at(selected.slice(0, selected.size() - 1))
	var c := project.def_bounds(inst.def_id).get_center()
	var before := inst.local_transform() * c
	var rot := posmod(inst.rot + 1, 4)
	var after := ObjectInstance.basis_for(rot) * c
	project.set_instance_transform(parent.id, inst.id, Vector3i((before - after).round()), rot)


# --- Moving objects --------------------------------------------------------

func _start_grab(path: PackedStringArray, is_new: bool) -> void:
	var inst := project.instance_at(path)
	if inst == null:
		return
	if not is_new:
		project.begin_step("Move object")
	_grab = {
		"path": path,
		"inst": inst,
		"parent": project.def_at(path.slice(0, path.size() - 1)),
		"start_offset": inst.offset,
		"start_rot": inst.rot,
		"exclude": view.bodies_of(inst.id),
		"is_new": is_new,
	}
	selected = path
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _update_grab() -> void:
	if _aim.is_empty():
		return
	var inst: ObjectInstance = _grab.inst
	var parent: ObjectDef = _grab.parent
	var parent_path: PackedStringArray = _grab.path.slice(0, _grab.path.size() - 1)
	var snap: int = BRUSHES[brush_idx]
	var local: Vector3 = _world_xform(parent_path).affine_inverse() * (_aim.pos + _aim.normal * _eps())
	var b: AABB = Transform3D(ObjectInstance.basis_for(inst.rot), Vector3.ZERO) * project.def_bounds(inst.def_id)
	var target := Vector3(local.x - b.get_center().x, local.y - b.position.y, local.z - b.get_center().z)
	var offset := Vector3i(target.round())
	offset = Vector3i(roundi(float(offset.x) / snap) * snap, offset.y, roundi(float(offset.z) / snap) * snap)
	if offset != inst.offset or _grab.get("shown_rot", -1) != inst.rot:
		project.set_instance_transform(parent.id, inst.id, offset, inst.rot, false)
		view.refresh_instance(inst)
		_grab.shown_rot = inst.rot
	_grab.exclude = view.bodies_of(inst.id)


func _end_grab(commit: bool) -> void:
	var g := _grab
	_grab = {}
	if commit:
		project.end_step()
	else:
		project.cancel_step()
		if g.is_new:
			selected = null
	project.structure_changed.emit()
	_outline_dirty = true


func _delete_def(def_id: String) -> void:
	if def_id == project.root_id:
		hud.toast("The world itself can't be deleted")
		return
	var nm: String = project.defs[def_id].name
	var uses := project.usage_count(def_id)
	project.delete_def(def_id)
	selected = null
	hud.toast("Deleted %s and its %d instance(s). Undo history was cleared." % [nm, uses])
