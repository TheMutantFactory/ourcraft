class_name RoadTour
extends Scenario
## Walks the player (a cube, seen in third person) from Center Camp along a
## Hamiltonian path of Black Rock City's street grid, visiting every
## intersection of a radial and an annular street exactly once and only
## moving along streets. Behind it a trail of 10 cm dots runs from magenta
## to chartreuse over the whole walk.
##
##   tools/brc-tour.sh               [ ] slower / faster · P pause · V camera
##
## The grid comes from the project's environment.roads (written by
## tools/gen/black_rock_city.gd).

const DOT := 0.1
const DOT_SPACING := 1.0
## Dots per MultiMesh.
const BATCH := 4096
const SPEED := 20.0
const SPEEDS := [1.25, 2.5, 5.0, 10.0, 20.0, 40.0, 80.0, 160.0, 320.0]
## The trail's hues: magenta (300°) forward through red, orange and yellow
## to chartreuse (90°), so the middle stays bright instead of turning grey.
const HUE_FROM := 300.0
const HUE_SPAN := 150.0

var speed := SPEED
var paused := false
## The walk as a polyline (metres) with cumulative distances.
var _points := PackedVector3Array()
var _cum := PackedFloat64Array()
## Per route node: [label, distance along the walk].
var _stops: Array = []
var _distance := 0.0
var _dots := 0
var _dots_root: Node3D
var _batches: Array = []
var _done := false


func _init(seed := 1) -> void:
	super(seed)
	name = "Road tour"
	stats = {"intersections": 0, "km": 0.0, "dots": 0}


func _setup() -> void:
	_clear_dots()
	_points.clear()
	_cum.clear()
	_stops.clear()
	_distance = 0.0
	_dots = 0
	_done = false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--speed="):
			speed = float(a.trim_prefix("--speed="))
	var roads: Dictionary = project.environment.get("roads", {})
	if roads.is_empty():
		main.hud.toast("This world has no street grid to tour (make one with tools/black-rock-city.sh)", 8.0)
		return
	_build(roads)
	_dots_root = Node3D.new()
	_dots_root.name = "Tour trail"
	main.add_child(_dots_root)
	var player: Player = main.player
	player.driven = true
	player.set_third_person(true)
	# Low behind the cube, looking along the street.
	player.follow = 4.5
	player.follow_up = 0.2
	player.set_pitch(deg_to_rad(-8))
	player.global_position = _points[0]
	player.rotation = Vector3(0, _yaw(_points[1] - _points[0]), 0)


## The route over the grid of intersections: col is the radial (0 = the
## first hour), row the street (0 = Esplanade). Starts at (start, 0), goes
## along row 0 to col 0, then serpentines over rows 1..rows-1 for cols
## 0..start, then over every row (back down to 0) for the remaining cols.
## Every intersection appears once and each step moves to a neighbour.
## Needs an even number of rows, so the second sweep ends at col start.
static func route(cols: int, rows: int, start: int) -> Array:
	var out := []
	for c in range(start, -1, -1):
		out.append(Vector2i(c, 0))
	for r in range(1, rows):
		var forward := r % 2 == 1
		for k in start + 1:
			out.append(Vector2i(k if forward else start - k, r))
	if start + 1 < cols:
		var width := cols - start - 1
		for i in rows:
			var r := rows - 1 - i
			var forward := i % 2 == 0
			for k in width:
				out.append(Vector2i(start + 1 + (k if forward else width - 1 - k), r))
	return out


func _build(roads: Dictionary) -> void:
	var rings: Array = roads.rings
	var h: Array = roads.hours
	var cols := int(round((float(h[1]) - float(h[0])) / float(h[2]))) + 1
	var start := int(round((6.0 - float(h[0])) / float(h[2])))
	var letters: Array = roads.get("letters", [])
	var cc: Array = roads.center_camp
	_add_point(Vector3(cc[0], 0, cc[1]))
	_stops.append(["Center Camp", 0.0])
	var prev := Vector2i(-1, -1)
	for node: Vector2i in route(cols, rings.size(), start):
		var hour := float(h[0]) + node.x * float(h[2])
		var r := float(rings[node.y])
		if prev.y == node.y and prev.x >= 0:
			# Along the street: an arc around the Man.
			var from_hour := float(h[0]) + prev.x * float(h[2])
			var steps := maxi(1, ceili(absf(hour - from_hour) / 12.0 * TAU * r / DOT_SPACING))
			for k in range(1, steps + 1):
				_add_point(_polar(lerpf(from_hour, hour, float(k) / steps), r))
		else:
			_add_point(_polar(hour, r))
		var street: String = letters[node.y] if node.y < letters.size() else str(node.y)
		_stops.append(["%d:%02d & %s" % [int(hour), 30 if fmod(hour, 1.0) > 0.0 else 0, street], _cum[-1]])
		prev = node


