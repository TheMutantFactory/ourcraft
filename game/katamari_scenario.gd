class_name KatamariScenario
extends Scenario
## A Katamari Damacy-style demo: roll a ball over a field of objects, picking
## up anything no bigger than the ball's radius; it grows with every pickup,
## so it can soon pick up bigger things.
##
##   tools/katamari.sh            WASD roll · mouse turns · P autopilot
##   tools/katamari.sh --soak=60  autopilot for 60 s, check, report, quit
##
## Objects come in size classes, each made of blocks of one size and one
## colour (1 cm blocks red, 2 cm orange, ... 2.5 m grey): every object is
## the same three-block staircase, so a class's size is 3 blocks. Each class
## is one object instanced hundreds of times, so it's drawn live (instanced).
##
## The ball is the only thing that collides: no physics bodies are made for
## the objects. The scenario keeps its own grid of object bounds; objects
## too big to pick up push the ball back.
##
## A picked-up object stops being a game object: it's hidden at once,
## removed from the project in batches (one view rebuild per batch), and
## carried as an instance in a MultiMesh on the ball (one per class, so a
## piece costs a transform). Once the ball has grown past a piece, burying
## it, the piece is retired; a class's MultiMesh is freed when its last
## piece goes.

## [block unit (cm), copies, spread radius (m), colour]
const CLASSES := [
	[1, 1200, 5.0, "#ff4d4d"],
	[2, 900, 10.0, "#ff9f1c"],
	[5, 700, 20.0, "#ffd60a"],
	[10, 500, 40.0, "#7bd389"],
	[25, 350, 80.0, "#2ec4b6"],
	[50, 250, 160.0, "#3a86ff"],
	[100, 150, 320.0, "#8338ec"],
	[250, 100, 640.0, "#c8c8d0"],
]
## Every object is this many blocks across.
const BLOCKS := 3
const START_RADIUS := 0.05
## Pick up objects whose longest side is at most this × the ball's radius.
const PICK := 1.0
## Volume added to the ball per volume picked up (more than 1 keeps it brisk).
const GROWTH := 2.0
## Grid cell for finding objects near the ball (metres).
const HASH := 4.0
## Seconds between batches of project removals.
const FLUSH_EVERY := 1.0

var autopilot := false
var ball_pos := Vector3.ZERO
var ball_vel := Vector3.ZERO
var radius := START_RADIUS
## Per object: {id, cls, aabb, size, volume, xform, alive}
var _items: Array = []
var _hash := {}
var _class_defs: Array = []
var _class_colour: Array = []
var _class_mesh: Array = []
## Per class: objects not picked up yet.
var _left: Array = []
## Per class: Array of {xform (ball-local), dist, half}
var _pieces: Array = []
var _piece_nodes: Array = []
var _pieces_dirty := {}
var _pending: Array = []
var _flush_timer := 0.0
var _ball: Node3D
var _core: MeshInstance3D
var _target := -1
var _retarget := 0.0
var _stuck_check := 0.0
var _stuck_from := Vector3.ZERO
var _detour := 0.0
var _detour_dir := Vector3.ZERO
var _poke_timer := 5.0
## Objects the project had before the field was added.
var _base_children := 0


func _init(seed := 1) -> void:
	super(seed)
	name = "Katamari"
	world_collision = false
	stats = {"picked": 0, "retired": 0, "carried": 0, "diameter cm": 0.0}


func _setup() -> void:
	if _ball != null:
		_ball.queue_free()
		_ball = null
	# Always a fresh field: start over on an empty world if given anything
	# else (your own world, or a saved scratch). Switching projects comes
	# back here.
	if not project.root().children.is_empty() or project.defs.size() > 1:
		main._use_project(Project.create_empty(project.voxel_size))
		return
	_items.clear()
	_hash.clear()
	_class_defs.clear()
	_class_colour.clear()
	_class_mesh.clear()
	_left.clear()
	_pieces.clear()
	_piece_nodes.clear()
	_pieces_dirty.clear()
	_pending.clear()
	radius = START_RADIUS
	ball_pos = Vector3(0, radius, 0)
	ball_vel = Vector3.ZERO
	for a in OS.get_cmdline_user_args():
		if a == "--auto":
			autopilot = true
	# Ctrl+S saves here, not over your own world.
	main.project_path = "user://projects/katamari-scratch.ourcraft"
	project.environment = {"ground_size": 1600, "far": 3000, "fog_density": 0.0012,
		"ground_color": "#a9d18e", "ground_line_color": "#98c27d"}
	main.apply_environment()
	_build_world()
	_build_ball()
	var player: Player = main.player
	player.driven = true
	player.avatar = false
	player.set_third_person(true)
	# About five ball radii behind and two above (player size is radius / 0.3).
	player.follow = 1.5
	player.follow_up = 0.6
	player.set_pitch(deg_to_rad(-14))
	_follow_camera()


