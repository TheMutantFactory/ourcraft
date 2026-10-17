class_name BurstScenario
extends Scenario
## Platforms of different heights in a ring, each with a few words on top,
## each word's letters stepping along a colour gradient. Every second or
## so a random word (never a platform) breaks into flying pieces of its
## voxels (BurstEffect) and is removed; new words keep appearing.
##
## The words are instances inside their platform objects, so bursting also
## exercises removing nested objects from baked regions.

const PLATFORMS := 14
const RING := 9.0
## Seconds between bursts, and between new words.
const BURST_EVERY := Vector2(0.6, 1.6)
const SPAWN_EVERY := Vector2(0.4, 1.2)
## Words must exist this long before they can burst (so they're meshed).
const MIN_AGE := 0.8
const WORDS_PER_PLATFORM := 2

var trees: WordTrees
var _ramp_base := 11
## word instance id -> {platform: def id, platform_inst: inst id, born: s}
var _words := {}
## [{inst: platform instance id, def: platform def id, top: min units,
##   size: Vector3i in min units}]
var _platforms: Array = []
var _burst_timer := 1.5
var _spawn_timer := 0.5
var _effects := 0
var _poke_timer := 7.0


func _init(seed := 1) -> void:
	super(seed)
	name = "Burst"
	stats = {"bursts": 0, "pieces": 0, "words made": 0, "objects deleted": 0, "biggest chunk": 1}
	trees = WordTrees.new(seed, WordTrees.load_words())


func _setup() -> void:
	_ramp_base = PaletteRamps.ensure(project)
	_words.clear()
	_platforms.clear()
	var s := 1.0 / project.voxel_size
	for i in PLATFORMS:
		var angle := TAU * i / PLATFORMS + rng.randf_range(-0.1, 0.1)
		var r := RING + rng.randf_range(-1.5, 3.0)
		var size_cells := Vector3i(rng.randi_range(14, 30), rng.randi_range(3, 40), rng.randi_range(12, 22))
		var def := project.create_def("platform %d" % (i + 1), 10)
		def.grid.fill_box(Vector3i.ZERO, size_cells - Vector3i(0, 1, 0), 1)
		def.grid.fill_box(Vector3i(0, size_cells.y - 1, 0), size_cells, 9)
		var size := size_cells * def.unit
		# Turn the platform so its front (+Z, where words face) looks at the
		# middle of the ring.
		var centre := Vector3(cos(angle), 0, sin(angle)) * r * s
		var rot := _facing(-centre)
		var basis := ObjectInstance.basis_for(rot)
		var half := basis * Vector3(size.x * 0.5, 0, size.z * 0.5)
		var inst := project.add_instance(project.root_id, def.id, Vector3i((centre - half).round()), rot)
		_platforms.append({"inst": inst.id, "def": def.id, "top": size.y, "size": size})
	for p in _platforms:
		for k in WORDS_PER_PLATFORM:
			_spawn_word(p)


func status_lines() -> String:
	return "bursts %d · pieces %d · words %d\nlibrary %d objects · effects %d" % [
		stats.bursts, stats.pieces, _words.size(), project.defs.size(), _effects]


func report_line() -> String:
	return "words %d" % _words.size()


func _tick(dt: float) -> void:
	_spawn_timer -= dt
	if _spawn_timer <= 0.0:
		_spawn_timer = rng.randf_range(SPAWN_EVERY.x, SPAWN_EVERY.y)
		if _words.size() < PLATFORMS * WORDS_PER_PLATFORM:
			_spawn_word(_platforms[rng.randi_range(0, _platforms.size() - 1)])
	_burst_timer -= dt
	if _burst_timer <= 0.0:
		_burst_timer = rng.randf_range(BURST_EVERY.x, BURST_EVERY.y)
		_forget_missing()
		var ready := _words.keys().filter(func(id): return _elapsed - _words[id].born >= MIN_AGE)
		if not ready.is_empty():
			burst_word(ready[rng.randi_range(0, ready.size() - 1)])


## Drops words that are gone for another reason (burst with B, deleted).
func _forget_missing() -> void:
	for id in _words.keys():
		var platform: ObjectDef = project.defs.get(_words[id].platform)
		if platform == null or platform.find_child(id) == null:
			_words.erase(id)


## Bursts one word into pieces and removes it (and any object only it used).
func burst_word(id: String) -> void:
	var w: Dictionary = _words[id]
	_words.erase(id)
	view.flush()
	var path := PackedStringArray([w.platform_inst, id])
	var parts := BurstEffect.collect(project, view, path)
	if parts.pieces.is_empty():
		poke_failures.append("bursting %s produced no pieces" % id)
	else:
		var fx := BurstEffect.new()
		main.add_child(fx)
		fx.setup(parts, 3.5)
		_effects += 1
		fx.tree_exited.connect(func(): _effects -= 1)
	stats.bursts += 1
	stats.pieces += parts.pieces.size()
	stats["biggest chunk"] = maxi(stats["biggest chunk"], parts.chunk)
	stats["objects deleted"] += project.remove_and_prune(w.platform, id)
	if project.defs[w.platform].find_child(id) != null:
		poke_failures.append("burst word %s is still on its platform" % id)


func _spawn_word(p: Dictionary) -> void:
	var text := trees.word()
	var size: Vector3i = p.size
	# The biggest block size (5, 2 or 1 cm) at which the word fits the platform.
	var unit := 1
	for u in [5, 2, 1]:
		if BlockFont.text_width(text) * u <= size.x - 10:
			unit = u
			break
	var def := project.create_def(text, unit)
	var colours := PaletteRamps.letter_colours(_ramp_base, rng.randi_range(0, PaletteRamps.RAMPS.size() - 1), text.length())
	BlockFont.write(def.grid, text, 1, 2, colours)
	var width := BlockFont.text_width(text) * unit
	var depth := 2 * unit
	var offset := Vector3i(rng.randi_range(5, maxi(5, size.x - width - 5)), p.top, rng.randi_range(5, maxi(5, size.z - depth - 5)))
	var inst := project.add_instance(p.def, def.id, offset, 0)
	if inst != null:
		_words[inst.id] = {"platform": p.def, "platform_inst": p.inst, "born": _elapsed}
		stats["words made"] += 1


## During a soak: also burst a whole platform's worth of words at once now
## and then, and check bursting really removed them.
func _poke(dt: float) -> void:
	_poke_timer -= dt
	if _poke_timer <= 0.0 and _words.size() > 6:
		_poke_timer = 7.0
		_forget_missing()
		var ready := _words.keys().filter(func(id): return _elapsed - _words[id].born >= MIN_AGE)
		for id in ready.slice(0, 4):
			burst_word(id)


## Quarter turn whose +Z points most nearly along dir.
static func _facing(dir: Vector3) -> int:
	var best := 0
	var best_dot := -INF
	for k in 4:
		var d := ObjectInstance.basis_for(k) * Vector3(0, 0, 1)
		var dot := d.dot(dir.normalized())
		if dot > best_dot:
			best = k
			best_dot = dot
	return best
