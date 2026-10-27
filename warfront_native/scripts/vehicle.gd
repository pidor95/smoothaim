extends Node3D
## One aircraft, helicopter or tank: state, controls, physics and model animation.
## Godot axes: X east, Y up, Z south. Models face -Z; a heading h points along (-sin h, 0, -cos h).

const D := preload("res://scripts/data.gd")
const G := D.G

var game: Node                 # game.gd, for the world, effects and kills
var world: Node3D
var type: String
var T: Dictionary
var cat: String
var team: String
var nick: String
var is_player := false
var is_bot := false
var remote := false
var peer := 0                  # network peer id for remote players

var pos := Vector3.ZERO
var vel := Vector3.ZERO
var rot := Basis.IDENTITY
var hp := 100.0
var dead := false
var respawn_t := 0.0
var ammo: Array[int] = []
var slot := 0
var cd := {}
var inp := {"throttle": 0.0, "aim": Vector3.FORWARD, "aim_point": Vector3.ZERO, "fire": false, "fire_pressed": false,
	"flare": false, "up": 0.0, "down": 0.0, "left": 0.0, "right": 0.0}
var lock_target = null
var lock_time := 0.0
var locked := false
var in_smoke := false
var last_hit_by = null
var zone_t := 0.0
var alt_side := false
var kills := 0

# plane
var man = null                 # active post-stall manoeuvre {type, t, side}
var maneuver := false          # thrust-vectoring mode switched on
var w := Vector3.ZERO          # body rates: pitch (up negative), yaw (left positive), roll (right positive)
var speed := 0.0
var aoa := 0.0
var gload := 1.0
var mach := 0.0
var stalled := false
var stall_t := 0.0             # seconds spent stalled; the autopilot recovers after a moment
var acc := Vector3.ZERO
var aim_dir := Vector3.FORWARD
var fixed_dir := Vector3.FORWARD
# heli / tank
var heading := 0.0
var yaw_rate := 0.0
var pitch_v := 0.0
var roll_v := 0.0
var vy := 0.0
var fspd := 0.0
var sp := 0.0
var spv := 0.0
var recoil := 0.0
var turret_yaw := 0.0
var gun_pitch := 0.0
var blocked := 0.0

# bot brain
var bot := {}

# shot down: the wreck keeps falling, burning and tumbling until it hits the ground
var wreck := false
var wreck_spin := Vector3.ZERO
var wreck_fx: Array = []

# model parts
var model: Node3D
var hull: Node3D               # tilts with the tank suspension
var turret: Node3D
var gun: Node3D
var rotor: Node3D
var tail_rotor: Node3D
var flames: Array = []
var muzzle: Sprite3D
var muzzle_t := 0.0


func setup(g: Node, t: String, tm: String, opts := {}) -> void:
	game = g
	world = g.world
	type = t
	T = D.TYPES[t]
	cat = T["cat"]
	team = tm
	nick = opts.get("name", T["name"])
	is_player = opts.get("player", false)
	is_bot = opts.get("bot", false)
	remote = opts.get("remote", false)
	peer = opts.get("peer", 0)
	_build_model()
	reset()


func _build_model() -> void:
	hull = Node3D.new()
	add_child(hull)
	model = load("res://assets/models/%s.glb" % T["model"]).instantiate()
	hull.add_child(model)
	if type == "pantsir":
		for mi in model.find_children("*", "MeshInstance3D", true, false):
			var m3 := mi as MeshInstance3D
			for i in m3.mesh.get_surface_count():
				var mat := m3.mesh.surface_get_material(i)
				if mat is BaseMaterial3D:
					mat = mat.duplicate()
					mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
					m3.set_surface_override_material(i, mat)
	turret = model.find_child("Turret", true, false)
	gun = model.find_child("Gun", true, false)
	rotor = model.find_child("Rotor", true, false)
	tail_rotor = model.find_child("TailRotor", true, false)
	for n in ["Nozzle_L", "Nozzle_R"]:
		var nz: Node3D = model.find_child(n, true, false)
		if nz:
			var f := Sprite3D.new()
			f.texture = preload("res://assets/fx/glow.png")
			f.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			f.modulate = Color(1.0, 0.55, 0.25)
			f.pixel_size = 0.012
			f.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			f.material_override = _additive(preload("res://assets/fx/glow.png"))
			nz.add_child(f)
			flames.append(f)
	muzzle = Sprite3D.new()
	muzzle.texture = preload("res://assets/fx/glow.png")
	muzzle.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	muzzle.material_override = _additive(preload("res://assets/fx/glow.png"))
	muzzle.modulate = Color(1, 0.8, 0.45)
	muzzle.visible = false
	muzzle.top_level = true
	muzzle.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(muzzle)
	# a softer shadow on the ground is enough for fast aircraft far away; tanks and helis cast real shadows
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).visibility_range_end = 7000.0 if cat != "tank" else 3500.0


