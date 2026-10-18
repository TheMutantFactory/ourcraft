extends SceneTree
## Builds a roughly 1:1 Black Rock City (Burning Man) as a test level for
## chunks, distance, scale and instancing. Sources and which numbers are
## estimates: docs/bibliography.md and docs/testing.md.
##
##   tools/black-rock-city.sh [--seed=1] [--density=0.35] [--out=user://projects/black-rock-city.ourcraft]
##
## Layout (2022 city plan): the Man at the centre; the Esplanade 2,500 ft out;
## annular streets Esplanade, then A–K with 400/250/450/150 ft blocks; 40 ft
## streets; radial streets every half hour from 2:00 to 10:00; plazas on B
## and G; Center Camp at 6:00; the Temple at 12:00; a pentagonal trash fence
## about nine miles around. Clock directions: 12:00 is -Z, 3:00 is +X, 6:00
## is +Z.
##
## Block sizes are mixed on purpose: roads 1 m, fence, Man and Temple 25 cm,
## camps 10 cm, signs 5 cm, playa art down to 1 cm.

const FT := 0.3048
const ESPLANADE := 2500.0 * FT
const STREET := 40.0 * FT
## Curb-to-curb block depths outward from the Esplanade (2022 plan).
const BLOCKS := [400, 250, 250, 250, 250, 450, 250, 250, 250, 150, 150]
const STREETS := ["Esplanade", "Apparition", "Breton", "Cocteau", "Dali", "Enigma",
	"Fugue", "Glimmer", "Hypnagogia", "Inception", "Jarry", "Kahlo"]
const LETTERS := ["ESP", "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K"]
## Estimates (not in the published plans).
const TEMPLE_DISTANCE := 2500.0 * FT
const CENTER_CAMP_RING := 300.0 * FT   # Rod's Road radius
const PLAZA_RADIUS := 100.0 * FT       # 200 ft plazas (2018 plan)
const FENCE_PERIMETER := 9.0 * 1609.34 # "about nine miles"

# Palette values (Project.DEFAULT_PALETTE): 1 stone, 2 plaster, 3 oak,
# 4 walnut, 5 brick, 6 leaf, 7 blue, 8 brass, 9 charcoal, 10 steel.
const ROAD := 9

var rng := RandomNumberGenerator.new()
var project: Project
var trees: WordTrees
var ramp_base := 11
var rings := []           # street centre radii in metres
var shared := {}          # name -> ObjectDef, objects reused everywhere
var counts := {"camps": 0, "camp items": 0, "signs": 0, "art": 0}


func _init() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else ""
	rng.seed = int(args.get("seed", "1"))
	var density := float(args.get("density", "0.35"))
	var out := str(args.get("out", "user://projects/black-rock-city.ourcraft"))
	var out_abs := ProjectSettings.globalize_path(out) if out.begins_with("user://") else out
	var t0 := Time.get_ticks_msec()

	project = Project.create_empty(0.01)
	project.title = "Black Rock City"
	ramp_base = PaletteRamps.ensure(project)
	trees = WordTrees.new(rng.seed, WordTrees.load_words())
	rings = [ESPLANADE]
	for d in BLOCKS:
		rings.append(rings[-1] + STREET + d * FT)
	var center_camp := _polar(6.0, rings[1])
	project.environment = {
		"ground_size": 6000, "ground_color": "#d9c9a6", "ground_line_color": "#cbb995",
		"ground_y": -0.02, "fog_density": 0.00018, "far": 7000,
		"spawn": [center_camp.x, 0.3, center_camp.z - CENTER_CAMP_RING - 20, 0],
	}

	var world := project.root()
	var city := _def("Black Rock City", 100)
	_place(world, city, Vector3.ZERO)
	_place(world, _man(), Vector3.ZERO)
	_place(world, _temple(), _polar(12.0, TEMPLE_DISTANCE))
	_place(world, _fence(), Vector3.ZERO)
	_playa_art(world)
	_roads(city)
	_plazas(city)
	_place(city, _center_camp(), center_camp)
	_signs(city)
	_camps(city, density, center_camp)

	var err := project.save_dir(out_abs)
	print("Black Rock City: %d objects, %s, %.1f s (error %d)" % [
		project.defs.size(), counts, (Time.get_ticks_msec() - t0) / 1000.0, err])
	print("Open it with: tools/run.sh --project=%s" % out)
	quit(0 if err == OK else 1)


