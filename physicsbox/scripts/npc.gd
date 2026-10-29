class_name Npc
extends CharacterBody3D
## Mannequin NPC. Its body is 11 rigid parts. While standing they are
## kinematic and follow animations authored in Blender (MannequinAnims):
## locomotion clips blended by speed, hit reactions layered additively on top
## and per-bone springs kicked by each bullet. Every hit costs balance; when it
## runs out the body goes limp as a jointed ragdoll and later gets back up.
## Death leaves the ragdoll for good.
## A neck shot opens the carotid: he clamps his throat with both hands and
## fights for air until he bleeds out. A lethal body hit may leave him down
## but alive, writhing on the floor, to be finished off.
## Soldiers: two teams (the player's side 0, the enemy 1) in camouflage,
## helmet and plate carrier, with an AK; they hold posts or assault the
## enemy line, spot enemies and fire bursts at them. They obey the player's
## orders (the enemy only when he has had enough), fire wildly while choking
## and with no way out may draw a pistol and shoot themselves.

signal died(npc: Npc, headshot: bool)

enum State { IDLE, WANDER, PANIC, STAGGER, KNOCKED, GETUP, DEAD, CHOKE, ORDER, SHOOT }

## Global AI switch (pause menu / HUD). When off NPCs just stand and take hits.
static var ai_enabled := true
## Teams: 0 = the player's side, 1 = the enemy.
const TEAM_NAMES := ["ВИТЯЗЬ", "ОПОЛЧЕНИЕ"]
const TEAM_CAMO := ["res://assets/textures/camo_green.png", "res://assets/textures/camo_tan.png"]
const TEAM_TAPE := [Color(0.2, 0.4, 1.0), Color(1.0, 0.82, 0.1)]
const SKINS := [Color(0.93, 0.8, 0.7), Color(0.85, 0.68, 0.55), Color(0.66, 0.48, 0.34), Color(0.95, 0.85, 0.76)]
const GEAR_SCENE := "res://assets/npc/soldier_gear.glb"
## A lethal body hit leaves him down but alive this often (to be finished off).
const SURVIVE_CHANCE := 0.4
## Pain: a heavy hit (or several in a row) may knock him out cold; he lies
## limp for a while (to be finished off) and then comes round.
const FAINT_PAIN := 70.0
const FAINT_CHANCE := 0.45
## With his throat shot through he fires blindly only this long, and only
## sometimes.
const WILD_FIRE_TIME := 5.0
const WILD_FIRE_CHANCE := 0.5
## Firing positions (front trench) of each team, set by the level.
static var war_posts: Array = [[], []]

# The pistol in the right hand, farm_r space. Must match HAND_R / GUN_BARREL /
# GUN_TOP in tools/blender/build_mannequin_anims.py (the suicide pose is
# solved for it): barrel along the forearm tipped 20 degrees forward.
const GUN_SCENE := "res://assets/npc/npc_pistol.glb"
const GUN_HAND := Vector3(0, -0.19, 0)
const GUN_BARREL := Vector3(0, -0.9397, -0.342)
const GUN_TOP := Vector3(0, 0.342, -0.9397)
const GUN_MUZZLE := Vector3(0, 0.056, -0.195) # in the gun model
const GUN_TEXTURE := "res://assets/m1911/m1911_albedo.jpg"
# The AK sits in the right hand with the wrist cocked; must match RIFLE_U /
# RIFLE_ATTACH in tools/blender/build_mannequin_anims.py (printed there).
const RIFLE_SCENE := "res://assets/npc/npc_rifle.glb"
const RIFLE_BASIS := Basis(Vector3(0.4422, 0.4624, -0.7685), Vector3(-0.4624, -0.6166, -0.6371),
		Vector3(-0.7685, 0.6371, -0.0588))
const RIFLE_MUZZLE := Vector3(0, 0.105, -0.666)
const RIFLE_MAG := 30
# Snipers carry an SVD (tools/blender/build_sketchfab_kit.py, same rifle frame).
const SVD_SCENE := "res://assets/npc/npc_svd.glb"
const SVD_MUZZLE := Vector3(0, 0.095, -0.992)
const SVD_MAG := 10
## A round with this much push (sniper rifles) goes through the plate and
## always puts a man down.
const HEAVY_ROUND := 20.0
const MAX_DROPPED_GUNS := 8
const MAGAZINE := 8
const BULLET_DAMAGE_PLAYER := 16.0
const BULLET_DAMAGE_NPC := 34.0

## Orders the player can shout: [command, what is shouted].
const ORDERS := [["stand", "СТОЯТЬ!"], ["hands_up", "РУКИ ВВЕРХ!"], ["kneel", "НА КОЛЕНИ!"],
		["drop", "БРОСЬ ОРУЖИЕ!"], ["come", "КО МНЕ!"], ["flee", "ПРОВАЛИВАЙ!"], ["free", "ВОЛЬНО"],
		["suicide", "ЗАСТРЕЛИСЬ!"]]
## Pose each order is held in ("" = just stand).
const ORDER_CLIPS := {"stand": "", "hands_up": "hands_up", "kneel": "kneel_hands_head", "come": ""}

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

# How much a hit on each part costs in balance per unit of impulse. He tries
# hard to stay on his feet, so it takes a few hits to put him down.
const BALANCE_COST := {"pelvis": 0.055, "chest": 0.042, "head": 0.045, "uarm_l": 0.016, "uarm_r": 0.016,
		"farm_l": 0.012, "farm_r": 0.012, "thigh_l": 0.06, "thigh_r": 0.06, "shin_l": 0.08, "shin_r": 0.08}
# Spring "mass" per bone: lighter bones get kicked further by a bullet.
const SPRING_MASS := [9.0, 7.0, 2.2, 1.6, 1.0, 1.6, 1.0, 4.0, 2.4, 4.0, 2.4]
## Muscles after death: the limbs that twitch and how hard (death throes).
const SPASM_PARTS := [4, 6, 8, 10, 3, 5, 7, 9, 2]

static var _mesh_cache := {}
static var _gear := {} # mesh name -> Mesh (soldier_gear.glb)
static var _camo_mats := {}
static var _ragdoll_material: PhysicsMaterial
static var _mat_cache := {}

var state := State.IDLE
var health := 100.0
var balance := 1.0
var display_only := false # menu mannequin: stands still, no AI
var dead := false
var armed := true # set before adding to the tree
var weapon := "rifle" # rifle | pistol
var team := 0
var role := "hold" # hold (his post in the line) | assault (the enemy's line)
var post := Vector3.ZERO
var suicided := false
var last_hit_by_player := false

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
var _clutch: MannequinAnims.Clip # hand pressed on the latest wound
var _clutch_mask := PackedFloat32Array()
var _clutch_w := 0.0
var _clutch_delay := 0.0
var _clutch_hold := 0.0
var _stagger: MannequinAnims.Clip
var _stagger_t := 0.0
var _stagger_prev := Vector3.ZERO
var _stagger_fall := false
var _fall_args: Array = []
var _wounds: Array = []
var _bleed_left := 0.0
var _bleed_cd := 0.0
var _pool_done := false
var _dead_time := 0.0
var _guts_spilled := false
var _skin_mat: StandardMaterial3D
var _head_visuals: Array[MeshInstance3D] = []
var _head_shape: CollisionShape3D
var head_gone := false
var _head_damage := 0.0 # decays; enough of it in a short time blows the head apart
var _joint_of := {} # child part -> joint holding it to its parent
var _severed := {}
var _arteries: Array = [] # [{part, pos, dir, strength, age}]
var _time := 0.0
var _hit_frame := -1
var _blend_time := 0.25
var _downed := false # left for dead: writhing on the floor, bleeding out
var _c_down_floor: MannequinAnims.Clip
var _c_down_roll_l: MannequinAnims.Clip
var _c_down_roll_r: MannequinAnims.Clip
var _muzzle := GUN_MUZZLE
var _target: Node3D # enemy he is fighting
var _scan_cd := 0.0
var _lost_t := 0.0
var _alerted_t := 0.0
var _burst_left := 0
var _nade_cd := randf_range(6.0, 20.0)
# neck wound
var _neck_wound := false
var _choke_drain := 0.0 # hp per second lost through the throat
var _choke_phase := 0 # 0 on his feet, 1 on his knees, 2 keeling over, 3 rolling on the floor
var _choke_phase_t := 0.0
var _choke_stand_time := 2.5
var _choke_t := 0.0
var _cough_cd := 0.8
var _c_choke_stand: MannequinAnims.Clip
var _c_choke_knees: MannequinAnims.Clip
var _c_choke_fall: MannequinAnims.Clip
var _c_choke_floor: MannequinAnims.Clip
static var _gun_material: StandardMaterial3D
var _c_choke_roll_l: MannequinAnims.Clip
var _c_choke_roll_r: MannequinAnims.Clip
var _floor_clip: MannequinAnims.Clip
var _floor_speed := 1.0
var _floor_left := 0.0
var _floor_prev := Vector3.ZERO
# shooting
var _c_ready: MannequinAnims.Clip
var _c_aim: MannequinAnims.Clip
var _ready_w := 0.0
var _aim_w := 0.0
var _aiming := false
var _aim_yaw := 0.0
var _aim_pitch := 0.0
var _ammo := MAGAZINE
var _shoot_cd := 0.0
var _reload_t := 0.0
var _wild_cd := 1.0
# orders
var _order := ""
var _order_clip: MannequinAnims.Clip
var _order_w := 0.0
var _t_order := 0.0
var _order_retarget := 0.0
# pistol / despair
var _gun: Node3D
var _c_suicide: MannequinAnims.Clip
var _suicide_t := -1.0
var _suicide_fire := 0.0
var _suicide_w := 0.0
var _despair_cd := 1.0
var _choke_despair_rolled := false
var _stuck_count := 0
var _knee_hits := 0
# pain, fainting, the throes after death, being shoved by hits
var _pain := 0.0
var _out_cold := 0.0 # seconds left lying unconscious
var unconscious := false
var _wild_left := -1.0 # -1: not decided yet (first neck wound decides)
var _spasm_time := 0.0
var _spasm_cd := 0.0
var _shove := Vector3.ZERO
var _down_time := 2.0 # how long a knocked-down man stays down before he tries to rise
var _shove_v := Vector3.ZERO


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
	_c_choke_stand = _lib.clip("choke_stand")
	_c_choke_knees = _lib.clip("choke_knees")
	_c_choke_fall = _lib.clip("choke_fall")
	_c_choke_floor = _lib.clip("choke_floor")
	_c_choke_roll_l = _lib.clip("choke_roll_l")
	_c_choke_roll_r = _lib.clip("choke_roll_r")
	_c_down_floor = _lib.clip("down_floor")
	_c_down_roll_l = _lib.clip("down_roll_l")
	_c_down_roll_r = _lib.clip("down_roll_r")
	_floor_clip = _c_choke_floor
	_c_ready = _lib.clip("pistol_ready")
	_c_aim = _lib.clip("pistol_aim")
	_c_suicide = _lib.clip("suicide_r")
	_spring.resize(CENTERS.size())
	_spring_vel.resize(CENTERS.size())

	_build_body()
	if armed:
		_attach_gun()
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
	# far off in the haze a soldier's small parts are not drawn (big map)
	mi.visibility_range_end = 140.0 if mesh.get_aabb().size.length() > 0.3 else 90.0
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


