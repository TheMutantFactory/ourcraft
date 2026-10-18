class_name Player
extends CharacterBody3D
## First-person walker/flyer. The player can be resized so that 1 cm work is
## comfortable: at 0.1x the player is 18 cm tall and a centimetre block is a
## sensible step.

const HEIGHT := 1.8
const RADIUS := 0.3
const EYE := 1.62
const WALK := 4.3
const SPRINT := 1.8
const FLY := 7.0
const GRAVITY := 24.0
const JUMP_HEIGHT := 1.15
const STEP := 0.35
const SCALES := [0.05, 0.1, 0.25, 0.5, 1.0, 2.0]

var camera: Camera3D
var flying := false
var size := 1.0
var mouse_sensitivity := 0.0025
var _shape: CapsuleShape3D
var _col: CollisionShape3D
var _pitch := 0.0


func _ready() -> void:
	_shape = CapsuleShape3D.new()
	_col = CollisionShape3D.new()
	_col.shape = _shape
	add_child(_col)
	camera = Camera3D.new()
	camera.fov = 75.0
	add_child(camera)
	floor_max_angle = deg_to_rad(50)
	set_size(1.0)


func set_size(f: float) -> void:
	size = f
	_shape.radius = RADIUS * f
	_shape.height = HEIGHT * f
	_col.position = Vector3(0, HEIGHT * f * 0.5, 0)
	camera.position = Vector3(0, EYE * f, 0)
	camera.near = clampf(0.05 * f, 0.002, 0.05)
	floor_snap_length = 0.2 * f
	safe_margin = clampf(0.001 * f, 0.0002, 0.001)


func reach() -> float:
	return 8.0 * maxf(size, 0.25)


func look(relative: Vector2) -> void:
	rotate_y(-relative.x * mouse_sensitivity)
	_pitch = clampf(_pitch - relative.y * mouse_sensitivity, -PI / 2 + 0.01, PI / 2 - 0.01)
	camera.rotation.x = _pitch


## Sets the look angle (radians, positive looks up).
func set_pitch(p: float) -> void:
	_pitch = clampf(p, -PI / 2 + 0.01, PI / 2 - 0.01)
	camera.rotation.x = _pitch


func _physics_process(delta: float) -> void:
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	var input := Vector2.ZERO
	if captured:
		input = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var dir := (transform.basis * Vector3(input.x, 0, input.y)).normalized()
	if flying:
		# Faster the higher you fly, so big worlds can be crossed: twice as
		# fast 6 m up (in player sizes), 150× at 900 m.
		var speed := FLY * size * (2.5 if captured and Input.is_key_pressed(KEY_CTRL) else 1.0)
		speed *= 1.0 + maxf(0.0, global_position.y) / (6.0 * size)
		var vy := 0.0
		if captured and Input.is_action_pressed("jump"): vy += 1.0
		if captured and Input.is_action_pressed("descend"): vy -= 1.0
		var target := dir * speed + Vector3.UP * vy * speed
		velocity = velocity.lerp(target, clampf(12.0 * delta, 0.0, 1.0))
		move_and_slide()
		return
	var speed := WALK * size * (SPRINT if captured and Input.is_action_pressed("descend") else 1.0)
	var g := GRAVITY * size
	if not is_on_floor():
		velocity.y -= g * delta
	elif captured and Input.is_action_pressed("jump"):
		velocity.y = sqrt(2.0 * g * JUMP_HEIGHT * size)
	var accel := 14.0 if is_on_floor() else 3.0
	var hv := Vector3(velocity.x, 0, velocity.z).lerp(dir * speed, clampf(accel * delta, 0.0, 1.0))
	velocity.x = hv.x
	velocity.z = hv.z
	var was_on_floor := is_on_floor()
	var before := global_position
	move_and_slide()
	if was_on_floor and is_on_wall() and dir != Vector3.ZERO:
		_try_step(before, dir * speed * delta)


## Climbs small ledges (stairs, a 10 cm floor) without jumping.
func _try_step(from: Vector3, motion: Vector3) -> void:
	var step := STEP * size
	var t := Transform3D(global_transform.basis, from)
	if test_move(t, Vector3.UP * step):
		return
	t.origin += Vector3.UP * step
	if test_move(t, motion):
		return
	t.origin += motion
	var col := KinematicCollision3D.new()
	if test_move(t, Vector3.DOWN * step, col):
		global_position = t.origin + col.get_travel()
		velocity.y = 0.0
