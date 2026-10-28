class_name Player
extends CharacterBody3D
## First-person player controller (touch + keyboard/mouse).

const SPEED := 4.6
const AIM_SPEED := 2.4
const JUMP_VELOCITY := 4.8
const GRAVITY := 12.0
const EYE_HEIGHT := 1.62

var head := Node3D.new()
var camera := Camera3D.new()
var weapon: Weapon
var touch_mode := false
var touch_move := Vector2.ZERO
var jump_queued := false
var yaw := 0.0
var pitch := 0.0

var _look_accum := Vector2.ZERO
var _recoil := Vector2.ZERO
var _step_dist := 0.0
var _spawn: Transform3D


func _ready() -> void:
	add_to_group("player")
	add_to_group("settings_listeners")
	collision_layer = 16
	collision_mask = 1 | 2 | 8
	floor_snap_length = 0.35
	floor_max_angle = deg_to_rad(50)
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.33
	cap.height = 1.8
	cs.shape = cap
	cs.position = Vector3(0, 0.9, 0)
	add_child(cs)

	head.position = Vector3(0, EYE_HEIGHT, 0)
	add_child(head)
	camera.near = 0.03
	camera.far = 400.0
	camera.current = true
	head.add_child(camera)
	weapon = Weapon.new()
	weapon.player = self
	camera.add_child(weapon)

	yaw = rotation.y
	_spawn = global_transform
	touch_mode = DisplayServer.is_touchscreen_available() or OS.has_feature("mobile")
	on_settings_changed()


func on_settings_changed() -> void:
	camera.fov = Settings.fov


func capture_mouse() -> void:
	if not touch_mode:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Rotate the view by a screen-space delta in pixels.
func look(delta_px: Vector2, scale := 1.0) -> void:
	var s := 0.13 * Settings.sensitivity * scale * lerpf(1.0, 0.55, weapon.aim_t)
	yaw -= deg_to_rad(delta_px.x * s)
	pitch = clampf(pitch - deg_to_rad(delta_px.y * s), deg_to_rad(-88), deg_to_rad(88))
	_look_accum += delta_px * scale


func consume_look_delta() -> Vector2:
	var d := _look_accum
	_look_accum = Vector2.ZERO
	return d


func add_recoil(up: float, side: float) -> void:
	_recoil += Vector2(up, side)


func _unhandled_input(event: InputEvent) -> void:
	if touch_mode:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		look(event.relative, 0.6)
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		capture_mouse()


func _physics_process(delta: float) -> void:
	var input := touch_move
	if not touch_mode:
		input += Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		if Input.is_action_just_pressed("jump"):
			jump_queued = true
	input = input.limit_length(1.0)

	rotation.y = yaw
	var wish := (Basis(Vector3.UP, yaw) * Vector3(input.x, 0.0, input.y))
	var speed := lerpf(SPEED, AIM_SPEED, weapon.aim_t)
	var accel := 14.0 if is_on_floor() else 3.0
	velocity.x = move_toward(velocity.x, wish.x * speed, accel * speed * delta)
	velocity.z = move_toward(velocity.z, wish.z * speed, accel * speed * delta)

	if is_on_floor():
		if jump_queued:
			velocity.y = JUMP_VELOCITY
	else:
		velocity.y -= GRAVITY * delta
	jump_queued = false

	move_and_slide()
	_push_bodies(wish * speed)
	_footsteps(delta)

	camera.fov = lerpf(Settings.fov, Settings.fov * weapon.current.def.ads_fov, smoothstep(0.0, 1.0, weapon.aim_t))
	# camera recoil recovers over time; it never changes where you aim permanently
	_recoil = _recoil.lerp(Vector2.ZERO, clampf(delta * 9.0, 0.0, 1.0))
	head.rotation = Vector3(pitch + _recoil.x, _recoil.y, 0.0)

	if global_position.y < -30.0:
		global_transform = _spawn
		velocity = Vector3.ZERO
		yaw = _spawn.basis.get_euler().y


func _push_bodies(wish_vel: Vector3) -> void:
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		var body := c.get_collider() as RigidBody3D
		if body == null:
			continue
		var push := -c.get_normal()
		push.y = 0.0
		if push.length() < 0.1:
			continue
		push = push.normalized()
		var target := maxf(wish_vel.dot(push), 0.0)
		var current := body.linear_velocity.dot(push)
		var need := target - current
		if need > 0.0:
			body.apply_impulse(push * need * minf(body.mass, 20.0) * 0.35, c.get_position() - body.global_position)


func _footsteps(delta: float) -> void:
	if not is_on_floor():
		return
	var hspeed := Vector2(velocity.x, velocity.z).length()
	_step_dist += hspeed * delta
	if _step_dist > 2.1:
		_step_dist = 0.0
		Sfx.play("footstep", -10.0, 0.12)
