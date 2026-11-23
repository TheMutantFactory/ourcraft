class_name Thumbnailer
extends Node
## Renders small pictures of objects for the palette in an offscreen
## viewport, one object per frame, and caches them by content.
##
## A thumbnail is keyed by a signature of everything that changes how the
## object looks: its voxels, its nested objects and where they sit, block
## sizes and the palette. Editing an object gives it a new signature, so the
## next request renders a fresh picture; an unchanged object comes from the
## memory cache or, after a restart, from user://thumbs/<signature>.png.

signal rendered(def_id: String, texture: Texture2D)

const SIZE := 160
const CACHE_DIR := "user://thumbs"
## Unique chunks meshed for one thumbnail. Past this the picture shows what
## was meshed so far; palette objects are far smaller than this.
const MAX_CHUNKS := 600
## Drawn placements per thumbnail (nested copies count separately).
const MAX_PLACEMENTS := 4000
const FOV := 30.0
const YAW := deg_to_rad(-35.0)
const PITCH := deg_to_rad(-28.0)

## Set false to skip the disk cache (tests).
var use_disk := true

var _vp: SubViewport
var _cam: Camera3D
var _stage: Node3D
var _material: ShaderMaterial
var _depth_materials: Array = []
var _queue: Array = [] # [{project, def_id, sig}]
var _queued: Dictionary = {} # sig -> true
var _mem: Dictionary = {} # sig -> Texture2D
var _failed: Dictionary = {} # sig -> true (renderer gave no image)
var _working := false


func _ready() -> void:
	_vp = SubViewport.new()
	_vp.size = Vector2i(SIZE, SIZE)
	_vp.own_world_3d = true
	_vp.transparent_bg = true
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_vp)

	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#e6dfd2")
	env.ambient_light_energy = 0.75
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	_vp.add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -35, 0)
	sun.light_energy = 1.1
	sun.light_color = Color("#fff4e0")
	_vp.add_child(sun)

	_cam = Camera3D.new()
	_cam.fov = FOV
	_vp.add_child(_cam)

	_stage = Node3D.new()
	_vp.add_child(_stage)

	_material = ShaderMaterial.new()
	_material.shader = load("res://render/voxel.gdshader")
	# Thumbnails are viewed from a few metres at most; a larger bias keeps
	# coplanar nested faces from fighting at this small size.
	_material.set_shader_parameter("bias_per_layer", 0.0001)


## The cached thumbnail for an object, or null. A missing one is queued,
## and `rendered` fires when it is ready.
func request(project: Project, def_id: String) -> Texture2D:
	if not project.defs.has(def_id):
		return null
	var sig := signature(project, def_id)
	if _mem.has(sig):
		return _mem[sig]
	if _failed.has(sig):
		return null
	if use_disk:
		var file := "%s/%s.png" % [CACHE_DIR, sig]
		if FileAccess.file_exists(file):
			var img := Image.load_from_file(ProjectSettings.globalize_path(file))
			if img != null and not img.is_empty():
				var tex := ImageTexture.create_from_image(img)
				_mem[sig] = tex
				return tex
	if not _queued.has(sig):
		_queued[sig] = true
		_queue.append({"project": project, "def_id": def_id, "sig": sig})
	return null


## Drops queued work (another project was loaded).
func clear_queue() -> void:
	_queue.clear()
	_queued.clear()


func pending() -> int:
	return _queue.size() + (1 if _working else 0)


## Hash of everything that affects how def_id looks.
static func signature(project: Project, def_id: String) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_MD5)
	ctx.update(("thumb-v1|%d|%s|%s|" % [SIZE, project.voxel_size, def_id]).to_utf8_buffer())
	ctx.update(var_to_bytes(project.palette))
	for id in project.dependencies(def_id):
		var def: ObjectDef = project.defs[id]
		ctx.update(("|%s|%d|" % [id, def.unit]).to_utf8_buffer())
		for key in def.sorted_keys():
			ctx.update(var_to_bytes(key))
			ctx.update(def.grid.get_packed(key))
		for inst in def.children:
			ctx.update(("%s@%s/%d;" % [inst.def_id, inst.offset, inst.rot]).to_utf8_buffer())
	return ctx.finish().hex_encode()


