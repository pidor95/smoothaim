class_name Npc
extends CharacterBody3D
## Mannequin NPC. While alive its body parts are kinematic rigid bodies driven
## by a procedural animation; on death they are joined with joints and
## released as a physics ragdoll.

signal died(npc: Npc, headshot: bool)

enum State { IDLE, WANDER, PANIC, DEAD }

const LAYER_WORLD := 1
const LAYER_PROPS := 2
const LAYER_PARTS := 4
const LAYER_NPC_BODY := 8

# Rest-pose skeleton (NPC local space, feet at y=0, facing -Z).
const P_SPINE := Vector3(0, 1.08, 0)
const P_NECK := Vector3(0, 1.55, 0)
const P_SHOULDER_L := Vector3(-0.265, 1.47, 0)
const P_SHOULDER_R := Vector3(0.265, 1.47, 0)
const P_ELBOW_L := Vector3(-0.265, 1.19, 0)
const P_ELBOW_R := Vector3(0.265, 1.19, 0)
const P_HIP_L := Vector3(-0.1, 0.93, 0)
const P_HIP_R := Vector3(0.1, 0.93, 0)
const P_KNEE_L := Vector3(-0.1, 0.5, 0)
const P_KNEE_R := Vector3(0.1, 0.5, 0)

const C_PELVIS := Vector3(0, 0.97, 0)
const C_CHEST := Vector3(0, 1.3, 0)
const C_HEAD := Vector3(0, 1.69, 0)
const C_UARM_L := Vector3(-0.265, 1.33, 0)
const C_UARM_R := Vector3(0.265, 1.33, 0)
const C_FARM_L := Vector3(-0.265, 1.04, 0)
const C_FARM_R := Vector3(0.265, 1.04, 0)
const C_THIGH_L := Vector3(-0.1, 0.71, 0)
const C_THIGH_R := Vector3(0.1, 0.71, 0)
const C_SHIN_L := Vector3(-0.1, 0.29, 0)
const C_SHIN_R := Vector3(0.1, 0.29, 0)

# Joint frames: X = twist axis pointing down / up the bone, hinge Z = body X.
const JB_DOWN := Basis(Vector3(0, -1, 0), Vector3(1, 0, 0), Vector3(0, 0, 1))
const JB_UP := Basis(Vector3(0, 1, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1))
const JB_HINGE := Basis(Vector3(0, -1, 0), Vector3(0, 0, -1), Vector3(1, 0, 0))

const OUTFITS := [
	{"shirt": Color(0.05, 0.05, 0.06), "pants": Color(0.05, 0.05, 0.06), "skin": Color(0.93, 0.89, 0.85)},
	{"shirt": Color(0.92, 0.92, 0.92), "pants": Color(0.06, 0.06, 0.07), "skin": Color(0.07, 0.065, 0.065)},
	{"shirt": Color(0.07, 0.07, 0.08), "pants": Color(0.78, 0.6, 0.42), "skin": Color(0.95, 0.78, 0.66)},
	{"shirt": Color(0.94, 0.94, 0.94), "pants": Color(0.06, 0.06, 0.07), "skin": Color(0.86, 0.66, 0.24)},
	{"shirt": Color(0.36, 0.22, 0.16), "pants": Color(0.12, 0.13, 0.16), "skin": Color(0.42, 0.27, 0.18)},
	{"shirt": Color(0.85, 0.32, 0.08), "pants": Color(0.85, 0.32, 0.08), "skin": Color(0.85, 0.32, 0.08)},
]

static var _mesh_cache := {}
static var _mat_cache := {}

var state := State.IDLE
var health := 100.0
var display_only := false # menu mannequin: stands still, no AI
var outfit_index := -1 # -1 = random
var dead := false

