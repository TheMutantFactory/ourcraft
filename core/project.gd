class_name Project
extends RefCounted
## The whole document: a library of object definitions, the root object that
## forms the world, project-wide settings, and undo history.
##
## All undoable mutations go through methods on this class so that history
## and change notifications stay consistent.

signal voxels_changed(def_id: String, keys: Array)
signal structure_changed
signal library_changed

const FORMAT := "ourcraft.project"
## 1: objects/<id>.json per object. 2: objects.json plus a chunk pack.
const VERSION := 2
const OBJECTS_FILE := "objects.json"

const MAX_DEPTH := 32
const MAX_HISTORY := 200

const DEFAULT_PALETTE := [
	Color("#8a8f98"), # 1 stone
	Color("#f2efe6"), # 2 plaster
	Color("#b07a4a"), # 3 oak
	Color("#5e3c25"), # 4 walnut
	Color("#b4483a"), # 5 brick
	Color("#6aa84f"), # 6 leaf
	Color("#3d7cc9"), # 7 blue
	Color("#e8b93c"), # 8 brass
	Color("#2b2d33"), # 9 charcoal
	Color("#c9ced6"), # 10 steel
]

var title := "Untitled world"
## Per-project scenery and camera settings (ground size/colour/height, fog,
## view distance, spawn point); see Scenery.add_to and game/main.gd.
var environment: Dictionary = {}
## Physical size of the minimum block, in metres.
var voxel_size := 0.01
var palette: Array = DEFAULT_PALETTE.duplicate()
var defs: Dictionary = {}
var root_id := ""

var _undo: Array = []
var _redo: Array = []
## When false, mutations still work (and cancel_step still reverts) but
## nothing is added to undo history. Simulations use this so they don't
## flood the user's history.
var recording := true
var _step = null
var _depth := 0
var _bounds_cache: Dictionary = {}
## Saving only rewrites objects changed since the last save to the same
## directory: _clean holds ids whose file at _saved_path is up to date.
var _saved_path := ""
var _clean: Dictionary = {}
var _removed_since_save := false
## Number of objects whose entry the last save_dir regenerated.
var last_save_written := 0
## id -> that object's one-line entry in objects.json (valid while clean)
var _meta_text: Dictionary = {}
## id -> its chunk hashes in key order (valid while clean)
var _def_hashes: Dictionary = {}
## Current chunk pack file name and hash -> entry size of what it holds.
var _pack_name := ""
var _pack_sizes: Dictionary = {}
## Compact the chunk pack when unreferenced bytes exceed live ones and this.
var compact_min_garbage := 65536


static func create_empty(voxel_size_m: float) -> Project:
	var p := Project.new()
	p.voxel_size = voxel_size_m
	var root := p.create_def("World", 1)
	p.root_id = root.id
	return p


static func new_id() -> String:
	return "%08x%08x" % [randi(), randi()]


func root() -> ObjectDef:
	return defs[root_id]


# --- Library (not undoable) ------------------------------------------------

func create_def(def_name: String, unit := 1) -> ObjectDef:
	var def := ObjectDef.new()
	def.id = new_id()
	while defs.has(def.id):
		def.id = new_id()
	def.name = def_name
	def.unit = maxi(1, unit)
	defs[def.id] = def
	library_changed.emit()
	return def


func unique_name(base: String) -> String:
	var taken := {}
	for d in defs.values():
		taken[d.name] = true
	if not taken.has(base):
		return base
	var n := 2
	while taken.has("%s %d" % [base, n]):
		n += 1
	return "%s %d" % [base, n]


func rename_def(def_id: String, new_name: String) -> void:
	var def: ObjectDef = defs.get(def_id)
	if def == null or new_name.strip_edges() == "":
		return
	def.name = new_name.strip_edges()
	_clean.erase(def_id)
	library_changed.emit()
	structure_changed.emit()


## Copies a definition (voxels and the list of child instances, which keep
## referencing the same nested objects). Returns the new definition.
func fork_def(def_id: String) -> ObjectDef:
	var src: ObjectDef = defs[def_id]
	var def := create_def(unique_name(src.name + " copy"), src.unit)
	def.grid = src.grid.copy()
	def.forked_from = src.id
	if not def.grid.is_empty():
		voxels_changed.emit(def.id, def.grid.keys())
	for inst in src.children:
		var c: ObjectInstance = inst.copy()
		c.id = new_id()
		def.children.append(c)
	library_changed.emit()
	return def