## Uniform: the team's camouflage, laid on in the parts' own space.
static func _camo(t: int, shade := 1.0) -> StandardMaterial3D:
	var key := "%d_%s" % [t, shade]
	if not _camo_mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_texture = load(TEAM_CAMO[t])
		m.albedo_color = Color(shade, shade, shade)
		m.uv1_triplanar = true
		m.uv1_scale = Vector3.ONE * 2.5
		m.roughness = 0.95
		_camo_mats[key] = m
	return _camo_mats[key]


static func _gear_mesh(mesh_name: String) -> Mesh:
	if _gear.is_empty():
		var scene: Node = load(GEAR_SCENE).instantiate()
		for mi in scene.find_children("*", "MeshInstance3D", true, false):
			_gear[String(mi.name)] = mi.mesh
		scene.free()
	return _gear.get(mesh_name)


func _build_body() -> void:
	var shirt := _camo(team)
	var pants := _camo(team, 0.92)
	var skin := _mat(SKINS[randi() % SKINS.size()], 0.6)
	_skin_mat = skin
	var shoes := _mat(Color(0.06, 0.055, 0.05), 0.7)
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
	for i in head.get_child_count():
		if i != 1: # everything but the neck goes when the head is blown off
			_head_visuals.append(head.get_child(i))
	var hsh := SphereShape3D.new()
	hsh.radius = 0.125
	_shape(head, hsh)
	_head_shape = head.get_child(head.get_child_count() - 1)
	var nsh := CapsuleShape3D.new() # neck: shots here open the carotid
	nsh.radius = 0.055
	nsh.height = 0.17
	_shape(head, nsh, Vector3(0, -0.14, 0))

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
		_visual(s, _capsule_mesh(0.07, 0.2), shoes, Vector3(0, -0.15, 0)) # boot tops
	parts = [pelvis, chest, head, uarm_l, farm_l, uarm_r, farm_r, thigh_l, shin_l, thigh_r, shin_r]
	# kit from Blender: helmet (goes with the head when it is blown off),
	# plate carrier; team-coloured tape round the arms and the right thigh
	_visual(head, _gear_mesh("Helmet"), _camo(team, 0.85))
	_visual(head, _gear_mesh("ChinStrap"), shoes)
	_head_visuals.append(head.get_child(head.get_child_count() - 2))
	_head_visuals.append(head.get_child(head.get_child_count() - 1))
	_visual(chest, _gear_mesh("Vest"), _camo(team, 0.7))
	var tape := _mat(TEAM_TAPE[team], 0.6)
	var ring := CylinderMesh.new()
	ring.top_radius = 0.064
	ring.bottom_radius = 0.064
	ring.height = 0.05
	ring.radial_segments = 12
	for p in [uarm_l, uarm_r]:
		_visual(p, ring, tape, Vector3(0, 0.05, 0))
	_visual(thigh_r, ring, tape, Vector3(0, 0.08, 0), Vector3.ZERO, Vector3(1.3, 1, 1.3))


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
		elif state == State.STAGGER:
			q = L.rot(_stagger, i, _stagger_t)
			p = L.rest_local[i].origin
			if i == 0:
				# horizontal travel is root motion (the body itself is moved)
				p.y = L.pelvis_pos(_stagger, _stagger_t).y
		elif state == State.CHOKE:
			var cc := _choke_clip()
			var ct := _choke_clip_t(cc)
			q = L.rot(cc, i, ct)
			p = L.pelvis_pos(cc, ct) if i == 0 else L.rest_local[i].origin
			if i == 0 and _choke_phase == 3:
				# on the floor the sideways travel moves the body itself
				p.x = 0.0
				p.z = 0.0
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
			# obeying an order: hands up / on his knees
			if _order_w > 0.001 and _order_clip != null:
				q = q.slerp(L.rot(_order_clip, i, _t_order), _order_w)
				if i == 0:
					p = p.lerp(L.pelvis_pos(_order_clip, _t_order), _order_w)
		# hand on the wound: overrides the bones that pose touches
		if _clutch_w > 0.001 and _clutch_mask[i] > 0.0:
			var cw := _clutch_w * _clutch_mask[i]
			q = q.slerp(L.rot(_clutch, i, 0.0), cw)
			if i == 0:
				p.y += (L.pelvis_pos(_clutch, 0.0).y - L.rest_local[0].origin.y) * cw
		# weapon in hand: held ready or aimed (a pistol turns at the shoulder,
		# a rifle in both hands turns the whole upper body), or a pistol
		# pressed to the temple
		var rifle := weapon != "pistol" and _gun != null
		if i == 5 or i == 6 or (rifle and (i == 3 or i == 4 or (i == 2 and _aim_w > 0.001))):
			if _ready_w > 0.001 and i != 2:
				q = q.slerp(L.rot(_c_ready, i, 0.0), _ready_w)
			if _aim_w > 0.001:
				q = q.slerp(L.rot(_c_aim, i, 0.0), _aim_w)
				if i == 5 and not rifle:
					var gc := L.rest_global[1].basis
					var turn := Basis(Vector3.UP, _aim_yaw * _aim_w) * Basis(Vector3.RIGHT, _aim_pitch * _aim_w)
					q = Quaternion(gc.inverse() * turn * gc) * q
		if i == 1 and rifle and _aim_w > 0.001:
			var gp := L.rest_global[0].basis
			var turn := Basis(Vector3.UP, _aim_yaw * _aim_w) * Basis(Vector3.RIGHT, _aim_pitch * _aim_w)
			q = Quaternion(gp.inverse() * turn * gp) * q
		if _suicide_w > 0.001 and (i == 2 or i == 5 or i == 6):
			q = q.slerp(L.rot(_c_suicide, i, 0.0), _suicide_w)
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
	if _order_clip != null:
		_t_order = fposmod(_t_order + delta, _order_clip.length)
	_order_w = 1.0 if state == State.ORDER and _order_clip != null else 0.0
	var panic := state == State.PANIC or (state == State.WANDER and _speed > 3.0) # running, not walking
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
		_spring_vel[i] += (-_spring[i] * 110.0 - _spring_vel[i] * 10.0) * delta
		_spring[i] += _spring_vel[i] * delta
	balance = minf(balance + delta * 0.3, 1.0)
	_pain = maxf(_pain - delta * 9.0, 0.0)
	_update_clutch(delta)
	_update_suicide(delta)
	_update_gun_arm(delta)


# ------------------------------------------------------------------ AI

func _physics_process(delta: float) -> void:
	_time += delta
	_head_damage = maxf(_head_damage - delta * 35.0, 0.0)
	_update_arteries(delta)
	if (_neck_wound or _downed) and not dead:
		health -= _choke_drain * delta
	if not dead and health <= 0.0:
		_bleed_out()
	if _suicide_t >= 0.0 and _suicide_t >= _suicide_fire and not dead:
		_suicide_shot()
	if armed and not dead:
		_despair_check(delta)
	match state:
		State.DEAD:
			_dead_process(delta)
			return
		State.CHOKE:
			_choke_process(delta)
			return
		State.KNOCKED:
			_knocked_process(delta)
			return
		State.GETUP:
			_getup_process(delta)
			return
		State.STAGGER:
			_stagger_process(delta)
			return

	var ai := ai_enabled and not display_only and _suicide_t < 0.0
	if _order != "" and (state == State.IDLE or state == State.WANDER or state == State.PANIC):
		state = State.ORDER
	if not ai and state != State.IDLE and state != State.ORDER:
		state = State.IDLE
	_state_time -= delta
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if state == State.ORDER and _order == "come" and player:
		_order_retarget -= delta
		if _order_retarget <= 0.0:
			_order_retarget = 0.5
			_agent.target_position = player.global_position
		if global_position.distance_to(player.global_position) < 1.8:
			_set_order("stand")
	if ai:
		_war_think(delta)
		match state:
			State.IDLE:
				if _state_time <= 0.0:
					_war_move()
			State.WANDER:
				if _agent.is_navigation_finished():
					_arrived()
			State.PANIC:
				if _state_time <= 0.0 and player and global_position.distance_to(player.global_position) < 12.0:
					_state_time = 1.5 # the shooter is still close: keep running
				elif _state_time <= 0.0:
					state = State.IDLE
					_state_time = randf_range(2.0, 4.0)
				elif _agent.is_navigation_finished():
					_flee_target()
			State.SHOOT:
				_shoot_process(delta)
	if state != State.SHOOT:
		_aiming = false

	var desired := Vector3.ZERO
	var moving := state == State.WANDER or state == State.PANIC or (state == State.ORDER and _order == "come")
	if moving and _suicide_t < 0.0 and not _agent.is_navigation_finished():
		var next := _agent.get_next_path_position()
		var to := next - global_position
		to.y = 0.0
		if to.length() > 0.05:
			desired = to.normalized() * (4.3 if state == State.PANIC else _speed)
	# reacting to a hit slows him down while he catches his balance
	desired *= clampf(0.35 + balance * 0.65, 0.0, 1.0)

	var accel := 10.0 if state == State.PANIC or _speed > 3.0 else 6.0
	velocity.x = move_toward(velocity.x, desired.x, accel * delta) + _shove.x
	velocity.z = move_toward(velocity.z, desired.z, accel * delta) + _shove.z
	_shove = Vector3.ZERO
	if is_on_floor():
		velocity.y = -0.5
	else:
		velocity.y -= 9.8 * delta
	if not display_only:
		move_and_slide()

	var hspeed := Vector2(velocity.x, velocity.z).length()
	if hspeed > 0.3 and desired != Vector3.ZERO:
		rotation.y = lerp_angle(rotation.y, atan2(-velocity.x, -velocity.z), 7.0 * delta)
	elif state == State.SHOOT and is_instance_valid(_target):
		# squares up to his target
		var tp := _target.global_position - global_position
		rotation.y = lerp_angle(rotation.y, atan2(-tp.x, -tp.z), 6.0 * delta)
	elif state == State.ORDER and player:
		# keeps his eyes on whoever gives the orders
		var tp := player.global_position - global_position
		rotation.y = lerp_angle(rotation.y, atan2(-tp.x, -tp.z), 2.5 * delta)
	elif state == State.IDLE and ai:
		# at his post: watches the enemy's side
		var ahead := -1.0 if team == 0 else 1.0
		rotation.y = lerp_angle(rotation.y, atan2(0.0, -ahead), 1.5 * delta)

	if desired != Vector3.ZERO:
		_stuck_time += delta
		if _stuck_time > 1.5:
			if global_position.distance_to(_last_pos) < 0.4:
				if state == State.PANIC:
					_stuck_count += 1 # cornered
					_flee_target()
				elif state == State.WANDER:
					_war_move(true)
			else:
				_stuck_count = 0
			_stuck_time = 0.0
			_last_pos = global_position
	if global_position.y < -40.0:
		queue_free()
		return

	var target_yaw := 0.0
	var look_at: Node3D = player if state == State.ORDER else (_target if is_instance_valid(_target) else null)
	if look_at and state != State.SHOOT:
		var local := to_local(look_at.global_position)
		target_yaw = clampf(atan2(-local.x, -local.z), -1.0, 1.0)
	_head_yaw = lerp_angle(_head_yaw, target_yaw, 3.0 * delta)

	_update_layers(delta, hspeed)
	_bleed(delta, 0.25, 0.45)
	_blend_w = minf(_blend_w + delta / _blend_time, 1.0)
	_apply_pose(_compute_pose())


