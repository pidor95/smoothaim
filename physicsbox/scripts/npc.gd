class_name Npc
extends CharacterBody3D
## Mannequin NPC. Its body is 11 rigid parts. While standing they are
## kinematic and follow animations authored in Blender (MannequinAnims):
## locomotion clips blended by speed, hit reactions layered additively on top
## and per-bone springs kicked by each bullet. Every hit costs balance; when it
## runs out the body goes limp as a jointed ragdoll and later gets back up.
## Death leaves the ragdoll for good.

signal died(npc: Npc, headshot: bool)

enum State { IDLE, WANDER, PANIC, KNOCKED, GETUP, DEAD }

## Global AI switch (pause menu / HUD). When off NPCs just stand and take hits.
static var ai_enabled := true

const LAYER_WORLD := 1
const LAYER_PROPS := 2
const LAYER_PARTS := 4
const LAYER_NPC_BODY := 8
const LAYER_DEBRIS := 32

# Joint pivots (NPC local space, feet at y=0, facing -Z). Must match the
# Blender armature in tools/blender/build_mannequin_anims.py.
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

# Rest-pose centres of the parts, in MannequinAnims.BONES order.
const CENTERS := [
	Vector3(0, 0.97, 0), Vector3(0, 1.3, 0), Vector3(0, 1.69, 0),
	Vector3(-0.265, 1.33, 0), Vector3(-0.265, 1.04, 0), Vector3(0.265, 1.33, 0), Vector3(0.265, 1.04, 0),
	Vector3(-0.1, 0.71, 0), Vector3(-0.1, 0.29, 0), Vector3(0.1, 0.71, 0), Vector3(0.1, 0.29, 0),
]

# Joint frames: X = twist axis pointing down / up the bone, hinge Z = body X.
const JB_DOWN := Basis(Vector3(0, -1, 0), Vector3(1, 0, 0), Vector3(0, 0, 1))
const JB_UP := Basis(Vector3(0, 1, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1))
const JB_HINGE := Basis(Vector3(0, -1, 0), Vector3(0, 0, -1), Vector3(1, 0, 0))

# How much a hit on each part costs in balance per unit of impulse.
const BALANCE_COST := {"pelvis": 0.045, "chest": 0.03, "head": 0.04, "uarm_l": 0.014, "uarm_r": 0.014,
		"farm_l": 0.012, "farm_r": 0.012, "thigh_l": 0.06, "thigh_r": 0.06, "shin_l": 0.07, "shin_r": 0.07}
# Spring "mass" per bone: lighter bones get kicked further by a bullet.
const SPRING_MASS := [9.0, 7.0, 2.2, 1.6, 1.0, 1.6, 1.0, 4.0, 2.4, 4.0, 2.4]

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
var balance := 1.0
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
var parts: Array[RigidBody3D] = [] # in MannequinAnims.BONES order