func set_def_unit(def_id: String, unit: int) -> void:
	var def: ObjectDef = defs.get(def_id)
	if def == null or unit < 1 or def.unit == unit:
		return
	def.unit = unit
	_clean.erase(def_id)
	_bounds_cache.clear()
	voxels_changed.emit(def_id, def.grid.keys())
	structure_changed.emit()
	library_changed.emit()


## Deletes a definition and every instance of it. Clears undo history.
func delete_def(def_id: String) -> bool:
	if def_id == root_id or not defs.has(def_id):
		return false
	for def in defs.values():
		var kept: Array = def.children.filter(func(i): return i.def_id != def_id)
		if kept.size() != def.children.size():
			def.children = kept
			_clean.erase(def.id)
	defs.erase(def_id)
	_clean.erase(def_id)
	_removed_since_save = true
	_undo.clear()
	_redo.clear()
	_bounds_cache.clear()
	library_changed.emit()
	structure_changed.emit()
	return true


## Instance count for every object, in one pass (usage_count per object
## would scan every object each time).
func usage_counts() -> Dictionary:
	var counts := {}
	for def in defs.values():
		for inst in def.children:
			counts[inst.def_id] = int(counts.get(inst.def_id, 0)) + 1
	return counts


func usage_count(def_id: String) -> int:
	var n := 0
	for def in defs.values():
		for inst in def.children:
			if inst.def_id == def_id:
				n += 1
	return n


## True if placing child_id inside parent_id would make an object contain
## itself.
func would_cycle(parent_id: String, child_id: String) -> bool:
	if parent_id == child_id:
		return true
	return _contains(child_id, parent_id, 0)


func _contains(def_id: String, target: String, depth: int) -> bool:
	if depth > MAX_DEPTH:
		return true
	var def: ObjectDef = defs.get(def_id)
	if def == null:
		return false
	for inst in def.children:
		if inst.def_id == target or _contains(inst.def_id, target, depth + 1):
			return true
	return false


# --- Paths -----------------------------------------------------------------
# A path is a PackedStringArray of instance ids starting below the root.

## Returns the definitions along a path (root first), or [] if invalid.
func defs_along(path: PackedStringArray) -> Array:
	var out := [root()]
	var def: ObjectDef = root()
	for inst_id in path:
		var inst := def.find_child(inst_id)
		if inst == null or not defs.has(inst.def_id):
			return []
		def = defs[inst.def_id]
		out.append(def)
	return out


func def_at(path: PackedStringArray) -> ObjectDef:
	var chain := defs_along(path)
	return null if chain.is_empty() else chain[-1]


func instance_at(path: PackedStringArray) -> ObjectInstance:
	if path.is_empty():
		return null
	var parent := def_at(path.slice(0, path.size() - 1))
	return null if parent == null else parent.find_child(path[-1])


func is_valid_path(path: PackedStringArray) -> bool:
	return not defs_along(path).is_empty()


## Transform from the object at path's local min units to world min units.
func path_transform(path: PackedStringArray) -> Transform3D:
	var t := Transform3D.IDENTITY
	var def: ObjectDef = root()
	for inst_id in path:
		var inst := def.find_child(inst_id)
		if inst == null:
			break
		t = t * inst.local_transform()
		def = defs[inst.def_id]
	return t


func path_label(path: PackedStringArray) -> String:
	var names := []
	for def in defs_along(path):
		names.append(def.name)
	return " › ".join(names)


# --- Bounds ----------------------------------------------------------------

## Bounds of an object and everything nested in it, in its local min units.
## Returns an AABB with zero size when empty.
func def_bounds(def_id: String, depth := 0) -> AABB:
	if _bounds_cache.has(def_id):
		return _bounds_cache[def_id]
	var def: ObjectDef = defs.get(def_id)
	var result := AABB()
	var has := false
	if def != null and depth <= MAX_DEPTH:
		if not def.grid.is_empty():
			var g := def.grid.bounds()
			result = AABB(g.position * def.unit, g.size * def.unit)
			has = true
		for inst in def.children:
			var cb := def_bounds(inst.def_id, depth + 1)
			if cb.size == Vector3.ZERO:
				continue
			cb = inst.local_transform() * cb
			result = cb if not has else result.merge(cb)
			has = true
	_bounds_cache[def_id] = result
	return result