func _random_nav_point() -> Vector3:
	return NavigationServer3D.map_get_random_point(get_world_3d().navigation_map, 1, false)


## Somewhere far from the shooter, in the direction away from him (never
## running past him).
func _flee_target() -> void:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	var away := Vector3.ZERO
	if player:
		away = global_position - player.global_position
		away.y = 0.0
		away = away.normalized()
	var best := global_position
	var best_s := -INF
	for i in 10:
		var p := _random_nav_point()
		var to := p - global_position
		to.y = 0.0
		var s := p.distance_to(player.global_position) if player else randf()
		if to.length() > 1.0 and away != Vector3.ZERO:
			s += to.normalized().dot(away) * 8.0
		if s > best_s:
			best_s = s
			best = p
	_agent.target_position = best
	_stuck_time = 0.0
	_last_pos = global_position


## Gunshot or blast nearby: a soldier looks round at once, even behind him.
func alert(_from: Vector3) -> void:
	if dead or display_only or not ai_enabled:
		return
	_alerted_t = 3.0
	_scan_cd = minf(_scan_cd, 0.1)


# ------------------------------------------------------------------ damage

## Called by the gun for every bullet / pellet. `fx` scales the blood effects
## (pellets use less each). Returns 0 = hit, 1 = kill, 2 = headshot kill.
func take_hit(part: RigidBody3D, pos: Vector3, normal: Vector3, dir: Vector3, damage: float,
		impulse: float, fx := 1.0) -> int:
	var part_name: String = part.get_meta("part")
	var is_head := part == head
	var local := part.to_local(pos)
	# the plate carrier: steel plates front and back over the vitals stop a
	# rifle round - no wound, but the blow knocks the wind out of him and
	# often off his feet. A sniper's round goes through.
	var plate := part == chest and absf(local.x) < 0.13 and local.y > -0.17 and local.y < 0.2 \
			and absf(local.z) > 0.04 and impulse < HEAVY_ROUND
	if plate:
		Sfx.play_3d("metal_hit", pos, -3.0, 0.15)
		Blood.dust(pos, normal, Color(0.32, 0.32, 0.28))
		damage *= 0.12
		_pain += 16.0
		impulse *= 1.25 # all of it goes into the man
	else:
		Blood.wound(part, pos, normal)
		Blood.mist(pos, normal * 0.6 - dir * 0.4, 0.8 * fx)
		Blood.spray(pos + dir * 0.12, dir + Vector3.UP * 0.1, int(10 * fx), 2.5, 6.5, 0.3)
		if _wounds.size() < 10:
			_wounds.append([part, part.to_local(pos)])
		_bleed_left = maxf(_bleed_left, 14.0)

	var local_normal := part.global_basis.inverse() * normal
	if is_head and local.y < -0.065:
		# neck: not an instant kill, but the carotid opens up and he chokes
		# on his own blood until he bleeds out
		is_head = false
		damage = minf(damage, 40.0)
		_add_artery(part, local, local_normal, 1.1, true, false)
		if not dead:
			_neck_wound = true
			_choke_drain = minf(_choke_drain + 3.4, 7.0)
			_bleed_left = 9999.0
	elif is_head and not head_gone:
		_head_damage += damage
		if _head_damage >= 150.0:
			_explode_head(pos, dir)
			if dead:
				part.apply_impulse(dir * impulse, pos - part.global_position)
				return 0
			health = 0.0
			_die(part, pos, dir, impulse * 1.5, true)
			return 2
	elif not plate:
		var artery := _artery_strength(part_name, local)
		if artery > 0.0:
			_add_artery(part, local, local_normal, artery)
		if part_name == "chest" and _in_heart(local):
			damage = 999.0
			_add_artery(part, local, local_normal, 1.3)

	if dead:
		part.apply_impulse(dir * impulse, pos - part.global_position)
		return 0

	health -= damage
	_pain += damage
	var killed := health <= 0.0
	if killed and _survives(is_head, damage):
		# not dead yet: down, writhing, to be finished off
		_go_down()
		if state == State.KNOCKED:
			part.apply_impulse(dir * impulse, pos - part.global_position)
		else:
			_knockdown(part, pos, dir, impulse * 1.2)
		return 0
	if state == State.KNOCKED:
		part.apply_impulse(dir * impulse, pos - part.global_position)
		if killed:
			_mark_dead(is_head)
			return 2 if is_head else 1
		_knock_time = minf(_knock_time, 1.0)
		if unconscious:
			_out_cold = maxf(_out_cold, 6.0) # a fresh wound keeps him under
		return 0

	if killed:
		if is_head:
			Blood.mist(pos + dir * 0.1, dir, 2.2)
			Gore.chunks(pos, dir + Vector3.UP * 0.3, 2, 3.0)
			Blood.spray(pos + dir * 0.15, dir + Vector3.UP * 0.25, 34, 3.5, 9.0, 0.45, 0.012, 0.035)
		_die(part, pos, dir, impulse * (1.5 if is_head else 1.0), is_head)
		return 2 if is_head else 1

	# too much pain: he blacks out and drops where he stands
	if not display_only and not _downed and not _neck_wound and _pain > FAINT_PAIN and randf() < FAINT_CHANCE \
			and state != State.CHOKE:
		_faint(part, pos, dir, impulse)
		return 0
	# still standing: the struck part jerks, the body is shoved along the
	# bullet, then he fights to stay on his feet with a recovery that depends
	# on where he was hit; a knee hit folds him, a gut shot may too
	_react(part_name, pos, dir, impulse)
	var push := Vector3(dir.x, 0.0, dir.z) * impulse * (0.09 if part == chest or part == pelvis else 0.05)
	_shove += push
	balance -= impulse * BALANCE_COST.get(part_name, 0.02)
	var knee := part_name.begins_with("shin") or (part_name.begins_with("thigh") and local.y < -0.13) \
			or (part == pelvis and randf() < 0.3 and not display_only)
	if knee:
		_knee_hits += 1
	var frame := Engine.get_physics_frames()
	# fighting for air (or kneeling on orders): hits only rock him, unless
	# they knock him down
	var kneeling := state == State.ORDER and _order == "kneel"
	if state == State.CHOKE or kneeling or (_neck_wound and not knee):
		if balance < 0.0:
			_knockdown(part, pos, dir, impulse)
		elif state != State.CHOKE and _neck_wound:
			_start_choke()
		elif kneeling:
			_start_clutch(_clutch_for(part_name, local))
		_hit_frame = frame
		return 0
	var falling_on_knee := state == State.STAGGER and _stagger_fall
	# a round in the body often drops a man where he stands, plate or not
	var collapse := 0.0
	if part == chest or part == pelvis:
		collapse = 0.22 if plate else 0.33
	elif part_name.begins_with("thigh"):
		collapse = 0.35
	if impulse >= HEAVY_ROUND:
		collapse = 1.0
	if knee and not falling_on_knee:
		# shin / thigh: that side's knee gives; a gut shot folds either one
		var side := part_name.right(1) if part_name.ends_with("_l") or part_name.ends_with("_r") else ("l" if randf() < 0.5 else "r")
		_start_stagger("knee_fall_" + side, true, part, pos, dir, impulse)
	elif (balance < 0.0 or randf() < collapse) and not falling_on_knee and not display_only:
		_knockdown(part, pos, dir, impulse * 1.3)
	elif frame != _hit_frame and not falling_on_knee:
		_start_stagger(_pick_stagger(part_name, dir), false, part, pos, dir, impulse)
	_hit_frame = frame
	_start_clutch(_clutch_for(part_name, local))
	if not display_only:
		alert(pos - dir)
	return 0


## A lethal body hit (not the head, not the heart, not torn apart) leaves
## him alive now and then.
func _survives(is_head: bool, damage: float) -> bool:
	return not _downed and not _neck_wound and not is_head and damage < 500.0 and health > -45.0 \
			and randf() < SURVIVE_CHANCE


func _go_down() -> void:
	_downed = true
	health = randf_range(15.0, 28.0)
	_choke_drain = randf_range(0.6, 1.1)
	_bleed_left = 9999.0
	_target = null
	_aiming = false
	_order = ""
	_order_clip = null