var pelvis: RigidBody3D
var chest: RigidBody3D
var head: RigidBody3D
var uarm_l: RigidBody3D
var uarm_r: RigidBody3D
var farm_l: RigidBody3D
var farm_r: RigidBody3D
var thigh_l: RigidBody3D
var thigh_r: RigidBody3D
var shin_l: RigidBody3D
var shin_r: RigidBody3D
var parts: Array[RigidBody3D] = []

var _agent: NavigationAgent3D
var _state_time := 0.0
var _walk_phase := 0.0
var _walk_amount := 0.0
var _panic_amount := 0.0
var _time := randf() * 10.0
var _flinch := Vector2.ZERO
var _flinch_vel := Vector2.ZERO
var _head_yaw := 0.0
var _speed := 1.4
var _stuck_time := 0.0
var _last_pos := Vector3.ZERO
var _wounds: Array = []
var _bleed_left := 0.0
var _bleed_cd := 0.0
var _pool: MeshInstance3D
var _pool_done := false
var _dead_time := 0.0
var _fall_sound_cd := 0.0
var _outfit: Dictionary


func _ready() -> void:
	add_to_group("npcs")
	collision_layer = LAYER_NPC_BODY
	collision_mask = LAYER_WORLD
	floor_snap_length = 0.3
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.8
	cs.shape = cap
	cs.position = Vector3(0, 0.9, 0)
	add_child(cs)

	_agent = NavigationAgent3D.new()
	_agent.radius = 0.35
	_agent.height = 1.8
	_agent.path_desired_distance = 0.6
	_agent.target_desired_distance = 0.7
	_agent.path_max_distance = 3.0
	add_child(_agent)

	_outfit = OUTFITS[outfit_index if outfit_index >= 0 else randi() % OUTFITS.size()]
	_build_body()
	_state_time = randf_range(0.5, 2.5)
	_last_pos = global_position
	_pose()


# ------------------------------------------------------------------ building

func _mat(color: Color, roughness := 0.75, emission := false) -> StandardMaterial3D:
	var key := "%s_%s_%s" % [color.to_html(), roughness, emission]
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	if emission:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat_cache[key] = m
	return m


func _capsule_mesh(radius: float, height: float) -> CapsuleMesh:
	var key := "cap_%s_%s" % [radius, height]
	if not _mesh_cache.has(key):
		var m := CapsuleMesh.new()
		m.radius = radius
		m.height = height
		m.radial_segments = 14
		m.rings = 5
		_mesh_cache[key] = m
	return _mesh_cache[key]


func _sphere_mesh(radius: float, height: float) -> SphereMesh:
	var key := "sph_%s_%s" % [radius, height]
	if not _mesh_cache.has(key):
		var m := SphereMesh.new()
		m.radius = radius
		m.height = height
		m.radial_segments = 16
		m.rings = 10
		_mesh_cache[key] = m
	return _mesh_cache[key]


func _box_mesh(size: Vector3) -> BoxMesh:
	var key := "box_%s" % size
	if not _mesh_cache.has(key):
		var m := BoxMesh.new()
		m.size = size
		_mesh_cache[key] = m
	return _mesh_cache[key]


func _visual(body: Node3D, mesh: Mesh, mat: Material, pos := Vector3.ZERO, rot := Vector3.ZERO, scl := Vector3.ONE) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	mi.scale = scl
	body.add_child(mi)


func _shape(body: Node3D, shape: Shape3D, pos := Vector3.ZERO, rot := Vector3.ZERO) -> void:
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = pos
	cs.rotation = rot
	body.add_child(cs)


func _part(part_name: String, mass: float) -> RigidBody3D:
	var b := RigidBody3D.new()
	b.name = part_name
	b.top_level = true
	b.mass = mass
	b.freeze = true
	b.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	b.collision_layer = LAYER_PARTS
	b.collision_mask = 0
	b.linear_damp = 0.05
	b.angular_damp = 1.2
	b.set_meta("npc", self)
	b.set_meta("surface", "flesh")
	b.set_meta("part", part_name)
	add_child(b)
	parts.append(b)
	return b


