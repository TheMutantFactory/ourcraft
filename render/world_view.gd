class_name WorldView
extends Node3D
## Renders a Project. Chunk meshes and collision shapes are built once per
## object definition and shared by every instance of it, so instancing is
## cheap and an edit shows up in every copy at once. To save memory, a chunk
## only gets an ArrayMesh while its object is drawn live, and a collision
## shape only while a nearby body uses it; baked objects are remeshed straight
## into their region.
##
## The instance tree is flattened into placements (one per rendered copy of
## an object, with its world transform); no nodes are created per instance.
## Live placements (the object being edited, anything dragged, and objects
## with many copies) are drawn by InstanceRenderer with shared meshes;
## everything else is merged into region meshes by RegionBaker.
## CollisionField gives placements near the player physics bodies.

## Main-thread time per frame for uploading meshes from worker jobs.
const UPLOAD_BUDGET_USEC := 4000
## Main-thread time per frame for meshing inline with the native mesher.
const INLINE_BUDGET_USEC := 8000
## Main-thread time per frame for rebaking regions (at least one per frame).
const BAKE_BUDGET_USEC := 6000

var project: Project
var material: ShaderMaterial

## def_id -> {Vector3i key -> {"mesh": ArrayMesh or null, "shape":
## ConcavePolygonShape3D or null, "users": bodies using the shape}}. Every
## allocated chunk has an entry once processed.
var _meshes: Dictionary = {}
## def_id -> true for objects with at least one live placement.
var _live_defs: Dictionary = {}
## def_id -> {key -> true}
var _dirty: Dictionary = {}
## "def_id|key" -> edit counter, so results for stale snapshots are dropped.
var _versions: Dictionary = {}
## Bumped by remesh_all so jobs from before a full rebuild are dropped.
var _generation := 0
## Running mesh jobs: Array of {task, def_id, key, version, generation, result}
var _jobs: Array = []
var _max_jobs := maxi(1, OS.get_processor_count() - 1)
var _depth_materials: Array = []
## Physics bodies near the player (see CollisionField).
var collision: CollisionField
## Array of {path, def_id, depth, xform (metres), cell_m}
var _placements: Array = []
var _renderer: InstanceRenderer
var _baker: RegionBaker
var _isolated = null
## The object being edited and the instance being dragged stay live.
var _edit_def_id := ""
var _drag_inst := "" # PackedStringArray or null
var _tree_dirty := false


func _ready() -> void:
	Native.kernels() # initialise on the main thread before workers use it
	collision = CollisionField.new(get_world_3d().space)
	material = ShaderMaterial.new()
	material.shader = load("res://render/voxel.gdshader")
	_renderer = InstanceRenderer.new()
	_renderer.material_for_depth = _material_for_depth
	add_child(_renderer)
	_baker = RegionBaker.new()
	_baker.material_for_depth = _material_for_depth
	_baker.bounds_of = _chunk_bounds
	_baker.arrays_for = _arrays_for
	collision.shape_for = _shape_for
	collision.release_shape = _release_shape
	add_child(_baker)


func _exit_tree() -> void:
	if collision != null:
		collision.clear()


func set_project(p: Project) -> void:
	if project != null:
		project.voxels_changed.disconnect(_on_voxels_changed)
		project.structure_changed.disconnect(_on_structure_changed)
	project = p
	project.voxels_changed.connect(_on_voxels_changed)
	project.structure_changed.connect(_on_structure_changed)
	remesh_all()


## Rebuilds every mesh (e.g. after the minimum block size changes).
func remesh_all() -> void:
	if collision != null:
		collision.clear()
	if _baker != null:
		_baker.clear()
	_meshes.clear()
	_live_defs.clear()
	_dirty.clear()
	_generation += 1
	for def in project.defs.values():
		for key in def.grid.keys():
			_dirty.get_or_add(def.id, {})[key] = true
	# Rebuilt on the next frame (or flush), after callers set the edit
	# context, so render modes are only computed once.
	_tree_dirty = true


func pending_chunks() -> int:
	var n := 0
	for d in _dirty.values():
		n += d.size()
	return n + _jobs.size() + (_baker.pending() if _baker != null else 0)


func _on_voxels_changed(def_id: String, keys: Array) -> void:
	var d: Dictionary = _dirty.get_or_add(def_id, {})
	for key in keys:
		d[key] = true
		var vk := _version_key(def_id, key)
		_versions[vk] = int(_versions.get(vk, 0)) + 1


static func _version_key(def_id: String, key: Vector3i) -> String:
	return "%s|%d|%d|%d" % [def_id, key.x, key.y, key.z]