func _clutch_for(part_name: String, local: Vector3) -> String:
	match part_name:
		"head":
			return "clutch_neck" if local.y < -0.065 else "clutch_head"
		"chest":
			return "clutch_chest_l" if local.x < 0.0 else "clutch_chest_r"
		"pelvis":
			return "clutch_belly"
		"uarm_l", "farm_l":
			return "clutch_arm_l"
		"uarm_r", "farm_r":
			return "clutch_arm_r"
		"thigh_l", "shin_l":
			return "clutch_thigh_l"
	return "clutch_thigh_r"


## After the first jolt a hand goes to the wound, presses it for a while,
## then lets go.
func _start_clutch(clip_name: String) -> void:
	var c := _lib.clip(clip_name)
	if c != _clutch:
		_clutch_w = minf(_clutch_w, 0.3)
		_clutch = c
		_clutch_mask = _mask_of(c)
	_clutch_delay = 0.22
	_clutch_hold = randf_range(1.8, 3.2)


static var _masks := {}


## Which bones a pose actually moves (chest / head / legs only partly).
func _mask_of(c: MannequinAnims.Clip) -> PackedFloat32Array:
	if _masks.has(c):
		return _masks[c]
	var m := PackedFloat32Array()
	m.resize(CENTERS.size())
	for i in CENTERS.size():
		var moved := _lib.rot(c, i, 0.0).angle_to(_lib.rest_rot[i]) > 0.03
		if i == 0:
			moved = moved or absf(_lib.pelvis_pos(c, 0.0).y - _lib.rest_local[0].origin.y) > 0.005
		var weight := 1.0
		if i <= 2:
			weight = 0.8
		elif i >= 7:
			weight = 0.7
		m[i] = weight if moved else 0.0
	_masks[c] = m
	return m


func _update_clutch(delta: float) -> void:
	if _clutch == null:
		return
	var target := 0.0
	if _clutch_delay > 0.0:
		_clutch_delay -= delta
	elif _clutch_hold > 0.0:
		_clutch_hold -= delta
		target = 1.0
	_clutch_w = move_toward(_clutch_w, target, delta * (3.5 if target > _clutch_w else 1.4))
	if _clutch_w <= 0.0 and _clutch_hold <= 0.0 and _clutch_delay <= 0.0:
		_clutch = null


func _pick_stagger(part_name: String, dir: Vector3) -> String:
	match part_name:
		"head":
			return "stagger_head"
		"thigh_l", "thigh_r":
			return "limp_" + part_name.right(1)
		"uarm_l", "farm_l":
			return "spin_l"
		"uarm_r", "farm_r":
			return "spin_r"
	var local_dir := global_transform.basis.inverse() * dir
	if absf(local_dir.z) >= absf(local_dir.x):
		return "stagger_back" if local_dir.z > 0.0 else "stagger_fwd"
	return "stagger_right" if local_dir.x > 0.0 else "stagger_left"


func _capture_blend() -> void:
	_blend_time = 0.25
	_blend_from.clear()
	for p in parts:
		_blend_from.append(p.global_transform)
	_blend_w = 0.0


func _start_stagger(clip_name: String, fall: bool, part: RigidBody3D, pos: Vector3, dir: Vector3, impulse: float) -> void:
	_capture_blend()
	_shove_v = Vector3.ZERO
	_stagger = _lib.clip(clip_name)
	_stagger_t = 0.0
	_stagger_prev = _lib.pelvis_pos(_stagger, 0.0)
	_stagger_fall = fall
	_fall_args = [part, pos, dir, impulse]
	state = State.STAGGER
	velocity.x = 0.0
	velocity.z = 0.0


func _stagger_process(delta: float) -> void:
	_stagger_t += delta
	_blend_w = minf(_blend_w + delta / 0.12, 1.0)
	var p := _lib.pelvis_pos(_stagger, _stagger_t)
	var d := p - _stagger_prev
	_stagger_prev = p
	var world := global_transform.basis * Vector3(d.x, 0.0, d.z)
	# the bullet's push carries on for a moment on top of the stumble
	_shove_v = _shove_v.lerp(Vector3.ZERO, clampf(delta * 6.0, 0.0, 1.0)) + _shove * 3.0
	_shove = Vector3.ZERO
	velocity.x = world.x / delta + _shove_v.x
	velocity.z = world.z / delta + _shove_v.z
	if is_on_floor():
		velocity.y = -0.5
	else:
		velocity.y -= 9.8 * delta
	move_and_slide()
	_update_layers(delta, 0.0)
	_bleed(delta, 0.2, 0.4)
	_apply_pose(_compute_pose())
	if _stagger_t < _stagger.length:
		return
	if _stagger_fall:
		var part: RigidBody3D = _fall_args[0] if is_instance_valid(_fall_args[0]) else pelvis
		var fwd := -global_transform.basis.z
		_knockdown(chest, chest.global_position, (fwd + _fall_args[2] * 0.3).normalized(), 4.0 + _fall_args[3] * 0.2)
		part.apply_central_impulse(_fall_args[2] * 2.0)
		return
	_capture_blend()
	velocity = Vector3.ZERO
	state = State.IDLE
	_state_time = 0.4
	if _neck_wound:
		_start_choke()
	elif ai_enabled and not display_only:
		alert(global_position)


func _react(part_name: String, pos: Vector3, dir: Vector3, impulse: float) -> void:
	var local_dir := global_transform.basis.inverse() * dir
	# springs: the struck bone (and its parent) get spun around the hit point
	var bi := MannequinAnims.BONES.find(part_name)
	var local_pos := to_local(pos)
	var b := bi
	var falloff := 1.0
	while b >= 0 and falloff > 0.2:
		var pivot := _lib.rest_global[b].origin
		var kick: Vector3 = (local_pos - pivot).cross(local_dir) * impulse * falloff / SPRING_MASS[b] * 15.0
		_spring_vel[b] += kick.limit_length(24.0)
		b = _lib.parent[b]
		falloff *= 0.45



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
	_aiming = false
	_ready_w = 0.0
	_aim_w = 0.0
	_clutch = null
	_clutch_w = 0.0
	_suicide_t = -1.0
	_suicide_w = 0.0
	drop_gun(velocity + dir * 1.5 + Vector3.UP * 0.8)
	collision_layer = 0
	collision_mask = 0
	var vel := velocity
	velocity = Vector3.ZERO
	_reacts.clear()
	if _joints.is_empty():
		_make_joints()
	if _ragdoll_material == null:
		# grippy, dead-weight bodies: they slump and stay instead of sliding
		_ragdoll_material = PhysicsMaterial.new()
		_ragdoll_material.friction = 0.9
		_ragdoll_material.bounce = 0.0
	var carry := Vector3(dir.x, 0.0, dir.z).normalized() * clampf(impulse * 0.06, 0.0, 1.6)
	for p in parts:
		p.freeze = false
		p.collision_mask = LAYER_WORLD | LAYER_PROPS | LAYER_PARTS
		p.physics_material_override = _ragdoll_material
		p.linear_damp = 0.12
		p.angular_damp = 1.8
		p.linear_velocity = vel + carry
	# small fast parts must not tunnel through the floor when blasted
	for p in [head, farm_l, farm_r, shin_l, shin_r]:
		p.continuous_cd = true
	part.apply_impulse(dir * impulse, pos - part.global_position)


func _knockdown(part: RigidBody3D, pos: Vector3, dir: Vector3, impulse: float) -> void:
	state = State.KNOCKED
	_knock_time = 0.0
	_down_time = randf_range(2.2, 5.0) # lies there a while, hurt, before he tries to rise
	_go_limp(part, pos, dir, impulse)
	# legs give way
	shin_l.angular_velocity = global_transform.basis.x * randf_range(-3, 3)
	shin_r.angular_velocity = global_transform.basis.x * randf_range(-3, 3)


## Blacks out from the pain: drops limp where he stands and lies there,
## out of the fight, until he comes round (or is finished off).
func _faint(part: RigidBody3D, pos: Vector3, dir: Vector3, impulse: float) -> void:
	unconscious = true
	_out_cold = randf_range(14.0, 26.0)
	_pain = 0.0
	_target = null
	_aiming = false
	_order = ""
	_order_clip = null
	_knockdown(part, pos, dir, impulse * 0.6)
	# no bracing: the knees just go
	thigh_l.angular_velocity = global_transform.basis.x * randf_range(2, 4)
	thigh_r.angular_velocity = global_transform.basis.x * randf_range(2, 4)


func _die(part: RigidBody3D, pos: Vector3, dir: Vector3, impulse: float, headshot: bool) -> void:
	_go_limp(part, pos, dir, impulse)
	shin_l.angular_velocity = global_transform.basis.x * randf_range(-3, 3)
	shin_r.angular_velocity = global_transform.basis.x * randf_range(-3, 3)
	_mark_dead(headshot)


func _mark_dead(headshot: bool) -> void:
	dead = true
	unconscious = false
	state = State.DEAD
	# the muscles keep going a while: the limbs jerk and the legs kick
	_spasm_time = randf_range(3.0, 7.0) if not head_gone else randf_range(1.5, 3.0)
	_spasm_cd = randf_range(0.3, 0.8)
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
	_joint_of[b] = j


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
	_joint_of[b] = j


# ------------------------------------------------------------------ knocked down / getting up

func _knocked_process(delta: float) -> void:
	_knock_time += delta
	_bleed(delta, 0.15, 0.35)
	if chest.global_position.y < -40.0:
		queue_free()
		return
	var settled := chest.linear_velocity.length() < 0.5 and pelvis.linear_velocity.length() < 0.5
	if unconscious:
		# out cold: limp, breathing shallowly; then he comes round
		_out_cold -= delta
		if settled and fmod(_time, 3.6) < delta:
			chest.apply_central_impulse(Vector3.UP * 3.0)
		if _out_cold <= 0.0:
			unconscious = false
			if health < 35.0:
				_downed = true # too weak to stand: he writhes on the floor
				_choke_drain = randf_range(0.6, 1.1)
				_bleed_left = 9999.0
				_start_floor_choke()
			else:
				_start_getup()
		return
	if _neck_wound or _downed:
		# throat open / left for dead: he does not get up, he rolls about on the floor
		if (_knock_time > 1.0 and settled) or _knock_time > 4.0:
			_start_floor_choke()
		return
	if (_knock_time > _down_time and settled) or _knock_time > _down_time + 4.0:
		_start_getup()


