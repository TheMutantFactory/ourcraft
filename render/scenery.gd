class_name Scenery
extends RefCounted
## Sky, sun and ground shared by the game and the stress test.


## Adds sky, sun and ground. hole > 0 cuts a square hole of that size
## (metres) out of the ground at the origin, with a pit below it.
static func add_to(parent: Node, hole := 0.0) -> void:
	var env := Environment.new()
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color("#3f7fd0")
	sky_mat.sky_horizon_color = Color("#bcd6ee")
	sky_mat.ground_horizon_color = Color("#bcd6ee")
	sky_mat.ground_bottom_color = Color("#5a6b52")
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 1.0
	env.ambient_light_color = Color("#e6dfd2")
	env.ambient_light_sky_contribution = 0.45
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.ssao_enabled = true
	env.ssao_radius = 0.6
	env.ssao_intensity = 1.6
	env.fog_enabled = true
	env.fog_light_color = Color("#bcd6ee")
	env.fog_density = 0.004
	env.fog_sky_affect = 0.0
	var we := WorldEnvironment.new()
	we.environment = env
	parent.add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -35, 0)
	sun.light_energy = 1.25
	sun.light_color = Color("#fff4e0")
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 60.0
	sun.shadow_bias = 0.02
	parent.add_child(sun)

	var gmat := ShaderMaterial.new()
	gmat.shader = load("res://render/ground.gdshader")
	var ground := StaticBody3D.new()
	ground.set_meta("ground", true)
	parent.add_child(ground)
	if hole <= 0.0:
		_ground_slab(ground, gmat, Rect2(-200, -200, 400, 400))
		return
	# Four slabs around a square hole at the origin, and a dark pit below it.
	var h := hole * 0.5
	_ground_slab(ground, gmat, Rect2(-200, -200, 400, 200 - h))
	_ground_slab(ground, gmat, Rect2(-200, h, 400, 200 - h))
	_ground_slab(ground, gmat, Rect2(-200, -h, 200 - h, hole))
	_ground_slab(ground, gmat, Rect2(h, -h, 200 - h, hole))
	var pit := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(hole, PIT_DEPTH, hole)
	pit.mesh = box
	pit.position.y = -PIT_DEPTH * 0.5
	# Unlit and unfogged so it reads as a drop, not a grey slab.
	var pit_mat := StandardMaterial3D.new()
	pit_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pit_mat.albedo_color = Color("#08070a")
	pit_mat.disable_fog = true
	pit_mat.cull_mode = BaseMaterial3D.CULL_FRONT # see the inside walls
	pit.material_override = pit_mat
	pit.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(pit)


## Depth of the pit under a hole, in metres.
const PIT_DEPTH := 30.0


## One rectangle of ground (rect in the XZ plane), with a collision box.
static func _ground_slab(body: StaticBody3D, mat: Material, rect: Rect2) -> void:
	var mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = rect.size
	mesh.mesh = plane
	mesh.material_override = mat
	var center := rect.get_center()
	mesh.position = Vector3(center.x, 0, center.y)
	body.add_child(mesh)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(rect.size.x, 2, rect.size.y)
	shape.shape = box
	shape.position = Vector3(center.x, -1, center.y)
	body.add_child(shape)
