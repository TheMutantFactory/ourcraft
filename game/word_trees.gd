class_name WordTrees
extends RefCounted
## Builds small random trees of words written upright in voxels: the whole
## in larger blocks, its parts smaller in a row in front of it (+Z), and so
## on down. Used by the hole scenario's clouds.

## Block size by depth, in smallest-block units (5 cm, 2 cm, 1 cm).
const UNITS := [5, 2, 1]
const TEXT_DEPTH := 2
const GAP_BLOCKS := 3

var rng := RandomNumberGenerator.new()
var words: Array = []


func _init(seed: int, word_list: Array = []) -> void:
	rng.seed = seed
	words = word_list


## Nouns from Open English WordNet if tools/fetch-wordnet.sh has run, else
## an empty list (made-up words are used instead).
static func load_words() -> Array:
	var out := []
	var dir := ProjectSettings.globalize_path("res://data/wordnet/json")
	if not DirAccess.dir_exists_absolute(dir):
		return out
	for f in ["noun.artifact.json", "noun.animal.json", "noun.food.json", "noun.plant.json", "noun.body.json"]:
		var d = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join(f)))
		if d is Dictionary:
			for id in d:
				var w := str(d[id]["members"][0])
				if w.length() <= 12 and not w.contains("_"):
					out.append(w)
	return out


func word() -> String:
	if not words.is_empty():
		return words[rng.randi_range(0, words.size() - 1)]
	const SYL := ["ka", "lo", "mi", "ren", "to", "va", "shi", "pu", "dor", "el", "an", "bri"]
	var w := ""
	for i in rng.randi_range(1, 3):
		w += SYL[rng.randi_range(0, SYL.size() - 1)]
	return w


## Creates a tree of new objects in the project and returns its top object.
## The voxels are written straight into the grids; the view meshes them when
## the tree is placed.
func build(project: Project, max_depth := 3, max_width := 3) -> ObjectDef:
	var top := _make(project, 0, max_depth, max_width)
	_layout(project, top)
	return top


func _make(project: Project, depth: int, max_depth: int, max_width: int) -> ObjectDef:
	var unit: int = UNITS[mini(depth, UNITS.size() - 1)]
	var def := project.create_def(word(), unit)
	BlockFont.write(def.grid, def.name, rng.randi_range(1, 10), TEXT_DEPTH)
	if depth < max_depth:
		var n := rng.randi_range(1 if depth == 0 else 0, max_width)
		for i in n:
			var child := _make(project, depth + 1, max_depth, max_width)
			def.children.append(Demo._inst(project, child.id, Vector3i.ZERO, 0))
	return def


## Lays out parts in a row in front of their word, centred under it.
## Returns the footprint {xmin, xmax, zmax} in the object's own min units.
func _layout(project: Project, def: ObjectDef) -> Dictionary:
	var u := def.unit
	var text_w := BlockFont.text_width(def.name) * u
	var fp := {"xmin": 0, "xmax": text_w, "zmax": TEXT_DEPTH * u}
	if def.children.is_empty():
		return fp
	var kids := []
	for inst in def.children:
		kids.append([inst, _layout(project, project.defs[inst.def_id])])
	var gap := GAP_BLOCKS * u
	var row_w := gap * (kids.size() - 1)
	for k in kids:
		row_w += k[1].xmax - k[1].xmin
	var x := (text_w - row_w) / 2
	var z := TEXT_DEPTH * u + gap
	var row_depth := 0
	for k in kids:
		var kfp: Dictionary = k[1]
		k[0].offset = Vector3i(x - kfp.xmin, 0, z)
		x += kfp.xmax - kfp.xmin + gap
		row_depth = maxi(row_depth, kfp.zmax)
	fp.xmin = mini(0, (text_w - row_w) / 2)
	fp.xmax = maxi(text_w, (text_w - row_w) / 2 + row_w)
	fp.zmax = z + row_depth
	return fp
