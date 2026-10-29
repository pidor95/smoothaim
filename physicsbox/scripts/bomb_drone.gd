class_name BombDrone
extends FpvDrone
## The player's drop drone: a Mavic with a printed drop rig and two F-1s
## under the belly (Blender, tools/blender/build_drone_kit.py), flown through
## its gimbal camera. It hangs where it is, climbs to a safe height on
## launch, and lets go of a grenade with СБРОС (they go off on impact). The
## gimbal looks down (swipe to turn and tilt it); the HUD marks where a drop
## would land. ВЫХОД flies it home - it comes back to the player with its
## grenades re-armed. Crashing or being shot down loses it.

const BOMB_SCENE := "res://assets/weapons/bomb_drone.glb"
const GRENADE_SCENE := "res://assets/weapons/f1.glb"
const BOMB_BATTERY := 150.0
const CRUISE := 13.0
const CLIMB_SPEED := 5.0
const LIFT_HEIGHT := 22.0 # climbs this high over the launch point by itself

var grenades := 0
var impact_point := Vector3.ZERO
var impact_valid := false
var agl := 0.0 # height over whatever is below it
var zoomed := false # the camera's zoom (ЗУМ / ПКМ): a man 25 m below is a dot without it
var _grenade_nodes: Array[Node3D] = []
var _lift_to := NAN # set on the first frame (it is placed after _ready)
var _cam_mount := Vector3(0, -0.02, -0.08)
var _predict_cd := 0


func _init() -> void:
	team = 0
	scene_path = BOMB_SCENE
	battery_max = BOMB_BATTERY
	_pitch = -1.45 # the gimbal looks almost straight down, like for a drop


func _setup(model: Node3D) -> void:
	(get_child(0) as CollisionShape3D).shape.size = Vector3(0.44, 0.22, 0.38)
	var cam := model.find_child("Cam", true, false) as Node3D
	if cam:
		_cam_mount = cam.position
	for i in 2:
		var g := model.find_child("Grenade%d" % i, true, false) as Node3D
		if g:
			_grenade_nodes.append(g)
	grenades = _grenade_nodes.size()
	camera.fov = 72.0
	camera.position = _cam_mount
	_buzz.pitch_scale = 1.35
	_buzz.volume_db = -2.0


func look_input(delta_px: Vector2) -> void:
	var s := 0.0022 * Settings.sensitivity
	_yaw -= delta_px.x * s
	_pitch = clampf(_pitch - delta_px.y * s, -1.55, 0.25)


## СБРОС: lets go of the next grenade.
func trigger_pressed() -> void:
	drop()


## ВЫХОД: flies back to the player.
func exit_pressed() -> void:
	if dead:
		return
	dead = true
	if pilot:
		pilot.bomber_back(self)
	queue_free()


func drop() -> bool:
	if dead or grenades <= 0:
		return false
	grenades -= 1
	var node := _grenade_nodes[grenades]
	node.visible = false
	var g := Grenade.throw(get_tree(), node.global_position, velocity, true, 9.0, GRENADE_SCENE, true)
	g.global_basis = node.global_basis
	g.angular_velocity = Vector3(randf_range(-2, 2), randf_range(-2, 2), randf_range(-2, 2))
	g.add_collision_exception_with(self)
	Sfx.play("dry_fire", -4.0, 0.1) # the servo lets go
	return true


