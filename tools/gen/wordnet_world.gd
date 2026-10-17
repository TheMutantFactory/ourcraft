extends SceneTree
## Builds an Ourcraft project from Open English WordNet's part-of relations:
## every noun that has parts or is a part becomes an object whose voxels
## spell its word, and each part is an instance inside its whole. A part
## shared by several wholes ("door" in house and car) is one object instanced
## in each of them.
##
##   godot --headless --path . --script res://tools/gen/wordnet_world.gd -- \
##       [--data=data/wordnet/json] [--out=user://projects/wordnet.ourcraft]
##
## Run through tools/wordnet-world.sh. Data: docs/bibliography.md.

## Block size (multiples of the 1 cm minimum) by depth in the part tree:
## wholes are written in 10 cm blocks, their parts in 5 cm, then 2 cm, then 1 cm.
const UNIT_BY_DEPTH := [10, 5, 2]
const MIN_UNIT := 1
const TEXT_DEPTH := 2
## Gap between laid-out subtrees, in blocks of the parent's size.
const GAP_BLOCKS := 3
## Width of a row of top-level wholes, in centimetres.
const ROW_WIDTH := 20000

## Colour per WordNet lexicographer file, so categories read at a glance.
const CATEGORY_COLOURS := {
	"noun.body": 5, "noun.animal": 3, "noun.plant": 6, "noun.artifact": 10,
	"noun.food": 8, "noun.location": 7, "noun.object": 1, "noun.substance": 4,
	"noun.quantity": 2, "noun.time": 9, "noun.group": 7, "noun.person": 5,
}
const DEFAULT_COLOUR := 2

var synsets := {}     # synset id -> {members, mero_part, ...}
var category := {}    # synset id -> lexicographer file
var parts := {}       # synset id -> Array of part synset ids
var project: Project
var def_of := {}      # synset id -> ObjectDef
var footprint := {}   # synset id -> {xmin, xmax, zmax} in min units


func _init() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else ""
	var data_dir := ProjectSettings.globalize_path("res://").path_join(str(args.get("data", "data/wordnet/json")))
	var out := str(args.get("out", "user://projects/wordnet.ourcraft"))
	if out.begins_with("user://") or out.begins_with("res://"):
		out = ProjectSettings.globalize_path(out)

	var t0 := Time.get_ticks_msec()
	if not _load(data_dir):
		printerr("No WordNet noun files in %s. Run tools/fetch-wordnet.sh first." % data_dir)
		quit(1)
		return
	var roots := _roots()
	var depth := _min_depths(roots)
	print("WordNet: %d wholes, %d objects, %d top-level" % [parts.size(), depth.size(), roots.size()])

	project = Project.create_empty(0.01)
	project.title = "WordNet part-of world"
	_make_defs(depth)
	for r in roots:
		_layout(r, {})
	_place_roots(roots)

	var err := project.save_dir(out)
	var placements := _count_placements(project.root_id, 0)
	print("Wrote %s: %d objects, %d placements, %.1f s (error %d)" % [
		out, project.defs.size(), placements, (Time.get_ticks_msec() - t0) / 1000.0, err])
	quit(0 if err == OK else 1)


func _load(dir: String) -> bool:
	var files := DirAccess.get_files_at(dir)
	var found := false
	for f in files:
		if not (f.begins_with("noun.") and f.ends_with(".json")):
			continue
		var d = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join(f)))
		if not (d is Dictionary):
			continue
		found = true
		var lexfile := f.trim_suffix(".json")
		for id in d:
			synsets[id] = d[id]
			category[id] = lexfile
			if d[id].has("mero_part"):
				parts[id] = d[id]["mero_part"]
	return found


## Wholes that aren't part of anything.
func _roots() -> Array:
	var is_part := {}
	for whole in parts:
		for p in parts[whole]:
			is_part[p] = true
	var roots := []
	for whole in parts:
		if not is_part.has(whole):
			roots.append(whole)
	roots.sort_custom(func(a, b): return _word(a).naturalnocasecmp_to(_word(b)) < 0)
	return roots