# --- Undoable mutations ----------------------------------------------------

## Turns undo recording on or off. Turning it off clears the history, since
## unrecorded changes would make older steps restore stale states.
func set_recording(on: bool) -> void:
	recording = on
	if not on:
		_undo.clear()
		_redo.clear()


## Removes an instance, then deletes every object that was only used inside
## it (nothing else refers to it any more). Returns how many objects were
## deleted. Clears undo history if objects were deleted while recording,
## like delete_def.
func remove_and_prune(parent_id: String, inst_id: String) -> int:
	var parent: ObjectDef = defs.get(parent_id)
	if parent == null:
		return 0
	var inst := parent.find_child(inst_id)
	if inst == null:
		return 0
	var candidates := dependencies(inst.def_id)
	begin_step("Delete object")
	_record_children(parent)
	parent.children.erase(inst)
	end_step()
	var counts := usage_counts()
	var deleted := 0
	var changed := true
	while changed:
		changed = false
		for id in candidates:
			if id == root_id or not defs.has(id) or counts.get(id, 0) > 0:
				continue
			for child in defs[id].children:
				counts[child.def_id] = int(counts.get(child.def_id, 0)) - 1
			defs.erase(id)
			_clean.erase(id)
			deleted += 1
			changed = true
	if deleted > 0:
		_removed_since_save = true
		if recording:
			_undo.clear()
			_redo.clear()
	_bounds_cache.clear()
	structure_changed.emit()
	library_changed.emit()
	return deleted


func begin_step(label: String) -> void:
	if _depth == 0:
		_step = {"label": label, "chunks": {}, "children": {}}
	_depth += 1


func end_step() -> void:
	_depth -= 1
	if _depth > 0:
		return
	if recording and not (_step.chunks.is_empty() and _step.children.is_empty()):
		_undo.append(_step)
		_redo.clear()
		if _undo.size() > MAX_HISTORY:
			_undo.pop_front()
	_step = null


## Ends the current step and reverts everything recorded in it.
func cancel_step() -> void:
	_depth -= 1
	if _depth > 0:
		return
	var step: Dictionary = _step
	_step = null
	if not (step.chunks.is_empty() and step.children.is_empty()):
		_apply(step)


func _record_chunk(def: ObjectDef, key: Vector3i) -> void:
	_clean.erase(def.id)
	var d: Dictionary = _step.chunks.get_or_add(def.id, {})
	if not d.has(key):
		d[key] = def.grid.get_packed(key) # compressed and immutable: cheap to keep


func _record_children(def: ObjectDef) -> void:
	_clean.erase(def.id)
	if not _step.children.has(def.id):
		_step.children[def.id] = def.copy_children()


## Sets every cell in [cmin, cmax) of an object's grid to value (0 erases).
func edit_box(def_id: String, cmin: Vector3i, cmax: Vector3i, value: int) -> void:
	var def: ObjectDef = defs.get(def_id)
	if def == null:
		return
	begin_step("Edit blocks")
	var kmin := VoxelGrid.chunk_of(cmin)
	var kmax := VoxelGrid.chunk_of(cmax - Vector3i.ONE)
	for kz in range(kmin.z, kmax.z + 1):
		for ky in range(kmin.y, kmax.y + 1):
			for kx in range(kmin.x, kmax.x + 1):
				_record_chunk(def, Vector3i(kx, ky, kz))
	var affected := def.grid.fill_box(cmin, cmax, value)
	end_step()
	if not affected.is_empty():
		_bounds_cache.clear()
		voxels_changed.emit(def_id, affected.keys())


func add_instance(parent_id: String, def_id: String, offset: Vector3i, rot := 0) -> ObjectInstance:
	var parent: ObjectDef = defs.get(parent_id)
	if parent == null or not defs.has(def_id) or would_cycle(parent_id, def_id):
		return null
	begin_step("Add object")
	_record_children(parent)
	var inst := ObjectInstance.new()
	inst.id = new_id()
	inst.def_id = def_id
	inst.offset = offset
	inst.rot = posmod(rot, 4)
	parent.children.append(inst)
	end_step()
	_bounds_cache.clear()
	structure_changed.emit()
	library_changed.emit()
	return inst


