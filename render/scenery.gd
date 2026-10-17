class_name Scenery
extends RefCounted
## Sky, sun and ground shared by the game and the stress test.


static func add_to(parent: Node) -> void:
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

	var ground := StaticBody3D.new()
	ground.set_meta("ground", true)
	var gmesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(400, 400)
	gmesh.mesh = plane
	var gmat := ShaderMaterial.new()
	gmat.shader = load("res://render/ground.gdshader")
	gmesh.material_override = gmat
	ground.add_child(gmesh)
	var gshape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(400, 2, 400)
	gshape.shape = box
	gshape.position.y = -1
	ground.add_child(gshape)
	parent.add_child(ground)
