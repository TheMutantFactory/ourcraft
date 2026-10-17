class_name TreeLines
extends MeshInstance3D
## Draws the object tree as org-chart lines: from the bottom edge of each
## object to the top edge of each of its parts, with an elbow halfway. The
## lines come from the live tree, so they stay right after edits. Toggle
## with L in the game.

## Lines float this far (metres) above the tallest of the two ends.
const LIFT := 0.01
const COLORS := [
	Color("#ffd75e"), Color("#7fd3ff"), Color("#ff8a65"), Color("#a5d6a7"),
	Color("#ce93d8"), Color("#fff59d"), Color("#80cbc4"), Color("#f48fb1"),
]

var _source: Array = []
var _dirty := true


func _ready() -> void:
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	material_override = mat
	visible = false


func mark_dirty() -> void:
	_dirty = true


## Rebuilds the lines when the view's placements or the voxels changed.
func update_from(view: WorldView, project: Project) -> void:
	if not visible or project == null:
		return
	if not _dirty and is_same(view._placements, _source):
		return
	_dirty = false
	_source = view._placements
	var index := {}
	for i in _source.size():
		index["/".join(_source[i].path)] = i
	var boxes := {}
	var verts := PackedVector3Array()
	var colors := PackedColorArray()
	for pl in _source:
		if pl.path.is_empty():
			continue
		var parent_key := "/".join(pl.path.slice(0, pl.path.size() - 1))
		if not index.has(parent_key):
			continue
		var parent: Dictionary = _source[index[parent_key]]
		var a := _box(parent, project, boxes)
		var b := _box(pl, project, boxes)
		if a.size == Vector3.ZERO and a.position == Vector3.ZERO and parent.path.is_empty():
			continue # the world itself has no word to hang lines from
		var y := maxf(a.end.y, b.end.y) + LIFT
		var top := Vector3(a.get_center().x, y, a.end.z)
		var bottom := Vector3(b.get_center().x, y, b.position.z)
		var mid_z := (top.z + bottom.z) * 0.5
		var c: Color = COLORS[(pl.path.size() - 1) % COLORS.size()]
		for seg in [[top, Vector3(top.x, y, mid_z)], [Vector3(top.x, y, mid_z), Vector3(bottom.x, y, mid_z)], [Vector3(bottom.x, y, mid_z), bottom]]:
			verts.append(seg[0])
			verts.append(seg[1])
			colors.append(c)
			colors.append(c)
	var m := ArrayMesh.new()
	if not verts.is_empty():
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_COLOR] = colors
		m.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	mesh = m


## World box of a placement's own voxels (not its parts).
func _box(pl: Dictionary, project: Project, cache: Dictionary) -> AABB:
	var def: ObjectDef = project.defs.get(pl.def_id)
	if def == null:
		return AABB(pl.xform.origin, Vector3.ZERO)
	if not cache.has(def.id):
		var g := def.grid.bounds()
		var s: float = project.voxel_size * def.unit
		cache[def.id] = AABB(g.position * s, g.size * s)
	var local: AABB = cache[def.id]
	if local.size == Vector3.ZERO:
		return AABB(pl.xform.origin, Vector3.ZERO)
	return pl.xform * local