func _on_structure_changed() -> void:
	_tree_dirty = true


func _process(_delta: float) -> void:
	if _tree_dirty:
		rebuild_tree()
	if Native.available():
		_mesh_inline(INLINE_BUDGET_USEC)
	else:
		_collect_jobs(UPLOAD_BUDGET_USEC)
		_dispatch_jobs()
	# Bake once meshing has caught up, so regions aren't rebuilt per chunk.
	if _dirty.is_empty() and _jobs.is_empty():
		_baker.process(_meshes, BAKE_BUDGET_USEC)


## With the native mesher a chunk takes ~20 µs, so meshing on the main
## thread within a time budget beats the latency of handing work to threads.
func _mesh_inline(budget_usec: int) -> void:
	var start := Time.get_ticks_usec()
	_collect_jobs(0) # finish anything started before the extension loaded
	for def_id in _dirty.keys():
		var def: ObjectDef = project.defs.get(def_id)
		var keys: Dictionary = _dirty[def_id]
		for key in keys.keys():
			if budget_usec > 0 and Time.get_ticks_usec() - start > budget_usec:
				return
			keys.erase(key)
			if def != null:
				_apply(def_id, key, _build(def, key) if _needs_geometry(def_id, key) else {})
		_dirty.erase(def_id)


## Whether a changed chunk needs meshing now: its object is drawn live or a
## body is using its collision shape. Otherwise baking will mesh it.
func _needs_geometry(def_id: String, key: Vector3i) -> bool:
	if _live_defs.has(def_id):
		return true
	var entry = _meshes.get(def_id, {}).get(key)
	return entry != null and entry.shape != null


func _build(def: ObjectDef, key: Vector3i) -> Dictionary:
	return Mesher.build_from(Mesher.gather(def.grid, key), key, project.palette, project.voxel_size * def.unit)


## Starts mesh jobs on the worker pool for dirty chunks, skipping chunks
## that already have a job running (they stay dirty until it finishes).
func _dispatch_jobs() -> void:
	if _dirty.is_empty() or _jobs.size() >= _max_jobs:
		return
	var running := {}
	for job in _jobs:
		running[_version_key(job.def_id, job.key)] = true
	for def_id in _dirty.keys():
		var def: ObjectDef = project.defs.get(def_id)
		var keys: Dictionary = _dirty[def_id]
		if def == null:
			_dirty.erase(def_id)
			continue
		for key in keys.keys():
			if _jobs.size() >= _max_jobs:
				return
			var vk := _version_key(def_id, key)
			if running.has(vk):
				continue
			keys.erase(key)
			if not _needs_geometry(def_id, key):
				_apply(def_id, key, {})
				continue
			var job := {
				"def_id": def_id, "key": key, "version": _versions.get(vk, 0),
				"generation": _generation, "result": {},
			}
			var input := Mesher.gather(def.grid, key)
			var palette := project.palette.duplicate()
			var cell_m := project.voxel_size * def.unit
			job.task = WorkerThreadPool.add_task(func():
				job.result = Mesher.build_from(input, key, palette, cell_m))
			_jobs.append(job)
		if keys.is_empty():
			_dirty.erase(def_id)


## Applies finished jobs, spending at most budget_usec (0 = wait for all).
func _collect_jobs(budget_usec: int) -> void:
	var start := Time.get_ticks_usec()
	var i := 0
	while i < _jobs.size():
		var job: Dictionary = _jobs[i]
		if budget_usec > 0 and not WorkerThreadPool.is_task_completed(job.task):
			i += 1
			continue
		WorkerThreadPool.wait_for_task_completion(job.task)
		_jobs.remove_at(i)
		var vk := _version_key(job.def_id, job.key)
		if job.generation == _generation and job.version == _versions.get(vk, 0):
			_apply(job.def_id, job.key, job.result)
		if budget_usec > 0 and Time.get_ticks_usec() - start > budget_usec:
			return


## Meshes everything still pending right away (used before screenshots/tests).
func flush() -> void:
	if _tree_dirty:
		rebuild_tree()
	if Native.available():
		_mesh_inline(0)
	else:
		while not _jobs.is_empty() or not _dirty.is_empty():
			_dispatch_jobs()
			_collect_jobs(0)
	_baker.process(_meshes, 0)


