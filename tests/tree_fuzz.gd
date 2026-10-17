class_name TreeFuzz
extends RefCounted
## Seeded random object-tree manipulation with invariant checks after every
## step. Used by tests/fuzz.gd (tools/fuzz.sh) and by the synthetic tree
## generator to scramble worlds.
##
## Checks: references resolve, no cycles, refusals match an independent
## cycle check, instance ids are unique, cached bounds and usage counts
## match a fresh recompute, chunk counts match their data, undo returns the
## previous state exactly and redo the next, save/load and incremental saves
## reproduce the project, bundles round-trip, and (optionally) a live
## WorldView's placements, drawing and collision match the tree.

const BRUSH_SIZES := [1, 3, 8, 20, 40]

var rng := RandomNumberGenerator.new()
var p: Project
var words: Array = []
var view: WorldView
var save_dir := ""
var steps := 0
## Human-readable record of every step, for replaying a failure.
var history := PackedStringArray()
var failures := PackedStringArray()
## Operation -> number of times it ran (and changed something).
var stats := {}
## Run the invariant checks after each step. They rescan the whole project,
## so scrambling a large world is much faster with this off.
var checks := true

var _weights := [
	["add", 14], ["remove", 6], ["move", 8], ["rotate", 3], ["retarget", 4],
	["reparent", 8], ["keep", 5], ["unique", 4], ["create", 5], ["delete", 2], ["rename", 2],
	["unit", 1], ["edit", 12], ["undo", 8], ["redo", 4],
]


func _init(seed: int, project: Project = null, word_list: Array = []) -> void:
	rng.seed = seed
	words = word_list
	p = project if project != null else Project.create_empty(0.01)
	if project == null:
		for i in 6:
			_create_with_voxels()


# --- Driving ---------------------------------------------------------------

## Runs one random operation and checks invariants. Returns false once a
## check has failed.
func step() -> bool:
	steps += 1
	var op := _pick_op()
	var undoable := op in ["add", "remove", "move", "rotate", "retarget", "reparent", "keep", "edit"]
	var pre := _snapshot() if undoable and checks else ""
	var undo_before = _last_undo()
	var note: String = call("_op_" + op)
	if note == "":
		return true
	history.append("%d %s: %s" % [steps, op, note])
	stats[op] = int(stats.get(op, 0)) + 1
	if not checks:
		return true
	_check_bounds_cache()
	if undoable:
		_check_undo_symmetry(op, pre, undo_before)
	_check_invariants()
	return failures.is_empty()


func _pick_op() -> String:
	var total := 0
	for w in _weights:
		total += w[1]
	var r := rng.randi_range(0, total - 1)
	for w in _weights:
		r -= w[1]
		if r < 0:
			return w[0]
	return "edit"


func fail(msg: String) -> void:
	failures.append("step %d: %s" % [steps, msg])


# --- Operations (each returns a description, or "" if it didn't apply) ------

func _op_add() -> String:
	var parent := _random_def()
	var child := _random_def()
	var expect_ok := not _reaches(child.id, parent.id)
	var inst := p.add_instance(parent.id, child.id, _random_offset(parent), rng.randi_range(0, 3))
	if (inst != null) != expect_ok:
		fail("add %s into %s: got %s, expected %s" % [child.name, parent.name, inst != null, expect_ok])
	return "%s into %s (%s)" % [child.name, parent.name, "ok" if inst != null else "refused"]


func _op_remove() -> String:
	var parent := _random_def_with_children()
	if parent == null:
		return ""
	var inst: ObjectInstance = parent.children[rng.randi_range(0, parent.children.size() - 1)]
	p.remove_instance(parent.id, inst.id)
	if parent.find_child(inst.id) != null:
		fail("remove left instance %s in %s" % [inst.id, parent.name])
	return "%s from %s" % [p.defs[inst.def_id].name if p.defs.has(inst.def_id) else inst.def_id, parent.name]


func _op_move() -> String:
	var parent := _random_def_with_children()
	if parent == null:
		return ""
	var inst: ObjectInstance = parent.children[rng.randi_range(0, parent.children.size() - 1)]
	var offset := _random_offset(parent)
	p.set_instance_transform(parent.id, inst.id, offset, inst.rot)
	return "%s in %s to %s" % [inst.id, parent.name, offset]