func remove_instance(parent_id: String, inst_id: String) -> void:
	var parent: ObjectDef = defs.get(parent_id)
	if parent == null or parent.find_child(inst_id) == null:
		return
	begin_step("Delete object")
	_record_children(parent)
	parent.children = parent.children.filter(func(i): return i.id != inst_id)
	end_step()
	_bounds_cache.clear()
	structure_changed.emit()
	library_changed.emit()


## Moves/rotates an instance. With notify = false only data changes (used
## while dragging; the caller updates the view directly).
func set_instance_transform(parent_id: String, inst_id: String, offset: Vector3i, rot: int, notify := true) -> void:
	var parent: ObjectDef = defs.get(parent_id)
	if parent == null:
		return
	var inst := parent.find_child(inst_id)
	if inst == null:
		return
	begin_step("Move object")
	_record_children(parent)
	inst.offset = offset
	inst.rot = posmod(rot, 4)
	end_step()
	_bounds_cache.clear()
	if notify:
		structure_changed.emit()


## Points an instance at a different definition (used by "make unique").
func set_instance_def(parent_id: String, inst_id: String, def_id: String) -> void:
	var parent: ObjectDef = defs.get(parent_id)
	if parent == null or would_cycle(parent_id, def_id):
		return
	var inst := parent.find_child(inst_id)
	if inst == null:
		return
	begin_step("Make unique")
	_record_children(parent)
	inst.def_id = def_id
	end_step()
	_bounds_cache.clear()
	structure_changed.emit()
	library_changed.emit()


## Moves an instance into a different object (keeping its id), placing it
## at offset in the new parent's space. Refused if the new parent is the
## instance's object or is inside it. Returns whether it moved.
func reparent_instance(from_id: String, inst_id: String, to_id: String, offset: Vector3i, rot := -1) -> bool:
	var from: ObjectDef = defs.get(from_id)
	var to: ObjectDef = defs.get(to_id)
	if from == null or to == null:
		return false
	var inst := from.find_child(inst_id)
	if inst == null or would_cycle(to_id, inst.def_id):
		return false
	begin_step("Move into another object")
	_record_children(from)
	_record_children(to)
	from.children.erase(inst)
	inst.offset = offset
	if rot >= 0:
		inst.rot = posmod(rot, 4)
	to.children.append(inst)
	end_step()
	_bounds_cache.clear()
	structure_changed.emit()
	library_changed.emit()
	return true


## Moves the instance at `path` into the object at `to_path`, keeping it
## where it is in the world (its offset and rotation are recomputed for the
## new parent's space). `to_path` is one placement of the target object, so
## the move is measured against that copy. Returns "" on success or a reason
## it was refused.
func reparent_path(path: PackedStringArray, to_path: PackedStringArray) -> String:
	if path.is_empty():
		return "the world itself can't be moved"
	var inst := instance_at(path)
	var from := def_at(path.slice(0, path.size() - 1))
	var to := def_at(to_path)
	if inst == null or from == null or to == null:
		return "that object no longer exists"
	if path.slice(0, path.size() - 1) == to_path:
		return "it's already there"
	if would_cycle(to.id, inst.def_id):
		return "%s is part of %s" % [to.name, defs[inst.def_id].name]
	var local := path_transform(to_path).affine_inverse() * path_transform(path)
	var rot := ObjectInstance.quarter_turns_of(local.basis)
	if rot < 0:
		return "the new parent is rotated in a way the object can't follow"
	var ok := reparent_instance(from.id, inst.id, to.id, Vector3i(local.origin.round()), rot)
	return "" if ok else "the move was refused"


func can_undo() -> bool:
	return not _undo.is_empty() and _depth == 0


func can_redo() -> bool:
	return not _redo.is_empty() and _depth == 0


func undo() -> String:
	if not can_undo():
		return ""
	var step: Dictionary = _undo.pop_back()
	_redo.append(_apply(step))
	return step.label


func redo() -> String:
	if not can_redo():
		return ""
	var step: Dictionary = _redo.pop_back()
	_undo.append(_apply(step))
	return step.label


