extends SceneTree
## Builds a synthetic deep-and-wide object tree from random words, written
## flat on the ground like an org chart (press L in the game for the
## relationship lines). Optionally scrambles it with random tree edits.
##
##   tools/synthetic-world.sh [--seed=1] [--depth=14] [--width=5] [--roots=12]
##       [--share=0.2] [--max=6000] [--mutations=0] [--check]
##       [--out=user://projects/synthetic.ourcraft]
## --check runs the fuzzer's invariant checks after every edit (slow on
## large worlds).
##
## Besides the random trees it adds corner cases: a "deep" chain of 40
## levels (deeper than Project.MAX_DEPTH, so only 33 render), a "wide" object
## with 300 parts, and an "empty" object with no voxels.

const UNIT := 2
## Vertical gap between a word and the row of its parts, in blocks.
const ROW_GAP := 8
const COLUMN_GAP := 4
## Rows of parts wrap at this width (smallest-block units, 30 m).
const MAX_ROW := 3000

var rng := RandomNumberGenerator.new()
var project: Project
var words: Array = []
var footprint := {}  # def id -> {xmin, xmax, zmax}
var depth_of := {}   # def id -> generation level


func _init() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else ""
	rng.seed = int(args.get("seed", "1"))
	var max_depth := int(args.get("depth", "14"))
	var width := int(args.get("width", "5"))
	var roots := int(args.get("roots", "12"))
	var share := float(args.get("share", "0.2"))
	var max_objects := int(args.get("max", "6000"))
	var mutations := int(args.get("mutations", "0"))
	var out := str(args.get("out", "user://projects/synthetic.ourcraft"))
	if out.begins_with("user://"):
		out = ProjectSettings.globalize_path(out)
	_load_words()

	project = Project.create_empty(0.01)
	project.title = "Synthetic tree (seed %d)" % rng.seed
	var world := project.root()

	# Random trees, generated level by level. A part may reuse an object from
	# the level below it (shared, instanced), which can't form a cycle.
	var levels := [[]]
	for r in roots:
		levels[0].append(_new_def(0))
	for d in max_depth:
		levels.append([])
		for def in levels[d]:
			var n := rng.randi_range(1 if d < 2 else 0, maxi(1, width - d / 3))
			for k in n:
				if project.defs.size() >= max_objects:
					break
				var child: ObjectDef
				if not levels[d + 1].is_empty() and rng.randf() < share:
					child = levels[d + 1][rng.randi_range(0, levels[d + 1].size() - 1)]
				else:
					child = _new_def(d + 1)
					levels[d + 1].append(child)
				def.children.append(Demo._inst(project, child.id, Vector3i.ZERO, 0))

	var tops: Array = levels[0].duplicate()
	tops.append(_corner_deep_chain(40))
	tops.append(_corner_wide(300))
	var empty := project.create_def("empty", UNIT)
	tops.append(empty)

	for def in tops:
		_layout(def, {})
	_place_tops(world, tops)

	if mutations > 0:
		var fuzz := TreeFuzz.new(rng.seed, project, words)
		fuzz.checks = args.has("check")
		for i in mutations:
			fuzz.step()
		print("Applied %d random tree edits; %d checks failed" % [mutations, fuzz.failures.size()])
		for f in fuzz.failures:
			print("  " + f)

	var err := project.save_dir(out)
	print("Wrote %s: %d objects, %.1f s (error %d)" % [out, project.defs.size(), Time.get_ticks_msec() / 1000.0, err])
	print("Open it with: tools/run.sh --project=%s   (press L for relationship lines)" % args.get("out", "user://projects/synthetic.ourcraft"))
	quit(0 if err == OK else 1)


func _load_words() -> void:
	var dir := ProjectSettings.globalize_path("res://data/wordnet/json")
	if not DirAccess.dir_exists_absolute(dir):
		return
	for f in ["noun.artifact.json", "noun.animal.json", "noun.food.json", "noun.plant.json"]:
		var d = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join(f)))
		if d is Dictionary:
			for id in d:
				var w := str(d[id]["members"][0])
				if w.length() <= 14 and not w.contains("_"):
					words.append(w)