func _op_rotate() -> String:
	var parent := _random_def_with_children()
	if parent == null:
		return ""
	var inst: ObjectInstance = parent.children[rng.randi_range(0, parent.children.size() - 1)]
	p.set_instance_transform(parent.id, inst.id, inst.offset, inst.rot + rng.randi_range(1, 3))
	return "%s in %s to rot %d" % [inst.id, parent.name, inst.rot]


func _op_retarget() -> String:
	var parent := _random_def_with_children()
	if parent == null:
		return ""
	var inst: ObjectInstance = parent.children[rng.randi_range(0, parent.children.size() - 1)]
	var target := _random_def()
	var expect_ok := not _reaches(target.id, parent.id)
	var before := inst.def_id
	p.set_instance_def(parent.id, inst.id, target.id)
	var changed := inst.def_id == target.id and before != target.id
	if expect_ok and inst.def_id != target.id:
		fail("retarget to %s refused but allowed by cycle check" % target.name)
	if not expect_ok and inst.def_id == target.id and before != target.id:
		fail("retarget to %s made a cycle" % target.name)
	return "%s in %s to %s (%s)" % [inst.id, parent.name, target.name, "ok" if changed or before == target.id else "refused"]


func _op_reparent() -> String:
	var from := _random_def_with_children()
	if from == null:
		return ""
	var inst: ObjectInstance = from.children[rng.randi_range(0, from.children.size() - 1)]
	var to := _random_def()
	var expect_ok := not _reaches(inst.def_id, to.id)
	var ok := p.reparent_instance(from.id, inst.id, to.id, _random_offset(to))
	if ok != expect_ok:
		fail("reparent %s from %s to %s: got %s, expected %s" % [inst.id, from.name, to.name, ok, expect_ok])
	if ok and (to.find_child(inst.id) == null or (from != to and from.find_child(inst.id) != null)):
		fail("reparent left %s in the wrong place" % inst.id)
	return "%s from %s to %s (%s)" % [inst.id, from.name, to.name, "ok" if ok else "refused"]


## Like dragging in the outline: move a placed instance into another placed
## object, keeping its world position.
func _op_keep() -> String:
	var path := _random_path()
	var to_path := _random_path()
	if path.is_empty():
		return ""
	var world := p.path_transform(path)
	var inst := p.instance_at(path)
	var expect_ok := to_path != path.slice(0, path.size() - 1) and not _reaches(inst.def_id, p.def_at(to_path).id)
	var why := p.reparent_path(path, to_path)
	if (why == "") != expect_ok:
		fail("keep-in-place move %s -> %s: got '%s', expected ok=%s" % ["/".join(path), "/".join(to_path), why, expect_ok])
	if why == "":
		var moved := to_path.duplicate()
		moved.append(inst.id)
		if not p.path_transform(moved).is_equal_approx(world):
			fail("keep-in-place move changed the world position")
	return "%s -> %s (%s)" % [inst.id, p.def_at(to_path).name, "ok" if why == "" else why]


func _last_undo():
	return null if p._undo.is_empty() else p._undo.back()


## A random path from the world down the tree (possibly the world itself).
func _random_path() -> PackedStringArray:
	var path := PackedStringArray()
	var def := p.root()
	while not def.children.is_empty() and path.size() < Project.MAX_DEPTH and rng.randf() < 0.7:
		var inst: ObjectInstance = def.children[rng.randi_range(0, def.children.size() - 1)]
		if not p.defs.has(inst.def_id):
			break
		path.append(inst.id)
		def = p.defs[inst.def_id]
	return path