func _build_world() -> void:
	_base_children = project.root().children.size()
	var s := 1.0 / project.voxel_size
	for c in CLASSES.size():
		var unit: int = CLASSES[c][0]
		project.palette.append(Color(CLASSES[c][3]))
		var colour := project.palette.size()
		_class_colour.append(colour)
		var def := project.create_def("%s blocks" % Hud._fmt(unit) + " cm", unit)
		# A staircase: 3×3, then 2×3, then 1×3 blocks.
		for y in BLOCKS:
			def.grid.fill_box(Vector3i(0, y, 0), Vector3i(BLOCKS - y, y + 1, BLOCKS), colour)
		_class_defs.append(def)
		_class_mesh.append(null)
		_pieces.append([])
		_piece_nodes.append(null)
		var size_m := BLOCKS * unit * project.voxel_size
		var volume := 18.0 * pow(unit * project.voxel_size, 3.0) # 9 + 6 + 3 blocks
		var spread: float = CLASSES[c][2]
		_left.append(CLASSES[c][1])
		for n in CLASSES[c][1]:
			var at := Vector3.ZERO
			while at.length() < size_m + 0.3:
				var a := rng.randf() * TAU
				var r := spread * sqrt(rng.randf())
				at = Vector3(cos(a) * r, 0, sin(a) * r)
			var rot := rng.randi_range(0, 3)
			var inst := project.add_instance(project.root_id, def.id, Vector3i((at * s).round()), rot)
			var xform := Transform3D(ObjectInstance.basis_for(rot), Vector3(inst.offset) * project.voxel_size)
			var aabb := xform * AABB(Vector3.ZERO, Vector3.ONE * size_m)
			_items.append({"id": inst.id, "cls": c, "aabb": aabb, "size": size_m, "volume": volume,
				"xform": xform, "alive": true})
			_insert(_items.size() - 1)


func _insert(i: int) -> void:
	var b: AABB = _items[i].aabb
	for x in range(floori(b.position.x / HASH), floori(b.end.x / HASH) + 1):
		for z in range(floori(b.position.z / HASH), floori(b.end.z / HASH) + 1):
			_hash.get_or_add(Vector2i(x, z), []).append(i)


func _build_ball() -> void:
	_ball = Node3D.new()
	_ball.name = "Ball"
	main.add_child(_ball)
	_core = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	var mat := StandardMaterial3D.new()
	# Stripes, so you can see it roll.
	var img := Image.create(8, 4, false, Image.FORMAT_RGB8)
	for x in 8:
		for y in 4:
			img.set_pixel(x, y, Color("#ff6fb5") if (x + y) % 2 == 0 else Color("#fff1f8"))
	mat.albedo_texture = ImageTexture.create_from_image(img)
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sphere.material = mat
	_core.mesh = sphere
	_ball.add_child(_core)
	_place_ball()


func _place_ball() -> void:
	_ball.position = ball_pos
	_core.scale = Vector3.ONE * radius


func _follow_camera() -> void:
	var player: Player = main.player
	player.set_size(radius / 0.3)
	player.global_position = ball_pos - Vector3(0, Player.EYE * player.size, 0)


## Biggest object the ball can pick up right now (metres).
func reach() -> float:
	return radius * PICK


