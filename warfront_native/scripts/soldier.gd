extends "res://scripts/vehicle.gd"
## Infantry soldier. The body is 15 joints; while alive they are posed procedurally (walk cycle, two-bone IK
## for knees and for the arms holding the weapon), when killed they become a Verlet ragdoll that keeps the
## same limb lengths. Body-part meshes are placed between joints every frame, and hits are tested against
## capsules on the same joints, so a bullet through the head is a headshot.

enum { HEAD, NECK, PELVIS, SL, SR, EL, ER, WL, WR, HIPL, HIPR, KL, KR, AL, AR }
const UP := Vector3.UP
const L_UPPER := 0.29
const L_FORE := 0.27
const L_THIGH := 0.44
const L_SHIN := 0.43
const L_TORSO := 0.5
const ANKLE_H := 0.095
const WEAPON_MODELS := {"ak": "ak47", "shotgun": "m500", "stinger": "stinger"}
# capsules for hit tests: [joint a, joint b, radius, part]
const HITBOX := [[NECK, HEAD, 0.125, "head"], [PELVIS, NECK, 0.2, "torso"], [SL, EL, 0.065, "arm"], [SR, ER, 0.065, "arm"],
	[EL, WL, 0.055, "arm"], [ER, WR, 0.055, "arm"], [HIPL, KL, 0.09, "leg"], [HIPR, KR, 0.09, "leg"], [KL, AL, 0.065, "leg"], [KR, AR, 0.065, "leg"]]
# ragdoll links: rigid torso box, head, limbs
const LINKS := [[HEAD, NECK], [NECK, PELVIS], [SL, SR], [SL, NECK], [SR, NECK], [SL, PELVIS], [SR, PELVIS], [HIPL, HIPR], [HIPL, PELVIS],
	[HIPR, PELVIS], [HIPL, NECK], [HIPR, NECK], [SL, HIPR], [SR, HIPL], [SL, HIPL], [SR, HIPR], [HEAD, SL], [HEAD, SR],
	[SL, EL], [EL, WL], [SR, ER], [ER, WR], [HIPL, KL], [KL, AL], [HIPR, KR], [KR, AR]]
const RADIUS := [0.11, 0.06, 0.1, 0.07, 0.07, 0.05, 0.05, 0.05, 0.05, 0.07, 0.07, 0.06, 0.06, 0.06, 0.06]
# ragdoll: heavy trunk, lighter head and limbs (inverse masses), and how stiff each link is
const INV_MASS := [0.6, 0.35, 0.3, 0.4, 0.4, 0.8, 0.8, 1.0, 1.0, 0.35, 0.35, 0.8, 0.8, 1.0, 1.0]
const LINK_K := [1.0, 1.0, 0.9, 0.9, 0.9, 0.7, 0.7, 0.9, 0.9, 0.9, 0.6, 0.6, 0.45, 0.45, 0.6, 0.6, 0.5, 0.5,
	1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0]
const RAG_H := 1.0 / 120.0

static var _meshes := {}
static var _winfo := {}

var jp := PackedVector3Array()
var jprev := PackedVector3Array()
var rest := PackedFloat32Array()
var ragdoll := false
var rag_t := 0.0
var rag_still := 0.0
var jvel := PackedVector3Array()   # joint velocities of the live pose, carried into the ragdoll
var parts: Array = []            # [MeshInstance3D, joint a, joint b, kind]
var guns := {}                   # weapon name -> Node3D
var gun_xf := Transform3D()
var muzzle_world := Vector3.ZERO
var gait := 0.0
var aim_pitch := 0.0
var mag: Array[int] = []
var reload_t := 0.0
var sprinting := false
var step_t := 0.0
var hit_part := ""
var last_impulse := Vector3.ZERO
var lod_skip := 0
var recoil_kick := 0.0


