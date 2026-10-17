class_name CollisionField
extends RefCounted
## Physics bodies for voxel chunks, created only near a focus point (the
## player). Bodies live directly on the PhysicsServer3D (no nodes) and share
## each chunk's collision shape with every other copy of that chunk.
##
## Rendering is unaffected: far-away chunks are drawn but can't be touched,
## which is fine because the player can only reach a few metres.

## Spatial hash cell size for placements, in metres.
const CELL := 8.0
## Re-query when the focus moves this far (metres).
const MOVE_THRESHOLD := 0.5

## Where the player is and how far bodies should extend around them.
var focus := Vector3.ZERO
var radius := 10.0

var _space: RID
## Array of placements: {path, def_id, xform (Transform3D, metres), cell_m}
var _placements: Array = []
## Vector3i hash cell -> Array of placement indices
var _hash: Dictionary = {}
## instance id -> Array of placement indices at or below that instance
var _by_inst: Dictionary = {}
## def id -> Array of placement indices
var _by_def: Dictionary = {}
var _bounds_of: Callable
var _stale_defs: Dictionary = {}
## "placement index|chunk key" -> body RID
var _bodies: Dictionary = {}
## body RID -> placement index (for picking)
var _owner: Dictionary = {}
var _isolated = null
var _last_focus := Vector3.INF
var _dirty := true


func _init(space: RID) -> void:
	_space = space


## Replaces the placement list (after the instance tree was rebuilt).
## bounds_of(def_id) gives a definition's chunk bounds in local metres.
func set_placements(placements: Array, bounds_of: Callable) -> void:
	clear()
	_placements = placements
	_bounds_of = bounds_of
	_stale_defs.clear()
	_hash.clear()
	_by_inst.clear()
	_by_def.clear()
	var cache := {}
	for i in _placements.size():
		var pl: Dictionary = _placements[i]
		if not cache.has(pl.def_id):
			cache[pl.def_id] = bounds_of.call(pl.def_id)
		_insert(i, pl.xform * (cache[pl.def_id] as AABB))
		_by_def.get_or_add(pl.def_id, []).append(i)
		for inst_id in pl.path:
			_by_inst.get_or_add(inst_id, []).append(i)
	_dirty = true


## Call when a definition's set of chunks changed (a chunk appeared or went
## away), so its placements are re-indexed with the new bounds on the next
## sync. Batched because meshing a new scene reports every chunk.
func update_def(def_id: String) -> void:
	if _by_def.has(def_id):
		_stale_defs[def_id] = true
	_dirty = true


func _reindex_stale() -> void:
	if _stale_defs.is_empty() or not _bounds_of.is_valid():
		return
	for def_id in _stale_defs:
		var local: AABB = _bounds_of.call(def_id)
		for i in _by_def.get(def_id, []):
			_placements[i].aabb = _placements[i].xform * local
	_stale_defs.clear()
	_hash.clear()
	for i in _placements.size():
		_insert(i, _placements[i].aabb)


func _insert(i: int, aabb: AABB) -> void:
	var pl: Dictionary = _placements[i]
	pl.aabb = aabb
	for c in _cells(aabb):
		_hash.get_or_add(c, []).append(i)


func set_isolation(path) -> void:
	_isolated = path
	clear()
	_dirty = true


func active_count() -> int:
	return _bodies.size()


## Picking info for a body hit by a ray: {path, def_id} or {}.
func info(rid: RID) -> Dictionary:
	var i = _owner.get(rid)
	if i == null:
		return {}
	var pl: Dictionary = _placements[i]
	return {"path": pl.path, "def_id": pl.def_id}


## Bodies of every placement at or below an instance (to exclude from rays).
func bodies_of(inst_id: String) -> Array:
	var out := []
	var wanted := {}
	for i in _by_inst.get(inst_id, []):
		wanted[i] = true
	for k in _bodies:
		if wanted.has(int(k.get_slice("|", 0))):
			out.append(_bodies[k])
	return out