func _limb(part_name: String, mass: float, radius: float, length: float, mat: Material) -> RigidBody3D:
	var b := _part(part_name, mass)
	_visual(b, _capsule_mesh(radius, length), mat)
	var sh := CapsuleShape3D.new()
	sh.radius = radius
	sh.height = length
	_shape(b, sh)
	return b


func _build_body() -> void:
	var shirt := _mat(_outfit.shirt)
	var pants := _mat(_outfit.pants)
	var skin := _mat(_outfit.skin, 0.6)
	var shoes := _mat(Color(0.04, 0.04, 0.04), 0.5)
	var eyes := _mat(Color(1, 1, 1), 0.5, true)

	pelvis = _part("pelvis", 10.0)
	_visual(pelvis, _capsule_mesh(0.125, 0.38), pants, Vector3.ZERO, Vector3(0, 0, PI / 2), Vector3(1, 1, 0.85))
	var psh := CapsuleShape3D.new()
	psh.radius = 0.12
	psh.height = 0.36
	_shape(pelvis, psh, Vector3.ZERO, Vector3(0, 0, PI / 2))

	chest = _part("chest", 14.0)
	_visual(chest, _capsule_mesh(0.17, 0.56), shirt, Vector3.ZERO, Vector3.ZERO, Vector3(1.2, 1, 0.78))
	var csh := BoxShape3D.new()
	csh.size = Vector3(0.38, 0.48, 0.25)
	_shape(chest, csh)

	head = _part("head", 5.0)
	head.set_meta("part", "head")
	_visual(head, _sphere_mesh(0.115, 0.27), skin)
	_visual(head, _capsule_mesh(0.05, 0.16), skin, Vector3(0, -0.14, 0))
	_visual(head, _sphere_mesh(0.014, 0.02), eyes, Vector3(-0.042, 0.02, -0.103))
	_visual(head, _sphere_mesh(0.014, 0.02), eyes, Vector3(0.042, 0.02, -0.103))
	var hsh := SphereShape3D.new()
	hsh.radius = 0.125
	_shape(head, hsh)

	uarm_l = _limb("uarm_l", 2.5, 0.058, 0.34, shirt)
	uarm_r = _limb("uarm_r", 2.5, 0.058, 0.34, shirt)
	farm_l = _limb("farm_l", 1.8, 0.05, 0.3, shirt)
	farm_r = _limb("farm_r", 1.8, 0.05, 0.3, shirt)
	for f in [farm_l, farm_r]:
		_visual(f, _sphere_mesh(0.048, 0.12), skin, Vector3(0, -0.19, 0), Vector3.ZERO, Vector3(0.85, 1, 1.1))
	thigh_l = _limb("thigh_l", 7.0, 0.08, 0.48, pants)
	thigh_r = _limb("thigh_r", 7.0, 0.08, 0.48, pants)
	shin_l = _limb("shin_l", 4.0, 0.065, 0.46, pants)
	shin_r = _limb("shin_r", 4.0, 0.065, 0.46, pants)
	for s in [shin_l, shin_r]:
		_visual(s, _box_mesh(Vector3(0.11, 0.08, 0.26)), shoes, Vector3(0, -0.24, -0.06))
		var fsh := BoxShape3D.new()
		fsh.size = Vector3(0.11, 0.08, 0.26)
		_shape(s, fsh, Vector3(0, -0.24, -0.06))


# ------------------------------------------------------------------ animation

static func _about(pivot: Vector3, b: Basis) -> Transform3D:
	return Transform3D(b, pivot) * Transform3D(Basis.IDENTITY, -pivot)