# --- Helpers -----------------------------------------------------------------

func _def(name: String, unit: int) -> ObjectDef:
	return project.create_def(name, unit)


## Places child at a world position (metres) inside parent (which sits at
## the world origin).
func _place(parent: ObjectDef, child: ObjectDef, at: Vector3, rot := 0) -> ObjectInstance:
	var inst := Demo._inst(project, child.id, Vector3i((at / project.voxel_size).round()), rot)
	parent.children.append(inst)
	return inst


## World position (metres) at a clock hour and distance from the Man.
static func _polar(hour: float, r: float) -> Vector3:
	var a := hour / 12.0 * TAU
	return Vector3(sin(a) * r, 0, -cos(a) * r)


static func _hour_of(x: float, z: float) -> float:
	return fposmod(atan2(x, -z) / TAU * 12.0, 12.0)


## Quarter turn whose +Z faces most nearly along dir.
static func _facing(dir: Vector3) -> int:
	var best := 0
	var best_dot := -INF
	for k in 4:
		var d := ObjectInstance.basis_for(k) * Vector3(0, 0, 1)
		if d.dot(dir.normalized()) > best_dot:
			best = k
			best_dot = d.dot(dir.normalized())
	return best


# --- Roads -------------------------------------------------------------------
# Roads are 1 m blocks sunk into the playa: the cells sit at y = -1..0, so
# their tops are flush with the ground (which is lowered 2 cm to avoid
# z-fighting).

func _roads(city: ObjectDef) -> void:
	for i in rings.size():
		var road := _def("%s street" % STREETS[i], 100)
		var p := GridPainter.new()
		_paint_arc(p, rings[i], STREET, 2.0, 10.0)
		p.commit(road.grid)
		_place(city, road, Vector3.ZERO)
	for k in 17:
		var hour := 2.0 + k * 0.5
		var road := _def("%d:%02d street" % [int(hour), 30 if fmod(hour, 1.0) > 0 else 0], 100)
		var p := GridPainter.new()
		var a := _polar(hour, rings[0])
		var b := _polar(hour, rings[-1])
		p.line(Vector2(a.x, a.z), Vector2(b.x, b.z), STREET, -1, 1, ROAD)
		p.commit(road.grid)
		_place(city, road, Vector3.ZERO)


## An arc of road centred on the Man between two clock hours, in 1 m cells
## (painter units are metres here).
func _paint_arc(p: GridPainter, radius: float, width: float, from_hour: float, to_hour: float, centre := Vector2.ZERO) -> void:
	var r_in := radius - width * 0.5
	var r_out := radius + width * 0.5
	for z in range(floori(-r_out), ceili(r_out) + 1):
		var zc := z + 0.5
		if absf(zc) > r_out:
			continue
		var x_out := sqrt(r_out * r_out - zc * zc)
		var x_in := sqrt(maxf(0.0, r_in * r_in - zc * zc))
		for side in [-1, 1]:
			var a := x_in if side > 0 else -x_out
			var b := x_out if side > 0 else -x_in
			for x in range(floori(a), ceili(b)):
				var xc := x + 0.5
				var h := _hour_of(xc, zc)
				if from_hour <= to_hour and (h < from_hour or h > to_hour):
					continue
				p.set_cell(Vector3i(x + int(centre.x), -1, z + int(centre.y)), ROAD)


func _ring_def(name: String, radius: float, width: float) -> ObjectDef:
	var def := _def(name, 100)
	var p := GridPainter.new()
	_paint_arc(p, radius, width, 0.0, 12.0)
	p.commit(def.grid)
	return def