## Moves the bodies of placements below an instance (used while dragging).
func refresh_instance(inst_id: String, new_xform_of: Callable) -> void:
	var touched := {}
	for i in _by_inst.get(inst_id, []):
		var pl: Dictionary = _placements[i]
		pl.xform = new_xform_of.call(pl.path)
		touched[i] = true
	for k in _bodies:
		var i := int(k.get_slice("|", 0))
		if touched.has(i):
			PhysicsServer3D.body_set_state(_bodies[k], PhysicsServer3D.BODY_STATE_TRANSFORM, _placements[i].xform)


## Creates and frees bodies so that exactly the chunks near the focus have
## one. meshes is WorldView._meshes (def_id -> key -> {shape, ...}).
func sync(meshes: Dictionary) -> void:
	if not _dirty and focus.distance_to(_last_focus) < MOVE_THRESHOLD:
		return
	_dirty = false
	_last_focus = focus
	_reindex_stale()
	var want := {}
	var seen := {}
	for c in _cells(AABB(focus - Vector3.ONE * radius, Vector3.ONE * radius * 2.0)):
		for i in _hash.get(c, []):
			if seen.has(i):
				continue
			seen[i] = true
			var pl: Dictionary = _placements[i]
			if _isolated != null and not _has_prefix(pl.path, _isolated):
				continue
			if _distance(pl.aabb, focus) > radius:
				continue
			var entries: Dictionary = meshes.get(pl.def_id, {})
			if entries.is_empty():
				continue
			_want_chunks(i, pl, entries, want)
	for k in _bodies.keys():
		if not want.has(k):
			var rid: RID = _bodies[k]
			_owner.erase(rid)
			PhysicsServer3D.free_rid(rid)
			_bodies.erase(k)
	for k in want:
		if _bodies.has(k):
			continue
		var i: int = want[k][0]
		var shape: Shape3D = want[k][1]
		var rid := PhysicsServer3D.body_create()
		PhysicsServer3D.body_set_mode(rid, PhysicsServer3D.BODY_MODE_STATIC)
		PhysicsServer3D.body_add_shape(rid, shape.get_rid())
		PhysicsServer3D.body_set_state(rid, PhysicsServer3D.BODY_STATE_TRANSFORM, _placements[i].xform)
		PhysicsServer3D.body_set_space(rid, _space)
		_bodies[k] = rid
		_owner[rid] = i


## Adds the chunks of one placement that lie within the radius.
func _want_chunks(i: int, pl: Dictionary, entries: Dictionary, want: Dictionary) -> void:
	var size: float = VoxelGrid.SIZE * pl.cell_m
	var local: Vector3 = pl.xform.affine_inverse() * focus
	var lo := Vector3i(((local - Vector3.ONE * radius) / size).floor())
	var hi := Vector3i(((local + Vector3.ONE * radius) / size).floor())
	var span := hi - lo + Vector3i.ONE
	var keys: Array
	if span.x * span.y * span.z < entries.size():
		keys = []
		for z in range(lo.z, hi.z + 1):
			for y in range(lo.y, hi.y + 1):
				for x in range(lo.x, hi.x + 1):
					var key := Vector3i(x, y, z)
					if entries.has(key):
						keys.append(key)
	else:
		keys = entries.keys()
	for key in keys:
		var box := AABB(Vector3(key) * size, Vector3.ONE * size)
		if _distance(box, local) > radius:
			continue
		want["%d|%d,%d,%d" % [i, key.x, key.y, key.z]] = [i, entries[key].shape]


func clear() -> void:
	for rid in _bodies.values():
		PhysicsServer3D.free_rid(rid)
	_bodies.clear()
	_owner.clear()
	_dirty = true


func _cells(aabb: AABB) -> Array:
	var lo := Vector3i((aabb.position / CELL).floor())
	var hi := Vector3i((aabb.end / CELL).floor())
	var out := []
	for z in range(lo.z, hi.z + 1):
		for y in range(lo.y, hi.y + 1):
			for x in range(lo.x, hi.x + 1):
				out.append(Vector3i(x, y, z))
	return out


static func _distance(box: AABB, p: Vector3) -> float:
	var q := p.clamp(box.position, box.end)
	return q.distance_to(p)


static func _has_prefix(path: PackedStringArray, prefix: PackedStringArray) -> bool:
	if prefix.size() > path.size():
		return false
	for k in prefix.size():
		if path[k] != prefix[k]:
			return false
	return true