## Restores a recorded state and returns the inverse step.
func _apply(step: Dictionary) -> Dictionary:
	var inv := {"label": step.label, "chunks": {}, "children": {}}
	for def_id in step.chunks:
		var def: ObjectDef = defs.get(def_id)
		if def == null:
			continue
		var inv_chunks := {}
		var affected := {}
		for key in step.chunks[def_id]:
			inv_chunks[key] = def.grid.get_packed(key)
			def.grid.set_packed(key, step.chunks[def_id][key])
			affected[key] = true
			for n in [Vector3i.LEFT, Vector3i.RIGHT, Vector3i.UP, Vector3i.DOWN, Vector3i.FORWARD, Vector3i.BACK]:
				affected[key + n] = true
		inv.chunks[def_id] = inv_chunks
		_clean.erase(def_id)
		voxels_changed.emit(def_id, affected.keys())
	for def_id in step.children:
		var def: ObjectDef = defs.get(def_id)
		if def == null:
			continue
		inv.children[def_id] = def.copy_children()
		_clean.erase(def_id)
		var restored := []
		for inst in step.children[def_id]:
			restored.append(inst.copy())
		def.children = restored
	_bounds_cache.clear()
	if not step.children.is_empty():
		structure_changed.emit()
		library_changed.emit()
	return inv


# --- Persistence -----------------------------------------------------------

func manifest() -> Dictionary:
	var pal := []
	for c in palette:
		pal.append(c.to_html(false))
	return {
		"format": FORMAT,
		"version": VERSION,
		"engine": "godot-%s" % Engine.get_version_info().string,
		"title": title,
		"units": {"min_block_m": voxel_size, "up": "+y", "handedness": "right"},
		"root": root_id,
		"palette": pal,
		"objects_file": OBJECTS_FILE,
		"environment": environment,
	}


## Saves as a directory: manifest.json, objects.json (one line per object)
## and a content-addressed chunk pack (see docs/file-format.md). Saving again
## to the same directory regenerates only changed objects' entries and
## appends only new chunks. objects.json names its pack and is replaced
## atomically, so it is the commit point of a save.
func save_dir(path: String) -> Error:
	var err := DirAccess.make_dir_recursive_absolute(path)
	if err != OK:
		return err
	var full := path != _saved_path or _pack_name == ""
	if full:
		_clean.clear()
		_meta_text.clear()
		_def_hashes.clear()
		_pack_sizes.clear()
		_pack_name = _next_pack_name(path)
	last_save_written = 0
	var ids := defs.keys()
	ids.sort()
	var new_chunks := {}
	for id in ids:
		if _clean.has(id) and _meta_text.has(id):
			continue
		var def: ObjectDef = defs[id]
		var refs := []
		var hashes := []
		for key in def.sorted_keys():
			var packed: PackedByteArray = def.grid.get_packed(key)
			var h := ChunkPack.hash_of(packed)
			refs.append([key, h, def.grid.counts[key]])
			hashes.append(h)
			if not _pack_sizes.has(h):
				new_chunks[h] = packed
		_def_hashes[id] = hashes
		_meta_text[id] = JSON.stringify(def.to_meta(refs), "", true)
		last_save_written += 1
	for id in _meta_text.keys():
		if not defs.has(id):
			_meta_text.erase(id)
			_def_hashes.erase(id)

	var old_pack := ""
	var pack_path := path.path_join(_pack_name)
	if full:
		err = ChunkPack.write(pack_path, new_chunks)
		_pack_sizes = _sizes_of(new_chunks)
	elif _garbage_exceeds_live():
		old_pack = _pack_name
		_pack_name = _next_pack_name(path)
		pack_path = path.path_join(_pack_name)
		var live := _live_chunks()
		err = ChunkPack.write(pack_path, live)
		_pack_sizes = _sizes_of(live)
	else:
		err = ChunkPack.append(pack_path, new_chunks)
		_pack_sizes.merge(_sizes_of(new_chunks))
	if err != OK:
		return err

	var lines := PackedStringArray()
	for id in ids:
		lines.append(_meta_text[id])
	var header := JSON.stringify({"format": "ourcraft.objects", "version": 1, "chunks_file": _pack_name}, "", true)
	err = _write_text(path.path_join(OBJECTS_FILE),
		header.trim_suffix("}") + ', "objects": [\n' + ",\n".join(lines) + "\n]}\n")
	if err != OK:
		return err
	err = _write_json(path.path_join("manifest.json"), manifest())
	if err != OK:
		return err
	if old_pack != "":
		DirAccess.remove_absolute(path.path_join(old_pack))
	if full:
		_remove_stale_files(path)
	for id in ids:
		_clean[id] = true
	_saved_path = path
	_removed_since_save = false
	return OK


