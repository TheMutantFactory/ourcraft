class_name ObjectDef
extends RefCounted
## A reusable construction ("object" / layer): its own voxels plus nested
## instances of other objects. Many instances may share one ObjectDef, so an
## edit to it appears everywhere it is used.

const CHUNK_FORMAT := "u8-deflate-base64"

var id: String
var name: String
## Block size of this object's grid, in multiples of the project's minimum
## block size.
var unit := 1
var grid := VoxelGrid.new()
## Array of ObjectInstance.
var children: Array = []
var forked_from := ""


func find_child(inst_id: String) -> ObjectInstance:
	for inst in children:
		if inst.id == inst_id:
			return inst
	return null


func copy_children() -> Array:
	var out := []
	for inst in children:
		out.append(inst.copy())
	return out


func to_dict() -> Dictionary:
	var keys := grid.chunks.keys()
	keys.sort_custom(func(a: Vector3i, b: Vector3i) -> bool:
		if a.z != b.z: return a.z < b.z
		if a.y != b.y: return a.y < b.y
		return a.x < b.x)
	var chunk_list := []
	for key in keys:
		var data: PackedByteArray = grid.chunks[key]
		chunk_list.append({
			"key": [key.x, key.y, key.z],
			"data": Marshalls.raw_to_base64(data.compress(FileAccess.COMPRESSION_DEFLATE)),
		})
	var child_list := []
	for inst in children:
		child_list.append(inst.to_dict())
	var d := {
		"format": "ourcraft.object",
		"version": 1,
		"id": id,
		"name": name,
		"unit": unit,
		"chunk_size": VoxelGrid.SIZE,
		"chunk_format": CHUNK_FORMAT,
		"chunks": chunk_list,
		"children": child_list,
	}
	if forked_from != "":
		d["forked_from"] = forked_from
	return d


static func from_dict(d: Dictionary) -> ObjectDef:
	var def := ObjectDef.new()
	def.id = str(d["id"])
	def.name = str(d.get("name", "Object"))
	def.unit = maxi(1, int(d.get("unit", 1)))
	def.forked_from = str(d.get("forked_from", ""))
	if int(d.get("chunk_size", VoxelGrid.SIZE)) != VoxelGrid.SIZE:
		push_error("Unsupported chunk size in object %s" % def.id)
		return def
	for c in d.get("chunks", []):
		var k: Array = c["key"]
		var raw := Marshalls.base64_to_raw(str(c["data"]))
		var data := raw.decompress(VoxelGrid.VOLUME, FileAccess.COMPRESSION_DEFLATE)
		if data.size() != VoxelGrid.VOLUME:
			push_error("Corrupt chunk in object %s" % def.id)
			continue
		def.grid.set_chunk(Vector3i(int(k[0]), int(k[1]), int(k[2])), data)
	for c in d.get("children", []):
		def.children.append(ObjectInstance.from_dict(c))
	return def