func _pose() -> void:
	var walk := _walk_amount
	var panic := _panic_amount
	var ph := _walk_phase
	var breath := sin(_time * 1.7) * 0.02
	var stride := 0.55 + 0.25 * panic

	var bob := -absf(sin(ph)) * 0.05 * walk
	var t_pelvis := Transform3D(Basis(Vector3.UP, sin(ph) * 0.08 * walk), Vector3(0, bob, 0))

	var chest_pitch := -0.12 * panic * walk + breath + _flinch.x
	var chest_roll := _flinch.y
	var t_chest := t_pelvis * _about(P_SPINE, Basis.from_euler(Vector3(chest_pitch, -sin(ph) * 0.12 * walk, chest_roll)))
	var t_head := t_chest * _about(P_NECK, Basis.from_euler(Vector3(-chest_pitch * 0.5 + 0.1 * panic, _head_yaw, 0)))

	# Arms: swing opposite to legs; in panic they go up over the head.
	var swing := sin(ph) * 0.45 * walk * (1.0 - panic)
	var raise := lerpf(0.06, 2.75, panic)
	var elbow := lerpf(0.25 + 0.25 * walk, 0.55, panic)
	var flail := sin(_time * 9.0) * 0.25 * panic
	var t_uarm_l := t_chest * _about(P_SHOULDER_L, Basis.from_euler(Vector3(-swing + flail, 0, -raise)))
	var t_uarm_r := t_chest * _about(P_SHOULDER_R, Basis.from_euler(Vector3(swing - flail, 0, raise)))
	var t_farm_l := t_uarm_l * _about(P_ELBOW_L, Basis(Vector3.RIGHT, elbow))
	var t_farm_r := t_uarm_r * _about(P_ELBOW_R, Basis(Vector3.RIGHT, elbow))

	var leg_l := sin(ph) * stride * walk
	var leg_r := -leg_l
	var knee_l := -maxf(0.0, sin(ph + 1.6)) * (0.9 + 0.4 * panic) * walk
	var knee_r := -maxf(0.0, sin(ph + 1.6 + PI)) * (0.9 + 0.4 * panic) * walk
	var t_thigh_l := t_pelvis * _about(P_HIP_L, Basis(Vector3.RIGHT, leg_l))
	var t_thigh_r := t_pelvis * _about(P_HIP_R, Basis(Vector3.RIGHT, leg_r))
	var t_shin_l := t_thigh_l * _about(P_KNEE_L, Basis(Vector3.RIGHT, knee_l))
	var t_shin_r := t_thigh_r * _about(P_KNEE_R, Basis(Vector3.RIGHT, knee_r))

	var g := global_transform
	_place(pelvis, g * t_pelvis, C_PELVIS)
	_place(chest, g * t_chest, C_CHEST)
	_place(head, g * t_head, C_HEAD)
	_place(uarm_l, g * t_uarm_l, C_UARM_L)
	_place(uarm_r, g * t_uarm_r, C_UARM_R)
	_place(farm_l, g * t_farm_l, C_FARM_L)
	_place(farm_r, g * t_farm_r, C_FARM_R)
	_place(thigh_l, g * t_thigh_l, C_THIGH_L)
	_place(thigh_r, g * t_thigh_r, C_THIGH_R)
	_place(shin_l, g * t_shin_l, C_SHIN_L)
	_place(shin_r, g * t_shin_r, C_SHIN_R)


func _place(part: RigidBody3D, t: Transform3D, rest_center: Vector3) -> void:
	part.global_transform = t * Transform3D(Basis.IDENTITY, rest_center)


# ------------------------------------------------------------------ AI