static func _additive(tex: Texture2D) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.vertex_color_use_as_albedo = true
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.no_depth_test = false
	return m


func reset() -> void:
	hp = T["hp"]
	dead = false
	visible = true
	ammo.clear()
	for s in T["slots"]:
		ammo.append(int(s["a"]))
	slot = 0
	cd = {}
	man = null
	maneuver = false
	w = Vector3.ZERO
	vel = Vector3.ZERO
	lock_target = null
	lock_time = 0.0
	locked = false
	last_hit_by = null
	zone_t = 0.0
	fspd = 0.0
	sp = 0.0
	spv = 0.0
	recoil = 0.0
	vy = 0.0
	yaw_rate = 0.0
	pitch_v = 0.0
	roll_v = 0.0
	blocked = 0.0
	stalled = false
	stall_t = 0.0
	end_wreck()


func place(p: Vector3, h: float, spd: float) -> void:
	pos = p
	heading = h
	turret_yaw = h
	gun_pitch = 0.0
	rot = Basis(Vector3.UP, h)
	vel = dir_of(h) * spd
	speed = spd
	aim_dir = dir_of(h)
	fixed_dir = aim_dir
	inp["aim"] = aim_dir
	inp["aim_point"] = pos + aim_dir * 300.0
	if cat == "tank":
		rot = _terrain_basis()
	sync()


# ---------------------------------------------------------------- helpers
static func dir_of(h: float) -> Vector3:
	return Vector3(-sin(h), 0, -cos(h))


static func heading_of(d: Vector3) -> float:
	return atan2(-d.x, -d.z)


func fwd() -> Vector3:
	return -rot.z


## Local offset (right, up, forward) to world position.
func lw(right: float, up: float, forward: float) -> Vector3:
	return pos + rot * Vector3(right, up, -forward)


func slot_of(wname: String) -> int:
	for i in T["slots"].size():
		if T["slots"][i]["w"] == wname:
			return i
	return -1


func weapon() -> String:
	return T["slots"][slot]["w"]


func sync() -> void:
	global_transform = Transform3D(rot, pos)


# ---------------------------------------------------------------- physics
func physics(dt: float) -> void:
	match cat:
		"plane": _plane(dt)
		"heli": _heli(dt)
		_: _tank(dt)
	_animate(dt)


static func _cl(A: Dictionary, a: float) -> float:
	var x := absf(a)
	if x < A["a_st"]:
		return A["cla"] * a
	return signf(a) * maxf(maxf(A["cl_max"] * (1.0 - (x - A["a_st"]) * 1.4), 1.1 * sin(2.0 * x)), 0.0)


func start_maneuver(mtype: String, side := 1.0) -> bool:
	if not T.get("maneuver", false) or man != null or dead:
		return false
	if speed < 70.0:
		if is_player:
			game.flash("Мало скорости для манёвра", "org")
		return false
	man = {"type": mtype, "t": 0.0, "side": side}
	if is_player:
		game.flash(String(D.MANEUVERS[mtype]["n"]).to_upper() + "!", "grn")
	return true