## Like the game's "make unique": fork the object (not undoable), then point
## the instance at the fork (undoable).
func _op_unique() -> String:
	var parent := _random_def_with_children()
	if parent == null:
		return ""
	var inst: ObjectInstance = parent.children[rng.randi_range(0, parent.children.size() - 1)]
	var fork := p.fork_def(inst.def_id)
	var pre := _snapshot() if checks else ""
	var undo_before = _last_undo()
	p.set_instance_def(parent.id, inst.id, fork.id)
	if inst.def_id != fork.id:
		fail("make unique didn't take")
	if checks:
		_check_bounds_cache()
		_check_undo_symmetry("unique", pre, undo_before)
	return "%s in %s -> %s" % [inst.id, parent.name, fork.name]


func _op_create() -> String:
	var def := _create_with_voxels()
	var parent := _random_def()
	p.add_instance(parent.id, def.id, _random_offset(parent), 0)
	return "%s under %s" % [def.name, parent.name]


func _op_delete() -> String:
	var candidates := p.defs.keys().filter(func(id): return id != p.root_id)
	if candidates.size() < 3:
		return ""
	var id: String = candidates[rng.randi_range(0, candidates.size() - 1)]
	var nm: String = p.defs[id].name
	p.delete_def(id)
	for def in p.defs.values():
		for inst in def.children:
			if inst.def_id == id:
				fail("deleted %s still referenced by %s" % [nm, def.name])
	return nm


func _op_rename() -> String:
	var def := _random_def()
	var names := ["", "  ", "x", _word(), _word() + " " + _word(), "naïve café", "a/b'c-d", "Z".repeat(80)]
	var n: String = names[rng.randi_range(0, names.size() - 1)]
	var before := def.name
	p.rename_def(def.id, n)
	if n.strip_edges() == "" and def.name != before:
		fail("blank rename changed the name")
	return "%s -> %s" % [before, def.name]


func _op_unit() -> String:
	var def := _random_def()
	var u: int = [1, 2, 5, 10][rng.randi_range(0, 3)]
	p.set_def_unit(def.id, u)
	return "%s unit %d" % [def.name, u]


func _op_edit() -> String:
	var def := _random_def()
	var s: int = BRUSH_SIZES[rng.randi_range(0, BRUSH_SIZES.size() - 1)]
	var a := Vector3i(rng.randi_range(-40, 60), rng.randi_range(-10, 40), rng.randi_range(-40, 60))
	var size := Vector3i(rng.randi_range(1, s), rng.randi_range(1, s), rng.randi_range(1, s))
	var value := 0 if rng.randf() < 0.35 else rng.randi_range(1, 10)
	p.edit_box(def.id, a, a + size, value)
	return "%s %s+%s = %d" % [def.name, a, size, value]


func _op_undo() -> String:
	return "undid %s" % p.undo() if p.can_undo() else ""


func _op_redo() -> String:
	return "redid %s" % p.redo() if p.can_redo() else ""


# --- Checks ------------------------------------------------------------------

## Cached bounds match a fresh computation; then re-fill the cache so the
## next mutation has to invalidate it. Runs straight after each op, before
## undo/redo (which clear the cache and would hide a stale one).
func _check_bounds_cache() -> void:
	var cached := {}
	for id in p.defs:
		cached[id] = p.def_bounds(id)
	p._bounds_cache.clear()
	for id in p.defs:
		var fresh := p.def_bounds(id)
		if not fresh.is_equal_approx(cached[id]):
			fail("stale bounds cache for %s: %s vs %s" % [p.defs[id].name, cached[id], fresh])


## Undo must restore exactly the state before the op, redo exactly the
## state after it. Ops that changed nothing must not add history.
func _check_undo_symmetry(op: String, pre: String, undo_before) -> void:
	var post := _snapshot()
	# Compare the newest entry, not the length: once history is full,
	# recording a step drops the oldest and the length stays the same.
	if is_same(_last_undo(), undo_before):
		if post != pre:
			fail("%s changed the project without recording undo" % op)
		return
	p.undo()
	if _snapshot() != pre:
		fail("undo of %s didn't restore the previous state" % op)
	p.redo()
	if _snapshot() != post:
		fail("redo of %s didn't restore the changed state" % op)