func _physics_process(delta: float) -> void:
	_time += delta
	if dead:
		_dead_process(delta)
		return

	if display_only:
		_flinch_vel += (-_flinch * 120.0 - _flinch_vel * 12.0) * delta
		_flinch += _flinch_vel * delta
		_pose()
		return

	_state_time -= delta
	match state:
		State.IDLE:
			if _state_time <= 0.0:
				_start_wander()
		State.WANDER:
			if _agent.is_navigation_finished():
				state = State.IDLE
				_state_time = randf_range(1.0, 4.0)
		State.PANIC:
			if _state_time <= 0.0:
				state = State.IDLE
				_state_time = randf_range(2.0, 4.0)
			elif _agent.is_navigation_finished():
				_flee_target()

	var desired := Vector3.ZERO
	if state != State.IDLE and not _agent.is_navigation_finished():
		var next := _agent.get_next_path_position()
		var to := next - global_position
		to.y = 0.0
		if to.length() > 0.05:
			desired = to.normalized() * (_speed if state == State.WANDER else 4.3)

	var accel := 10.0 if state == State.PANIC else 6.0
	velocity.x = move_toward(velocity.x, desired.x, accel * delta)
	velocity.z = move_toward(velocity.z, desired.z, accel * delta)
	if is_on_floor():
		velocity.y = -0.5
	else:
		velocity.y -= 9.8 * delta
	move_and_slide()

	var hv := Vector2(velocity.x, velocity.z)
	var hspeed := hv.length()
	if hspeed > 0.2:
		var yaw := atan2(-velocity.x, -velocity.z)
		rotation.y = lerp_angle(rotation.y, yaw, 7.0 * delta)

	# stuck detection
	if desired != Vector3.ZERO:
		_stuck_time += delta
		if _stuck_time > 1.5:
			if global_position.distance_to(_last_pos) < 0.4:
				if state == State.PANIC:
					_flee_target()
				else:
					_start_wander()
			_stuck_time = 0.0
			_last_pos = global_position
	if global_position.y < -40.0:
		queue_free()
		return

	_walk_amount = lerpf(_walk_amount, clampf(hspeed / 1.4, 0.0, 1.0), 8.0 * delta)
	_walk_phase += delta * hspeed * (3.6 if state == State.PANIC else 4.2)
	_panic_amount = lerpf(_panic_amount, 1.0 if state == State.PANIC else 0.0, 5.0 * delta)

	# flinch spring
	_flinch_vel += (-_flinch * 120.0 - _flinch_vel * 12.0) * delta
	_flinch += _flinch_vel * delta

	# idle: look at the player
	var target_yaw := 0.0
	if state == State.IDLE:
		var player := get_tree().get_first_node_in_group("player") as Node3D
		if player:
			var local := to_local(player.global_position)
			target_yaw = clampf(atan2(-local.x, -local.z), -1.1, 1.1)
	_head_yaw = lerp_angle(_head_yaw, target_yaw, 3.0 * delta)

	_bleed_alive(delta)
	_pose()


func _random_nav_point() -> Vector3:
	var map := get_world_3d().navigation_map
	return NavigationServer3D.map_get_random_point(map, 1, false)


func _start_wander() -> void:
	state = State.WANDER
	_speed = randf_range(1.1, 1.6)
	var best := global_position
	for i in 4:
		var p := _random_nav_point()
		if p.distance_to(global_position) > 3.0 and p.distance_to(global_position) < 18.0:
			best = p
			break
	_agent.target_position = best
	_stuck_time = 0.0
	_last_pos = global_position


func _flee_target() -> void:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	var best := global_position
	var best_d := -1.0
	for i in 6:
		var p := _random_nav_point()
		var d := p.distance_to(player.global_position) if player else randf()
		if d > best_d:
			best_d = d
			best = p
	_agent.target_position = best
	_stuck_time = 0.0
	_last_pos = global_position


## Gunshot heard nearby.
func alert(_from: Vector3) -> void:
	if dead:
		return
	if state != State.PANIC:
		state = State.PANIC
		_flee_target()
	_state_time = randf_range(6.0, 10.0)


# ------------------------------------------------------------------ damage

