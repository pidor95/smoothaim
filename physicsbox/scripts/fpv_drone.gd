class_name FpvDrone
extends CharacterBody3D
## FPV kamikaze drone with a PG-7 warhead (model from Blender,
## tools/blender/build_explosives.py). Either the player flies it through
## its camera (`pilot` set) or it hunts a target by itself (`target` set,
## the enemy's drones). It goes off when it hits something at speed, when
## the pilot triggers it, or when it is shot; the battery lasts a minute.

const SCENE := "res://assets/weapons/fpv_drone.glb"
const MAX_SPEED := 24.0
const BATTERY := 60.0

var team := 1
var pilot: Player # flown by the player
var target: Node3D # hunted by itself
var battery := BATTERY
var camera := Camera3D.new()
var dead := false

var _yaw := 0.0
var _pitch := 0.0
var _speed := 12.0
var _props: Array[Node3D] = []
var _buzz := AudioStreamPlayer3D.new()
var _weave := randf() * TAU
static var _loop: AudioStream


func _ready() -> void:
	add_to_group("drones")
	collision_layer = 2 # props: bullets hit it
	collision_mask = 1 | 2 | 4 | 8 | 16
	set_meta("drone", true)
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(0.36, 0.14, 0.4)
	cs.shape = sh
	add_child(cs)
	var model: Node3D = (load(SCENE) as PackedScene).instantiate()
	add_child(model)
	# its own camera does not see the frame and props
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).layers = 2
	camera.cull_mask = 0xFFFFF & ~2
	for n in model.find_children("Prop*", "MeshInstance3D", true, false):
		_props.append(n)
	camera.position = Vector3(0, 0.02, -0.09)
	camera.rotation.x = deg_to_rad(18.0)
	camera.fov = 100.0
	camera.near = 0.02
	camera.far = 300.0
	add_child(camera)
	if _loop == null:
		var s: AudioStreamWAV = load("res://assets/sounds/drone_loop.wav").duplicate()
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_begin = 0
		s.loop_end = int(s.get_length() * s.mix_rate)
		_loop = s
	_buzz.stream = _loop
	_buzz.unit_size = 6.0
	_buzz.max_distance = 90.0
	_buzz.volume_db = 2.0
	add_child(_buzz)
	_buzz.play()
	_yaw = rotation.y
	if pilot:
		camera.current = true


## Mouse / swipe from the pilot: turn and climb / dive.
func look_input(delta_px: Vector2) -> void:
	var s := 0.0022 * Settings.sensitivity
	_yaw -= delta_px.x * s
	_pitch = clampf(_pitch - delta_px.y * s, -1.3, 1.0)


func _physics_process(delta: float) -> void:
	if dead:
		return
	battery -= delta
	if battery <= 0.0:
		detonate()
		return
	for i in _props.size():
		_props[i].rotate_y((70.0 if i % 2 == 0 else -70.0) * delta)
	var fwd := Vector3.FORWARD
	var strafe := 0.0
	if pilot:
		# stick: forward = faster, back = slower; sideways = strafe
		var stick := pilot.touch_move
		if not pilot.touch_mode:
			stick += Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		_speed = clampf(_speed - stick.y * 18.0 * delta, 4.0, MAX_SPEED)
		strafe = stick.x
		# the arrows (on screen or on the keyboard): turn and climb / dive
		var arrows := pilot.drone_arrows + Input.get_vector("fpv_left", "fpv_right", "fpv_down", "fpv_up")
		_yaw -= clampf(arrows.x, -1.0, 1.0) * 1.9 * delta
		_pitch = clampf(_pitch + clampf(arrows.y, -1.0, 1.0) * 1.3 * delta, -1.3, 1.0)
	elif is_instance_valid(target) and not (target is Npc and target.dead):
		# hunts its target: stays high over the trees, weaving a little, then
		# dives onto it from above
		var aim: Vector3 = (target.center() if target is Npc else target.global_position + Vector3.UP * 1.1)
		var flat := Vector2(aim.x - global_position.x, aim.z - global_position.z).length()
		if flat > 15.0:
			aim.y = maxf(aim.y + 9.0, global_position.y - 1.0)
			_weave += delta * 2.0
			aim += Vector3(sin(_weave), 0.0, cos(_weave * 0.7)) * clampf(flat * 0.08, 0.0, 2.5)
		var to := aim - global_position
		var want_yaw := atan2(-to.x, -to.z)
		var want_pitch := atan2(to.y, Vector2(to.x, to.z).length())
		_yaw = lerp_angle(_yaw, want_yaw, clampf(delta * 4.0, 0.0, 1.0))
		_pitch = lerp_angle(_pitch, want_pitch, clampf(delta * 4.0, 0.0, 1.0))
		_speed = minf(_speed + delta * 6.0, 19.0 if flat > 15.0 else 15.0)
		if (aim - global_position).length() < 1.8 and flat < 15.0:
			detonate()
			return
	else:
		target = null
		_pitch = lerpf(_pitch, -0.2, delta)
	var basis_now := Basis(Vector3.UP, _yaw) * Basis(Vector3.RIGHT, _pitch)
	fwd = basis_now * Vector3.FORWARD
	var right := basis_now * Vector3.RIGHT
	var want := fwd * _speed + right * strafe * 6.0
	velocity = velocity.lerp(want, clampf(delta * (3.0 if pilot else 5.0), 0.0, 1.0))
	# the body banks into turns and tips forward with speed
	var bank := clampf(-strafe * 0.5, -0.6, 0.6)
	basis = (basis_now * Basis(Vector3.RIGHT, -0.35 * _speed / MAX_SPEED) * Basis(Vector3.BACK, bank)).orthonormalized()
	var before := velocity.length()
	var col := move_and_collide(velocity * delta)
	if col:
		var hit := col.get_collider()
		if before > 3.5 or hit is Player or (hit is Object and hit.has_meta("npc")) or hit is Npc:
			detonate()
			return
		velocity = velocity.slide(col.get_normal())
	_buzz.pitch_scale = 0.85 + velocity.length() / MAX_SPEED * 0.5
	if global_position.y < -30.0:
		_finish()


## Shot by someone.
func take_bullet(_pos: Vector3, _dir: Vector3, _damage: float) -> void:
	detonate(0.6)


func detonate(power := 1.4) -> void:
	if dead:
		return
	dead = true
	collision_layer = 0 # out of the blast's line of sight checks
	Explosion.boom(get_tree(), global_position, power, pilot != null or team == 0, "blast_big")
	_finish()


func _finish() -> void:
	dead = true
	if pilot:
		pilot.drone_lost(self)
	queue_free()