func _plazas(city: ObjectDef) -> void:
	var plaza := _ring_def("plaza", PLAZA_RADIUS, STREET)
	shared.plaza = plaza
	for street in [2, 7]: # B and G
		for hour in [3.0, 4.5, 7.5, 9.0]:
			_place(city, plaza, _polar(hour, rings[street]))
	_place(city, plaza, _polar(6.0, rings[7]))


# --- Landmarks -------------------------------------------------------------

func _man() -> ObjectDef:
	var man := _def("The Man", 25)
	var p := GridPainter.new()
	# A stepped pavilion, then the figure (25 cm cells).
	var steps := [120, 96, 72, 48]
	for i in steps.size():
		var w: int = steps[i]
		p.fill_box(Vector3i(-w / 2, i * 8, -w / 2), Vector3i(w / 2, i * 8 + 8, w / 2), 3 if i % 2 == 0 else 4)
	var base := 32
	p.fill_box(Vector3i(-6, base, -2), Vector3i(-2, base + 24, 2), 3)      # legs
	p.fill_box(Vector3i(2, base, -2), Vector3i(6, base + 24, 2), 3)
	p.fill_box(Vector3i(-6, base + 24, -2), Vector3i(6, base + 40, 2), 3)  # torso
	for k in 16:                                                          # arms up
		p.fill_box(Vector3i(-7 - k, base + 34 + k, -1), Vector3i(-5 - k, base + 36 + k, 1), 3)
		p.fill_box(Vector3i(5 + k, base + 34 + k, -1), Vector3i(7 + k, base + 36 + k, 1), 3)
	for k in 6:                                                           # diamond head
		var w := 6 - absi(k - 3) * 2
		p.fill_box(Vector3i(-w / 2, base + 41 + k, -2), Vector3i(w / 2 + 1, base + 42 + k, 2), 7)
	p.commit(man.grid)
	return man


func _temple() -> ObjectDef:
	var temple := _def("Temple", 25)
	var p := GridPainter.new()
	p.fill_box(Vector3i(-80, 0, -80), Vector3i(80, 4, 80), 3)
	var y := 4
	var w := 64
	for tier in 6:
		# Hollow walls with an opening, then a roof slab.
		for k in 10:
			for x in range(-w, w):
				if absi(x) > 6 or k > 6:
					p.set_cell(Vector3i(x, y + k, -w), 3)
					p.set_cell(Vector3i(x, y + k, w - 1), 3)
			for z in range(-w, w):
				if absi(z) > 6 or k > 6:
					p.set_cell(Vector3i(-w, y + k, z), 3)
					p.set_cell(Vector3i(w - 1, y + k, z), 3)
		y += 10
		p.fill_box(Vector3i(-w - 4, y, -w - 4), Vector3i(w + 4, y + 2, w + 4), 4)
		y += 2
		w = int(w * 0.72)
	p.fill_box(Vector3i(-2, y, -2), Vector3i(2, y + 40, 2), 8)
	p.commit(temple.grid)
	return temple


## The trash fence: a pentagon about nine miles around, 1 m (4 ft) tall,
## in 25 cm cells. One corner points to 12:00.
func _fence() -> ObjectDef:
	var fence := _def("trash fence", 25)
	var side := FENCE_PERIMETER / 5.0
	var radius := side / (2.0 * sin(PI / 5.0)) / 0.25 # in cells
	var orange := ramp_base + 3 * PaletteRamps.STEPS
	var p := GridPainter.new()
	for k in 5:
		var a := _polar(k * 12.0 / 5.0, radius)
		var b := _polar((k + 1) * 12.0 / 5.0, radius)
		p.line(Vector2(a.x, a.z), Vector2(b.x, b.z), 1.0, 0, 4, orange)
	p.commit(fence.grid)
	return fence