## Flight model: lift/drag polars, thrust with altitude lapse, G-limited fly-by-wire and rotational inertia.
func _plane(dt: float) -> void:
	var A: Dictionary = D.AERO[type]
	var spd := vel.length()
	if spd < 1.0:
		vel = fwd()
		spd = 1.0
	var f := fwd()
	var u := rot.y
	var r := rot.x
	var alpha := atan2(-vel.dot(u), vel.dot(f))
	var beta := atan2(-vel.dot(r), vel.dot(f))       # positive = airflow from the left
	var rho := 1.225 * exp(-maxf(pos.y + 200.0, 0.0) / 8500.0)
	var qd := 0.5 * rho * spd * spd
	var W: float = A["m"] * G
	var tvc: bool = A["tvc"] and (maneuver or man != null)
	var wd := Vector3.ZERO
	var auth := 1.0
	if man != null:
		man["t"] += dt
		wd = D.maneuver_rate(man["type"], man["t"], man["side"])
		if man["t"] >= D.MANEUVERS[man["type"]]["dur"]:
			man = null
			if is_player:
				game.reset_camera_to(fwd())
	else:
		# instructor: roll the target above the canopy for large corrections, keep wings level for small ones, then pull
		var d: Vector3 = inp["aim"].normalized()
		# stall recovery: after a moment in a stall the autopilot points the nose along the fall to regain speed
		if stall_t > 0.8:
			var k := clampf((stall_t - 0.8) / 0.8, 0.0, 1.0)
			# dive to regain speed only with height to spare; close to the ground fly level out of it
			var alt: float = pos.y - world.surf_h(pos.x, pos.z)
			var dip := -0.25 if alt > 700.0 else (0.0 if alt > 300.0 else 0.15)
			d = d.lerp((Vector3(vel.x, 0, vel.z).normalized() * 0.9 + Vector3(0, dip, 0)).normalized(), k).normalized()
		var dl := Vector3(-d.dot(r), d.dot(u), d.dot(f))   # left, up, forward
		var off := acos(clampf(dl.z, -1.0, 1.0))
		var bank := atan2(-Vector3.UP.dot(r), Vector3.UP.dot(u))
		var phi: float
		if off > 0.35:
			phi = atan2(dl.x, dl.y)
		else:
			phi = (1.0 if dl.y >= 0.0 else -1.0) * atan2(dl.x, absf(dl.y) + 1e-4)
		var wg := smoothstep(0.02, 0.12, off)
		var roll_err := phi * wg + bank * (1.0 - wg)
		wd.z = clampf(-roll_err * 5.0, -A["rr"], A["rr"])
		var pe := atan2(dl.y, dl.z)
		if off > 0.35 and dl.y < 0.0:
			pe = maxf(pe, -0.1)
		var roll_ok := clampf(1.25 - absf(phi) / 1.1, 0.0, 1.0) if off > 0.35 else 1.0
		wd.x = -clampf(pe * 2.6 * roll_ok, -0.5, A["pr"])
		wd.y = clampf(atan2(dl.x, maxf(dl.z, 0.2)) * 1.4, -A["yr"], A["yr"]) + beta * 1.5
		auth = clampf(qd / 12000.0, 0.08, 1.0)
		if tvc:
			auth = maxf(auth, 0.9)
		# fly-by-wire limiter: AoA / G for pitch-up, and a push limit
		if wd.x < 0.0:
			var a_lim: float = 1.7 if tvc else minf(A["a_st"] * 0.95, (A["n"] * W / (qd * A["s"] + 1.0)) / A["cla"])
			var v_turn: float = qd * A["s"] * absf(_cl(A, alpha)) / (A["m"] * spd)
			wd.x = maxf(wd.x, -maxf(0.0, (a_lim - alpha) * 4.0 + v_turn))
		if wd.x > 0.0 and alpha < -0.18:
			wd.x = minf(wd.x, maxf(0.0, (alpha + 0.25) * 4.0))
		if is_bot:
			wd *= D.DIFF[game.settings["diff"]]["turn"]
	# weathervane stability: past the stall angle the airflow itself swings the nose back into the wind,
	# even when the controls have no authority left (this is what a falling plane does)
	var st := Vector3.ZERO
	if man == null:
		var a_ok: float = 1.25 if tvc and speed > 60.0 else A["a_st"]
		var ks := clampf(spd / 70.0, 0.35, 1.3)
		st.x = signf(alpha) * maxf(0.0, absf(alpha) - a_ok) * 2.4 * ks
		st.y = signf(beta) * maxf(0.0, absf(beta) - 0.15) * 2.0 * ks
	w.x += (wd.x * auth + st.x - w.x) * (1.0 - exp(-dt / 0.22))
	w.y += (wd.y * auth + st.y - w.y) * (1.0 - exp(-dt / 0.4))
	w.z += (wd.z * maxf(auth, 0.3) - w.z) * (1.0 - exp(-dt / 0.12))
	rot = (rot * Basis.from_euler(Vector3(-w.x * dt, w.y * dt, -w.z * dt))).orthonormalized()
	# forces: thrust along the nose, lift normal to the airflow, drag, side force, gravity
	f = fwd()
	u = rot.y
	var vd := vel / spd
	var cl := _cl(A, alpha)
	var L := clampf(qd * A["s"] * cl, -3.5 * W, (A["n"] + 1.5) * W)
	var ld := u - vd * u.dot(vd)
	if ld.length() > 1e-4:
		ld = ld.normalized()
	var M := spd / 340.0
	var sa := sin(minf(absf(alpha), 1.57))
	var cd_: float = A["cd0"] + A["k"] * cl * cl + 1.4 * sa * sa + 0.028 * smoothstep(0.88, 1.15, M) + 0.012 * maxf(0.0, M - 1.2)
	var thr: float = inp["throttle"]
	var thrust: float = (thr / 0.85 * A["mil"] if thr <= 0.85 else A["mil"] + (thr - 0.85) / 0.15 * (A["ab"] - A["mil"])) * pow(rho / 1.225, 0.7)
	var left := -rot.x
	acc = (f * thrust + ld * L - vd * qd * A["s"] * cd_ - left * qd * A["s"] * 0.9 * beta) / A["m"]
	acc.y -= G
	vel += acc * dt
	pos += vel * dt
	speed = vel.length()
	aoa = alpha
	gload = L / W
	mach = M
	stalled = man == null and absf(alpha) > (1.3 if tvc else A["a_st"] * 1.02) or (man == null and spd < 45.0)
	stall_t = stall_t + dt if stalled else maxf(0.0, stall_t - dt * 2.0)
	aim_dir = f
	var s := 3.4 + randf() * 1.2 if thr > 0.85 else 0.4 + thr * 1.2
	for fl in flames:
		fl.pixel_size = 0.004 * s
	if pos.y < world.surf_h(pos.x, pos.z) + 2.5:
		game.kill(self, null, "crash")