func _build_model() -> void:
	hull = Node3D.new()
	add_child(hull)
	if _meshes.is_empty():
		var sc: Node3D = load("res://assets/models/soldier.glb").instantiate()
		for mi in sc.find_children("*", "MeshInstance3D", true, false):
			_meshes[String(mi.name).get_slice("_", 0)] = (mi as MeshInstance3D).mesh
		sc.free()
		_winfo = JSON.parse_string(FileAccess.get_file_as_string("res://assets/models/weapons.json"))
	var tint := Color(1, 1, 1) if team == "blue" or team.begins_with("p") else Color(1.3, 1.12, 0.82)
	var mat: Material = null
	var src: Mesh = _meshes.get("Torso")
	if src and src.surface_get_material(0) is BaseMaterial3D:
		mat = (src.surface_get_material(0) as BaseMaterial3D).duplicate()
		(mat as BaseMaterial3D).albedo_color = tint
	for spec in [["Torso", PELVIS, NECK, "limb"], ["Pelvis", PELVIS, NECK, "limb"], ["Head", NECK, HEAD, "limb"],
			["UpperArm", SL, EL, "limb"], ["UpperArm", SR, ER, "limb"], ["LowerArm", EL, WL, "limb"], ["LowerArm", ER, WR, "limb"],
			["Hand", WL, -EL - 1, "hand"], ["Hand", WR, -ER - 1, "hand"], ["Thigh", HIPL, KL, "limb"], ["Thigh", HIPR, KR, "limb"],
			["Shin", KL, AL, "limb"], ["Shin", KR, AR, "limb"], ["Foot", AL, KL, "foot"], ["Foot", AR, KR, "foot"]]:
		var mi := MeshInstance3D.new()
		mi.mesh = _meshes.get(spec[0])
		if mat:
			mi.material_override = mat
		mi.top_level = true
		mi.visibility_range_end = 1600.0
		hull.add_child(mi)
		parts.append([mi, spec[1], spec[2], spec[3]])
	for w in WEAPON_MODELS:
		var g: Node3D = load("res://assets/models/%s.glb" % WEAPON_MODELS[w]).instantiate()
		g.top_level = true
		g.visible = false
		hull.add_child(g)
		for m in g.find_children("*", "MeshInstance3D", true, false):
			(m as MeshInstance3D).visibility_range_end = 900.0
		guns[w] = g
	muzzle = Sprite3D.new()
	muzzle.texture = preload("res://assets/fx/glow.png")
	muzzle.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	muzzle.material_override = _additive(preload("res://assets/fx/glow.png"))
	muzzle.modulate = Color(1, 0.8, 0.45)
	muzzle.visible = false
	muzzle.top_level = true
	add_child(muzzle)
	jp.resize(15)
	jprev.resize(15)


## A standing soldier holding the AK, for the vehicle selection screen.
static func preview_node() -> Node3D:
	var root := Node3D.new()
	var sc: Node3D = load("res://assets/models/soldier.glb").instantiate()
	var meshes := {}
	for mi in sc.find_children("*", "MeshInstance3D", true, false):
		meshes[String(mi.name).get_slice("_", 0)] = (mi as MeshInstance3D).mesh
	sc.free()
	var f := Vector3(0, 0, -1)
	var right := Vector3(1, 0, 0)
	var j := {}
	j[PELVIS] = Vector3(0, 0.99, 0)
	j[NECK] = Vector3(0, 1.49, -0.03)
	j[HEAD] = j[NECK] + Vector3(0, 0.2, 0)
	j[SL] = j[NECK] + Vector3(-0.19, -0.05, 0)
	j[SR] = j[NECK] + Vector3(0.19, -0.05, 0)
	j[HIPL] = Vector3(-0.095, 0.96, 0)
	j[HIPR] = Vector3(0.095, 0.96, 0)
	var kl := ik(j[HIPL], Vector3(-0.13, ANKLE_H, 0.05), L_THIGH, L_SHIN, f)
	var kr := ik(j[HIPR], Vector3(0.13, ANKLE_H, -0.08), L_THIGH, L_SHIN, f)
	j[KL] = kl[0]; j[AL] = kl[1]; j[KR] = kr[0]; j[AR] = kr[1]
	var a := Vector3(0.15, -0.35, -1).normalized()
	var wb := Basis.looking_at(a, Vector3.UP)
	var grip: Vector3 = j[SR] + a * 0.26 - wb.y * 0.07 - wb.x * 0.03
	var gun_xf := Transform3D(wb, grip)
	var winfo: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/models/weapons.json"))
	var fore: Array = winfo["ak47"]["fore"]
	var re := ik(j[SR], grip - wb.y * 0.05, L_UPPER, L_FORE, Vector3.DOWN + right * 0.7)
	var le := ik(j[SL], gun_xf * Vector3(fore[0], fore[1] - 0.03, fore[2]), L_UPPER, L_FORE, Vector3.DOWN - right * 0.6)
	j[ER] = re[0]; j[WR] = re[1]; j[EL] = le[0]; j[WL] = le[1]
	var spec := [["Torso", PELVIS, NECK], ["Pelvis", PELVIS, NECK], ["Head", NECK, HEAD], ["UpperArm", SL, EL], ["UpperArm", SR, ER],
		["LowerArm", EL, WL], ["LowerArm", ER, WR], ["Thigh", HIPL, KL], ["Thigh", HIPR, KR], ["Shin", KL, AL], ["Shin", KR, AR]]
	for sp in spec:
		var mi := MeshInstance3D.new()
		mi.mesh = meshes.get(sp[0])
		mi.transform = Transform3D(basis_y(j[sp[2]] - j[sp[1]], f), j[sp[1]])
		root.add_child(mi)
	for h in [[WL, EL], [WR, ER]]:
		var mi := MeshInstance3D.new()
		mi.mesh = meshes.get("Hand")
		mi.transform = Transform3D(basis_y(j[h[0]] - j[h[1]], f), j[h[0]])
		root.add_child(mi)
	for ft in [AL, AR]:
		var mi := MeshInstance3D.new()
		mi.mesh = meshes.get("Foot")
		mi.transform = Transform3D(basis_y(Vector3.UP, f), j[ft])
		root.add_child(mi)
	var gun: Node3D = load("res://assets/models/ak47.glb").instantiate()
	gun.transform = gun_xf
	root.add_child(gun)
	return root


