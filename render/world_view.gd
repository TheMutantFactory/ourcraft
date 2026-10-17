class_name WorldView
extends Node3D
## Renders a Project. Chunk meshes and collision shapes are built once per
## object definition and shared by every instance of it, so instancing is
## cheap and an edit shows up in every copy at once.

const MESH_BUDGET_USEC := 6000

var project: Project
var material: StandardMaterial3D

## def_id -> {Vector3i key -> {"mesh": ArrayMesh, "shape": ConcavePolygonShape3D}}
var _meshes: Dictionary = {}
## def_id -> Array of chunk container nodes (one per rendered instance)
var _containers: Dictionary = {}
## path string -> instance Node3D
var _nodes: Dictionary = {}
## instance id -> Array of instance Node3D (one per place it is rendered)
var _nodes_by_inst: Dictionary = {}
## def_id -> {key -> true}
var _dirty: Dictionary = {}
var _root_node: Node3D
var _isolated = null # PackedStringArray or null
var _tree_dirty := false


func _ready() -> void:
	material = StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true
	material.roughness = 0.88


func set_project(p: Project) -> void:
	if project != null:
		project.voxels_changed.disconnect(_on_voxels_changed)
		project.structure_changed.disconnect(_on_structure_changed)
	project = p
	project.voxels_changed.connect(_on_voxels_changed)
	project.structure_changed.connect(_on_structure_changed)
	remesh_all()


## Rebuilds every mesh (e.g. after the minimum block size changes).
func remesh_all() -> void:
	_meshes.clear()
	_dirty.clear()
	for def in project.defs.values():
		for key in def.grid.chunks:
			_dirty.get_or_add(def.id, {})[key] = true
	rebuild_tree()


func pending_chunks() -> int:
	var n := 0
	for d in _dirty.values():
		n += d.size()
	return n


func _on_voxels_changed(def_id: String, keys: Array) -> void:
	var d: Dictionary = _dirty.get_or_add(def_id, {})
	for key in keys:
		d[key] = true


func _on_structure_changed() -> void:
	_tree_dirty = true


func _process(_delta: float) -> void:
	if _tree_dirty:
		rebuild_tree()
	var start := Time.get_ticks_usec()
	while not _dirty.is_empty() and Time.get_ticks_usec() - start < MESH_BUDGET_USEC:
		var def_id: String = _dirty.keys()[0]
		var keys: Dictionary = _dirty[def_id]
		var key: Vector3i = keys.keys()[0]
		keys.erase(key)
		if keys.is_empty():
			_dirty.erase(def_id)
		_remesh(def_id, key)


## Meshes everything still pending right away (used before screenshots/tests).
func flush() -> void:
	if _tree_dirty:
		rebuild_tree()
	for def_id in _dirty.keys():
		for key in _dirty[def_id].keys():
			_remesh(def_id, key)
	_dirty.clear()


func _remesh(def_id: String, key: Vector3i) -> void:
	var def: ObjectDef = project.defs.get(def_id)
	if def == null:
		_meshes.erase(def_id)
		return
	var cell_m := project.voxel_size * def.unit
	var built := Mesher.build(def.grid, key, project.palette, cell_m)
	var entries: Dictionary = _meshes.get_or_add(def_id, {})
	if built.is_empty():
		if entries.has(key):
			entries.erase(key)
			for container in _containers.get(def_id, []):
				var n: Node = container.get_node_or_null(_key_name(key))
				if n != null:
					n.free()
		return
	var entry = entries.get(key)
	var fresh: bool = entry == null
	if fresh:
		entry = {"mesh": ArrayMesh.new(), "shape": ConcavePolygonShape3D.new()}
		entry.shape.backface_collision = true
		entries[key] = entry
	var mesh: ArrayMesh = entry.mesh
	mesh.clear_surfaces()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, built.arrays)
	mesh.surface_set_material(0, material)
	entry.shape.set_faces(built.faces)
	if fresh:
		for container in _containers.get(def_id, []):
			_add_chunk_node(container, key, entry)