## Helicopter: the rotor disc tilts to accelerate, so the body pitches and banks with real inertia and sideslip.
func _heli(dt: float) -> void:
	var ty := heading_of(inp["aim"])
	yaw_rate += (clampf(angle_difference(heading, ty) * 2.0, -1.0, 1.0) - yaw_rate) * (1.0 - exp(-2.2 * dt))
	heading += yaw_rate * dt
	var f := dir_of(heading)
	var right := Vector3(-f.z, 0, f.x)
	var fw := vel.dot(f)
	var lt := vel.dot(right)
	var tgt: float = T["vmax"] * clampf(inp["throttle"], 0.0, 1.0)
	var a_f := clampf((tgt - fw) * 0.45, -4.5, 3.5)
	var a_l := clampf(-lt * 0.6, -3.5, 3.5)
	var d_f := 0.0035 * fw * absf(fw)
	var d_l := 0.02 * lt * absf(lt)
	pitch_v += (atan((a_f + d_f) / G) - pitch_v) * (1.0 - exp(-2.6 * dt))
	roll_v += (atan((a_l + d_l) / G) - roll_v) * (1.0 - exp(-2.6 * dt))
	fw += (G * tan(pitch_v) - d_f) * dt
	lt += (G * tan(roll_v) - d_l) * dt
	vy += clampf((inp["up"] - inp["down"]) * 12.0 - vy, -7.0 * dt, 7.0 * dt)
	vel = f * fw + right * lt + Vector3(0, vy, 0)
	pos += vel * dt
	var gh: float = world.surf_h(pos.x, pos.z) + 2.4
	if pos.y < gh:
		if vy < -9.0 or absf(fw) > 35.0:
			game.kill(self, null, "crash")
			return
		pos.y = gh
		vy = maxf(vy, 0.0)
		vel *= 0.9
	if pos.y > 1800.0:
		pos.y = 1800.0
		vy = minf(vy, 0.0)
	rot = Basis.from_euler(Vector3(-pitch_v, heading, -roll_v), EULER_ORDER_YXZ)
	speed = vel.length()
	var td: Vector3 = (inp["aim_point"] - pos).normalized()
	var p := clampf(asin(clampf(td.y, -1.0, 1.0)), -0.6, 0.2)
	fixed_dir = f * cos(p) + Vector3(0, sin(p), 0)
	if type == "ah64":
		var cp := chin_pos()
		var dir: Vector3 = (inp["aim_point"] - cp).normalized()
		var el := clampf(asin(clampf(dir.y, -1.0, 1.0)), -1.2, 0.35)
		var az := heading_of(dir)
		aim_dir = dir_of(az) * cos(el) + Vector3(0, sin(el), 0)
	else:
		aim_dir = fixed_dir