func _start_getup() -> void:
	var face_up := (chest.global_basis * Vector3(0, 0, -1)).y > 0.0
	_getup = _lib.clip("getup_back" if face_up else "getup_front")
	_getup_t = 0.0
	_freeze_from_ragdoll(Vector3(0, 0, 1) if face_up else Vector3(0, 0, -1))
	state = State.GETUP


## Ragdoll back to animated parts: turns the root so the clip's lying body
## (head towards `head_dir`, NPC space) lines up with the ragdoll and blends
## from where the parts lie now.
func _freeze_from_ragdoll(head_dir: Vector3) -> void:
	var saved: Array[Transform3D] = []
	for p in parts:
		saved.append(p.global_transform)
	for j in _joints:
		j.queue_free()
	_joints.clear()
	_joint_of.clear()
	for p in parts:
		p.freeze = true
		p.collision_mask = 0
		p.contact_monitor = false
	var actual := head.global_position - pelvis.global_position
	actual.y = 0.0
	var yaw := atan2(actual.x, actual.z) - atan2(head_dir.x, head_dir.z)
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
	_blend_time = 0.4


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
		if _gun == null and not display_only and _order == "":
			# back on his feet he takes up a rifle again (a mate's, his own)
			if weapon == "pistol":
				weapon = "rifle"
			_attach_gun()
		if _neck_wound:
			_start_choke()
		elif ai_enabled and not display_only:
			alert(global_position)


func _dead_process(delta: float) -> void:
	_dead_time += delta
	if chest.global_position.y < -40.0:
		queue_free()
		return
	_death_throes(delta)
	_bleed(delta, 0.12, 0.3)
	# once the body settles, a pool of blood spreads underneath
	if not _pool_done and _dead_time > 1.0 and chest.linear_velocity.length() < 0.4 and not _wounds.is_empty():
		_pool_done = true
		var from := chest.global_position + Vector3.UP * 0.2
		var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 1.5, LAYER_WORLD | LAYER_PROPS)
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		if not hit.is_empty() and hit.normal.y > 0.7:
			Blood.pool(hit.position, hit.normal, randf_range(1.6, 2.4) * Settings.blood_amount, randf_range(8.0, 14.0))


## Just dead: the muscles cramp and jerk - a limb snaps up, a leg kicks, the
## hand claws, the body shivers - weaker and rarer until it stops.
func _death_throes(delta: float) -> void:
	if _dead_time > _spasm_time or display_only:
		return
	var k := pow(1.0 - _dead_time / _spasm_time, 1.5)
	_spasm_cd -= delta
	# a fine tremor through the whole body
	for i in [1, 0, 7, 9]:
		var p: RigidBody3D = parts[i]
		if not p.freeze and not _severed.has(p):
			p.apply_central_impulse(Vector3(randf_range(-1, 1), randf_range(0, 1), randf_range(-1, 1)) * p.mass * 0.06 * k)
	if _spasm_cd > 0.0:
		return
	_spasm_cd = lerpf(0.5, 0.12, k) * randf_range(0.6, 1.4)
	for n in randi_range(1, 3):
		var p: RigidBody3D = parts[SPASM_PARTS[randi() % SPASM_PARTS.size()]]
		if p.freeze or _severed.has(p):
			continue
		var axis := p.global_basis.x if randf() < 0.6 else p.global_basis.z
		p.apply_torque_impulse(axis * randf_range(-1.0, 1.0) * p.mass * 0.55 * k)
		p.apply_central_impulse((Vector3.UP * 0.5 + Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)) * 0.4) * p.mass * 0.6 * k)
	if randf() < 0.25 * k:
		# the chest heaves
		chest.apply_central_impulse(Vector3.UP * chest.mass * 0.35 * k)


# ------------------------------------------------------------------ guts

## Close shotgun blast to the torso: organs (Blender meshes) fall out and a
## string of intestine spills from the wound, hanging on physics joints.
func spill_organs(part: RigidBody3D, pos: Vector3, normal: Vector3, dir: Vector3) -> void:
	if _guts_spilled:
		return
	_guts_spilled = true
	var organs := ["heart", "lung", "lung"] if part == chest else ["stomach", "liver", "kidney"]
	for o in organs:
		var b := Basis.from_euler(Vector3(randf(), randf(), randf()) * TAU)
		Gore.spawn(o, Transform3D(b, pos + normal * 0.05), normal * randf_range(1.2, 2.8) + dir * 1.2 + Vector3.UP * 0.6, null, 0.35)
	Gore.chunks(pos, normal + dir * 0.5, 4, 3.5)
	if part == chest:
		Blood.spray(pos, normal + Vector3.DOWN * 0.3, 26, 1.5, 4.5, 0.5, 0.015, 0.04)
		_bleed_left = maxf(_bleed_left, 25.0)
		return
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


# ------------------------------------------------------------------ head, arteries, limbs

func _explode_head(pos: Vector3, dir: Vector3) -> void:
	head_gone = true
	for v in _head_visuals:
		v.visible = false
	_head_shape.disabled = true
	var stump := MeshInstance3D.new()
	stump.mesh = Gore.mesh("stump")
	stump.position = Vector3(0, -0.075, 0)
	head.add_child(stump)
	var c := head.global_position
	var away := (dir + Vector3.UP * 0.35).normalized()
	for i in 4:
		var b := Basis.from_euler(Vector3(randf(), randf(), randf()) * TAU)
		var spread := Vector3(randf_range(-1, 1), randf_range(-0.3, 1), randf_range(-1, 1))
		Gore.spawn("skull_%d" % i, Transform3D(b, c + spread * 0.06), away * randf_range(2.5, 6.0) + spread * 2.5, _skin_mat, 0.12)
	for i in 4:
		var b := Basis.from_euler(Vector3(randf(), randf(), randf()) * TAU)
		var spread := Vector3(randf_range(-1, 1), randf_range(-0.2, 1), randf_range(-1, 1))
		Gore.spawn("brain_%d" % (i % 3), Transform3D(b, c + spread * 0.04), away * randf_range(1.5, 5.0) + spread * 1.8, null, 0.1)
	for i in 2:
		Gore.spawn("eye", Transform3D(Basis.IDENTITY, c + Vector3(randf_range(-0.05, 0.05), 0.02, 0)), away * randf_range(2.0, 4.0) + Vector3(randf_range(-1.5, 1.5), 1.5, randf_range(-1.5, 1.5)), null, 0.02)
	Gore.chunks(c, away, 6, 5.5)
	Blood.spray(c, away, 70, 3.0, 10.0, 0.6, 0.012, 0.04)
	Blood.mist(c, dir, 3.0)
	Blood.mist(c, -dir + Vector3.UP, 1.5)
	_wounds.append([head, Vector3(0, -0.06, 0)])
	_add_artery(head, Vector3(0, -0.055, 0), Vector3.UP, 1.5, true)
	_bleed_left = maxf(_bleed_left, 30.0)


## Inner thigh / inner upper arm hits may open an artery.
func _artery_strength(part_name: String, local: Vector3) -> float:
	match part_name:
		"thigh_l":
			return 0.9 if local.x > 0.02 and local.y > -0.08 and randf() < 0.6 else 0.0
		"thigh_r":
			return 0.9 if local.x < -0.02 and local.y > -0.08 and randf() < 0.6 else 0.0
		"uarm_l":
			return 0.6 if local.x > 0.015 and randf() < 0.45 else 0.0
		"uarm_r":
			return 0.6 if local.x < -0.015 and randf() < 0.45 else 0.0
	return 0.0


func _in_heart(local: Vector3) -> bool:
	return local.x > -0.11 and local.x < -0.012 and local.y > 0.02 and local.y < 0.13


## `drain`: the jet also costs health (the neck wound drains at its own rate).
func _add_artery(part: RigidBody3D, local_pos: Vector3, local_dir: Vector3, strength: float, force := false,
		drain := true) -> void:
	if _arteries.size() >= 6 and not force:
		return
	_arteries.append({"part": part, "pos": local_pos, "dir": local_dir.normalized(), "strength": strength, "age": 0.0,
			"acc": 0.0, "drain": drain})


## Pulsing jets of blood. The heart keeps pumping while he lives (and he
## bleeds out); after death the pressure fades within a few seconds.
func _update_arteries(delta: float) -> void:
	if _arteries.is_empty():
		return
	var beat := pow(maxf(sin(_time * TAU * 1.3), 0.0), 2.0) * 0.8 + 0.2
	for a in _arteries:
		a.age += delta
		var p: RigidBody3D = a.part
		if not is_instance_valid(p):
			continue
		var pressure: float = a.strength * exp(-a.age / (14.0 if a.drain else 40.0))
		if dead:
			pressure *= exp(-_dead_time / 3.0)
		if pressure < 0.05:
			continue
		if not dead and a.drain:
			health -= pressure * 4.5 * delta
		a.acc += delta
		if a.acc < 0.035:
			continue
		a.acc = 0.0
		var wpos: Vector3 = p.to_global(a.pos)
		var wdir: Vector3 = (p.global_basis * a.dir).normalized()
		var speed := (2.4 + 4.6 * beat) * pressure
		Blood.spray(wpos + wdir * 0.02, wdir + Vector3.UP * 0.2, int(2 + 5 * beat), speed * 0.85, speed * 1.15, 0.06, 0.013, 0.026)


## Blood loss finished him: he just collapses (forwards, still holding on).
func _bleed_out() -> void:
	match state:
		State.DEAD:
			return
		State.KNOCKED:
			_mark_dead(false)
		_:
			var fwd := -global_transform.basis.z
			_die(chest, chest.global_position + Vector3.UP * 0.2, fwd, 3.0 if state == State.CHOKE else 2.0, false)