var _lib: MannequinAnims
var _c_idle: MannequinAnims.Clip
var _c_walk: MannequinAnims.Clip
var _c_panic: MannequinAnims.Clip
var _agent: NavigationAgent3D
var _state_time := 0.0
var _t_idle := randf() * 3.0
var _t_walk := 0.0
var _t_panic := 0.0
var _w_walk := 0.0
var _w_panic := 0.0
var _reacts: Array = [] # [{clip, t, w}]
var _spring := PackedVector3Array()
var _spring_vel := PackedVector3Array()
var _head_yaw := 0.0
var _speed := 1.4
var _stuck_time := 0.0
var _last_pos := Vector3.ZERO
var _joints: Array[Joint3D] = []
var _knock_time := 0.0
var _getup: MannequinAnims.Clip
var _getup_t := 0.0
var _blend_from: Array[Transform3D] = []
var _blend_w := 1.0
var _wounds: Array = []
var _bleed_left := 0.0
var _bleed_cd := 0.0
var _pool: MeshInstance3D
var _pool_done := false
var _dead_time := 0.0
var _fall_sound_cd := 0.0
var _guts_spilled := false
var _hit_frame := -1
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

	_lib = MannequinAnims.get_lib()
	_c_idle = _lib.clip("idle")
	_c_walk = _lib.clip("walk")
	_c_panic = _lib.clip("panic_run")
	_spring.resize(CENTERS.size())
	_spring_vel.resize(CENTERS.size())

	_outfit = OUTFITS[outfit_index if outfit_index >= 0 else randi() % OUTFITS.size()]
	_build_body()
	_state_time = randf_range(0.5, 2.5)
	_last_pos = global_position
	_apply_pose(_compute_pose())


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
	_visual(head, _sphere_mesh(0.115, 0.27), skin)
	_visual(head, _capsule_mesh(0.05, 0.16), skin, Vector3(0, -0.14, 0))
	_visual(head, _sphere_mesh(0.014, 0.02), eyes, Vector3(-0.042, 0.02, -0.103))
	_visual(head, _sphere_mesh(0.014, 0.02), eyes, Vector3(0.042, 0.02, -0.103))
	var hsh := SphereShape3D.new()
	hsh.radius = 0.125
	_shape(head, hsh)

	uarm_l = _limb("uarm_l", 2.5, 0.058, 0.34, shirt)
	farm_l = _limb("farm_l", 1.8, 0.05, 0.3, shirt)
	uarm_r = _limb("uarm_r", 2.5, 0.058, 0.34, shirt)
	farm_r = _limb("farm_r", 1.8, 0.05, 0.3, shirt)
	for f in [farm_l, farm_r]:
		_visual(f, _sphere_mesh(0.048, 0.12), skin, Vector3(0, -0.19, 0), Vector3.ZERO, Vector3(0.85, 1, 1.1))
	thigh_l = _limb("thigh_l", 7.0, 0.08, 0.48, pants)
	shin_l = _limb("shin_l", 4.0, 0.065, 0.46, pants)
	thigh_r = _limb("thigh_r", 7.0, 0.08, 0.48, pants)
	shin_r = _limb("shin_r", 4.0, 0.065, 0.46, pants)
	for s in [shin_l, shin_r]:
		_visual(s, _box_mesh(Vector3(0.11, 0.08, 0.26)), shoes, Vector3(0, -0.24, -0.06))
		var fsh := BoxShape3D.new()
		fsh.size = Vector3(0.11, 0.08, 0.26)
		_shape(s, fsh, Vector3(0, -0.24, -0.06))
	parts = [pelvis, chest, head, uarm_l, farm_l, uarm_r, farm_r, thigh_l, shin_l, thigh_r, shin_r]


# ------------------------------------------------------------------ animation

## Bone transforms (NPC space) from the blended animation layers.
func _compute_pose() -> Array[Transform3D]:
	var L := _lib
	var n := CENTERS.size()
	var globals: Array[Transform3D] = []
	globals.resize(n)
	for i in n:
		var q: Quaternion
		var p: Vector3
		if state == State.GETUP:
			q = L.rot(_getup, i, _getup_t)
			p = L.pelvis_pos(_getup, _getup_t) if i == 0 else L.rest_local[i].origin
		else:
			q = L.rot(_c_idle, i, _t_idle)
			p = L.pelvis_pos(_c_idle, _t_idle) if i == 0 else L.rest_local[i].origin
			if _w_walk > 0.001:
				q = q.slerp(L.rot(_c_walk, i, _t_walk), _w_walk)
				if i == 0:
					p = p.lerp(L.pelvis_pos(_c_walk, _t_walk), _w_walk)
			if _w_panic > 0.001:
				q = q.slerp(L.rot(_c_panic, i, _t_panic), _w_panic)
				if i == 0:
					p = p.lerp(L.pelvis_pos(_c_panic, _t_panic), _w_panic)
		# hit reactions, additive relative to the rest pose
		for r in _reacts:
			var d: Quaternion = L.rest_rot[i].inverse() * L.rot(r.clip, i, r.t)
			q = q * Quaternion.IDENTITY.slerp(d, r.w)
			if i == 0:
				p += (L.pelvis_pos(r.clip, r.t) - L.rest_local[0].origin) * r.w
		# bullet springs (rotation vector in NPC rest axes)
		var e := _spring[i]
		if e.length_squared() > 0.000001:
			var gb := L.rest_global[i].basis
			q = q * Quaternion(gb.inverse() * Basis(e.normalized(), e.length()) * gb)
		if i == 2 and absf(_head_yaw) > 0.001:
			q = q * Quaternion(Vector3.UP, _head_yaw)
		var local := Transform3D(Basis(q), p)
		globals[i] = local if L.parent[i] < 0 else globals[L.parent[i]] * local
	return globals