static func _key_name(key: Vector3i) -> String:
	return "c_%d_%d_%d" % [key.x, key.y, key.z]


func _add_chunk_node(container: Node3D, key: Vector3i, entry: Dictionary) -> void:
	var mi := MeshInstance3D.new()
	mi.name = _key_name(key)
	mi.mesh = entry.mesh
	var body := StaticBody3D.new()
	body.set_meta("path", container.get_meta("path"))
	body.set_meta("def_id", container.get_meta("def_id"))
	var cs := CollisionShape3D.new()
	cs.shape = entry.shape
	body.add_child(cs)
	mi.add_child(body)
	container.add_child(mi)


# --- Instance tree ---------------------------------------------------------

func rebuild_tree() -> void:
	_tree_dirty = false
	if _root_node != null:
		_root_node.free()
	_containers.clear()
	_nodes.clear()
	_nodes_by_inst.clear()
	_root_node = _build_node(project.root_id, PackedStringArray(), null, 0)
	add_child(_root_node)
	_apply_isolation()


func _build_node(def_id: String, path: PackedStringArray, inst: ObjectInstance, depth: int) -> Node3D:
	var node := Node3D.new()
	node.name = "i_" + (inst.id if inst != null else "root")
	node.set_meta("path", path)
	if inst != null:
		_apply_transform(node, inst)
		_nodes_by_inst.get_or_add(inst.id, []).append(node)
	_nodes["/".join(path)] = node
	var container := Node3D.new()
	container.name = "chunks"
	container.set_meta("path", path)
	container.set_meta("def_id", def_id)
	node.add_child(container)
	_containers.get_or_add(def_id, []).append(container)
	var entries: Dictionary = _meshes.get(def_id, {})
	for key in entries:
		_add_chunk_node(container, key, entries[key])
	var def: ObjectDef = project.defs.get(def_id)
	if def != null and depth < Project.MAX_DEPTH:
		for child in def.children:
			var child_path := path.duplicate()
			child_path.append(child.id)
			node.add_child(_build_node(child.def_id, child_path, child, depth + 1))
	return node


func _apply_transform(node: Node3D, inst: ObjectInstance) -> void:
	node.transform = Transform3D(ObjectInstance.basis_for(inst.rot), Vector3(inst.offset) * project.voxel_size)


## Updates every rendered copy of an instance after its transform changed
## without rebuilding the tree (used while dragging).
func refresh_instance(inst: ObjectInstance) -> void:
	for node in _nodes_by_inst.get(inst.id, []):
		_apply_transform(node, inst)


func node_for(path: PackedStringArray) -> Node3D:
	return _nodes.get("/".join(path))


## Physics bodies belonging to every rendered copy of an instance.
func bodies_of(inst_id: String) -> Array:
	var out := []
	for node in _nodes_by_inst.get(inst_id, []):
		for b in node.find_children("*", "StaticBody3D", true, false):
			out.append(b.get_rid())
	return out


# --- Isolation -------------------------------------------------------------

## Shows only the object at path (and its contents); null shows everything.
func set_isolation(path) -> void:
	_isolated = path
	_apply_isolation()


func _apply_isolation() -> void:
	if _root_node == null:
		return
	_set_active(_root_node, true)
	if _isolated == null:
		return
	var node := _root_node
	for k in range(_isolated.size() + 1):
		var next_name: String = "i_" + _isolated[k] if k < _isolated.size() else ""
		for child in node.get_children():
			if k == _isolated.size():
				break
			if child.name != next_name:
				_set_active(child, false)
		if k == _isolated.size():
			break
		node = node.get_node_or_null(NodePath(next_name))
		if node == null:
			return


func _set_active(node: Node3D, on: bool) -> void:
	node.visible = on
	node.process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED
	if on:
		for child in node.get_children():
			if child is Node3D:
				_set_active(child, true)
