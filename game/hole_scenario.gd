class_name HoleScenario
extends Node
## A soak test you can watch: a square hole in the middle of the map
## destroys anything that touches it, and clouds circling above it drop
## freshly made word trees that fall in. It keeps creating, moving and
## deleting whole object trees through the normal Project API.
##
## Undo is off while it runs (its changes would flood the history). Objects
## that were only used by a destroyed tree are deleted from the library.

## Hole size and cloud layout, in metres.
const HOLE := 8.0
const CLOUD_HEIGHT := 20.0
const CLOUD_ORBIT := 3.5
const CLOUDS := 3
## Seconds between drops from each cloud.
const DROP_EVERY := Vector2(1.5, 3.5)
const GRAVITY := 9.8
## How far below the ground (metres) an object must sink inside the hole
## before it's destroyed, so you see it go in.
const SINK := 0.4
## Sideways drift of new trees (metres per second).
const DRIFT := 0.6

var main: Node
var project: Project
var view: WorldView
var rng := RandomNumberGenerator.new()
var trees: WordTrees
var stats := {"spawned": 0, "destroyed": 0, "landed": 0, "objects deleted": 0, "player falls": 0}

## inst id -> {angle, timer}
var _clouds := {}
## inst id -> {pos: Vector3, vel: Vector3}, both in smallest-block units
var _falling := {}
var _scan_timer := 0.0
var _cloud_def := ""
## Soak mode: run this many seconds, check invariants, report and quit.
var soak := 0.0
var _elapsed := 0.0
var _start_ram := 0
## Soak pokes: things the soak did that the hole must react to, with a
## deadline. {kind, id, deadline}
var _pokes: Array = []
var _poke_timer := 5.0
var _poke_failures := PackedStringArray()


func _init(seed := 1) -> void:
	rng.seed = seed
	trees = WordTrees.new(seed, WordTrees.load_words())


## Starts on a project (also called when the game switches projects).
func attach(main_node: Node, p: Project, v: WorldView) -> void:
	main = main_node
	project = p
	view = v
	project.set_recording(false)
	_clouds.clear()
	_falling.clear()
	var cloud := _make_cloud()
	for i in CLOUDS:
		var inst := project.add_instance(project.root_id, cloud.id, Vector3i.ZERO, 0)
		_clouds[inst.id] = {"angle": TAU * i / CLOUDS, "timer": rng.randf_range(0.2, DROP_EVERY.y)}
	_update_dynamic()


func falling_count() -> int:
	return _falling.size()


func _physics_process(dt: float) -> void:
	if project == null:
		return
	_elapsed += dt
	if _start_ram == 0:
		_start_ram = OS.get_static_memory_usage()
	if soak > 0.0 and _elapsed >= soak:
		_finish_soak()
		soak = 0.0
		return
	if soak > 0.0:
		_poke(dt)
	var s := 1.0 / project.voxel_size # metres -> smallest blocks
	var root := project.root()
	# Clouds circle the hole and drop trees.
	for id in _clouds.keys():
		var inst := root.find_child(id)
		if inst == null:
			_clouds.erase(id)
			continue
		var c: Dictionary = _clouds[id]
		c.angle += dt * 0.15
		var cb := project.def_bounds(inst.def_id)
		var centre := Vector3(cos(c.angle) * CLOUD_ORBIT, CLOUD_HEIGHT, sin(c.angle) * CLOUD_ORBIT) * s
		_move(inst, Vector3i((centre - cb.get_center()).round()))
		c.timer -= dt
		if c.timer <= 0.0:
			c.timer = rng.randf_range(DROP_EVERY.x, DROP_EVERY.y)
			_drop_tree(centre - Vector3(0, cb.size.y * 0.5 + 1.0 * s, 0))
	# Falling trees.
	var g := GRAVITY * s
	for id in _falling.keys():
		var inst := root.find_child(id)
		if inst == null:
			_falling.erase(id)
			continue
		var f: Dictionary = _falling[id]
		f.vel.y -= g * dt
		f.pos += f.vel * dt
		var offset := Vector3i(f.pos.round())
		var b := _rotated_bounds(inst)
		var bottom := offset.y + b.position.y
		if _over_hole(offset, b):
			if bottom < -SINK * s:
				_destroy(inst)
				continue
		elif bottom <= 0:
			offset.y -= int(floor(bottom))
			_falling.erase(id)
			stats.landed += 1
			_move(inst, offset)
			_update_dynamic()
			continue
		_move(inst, offset)
	# Every so often: things over the hole start to fall, world blocks over
	# it are erased, and a player who fell in comes back.
	_scan_timer -= dt
	if _scan_timer <= 0.0:
		_scan_timer = 0.5
		_scan(root, s)