## Close shotgun blast to a limb tears it off at the joint.
func sever(part: RigidBody3D, dir: Vector3) -> void:
	if _severed.has(part) or part == chest or part == pelvis or part == head:
		return
	if not dead:
		health = 0.0
		if state == State.KNOCKED:
			_mark_dead(false)
		else:
			_die(part, part.global_position, dir, 6.0, false)
	var j: Joint3D = _joint_of.get(part)
	if j == null:
		return
	var pivot := j.global_position
	var bi := parts.find(part)
	var parent_part: RigidBody3D = parts[_lib.parent[bi]]
	j.queue_free()
	_joint_of.erase(part)
	_severed[part] = true
	_add_artery(parent_part, parent_part.to_local(pivot), parent_part.global_basis.inverse() * (pivot - parent_part.global_position).normalized(), 1.0, true)
	_add_artery(part, part.to_local(pivot), part.global_basis.inverse() * (pivot - part.global_position).normalized(), 0.5, true)
	_wounds.append([parent_part, parent_part.to_local(pivot)])
	part.apply_central_impulse(dir * 7.0 + Vector3.UP * 2.0)
	Gore.chunks(pivot, dir, 4, 4.0)
	Blood.spray(pivot, dir, 30, 2.0, 6.0, 0.5, 0.012, 0.03)
	Blood.mist(pivot, dir, 1.5)
	_bleed_left = maxf(_bleed_left, 25.0)


# ------------------------------------------------------------------ neck wound

## Carotid open: both hands clamp the throat and stay there to the end.
func _start_choke() -> void:
	if state == State.CHOKE or dead:
		return
	_capture_blend()
	_blend_time = 0.35
	state = State.CHOKE
	_order = ""
	_order_clip = null
	_clutch = null
	_clutch_w = 0.0
	_choke_t = randf() * 2.0
	_choke_phase = mini(_choke_phase, 1) # back on his feet after a fall: he goes down again
	if _wild_left < 0.0:
		# some keep pulling the trigger for the first seconds, some don't
		_wild_left = WILD_FIRE_TIME if randf() < WILD_FIRE_CHANCE else 0.0
	_choke_phase_t = 0.0
	_choke_stand_time = randf_range(1.6, 2.8)
	_cough_cd = randf_range(0.4, 1.0)
	velocity.x = 0.0
	velocity.z = 0.0


## Knocked down with his throat open: from the ragdoll straight into rolling
## about on the floor.
func _start_floor_choke() -> void:
	_freeze_from_ragdoll(Vector3(0, 0, 1))
	collision_layer = 0
	collision_mask = LAYER_WORLD # lies on the floor, the player walks over him
	_blend_time = 0.5
	state = State.CHOKE
	_choke_phase = 3
	_choke_phase_t = 0.0
	_pick_floor_clip(false)
	_blend_time = 0.5
	_clutch = null
	_clutch_w = 0.0


func _choke_process(delta: float) -> void:
	_choke_t += delta
	_choke_phase_t += delta
	_blend_w = minf(_blend_w + delta / _blend_time, 1.0)
	match _choke_phase:
		0:
			if _choke_phase_t > _choke_stand_time or health < 30.0:
				# the legs give out: down on his knees, still holding his throat
				_next_choke_phase(0.7)
		1:
			if _choke_phase_t > 1.4:
				# keels over onto the floor
				_next_choke_phase(0.15)
				collision_layer = 0
		2:
			if _choke_t >= _c_choke_fall.length:
				_next_choke_phase(0.0)
				_pick_floor_clip(true)
		3:
			# writhing and rolling over, strung together at random
			_choke_t += delta * (_floor_speed - 1.0)
			_floor_left -= delta
			var rolling := not _is_writhe(_floor_clip)
			if (rolling and _choke_t >= _floor_clip.length) or (not rolling and _floor_left <= 0.0):
				_pick_floor_clip(false)
	var drift := Vector3.ZERO
	if _choke_phase == 0:
		# reeling on the spot, a little this way and that
		drift = global_transform.basis * Vector3(sin(_time * 1.3) * 0.22, 0.0, cos(_time * 0.8) * 0.18)
	if _choke_phase == 3:
		var pp := _lib.pelvis_pos(_floor_clip, _choke_clip_t(_floor_clip))
		var d := global_transform.basis * Vector3(pp.x - _floor_prev.x, 0.0, pp.z - _floor_prev.z)
		_floor_prev = pp
		velocity.x = d.x / delta
		velocity.z = d.z / delta
	else:
		velocity.x = move_toward(velocity.x, drift.x, 2.0 * delta)
		velocity.z = move_toward(velocity.z, drift.z, 2.0 * delta)
	_wild_fire(delta)
	if is_on_floor():
		velocity.y = -0.5
	else:
		velocity.y -= 9.8 * delta
	move_and_slide()
	_cough_cd -= delta
	if _neck_wound and _cough_cd <= 0.0:
		_cough_cd = randf_range(1.0, 2.6) * (0.75 if _choke_phase > 0 else 1.0)
		_cough()
	_update_layers(delta, 0.0)
	_bleed(delta, 0.12, 0.28)
	_apply_pose(_compute_pose())


func _choke_clip() -> MannequinAnims.Clip:
	return [_c_choke_stand, _c_choke_knees, _c_choke_fall, _floor_clip][_choke_phase]


func _choke_clip_t(cc: MannequinAnims.Clip) -> float:
	if cc == _c_choke_fall or (_choke_phase == 3 and not _is_writhe(cc)):
		return minf(_choke_t, cc.length)
	return fposmod(_choke_t, cc.length)


func _is_writhe(c: MannequinAnims.Clip) -> bool:
	return c == _c_choke_floor or c == _c_down_floor


## Next bit of floor thrashing: writhing side to side for a while or a full
## roll over either way, at a random pace.
func _pick_floor_clip(from_fall: bool) -> void:
	var belly := _downed and not _neck_wound
	var c := _c_down_floor if belly else _c_choke_floor
	if not from_fall and randf() < 0.6:
		if belly:
			c = _c_down_roll_l if randf() < 0.5 else _c_down_roll_r
		else:
			c = _c_choke_roll_l if randf() < 0.5 else _c_choke_roll_r
	if not from_fall:
		_capture_blend()
		_blend_time = 0.3
	_floor_clip = c
	_floor_speed = randf_range(0.8, 1.3)
	_floor_left = randf_range(1.5, 3.5)
	_choke_t = 0.0 if from_fall or not _is_writhe(c) else randf() * c.length
	_floor_prev = _lib.pelvis_pos(c, _choke_t)


func _next_choke_phase(blend: float) -> void:
	if blend > 0.0:
		_capture_blend()
		_blend_time = blend
	_choke_phase += 1
	_choke_phase_t = 0.0
	_choke_t = 0.0


## A gasp that brings up blood: chest and head jerk, the mouth sprays.
func _cough() -> void:
	_spring_vel[1] += Vector3(-2.2, randf_range(-0.6, 0.6), 0.0)
	_spring_vel[2] += Vector3(randf_range(2.0, 4.0), randf_range(-1.0, 1.0), 0.0)
	if head_gone:
		return
	var mouth := head.to_global(Vector3(0, -0.055, -0.1))
	Blood.spray(mouth, head.global_basis * Vector3(0, -0.35, -1), 7, 0.8, 2.4, 0.4, 0.008, 0.02)
	Blood.drip(mouth, randf_range(0.015, 0.025))


# ------------------------------------------------------------------ orders

## The player's order (see Game.ORDERS). Returns false when he cannot obey.
func order(cmd: String) -> bool:
	if dead or display_only or _suicide_t >= 0.0:
		return false
	if cmd == "suicide":
		# only an armed man can, and he does
		if _gun == null or state == State.KNOCKED or state == State.GETUP:
			return false
		_start_suicide(true)
		return true
	if _neck_wound or _downed:
		return false
	if team == 1 and not _gives_up():
		return false # the enemy only listens once he has had enough
	match cmd:
		"free":
			_set_order("")
			return true
		"flee":
			_set_order("")
			if state == State.IDLE or state == State.WANDER:
				state = State.PANIC
				_state_time = randf_range(6.0, 10.0)
				_flee_target()
			return true
	if _gun != null and (cmd == "drop" or cmd == "hands_up" or cmd == "kneel"):
		# told to give up: with no way out an armed man may take the other exit
		if _hopeless() and randf() < 0.5:
			_start_suicide()
			return true
		drop_gun(-global_transform.basis.z * 0.5 + Vector3.UP * 0.4)
	if cmd == "drop":
		cmd = "hands_up"
	_set_order(cmd)
	return true


func _gives_up() -> bool:
	return health < 65.0 or _knee_hits > 0 or _gun == null or randf() < 0.3


func _set_order(cmd: String) -> void:
	var clip_name: String = ORDER_CLIPS.get(cmd, "")
	var c: MannequinAnims.Clip = _lib.clip(clip_name) if clip_name != "" else null
	var posed := state == State.IDLE or state == State.WANDER or state == State.PANIC or state == State.ORDER \
			or state == State.SHOOT
	if posed:
		_aiming = false
		_target = null
	if posed and c != _order_clip:
		_capture_blend()
		_blend_time = 0.9 # going down on the knees / raising the hands takes a moment
	_order = cmd
	_order_clip = c
	_t_order = 0.0
	_order_retarget = 0.0
	if cmd == "":
		if state == State.ORDER:
			state = State.IDLE
			_state_time = randf_range(1.5, 3.0)
	elif posed:
		state = State.ORDER


# ------------------------------------------------------------------ pistol