## Places the kinematic parts from bone transforms.
func _apply_pose(globals: Array[Transform3D]) -> void:
	var g := global_transform
	for i in parts.size():
		var t := g * globals[i] * _lib.rest_global_inv[i] * Transform3D(Basis.IDENTITY, CENTERS[i])
		if _blend_w < 1.0 and _blend_from.size() == parts.size():
			t = _blend_from[i].interpolate_with(t, _blend_w)
		parts[i].global_transform = t


func _update_layers(delta: float, hspeed: float) -> void:
	_t_idle = fposmod(_t_idle + delta, _c_idle.length)
	var panic := state == State.PANIC
	_t_walk = fposmod(_t_walk + delta * maxf(hspeed, 0.4) / 1.3, _c_walk.length)
	_t_panic = fposmod(_t_panic + delta * maxf(hspeed, 1.0) / 4.3, _c_panic.length)
	var moving := clampf(hspeed / 1.2, 0.0, 1.0)
	_w_walk = lerpf(_w_walk, 0.0 if panic else moving, clampf(delta * 8.0, 0.0, 1.0))
	_w_panic = lerpf(_w_panic, moving if panic else 0.0, clampf(delta * 6.0, 0.0, 1.0))
	for i in range(_reacts.size() - 1, -1, -1):
		var r: Dictionary = _reacts[i]
		r.t += delta
		var left: float = r.clip.length - r.t
		r.w = clampf(left / 0.15, 0.0, 1.0) * clampf(r.t / 0.05, 0.0, 1.0)
		if left <= 0.0:
			_reacts.remove_at(i)
	for i in _spring.size():
		_spring_vel[i] += (-_spring[i] * 140.0 - _spring_vel[i] * 13.0) * delta
		_spring[i] += _spring_vel[i] * delta
	balance = minf(balance + delta * 0.3, 1.0)


# ------------------------------------------------------------------ AI

func _physics_process(delta: float) -> void:
	match state:
		State.DEAD:
			_dead_process(delta)
			return
		State.KNOCKED:
			_knocked_process(delta)
			return
		State.GETUP:
			_getup_process(delta)
			return

	var ai := ai_enabled and not display_only
	if not ai and state != State.IDLE:
		state = State.IDLE
	_state_time -= delta
	if ai:
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
	# reacting to a hit slows him down while he catches his balance
	desired *= clampf(0.35 + balance * 0.65, 0.0, 1.0)

	var accel := 10.0 if state == State.PANIC else 6.0
	velocity.x = move_toward(velocity.x, desired.x, accel * delta)
	velocity.z = move_toward(velocity.z, desired.z, accel * delta)
	if is_on_floor():
		velocity.y = -0.5
	else:
		velocity.y -= 9.8 * delta
	if not display_only:
		move_and_slide()

	var hspeed := Vector2(velocity.x, velocity.z).length()
	if hspeed > 0.3 and desired != Vector3.ZERO:
		rotation.y = lerp_angle(rotation.y, atan2(-velocity.x, -velocity.z), 7.0 * delta)

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

	var target_yaw := 0.0
	if state == State.IDLE and ai:
		var player := get_tree().get_first_node_in_group("player") as Node3D
		if player:
			var local := to_local(player.global_position)
			target_yaw = clampf(atan2(-local.x, -local.z), -1.0, 1.0)
	_head_yaw = lerp_angle(_head_yaw, target_yaw, 3.0 * delta)

	_update_layers(delta, hspeed)
	_bleed(delta, 0.25, 0.45)
	_apply_pose(_compute_pose())