## During a soak, every few seconds: drag a landed tree over the hole, put
## a world block over it and drop the player in, then check that each was
## dealt with in time.
func _poke(dt: float) -> void:
	var s := 1.0 / project.voxel_size
	for p in _pokes.duplicate():
		var done := false
		match p.kind:
			"tree": done = project.root().find_child(p.id) == null
			"block": done = project.root().grid.get_cell(p.cell) == 0
			"player": done = main.player.global_position.y > -0.5
		if done:
			_pokes.erase(p)
		elif _elapsed > p.deadline:
			_poke_failures.append("%s wasn't handled by the hole within 4 s (at %.0f s)" % [p.kind, _elapsed])
			_pokes.erase(p)
	_poke_timer -= dt
	if _poke_timer > 0.0:
		return
	_poke_timer = 5.0
	var landed := project.root().children.filter(func(i): return not _clouds.has(i.id) and not _falling.has(i.id))
	if not landed.is_empty():
		var inst: ObjectInstance = landed[rng.randi_range(0, landed.size() - 1)]
		var b := _rotated_bounds(inst)
		_move(inst, Vector3i(-int(b.get_center().x), inst.offset.y, -int(b.get_center().z)))
		_pokes.append({"kind": "tree", "id": inst.id, "deadline": _elapsed + 4.0})
	var root := project.root()
	var cell := Vector3i(int(rng.randf_range(-3, 3) * s / root.unit), 0, int(rng.randf_range(-3, 3) * s / root.unit))
	project.edit_box(root.id, cell, cell + Vector3i.ONE * 10, 5)
	_pokes.append({"kind": "block", "cell": cell, "deadline": _elapsed + 4.0})
	main.player.global_position = Vector3(0, -2.0, 0)
	_pokes.append({"kind": "player", "deadline": _elapsed + 4.0})


## Checks the project and the view after a soak run, prints a report and
## quits (exit code 1 if a check failed).
func _finish_soak() -> void:
	view.flush()
	var f := TreeFuzz.new(1, project)
	f.view = view
	f._check_invariants()
	f.check_view()
	var reachable := project.dependencies(project.root_id)
	var orphans := project.defs.size() - reachable.size()
	if orphans > 0:
		f.fail("%d objects are no longer used anywhere (a leak)" % orphans)
	for msg in _poke_failures:
		f.fail(msg)
	print("Hole soak: %.0f s, %s" % [_elapsed, stats])
	print("  library %d objects, %d placements, falling %d, RAM %+d MB since start, %d fps" % [
		project.defs.size(), view._placements.size(), _falling.size(),
		(OS.get_static_memory_usage() - _start_ram) / 1_000_000, Engine.get_frames_per_second()])
	if f.failures.is_empty():
		print("  all checks passed")
	for msg in f.failures:
		print("  FAILED " + msg)
	get_tree().quit(0 if f.failures.is_empty() else 1)


func _drop_tree(at: Vector3) -> void:
	var top := trees.build(project, rng.randi_range(1, 3), 3)
	var rot := rng.randi_range(0, 3)
	var b := Transform3D(ObjectInstance.basis_for(rot), Vector3.ZERO) * project.def_bounds(top.id)
	var offset := Vector3i((at - Vector3(b.get_center().x, b.end.y, b.get_center().z)).round())
	var inst := project.add_instance(project.root_id, top.id, offset, rot)
	if inst == null:
		return
	var s := 1.0 / project.voxel_size
	var drift := Vector3(rng.randf_range(-DRIFT, DRIFT), 0, rng.randf_range(-DRIFT, DRIFT)) * s
	_falling[inst.id] = {"pos": Vector3(offset), "vel": drift}
	stats.spawned += 1
	_update_dynamic()