func _garbage_exceeds_live() -> bool:
	var live := {}
	for hashes in _def_hashes.values():
		for h in hashes:
			live[h] = true
	var live_bytes := 0
	var garbage := 0
	for h in _pack_sizes:
		if live.has(h):
			live_bytes += _pack_sizes[h]
		else:
			garbage += _pack_sizes[h]
	return garbage > live_bytes and garbage > compact_min_garbage


## hash -> compressed bytes for every chunk referenced by an object.
func _live_chunks() -> Dictionary:
	var out := {}
	for id in _def_hashes:
		var def: ObjectDef = defs[id]
		var keys := def.sorted_keys()
		var hashes: Array = _def_hashes[id]
		for k in keys.size():
			out[hashes[k]] = def.grid.get_packed(keys[k])
	return out


static func _sizes_of(chunks: Dictionary) -> Dictionary:
	var out := {}
	for h in chunks:
		out[h] = ChunkPack.entry_size(chunks[h])
	return out


## A chunk pack name not used in the folder yet, so writing a new pack never
## touches the one the current objects.json refers to.
static func _next_pack_name(path: String) -> String:
	var n := 0
	for f in DirAccess.get_files_at(path):
		if f.begins_with("chunks-") and f.ends_with(".pack"):
			n = maxi(n, f.trim_prefix("chunks-").trim_suffix(".pack").to_int())
	return "chunks-%d.pack" % (n + 1)


## After a full save: older packs, temp files and version 1 object files.
func _remove_stale_files(path: String) -> void:
	for f in DirAccess.get_files_at(path):
		if (f.begins_with("chunks-") and f.ends_with(".pack") and f != _pack_name) or f.ends_with(".tmp"):
			DirAccess.remove_absolute(path.path_join(f))
	var legacy := path.path_join("objects")
	if DirAccess.dir_exists_absolute(legacy):
		for f in DirAccess.get_files_at(legacy):
			if f.ends_with(".json") or f.ends_with(".tmp"):
				DirAccess.remove_absolute(legacy.path_join(f))
		DirAccess.remove_absolute(legacy)


static func load_dir(path: String) -> Project:
	var m = _read_json(path.path_join("manifest.json"))
	if not (m is Dictionary) or m.get("format") != FORMAT:
		return null
	var version := int(m.get("version", 0))
	if version > VERSION:
		push_error("Project was saved by a newer Ourcraft")
		return null
	var p := Project.new()
	p.title = str(m.get("title", "Untitled world"))
	p.voxel_size = float(m.get("units", {}).get("min_block_m", 0.01))
	var pal: Array = m.get("palette", [])
	if not pal.is_empty():
		p.palette = []
		for h in pal:
			p.palette.append(Color(str(h)))
	p.root_id = str(m.get("root", ""))
	var env = m.get("environment", {})
	p.environment = env if env is Dictionary else {}
	var ok := p._load_objects_v2(path) if version >= 2 else p._load_objects_v1(path, m)
	if not ok or not p.defs.has(p.root_id):
		return null
	var changed := p._drop_dangling()
	if version >= 2:
		p._saved_path = path
		for id in p.defs:
			if not changed.has(id) and p._meta_text.has(id):
				p._clean[id] = true
	return p


## Version 1: one JSON file per object. The next save converts the folder.
func _load_objects_v1(path: String, m: Dictionary) -> bool:
	for id in m.get("objects", []):
		var d = _read_json(path.path_join("objects").path_join(str(id) + ".json"))
		if d is Dictionary:
			var def := ObjectDef.from_dict(d)
			defs[def.id] = def
	return true