func _random_nav_point() -> Vector3:
	return NavigationServer3D.map_get_random_point(get_world_3d().navigation_map, 1, false)


func _start_wander() -> void:
	state = State.WANDER
	_speed = randf_range(1.1, 1.6)
	var best := global_position
	for i in 4:
		var p := _random_nav_point()
		var d := p.distance_to(global_position)
		if d > 3.0 and d < 18.0:
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
	if dead or display_only or not ai_enabled:
		return
	if state == State.IDLE or state == State.WANDER:
		state = State.PANIC
		_flee_target()
	if state == State.PANIC:
		_state_time = randf_range(6.0, 10.0)


# ------------------------------------------------------------------ damage

## Called by the gun for every bullet / pellet. `fx` scales the blood effects
## (pellets use less each). Returns 0 = hit, 1 = kill, 2 = headshot kill.
func take_hit(part: RigidBody3D, pos: Vector3, normal: Vector3, dir: Vector3, damage: float,
		impulse: float, fx := 1.0) -> int:
	var part_name: String = part.get_meta("part")
	var is_head := part == head
	Blood.wound(part, pos, normal)
	Blood.mist(pos, normal * 0.6 - dir * 0.4, 0.8 * fx)
	Blood.spray(pos + dir * 0.12, dir + Vector3.UP * 0.1, int(10 * fx), 2.5, 6.5, 0.3)
	if _wounds.size() < 10:
		_wounds.append([part, part.to_local(pos)])
	_bleed_left = maxf(_bleed_left, 14.0)

	if dead:
		part.apply_impulse(dir * impulse, pos - part.global_position)
		return 0

	health -= damage
	var killed := health <= 0.0
	if state == State.KNOCKED:
		part.apply_impulse(dir * impulse, pos - part.global_position)
		if killed:
			_mark_dead(is_head)
			return 2 if is_head else 1
		_knock_time = minf(_knock_time, 1.0)
		return 0

	if killed:
		if is_head:
			Blood.mist(pos + dir * 0.1, dir, 2.2)
			Blood.spray(pos + dir * 0.15, dir + Vector3.UP * 0.25, 34, 3.5, 9.0, 0.45, 0.012, 0.035)
		_die(part, pos, dir, impulse * (1.5 if is_head else 1.0), is_head)
		return 2 if is_head else 1

	# still standing: react, try to keep balance, maybe fall over
	_react(part_name, pos, dir, impulse)
	balance -= impulse * BALANCE_COST.get(part_name, 0.02)
	if balance < 0.0:
		_knockdown(part, pos, dir, impulse)
	elif not display_only:
		velocity += Vector3(dir.x, 0, dir.z).normalized() * minf(impulse * 0.12, 2.5)
		alert(pos - dir)
	return 0


