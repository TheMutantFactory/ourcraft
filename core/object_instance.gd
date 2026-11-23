class_name ObjectInstance
extends RefCounted
## A placement of an ObjectDef inside another ObjectDef.
##
## The offset is measured in minimum-block units of the parent's local space,
## so a child can be positioned at the finest resolution regardless of the
## parent's own block size. Rotation is in quarter turns about +Y around the
## instance origin. Scale multiplies the copy's size (a power of two between
## MIN_SCALE and MAX_SCALE): the object keeps its own integer grid, and every
## block in it, nested objects included, is drawn that much bigger or
## smaller. Scale belongs to the copy, so one House can be full size and
## another a 1/16 dollhouse of the same plan.

var id: String
var def_id: String
var offset := Vector3i.ZERO
var rot := 0
var scale := 1.0

const MIN_SCALE := 1.0 / 64.0
const MAX_SCALE := 64.0


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


## Rotation and scale of this copy.
func basis() -> Basis:
	return basis_for(rot) * scale


## Transform from this instance's local min units to the parent's min units.
func local_transform() -> Transform3D:
	return Transform3D(basis(), Vector3(offset))


## Nearest allowed scale: a power of two within [MIN_SCALE, MAX_SCALE].
static func snap_scale(s: float) -> float:
	if not (s > 0.0):
		return 1.0
	return clampf(pow(2.0, roundf(log(s) / log(2.0))), MIN_SCALE, MAX_SCALE)


## A scale as people read it: 1/16, 1, 4.
static func scale_label(s: float) -> String:
	if s >= 1.0:
		return "%d×" % roundi(s)
	return "1/%d" % roundi(1.0 / s)


func copy() -> ObjectInstance:
	var c := ObjectInstance.new()
	c.id = id
	c.def_id = def_id
	c.offset = offset
	c.rot = rot
	c.scale = scale
	return c


func to_dict() -> Dictionary:
	var d := {
		"id": id,
		"object": def_id,
		"offset": [offset.x, offset.y, offset.z],
		"rot": rot,
	}
	if scale != 1.0:
		d["scale"] = scale
	return d


static func from_dict(d: Dictionary) -> ObjectInstance:
	var inst := ObjectInstance.new()
	inst.id = str(d["id"])
	inst.def_id = str(d["object"])
	var o: Array = d.get("offset", [0, 0, 0])
	inst.offset = Vector3i(int(o[0]), int(o[1]), int(o[2]))
	inst.rot = posmod(int(d.get("rot", 0)), 4)
	inst.scale = snap_scale(float(d.get("scale", 1.0)))
	return inst
