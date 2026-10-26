extends CharacterBody3D
## Flight model of the quad.
## EASY: arrow buttons; the drone holds altitude and flies like an arcade game.
## CASUAL: two sticks in self-levelling angle mode with a hover-centred throttle,
## so it handles like a real quad without having to manage hover by hand.

signal crashed(reason: String)

const WorldScript := preload("res://scripts/world.gd")
const ModelScript := preload("res://scripts/drone_model.gd")

const G := 9.81
const EASY_TURN := 1.75
const CEILING := 900.0
const LIMIT := 1740.0
const BASE_FOV := 80.0

## Selectable drones. speed is the top speed in km/h, tilt the maximum lean
## angle in radians, yaw the turn rate in rad/s and climb the extra thrust in g.
const TYPES := [
	{"name": "СТАНДАРТ", "about": "5 дюймов · фристайл, мягкий и послушный", "speed": 110.0,
		"tilt": 0.70, "yaw": 2.6, "climb": 1.3, "accent": Color(1.0, 0.45, 0.08), "arms": 1.0},
	{"name": "ГОНЩИК", "about": "рейсинг-рама · резкий, быстро поворачивает", "speed": 160.0,
		"tilt": 0.92, "yaw": 3.3, "climb": 1.8, "accent": Color(0.1, 0.8, 1.0), "arms": 0.88},
	{"name": "РАКЕТА", "about": "спид-билд 6S · разгон до 200 км/ч", "speed": 200.0,
		"tilt": 1.08, "yaw": 3.0, "climb": 2.4, "accent": Color(1.0, 0.16, 0.22), "arms": 1.1},
]

var world: WorldScript
var mode: int = 1
var drone_type := 0
var top_speed := 30.0 # m/s
var max_tilt := 0.7
var yaw_rate := 2.6
var climb := 1.3
var _drag_lin := 0.06
var _drag_quad := 0.0
var active := false
var camera_tilt_deg := 20.0
## Extra camera pitch from swiping the screen, in radians.
var look_pitch := 0.0

var yaw := 0.0
var pitch := 0.0
var roll := 0.0
## 0..1, used by the HUD, sound and props.
var throttle_level := 0.0

# Casual inputs, each -1..1. Throttle 0 means hover.
var in_throttle := 0.0
var in_yaw := 0.0
var in_pitch := 0.0
var in_roll := 0.0
# Easy inputs, each -1..1.
var in_forward := 0.0
var in_turn := 0.0
var in_lift := 0.0

var model: ModelScript
var fpv_cam: Camera3D
var chase_cam: Camera3D

var _shake_t := 0.0


func _ready() -> void:
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	var shape := SphereShape3D.new()
	shape.radius = 0.16
	var cs := CollisionShape3D.new()
	cs.shape = shape
	add_child(cs)

	model = ModelScript.new()
	add_child(model)

	fpv_cam = Camera3D.new()
	fpv_cam.position = Vector3(0.0, 0.02, -0.06)
	fpv_cam.fov = 80.0
	fpv_cam.near = 0.03
	fpv_cam.far = 4500.0
	fpv_cam.cull_mask = 0xFFFFF & ~ModelScript.MODEL_LAYER
	add_child(fpv_cam)

	chase_cam = Camera3D.new()
	chase_cam.top_level = true
	chase_cam.fov = 72.0
	chase_cam.near = 0.05
	chase_cam.far = 4500.0
	add_child(chase_cam)
	set_type(drone_type)


## Switches flight characteristics and looks to one of TYPES.
func set_type(index: int) -> void:
	drone_type = clampi(index, 0, TYPES.size() - 1)
	var t: Dictionary = TYPES[drone_type]
	top_speed = float(t["speed"]) / 3.6
	max_tilt = t["tilt"]
	yaw_rate = t["yaw"]
	climb = t["climb"]
	# Drag chosen so that full forward stick settles exactly at top_speed:
	# in level flight the horizontal acceleration is g * tan(tilt).
	_drag_lin = 0.06
	_drag_quad = maxf(0.0, (G * tan(max_tilt) / top_speed - _drag_lin) / top_speed)
	model.restyle(t["accent"], t["arms"])


func reset_to(pos: Vector3, heading: float) -> void:
	global_position = pos
	velocity = Vector3.ZERO
	yaw = heading
	pitch = 0.0
	roll = 0.0
	throttle_level = 0.0
	in_throttle = 0.0
	in_yaw = 0.0
	in_pitch = 0.0
	in_roll = 0.0
	in_forward = 0.0
	in_turn = 0.0
	in_lift = 0.0
	look_pitch = 0.0
	_apply_rotation()
	var back := Vector3(sin(yaw), 0.0, cos(yaw))
	chase_cam.global_position = pos + back * 1.6 + Vector3.UP * 0.55
	_update_cameras(1.0)


func forward_flat() -> Vector3:
	return Vector3(-sin(yaw), 0.0, -cos(yaw))


func altitude() -> float:
	return global_position.y - world.surface_height(global_position.x, global_position.z)


func _process(delta: float) -> void:
	if not active:
		model.update_props(delta, 0.0)
		_update_cameras(delta)
		return
	delta = minf(delta, 0.05)
	if mode == 0:
		_fly_easy(delta)
	else:
		_fly_casual(delta)
	_apply_rotation()
	var before := velocity
	move_and_slide()
	if _handle_collisions(before, delta):
		return
	_check_limits()
	model.update_props(delta, throttle_level)
	_update_cameras(delta)