func _react(part_name: String, pos: Vector3, dir: Vector3, impulse: float) -> void:
	var local_dir := global_transform.basis.inverse() * dir
	# springs: the struck bone (and its parent) get spun around the hit point
	var bi := MannequinAnims.BONES.find(part_name)
	var local_pos := to_local(pos)
	var b := bi
	var falloff := 1.0
	while b >= 0 and falloff > 0.2:
		var pivot := _lib.rest_global[b].origin
		var kick: Vector3 = (local_pos - pivot).cross(local_dir) * impulse * falloff / SPRING_MASS[b] * 9.0
		_spring_vel[b] += kick.limit_length(14.0)
		b = _lib.parent[b]
		falloff *= 0.45

	# one animated reaction per frame (pellets arrive together)
	var frame := Engine.get_physics_frames()
	if frame == _hit_frame:
		return
	_hit_frame = frame
	var clip := ""
	match part_name:
		"head":
			clip = "react_head"
		"thigh_l", "shin_l":
			clip = "react_leg_l"
		"thigh_r", "shin_r":
			clip = "react_leg_r"
		"uarm_l", "farm_l":
			clip = "react_arm_l"
		"uarm_r", "farm_r":
			clip = "react_arm_r"
		_:
			if absf(local_dir.z) >= absf(local_dir.x):
				clip = "react_back" if local_dir.z > 0.0 else "react_fwd"
			else:
				clip = "react_right" if local_dir.x > 0.0 else "react_left"
	var c := _lib.clip(clip)
	for r in _reacts:
		if r.clip == c:
			r.t = minf(r.t, 0.08)
			return
	if _reacts.size() >= 3:
		_reacts.pop_front()
	_reacts.append({"clip": c, "t": 0.0, "w": 0.0})


func _bleed(delta: float, cd_min: float, cd_max: float) -> void:
	if _wounds.is_empty() or _bleed_left <= 0.0:
		return
	_bleed_left -= delta
	_bleed_cd -= delta
	if _bleed_cd <= 0.0:
		_bleed_cd = randf_range(cd_min, cd_max)
		var w = _wounds[randi() % _wounds.size()]
		if is_instance_valid(w[0]):
			Blood.drip(w[0].to_global(w[1]), randf_range(0.015, 0.035))


# ------------------------------------------------------------------ ragdoll

func _go_limp(part: RigidBody3D, pos: Vector3, dir: Vector3, impulse: float) -> void:
	collision_layer = 0
	collision_mask = 0
	var vel := velocity
	velocity = Vector3.ZERO
	_reacts.clear()
	if _joints.is_empty():
		_make_joints()
	for p in parts:
		p.freeze = false
		p.collision_mask = LAYER_WORLD | LAYER_PROPS | LAYER_PARTS
		p.linear_velocity = vel
	part.apply_impulse(dir * impulse, pos - part.global_position)
	for p in [chest, pelvis, head]:
		p.contact_monitor = true
		p.max_contacts_reported = 2
		if not p.body_entered.is_connected(_on_part_contact):
			p.body_entered.connect(_on_part_contact.bind(p))


func _knockdown(part: RigidBody3D, pos: Vector3, dir: Vector3, impulse: float) -> void:
	state = State.KNOCKED
	_knock_time = 0.0
	_go_limp(part, pos, dir, impulse)
	# legs give way
	shin_l.angular_velocity = global_transform.basis.x * randf_range(-3, 3)
	shin_r.angular_velocity = global_transform.basis.x * randf_range(-3, 3)


func _die(part: RigidBody3D, pos: Vector3, dir: Vector3, impulse: float, headshot: bool) -> void:
	_go_limp(part, pos, dir, impulse)
	shin_l.angular_velocity = global_transform.basis.x * randf_range(-3, 3)
	shin_r.angular_velocity = global_transform.basis.x * randf_range(-3, 3)
	_mark_dead(headshot)


func _mark_dead(headshot: bool) -> void:
	dead = true
	state = State.DEAD
	if is_instance_valid(_agent):
		_agent.queue_free()
	died.emit(self, headshot)