## Camera transform that fits an AABB (metres) in view from the thumbnail
## angle: in front of and above the object, looking down at it.
static func frame(box: AABB, fov_deg := FOV) -> Transform3D:
	var center := box.get_center()
	var radius := maxf(box.size.length() * 0.5, 0.01)
	var dist := radius / sin(deg_to_rad(fov_deg) * 0.5) * 1.02
	var basis := Basis.from_euler(Vector3(PITCH, YAW, 0.0))
	return Transform3D(basis, center + basis.z * dist)


func _process(_delta: float) -> void:
	if _working or _queue.is_empty():
		return
	_render_next()


func _render_next() -> void:
	_working = true
	var job: Dictionary = _queue.pop_front()
	_queued.erase(job.sig)
	var project: Project = job.project
	if not project.defs.has(job.def_id):
		_working = false
		return
	var box := build_stage(project, job.def_id)
	_cam.transform = frame(box)
	_cam.near = maxf(0.01, _cam.transform.origin.distance_to(box.get_center()) - box.size.length())
	_cam.far = _cam.transform.origin.distance_to(box.get_center()) + box.size.length() + 1.0
	_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	var img := _vp.get_texture().get_image()
	_clear_stage()
	_working = false
	if img == null or img.is_empty():
		_failed[job.sig] = true
		return
	var tex := ImageTexture.create_from_image(img)
	_mem[job.sig] = tex
	if use_disk:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CACHE_DIR))
		img.save_png(ProjectSettings.globalize_path("%s/%s.png" % [CACHE_DIR, job.sig]))
	rendered.emit(job.def_id, tex)


## Fills the stage with meshes of def_id and everything nested in it.
## Returns the drawn bounds in metres (the object's own frame).
func build_stage(project: Project, def_id: String) -> AABB:
	_clear_stage()
	var meshes := {} # def_id -> Array of ArrayMesh
	var budget := [MAX_CHUNKS, MAX_PLACEMENTS]
	_add(project, def_id, Transform3D.IDENTITY, 0, meshes, budget)
	var b := project.def_bounds(def_id)
	if b.size == Vector3.ZERO:
		b = AABB(Vector3.ZERO, Vector3.ONE * 4)
	return AABB(b.position * project.voxel_size, b.size * project.voxel_size)


func stage_mesh_count() -> int:
	return _stage.get_child_count()


func _add(project: Project, def_id: String, xform: Transform3D, depth: int,
		meshes: Dictionary, budget: Array) -> void:
	var def: ObjectDef = project.defs.get(def_id)
	if def == null or depth > Project.MAX_DEPTH or budget[1] <= 0:
		return
	budget[1] -= 1
	if not meshes.has(def_id):
		var list := []
		for key in def.sorted_keys():
			if budget[0] <= 0:
				break
			budget[0] -= 1
			var built := Mesher.build(def.grid, key, project.palette, project.voxel_size * def.unit)
			if built.is_empty():
				continue
			var m := ArrayMesh.new()
			m.add_surface_from_arrays(Mesher.PRIMITIVE, built.arrays)
			list.append(m)
		meshes[def_id] = list
	var mat := _material_for_depth(depth)
	for m in meshes[def_id]:
		var mi := MeshInstance3D.new()
		mi.mesh = m
		mi.material_override = mat
		mi.transform = xform
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_stage.add_child(mi)
	for inst in def.children:
		var local := Transform3D(ObjectInstance.basis_for(inst.rot), Vector3(inst.offset) * project.voxel_size)
		_add(project, inst.def_id, xform * local, depth + 1, meshes, budget)


func _material_for_depth(depth: int) -> ShaderMaterial:
	while _depth_materials.size() <= depth:
		var m: ShaderMaterial = _material.duplicate()
		m.set_shader_parameter("layer", float(_depth_materials.size()))
		_depth_materials.append(m)
	return _depth_materials[depth]


func _clear_stage() -> void:
	for c in _stage.get_children():
		_stage.remove_child(c)
		c.queue_free()