static func _expo(v: float) -> float:
	return v * 0.55 + v * v * v * 0.45


func _fly_casual(delta: float) -> void:
	var s := Settings.sensitivity
	var k := 1.0 - exp(-7.0 * delta)
	pitch = lerpf(pitch, -_expo(in_pitch) * max_tilt, k)
	roll = lerpf(roll, -_expo(in_roll) * max_tilt, k)
	yaw = wrapf(yaw - _expo(in_yaw) * yaw_rate * s * delta, -PI, PI)

	var up := Basis.from_euler(Vector3(pitch, yaw, roll)).y
	var gain := climb if in_throttle > 0.0 else 0.95
	var max_thrust := G * (1.0 + climb) / cos(max_tilt)
	var thrust := G * (1.0 + gain * in_throttle)
	thrust = minf(thrust / maxf(up.y, 0.3), max_thrust)
	throttle_level = clampf(thrust / max_thrust, 0.0, 1.0)

	var acc := up * thrust + Vector3.DOWN * G
	var hv := Vector3(velocity.x, 0.0, velocity.z)
	acc -= hv * (_drag_lin + hv.length() * _drag_quad)
	acc.y -= velocity.y * 0.9
	velocity += acc * delta


func _fly_easy(delta: float) -> void:
	var s := Settings.sensitivity
	yaw = wrapf(yaw - in_turn * EASY_TURN * s * delta, -PI, PI)
	var fwd := forward_flat()
	var hv := Vector3(velocity.x, 0.0, velocity.z)
	hv = hv.lerp(fwd * in_forward * top_speed, 1.0 - exp(-1.2 * delta))
	var vy := lerpf(velocity.y, in_lift * (6.0 + climb * 3.0), 1.0 - exp(-3.0 * delta))
	velocity = Vector3(hv.x, vy, hv.z)

	var fspeed := hv.dot(fwd)
	var k := 1.0 - exp(-5.0 * delta)
	pitch = lerpf(pitch, -clampf(fspeed / top_speed, -1.0, 1.0) * 0.42, k)
	roll = lerpf(roll, -in_turn * 0.35 * clampf(absf(fspeed) / 8.0, 0.25, 1.0), k)
	throttle_level = clampf(0.4 + in_lift * 0.3 + absf(in_forward) * 0.25, 0.0, 1.0)


func _apply_rotation() -> void:
	basis = Basis.from_euler(Vector3(pitch, yaw, roll))


## Returns true when the drone crashed this frame.
func _handle_collisions(before: Vector3, delta: float) -> bool:
	var limit := 11.0 if mode == 0 else 7.5
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		var n := c.get_normal()
		var impact := -before.dot(n)
		if impact > limit:
			_crash("Удар на скорости %d км/ч" % roundi(before.length() * 3.6))
			return true
		if n.y > 0.7:
			# Resting on the ground or a roof: skid to a stop.
			var f := exp(-5.0 * delta)
			velocity.x *= f
			velocity.z *= f
	return false


func _check_limits() -> void:
	var p := global_position
	if world.in_lake(p.x, p.z) and p.y < WorldScript.WATER_Y + 0.12:
		_crash("Дрон упал в воду")
		return
	if p.y < world.grid_height(p.x, p.z) - 1.5:
		_crash("Дрон ушёл под землю")
		return
	if absf(p.x) > LIMIT:
		p.x = signf(p.x) * LIMIT
		velocity.x = 0.0
	if absf(p.z) > LIMIT:
		p.z = signf(p.z) * LIMIT
		velocity.z = 0.0
	if p.y > CEILING:
		p.y = CEILING
		velocity.y = minf(velocity.y, 0.0)
	global_position = p


func _crash(reason: String) -> void:
	if not active:
		return
	active = false
	velocity = Vector3.ZERO
	crashed.emit(reason)


func _update_cameras(delta: float) -> void:
	_shake_t += delta
	var shake := 0.0
	if active:
		shake = 0.0012 + throttle_level * 0.002 + minf(velocity.length(), 40.0) * 0.00006
	fpv_cam.rotation = Vector3(
		deg_to_rad(camera_tilt_deg) + look_pitch + sin(_shake_t * 47.0) * shake,
		0.0,
		sin(_shake_t * 39.0 + 1.3) * shake)

	# Widen the FPV view with speed: it sells the sense of speed.
	var speed_fov := BASE_FOV + clampf(velocity.length() / 55.0, 0.0, 1.0) * 16.0
	fpv_cam.fov = lerpf(fpv_cam.fov, speed_fov, 1.0 - exp(-3.0 * delta))

	var fwd := forward_flat()
	var target := global_position - fwd * 1.6 + Vector3.UP * 0.55
	var cam_pos := chase_cam.global_position.lerp(target, 1.0 - exp(-12.0 * delta))
	if world != null:
		cam_pos.y = maxf(cam_pos.y, world.surface_height(cam_pos.x, cam_pos.z) + 0.3)
	chase_cam.global_position = cam_pos
	var look := global_position + fwd * 2.0 + Vector3.UP * (0.15 + look_pitch * 2.5)
	if not cam_pos.is_equal_approx(look):
		chase_cam.look_at(look, Vector3.UP)