func _attach_gun() -> void:
	armed = true
	if weapon != "pistol":
		var svd := weapon == "svd"
		_gun = (load(SVD_SCENE if svd else RIFLE_SCENE) as PackedScene).instantiate()
		_gun.transform = Transform3D(RIFLE_BASIS, GUN_HAND)
		_muzzle = SVD_MUZZLE if svd else RIFLE_MUZZLE
		_ammo = SVD_MAG if svd else RIFLE_MAG
		_c_ready = _lib.clip("rifle_ready")
		_c_aim = _lib.clip("rifle_aim")
		for mi in _gun.find_children("*", "MeshInstance3D", true, false):
			(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		farm_r.add_child(_gun)
		return
	_gun = (load(GUN_SCENE) as PackedScene).instantiate()
	var z := -GUN_BARREL
	_gun.transform = Transform3D(Basis(GUN_TOP.cross(z), GUN_TOP, z), GUN_HAND)
	_muzzle = GUN_MUZZLE
	_ammo = MAGAZINE
	_c_ready = _lib.clip("pistol_ready")
	_c_aim = _lib.clip("pistol_aim")
	if _gun_material == null:
		_gun_material = StandardMaterial3D.new()
		_gun_material.albedo_texture = load(GUN_TEXTURE)
		_gun_material.metallic = 0.3
		_gun_material.roughness = 0.5
	for mi in _gun.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_override = _gun_material
	farm_r.add_child(_gun)


## Lets go of his weapon: it falls as a loose physics prop.
func drop_gun(vel: Vector3) -> void:
	if _gun == null:
		return
	var rb := RigidBody3D.new()
	rb.mass = 1.1
	rb.collision_layer = LAYER_DEBRIS
	rb.collision_mask = LAYER_WORLD | LAYER_PROPS
	rb.continuous_cd = true
	rb.set_meta("surface", "metal")
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	if weapon == "svd":
		rb.mass = 4.3
		box.size = Vector3(0.05, 0.2, 1.25)
		cs.position = Vector3(0, 0.04, -0.3)
	elif weapon == "rifle":
		rb.mass = 3.4
		box.size = Vector3(0.05, 0.2, 1.0)
		cs.position = Vector3(0, 0.03, -0.19)
	else:
		box.size = Vector3(0.032, 0.13, 0.2)
		cs.position = Vector3(0, -0.005, -0.025)
	cs.shape = box
	rb.add_child(cs)
	rb.add_to_group("dropped_guns")
	get_tree().current_scene.add_child(rb)
	rb.global_transform = _gun.global_transform
	_gun.reparent(rb, false)
	_gun.transform = Transform3D.IDENTITY
	rb.linear_velocity = vel
	rb.angular_velocity = Vector3(randf_range(-6, 6), randf_range(-6, 6), randf_range(-6, 6))
	_gun = null
	armed = false
	var guns := get_tree().get_nodes_in_group("dropped_guns")
	while guns.size() > MAX_DROPPED_GUNS: # out of the group at once: a queued one must not count twice
		var old: Node = guns.pop_front()
		old.remove_from_group("dropped_guns")
		old.queue_free()


func _hopeless() -> bool:
	return _neck_wound or health < 45.0 or _knee_hits >= 2 or _stuck_count >= 2


## Armed and out of options (throat cut open, shot to pieces with the shooter
## close, crippled): now and then he decides to end it himself. While he can
## still run he just runs.
func _despair_check(delta: float) -> void:
	if _gun == null or _suicide_t >= 0.0 or display_only:
		return
	if state == State.STAGGER or state == State.KNOCKED or state == State.GETUP:
		return
	_despair_cd -= delta
	if _despair_cd > 0.0:
		return
	_despair_cd = 1.0
	var player := get_tree().get_first_node_in_group("player") as Node3D
	var dist := global_position.distance_to(player.global_position) if player else 99.0
	var chance := 0.0
	if _neck_wound:
		chance = 0.03
		if _choke_phase >= 1 and not _choke_despair_rolled:
			_choke_despair_rolled = true
			chance = 0.55
	elif health < 35.0 and dist < 10.0:
		chance = 0.12
	elif _knee_hits >= 2 and dist < 10.0 and state != State.PANIC:
		chance = 0.1
	if randf() < chance:
		_start_suicide()


## Raises the pistol to his temple, hesitates with a shaking hand, fires.
func _start_suicide(ordered := false) -> void:
	if _gun == null or _suicide_t >= 0.0 or dead:
		return
	if weapon != "pistol":
		# a rifle won't do: he lets it fall and draws his pistol
		drop_gun(-global_transform.basis.z * 0.3 + Vector3.UP * 0.2)
		weapon = "pistol"
		_attach_gun()
	_suicide_t = 0.0
	_suicide_fire = randf_range(1.3, 2.2) if ordered else randf_range(1.7, 3.4)
	_aiming = false
	if _order != "":
		_set_order("")
	if state == State.WANDER or state == State.PANIC or state == State.SHOOT:
		state = State.IDLE
	velocity.x = 0.0
	velocity.z = 0.0


func _update_suicide(delta: float) -> void:
	if _suicide_t < 0.0:
		return
	_suicide_t += delta
	_suicide_w = smoothstep(0.0, 1.0, _suicide_t / 0.9)
	if _suicide_t > 0.9:
		_spring_vel[6] += Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 18.0 * delta


func _suicide_shot() -> void:
	var muzzle := _gun.global_transform * _muzzle
	var c := head.global_position
	var into := (c - muzzle).normalized()
	var entry := c - into * 0.115
	var exit := c + into * 0.115
	Sfx.play_3d("gunshot", muzzle)
	var flash := OmniLight3D.new()
	flash.light_color = Color(1.0, 0.72, 0.38)
	flash.light_energy = 4.0
	flash.omni_range = 4.0
	get_tree().current_scene.add_child(flash)
	flash.global_position = muzzle
	get_tree().create_timer(0.06).timeout.connect(flash.queue_free)
	Blood.wound(head, entry, -into)
	Blood.wound(head, exit, into)
	Blood.mist(entry, -into, 0.6)
	Blood.mist(exit, into, 2.2)
	Blood.spray(exit, into + Vector3.UP * 0.15, 40, 2.5, 7.5, 0.35, 0.012, 0.035)
	Gore.chunks(exit, into, 2, 3.5)
	if _wounds.size() < 14:
		_wounds.append([head, head.to_local(exit)])
	_bleed_left = maxf(_bleed_left, 30.0)
	suicided = true
	health = 0.0
	_die(head, exit, into, 5.0, true)
	for n in get_tree().get_nodes_in_group("npcs"):
		if n != self and n.global_position.distance_to(global_position) < 22.0:
			n.alert(muzzle)


# ------------------------------------------------------------------ shooting

func _update_gun_arm(delta: float) -> void:
	var ready_t := 0.0
	var aim_t := 0.0
	if _gun != null and _suicide_t < 0.0:
		if _aiming and _reload_t <= 0.0 and (state == State.SHOOT or state == State.CHOKE):
			aim_t = 1.0
		elif state != State.CHOKE:
			ready_t = 1.0
	_ready_w = move_toward(_ready_w, ready_t, delta * 3.0)
	_aim_w = move_toward(_aim_w, aim_t, delta * 4.5)


## Turns the aim towards a point: yaw / pitch about the right shoulder for a
## pistol, about the rifle's butt (the upper body turns) for a rifle.
func _aim_towards(target: Vector3) -> void:
	var pivot := P_SHOULDER_R if weapon == "pistol" else Vector3(0.1, 1.44, 0.0)
	var local := to_local(target) - pivot
	_aim_yaw = clampf(atan2(-local.x, -local.z), -0.7, 0.7)
	_aim_pitch = clampf(atan2(local.y, Vector2(local.x, local.z).length()), -1.0, 1.0)


## Where to shoot someone: an NPC's chest, the player's upper body.
func _aim_point(t: Node3D) -> Vector3:
	if t is Npc:
		return (t as Npc).center()
	if t is FpvDrone:
		return t.global_position
	if t is Player:
		return t.global_position + Vector3.UP * ((t as Player).eye_height() - 0.3) # lower when he crouches
	return t.global_position + Vector3.UP * 1.3


## Clear line of fire from his eyes to a point.
func _sees(target: Vector3) -> bool:
	var from := head.global_position
	var q := PhysicsRayQueryParameters3D.create(from, target, LAYER_WORLD | LAYER_PROPS)
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()


# ------------------------------------------------------------------ war AI

## Still a threat: alive, on his feet and not surrendering.
func is_combatant() -> bool:
	return not dead and not _downed and not _neck_wound and not unconscious and _order != "hands_up" and _order != "kneel" \
			and state != State.KNOCKED and state != State.GETUP


func _enemies() -> Array[Node3D]:
	var out: Array[Node3D] = []
	for n in get_tree().get_nodes_in_group("npcs"):
		if n.team != team and n.is_combatant():
			out.append(n)
	if team == 1:
		var player := get_tree().get_first_node_in_group("player") as Player
		if player and not player.dead:
			out.append(player)
	for d in get_tree().get_nodes_in_group("drones"):
		if d.team != team and not d.dead:
			out.append(d)
	return out


## A few times a second: the nearest enemy he can see (in front of him, or
## anywhere right after shots) becomes his target.
func _war_think(delta: float) -> void:
	_alerted_t -= delta
	_scan_cd -= delta
	if _scan_cd > 0.0 or _gun == null:
		return
	_scan_cd = randf_range(0.3, 0.5)
	var surrendered := state == State.ORDER and _order != "stand" and _order != "come"
	if surrendered or not (state == State.IDLE or state == State.WANDER or state == State.SHOOT or state == State.ORDER):
		return
	var eye := head.global_position
	var fwd := -global_transform.basis.z
	var best: Node3D = null
	var best_d := 170.0 if weapon == "svd" else 75.0
	for e in _enemies():
		var tp := _aim_point(e)
		var d := eye.distance_to(tp)
		if d >= best_d:
			continue
		if e != _target and _alerted_t <= 0.0 and d > 10.0 and fwd.dot((tp - eye) / d) < -0.1:
			continue
		if _sees(tp):
			best = e
			best_d = d
	if best:
		_target = best
		_lost_t = 0.0
		if state != State.SHOOT:
			_start_fight()
	elif state == State.SHOOT:
		_lost_t += 0.4
		if _lost_t > 2.5:
			_end_fight()


func _start_fight() -> void:
	state = State.SHOOT
	_aiming = true
	_shoot_cd = randf_range(0.3, 0.7)
	_burst_left = 0
	velocity.x = 0.0
	velocity.z = 0.0


func _end_fight() -> void:
	_target = null
	_aiming = false
	state = State.IDLE
	_state_time = randf_range(0.5, 1.5)


func _shoot_process(delta: float) -> void:
	if _gun == null or not is_instance_valid(_target) or (_target is Npc and not (_target as Npc).is_combatant()) \
			or (_target is Player and (_target as Player).dead) or (_target is FpvDrone and (_target as FpvDrone).dead):
		_end_fight()
		return
	var target := _aim_point(_target)
	_aim_towards(target)
	if _reload_t > 0.0:
		_reload_t -= delta
		if _reload_t <= 0.0:
			_ammo = {"rifle": RIFLE_MAG, "svd": SVD_MAG}.get(weapon, MAGAZINE)
		return
	_nade_cd -= delta
	if _nade_cd <= 0.0 and weapon != "svd":
		_nade_cd = randf_range(10.0, 25.0)
		if not (_target is FpvDrone) and randf() < 0.45:
			_throw_grenade(target)
	_shoot_cd -= delta
	if _shoot_cd > 0.0 or _aim_w < 0.85:
		return
	# farther, hurt men shoot worse; a rifle fires short bursts, a sniper
	# takes his time over every shot
	var dist := head.global_position.distance_to(target)
	if weapon == "svd":
		_fire_at(target, 0.15 + dist * 0.0035 + (100.0 - health) * 0.02)
	else:
		_fire_at(target, 0.5 + dist * 0.028 + (100.0 - health) * 0.04)
	if _ammo <= 0:
		_reload_t = 2.6 if weapon != "svd" else 3.2
		_burst_left = 0
		_shoot_cd = 0.3
	elif weapon == "svd":
		_shoot_cd = randf_range(2.2, 4.2)
	elif weapon == "rifle":
		if _burst_left <= 0:
			_burst_left = randi_range(2, 5)
		_burst_left -= 1
		_shoot_cd = 0.1 if _burst_left > 0 else randf_range(0.5, 1.2)
	else:
		_shoot_cd = randf_range(0.45, 1.2)


## Sends him to his post (holding) or the enemy's line (assault).
func _war_move(retry := false) -> void:
	if post == Vector3.ZERO or (not retry and global_position.distance_to(post) < 1.5):
		# at his post: watch the enemy's side a while, sometimes shift along the line
		_state_time = randf_range(4.0, 10.0)
		state = State.IDLE
		if role == "hold" and randf() < 0.25 and not war_posts[team].is_empty():
			post = war_posts[team][randi() % war_posts[team].size()]
		return
	if retry:
		post = NavigationServer3D.map_get_closest_point(get_world_3d().navigation_map, post + Vector3(randf_range(-2, 2), 0, randf_range(-2, 2)))
	state = State.WANDER
	_speed = randf_range(3.3, 3.8) if role == "assault" else randf_range(1.6, 2.4)
	_agent.target_position = post
	_stuck_time = 0.0
	_last_pos = global_position


func _arrived() -> void:
	state = State.IDLE
	_state_time = randf_range(2.0, 5.0)
	if role == "assault":
		role = "hold" # took the enemy's trench: holds it


## Throat open and a gun in his hand: he lets off shots towards the enemy
## as he chokes, reels and rolls about, barely aiming.
func _wild_fire(delta: float) -> void:
	_wild_left = maxf(_wild_left - delta, 0.0) if _wild_left > 0.0 else _wild_left
	if _gun == null or _suicide_t >= 0.0 or _ammo <= 0 or _wild_left <= 0.0:
		_aiming = false
		return
	var foe: Node3D = _target if is_instance_valid(_target) else null
	if foe == null:
		for e in _enemies():
			if foe == null or e.global_position.distance_to(global_position) < foe.global_position.distance_to(global_position):
				foe = e
	if foe == null or global_position.distance_to(foe.global_position) > 30.0:
		_aiming = false
		return
	_aiming = true
	if _choke_phase == 0:
		var tp := foe.global_position - global_position
		rotation.y = lerp_angle(rotation.y, atan2(-tp.x, -tp.z), 2.0 * delta)
	# the gun wanders about while he tries to point it
	_aim_towards(_aim_point(foe))
	_aim_yaw += sin(_time * 2.3) * 0.45 + sin(_time * 5.7) * 0.15
	_aim_pitch += sin(_time * 1.7) * 0.3
	_wild_cd -= delta
	if _wild_cd <= 0.0 and _aim_w > 0.6:
		_wild_cd = randf_range(0.12, 0.5) if weapon == "rifle" else randf_range(0.35, 1.3)
		_fire_at(_aim_point(foe), 9.0, 0.45)


## One round from his gun towards `target`; `wild` mixes in where the
## barrel actually points.
func _fire_at(target: Vector3, spread_deg: float, wild := 0.0) -> void:
	if _gun == null:
		return
	_ammo -= 1
	var muzzle := _gun.global_transform * _muzzle
	var barrel := (_gun.global_basis * Vector3(0, 0, -1)).normalized()
	var dir := (target - muzzle).normalized()
	if wild > 0.0:
		dir = dir.lerp(barrel, wild).normalized()
	var side := dir.cross(Vector3.UP if absf(dir.y) < 0.9 else Vector3.RIGHT).normalized()
	dir = dir.rotated(side, deg_to_rad(randf_range(-spread_deg, spread_deg)))
	dir = dir.rotated(dir.cross(side).normalized(), deg_to_rad(randf_range(-spread_deg, spread_deg)))
	_muzzle_flash(muzzle, dir)
	_spring_vel[6] += Vector3(randf_range(3.0, 5.0), randf_range(-1.0, 1.0), 0.0)
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(muzzle, muzzle + dir * 120.0, LAYER_WORLD | LAYER_PROPS | LAYER_PARTS | 16)
	var ex: Array[RID] = [get_rid()]
	for p in parts:
		ex.append(p.get_rid())
	q.exclude = ex
	for _i in 4:
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			break
		var c: Object = hit.collider
		var pos: Vector3 = hit.position
		var normal: Vector3 = hit.normal
		if c is Player:
			if team == 0: # his own side's rounds don't count against the player
				ex.append(c.get_rid())
				q.exclude = ex
				q.from = pos + dir * 0.01
				continue
			(c as Player).take_damage(BULLET_DAMAGE_PLAYER * (1.15 if weapon == "rifle" else 1.0), dir,
					"sniper" if weapon == "svd" else "bullet")
			break
		if c.has_meta("npc"):
			var other = c.get_meta("npc")
			if is_instance_valid(other) and other.team == team and not other.dead:
				# his own side: soldiers don't fire through their mates
				ex.append(c.get_rid())
				q.exclude = ex
				q.from = pos + dir * 0.01
				continue
			if is_instance_valid(other):
				other.last_hit_by_player = false
				if weapon == "svd":
					other.take_hit(c, pos, normal, dir, BULLET_DAMAGE_NPC * 2.6, 24.0)
				else:
					other.take_hit(c, pos, normal, dir, BULLET_DAMAGE_NPC * (1.2 if weapon == "rifle" else 1.0), 11.0)
			break
		if c.get_meta("surface", "") == "glass" and c.has_method("shatter"):
			c.shatter(pos, dir)
			ex.append(c.get_rid())
			q.exclude = ex
			q.from = pos + dir * 0.01
			continue
		if c.has_meta("drone"):
			c.take_bullet(pos, dir, 30.0)
			break
		if c.has_method("take_bullet"):
			c.take_bullet(pos, dir, 30.0)
		if c is RigidBody3D:
			(c as RigidBody3D).apply_impulse(dir * 4.0, pos - (c as RigidBody3D).global_position)
			Blood.bullet_hole(pos, normal, c as Node3D)
		else:
			Blood.bullet_hole(pos, normal, c as Node3D if c is AnimatableBody3D else null)
		Blood.dust(pos, normal)
		break
	for n in get_tree().get_nodes_in_group("npcs"):
		if n != self and n.global_position.distance_to(global_position) < 22.0:
			n.alert(muzzle)


## Lobs a grenade at `at` (8..32 m away): a 40 degree arc, a little off.
func _throw_grenade(at: Vector3) -> void:
	var from := head.global_position + Vector3.UP * 0.15 - global_transform.basis.z * 0.3
	var flat := Vector3(at.x - from.x, 0.0, at.z - from.z)
	var d := flat.length()
	if d < 8.0 or d > 32.0:
		return
	var h := at.y - 1.0 - from.y
	var th := deg_to_rad(40.0)
	var den := 2.0 * cos(th) * cos(th) * (d * tan(th) - h)
	if den <= 0.0:
		return
	var v := sqrt(9.8 * d * d / den) * randf_range(0.9, 1.08)
	var dir := flat / d
	_spring_vel[5] += Vector3(-9.0, 0.0, 0.0) # the arm swings over
	Grenade.throw(get_tree(), from, dir * v * cos(th) + Vector3.UP * v * sin(th), false, randf_range(2.6, 3.4))


## Caught in a blast (f: 0 at its edge .. 1 on top of it). Close up it tears
## him apart; it throws him down and hurts him through his whole body.
func blast(center: Vector3, f: float, power: float) -> void:
	var c := chest.global_position
	var dir := (c - center).normalized()
	if f > 0.72 and not display_only:
		for p in [uarm_l, uarm_r, farm_l, farm_r, thigh_l, thigh_r, shin_l, shin_r]:
			if randf() < 0.3 * power:
				sever(p, (p.global_position - center).normalized())
		if randf() < 0.5:
			spill_organs(pelvis if randf() < 0.5 else chest, c - dir * 0.12, -dir, dir)
	if dead:
		for p in parts:
			if not p.freeze:
				p.apply_central_impulse((p.global_position - center).normalized() * p.mass * 7.0 * f * power + Vector3.UP * p.mass * 2.0 * f)
		return
	take_hit(chest, c - dir * 0.12, -dir, (dir + Vector3.UP * 0.6).normalized(), 170.0 * f * f * power, 30.0 * f + 6.0)
	if not dead and state != State.KNOCKED and f > 0.25:
		_knockdown(chest, c, (dir + Vector3.UP * 0.5).normalized(), 25.0 * f)


func _muzzle_flash(muzzle: Vector3, dir: Vector3) -> void:
	Sfx.play_3d({"rifle": "rifle", "svd": "sniper"}.get(weapon, "gunshot"), muzzle, 3.0 if weapon == "svd" else 0.0)
	var root := get_tree().current_scene
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.72, 0.38)
	light.light_energy = 4.0
	light.omni_range = 4.0
	root.add_child(light)
	light.global_position = muzzle + dir * 0.05
	var s := Sprite3D.new()
	s.texture = load("res://assets/textures/muzzle_flash.png")
	s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	s.shaded = false
	s.pixel_size = 0.0012
	s.modulate = Color(1.4, 1.1, 0.8)
	s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(s)
	s.global_position = muzzle + dir * 0.06
	get_tree().create_timer(0.05).timeout.connect(light.queue_free)
	get_tree().create_timer(0.05).timeout.connect(s.queue_free)


## Body hit position estimate for camera / spawn logic.
func center() -> Vector3:
	return chest.global_position if chest else global_position + Vector3.UP