func _scan(root: ObjectDef, s: float) -> void:
	var newly := false
	for inst in root.children.duplicate():
		if _clouds.has(inst.id) or _falling.has(inst.id):
			continue
		var b := _rotated_bounds(inst)
		if b.size == Vector3.ZERO:
			continue
		if _over_hole(inst.offset, b):
			# Nothing holds it up any more: let it fall in.
			_falling[inst.id] = {"pos": Vector3(inst.offset), "vel": Vector3.ZERO}
			newly = true
	if newly:
		_update_dynamic()
	# Blocks of the world itself over the hole (only if a chunk is there;
	# sweeping the whole column every time would be slow).
	var h := int(HOLE * 0.5 * s / root.unit)
	var lo := Vector3i(-h, -int(Scenery.PIT_DEPTH * s / root.unit), -h)
	var hi := Vector3i(h, int(4.0 * s / root.unit), h)
	var hole_box := AABB(Vector3(lo), Vector3(hi - lo))
	for key in root.grid.keys():
		if AABB(Vector3(key * VoxelGrid.SIZE), Vector3.ONE * VoxelGrid.SIZE).intersects(hole_box):
			project.edit_box(root.id, lo, hi, 0)
			break
	# The player.
	var player: Node3D = main.player
	var pp := player.global_position
	if absf(pp.x) < HOLE * 0.5 and absf(pp.z) < HOLE * 0.5 and pp.y < -1.0:
		stats["player falls"] += 1
		player.global_position = Vector3(0, 0.2, HOLE * 0.5 + 4.0)
		player.velocity = Vector3.ZERO
		main.hud.toast("The hole got you. Respawned at the edge.", 3.0)


## An instance's bounds turned by its rotation (local smallest blocks).
func _rotated_bounds(inst: ObjectInstance) -> AABB:
	return Transform3D(ObjectInstance.basis_for(inst.rot), Vector3.ZERO) * project.def_bounds(inst.def_id)


## Whether an object at offset (bounds b, local smallest blocks, already
## rotated if needed) overlaps the hole's footprint.
func _over_hole(offset: Vector3i, b: AABB) -> bool:
	var h := HOLE * 0.5 / project.voxel_size
	var x0 := offset.x + b.position.x
	var z0 := offset.z + b.position.z
	return x0 < h and x0 + b.size.x > -h and z0 < h and z0 + b.size.z > -h


func _destroy(inst: ObjectInstance) -> void:
	_falling.erase(inst.id)
	stats["objects deleted"] += project.remove_and_prune(project.root_id, inst.id)
	stats.destroyed += 1
	_update_dynamic()


func _move(inst: ObjectInstance, offset: Vector3i) -> void:
	if offset == inst.offset:
		return
	project.set_instance_transform(project.root_id, inst.id, offset, inst.rot, false)
	view.refresh_instance(inst)


## Clouds and falling trees move every frame, so they're drawn live.
func _update_dynamic() -> void:
	var ids := {}
	for id in _clouds:
		ids[id] = true
	for id in _falling:
		ids[id] = true
	view.set_dynamic(ids)


func _make_cloud() -> ObjectDef:
	if project.defs.has(_cloud_def):
		return project.defs[_cloud_def]
	var cloud := project.create_def("cloud", 10)
	# A few overlapping blobs of 10 cm blocks.
	for k in 5:
		var c := Vector3(rng.randf_range(-12, 12), rng.randf_range(-2, 3), rng.randf_range(-8, 8))
		var r := rng.randf_range(5, 9)
		for x in range(int(c.x - r), int(c.x + r) + 1):
			for z in range(int(c.z - r), int(c.z + r) + 1):
				var dy := sqrt(maxf(0.0, r * r - (x - c.x) * (x - c.x) - (z - c.z) * (z - c.z))) * 0.5
				if dy > 0.0:
					cloud.grid.fill_box(Vector3i(x, int(c.y - dy), z), Vector3i(x + 1, int(c.y + dy) + 1, z + 1), 2)
	_cloud_def = cloud.id
	return cloud