func _tick(dt: float) -> void:
	if _ball == null:
		return
	var dir := _steer(dt)
	var vmax := 1.5 * pow(radius / START_RADIUS, 0.55)
	ball_vel = ball_vel.move_toward(dir * vmax, 3.0 * vmax * dt)
	var step := ball_vel * dt
	ball_pos += step
	_collide()
	ball_pos.y = radius
	if step.length() > 0.0:
		var axis := Vector3.UP.cross(step).normalized()
		if axis != Vector3.ZERO:
			_ball.basis = (Basis(axis, step.length() / radius) * _ball.basis).orthonormalized()
	_retire()
	_refresh_pieces()
	_place_ball()
	_follow_camera()
	_flush_timer -= dt
	if _flush_timer <= 0.0:
		_flush_timer = FLUSH_EVERY
		flush()
	stats["diameter cm"] = snappedf(radius * 200.0, 0.1)


## Movement direction: keys relative to the camera, or the autopilot.
func _steer(dt: float) -> Vector3:
	if not autopilot:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			return Vector3.ZERO
		var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		return (Basis(Vector3.UP, main.player.view_yaw()) * Vector3(input.x, 0, input.y)).limit_length(1.0)
	_retarget -= dt
	if _retarget <= 0.0 or _target < 0 or not _items[_target].alive:
		_retarget = 0.3
		_target = _nearest_pickable()
	# If the ball hasn't got anywhere for a while, it's probably pushing on
	# something too big: go sideways for a moment.
	_stuck_check -= dt
	if _stuck_check <= 0.0:
		_stuck_check = 1.5
		if ball_pos.distance_to(_stuck_from) < radius * 0.5 and _target >= 0:
			_detour = 1.2
			_detour_dir = Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized()
		_stuck_from = ball_pos
	if _detour > 0.0:
		_detour -= dt
		return _detour_dir
	if _target < 0:
		return Vector3.ZERO
	var to: Vector3 = _items[_target].aabb.get_center() - ball_pos
	to.y = 0
	return to.normalized()


## The pickable object most worth rolling to: the most volume per metre of
## travel, so a big ball doesn't chase crumbs.
func _nearest_pickable() -> int:
	var best := -1
	var best_score := 0.0
	for i in _items.size():
		var it: Dictionary = _items[i]
		if it.alive and it.size <= reach():
			var score: float = it.volume / (ball_pos.distance_to(it.aabb.get_center()) + radius)
			if score > best_score:
				best_score = score
				best = i
	return best


## Picks up what the ball touches and is pushed back by what's too big.
func _collide() -> void:
	var lo := Vector2i(floori((ball_pos.x - radius) / HASH), floori((ball_pos.z - radius) / HASH))
	var hi := Vector2i(floori((ball_pos.x + radius) / HASH), floori((ball_pos.z + radius) / HASH))
	var seen := {}
	for x in range(lo.x, hi.x + 1):
		for z in range(lo.y, hi.y + 1):
			for i in _hash.get(Vector2i(x, z), []):
				if seen.has(i) or not _items[i].alive:
					continue
				seen[i] = true
				var it: Dictionary = _items[i]
				var b: AABB = it.aabb
				var q := ball_pos.clamp(b.position, b.end)
				var d := ball_pos - q
				if d.length() >= radius:
					continue
				if it.size <= reach():
					_pick(i)
					continue
				d.y = 0.0
				if d.length() < 0.0001:
					d = ball_pos - b.get_center()
					d.y = 0.0
				var n := d.normalized()
				ball_pos += n * maxf(0.0, radius - d.length())
				var vn := ball_vel.dot(n)
				if vn < 0.0:
					ball_vel -= n * vn * 1.4


func _pick(i: int) -> void:
	var it: Dictionary = _items[i]
	it.alive = false
	_left[it.cls] -= 1
	view.hide_instances([it.id])
	_pending.append(it.id)
	# Stick it on the ball: its centre goes on the surface where it touched,
	# keeping its orientation, then into the ball's own (rolling) frame.
	var t: Transform3D = it.xform
	var centre: Vector3 = it.aabb.get_center()
	var out := centre - ball_pos
	out = out.normalized() if out.length() > 0.0001 else Vector3.UP
	t.origin += ball_pos + out * radius - centre
	_pieces[it.cls].append({"xform": _ball.global_transform.affine_inverse() * t,
		"dist": radius, "half": it.size * 0.5})
	_pieces_dirty[it.cls] = true
	radius = pow(pow(radius, 3.0) + GROWTH * 3.0 * it.volume / (4.0 * PI), 1.0 / 3.0)
	stats.picked += 1