## Called by the gun. Returns 0 = hit, 1 = kill, 2 = headshot kill.
func take_hit(part: RigidBody3D, pos: Vector3, normal: Vector3, dir: Vector3, damage: float, impulse: float) -> int:
	var is_head := part == head
	Blood.wound(part, pos, normal)
	Blood.mist(pos, normal * 0.6 - dir * 0.4, 0.8)
	Blood.spray(pos + dir * 0.12, dir + Vector3.UP * 0.1, 10, 2.5, 6.5, 0.3)
	Blood.spray(pos, normal + Vector3.UP * 0.4, 4, 0.8, 2.0, 0.5)
	if _wounds.size() < 8:
		_wounds.append([part, part.to_local(pos)])
	_bleed_left = maxf(_bleed_left, 14.0)

	if dead:
		part.apply_impulse(dir * impulse, pos - part.global_position)
		Sfx.play_3d("flesh", pos, -2.0)
		return 0

	health -= 999.0 if is_head else damage
	if health <= 0.0:
		if is_head:
			Sfx.play_3d("headshot", pos, 2.0)
			Blood.mist(pos + dir * 0.1, dir, 2.2)
			Blood.spray(pos + dir * 0.15, dir + Vector3.UP * 0.25, 34, 3.5, 9.0, 0.45, 0.012, 0.035)
		else:
			Sfx.play_3d("flesh", pos, 0.0)
		_die(part, pos, dir, impulse * (1.5 if is_head else 1.0), is_head)
		return 2 if is_head else 1

	Sfx.play_3d("flesh", pos, 0.0)
	var local_dir := global_transform.basis.inverse() * dir
	_flinch_vel += Vector2(local_dir.z, -local_dir.x) * 9.0
	if not display_only:
		velocity += Vector3(dir.x, 0, dir.z).normalized() * 1.8
		alert(pos - dir)
	return 0


func _bleed_alive(delta: float) -> void:
	if _wounds.is_empty():
		return
	_bleed_cd -= delta
	if _bleed_cd <= 0.0:
		_bleed_cd = randf_range(0.18, 0.4)
		var w = _wounds[randi() % _wounds.size()]
		if is_instance_valid(w[0]):
			Blood.drip(w[0].to_global(w[1]), randf_range(0.015, 0.03))


func _die(part: RigidBody3D, pos: Vector3, dir: Vector3, impulse: float, headshot: bool) -> void:
	dead = true
	state = State.DEAD
	collision_layer = 0
	collision_mask = 0
	_agent.queue_free()
	var vel := velocity
	_make_joints()
	for p in parts:
		p.freeze = false
		p.collision_mask = LAYER_WORLD | LAYER_PROPS | LAYER_PARTS
		p.linear_velocity = vel
	# legs give way: a little extra spin so the body crumples instead of toppling stiffly
	shin_l.angular_velocity = global_transform.basis.x * randf_range(-3, 3)
	shin_r.angular_velocity = global_transform.basis.x * randf_range(-3, 3)
	part.apply_impulse(dir * impulse, pos - part.global_position)
	for p in [chest, pelvis, head]:
		p.contact_monitor = true
		p.max_contacts_reported = 2
		p.body_entered.connect(_on_part_contact.bind(p))
	died.emit(self, headshot)


func _make_joints() -> void:
	_cone(pelvis, chest, P_SPINE, C_CHEST, JB_UP, 25.0, 20.0)
	_cone(chest, head, P_NECK, C_HEAD, JB_UP, 40.0, 45.0)
	_cone(chest, uarm_l, P_SHOULDER_L, C_UARM_L, JB_DOWN, 85.0, 50.0)
	_cone(chest, uarm_r, P_SHOULDER_R, C_UARM_R, JB_DOWN, 85.0, 50.0)
	_cone(pelvis, thigh_l, P_HIP_L, C_THIGH_L, JB_DOWN, 65.0, 20.0)
	_cone(pelvis, thigh_r, P_HIP_R, C_THIGH_R, JB_DOWN, 65.0, 20.0)
	# Hinge angle is measured opposite to the body-space X rotation:
	# elbows may only bend forward, knees only backward.
	_hinge(uarm_l, farm_l, P_ELBOW_L, C_FARM_L, -140.0, 0.0)
	_hinge(uarm_r, farm_r, P_ELBOW_R, C_FARM_R, -140.0, 0.0)
	_hinge(thigh_l, shin_l, P_KNEE_L, C_SHIN_L, 0.0, 140.0)
	_hinge(thigh_r, shin_r, P_KNEE_R, C_SHIN_R, 0.0, 140.0)