func _center_camp() -> ObjectDef:
	var camp := _def("Center Camp", 100)
	_place(camp, _ring_def("Rod's Road", CENTER_CAMP_RING, STREET), Vector3.ZERO)
	# The canopy: about an acre of shade (36 m radius) on poles, 50 cm cells.
	var canopy := _def("Center Camp canopy", 50)
	var p := GridPainter.new()
	var r := 72
	for z in range(-r, r):
		for x in range(-r, r):
			if x * x + z * z < r * r:
				p.set_cell(Vector3i(x, 12, z), 2)
	for k in 12:
		var a := k / 12.0 * TAU
		var c := Vector2(cos(a), sin(a)) * (r - 4)
		p.fill_box(Vector3i(int(c.x), 0, int(c.y)), Vector3i(int(c.x) + 1, 12, int(c.y) + 1), 3)
	p.commit(canopy.grid)
	_place(camp, canopy, Vector3.ZERO)
	var sign := _word_def("CENTER CAMP", 10, 2)
	_place(camp, sign, Vector3(-BlockFont.text_width("CENTER CAMP") * 0.05, 7.0, 40.0))
	return camp


# --- Signs, camps and art ------------------------------------------------------

func _word_def(text: String, unit: int, ramp: int) -> ObjectDef:
	var def := _def(text, unit)
	BlockFont.write(def.grid, text, 1, 2, PaletteRamps.letter_colours(ramp_base, ramp, text.length()))
	return def


## A post and a name at every intersection of a radial and an annular street.
func _signs(city: ObjectDef) -> void:
	var group := _def("street signs", 100)
	_place(city, group, Vector3.ZERO)
	var post := _def("sign post", 5)
	post.grid.fill_box(Vector3i(0, 0, 0), Vector3i(2, 60, 2), 9)
	for k in 17:
		var hour := 2.0 + k * 0.5
		var label := "%d:%02d" % [int(hour), 30 if fmod(hour, 1.0) > 0 else 0]
		for i in rings.size():
			var corner := _polar(hour + 0.05, rings[i] - STREET * 0.5 - 2.0)
			var sign := _def("%s & %s" % [label, STREETS[i]], 5)
			var text := "%s & %s" % [label, LETTERS[i]]
			BlockFont.write(sign.grid, text, 1, 1, PaletteRamps.letter_colours(ramp_base, 1, text.length()))
			_place(sign, post, Vector3(BlockFont.text_width(text) * 0.025, -3.0, 0))
			_place(group, sign, corner + Vector3(0, 3.0, 0), _facing(-corner))
			counts.signs += 1


func _camp_items() -> Array:
	if shared.has("items"):
		return shared.items
	var items := []
	for c in [[5, "red dome tent"], [7, "blue dome tent"], [6, "green dome tent"]]:
		var tent := _def(c[1], 10)
		var p := GridPainter.new()
		for x in range(-14, 15):
			for z in range(-14, 15):
				var h := sqrt(maxf(0.0, 196.0 - x * x - z * z))
				if h > 0.0:
					p.fill_box(Vector3i(x, 0, z), Vector3i(x + 1, int(h), z + 1), c[0])
		p.commit(tent.grid)
		items.append(tent)
	var shade := _def("shade structure", 10)
	var sp := GridPainter.new()
	for c in [Vector2i(0, 0), Vector2i(59, 0), Vector2i(0, 59), Vector2i(59, 59)]:
		sp.fill_box(Vector3i(c.x, 0, c.y), Vector3i(c.x + 1, 30, c.y + 1), 10)
	sp.fill_box(Vector3i(0, 30, 0), Vector3i(60, 31, 60), 2)
	sp.commit(shade.grid)
	items.append(shade)
	var rv := _def("RV", 10)
	var rp := GridPainter.new()
	rp.fill_box(Vector3i(0, 3, 0), Vector3i(75, 30, 25), 2)
	rp.fill_box(Vector3i(5, 18, -1), Vector3i(70, 23, 26), 9)
	rp.fill_box(Vector3i(8, 0, 2), Vector3i(14, 5, 23), 9)
	rp.fill_box(Vector3i(58, 0, 2), Vector3i(64, 5, 23), 9)
	rp.commit(rv.grid)
	items.append(rv)
	var dome := _def("geodesic dome", 10)
	var dp := GridPainter.new()
	for x in range(-30, 31):
		for z in range(-30, 31):
			for y in range(0, 31):
				var d := sqrt(x * x + y * y + z * z)
				if d <= 30.0 and d > 28.6 and (absi(x) % 6 == 0 or absi(z) % 6 == 0 or y % 6 == 0):
					dp.set_cell(Vector3i(x, y, z), 10)
	dp.commit(dome.grid)
	items.append(dome)
	shared.items = items
	return items