## Records a processed chunk. built is the mesher output, or {} when the
## chunk wasn't meshed (its object isn't live and no body needs its shape).
func _apply(def_id: String, key: Vector3i, built: Dictionary) -> void:
	var def: ObjectDef = project.defs.get(def_id)
	if def == null:
		_meshes.erase(def_id)
		return
	var entries: Dictionary = _meshes.get_or_add(def_id, {})
	if not def.grid.has_chunk(key):
		var old = entries.get(key)
		if old != null:
			if old.mesh != null:
				_renderer.chunk_removed(def_id, key)
			entries.erase(key)
			collision.update_def(def_id)
			_baker.def_changed(def_id)
		return
	var entry = entries.get(key)
	var fresh: bool = entry == null
	if fresh:
		entry = {"mesh": null, "shape": null, "users": 0}
		entries[key] = entry
	if _live_defs.has(def_id):
		_set_mesh(def_id, key, entry, built)
	if entry.shape != null:
		entry.shape.set_faces(built.get("faces", PackedVector3Array()))
	_baker.def_changed(def_id)
	if fresh:
		collision.update_def(def_id)


func _set_mesh(def_id: String, key: Vector3i, entry: Dictionary, built: Dictionary) -> void:
	if built.is_empty():
		if entry.mesh != null:
			entry.mesh = null
			_renderer.chunk_removed(def_id, key)
		return
	var fresh: bool = entry.mesh == null
	if fresh:
		entry.mesh = ArrayMesh.new()
	var mesh: ArrayMesh = entry.mesh
	mesh.clear_surfaces()
	mesh.add_surface_from_arrays(Mesher.PRIMITIVE, built.arrays)
	mesh.surface_set_material(0, material)
	if fresh:
		_renderer.chunk_added(def_id, key, mesh)


## Collision shape for a chunk, built on first use (CollisionField callback).
func _shape_for(def_id: String, key: Vector3i) -> Shape3D:
	var entry = _meshes.get(def_id, {}).get(key)
	var def: ObjectDef = project.defs.get(def_id)
	if entry == null or def == null:
		return null
	if entry.shape == null:
		var built := _build(def, key)
		if built.is_empty():
			return null
		var shape := ConcavePolygonShape3D.new()
		shape.backface_collision = true
		shape.set_faces(built.faces)
		entry.shape = shape
	entry.users += 1
	return entry.shape


## A body stopped using a chunk's shape; drop the shape when none do.
func _release_shape(def_id: String, key: Vector3i) -> void:
	var entry = _meshes.get(def_id, {}).get(key)
	if entry == null:
		return
	entry.users -= 1
	if entry.users <= 0:
		entry.users = 0
		entry.shape = null


## Mesh arrays for baking (RegionBaker callback); null if nothing visible.
func _arrays_for(def_id: String, key: Vector3i):
	var def: ObjectDef = project.defs.get(def_id)
	if def == null:
		return null
	var entry = _meshes.get(def_id, {}).get(key)
	if entry != null and entry.mesh != null:
		return (entry.mesh as ArrayMesh).surface_get_arrays(0)
	var built := _build(def, key)
	return null if built.is_empty() else built.arrays


## Gives newly live objects meshes and frees meshes of objects no longer
## drawn live.
func _update_live_meshes(live_defs: Dictionary) -> void:
	for def_id in _live_defs:
		if live_defs.has(def_id):
			continue
		for entry in _meshes.get(def_id, {}).values():
			entry.mesh = null
	for def_id in live_defs:
		if _live_defs.has(def_id):
			continue
		_live_defs[def_id] = true
		var def: ObjectDef = project.defs.get(def_id)
		if def == null:
			continue
		var pending: Dictionary = _dirty.get(def_id, {})
		for key in def.grid.keys():
			if not pending.has(key):
				_apply(def_id, key, _build(def, key))
	_live_defs = live_defs


## One material per tree depth; per-instance shader parameters run out of
## global buffer space with tens of thousands of chunks.
func _material_for_depth(depth: int) -> ShaderMaterial:
	while _depth_materials.size() <= depth:
		var m: ShaderMaterial = material.duplicate()
		m.set_shader_parameter("layer", float(_depth_materials.size()))
		_depth_materials.append(m)
	return _depth_materials[depth]


# --- Instance tree ---------------------------------------------------------

func rebuild_tree() -> void:
	_tree_dirty = false
	_placements = []
	_collect(project.root_id, PackedStringArray(), Transform3D.IDENTITY, 0)
	collision.set_placements(_placements, _chunk_bounds)
	_apply_isolation()