func _physics_process(delta: float) -> void:
	if dead:
		return
	battery -= delta
	if battery <= 0.0:
		crash() # flat battery: it falls out of the sky
		return
	for i in _props.size():
		_props[i].rotate_y((80.0 if i % 2 == 0 else -80.0) * delta)
	var stick := pilot.touch_move if pilot else Vector2.ZERO
	var arrows := pilot.drone_arrows if pilot else Vector2.ZERO
	var climb := pilot.drone_climb if pilot else 0.0
	if pilot and not pilot.touch_mode:
		stick += Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		arrows += Input.get_vector("fpv_left", "fpv_right", "fpv_down", "fpv_up")
		climb += Input.get_axis("fpv_sink", "fpv_climb")
	if is_nan(_lift_to):
		_lift_to = global_position.y + LIFT_HEIGHT
	if absf(climb) > 0.05:
		_lift_to = -INF # the pilot has taken over the height
	elif global_position.y < _lift_to:
		climb = 1.0
	var throttle := clampf(arrows.y - stick.y, -1.0, 1.0)
	var turn := clampf(arrows.x, -1.0, 1.0)
	var strafe := clampf(stick.x, -1.0, 1.0)
	climb = clampf(climb, -1.0, 1.0)
	_yaw -= turn * 1.4 * delta
	var heading := Basis(Vector3.UP, _yaw)
	var want := heading * Vector3(strafe * 8.0, 0.0, -throttle * CRUISE) + Vector3.UP * climb * CLIMB_SPEED
	velocity = velocity.lerp(want, clampf(delta * (1.8 if want.length() > 0.1 else 2.6), 0.0, 1.0))
	# the frame leans into its motion; the gimbal keeps the picture level
	var local := heading.inverse() * velocity
	var tip := clampf(local.z / CRUISE, -1.0, 1.0) * 0.35
	var bank := clampf(-local.x / 8.0, -1.0, 1.0) * 0.3
	basis = (heading * Basis(Vector3.RIGHT, tip) * Basis(Vector3.BACK, bank)).orthonormalized()
	camera.global_transform = Transform3D(heading * Basis(Vector3.RIGHT, _pitch), global_transform * _cam_mount)
	var before := velocity.length()
	var col := move_and_collide(velocity * delta)
	if col:
		if _crash(col.get_collider(), before):
			return
		velocity = velocity.slide(col.get_normal())
	_buzz.pitch_scale = 1.3 + velocity.length() / CRUISE * 0.25 + absf(climb) * 0.12
	var aim := pilot != null and not pilot.touch_mode and Input.is_action_pressed("aim")
	camera.fov = move_toward(camera.fov, 24.0 if zoomed or aim else 72.0, delta * 160.0)
	_predict_cd -= 1
	if _predict_cd <= 0:
		_predict_cd = 3
		_predict()
	if global_position.y < -30.0:
		_finish()


## Where a grenade let go now would come down (and how high it flies).
func _predict() -> void:
	var space := get_world_3d().direct_space_state
	var p := global_position + Vector3.DOWN * 0.08
	var v := velocity
	var g := Vector3(0, -ProjectSettings.get_setting("physics/3d/default_gravity", 9.8), 0)
	impact_valid = false
	for i in 120:
		var nv := v + g * 0.05
		var np := p + (v + nv) * 0.025
		var q := PhysicsRayQueryParameters3D.create(p, np, 1 | 2 | 4)
		q.exclude = [get_rid()]
		var hit := space.intersect_ray(q)
		if not hit.is_empty():
			impact_point = hit.position
			impact_valid = true
			break
		p = np
		v = nv
	var down := PhysicsRayQueryParameters3D.create(global_position, global_position + Vector3.DOWN * 300.0, 1 | 2)
	down.exclude = [get_rid()]
	var below := space.intersect_ray(down)
	agl = global_position.y - (below.position.y if not below.is_empty() else -0.5)


func _crash(hit: Object, speed: float) -> bool:
	if speed > 5.0 or ((hit is Player or hit is Npc or (hit != null and hit.has_meta("npc"))) and speed > 2.5):
		crash()
		return true
	return false


func take_bullet(_pos: Vector3, _dir: Vector3, _damage: float) -> void:
	crash()


## Shot down, crashed or out of battery: it breaks up (the grenades still
## on board go down with it as duds) and the link is gone.
func crash() -> void:
	if dead:
		return
	dead = true
	collision_layer = 0
	Sfx.play_3d("metal_hit", global_position, -2.0, 0.2)
	Blood.dust(global_position, Vector3.UP, Color(0.3, 0.3, 0.32))
	_finish()


func detonate(_power := 1.4) -> void:
	crash()