## Camps on a grid of lots in every block: sector (half hour) › block
## (between two streets) › camp › tents, shade, RVs and domes.
func _camps(city: ObjectDef, density: float, center_camp: Vector3) -> void:
	var items := _camp_items()
	var lot := 18.0
	for k in 16:
		var h0 := 2.0 + k * 0.5
		var sector := _def("%d:%02d–%d:%02d sector" % [int(h0), 30 if fmod(h0, 1.0) > 0 else 0,
			int(h0 + 0.5), 30 if fmod(h0 + 0.5, 1.0) > 0 else 0], 100)
		_place(city, sector, Vector3.ZERO)
		for i in rings.size() - 1:
			var block := _def("%d:%02d & %s block" % [int(h0), 30 if fmod(h0, 1.0) > 0 else 0, STREETS[i + 1]], 100)
			_place(sector, block, Vector3.ZERO)
			var r := float(rings[i]) + STREET * 0.5 + lot * 0.5
			while r < float(rings[i + 1]) - STREET * 0.5 - lot * 0.5:
				var margin := (STREET * 0.5 + lot * 0.5) / r / TAU * 12.0
				var h := h0 + margin
				while h < h0 + 0.5 - margin:
					var at := _polar(h, r)
					var skip := at.distance_to(center_camp) < CENTER_CAMP_RING + 20.0
					for street in [2, 7]:
						for ph in [3.0, 4.5, 6.0, 7.5, 9.0]:
							if at.distance_to(_polar(ph, rings[street])) < PLAZA_RADIUS + 20.0:
								skip = true
					if not skip and rng.randf() < density:
						_camp(block, items, at)
					h += lot / r / TAU * 12.0
				r += lot


func _camp(block: ObjectDef, items: Array, at: Vector3) -> void:
	var camp := _def("camp %d" % (counts.camps + 1), 10)
	for n in rng.randi_range(2, 6):
		var item: ObjectDef = items[rng.randi_range(0, items.size() - 1)]
		var local := Vector3(rng.randf_range(-6, 4), 0, rng.randf_range(-6, 4))
		camp.children.append(Demo._inst(project, item.id, Vector3i((local / project.voxel_size).round()), rng.randi_range(0, 3)))
		counts["camp items"] += 1
	if rng.randf() < 0.2:
		var name := trees.word().capitalize() + " Camp"
		camp.name = name
		var sign := _word_def(name.to_upper(), 5, rng.randi_range(0, PaletteRamps.RAMPS.size() - 1))
		camp.children.append(Demo._inst(project, sign.id, Vector3i(-300, 250, 600), 0))
	_place(block, camp, at, _facing(-at))
	counts.camps += 1


## Word sculptures around the open playa, and one big one near the Man.
func _playa_art(world: ObjectDef) -> void:
	var art := _def("playa art", 100)
	_place(world, art, Vector3.ZERO)
	for n in 60:
		var hour := rng.randf_range(0.0, 12.0)
		var r := rng.randf_range(90.0, ESPLANADE - 60.0)
		if hour > 1.5 and hour < 10.5 and rng.randf() < 0.5:
			r = rng.randf_range(90.0, ESPLANADE * 0.6)
		var piece := trees.build(project, rng.randi_range(1, 3), 3)
		var at := _polar(hour, r)
		_place(art, piece, at, _facing(-at))
		counts.art += 1
	var big := _word_def("OURCRAFT", 25, 4)
	_place(art, big, _polar(0.0, 60.0) + Vector3(-BlockFont.text_width("OURCRAFT") * 0.125, 0, 0))