func reset() -> void:
	super.reset()
	ragdoll = false
	rag_t = 0.0
	reload_t = 0.0
	mag.clear()
	for s in T["slots"]:
		var W: Dictionary = D.WEAP[s["w"]]
		mag.append(mini(int(W.get("mag", 999)), int(s["a"])))
	visible = true


func place(p: Vector3, h: float, spd: float) -> void:
	super.place(p, h, spd)
	_pose(0.0, true)
	_render()


# ---------------------------------------------------------------- helpers
static func ik(a: Vector3, target: Vector3, l1: float, l2: float, pole: Vector3) -> Array:
	var d := target - a
	var L := clampf(d.length(), 0.02, l1 + l2 - 0.001)
	var dn := d.normalized() if d.length() > 1e-4 else Vector3.DOWN
	var x := (l1 * l1 - l2 * l2 + L * L) / (2.0 * L)
	var h := sqrt(maxf(l1 * l1 - x * x, 0.0))
	var pp := pole - dn * pole.dot(dn)
	pp = pp.normalized() if pp.length() > 1e-4 else Vector3.FORWARD
	return [a + dn * x + pp * h, a + dn * L]


static func basis_y(y: Vector3, fwd: Vector3) -> Basis:
	y = y.normalized()
	var z := -(fwd - y * fwd.dot(y))
	if z.length() < 1e-3:
		z = Vector3(0, 0, 1) if absf(y.z) < 0.9 else Vector3(1, 0, 0)
	z = z.normalized()
	return Basis(y.cross(z), y, z)


func eye() -> Vector3:
	return jp[HEAD] if not jp.is_empty() else pos + Vector3(0, 1.65, 0)


func centre() -> Vector3:
	return pos + Vector3(0, 1.1, 0)


func weapon_name() -> String:
	return T["slots"][slot]["w"]


func start_reload() -> void:
	var W: Dictionary = D.WEAP[weapon_name()]
	if reload_t > 0.0 or not W.has("mag") or mag[slot] >= int(W["mag"]) or ammo[slot] <= mag[slot]:
		return
	reload_t = W["reload"]
	if is_player:
		game.audio.play3d("reload", pos, -6.0, 20.0)


