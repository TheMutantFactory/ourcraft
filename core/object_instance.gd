class_name ObjectInstance
extends RefCounted
## A placement of an ObjectDef inside another ObjectDef.
##
## The offset is measured in minimum-block units of the parent's local space,
## so a child can be positioned at the finest resolution regardless of the
## parent's own block size. Rotation is in quarter turns about +Y around the
## instance origin.

var id: String
var def_id: String
var offset := Vector3i.ZERO
var rot := 0


static func basis_for(quarter_turns: int) -> Basis:
	match posmod(quarter_turns, 4):
		1: return Basis(Vector3(0, 0, -1), Vector3.UP, Vector3(1, 0, 0))
		2: return Basis(Vector3(-1, 0, 0), Vector3.UP, Vector3(0, 0, -1))
		3: return Basis(Vector3(0, 0, 1), Vector3.UP, Vector3(-1, 0, 0))
	return Basis.IDENTITY


## The quarter turn a basis represents (rotation about +Y), or -1 if it
## isn't one.
static func quarter_turns_of(b: Basis) -> int:
	for k in 4:
		if b.is_equal_approx(basis_for(k)):
			return k
	return -1


## Transform from this instance's local min units to the parent's min units.
func local_transform() -> Transform3D:
	return Transform3D(basis_for(rot), Vector3(offset))


func copy() -> ObjectInstance:
	var c := ObjectInstance.new()
	c.id = id
	c.def_id = def_id
	c.offset = offset
	c.rot = rot
	return c


func to_dict() -> Dictionary:
	return {
		"id": id,
		"object": def_id,
		"offset": [offset.x, offset.y, offset.z],
		"rot": rot,
	}


static func from_dict(d: Dictionary) -> ObjectInstance:
	var inst := ObjectInstance.new()
	inst.id = str(d["id"])
	inst.def_id = str(d["object"])
	var o: Array = d.get("offset", [0, 0, 0])
	inst.offset = Vector3i(int(o[0]), int(o[1]), int(o[2]))
	inst.rot = posmod(int(d.get("rot", 0)), 4)
	return inst