func chin_pos() -> Vector3:
	return lw(0, -1.7, 5.2)


func _terrain_basis() -> Basis:
	var n: Vector3 = world.normal(pos.x, pos.z)
	var f := dir_of(heading)
	f = (f - n * f.dot(n)).normalized()
	var z := -f
	var x := n.cross(z).normalized()
	return Basis(x, n, z)


## Tank: engine force against slope, sprung hull pitch, turret/gun drives, gun recoil.
func _tank(dt: float) -> void:
	heading += (inp["left"] - inp["right"]) * T.get("turn", 0.7) * dt * (1.0 - minf(absf(fspd) / 40.0, 0.4))
	var f := dir_of(heading)
	var grade: float = (world.height(pos.x + f.x * 3, pos.z + f.z * 3) - world.height(pos.x - f.x * 3, pos.z - f.z * 3)) / 6.0
	var thr: float = inp["throttle"]
	var tgt: float = thr * T["vmax"] if thr >= 0.0 else thr * T["vmax"] * 0.45
	var a := clampf(tgt - fspd, -7.0, 3.2) - G * grade * 0.55 - 0.15 * signf(fspd) * minf(absf(fspd), 1.0)
	var before := fspd
	fspd += a * dt
	if tgt == 0.0 and signf(before) != signf(fspd):
		fspd = 0.0
	var np := pos + f * fspd * dt
	var edge: float = world.HALF - 60.0
	if absf(np.x) > edge or absf(np.z) > edge or absf(grade) > 0.75 or world.building_hit(Vector3(np.x, world.height(np.x, np.z) + 1.0, np.z) + f * signf(fspd) * 4.0, 1.0):
		fspd *= 0.3
		blocked += dt
	else:
		pos = np
		blocked = 0.0
	pos.y = world.height(pos.x, pos.z)
	vel = f * fspd
	speed = absf(fspd)
	rot = Basis(Quaternion(rot).slerp(Quaternion(_terrain_basis()), 1.0 - exp(-6.0 * dt)))
	# suspension: hull squats when accelerating and dives when braking
	var ac := (fspd - before) / maxf(dt, 1e-3)
	spv += ((-ac * 0.012 - sp) * 55.0 - spv * 7.0) * dt
	sp += spv * dt
	hull.rotation.x = -clampf(sp, -0.12, 0.12)
	recoil = maxf(0.0, recoil - dt * 2.2)
	var piv := pos + Vector3(0, T.get("aim_h", 2.4), 0)
	var ad: Vector3 = (inp["aim_point"] - piv).normalized()
	var ty := heading_of(ad)
	var tr: float = T.get("turret_rate", 0.7) * dt
	turret_yaw += clampf(angle_difference(turret_yaw, ty), -tr, tr)
	var gp := clampf(asin(clampf(ad.y, -1.0, 1.0)), -0.17, T.get("pitch_max", 0.35))
	var pr: float = T.get("pitch_rate", 0.35) * dt
	gun_pitch += clampf(gp - gun_pitch, -pr, pr)
	if weapon() == "mg":
		aim_dir = (inp["aim_point"] - mg_pos()).normalized()
	else:
		aim_dir = dir_of(turret_yaw) * cos(gun_pitch) + Vector3(0, sin(gun_pitch), 0)