## Shallowest depth at which each object appears (breadth-first).
func _min_depths(roots: Array) -> Dictionary:
	var depth := {}
	var queue := []
	for r in roots:
		depth[r] = 0
		queue.append(r)
	var i := 0
	while i < queue.size():
		var id: String = queue[i]
		i += 1
		for p in parts.get(id, []):
			if not depth.has(p):
				depth[p] = depth[id] + 1
				queue.append(p)
	return depth


func _word(id: String) -> String:
	var s: Dictionary = synsets.get(id, {})
	var members: Array = s.get("members", ["?"])
	return str(members[0]).replace("_", " ")


## One object per synset, named after its first word (numbered when two
## senses share a word), with the word written in its own block size.
func _make_defs(depth: Dictionary) -> void:
	var ids := depth.keys()
	ids.sort()
	var used := {}
	for id in ids:
		var word := _word(id)
		var n: int = used.get(word, 0) + 1
		used[word] = n
		var unit: int = UNIT_BY_DEPTH[depth[id]] if depth[id] < UNIT_BY_DEPTH.size() else MIN_UNIT
		var def := project.create_def(word if n == 1 else "%s (%d)" % [word, n], unit)
		BlockFont.write(def.grid, word, CATEGORY_COLOURS.get(category.get(id, ""), DEFAULT_COLOUR), TEXT_DEPTH)
		def_of[id] = def


## Lays out an object's parts in a row in front of (+Z) its word, centred
## under it, and returns its footprint {xmin, xmax, zmax} in its own min
## units. Computed once per object, so every copy shares the layout.
func _layout(id: String, visiting: Dictionary) -> Dictionary:
	if footprint.has(id):
		return footprint[id]
	var def: ObjectDef = def_of[id]
	var u := def.unit
	var text_w := BlockFont.text_width(_word(id)) * u
	var fp := {"xmin": 0, "xmax": text_w, "zmax": TEXT_DEPTH * u}
	visiting[id] = true
	var kids := []
	for p in parts.get(id, []):
		if def_of.has(p) and not visiting.has(p):
			kids.append([p, _layout(p, visiting)])
	visiting.erase(id)
	if not kids.is_empty():
		var gap := GAP_BLOCKS * u
		var row_w := 0
		for k in kids:
			row_w += k[1].xmax - k[1].xmin
		row_w += gap * (kids.size() - 1)
		var x := (text_w - row_w) / 2
		var z := TEXT_DEPTH * u + gap
		var row_depth := 0
		for k in kids:
			var kfp: Dictionary = k[1]
			def.children.append(Demo._inst(project, def_of[k[0]].id, Vector3i(x - kfp.xmin, 0, z), 0))
			x += kfp.xmax - kfp.xmin + gap
			row_depth = maxi(row_depth, kfp.zmax)
		fp.xmin = mini(0, (text_w - row_w) / 2)
		fp.xmax = maxi(text_w, (text_w - row_w) / 2 + row_w)
		fp.zmax = z + row_depth
	footprint[id] = fp
	return fp


## Top-level wholes in rows across the ground, alphabetically.
func _place_roots(roots: Array) -> void:
	var world := project.root()
	var x := 0
	var z := 0
	var row_depth := 0
	var gap := 100
	for r in roots:
		var fp: Dictionary = footprint[r]
		var w: int = fp.xmax - fp.xmin
		if x > 0 and x + w > ROW_WIDTH:
			x = 0
			z += row_depth + gap
			row_depth = 0
		world.children.append(Demo._inst(project, def_of[r].id, Vector3i(x - fp.xmin, 0, z), 0))
		x += w + gap
		row_depth = maxi(row_depth, fp.zmax)
	# Centre the field on the origin, where the ground plane is.
	var shift := Vector3i(ROW_WIDTH / 2, 0, (z + row_depth) / 2)
	for inst in world.children:
		inst.offset -= shift


func _count_placements(def_id: String, depth: int) -> int:
	var n := 1
	if depth > Project.MAX_DEPTH:
		return n
	for inst in project.defs[def_id].children:
		n += _count_placements(inst.def_id, depth + 1)
	return n