# ---------------------------------------------------------------- movement
func physics(dt: float) -> void:
	if ragdoll:
		return
	var mv: Vector2 = inp.get("move", Vector2.ZERO)
	if mv.length() > 1.0:
		mv = mv.normalized()
	var aim: Vector3 = inp["aim"]
	var ty := heading_of(aim)
	heading += clampf(angle_difference(heading, ty), -9.0 * dt, 9.0 * dt)
	aim_pitch = clampf(asin(clampf(aim.normalized().y, -1.0, 1.0)), -1.2, 1.3)
	var f := dir_of(heading)
	var right := Vector3(-f.z, 0, f.x)
	sprinting = mv.length() > 0.92 and mv.y > 0.6 and not inp["fire"] and reload_t <= 0.0
	var target_spd: float = (6.3 if sprinting else T["vmax"]) * mv.length() * (0.65 if mv.y < -0.2 else 1.0)
	var want := (f * mv.y + right * mv.x)
	want = want.normalized() * target_spd if want.length() > 1e-3 else Vector3.ZERO
	var vh := Vector3(vel.x, 0, vel.z).lerp(want, 1.0 - exp(-10.0 * dt))
	var np := pos + vh * dt
	var edge: float = world.HALF - 30.0
	np.x = clampf(np.x, -edge, edge)
	np.z = clampf(np.z, -edge, edge)
	np.y = world.height(np.x, np.z)
	if np.y - pos.y > 0.6 * vh.length() * dt + 0.05 and vh.length() > 0.1:
		vh *= 0.5                                   # steep uphill slows you down
	if world.building_hit(np + Vector3(0, 1.0, 0), 0.35):
		# slide along the wall
		var nx := Vector3(np.x, 0, pos.z)
		var nz := Vector3(pos.x, 0, np.z)
		if not world.building_hit(Vector3(nx.x, np.y + 1.0, nx.z), 0.35):
			np = Vector3(nx.x, world.height(nx.x, nx.z), nx.z)
			vh.z = 0.0
		elif not world.building_hit(Vector3(nz.x, np.y + 1.0, nz.z), 0.35):
			np = Vector3(nz.x, world.height(nz.x, nz.z), nz.z)
			vh.x = 0.0
		else:
			np = pos
			vh = Vector3.ZERO
		blocked += dt
	else:
		blocked = 0.0
	pos = np
	vel = vh
	speed = vh.length()
	rot = Basis(UP, heading)
	aim_dir = aim.normalized()
	if reload_t > 0.0:
		reload_t -= dt
		if reload_t <= 0.0:
			var W: Dictionary = D.WEAP[weapon_name()]
			mag[slot] = mini(int(W.get("mag", 999)), ammo[slot])
	if speed > 0.5:
		step_t -= dt * speed / (2.4 if not sprinting else 3.0)
		if step_t <= 0.0:
			step_t = 0.5
			if is_player or pos.distance_to(game.cam.global_position) < 40.0:
				game.audio.play3d("step", pos, -14.0 if is_player else -18.0, 6.0)
	recoil_kick = maxf(0.0, recoil_kick - dt * 6.0)
	_animate_alive(dt)


func _animate_alive(dt: float) -> void:
	# distant soldiers are animated less often
	# joints are always posed (hit boxes must be current); far soldiers are redrawn less often
	var old := jp.duplicate()
	_pose(dt, false)
	if dt > 0.0:
		jvel.resize(15)
		for i in 15:
			jvel[i] = (jp[i] - old[i]) / dt if old[i] != Vector3.ZERO else Vector3.ZERO
	var dc: float = pos.distance_to(game.cam.global_position)
	lod_skip += 1
	if dc < 250.0 or lod_skip % (2 if dc < 600.0 else 4) == 0:
		_render()