## Retires pieces the ball has grown over: a piece is buried once the ball's
## radius passes the farthest corner it could have (centre + half × √3).
func _retire() -> void:
	for c in _pieces.size():
		var list: Array = _pieces[c]
		if list.is_empty():
			continue
		var kept := list.filter(func(p): return p.dist + p.half * 1.732 > radius)
		if kept.size() != list.size():
			stats.retired += list.size() - kept.size()
			_pieces[c] = kept
			_pieces_dirty[c] = true


func _refresh_pieces() -> void:
	for c in _pieces_dirty:
		var list: Array = _pieces[c]
		var node: MultiMeshInstance3D = _piece_nodes[c]
		if list.is_empty():
			if node != null:
				node.queue_free()
				_piece_nodes[c] = null
			continue
		if node == null:
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = _mesh_for(c)
			node = MultiMeshInstance3D.new()
			node.multimesh = mm
			_ball.add_child(node)
			_piece_nodes[c] = node
		var mm: MultiMesh = node.multimesh
		mm.instance_count = list.size()
		for k in list.size():
			mm.set_instance_transform(k, list[k].xform)
	_pieces_dirty.clear()
	var carried := 0
	for list in _pieces:
		carried += list.size()
	stats.carried = carried


## One mesh for a class's object, built from its voxels (Mesher).
func _mesh_for(c: int) -> Mesh:
	if _class_mesh[c] == null:
		var def: ObjectDef = _class_defs[c]
		var arrays := []
		for key in def.grid.keys():
			var built := Mesher.build(def.grid, key, project.palette, project.voxel_size * def.unit)
			if not built.is_empty():
				arrays.append(built.arrays)
		var mesh := InstanceRenderer.merge(arrays)
		var mat := StandardMaterial3D.new()
		mat.vertex_color_use_as_albedo = true
		mesh.surface_set_material(0, mat)
		_class_mesh[c] = mesh
	return _class_mesh[c]


## Removes picked-up objects from the project, all in one go; a class's
## object goes too once its last copy has been picked up.
func flush() -> void:
	for id in _pending:
		project.remove_and_prune(project.root_id, id)
	_pending.clear()


func _poke(dt: float) -> void:
	autopilot = true
	_poke_timer -= dt
	if _poke_timer > 0.0:
		return
	_poke_timer = 5.0
	flush()
	var alive := _items.filter(func(it): return it.alive).size()
	var in_project := project.root().children.size() - _base_children
	if in_project != alive:
		poke_failures.append("%d objects in the project but %d not picked up" % [in_project, alive])
	for c in _pieces.size():
		if _pieces[c].is_empty() and _piece_nodes[c] != null and not _pieces_dirty.has(c):
			poke_failures.append("class %d has no pieces but still has a MultiMesh" % c)


func status_lines() -> String:
	var counts := []
	for c in _left.size():
		var total: int = CLASSES[c][1]
		counts.append("%s cm %d/%d" % [Hud._fmt(CLASSES[c][0] * BLOCKS), total - _left[c], total])
	return "Ball %s cm across · picks up ≤ %s cm · %s\non the ball %d · retired %d\n%s\n%s" % [
		Hud._fmt(radius * 200.0), Hud._fmt(reach() * 100.0),
		"autopilot (P)" if autopilot else "P autopilot", stats.carried, stats.retired,
		" · ".join(counts.slice(0, 4)), " · ".join(counts.slice(4))]


func report_line() -> String:
	var classes := []
	for c in _left.size():
		classes.append("%s cm %d" % [Hud._fmt(CLASSES[c][0] * BLOCKS), CLASSES[c][1] - _left[c]])
	return "ball %.2f m across, %d picked (%s), %d on the ball, %d retired" % [
		radius * 2.0, stats.picked, ", ".join(classes), stats.carried, stats.retired]


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_P:
		autopilot = not autopilot
		main.hud.toast("Autopilot on" if autopilot else "Autopilot off")
