class_name Overlay
extends MeshInstance3D
## Line boxes drawn on top of the world: the brush target, the selection and
## the object being edited.

var _im := ImmediateMesh.new()
var _boxes: Array = []
var _fill: MeshInstance3D
var _fill_mat: StandardMaterial3D


func _ready() -> void:
	mesh = _im
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = true
	mat.render_priority = 10
	material_override = mat
	_fill = MeshInstance3D.new()
	_fill.mesh = BoxMesh.new()
	_fill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_fill_mat = StandardMaterial3D.new()
	_fill_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_fill_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_fill_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_fill.material_override = _fill_mat
	_fill.visible = false
	add_child(_fill)


func clear() -> void:
	_boxes.clear()
	_fill.visible = false


## Adds a box given in a local space (t maps local -> world).
func box(t: Transform3D, aabb: AABB, color: Color, grow := 0.0) -> void:
	_boxes.append([t, aabb.grow(grow), color])


## A translucent filled box (only one at a time, for the selection).
func fill(t: Transform3D, aabb: AABB, color: Color) -> void:
	_fill.visible = true
	_fill.global_transform = t * Transform3D(Basis.from_scale(aabb.size.max(Vector3.ONE * 0.0001)), aabb.get_center())
	_fill_mat.albedo_color = color


func commit() -> void:
	_im.clear_surfaces()
	if _boxes.is_empty():
		return
	_im.surface_begin(Mesh.PRIMITIVE_LINES)
	for b in _boxes:
		var t: Transform3D = b[0]
		var a: AABB = b[1]
		_im.surface_set_color(b[2])
		for e in [[0, 1], [1, 3], [3, 2], [2, 0], [4, 5], [5, 7], [7, 6], [6, 4], [0, 4], [1, 5], [2, 6], [3, 7]]:
			_im.surface_add_vertex(t * a.get_endpoint(e[0]))
			_im.surface_add_vertex(t * a.get_endpoint(e[1]))
	_im.surface_end()