## Procedural pose: walk cycle with foot IK on the terrain, torso leaning into the aim, arms holding the weapon.
func _pose(dt: float, snap: bool) -> void:
	var f := dir_of(heading)
	var right := Vector3(-f.z, 0, f.x)
	var g: float = world.height(pos.x, pos.z)
	var sp := Vector2(vel.x, vel.z).length()
	gait = fmod(gait + dt * sp * (2.2 if sprinting else 2.6), TAU)
	var mdir := Vector3(vel.x, 0, vel.z).normalized() if sp > 0.3 else f
	var k := clampf(sp / 4.4, 0.0, 1.5)
	var bob := absf(sin(gait)) * 0.035 * minf(k, 1.0)
	var lean := 0.12 * k if sprinting else 0.05 * k
	var p := Vector3(pos.x, g + 0.99 - bob - (0.04 if sprinting else 0.0), pos.z)
	var tup := (UP + f * (lean + maxf(0.0, -aim_pitch) * 0.15)).normalized()
	var n := p + tup * L_TORSO
	jp[PELVIS] = p
	jp[NECK] = n
	var look := dir_of(heading) * cos(aim_pitch * 0.6) + UP * sin(aim_pitch * 0.6)
	jp[HEAD] = n + (tup * 0.9 + look * 0.1).normalized() * 0.2
	jp[SL] = n - tup * 0.05 - right * 0.19
	jp[SR] = n - tup * 0.05 + right * 0.19
	jp[HIPL] = p - UP * 0.03 - right * 0.095
	jp[HIPR] = p - UP * 0.03 + right * 0.095
	var stride := 0.32 * minf(k, 1.4)
	for side in 2:
		var hip: Vector3 = jp[HIPL] if side == 0 else jp[HIPR]
		var ph := gait + (0.0 if side == 0 else PI)
		var lift := maxf(0.0, cos(ph)) * 0.15 * minf(k, 1.0)
		var foot := Vector3(hip.x, 0, hip.z) + mdir * sin(ph) * stride + right * (-0.02 if side == 0 else 0.02)
		foot.y = world.height(foot.x, foot.z) + ANKLE_H + lift
		var r := ik(hip, foot, L_THIGH, L_SHIN, f + UP * 0.1)
		jp[KL if side == 0 else KR] = r[0]
		jp[AL if side == 0 else AR] = r[1]
	# weapon held in front of the right shoulder, pointing where we aim
	var w := weapon_name()
	var a := aim_dir if aim_dir.length() > 0.5 else f
	if sprinting:
		a = (f * 0.7 - UP * 0.5 + right * 0.3).normalized()
	var wb := Basis.looking_at(a, UP)
	var grip: Vector3
	var ads: bool = is_player and game.ctrl["zoom"] and not sprinting and reload_t <= 0.0
	if ads:
		# first-person aiming: bring the sights up to the eye
		var eye_p: Vector3 = jp[NECK].lerp(jp[HEAD], 0.6) + game.cam_fwd * 0.1
		grip = eye_p + a * (0.42 if w == "stinger" else 0.3) - wb.y * (0.17 if w == "stinger" else 0.062) - wb.x * (0.05 if w == "stinger" else 0.0)
	elif w == "stinger":
		grip = jp[SR] + a * 0.3 - wb.y * 0.16 + wb.x * 0.02
	else:
		grip = jp[SR] + a * (0.24 - recoil_kick * 0.06) - wb.y * 0.07 - wb.x * 0.03
	if reload_t > 0.0:
		grip += -UP * 0.12 + f * 0.05
		wb = wb.rotated(wb.x, -0.5)
	gun_xf = Transform3D(wb, grip)
	var info: Dictionary = _winfo.get(WEAPON_MODELS[w], {})
	var fore: Array = info.get("fore", [0, -0.02, -0.25])
	var mz: Array = info.get("muzzle", [0, 0, -0.6])
	muzzle_world = gun_xf * Vector3(mz[0], mz[1], mz[2])
	var left_hand := gun_xf * Vector3(fore[0], fore[1] - 0.03, fore[2])
	var right_hand := grip - wb.y * 0.05 - a * 0.03
	var re := ik(jp[SR], right_hand, L_UPPER, L_FORE, -UP + right * 0.7 - f * 0.2)
	var le := ik(jp[SL], left_hand, L_UPPER, L_FORE, -UP - right * 0.6 - f * 0.1)
	jp[ER] = re[0]
	jp[WR] = re[1]
	jp[EL] = le[0]
	jp[WL] = le[1]