func _make_joints() -> void:
	_cone(pelvis, chest, P_SPINE, CENTERS[1], JB_UP, 25.0, 20.0)
	_cone(chest, head, P_NECK, CENTERS[2], JB_UP, 40.0, 45.0)
	_cone(chest, uarm_l, P_SHOULDER_L, CENTERS[3], JB_DOWN, 85.0, 50.0)
	_cone(chest, uarm_r, P_SHOULDER_R, CENTERS[5], JB_DOWN, 85.0, 50.0)
	_cone(pelvis, thigh_l, P_HIP_L, CENTERS[7], JB_DOWN, 65.0, 20.0)
	_cone(pelvis, thigh_r, P_HIP_R, CENTERS[9], JB_DOWN, 65.0, 20.0)
	# Hinge angle is measured opposite to the body-space X rotation:
	# elbows may only bend forward, knees only backward.
	_hinge(uarm_l, farm_l, P_ELBOW_L, CENTERS[4], -140.0, 0.0)
	_hinge(uarm_r, farm_r, P_ELBOW_R, CENTERS[6], -140.0, 0.0)
	_hinge(thigh_l, shin_l, P_KNEE_L, CENTERS[8], 0.0, 140.0)
	_hinge(thigh_r, shin_r, P_KNEE_R, CENTERS[10], 0.0, 140.0)


## Joint frame placed on the child's current pose (pivot given in rest space).
## Parts are posed with rotations only, so rest-space offsets stay valid.
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
	_joints.append(j)


func _hinge(a: RigidBody3D, b: RigidBody3D, pivot: Vector3, rest_center: Vector3, lower: float, upper: float) -> void:
	var j := HingeJoint3D.new()
	add_child(j)
	j.global_transform = _joint_frame(b, pivot, rest_center, JB_HINGE)
	j.set_flag(HingeJoint3D.FLAG_USE_LIMIT, true)
	j.set_param(HingeJoint3D.PARAM_LIMIT_LOWER, deg_to_rad(lower))
	j.set_param(HingeJoint3D.PARAM_LIMIT_UPPER, deg_to_rad(upper))
	j.node_a = j.get_path_to(a)
	j.node_b = j.get_path_to(b)
	_joints.append(j)


func _on_part_contact(_body: Node, part: RigidBody3D) -> void:
	if _fall_sound_cd > 0.0:
		return
	var speed := part.linear_velocity.length()
	if speed > 1.8:
		_fall_sound_cd = 0.25
		Sfx.play_3d("body_fall", part.global_position, clampf(-14.0 + speed * 2.0, -14.0, 0.0))


# ------------------------------------------------------------------ knocked down / getting up

func _knocked_process(delta: float) -> void:
	_knock_time += delta
	_fall_sound_cd -= delta
	_bleed(delta, 0.15, 0.35)
	if chest.global_position.y < -40.0:
		queue_free()
		return
	var settled := chest.linear_velocity.length() < 0.5 and pelvis.linear_velocity.length() < 0.5
	if (_knock_time > 1.8 and settled) or _knock_time > 6.0:
		_start_getup()


func _start_getup() -> void:
	var saved: Array[Transform3D] = []
	for p in parts:
		saved.append(p.global_transform)
	for j in _joints:
		j.queue_free()
	_joints.clear()
	for p in parts:
		p.freeze = true
		p.collision_mask = 0
		p.contact_monitor = false
	var face_up := (chest.global_basis * Vector3(0, 0, -1)).y > 0.0
	_getup = _lib.clip("getup_back" if face_up else "getup_front")
	_getup_t = 0.0
	# turn the root so the clip's lying body lines up with the ragdoll
	var actual := head.global_position - pelvis.global_position
	actual.y = 0.0
	var anim_dir := Vector3(0, 0, 1) if face_up else Vector3(0, 0, -1)
	var yaw := atan2(actual.x, actual.z) - atan2(anim_dir.x, anim_dir.z)
	var base := pelvis.global_position
	var q := PhysicsRayQueryParameters3D.create(base + Vector3.UP * 0.3, base + Vector3.DOWN * 2.0, LAYER_WORLD | LAYER_PROPS)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	var floor_y: float = hit.position.y if not hit.is_empty() else base.y - 0.13
	global_transform = Transform3D(Basis(Vector3.UP, yaw), Vector3(base.x, floor_y, base.z))
	velocity = Vector3.ZERO
	_spring.fill(Vector3.ZERO)
	_spring_vel.fill(Vector3.ZERO)
	_blend_from = saved
	_blend_w = 0.0
	state = State.GETUP