## Version 2: objects.json plus the chunk pack it names. Entries are read
## one line at a time so each object's text can be reused by the next save;
## a hand-edited (reformatted) file is parsed as a whole instead.
func _load_objects_v2(path: String) -> bool:
	var text := FileAccess.get_file_as_string(path.path_join(OBJECTS_FILE))
	if text == "":
		return false
	var lines := text.split("\n", false)
	var header = null
	var entries := []
	var texts := []
	if lines.size() >= 2 and lines[0].ends_with("[") and lines[-1] == "]}":
		header = JSON.parse_string(lines[0] + "]}")
		for k in range(1, lines.size() - 1):
			var line := lines[k].trim_suffix(",")
			var e = JSON.parse_string(line)
			if not (e is Dictionary):
				header = null
				break
			entries.append(e)
			texts.append(line)
	if not (header is Dictionary):
		var whole = JSON.parse_string(text)
		if not (whole is Dictionary):
			return false
		header = whole
		entries = whole.get("objects", [])
		texts = []
	_pack_name = str(header.get("chunks_file", ""))
	var pack = ChunkPack.read(path.path_join(_pack_name))
	if pack == null:
		push_error("Missing or unreadable chunk pack %s" % _pack_name)
		pack = {}
	_pack_sizes = _sizes_of(pack)
	for k in entries.size():
		var e: Dictionary = entries[k]
		var made := ObjectDef.from_meta(e, pack)
		var def: ObjectDef = made[0]
		defs[def.id] = def
		_def_hashes[def.id] = made[1]
		# Keep the entry text only if every chunk loaded, so a damaged object
		# gets rewritten from what was recovered.
		if k < texts.size() and made[1].size() == e.get("chunks", []).size():
			_meta_text[def.id] = texts[k]
	return true


## Removes instances that reference missing objects; returns the ids of
## objects whose child lists changed.
func _drop_dangling() -> Dictionary:
	var changed := {}
	for def in defs.values():
		var kept: Array = def.children.filter(func(i): return defs.has(i.def_id))
		if kept.size() != def.children.size():
			def.children = kept
			changed[def.id] = true
	return changed


## Collects an object and all objects nested in it.
func dependencies(def_id: String) -> Array:
	var seen := {}
	var stack := [def_id]
	while not stack.is_empty():
		var id: String = stack.pop_back()
		if seen.has(id) or not defs.has(id):
			continue
		seen[id] = true
		for inst in defs[id].children:
			stack.append(inst.def_id)
	var out := seen.keys()
	out.sort()
	return out


## Writes one object (with its nested objects) to a single portable file.
func export_object(def_id: String, file_path: String) -> Error:
	var objects := []
	for id in dependencies(def_id):
		objects.append(defs[id].to_dict())
	return _write_json(file_path, {
		"format": "ourcraft.bundle",
		"version": VERSION,
		"root": def_id,
		"min_block_m": voxel_size,
		"objects": objects,
	})


## Imports a bundle into the library. Objects whose id already exists are
## kept as they are. Returns the bundle's root object id, or "" on failure.
func import_bundle(file_path: String) -> String:
	var b = _read_json(file_path)
	if not (b is Dictionary) or b.get("format") != "ourcraft.bundle":
		return ""
	for d in b.get("objects", []):
		var def := ObjectDef.from_dict(d)
		if not defs.has(def.id):
			defs[def.id] = def
	_drop_dangling()
	library_changed.emit()
	var root_obj := str(b.get("root", ""))
	return root_obj if defs.has(root_obj) else ""


static func _write_json(file_path: String, data) -> Error:
	return _write_text(file_path, JSON.stringify(data, "  ", true))


## Writes text, replacing an existing file atomically (write a temp file,
## then rename) so an interrupted save never leaves a half-written file. New
## files are written in place: there's no earlier version to protect.
static func _write_text(file_path: String, text: String) -> Error:
	var exists := FileAccess.file_exists(file_path)
	var target := file_path + ".tmp" if exists else file_path
	var f := FileAccess.open(target, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(text)
	f.close()
	if not exists:
		return OK
	return DirAccess.rename_absolute(target, file_path)


static func _read_json(file_path: String):
	if not FileAccess.file_exists(file_path):
		return null
	return JSON.parse_string(FileAccess.get_file_as_string(file_path))