func _check_invariants() -> void:
	if not p.defs.has(p.root_id):
		fail("root object missing")
		return
	# References resolve and instance ids are unique.
	var seen := {}
	for def in p.defs.values():
		for inst in def.children:
			if not p.defs.has(inst.def_id):
				fail("%s has an instance of missing object %s" % [def.name, inst.def_id])
			if seen.has(inst.id):
				fail("instance id %s used in both %s and %s" % [inst.id, seen[inst.id], def.name])
			seen[inst.id] = def.name
			if inst.rot < 0 or inst.rot > 3:
				fail("rotation %d out of range" % inst.rot)
	# No cycles.
	var state := {}
	for id in p.defs:
		if _has_cycle(id, state):
			fail("cycle through %s" % p.defs[id].name)
			break
	# Usage counts.
	var naive := {}
	for def in p.defs.values():
		for inst in def.children:
			naive[inst.def_id] = int(naive.get(inst.def_id, 0)) + 1
	if p.usage_counts() != naive:
		fail("usage_counts disagrees with a naive count")
	_check_bounds_cache()
	# Chunk counts match their data (sampled).
	var ids := p.defs.keys()
	for k in 3:
		var def: ObjectDef = p.defs[ids[rng.randi_range(0, ids.size() - 1)]]
		for key in def.grid.keys():
			var data = def.grid.get_chunk(key)
			var n: int = 0 if data == null else VoxelGrid.VOLUME - data.count(0)
			if n == 0 or n != def.grid.counts[key]:
				fail("chunk %s of %s: count %d, data %d" % [key, def.name, def.grid.counts.get(key, -1), n])
	if p._undo.size() > Project.MAX_HISTORY:
		fail("undo history grew past its limit")


## Saves (incrementally, to the same folder), reloads, and compares; also
## checks that a full save into a fresh folder writes the same objects.
func check_save_load(fresh_dir: String) -> void:
	if save_dir == "":
		return
	if p.save_dir(save_dir) != OK:
		fail("save failed")
		return
	var q := Project.load_dir(save_dir)
	if q == null:
		fail("saved project didn't load")
		return
	if _snapshot_of(q) != _snapshot():
		fail("incrementally saved project loads differently")
	_clear_dir(fresh_dir)
	var r := Project.load_dir(save_dir)
	r.save_dir(fresh_dir)
	var a := _objects_lines(save_dir)
	var b := _objects_lines(fresh_dir)
	if a != b:
		fail("incremental objects.json differs from a fresh save")


## Exports a random object and imports it into an empty project.
func check_bundle(file: String) -> void:
	var def := _random_def()
	if p.export_object(def.id, file) != OK:
		fail("export failed")
		return
	var q := Project.create_empty(0.01)
	var id := q.import_bundle(file)
	if id != def.id:
		fail("bundle import returned %s, expected %s" % [id, def.id])
		return
	for dep in p.dependencies(def.id):
		if not q.defs.has(dep) or JSON.stringify(q.defs[dep].to_dict()) != JSON.stringify(p.defs[dep].to_dict()):
			fail("bundle of %s didn't round-trip object %s" % [def.name, dep])
			return


## Compares a live WorldView with the tree.
func check_view() -> void:
	if view == null:
		return
	view.flush()
	var expected := _expand(p.root_id, PackedStringArray(), 0, [])
	var got := {}
	for pl in view._placements:
		got["/".join(pl.path)] = pl.def_id
		if not p.is_valid_path(pl.path) or p.def_at(pl.path).id != pl.def_id:
			fail("view placement %s doesn't match the tree" % "/".join(pl.path))
			return
	if got.size() != expected.size():
		fail("view has %d placements, tree has %d" % [got.size(), expected.size()])
		return
	# Every placement is either drawn live or baked, never both.
	var drawn := view._renderer.drawn_placements()
	var baked := view._baker.baked_placements()
	var all := {}
	for i in drawn + baked:
		if all.has(i):
			fail("placement %d drawn twice" % i)
			return
		all[i] = true
	if all.size() != view._placements.size():
		fail("%d of %d placements drawn" % [all.size(), view._placements.size()])
	# Every allocated chunk of a placed object has a mesh entry, and no entry
	# outlives its chunk.
	var placed := {}
	for pl in view._placements:
		placed[pl.def_id] = true
	for def in p.defs.values():
		var entries: Dictionary = view._meshes.get(def.id, {})
		for key in def.grid.keys():
			if not placed.has(def.id):
				break
			if not entries.has(key):
				fail("chunk %s of %s has no mesh entry" % [key, def.name])
				return
		for key in entries:
			if not def.grid.has_chunk(key):
				fail("mesh entry %s of %s outlived its chunk" % [key, def.name])
				return
	# Collision near a random placement points at real objects.
	if not view._placements.is_empty():
		var pl: Dictionary = view._placements[rng.randi_range(0, view._placements.size() - 1)]
		view.set_focus(pl.xform.origin, 3.0)
		view.collision.sync(view._meshes)
		for rid in view.collision._owner:
			var info := view.collision.info(rid)
			if not p.is_valid_path(info.path):
				fail("collision body for a stale path")
				return


