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
var _feet := Area3D.new()

## Immortality (weapon menu): NPC bullets do no harm.
static var immortal := false
const MAX_HEALTH := 100.0
const RESPAWN_TIME := 3.0
var health := MAX_HEALTH
var dead := false
var hurt_flash := 0.0 # 1 on a hit, fades (HUD red vignette)
var _dead_t := 0.0
var _regen_wait := 0.0

## Grenades and FPV drones carried; one more comes back every so often.
const MAX_GRENADES := 4
const MAX_DRONES := 2
var grenades := MAX_GRENADES
var drones := MAX_DRONES
var piloting: FpvDrone # flying a drone through its camera
var signal_lost := 0.0 # HUD static after the drone is gone
var shake := 0.0
var _grenade_regen := 0.0
var _drone_regen := 0.0


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

	# feet zone: walking through bodies and gore shoves them around
	_feet.collision_layer = 0
	_feet.collision_mask = 4 | 32
	_feet.monitorable = false
	var fs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.5
	cyl.height = 0.7
	fs.shape = cyl
	fs.position = Vector3(0, 0.35, 0)
	_feet.add_child(fs)
	add_child(_feet)

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


## Rotate the view by a screen-space delta in pixels (or steer the drone).
func look(delta_px: Vector2, scale := 1.0) -> void:
	if piloting:
		piloting.look_input(delta_px * scale)
		return
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


## A bullet from an armed mannequin.
func take_damage(amount: float, dir: Vector3) -> void:
	if dead:
		return
	hurt_flash = 1.0
	add_recoil(deg_to_rad(randf_range(1.5, 3.0)), deg_to_rad(randf_range(-2.0, 2.0)))
	if immortal:
		return
	health -= amount
	_regen_wait = 5.0
	velocity += Vector3(dir.x, 0.0, dir.z) * 1.2
	if health <= 0.0:
		health = 0.0
		dead = true
		_dead_t = RESPAWN_TIME
		weapon.visible = false
		if piloting:
			piloting.detonate()


func add_shake(amount: float) -> void:
	shake = maxf(shake, amount)


## Pulls the pin and lobs a grenade where he looks.
func throw_grenade() -> void:
	if grenades <= 0 or dead or piloting:
		return
	grenades -= 1
	var b := camera.global_basis
	var from := camera.global_position - b.z * 0.4 + b.x * 0.15 - b.y * 0.1
	Grenade.throw(get_tree(), from, -b.z * 13.0 + Vector3.UP * 2.5 + velocity, true)
	Sfx.play("ui_click", -8.0)


## Sends an FPV drone up from his position and flies it through its camera.
func launch_drone() -> void:
	if piloting:
		piloting.detonate()
		return
	if drones <= 0 or dead:
		return
	drones -= 1
	var d := FpvDrone.new()
	d.team = 0
	d.pilot = self
	d.add_collision_exception_with(self)
	get_tree().current_scene.add_child(d)
	d.global_position = camera.global_position + Vector3.UP * 0.4 - Basis(Vector3.UP, yaw).z * 0.8
	d.rotation.y = yaw
	d._yaw = yaw
	piloting = d
	touch_move = Vector2.ZERO


## The drone went off (or its battery died): back to his own eyes.
func drone_lost(d: FpvDrone) -> void:
	if piloting == d:
		piloting = null
		camera.current = true
		signal_lost = 0.7


func _respawn() -> void:
	dead = false
	health = MAX_HEALTH
	global_transform = _spawn
	velocity = Vector3.ZERO
	yaw = _spawn.basis.get_euler().y
	pitch = 0.0
	head.position.y = EYE_HEIGHT
	head.rotation.z = 0.0
	weapon.visible = true


func _physics_process(delta: float) -> void:
	hurt_flash = maxf(hurt_flash - delta * 1.6, 0.0)
	signal_lost = maxf(signal_lost - delta, 0.0)
	shake = maxf(shake - delta * 1.1, 0.0)
	_grenade_regen += delta
	if _grenade_regen > 20.0:
		_grenade_regen = 0.0
		grenades = mini(grenades + 1, MAX_GRENADES)
	_drone_regen += delta
	if _drone_regen > 40.0:
		_drone_regen = 0.0
		drones = mini(drones + 1, MAX_DRONES)
	if not touch_mode and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if Input.is_action_just_pressed("grenade"):
			throw_grenade()
		if Input.is_action_just_pressed("drone"):
			launch_drone()
	if dead:
		# down on the floor; back at the start after a moment
		_dead_t -= delta
		head.position.y = move_toward(head.position.y, 0.3, delta * 2.5)
		head.rotation.z = move_toward(head.rotation.z, 1.2, delta * 2.0)
		velocity = Vector3(0, velocity.y - GRAVITY * delta, 0) if not is_on_floor() else Vector3.ZERO
		move_and_slide()
		if _dead_t <= 0.0:
			_respawn()
		return
	_regen_wait -= delta
	if _regen_wait <= 0.0:
		health = minf(health + delta * 6.0, MAX_HEALTH)
	var input := touch_move
	if not touch_mode:
		input += Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		if Input.is_action_just_pressed("jump"):
			jump_queued = true
	input = input.limit_length(1.0)
	if piloting:
		input = Vector2.ZERO # the sticks fly the drone
		jump_queued = false

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
	_kick_loose_bodies()
	_footsteps(delta)

	camera.fov = lerpf(Settings.fov, Settings.fov * weapon.current.def.ads_fov, smoothstep(0.0, 1.0, weapon.aim_t))
	# camera recoil recovers over time; it never changes where you aim permanently
	_recoil = _recoil.lerp(Vector2.ZERO, clampf(delta * 9.0, 0.0, 1.0))
	var sh := shake * shake * 0.07
	head.rotation = Vector3(pitch + _recoil.x + randf_range(-sh, sh), _recoil.y + randf_range(-sh, sh), randf_range(-sh, sh) * 0.5)

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


func _kick_loose_bodies() -> void:
	var hv := Vector3(velocity.x, 0.0, velocity.z)
	var speed := hv.length()
	if speed < 0.5:
		return
	for b in _feet.get_overlapping_bodies():
		var rb := b as RigidBody3D
		if rb == null or rb.freeze:
			continue
		var away := rb.global_position - global_position
		away.y = 0.0
		var push := (hv / speed * 0.7 + away.normalized() * 0.3) * speed * minf(rb.mass, 6.0) * 0.05
		rb.apply_central_impulse(push + Vector3.UP * 0.02 * minf(rb.mass, 6.0))


func _footsteps(delta: float) -> void:
	if not is_on_floor():
		return
	var hspeed := Vector2(velocity.x, velocity.z).length()
	_step_dist += hspeed * delta
	if _step_dist > 2.1:
		_step_dist = 0.0
		Sfx.play("footstep", -10.0, 0.12)
