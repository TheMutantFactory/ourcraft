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
const VERSION := 1
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
## Physical size of the minimum block, in metres.
var voxel_size := 0.01
var palette: Array = DEFAULT_PALETTE.duplicate()
var defs: Dictionary = {}
var root_id := ""

var _undo: Array = []
var _redo: Array = []
var _step = null
var _depth := 0
var _bounds_cache: Dictionary = {}
## Saving only rewrites objects changed since the last save to the same
## directory: _clean holds ids whose file at _saved_path is up to date.
var _saved_path := ""
var _clean: Dictionary = {}
var _removed_since_save := false
## Number of object files the last save_dir wrote (for tests and tools).
var last_save_written := 0


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

func begin_step(label: String) -> void:
	if _depth == 0:
		_step = {"label": label, "chunks": {}, "children": {}}
	_depth += 1


func end_step() -> void:
	_depth -= 1
	if _depth > 0:
		return
	if not (_step.chunks.is_empty() and _step.children.is_empty()):
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
	var ids := defs.keys()
	ids.sort()
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
		"objects": ids,
	}


## Saves as a directory: manifest.json plus objects/<id>.json. Saving again
## to the same directory only rewrites objects that changed. Objects are
## written before the manifest, so an interrupted save leaves the previous
## manifest pointing at complete files.
func save_dir(path: String) -> Error:
	var obj_dir := path.path_join("objects")
	var err := DirAccess.make_dir_recursive_absolute(obj_dir)
	if err != OK:
		return err
	var full := path != _saved_path
	if full:
		_clean.clear()
	last_save_written = 0
	for def in defs.values():
		if _clean.has(def.id):
			continue
		err = _write_json(obj_dir.path_join(def.id + ".json"), def.to_dict())
		if err != OK:
			return err
		_clean[def.id] = true
		last_save_written += 1
	err = _write_json(path.path_join("manifest.json"), manifest())
	if err != OK:
		return err
	if full or _removed_since_save:
		var dir := DirAccess.open(obj_dir)
		if dir != null:
			for f in dir.get_files():
				if f.ends_with(".json") and not defs.has(f.get_basename()):
					dir.remove(f)
	_saved_path = path
	_removed_since_save = false
	return OK


static func load_dir(path: String) -> Project:
	var m = _read_json(path.path_join("manifest.json"))
	if not (m is Dictionary) or m.get("format") != FORMAT:
		return null
	if int(m.get("version", 0)) > VERSION:
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
	for id in m.get("objects", []):
		var d = _read_json(path.path_join("objects").path_join(str(id) + ".json"))
		if d is Dictionary:
			var def := ObjectDef.from_dict(d)
			p.defs[def.id] = def
	p.root_id = str(m.get("root", ""))
	if not p.defs.has(p.root_id):
		return null
	p._drop_dangling()
	p._saved_path = path
	for id in p.defs:
		p._clean[id] = true
	return p


## Removes instances that reference missing objects.
func _drop_dangling() -> void:
	for def in defs.values():
		def.children = def.children.filter(func(i): return defs.has(i.def_id))


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


## Writes JSON, replacing an existing file atomically (write a temp file,
## then rename) so an interrupted save never leaves a half-written file. New
## files are written in place: there's no earlier version to protect, and
## the manifest isn't updated to reference them until they're complete.
static func _write_json(file_path: String, data) -> Error:
	var exists := FileAccess.file_exists(file_path)
	var target := file_path + ".tmp" if exists else file_path
	var f := FileAccess.open(target, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(data, "  ", true))
	f.close()
	if not exists:
		return OK
	return DirAccess.rename_absolute(target, file_path)


static func _read_json(file_path: String):
	if not FileAccess.file_exists(file_path):
		return null
	return JSON.parse_string(FileAccess.get_file_as_string(file_path))