func _add_point(p: Vector3) -> void:
	_cum.append(0.0 if _points.is_empty() else _cum[-1] + p.distance_to(_points[-1]))
	_points.append(p)


static func _polar(hour: float, r: float) -> Vector3:
	var a := hour / 12.0 * TAU
	return Vector3(sin(a) * r, 0, -cos(a) * r)


## Yaw that points the player's -Z along dir.
static func _yaw(dir: Vector3) -> float:
	return atan2(-dir.x, -dir.z)


func length() -> float:
	return _cum[-1] if not _cum.is_empty() else 0.0


## The point d metres along the walk.
func point_at(d: float) -> Vector3:
	if _points.is_empty():
		return Vector3.ZERO
	d = clampf(d, 0.0, length())
	var i := _cum.bsearch(d)
	if i <= 0:
		return _points[0]
	if i >= _points.size():
		return _points[-1]
	var span := _cum[i] - _cum[i - 1]
	var t := 0.0 if span <= 0.0 else (d - _cum[i - 1]) / span
	return _points[i - 1].lerp(_points[i], t)


## The trail colour at a fraction of the walk.
static func colour_at(t: float) -> Color:
	return Color.from_hsv(fposmod(HUE_FROM + HUE_SPAN * clampf(t, 0.0, 1.0), 360.0) / 360.0, 0.95, 1.0)


func _tick(dt: float) -> void:
	if _points.is_empty() or _done:
		return
	if not paused:
		_distance = minf(_distance + speed * dt, length())
	while _dots * DOT_SPACING <= _distance:
		_add_dot(point_at(_dots * DOT_SPACING), _dots * DOT_SPACING / length())
	var player: Player = main.player
	var p := point_at(_distance)
	player.global_position = p
	var ahead := point_at(_distance + 2.0) - p
	if ahead.length() > 0.01:
		player.rotation.y = lerp_angle(player.rotation.y, _yaw(ahead), clampf(8.0 * dt, 0.0, 1.0))
	stats.intersections = _stop_index()
	stats.km = snappedf(_distance / 1000.0, 0.01)
	stats.dots = _dots
	if _distance >= length():
		_done = true
		player.driven = false
		main.hud.toast("Tour complete: %d intersections, %.1f km" % [_stops.size() - 1, length() / 1000.0], 10.0)


func _add_dot(at: Vector3, t: float) -> void:
	var slot := _dots % BATCH
	if slot == 0:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		var box := BoxMesh.new()
		box.size = Vector3.ONE * DOT
		var mat := StandardMaterial3D.new()
		mat.vertex_color_use_as_albedo = true
		box.material = mat
		mm.mesh = box
		mm.instance_count = BATCH
		mm.visible_instance_count = 0
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		_dots_root.add_child(mmi)
		_batches.append(mmi)
	var mm: MultiMesh = _batches[-1].multimesh
	mm.set_instance_transform(slot, Transform3D(Basis.IDENTITY, at + Vector3(0, DOT * 0.5, 0)))
	mm.set_instance_color(slot, colour_at(t))
	mm.visible_instance_count = slot + 1
	_dots += 1


func _clear_dots() -> void:
	if _dots_root != null:
		_dots_root.queue_free()
	_dots_root = null
	_batches.clear()


## Index of the last intersection reached (0 = Center Camp).
func _stop_index() -> int:
	var i := 0
	while i + 1 < _stops.size() and _stops[i + 1][1] <= _distance:
		i += 1
	return i


func status_lines() -> String:
	if _points.is_empty():
		return "Road tour: no street grid in this world"
	var i := _stop_index()
	var at: String = _stops[i][0]
	var next: String = _stops[i + 1][0] if i + 1 < _stops.size() else "the end"
	var left := (length() - _distance) / maxf(speed, 0.001)
	return "%s → %s · intersection %d of %d\n%.1f of %.1f km · %s m/s ([ ] change, P pause) · %s left" % [
		at, next, i, _stops.size() - 1, _distance / 1000.0, length() / 1000.0,
		Hud._fmt(speed), "paused" if paused else ("%d min" % ceili(left / 60.0) if left > 60.0 else "%d s" % ceili(left))]


func report_line() -> String:
	return "%d of %d intersections, %.1f km, %d dots" % [_stop_index(), _stops.size() - 1, _distance / 1000.0, _dots]


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo) or _points.is_empty():
		return
	match event.keycode:
		KEY_BRACKETLEFT, KEY_BRACKETRIGHT:
			var i := SPEEDS.find(speed)
			if i < 0:
				i = SPEEDS.find(SPEED)
			i = clampi(i + (1 if event.keycode == KEY_BRACKETRIGHT else -1), 0, SPEEDS.size() - 1)
			speed = SPEEDS[i]
			main.hud.toast("Touring at %s m/s" % Hud._fmt(speed))
		KEY_P:
			paused = not paused
			main.hud.toast("Paused" if paused else "Walking on")