# --- Helpers -----------------------------------------------------------------

## Whether `to` is reachable from `from` through children (or is it).
func _reaches(from: String, to: String) -> bool:
	if from == to:
		return true
	var stack := [from]
	var seen := {}
	while not stack.is_empty():
		var id: String = stack.pop_back()
		if seen.has(id) or not p.defs.has(id):
			continue
		seen[id] = true
		for inst in p.defs[id].children:
			if inst.def_id == to:
				return true
			stack.append(inst.def_id)
	return false


func _has_cycle(id: String, state: Dictionary) -> bool:
	if state.get(id) == 1:
		return true
	if state.get(id) == 2 or not p.defs.has(id):
		return false
	state[id] = 1
	for inst in p.defs[id].children:
		if _has_cycle(inst.def_id, state):
			return true
	state[id] = 2
	return false


## Every path the renderer should draw, respecting the depth limit.
func _expand(def_id: String, path: PackedStringArray, depth: int, out: Array) -> Array:
	out.append(path)
	if depth >= Project.MAX_DEPTH:
		return out
	for inst in p.defs[def_id].children:
		var c := path.duplicate()
		c.append(inst.id)
		_expand(inst.def_id, c, depth + 1, out)
	return out


func _snapshot() -> String:
	return _snapshot_of(p)


static func _snapshot_of(q: Project) -> String:
	var ids := q.defs.keys()
	ids.sort()
	var parts := PackedStringArray([q.root_id])
	for id in ids:
		parts.append(JSON.stringify(q.defs[id].to_dict(), "", true))
	return "\n".join(parts)


static func _objects_lines(dir: String) -> PackedStringArray:
	var lines := FileAccess.get_file_as_string(dir.path_join("objects.json")).split("\n", false)
	return lines.slice(1) # the header names the pack, which may differ


static func _clear_dir(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))


func _random_def() -> ObjectDef:
	var ids := p.defs.keys()
	return p.defs[ids[rng.randi_range(0, ids.size() - 1)]]


func _random_def_with_children() -> ObjectDef:
	var withc := p.defs.values().filter(func(d): return not d.children.is_empty())
	return null if withc.is_empty() else withc[rng.randi_range(0, withc.size() - 1)]


func _random_offset(parent: ObjectDef) -> Vector3i:
	# Mostly near the parent, sometimes negative or far away.
	var span := 200 if rng.randf() < 0.9 else 100000
	return Vector3i(rng.randi_range(-span, span), rng.randi_range(-span / 4, span / 4), rng.randi_range(-span, span))


func _word() -> String:
	if not words.is_empty():
		return str(words[rng.randi_range(0, words.size() - 1)])
	const SYL := ["ka", "lo", "mi", "ren", "to", "va", "shi", "pu", "dor", "el", "an", "bri"]
	var w := ""
	for i in rng.randi_range(1, 3):
		w += SYL[rng.randi_range(0, SYL.size() - 1)]
	return w


func _create_with_voxels() -> ObjectDef:
	var def := p.create_def(p.unique_name(_word()), [1, 2, 5][rng.randi_range(0, 2)])
	BlockFont.write(def.grid, def.name, rng.randi_range(1, 10))
	# Written straight into the grid, so announce it like fork_def does.
	p.voxels_changed.emit(def.id, def.grid.keys())
	return def