func mg_pos() -> Vector3:
	return lw(0.6, 3.0, -0.2)


func muzzle_pos() -> Vector3:
	if gun:
		return gun.global_position + aim_dir * T.get("muzzle", 6.0)
	return pos + Vector3(0, 2.0, 0) + aim_dir * 6.0


# ---------------------------------------------------------------- model animation
func _animate(dt: float) -> void:
	if rotor:
		rotor.rotate_y(dt * 14.0)
	if tail_rotor:
		tail_rotor.rotate_x(dt * 60.0)
	if cat == "tank" and turret:
		turret.rotation.y = angle_difference(heading, turret_yaw)
		if gun and type == "abrams":
			gun.rotation.x = gun_pitch
			gun.position.z = -1.64 + 0.5 * sin(minf(recoil, 1.0) * PI / 2.0)
	if muzzle.visible:
		muzzle_t -= dt
		if muzzle_t <= 0.0:
			muzzle.visible = false


func flash_muzzle(p: Vector3, s: float) -> void:
	muzzle.global_position = p
	muzzle.pixel_size = 0.006 * s * randf_range(0.8, 1.2)
	muzzle.visible = true
	muzzle_t = 0.05


## Turn a destroyed aircraft into a falling, burning wreck.
func start_wreck() -> void:
	wreck = true
	visible = true
	vel += Vector3(randf_range(-8, 8), randf_range(-2, 6), randf_range(-8, 8))
	if cat == "heli":
		wreck_spin = Vector3(randf_range(-0.4, 0.4), randf_range(2.5, 4.0) * (1 if randf() < 0.5 else -1), randf_range(-0.4, 0.4))
	else:
		wreck_spin = Vector3(randf_range(-1.0, 1.0), randf_range(-0.6, 0.6), randf_range(2.0, 4.0) * (1 if randf() < 0.5 else -1))
	wreck_fx = game.fx.burning(self)


func end_wreck() -> void:
	wreck = false
	for e in wreck_fx:
		game.fx.detach_trail(e)
	wreck_fx.clear()


## Returns true when the wreck hits the ground.
func wreck_update(dt: float) -> bool:
	vel.y -= G * dt
	vel *= 1.0 - (0.12 if cat == "plane" else 0.35) * dt
	pos += vel * dt
	rot = (rot * Basis.from_euler(wreck_spin * dt)).orthonormalized()
	if rotor:
		rotor.rotate_y(dt * 4.0)
	sync()
	return pos.y < world.surf_h(pos.x, pos.z) + 1.0


## Network-driven vehicle: smooth towards the last received state.
func remote_update(dt: float, age: float, npos: Vector3, nvel: Vector3, nrot: Basis) -> void:
	var target := npos + nvel * minf(age, 0.5)
	if pos.distance_to(target) > 200.0:
		pos = target
	else:
		pos = pos.lerp(target, 1.0 - exp(-12.0 * dt))
	rot = Basis(Quaternion(rot).slerp(Quaternion(nrot.orthonormalized()), 1.0 - exp(-12.0 * dt)))
	vel = nvel
	speed = vel.length()
	if cat == "tank":
		heading = heading_of(fwd())
	_animate(dt)