## Walks the instance tree, adding a placement for every rendered object.
func _collect(def_id: String, path: PackedStringArray, xform: Transform3D, depth: int) -> void:
	var def: ObjectDef = project.defs.get(def_id)
	if def == null:
		return
	_placements.append({"path": path, "def_id": def_id, "depth": depth, "xform": xform,
		"cell_m": project.voxel_size * def.unit})
	if depth >= Project.MAX_DEPTH:
		return
	for child in def.children:
		var child_path := path.duplicate()
		child_path.append(child.id)
		_collect(child.def_id, child_path, xform * _local_xform(child), depth + 1)


func _local_xform(inst: ObjectInstance) -> Transform3D:
	return Transform3D(ObjectInstance.basis_for(inst.rot), Vector3(inst.offset) * project.voxel_size)


func render_node_count() -> int:
	return _renderer.node_count()


## Bounds of a definition's allocated chunks, in its local metres.
func _chunk_bounds(def_id: String) -> AABB:
	var def: ObjectDef = project.defs.get(def_id)
	if def == null or def.grid.is_empty():
		return AABB()
	var lo := Vector3i.ONE * (1 << 30)
	var hi := -lo
	for key in def.grid.keys():
		lo = lo.min(key)
		hi = hi.max(key)
	var size := VoxelGrid.SIZE * project.voxel_size * def.unit
	return AABB(Vector3(lo) * size, Vector3(hi - lo + Vector3i.ONE) * size)


## World transform (metres) of the object at a path.
func world_xform(path: PackedStringArray) -> Transform3D:
	var t := project.path_transform(path)
	t.origin *= project.voxel_size
	return t


## Updates every rendered copy of an instance after its transform changed
## without rebuilding the tree (used while dragging).
func refresh_instance(inst: ObjectInstance) -> void:
	collision.refresh_instance(inst.id, world_xform)
	_renderer.update(collision.placements_under(inst.id))


## Physics bodies belonging to every rendered copy of an instance.
func bodies_of(inst_id: String) -> Array:
	return collision.bodies_of(inst_id)


## {path, def_id} of the chunk a ray hit, or {} (e.g. for the ground).
func pick(hit: Dictionary) -> Dictionary:
	return collision.info(hit.get("rid", RID()))


## Keeps physics bodies around this point (call every physics frame).
func set_focus(point: Vector3, reach: float) -> void:
	collision.focus = point
	collision.radius = reach


func _physics_process(_delta: float) -> void:
	if collision != null and project != null:
		collision.sync(_meshes)


# --- Isolation -------------------------------------------------------------

## Shows only the object at path (and its contents); null shows everything.
func set_isolation(path) -> void:
	_isolated = path
	collision.set_isolation(path)
	_apply_isolation()


## Sets which object is being edited; it stays live (never baked) so
## edits show immediately in every copy.
func set_edit_def(def_id: String) -> void:
	if def_id == _edit_def_id:
		return
	_edit_def_id = def_id
	_apply_render_modes()


## Keeps an instance (and everything in it) live while it's dragged; "" ends.
func set_dragging(inst_id: String) -> void:
	if inst_id == _drag_inst:
		return
	_drag_inst = inst_id
	_apply_render_modes()


func baked_region_count() -> int:
	return _baker.region_count()


func baked_quad_count() -> int:
	return _baker.quad_count()


func _apply_isolation() -> void:
	_apply_render_modes()


## Splits visible placements between live instancing and baked regions.
func _apply_render_modes() -> void:
	if _renderer == null or project == null or _tree_dirty:
		return
	var copies := {}
	for i in _placements.size():
		if _is_visible(i):
			var pl: Dictionary = _placements[i]
			var gk := "%s|%d" % [pl.def_id, pl.depth]
			copies[gk] = int(copies.get(gk, 0)) + 1
	var dragged := {}
	if _drag_inst != "":
		for i in collision.placements_under(_drag_inst):
			dragged[i] = true
	var live := {}
	var live_defs := {}
	for i in _placements.size():
		if not _is_visible(i):
			continue
		var pl: Dictionary = _placements[i]
		if pl.def_id == _edit_def_id or dragged.has(i) \
				or copies["%s|%d" % [pl.def_id, pl.depth]] >= InstanceRenderer.MULTIMESH_MIN:
			live[i] = true
			live_defs[pl.def_id] = true
	_update_live_meshes(live_defs)
	_renderer.set_placements(_placements, func(i): return live.has(i), _meshes)
	_baker.set_placements(_placements, func(i): return _is_visible(i) and not live.has(i))


func _is_visible(i: int) -> bool:
	if _isolated == null:
		return true
	return CollisionField._has_prefix(_placements[i].path, _isolated)