func _word() -> String:
	if not words.is_empty():
		return words[rng.randi_range(0, words.size() - 1)]
	const SYL := ["ka", "lo", "mi", "ren", "to", "va", "shi", "pu", "dor", "el", "an", "bri"]
	var w := ""
	for i in rng.randi_range(1, 3):
		w += SYL[rng.randi_range(0, SYL.size() - 1)]
	return w


func _new_def(level: int) -> ObjectDef:
	var def := project.create_def(project.unique_name(_word()), UNIT)
	BlockFont.write_flat(def.grid, def.name, 1 + level % 10)
	depth_of[def.id] = level
	return def


func _corner_deep_chain(levels: int) -> ObjectDef:
	var top := project.create_def("deep", UNIT)
	BlockFont.write_flat(top.grid, top.name, 9)
	var parent := top
	for i in levels:
		var d := project.create_def("level %d" % (i + 1), UNIT)
		BlockFont.write_flat(d.grid, d.name, 1 + i % 10)
		parent.children.append(Demo._inst(project, d.id, Vector3i.ZERO, 0))
		parent = d
	return top


func _corner_wide(n: int) -> ObjectDef:
	var hub := project.create_def("wide", UNIT)
	BlockFont.write_flat(hub.grid, hub.name, 9)
	for i in n:
		var d := project.create_def("part %d" % (i + 1), UNIT)
		BlockFont.write_flat(d.grid, d.name, 1 + i % 10)
		hub.children.append(Demo._inst(project, d.id, Vector3i.ZERO, 0))
	return hub


## Positions an object's parts in a row below its word (towards +Z), centred
## under it, and returns its footprint in its own min units. Computed once
## per object, so shared objects lay out the same everywhere.
func _layout(def: ObjectDef, visiting: Dictionary) -> Dictionary:
	if footprint.has(def.id):
		return footprint[def.id]
	var u := def.unit
	var text_w := BlockFont.text_width(def.name) * u
	var text_h := BlockFont.HEIGHT * u
	var fp := {"xmin": 0, "xmax": maxi(text_w, u), "zmax": text_h}
	visiting[def.id] = true
	var kids := []
	for inst in def.children:
		var child: ObjectDef = project.defs[inst.def_id]
		if not visiting.has(child.id):
			kids.append([inst, _layout(child, visiting)])
	visiting.erase(def.id)
	if not kids.is_empty():
		# Rows of parts, wrapped so very wide objects stay readable.
		var gap := COLUMN_GAP * u
		var rows := [[]]
		var row_w := 0
		for k in kids:
			var w: int = k[1].xmax - k[1].xmin
			if not rows[-1].is_empty() and row_w + gap + w > MAX_ROW:
				rows.append([])
				row_w = 0
			row_w += (gap if not rows[-1].is_empty() else 0) + w
			rows[-1].append(k)
		var z := text_h + ROW_GAP * u
		for row in rows:
			var rw := 0
			for k in row:
				rw += k[1].xmax - k[1].xmin
			rw += gap * (row.size() - 1)
			var x := (text_w - rw) / 2
			var row_depth := 0
			for k in row:
				var kfp: Dictionary = k[1]
				k[0].offset = Vector3i(x - kfp.xmin, 0, z)
				x += kfp.xmax - kfp.xmin + gap
				row_depth = maxi(row_depth, kfp.zmax)
			fp.xmin = mini(fp.xmin, (text_w - rw) / 2)
			fp.xmax = maxi(fp.xmax, (text_w - rw) / 2 + rw)
			z += row_depth + ROW_GAP * u
		fp.zmax = z - ROW_GAP * u
	footprint[def.id] = fp
	return fp


## Top-level trees side by side, centred on the origin.
func _place_tops(world: ObjectDef, tops: Array) -> void:
	var x := 0
	var gap := 200
	var insts := []
	for def in tops:
		var fp: Dictionary = footprint[def.id]
		insts.append(Demo._inst(project, def.id, Vector3i(x - fp.xmin, 0, 0), 0))
		x += fp.xmax - fp.xmin + gap
	for inst in insts:
		inst.offset.x -= x / 2
		world.children.append(inst)