func _joint_frame(b: RigidBody3D, pivot: Vector3, rest_center: Vector3, jb: Basis) -> Transform3D:
	return b.global_transform * Transform3D(jb, pivot - rest_center)


func _cone(a: RigidBody3D, b: RigidBody3D, pivot: Vector3, rest_center: Vector3, jb: Basis, swing: float, twist: float) -> void:
	var j := ConeTwistJoint3D.new()
	add_child(j)
	j.global_transform = _joint_frame(b, pivot, rest_center, jb)
	j.set_param(ConeTwistJoint3D.PARAM_SWING_SPAN, deg_to_rad(swing))
	j.set_param(ConeTwistJoint3D.PARAM_TWIST_SPAN, deg_to_rad(twist))
	j.node_a = j.get_path_to(a)
	j.node_b = j.get_path_to(b)


func _hinge(a: RigidBody3D, b: RigidBody3D, pivot: Vector3, rest_center: Vector3, lower: float, upper: float) -> void:
	var j := HingeJoint3D.new()
	add_child(j)
	j.global_transform = _joint_frame(b, pivot, rest_center, JB_HINGE)
	j.set_flag(HingeJoint3D.FLAG_USE_LIMIT, true)
	j.set_param(HingeJoint3D.PARAM_LIMIT_LOWER, deg_to_rad(lower))
	j.set_param(HingeJoint3D.PARAM_LIMIT_UPPER, deg_to_rad(upper))
	j.node_a = j.get_path_to(a)
	j.node_b = j.get_path_to(b)


func _on_part_contact(_body: Node, part: RigidBody3D) -> void:
	if _fall_sound_cd > 0.0:
		return
	var speed := part.linear_velocity.length()
	if speed > 1.8:
		_fall_sound_cd = 0.25
		Sfx.play_3d("body_fall", part.global_position, clampf(-14.0 + speed * 2.0, -14.0, 0.0))


func _dead_process(delta: float) -> void:
	_dead_time += delta
	_fall_sound_cd -= delta
	if chest.global_position.y < -40.0:
		queue_free()
		return
	if _bleed_left > 0.0 and not _wounds.is_empty():
		_bleed_left -= delta
		_bleed_cd -= delta
		if _bleed_cd <= 0.0:
			_bleed_cd = randf_range(0.12, 0.3)
			var w = _wounds[randi() % _wounds.size()]
			if is_instance_valid(w[0]):
				Blood.drip(w[0].to_global(w[1]), randf_range(0.015, 0.035))
	# once the body settles, a pool of blood spreads underneath
	if not _pool_done and _dead_time > 1.0 and chest.linear_velocity.length() < 0.4 and not _wounds.is_empty():
		_pool_done = true
		var from := chest.global_position + Vector3.UP * 0.2
		var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 1.5, LAYER_WORLD | LAYER_PROPS)
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		if not hit.is_empty() and hit.normal.y > 0.7:
			_pool = Blood.pool(hit.position, hit.normal)
			var target := randf_range(1.0, 1.6) * Settings.blood_amount
			_pool.scale = Vector3(0.1, 0.1, 1.0)
			var tw := _pool.create_tween()
			tw.tween_property(_pool, "scale", Vector3(target, target, 1.0), 10.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


## Body hit position estimate for camera / spawn logic.
func center() -> Vector3:
	return chest.global_position if chest else global_position + Vector3.UP