func _render() -> void:
	var up := jp[NECK] - jp[PELVIS]
	var right := jp[SR] - jp[SL]
	var fwd := up.cross(right).normalized()
	# in first person our own head would fill the screen: keep only its shadow
	var hide_head: bool = is_player and not dead
	for prt in parts:
		var mi: MeshInstance3D = prt[0]
		if prt[2] == HEAD and prt[1] == NECK:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY if hide_head else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		var a: int = prt[1]
		var b: int = prt[2]
		var y: Vector3
		match prt[3]:
			"hand":
				y = jp[a] - jp[-b - 1]
			"foot":
				y = jp[b] - jp[a] if ragdoll else UP
			_:
				y = jp[b] - jp[a]
		mi.global_transform = Transform3D(basis_y(y, fwd), jp[a])
	for w in guns:
		var g: Node3D = guns[w]
		g.visible = w == weapon_name() and not dead
		if g.visible:
			g.global_transform = gun_xf


func flash_muzzle(p: Vector3, s: float) -> void:
	super.flash_muzzle(p, s * 0.5)
	recoil_kick = 1.0


# ---------------------------------------------------------------- hits
## Closest body part hit by the segment a->b, or "" when it misses; hit_point is set.
var hit_point := Vector3.ZERO
func test_hit(a: Vector3, b: Vector3) -> String:
	var best := ""
	var bd := INF
	for hb in HITBOX:
		var q := Geometry3D.get_closest_points_between_segments(a, b, jp[hb[0]], jp[hb[1]])
		var d := q[0].distance_to(q[1])
		if d < hb[2]:
			var along := a.distance_to(q[0])
			if along < bd:
				bd = along
				best = hb[3]
				hit_point = q[0]
	return best


# ---------------------------------------------------------------- ragdoll
func start_wreck() -> void:
	ragdoll = true
	wreck = true
	rag_t = 0.0
	rag_still = 0.0
	for g in guns.values():
		g.visible = false
	muzzle.visible = false
	var f := dir_of(heading)
	var right := Vector3(-f.z, 0, f.x)
	# start from the motion the body already had (walking, running)
	var v := PackedVector3Array()
	v.resize(15)
	for i in 15:
		v[i] = jvel[i] if jvel.size() == 15 else Vector3(vel.x, 0, vel.z)
	# muscles let go: the knees fold forward and the hips drop, the upper body sags back
	v[KL] += f * 1.3
	v[KR] += f * 1.3
	v[PELVIS] += Vector3(0, -1.0, 0) - f * 0.2
	v[HIPL] += Vector3(0, -1.0, 0) - f * 0.2
	v[HIPR] += Vector3(0, -1.0, 0) - f * 0.2
	v[NECK] -= f * 0.35
	v[HEAD] -= f * 0.45
	# a little asymmetry so no two falls look the same
	var tw := randf_range(-0.35, 0.35)
	v[SL] += right * tw
	v[SR] -= right * tw
	# the hit pushes the body near where it landed, the head harder for a headshot
	var imp := last_impulse
	var sigma := 0.6 if imp.length() > 6.0 else 0.3
	var at: Vector3 = hit_point if hit_point != Vector3.ZERO else jp[NECK]
	if hit_part == "head":
		at = jp[HEAD]
	for i in 15:
		var w: float = exp(-jp[i].distance_to(at) / sigma)
		v[i] += imp * w * INV_MASS[i] * 1.6
	for i in 15:
		jprev[i] = jp[i] - v[i] * RAG_H
	rest.resize(LINKS.size())
	for i in LINKS.size():
		rest[i] = jp[LINKS[i][0]].distance_to(jp[LINKS[i][1]])


func end_wreck() -> void:
	ragdoll = false
	wreck = false


## Move points a and b toward distance target (weighted by inverse mass and stiffness k).
func _solve(a: int, b: int, target: float, k: float) -> void:
	var d := jp[b] - jp[a]
	var l := d.length()
	if l < 1e-6:
		return
	var wa: float = INV_MASS[a]
	var wb: float = INV_MASS[b]
	var c := d * ((l - target) / (l * (wa + wb)) * k)
	jp[a] += c * wa
	jp[b] -= c * wb


func _min_dist(a: int, b: int, m: float) -> void:
	if jp[a].distance_to(jp[b]) < m:
		_solve(a, b, m, 1.0)


func _max_dist(a: int, b: int, m: float) -> void:
	if jp[a].distance_to(jp[b]) > m:
		_solve(a, b, m, 1.0)