func _getup_process(delta: float) -> void:
	_getup_t += delta
	_blend_w = minf(_blend_w + delta / 0.4, 1.0)
	_t_idle = fposmod(_t_idle + delta, _c_idle.length)
	_bleed(delta, 0.25, 0.45)
	_apply_pose(_compute_pose())
	if _getup_t >= _getup.length:
		collision_layer = LAYER_NPC_BODY
		collision_mask = LAYER_WORLD
		balance = 1.0
		_blend_w = 1.0
		state = State.IDLE
		_state_time = 0.5
		_w_walk = 0.0
		_w_panic = 0.0
		if ai_enabled and not display_only:
			alert(global_position)


func _dead_process(delta: float) -> void:
	_dead_time += delta
	_fall_sound_cd -= delta
	if chest.global_position.y < -40.0:
		queue_free()
		return
	_bleed(delta, 0.12, 0.3)
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


# ------------------------------------------------------------------ guts

## Close shotgun blast to the belly: a string of intestine spills out of the
## wound and hangs / drags on physics joints.
func spill_guts(part: RigidBody3D, pos: Vector3, normal: Vector3, dir: Vector3) -> void:
	if _guts_spilled:
		return
	_guts_spilled = true
	var mat := _mat(Color(0.72, 0.3, 0.32), 0.25)
	var dark := _mat(Color(0.45, 0.08, 0.1), 0.3)
	var seg_len := 0.085
	var radius := 0.028
	var out := (normal + Vector3.DOWN * 0.6).normalized()
	var prev: RigidBody3D = part
	var anchor := pos - normal * 0.03
	for i in 11:
		var s := RigidBody3D.new()
		s.mass = 0.12
		s.collision_layer = LAYER_DEBRIS
		s.collision_mask = LAYER_WORLD | LAYER_PROPS
		s.linear_damp = 0.6
		s.angular_damp = 3.0
		s.top_level = true
		s.set_meta("surface", "flesh")
		_visual(s, _capsule_mesh(radius, seg_len + radius * 2.0), mat if i % 3 != 2 else dark)
		var sh := CapsuleShape3D.new()
		sh.radius = radius
		sh.height = seg_len + radius * 2.0
		_shape(s, sh)
		add_child(s)
		var center := anchor + out * seg_len * (i + 0.5) + Vector3(randf_range(-0.02, 0.02), 0, randf_range(-0.02, 0.02))
		var side := out.cross(Vector3.FORWARD)
		if side.length() < 0.1:
			side = out.cross(Vector3.RIGHT)
		side = side.normalized()
		s.global_transform = Transform3D(Basis(side, out, side.cross(out)), center) # capsule axis (Y) along `out`
		s.linear_velocity = normal * randf_range(1.0, 2.2) + dir * 0.8 + Vector3.DOWN * 0.3
		var j := PinJoint3D.new()
		add_child(j)
		j.global_position = anchor + out * seg_len * i
		j.node_a = j.get_path_to(prev)
		j.node_b = j.get_path_to(s)
		prev = s
		if i % 4 == 1 and _wounds.size() < 14:
			_wounds.append([s, Vector3.ZERO])
	Blood.spray(pos, normal + Vector3.DOWN * 0.3, 26, 1.5, 4.5, 0.5, 0.015, 0.04)
	Blood.mist(pos, normal, 1.6)
	_bleed_left = maxf(_bleed_left, 25.0)


## Body hit position estimate for camera / spawn logic.
func center() -> Vector3:
	return chest.global_position if chest else global_position + Vector3.UP