## Keep a point outside the capsule pelvis->neck (arms don't pass through the chest).
func _out_of_torso(i: int, r: float) -> void:
	var q := Geometry3D.get_closest_point_to_segment(jp[i], jp[PELVIS], jp[NECK])
	var d := jp[i] - q
	var l := d.length()
	if l < r and l > 1e-5:
		jp[i] = q + d / l * r


func wreck_update(dt: float) -> bool:
	if not ragdoll:
		return false
	rag_t += dt
	if rag_still > 0.6 or rag_t > 12.0:
		return false                                  # at rest: stop simulating
	var steps := clampi(int(round(dt / RAG_H)), 1, 8)
	var moving := 0.0
	for s in steps:
		for i in 15:
			var p := jp[i]
			var v := (p - jprev[i]) * 0.998
			jprev[i] = p
			jp[i] = p + v + Vector3(0, -G * RAG_H * RAG_H, 0)
		for it in 8:
			for li in LINKS.size():
				_solve(LINKS[li][0], LINKS[li][1], rest[li], LINK_K[li])
			var up := jp[NECK] - jp[PELVIS]
			var fwd := up.cross(jp[SR] - jp[SL]).normalized()
			var upn := up.normalized()
			# knees bend only forward and never fold flat; the hip does not swing far backwards
			for leg in [[HIPL, KL, AL], [HIPR, KR, AR]]:
				var mid := (jp[leg[0]] + jp[leg[2]]) * 0.5
				var off := (jp[leg[1]] - mid).dot(fwd)
				if off < 0.0:
					jp[leg[1]] -= fwd * off * 0.8
				_min_dist(leg[0], leg[2], 0.26)
				var back := (jp[leg[1]] - jp[leg[0]]).dot(fwd)
				if back < -0.18:
					jp[leg[1]] -= fwd * (back + 0.18) * 0.7
				var high := (jp[leg[1]] - jp[leg[0]]).dot(upn)
				if high > 0.3:
					jp[leg[1]] -= upn * (high - 0.3) * 0.7
			# elbows bend only one way, arms stay out of the chest
			for arm in [[SL, EL, WL], [SR, ER, WR]]:
				var mid := (jp[arm[0]] + jp[arm[2]]) * 0.5
				var off := (jp[arm[1]] - mid).dot(fwd)
				if off > 0.03:
					jp[arm[1]] -= fwd * (off - 0.03) * 0.8
				_min_dist(arm[0], arm[2], 0.16)
				_out_of_torso(arm[1], 0.15)
				_out_of_torso(arm[2], 0.14)
			# the neck can't fold the head onto the chest or far behind the back
			_min_dist(HEAD, PELVIS, 0.6)
			_min_dist(HEAD, SL, 0.17)
			_min_dist(HEAD, SR, 0.17)
			# legs don't pass through each other
			_min_dist(KL, KR, 0.13)
			_min_dist(AL, AR, 0.1)
			# ground contact with friction
			for i in 15:
				var gy: float = world.height(jp[i].x, jp[i].z) + RADIUS[i]
				if jp[i].y < gy:
					jp[i].y = gy
					var vv := jp[i] - jprev[i]
					var hv := Vector2(vv.x, vv.z)
					var keep := 0.0 if hv.length() < 0.0015 else 0.55
					jprev[i] = jp[i] - Vector3(vv.x * keep, minf(vv.y, 0.0) * -0.1, vv.z * keep)
		if s == steps - 1:
			for i in 15:
				moving = maxf(moving, (jp[i] - jprev[i]).length())
	rag_still = rag_still + dt if moving < 0.0012 and rag_t > 1.5 else 0.0
	pos = jp[PELVIS] - Vector3(0, 0.9, 0)
	_render()
	return false


## Network-driven soldier: follow the received position and animate from its velocity.
func remote_update(dt: float, age: float, npos: Vector3, nvel: Vector3, nrot: Basis) -> void:
	var target := npos + nvel * minf(age, 0.3)
	pos = pos.lerp(target, 1.0 - exp(-12.0 * dt)) if pos.distance_to(target) < 20.0 else target
	vel = nvel
	speed = Vector2(vel.x, vel.z).length()
	heading = heading_of(-nrot.z)
	_animate_alive(dt)
