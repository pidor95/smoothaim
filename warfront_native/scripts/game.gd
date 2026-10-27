extends Node3D
## Match logic: vehicles, weapons, projectiles, damage, bots, camera and the player's controls.

const D := preload("res://scripts/data.gd")
const Vehicle := preload("res://scripts/vehicle.gd")
const Soldier := preload("res://scripts/soldier.gd")
const Flare := preload("res://scripts/flare.gd")
const G := D.G
const ZONE := D.ZONE
const ZONE_KILL := D.ZONE_KILL
const CAMC := {"plane": [30.0, 7.0], "heli": [24.0, 6.0], "tank": [15.0, 5.5], "inf": [3.3, 0.35]}
# infantry fights around the Prokhorovka village; each side gathers on its own edge of it
const INF_SPAWN := {"blue": Vector2(2150, 250), "red": Vector2(2380, -680)}

signal player_died(attacker_name: String, weapon: String)

var world: Node3D
var fx: Node3D
var audio: Node
var net: Node
var cam: Camera3D
var settings := {}

var playing := false
var paused := false
var player = null
var vehicles: Array = []
var bullets: Array = []
var missiles: Array = []
var flares: Array = []
var smokes: Array = []
var killfeed: Array = []
var feed_log: Array = []
var hit_stats := {}              # body-part hits (for tests)         # every kill message of the match (for tests)
var kills := 0
var deaths := 0
var time := 0.0

# player controls, written by the HUD and the keyboard
var ctrl := {"thr": 0.7, "slot": 0, "fire": false, "fire_pressed": false, "flare": false, "a": false, "b": false, "man": false, "zoom": false}
var cam_yaw := 0.0
var cam_pitch := 0.0
var cam_fwd := Vector3.FORWARD
var cam_shake := 0.0
var recoil_p := 0.0
var cam_sm := Vector3.ZERO
var cam_sm_init := false
var menu_t := 0.0

# HUD feedback
var flash_txt := ""
var flash_cls := "grn"
var flash_t := 0.0
var hit_t := 0.0
var dmg_t := 0.0
var lock_warn_t := 0.0
var beep_t := 0.0
var warn_beep_t := 0.0

var _msl_mesh: CylinderMesh
var _msl_mat: StandardMaterial3D


func setup(w: Node3D, f: Node3D, a: Node, c: Camera3D, n: Node, s: Dictionary) -> void:
	world = w
	fx = f
	audio = a
	cam = c
	net = n
	settings = s
	_msl_mesh = CylinderMesh.new()
	_msl_mesh.top_radius = 0.1
	_msl_mesh.bottom_radius = 0.1
	_msl_mesh.height = 3.0
	_msl_mesh.radial_segments = 8
	_msl_mat = StandardMaterial3D.new()
	_msl_mat.albedo_color = Color(0.85, 0.86, 0.84)
	_msl_mat.roughness = 0.5


# ---------------------------------------------------------------- match flow
func clear() -> void:
	for v in vehicles:
		v.queue_free()
	vehicles.clear()
	for m in missiles:
		m["node"].queue_free()
	for f in flares:
		f.queue_free()
	missiles.clear()
	bullets.clear()
	flares.clear()
	smokes.clear()
	killfeed.clear()
	feed_log.clear()
	player = null
	kills = 0
	deaths = 0
	fx.draw_tracers([], Vector3.ZERO)


func start(vehicle_type: String, online: bool) -> void:
	clear()
	player = _new_vehicle(vehicle_type, "blue", {"player": true, "name": settings.get("nick", "") if online and settings.get("nick", "") != "" else ("Игрок" if online else "Вы")})
	respawn_player(vehicle_type)
	if not online:
		var list: Array[String] = []
		for i in int(settings["bp"]):
			list.append("mig29" if i % 2 else "su57")
		for i in int(settings["bh"]):
			list.append("mi24" if i % 2 else "ah64")
		for i in int(settings["bt"]):
			list.append("pantsir" if i % 2 else "abrams")
		for i in int(settings.get("bi", 6)):
			list.append("soldier")
		for t in list:
			var b = _new_vehicle(t, "red", {"bot": true, "name": "Бот " + D.TYPES[t]["name"]})
			spawn(b)
		for i in int(settings.get("ba", 3)):
			spawn(_new_vehicle("soldier", "blue", {"bot": true, "name": "Союзник"}))
	playing = true
	paused = false


func _make(t: String):
	return Soldier.new() if D.TYPES[t]["cat"] == "inf" else Vehicle.new()


func _new_vehicle(t: String, team: String, opts: Dictionary):
	var v = _make(t)
	add_child(v)
	v.setup(self, t, team, opts)
	vehicles.append(v)
	return v


func respawn_player(t: String) -> void:
	if t != player.type:
		var nick: String = player.nick
		var idx := vehicles.find(player)
		player.queue_free()
		var v = _make(t)
		add_child(v)
		v.setup(self, t, "blue", {"player": true, "name": nick})
		vehicles[idx] = v
		player = v
	spawn(player)
	var cat: String = player.cat
	ctrl["thr"] = 0.7 if cat == "plane" else 0.5 if cat == "tank" else 0.0
	ctrl["slot"] = 0
	ctrl["man"] = false
	ctrl["zoom"] = false
	ctrl["flare"] = false
	cam_yaw = player.heading
	cam_pitch = 0.0 if cat == "plane" or cat == "inf" else -0.12
	cam_sm_init = false


func spawn_point(cat: String, team: String) -> Array:
	var s := 1.0 if team == "blue" else -1.0
	var online: bool = net != null and net.active
	if cat == "inf":
		var c: Vector2 = INF_SPAWN["blue" if team == "blue" else "red"]
		for k in 60:
			var a := randf() * TAU
			var r := randf_range(0, 90.0 + k * 6.0)
			var q := c + Vector2(cos(a), sin(a)) * r
			var gy: float = world.height(q.x, q.y)
			if world.building_hit(Vector3(q.x, gy + 1.0, q.y), 1.0):
				continue
			var tgt: Vector2 = INF_SPAWN["red" if team == "blue" else "blue"]
			return [Vector3(q.x, gy, q.y), Vehicle.heading_of(Vector3(tgt.x - q.x, 0, tgt.y - q.y))]
		return [Vector3(c.x, world.height(c.x, c.y), c.y), 0.0]
	for k in 40:
		var x: float
		var z: float
		if online:
			var a := randf() * TAU
			var r := 3600.0 if cat == "plane" else 2400.0 if cat == "heli" else 1600.0
			x = cos(a) * r
			z = sin(a) * r
		else:
			x = randf_range(-1500, 1500) if team == "red" else randf_range(-300, 300) * (1 + k * 0.3)
			z = s * (4200.0 if cat == "plane" else 2800.0 if cat == "heli" else 2200.0) + randf_range(-300, 300)
		var g: float = world.height(x, z)
		if cat == "tank" and (world.building_hit(Vector3(x, g + 1, z), 6.0) or world.normal(x, z).y < 0.93):
			continue
		var h: float = Vehicle.heading_of(Vector3(-x, 0, -z)) if online else (0.0 if team == "blue" else PI)
		var y := 900.0 + randf_range(0, 300) if cat == "plane" else g + (30.0 if team == "blue" else 80.0) if cat == "heli" else g
		return [Vector3(x, y, z), h]
	return [Vector3(0, 900, s * 4000), 0.0 if team == "blue" else PI]


func spawn(v) -> void:
	var sp := spawn_point(v.cat, v.team)
	v.reset()
	v.place(sp[0], sp[1], 200.0 if v.cat == "plane" else 0.0)
	v.inp["throttle"] = 0.7 if v.cat == "plane" else 0.0
	v.bot = {"think": 0.0, "tgt": null, "last_t": null, "seen_t": 0.0, "gun_t": 0.0, "flare_t": 0.0, "msl_t": randf_range(5, 15), "rkt_t": 5.0,
		"break_t": 0.0, "break_dir": Vector3.ZERO, "aim_err": Vector3.ZERO, "circ": 1.0 if randf() < 0.5 else -1.0, "burst": 0, "wp": null, "wp_t": 0.0,
		"stop_t": 0.0, "wander": sp[1]}


# ---------------------------------------------------------------- main loop
func _process(delta: float) -> void:
	var dt := minf(delta, 0.05)
	if not playing:
		menu_t += dt
		cam.global_position = Vector3(sin(menu_t * 0.04) * 2600.0 + 1200.0, 420.0, cos(menu_t * 0.04) * 2600.0)
		cam.look_at(Vector3(1600, 60, -300), Vector3.UP)
		cam.fov = 60.0
		return
	if paused:
		return
	time += dt
	if not player.dead:
		_player_input(dt)
	else:
		player.inp["fire"] = false
	_update_smokes(dt)
	for v in vehicles:
		if v.wreck and v.wreck_update(dt):
			v.end_wreck()
			v.visible = false
			explosion(v.pos, 2.2)
			fx.wreck(v.pos + Vector3(0, 2, 0))
		if v.remote:
			continue
		if v.dead:
			if v.is_bot:
				v.respawn_t -= dt
				if v.respawn_t <= 0.0:
					spawn(v)
			continue
		if v.is_bot:
			if v.cat == "inf":
				_bot_inf(v, dt)
			else:
				_bot_think(v, dt)
		v.physics(dt)
		if v.dead:
			continue
		_handle_weapons(v, dt)
		if v.cat == "tank" and v.speed > 2.5:
			_run_over(v)
		if v.cat != "tank" and v.cat != "inf" and world.building_hit(v.pos, 2.0):
			kill(v, null, "crash")
			continue
		var r := Vector2(v.pos.x, v.pos.z).length()
		if v.is_player:
			if r > ZONE:
				v.zone_t += dt
				if v.zone_t > 8.0 or r > ZONE_KILL:
					kill(v, null, "zone")
			else:
				v.zone_t = 0.0
		elif v.is_bot and r > ZONE_KILL + 2000.0:
			kill(v, null, "zone")
		v.sync()
	if net and net.active:
		net.tick(dt)
	ctrl["fire_pressed"] = false
	_update_bullets(dt)
	_update_missiles(dt)
	_update_flares(dt)
	_update_camera(dt)
	_update_feedback(dt)
	fx.draw_tracers(bullets, cam.global_position)


# ---------------------------------------------------------------- player input and camera
func look(dx: float, dy: float) -> void:
	var s: float = float(settings["sens"]) * 0.0009 * (0.35 if ctrl["zoom"] else 1.0)
	cam_yaw -= dx * s
	cam_pitch = clampf(cam_pitch - dy * s, -1.45, 1.45)


func reset_camera_to(f: Vector3) -> void:
	cam_yaw = Vehicle.heading_of(f)
	cam_pitch = clampf(asin(clampf(f.y, -1.0, 1.0)), -1.4, 1.4)
	if player:
		player.inp["aim"] = f


func maneuver(mtype: String) -> void:
	if player == null or player.dead:
		return
	var side := 1.0 if angle_difference(Vehicle.heading_of(player.fwd()), cam_yaw) >= 0.0 else -1.0
	if player.start_maneuver(mtype, side):
		audio.play3d("smoke", player.pos, -6.0, 60.0, 1.6)


## A moving tank crushes enemy soldiers in its way.
func _run_over(t) -> void:
	for v in vehicles:
		if v.cat == "inf" and not v.dead and can_hit(t, v) and v.pos.distance_to(t.pos) < 3.2:
			v.hit_part = "torso"
			v.last_impulse = t.vel * 1.5 + Vector3(0, 2, 0)
			fx.blood(v.centre(), t.vel.normalized(), 2.0)
			kill(v, t, "crash")


func _keys(dt: float) -> void:
	if player and player.cat == "inf":
		if Input.is_key_pressed(KEY_LEFT):
			look(-500.0 * dt, 0)
		if Input.is_key_pressed(KEY_RIGHT):
			look(500.0 * dt, 0)
		return
	if Input.is_key_pressed(KEY_W):
		ctrl["thr"] = clampf(ctrl["thr"] + dt * 0.5, 0.0, 1.0)
	if Input.is_key_pressed(KEY_S):
		ctrl["thr"] = clampf(ctrl["thr"] - dt * 0.5, 0.0, 1.0)
	if Input.is_key_pressed(KEY_LEFT):
		look(-500.0 * dt, 0)
	if Input.is_key_pressed(KEY_RIGHT):
		look(500.0 * dt, 0)
	if Input.is_key_pressed(KEY_UP):
		look(0, -400.0 * dt)
	if Input.is_key_pressed(KEY_DOWN):
		look(0, 400.0 * dt)


func _unhandled_key_input(e: InputEvent) -> void:
	if not playing or player == null:
		return
	var k := e as InputEventKey
	if k.echo:
		return
	if k.keycode == KEY_SPACE:
		if k.pressed and not ctrl["fire"]:
			ctrl["fire_pressed"] = true
		ctrl["fire"] = k.pressed
	elif k.keycode == KEY_X:
		ctrl["flare"] = k.pressed
	elif k.pressed:
		var n := k.keycode - KEY_1
		if n >= 0 and n < player.T["slots"].size():
			select_slot(n)
		match k.keycode:
			KEY_R:
				if player.cat == "inf":
					player.start_reload()
			KEY_M:
				if player.T.get("maneuver", false):
					ctrl["man"] = not ctrl["man"]
			KEY_Z:
				ctrl["zoom"] = not ctrl["zoom"]
			KEY_C:
				maneuver("cobra")
			KEY_V:
				maneuver("kulbit")
			KEY_B:
				maneuver("flat")


func select_slot(i: int) -> void:
	ctrl["slot"] = i
	audio.tone("click", -10.0)


func _player_input(dt: float) -> void:
	var p = player
	var inp: Dictionary = p.inp
	_keys(dt)
	inp["aim"] = cam_fwd
	if p.cat == "inf":
		var mv: Vector2 = ctrl.get("move", Vector2.ZERO)
		var kv := Vector2(float(Input.is_key_pressed(KEY_D)) - float(Input.is_key_pressed(KEY_A)), float(Input.is_key_pressed(KEY_W)) - float(Input.is_key_pressed(KEY_S)))
		if kv.length() > 0.0:
			mv = kv.normalized() * (1.0 if Input.is_key_pressed(KEY_SHIFT) else 0.9)
		inp["move"] = mv
		if ctrl.get("reload", false):
			ctrl["reload"] = false
			p.start_reload()
	var a: bool = ctrl["a"] or Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_R)
	var b: bool = ctrl["b"] or Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_F)
	if p.cat == "tank":
		var t: float = ctrl["thr"] * 2.0 - 1.0
		if absf(t) < 0.08:
			t = 0.0
		inp["throttle"] = t
		inp["left"] = 1.0 if a else 0.0
		inp["right"] = 1.0 if b else 0.0
		inp["up"] = 0.0
		inp["down"] = 0.0
	else:
		inp["throttle"] = ctrl["thr"]
		inp["up"] = 1.0 if a else 0.0
		inp["down"] = 1.0 if b else 0.0
		inp["left"] = 0.0
		inp["right"] = 0.0
	inp["fire"] = ctrl["fire"]
	inp["fire_pressed"] = ctrl["fire_pressed"]
	inp["flare"] = ctrl["flare"]
	p.slot = ctrl["slot"]
	p.maneuver = ctrl["man"]
	inp["aim_point"] = _aim_point()


## Where the crosshair ray meets a vehicle or the ground.
func _aim_point() -> Vector3:
	var o := cam.global_position
	var d := cam_fwd
	var best := 3000.0
	for v in vehicles:
		if v == player or v.dead:
			continue
		var inf: bool = v.cat == "inf"
		var to: Vector3 = (v.pos + Vector3(0, 1.0, 0) if inf else v.pos) - o
		var al := to.dot(d)
		if al < 0.0 or al > best:
			continue
		if to.length_squared() - al * al < (0.8 if inf else pow(v.T["r"] * 1.3, 2)):
			best = al
	var t := 2.0 if player and player.cat == "inf" else 8.0
	while t < best:
		var step := 12.0 + t * 0.03
		var q := o + d * t
		if q.y < world.surf_h(q.x, q.z):
			var lo := t - step
			var hi := t
			for i in 7:
				var m := (lo + hi) / 2.0
				var qm := o + d * m
				if qm.y < world.surf_h(qm.x, qm.z):
					hi = m
				else:
					lo = m
			best = hi
			break
		t += step
	return o + d * best


func _update_camera(dt: float) -> void:
	recoil_p *= exp(-7.0 * dt)
	var cp := clampf(cam_pitch + recoil_p, -1.45, 1.45)
	cam_fwd = Vector3(-sin(cam_yaw) * cos(cp), sin(cp), -cos(cam_yaw) * cos(cp))
	cam_shake *= exp(-4.0 * dt)
	var sk := cam_shake * cam_shake * 0.02
	cam.rotation = Vector3(cp + randf_range(-1, 1) * sk, cam_yaw + randf_range(-1, 1) * sk, randf_range(-1, 1) * sk * 0.5)
	var fov := (38.0 if player and player.cat == "inf" else 24.0) if ctrl["zoom"] else 65.0
	if player and player.cat == "plane" and not ctrl["zoom"]:
		fov += clampf((player.speed - 200.0) / 45.0, 0.0, 8.0)
	cam.fov = lerpf(cam.fov, fov, 1.0 - exp(-6.0 * dt))
	if player == null or (player.dead and not player.wreck):
		return
	var c: Array = CAMC[player.cat]
	var dist: float = c[0] * (0.7 if ctrl["zoom"] else 1.0) * (1.6 if player.dead else 1.0)
	var up := cam.global_transform.basis.y
	var ideal: Vector3 = player.pos - cam_fwd * dist + up * c[1]
	if player.cat == "inf":
		# over the right shoulder
		var right := cam.global_transform.basis.x
		var pivot: Vector3 = player.pos + Vector3(0, 1.55, 0) + right * (0.45 if ctrl["zoom"] else 0.6)
		if player.dead:
			pivot = player.pos + Vector3(0, 1.2, 0)
		ideal = pivot - cam_fwd * (1.4 if ctrl["zoom"] else dist) + up * (0.05 if ctrl["zoom"] else c[1])
		ideal.y = maxf(ideal.y, world.height(ideal.x, ideal.z) + 0.4)
		cam.global_position = ideal
		return
	if player.cat == "plane" and not player.dead:
		ideal -= player.acc * 0.012
		if player.gload > 5.0:
			cam_shake = maxf(cam_shake, (player.gload - 5.0) * 0.08)
	else:
		var off: Vector3 = ideal - player.pos
		if not cam_sm_init:
			cam_sm = off
			cam_sm_init = true
		cam_sm = cam_sm.lerp(off, 1.0 - exp(-9.0 * dt))
		ideal = player.pos + cam_sm
	var gh: float = world.surf_h(ideal.x, ideal.z) + 1.5
	ideal.y = maxf(ideal.y, gh)
	cam.global_position = ideal


func flash(t: String, cls := "grn") -> void:
	flash_txt = t
	flash_cls = cls
	flash_t = 2.2


func _update_feedback(dt: float) -> void:
	flash_t -= dt
	hit_t -= dt
	dmg_t -= dt
	lock_warn_t -= dt
	for k in killfeed:
		k["t"] -= dt
	while killfeed.size() > 0 and killfeed[0]["t"] <= 0.0:
		killfeed.pop_front()
	var p = player
	var W: Dictionary = D.WEAP[p.weapon()]
	audio.set_lock(W.get("homing", false) and p.locked and not p.dead)
	if W.get("homing", false) and p.lock_target != null and not p.locked and not p.dead:
		beep_t -= dt
		if beep_t <= 0.0:
			beep_t = 0.22
			audio.tone("beep", -8.0)
	var near := missile_threat(p)
	if near >= 0.0 and not p.dead:
		warn_beep_t -= dt
		if warn_beep_t <= 0.0:
			warn_beep_t = clampf(near / 4000.0, 0.08, 0.5)
			audio.tone("warn", -10.0, 1.05 if near < 1500.0 else 0.85)
	if p.dead:
		audio.set_engine("", 0, 1)
	elif p.cat == "plane":
		audio.set_engine("jet", 0.25 + ctrl["thr"] * 0.35, 0.8 + ctrl["thr"] * 0.5)
	elif p.cat == "heli":
		audio.set_engine("heli", 0.45, 1.0)
	else:
		audio.set_engine("tank", 0.3 + absf(p.fspd) / p.T["vmax"] * 0.25, 0.85 + absf(p.fspd) * 0.02)


## Distance to the closest missile chasing v, or -1.
func missile_threat(v) -> float:
	var near := -1.0
	for m in missiles:
		if m["target"] == v:
			var d: float = m["p"].distance_to(v.pos)
			if near < 0.0 or d < near:
				near = d
	return near


func being_locked(v) -> bool:
	if lock_warn_t > 0.0 and v == player:
		return true
	for o in vehicles:
		if o.lock_target == v and o.lock_time > 0.3:
			return true
	return false


# ---------------------------------------------------------------- weapons
func has_los(a: Vector3, b: Vector3) -> bool:
	var n := clampi(int(a.distance_to(b) / 25.0), 8, 40)
	for i in range(1, n):
		var q := a.lerp(b, float(i) / n)
		if q.y < world.height(q.x, q.z) - 1.0 or world.building_hit(q):
			return false
	for c in smokes:
		if _seg_dist2(a, b, c["p"]) < c["r"] * c["r"] * 0.6 and a.distance_to(c["p"]) > c["r"] and b.distance_to(c["p"]) > c["r"]:
			return false
	return true


static func _seg_dist2(a: Vector3, b: Vector3, c: Vector3) -> float:
	var d := b - a
	var l2 := d.length_squared()
	var t := clampf((c - a).dot(d) / l2, 0.0, 1.0) if l2 > 0.0 else 0.0
	return (a + d * t).distance_squared_to(c)


func can_hit(owner, v) -> bool:
	return owner == null or (owner != v and owner.team != v.team)


func _find_lock(v, dir: Vector3, W: Dictionary):
	var best = null
	var ba: float = W["cone"]
	for o in vehicles:
		if o == v or o.dead or o.team == v.team or o.in_smoke or o.cat == "inf" or (W.get("air_only", false) and o.cat == "tank"):
			continue
		var to: Vector3 = o.pos - v.pos
		var d := to.length()
		if d > W["range"] or d < 40.0:
			continue
		var a := dir.angle_to(to)
		if a < ba and has_los(v.pos, o.pos):
			best = o
			ba = a
	return best


func _update_lock(v, wname: String, dt: float) -> void:
	var W: Dictionary = D.WEAP[wname]
	var dir: Vector3
	if v.is_player:
		dir = v.inp["aim"]
	elif v.cat == "plane":
		dir = v.fwd()
	elif v.cat == "tank" or v.cat == "inf":
		dir = v.aim_dir
	else:
		dir = Vehicle.dir_of(v.heading).lerp(v.inp["aim"], 0.5).normalized()
	var c = _find_lock(v, dir, W)
	if c != null and c == v.lock_target:
		v.lock_time += dt
	else:
		v.lock_target = c
		v.lock_time = 0.0
	v.locked = c != null and v.lock_time >= W["lock_t"] * (D.DIFF[settings["diff"]]["lock"] if v.is_bot else 1.0)
	if v.is_player and c != null and c.remote and net and net.active:
		v.bot["lock_send"] = v.bot.get("lock_send", 0.0) - dt
		if v.bot["lock_send"] <= 0.0:
			v.bot["lock_send"] = 0.5
			net.event({"t": "l", "tid": c.peer})


func infinite_ammo(v) -> bool:
	return v.is_player and settings["ammo"] and not (net and net.active)


func _handle_weapons(v, dt: float) -> void:
	for k in v.cd:
		if v.cd[k] > 0.0:
			v.cd[k] -= dt
	var wname: String = v.weapon()
	var W: Dictionary = D.WEAP[wname]
	if v.is_player:
		if W.get("homing", false):
			_update_lock(v, wname, dt)
		else:
			v.lock_target = null
			v.lock_time = 0.0
			v.locked = false
	elif v.is_bot:
		for s in v.T["slots"]:
			if D.WEAP[s["w"]].get("homing", false):
				_update_lock(v, s["w"], dt)
				break
	if v.inp["flare"]:
		var fi: int = v.slot_of("flare")
		if fi >= 0 and v.cd.get("flare", 0.0) <= 0.0 and (v.ammo[fi] > 0 or infinite_ammo(v)):
			if not infinite_ammo(v):
				v.ammo[fi] -= 1
			v.cd["flare"] = 1.0 / D.WEAP["flare"]["rate"]
			_fire(v, "flare")
	if not v.inp["fire"] and not v.inp["fire_pressed"]:
		return
	if v.cd.get(wname, 0.0) > 0.0:
		return
	if not W["auto"] and not v.inp["fire_pressed"]:
		return
	if v.ammo[v.slot] <= 0 and not infinite_ammo(v):
		if v.is_player and v.inp["fire_pressed"]:
			audio.tone("click", -6.0, 0.5)
		return
	if W.has("mag") and not infinite_ammo(v):
		# magazine weapons: no shooting while reloading, reload automatically when empty
		if v.reload_t > 0.0 or v.sprinting:
			return
		if v.mag[v.slot] <= 0:
			v.start_reload()
			return
		v.mag[v.slot] -= 1
	if not infinite_ammo(v):
		v.ammo[v.slot] -= 1
	v.cd[wname] = 1.0 / W["rate"]
	_fire(v, wname)


func _fire(v, wname: String) -> void:
	var W: Dictionary = D.WEAP[wname]
	var pl: bool = v.is_player
	match wname:
		"gun":
			var mp: Vector3 = v.lw(-0.9, 0.35, 7.0)
			_bullet(v, mp, v.aim_dir, W, v.vel, wname)
			v.flash_muzzle(mp, 1.0)
			v.alt_side = not v.alt_side
			if v.alt_side:
				audio.play3d("gun", mp, -4.0 if pl else -8.0, 60.0)
		"gun360":
			var mp: Vector3 = v.chin_pos() + v.aim_dir * 2.0
			_bullet(v, mp, v.aim_dir, W, v.vel, wname)
			v.flash_muzzle(mp, 1.2)
			audio.play3d("gun", mp, -5.0 if pl else -9.0, 60.0, 0.7)
		"sidegun":
			v.alt_side = not v.alt_side
			var mp: Vector3 = v.lw(1.45 if v.alt_side else -1.45, -0.75, 3.6)
			_bullet(v, mp, v.aim_dir, W, v.vel, wname)
			v.flash_muzzle(mp, 1.0)
			if v.alt_side:
				audio.play3d("gun", mp, -5.0 if pl else -9.0, 60.0, 0.85)
		"mg":
			var mp: Vector3 = v.mg_pos()
			_bullet(v, mp, v.aim_dir, W, Vector3.ZERO, wname)
			v.flash_muzzle(mp, 0.6)
			v.alt_side = not v.alt_side
			if v.alt_side:
				audio.play3d("mg", mp, -6.0 if pl else -10.0, 40.0)
		"cannon":
			v.recoil = 1.0
			v.spv -= 1.3
			if pl:
				cam_shake = maxf(cam_shake, 0.9)
			var mp: Vector3 = v.muzzle_pos()
			_bullet(v, mp, v.aim_dir, W, Vector3.ZERO, wname)
			v.flash_muzzle(mp, 4.0)
			fx.impact(mp + v.aim_dir * 2.0, true)
			audio.play3d("cannon", mp, 2.0 if pl else -2.0, 120.0)
			if pl and net and net.active:
				net.event({"t": "c", "p": mp, "d": v.aim_dir})
		"rkt":
			v.alt_side = not v.alt_side
			var mp: Vector3 = v.lw(2.3 if v.alt_side else -2.3, -0.5, 1.4)
			var d: Vector3 = (v.fixed_dir + Vector3(randf_range(-0.01, 0.01), randf_range(-0.01, 0.01), randf_range(-0.01, 0.01))).normalized()
			spawn_rocket(v, mp, d)
			if pl and net and net.active:
				net.event({"t": "r", "p": mp, "d": d})
		"aam", "atgm":
			v.alt_side = not v.alt_side
			var mp: Vector3 = v.lw(3.4 if v.alt_side else -3.4, -0.6, -1.0) if v.cat == "plane" else v.lw(2.45 if v.alt_side else -2.45, -0.5, 0.6)
			var tg = v.lock_target if v.locked else null
			var d: Vector3
			if v.cat == "plane":
				d = v.fwd()
			elif tg != null:
				d = (tg.pos - mp).normalized()
			else:
				d = v.inp["aim"] if v.is_player else v.fixed_dir
			spawn_missile(v, mp, d, wname, tg)
			if pl and net and net.active:
				net.event({"t": "m", "w": wname, "p": mp, "d": d, "tid": tg.peer if tg != null and tg.remote else (-1 if tg == null else 0)})
			if v.is_bot:
				v.lock_time = 0.0
		"aa30":
			# twin 30 mm guns on both sides of the turret
			v.alt_side = not v.alt_side
			var side := Vector3(-v.aim_dir.z, 0, v.aim_dir.x).normalized() * (1.0 if v.alt_side else -1.0)
			var mp: Vector3 = v.muzzle_pos() + side
			_bullet(v, mp, v.aim_dir, W, Vector3.ZERO, wname)
			v.flash_muzzle(mp, 1.6)
			if v.alt_side:
				audio.play3d("gun", mp, -3.0 if pl else -7.0, 70.0, 0.6)
		"sam":
			v.alt_side = not v.alt_side
			var side := Vector3(-v.aim_dir.z, 0, v.aim_dir.x).normalized() * (1.3 if v.alt_side else -1.3)
			var mp: Vector3 = v.pos + Vector3(0, 3.8, 0) + side
			var tg = v.lock_target if v.locked else null
			var d: Vector3 = ((tg.pos - mp).normalized() if tg != null else v.aim_dir) + Vector3(0, 0.35, 0)
			d = d.normalized()
			spawn_missile(v, mp, d, wname, tg)
			if pl and net and net.active:
				net.event({"t": "m", "w": wname, "p": mp, "d": d, "tid": tg.peer if tg != null and tg.remote else (-1 if tg == null else 0)})
			if v.is_bot:
				v.lock_time = 0.0
		"ak", "shotgun":
			var mp: Vector3 = v.muzzle_world
			var target: Vector3 = v.inp["aim_point"]
			var d: Vector3 = (target - mp).normalized() if target.distance_to(mp) > 3.0 else v.aim_dir
			# moving and hip fire spread; bots also miss by their skill
			var sp: float = W["spread"] * (1.0 + v.speed * 0.35) * (0.45 if pl and ctrl["zoom"] else 1.0)
			for i in int(W.get("pellets", 1)):
				_bullet(v, mp, d, W, Vector3.ZERO, wname, sp)
			v.flash_muzzle(mp, 1.4 if wname == "shotgun" else 1.0)
			audio.play3d(wname, mp, -2.0 if pl else -6.0, 30.0)
			if pl:
				# muzzle climb that recovers by itself
				var kick := 0.045 if wname == "shotgun" else 0.012
				recoil_p = minf(recoil_p + kick, 0.12)
				cam_yaw += randf_range(-0.3, 0.3) * kick
				cam_shake = maxf(cam_shake, 0.25 if wname == "shotgun" else 0.08)
			if pl and net and net.active:
				pass
		"stinger":
			var mp: Vector3 = v.muzzle_world
			var tg = v.lock_target if v.locked else null
			var d: Vector3 = ((tg.pos - mp).normalized() if tg != null else v.aim_dir)
			spawn_missile(v, mp, d, wname, tg)
			fx.impact(mp - d * 1.8, true)
			if pl and net and net.active:
				net.event({"t": "m", "w": wname, "p": mp, "d": d, "tid": tg.peer if tg != null and tg.remote else (-1 if tg == null else 0)})
			if v.is_bot:
				v.lock_time = 0.0
		"flare":
			drop_flares(v)
			if pl and net and net.active:
				net.event({"t": "fl"})
		"smoke":
			var p: Vector3 = deploy_smoke(v)
			if pl and net and net.active:
				net.event({"t": "sm", "p": p})


func _bullet(owner, p: Vector3, dir: Vector3, W: Dictionary, inherit: Vector3, wname: String, spread := -1.0) -> void:
	var d := dir
	var s: float = W.get("spread", 0.0) if spread < 0.0 else spread
	if s > 0.0:
		d = (d + Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * s).normalized()
	bullets.append({"p": p, "prev": p, "v": d * W["spd"] + inherit, "life": W["life"], "W": W, "w": wname, "owner": owner, "col": W["col"], "len": W["len"]})


func _missile_node(rocket: bool) -> Node3D:
	var n := Node3D.new()
	add_child(n)
	var mi := MeshInstance3D.new()
	mi.mesh = _msl_mesh
	mi.material_override = _msl_mat
	mi.rotation.x = PI / 2.0
	if rocket:
		mi.scale = Vector3(0.8, 0.6, 0.8)
	n.add_child(mi)
	return n


func spawn_rocket(owner, p: Vector3, d: Vector3) -> void:
	var W: Dictionary = D.WEAP["rkt"]
	var n := _missile_node(true)
	var m := {"p": p, "prev": p, "d": d, "vel": owner.vel + d * W["launch"], "t": 0.0, "W": W, "w": "rkt", "owner": owner, "target": null,
		"life": W["life"], "node": n, "seen": {}, "rocket": true}
	n.global_position = p
	m["trail"] = fx.trail(n, true)
	missiles.append(m)
	audio.play3d("rocket", p, -4.0, 60.0)


func spawn_missile(owner, p: Vector3, d: Vector3, wname: String, target) -> void:
	var W: Dictionary = D.WEAP[wname]
	var n := _missile_node(false)
	var m := {"p": p, "prev": p, "d": d, "vel": owner.vel + d * W["launch"], "t": 0.0, "W": W, "w": wname, "owner": owner, "target": target,
		"life": W["life"], "node": n, "seen": {}, "rocket": false}
	n.global_position = p
	m["trail"] = fx.trail(n, false)
	missiles.append(m)
	audio.play3d("missile", p, -2.0, 80.0)


func drop_flares(v) -> void:
	var f: Vector3 = v.fwd()
	for i in 2:
		var vel: Vector3 = v.vel * 0.55 + Vector3(randf_range(-16, 16), randf_range(-12, 4), randf_range(-16, 16)) - f * 14.0
		var n = fx.flare_node()
		n.global_position = v.pos
		n.p = v.pos
		n.v = vel
		n.owner_v = v
		flares.append(n)
	audio.play3d("flare", v.pos, -6.0, 50.0)


func deploy_smoke(v, at = null) -> Vector3:
	var p: Vector3
	if at != null:
		p = at
	else:
		p = v.pos + v.fwd() * 4.0 + Vector3(0, 3, 0)
	smokes.append({"p": p, "r": 28.0, "t": 18.0})
	fx.smoke_screen(p, 28.0)
	audio.play3d("smoke", p, -2.0, 60.0)
	return p


# ---------------------------------------------------------------- network players
func add_remote(t: String, id: int, nick: String):
	return _new_vehicle(t, "p%d" % id, {"remote": true, "peer": id, "name": nick})


## Automatic guns of a remote player, simulated here so their bullets can hit us.
func remote_fire(v, dt: float) -> void:
	for k in v.cd:
		if v.cd[k] > 0.0:
			v.cd[k] -= dt
	var wname: String = v.weapon()
	var W: Dictionary = D.WEAP[wname]
	if not W["auto"] or wname == "rkt" or wname == "flare" or v.cd.get(wname, 0.0) > 0.0:
		return
	v.cd[wname] = 1.0 / W["rate"]
	_fire(v, wname)


## A remote player was destroyed: show the same falling or burning wreck as for local vehicles.
func remote_destroyed(v) -> void:
	v.dead = true
	for m in missiles:
		if m["target"] == v:
			m["target"] = null
	if v.cat == "inf":
		v.start_wreck()
	elif v.cat == "tank":
		explosion(v.pos, 2.0)
		v.wreck_fx = fx.burning(v)
	else:
		explosion(v.pos, 1.0)
		v.start_wreck()


func remote_cannon(v, p: Vector3, d: Vector3) -> void:
	_bullet(v, p, d, D.WEAP["cannon"], Vector3.ZERO, "cannon")
	v.flash_muzzle(p, 4.0)
	fx.impact(p + d * 2.0, true)
	audio.play3d("cannon", p, -2.0, 120.0)


# ---------------------------------------------------------------- damage
func damage(victim, amt: float, attacker, wname: String) -> void:
	if victim == null or victim.dead:
		return
	if attacker == player and victim != attacker:
		hit_t = 0.15
		audio.tone("hit", -12.0)
	if victim.remote:
		return
	var W = D.WEAP.get(wname)
	if W is Dictionary and W.get("small", false) and victim.cat != "inf":
		amt *= victim.T.get("small", 1.0)      # rifle bullets barely scratch armour
	if attacker != null and attacker.is_bot and not victim.is_bot:
		amt *= D.DIFF[settings["diff"]]["dmg"]
	victim.hp -= amt
	victim.last_hit_by = attacker
	if victim == player:
		dmg_t = 0.4
		cam_shake = maxf(cam_shake, 0.5)
	if victim.hp <= 0.0:
		kill(victim, attacker, wname)


func splash(p: Vector3, r: float, dmg: float, attacker, wname: String, except = null) -> void:
	for v in vehicles:
		if v.dead or v == except or not can_hit(attacker, v):
			continue
		var c: Vector3 = v.centre() if v.cat == "inf" else v.pos
		var d := maxf(0.0, c.distance_to(p) - v.T["r"] * 0.6)
		if d < r:
			if v.cat == "inf":
				v.hit_part = "torso"
				v.last_impulse = (c - p).normalized() * 9.0 * (1.0 - d / r) + Vector3(0, 4, 0)
			damage(v, dmg * (1.0 - d / r), attacker, wname)


func explosion(p: Vector3, s: float, snd := true) -> void:
	fx.explosion(p, s, p.y - world.height(p.x, p.z) < 6.0)
	var dc := p.distance_to(cam.global_position)
	if dc < 600.0:
		cam_shake = maxf(cam_shake, clampf(s * (1.0 - dc / 600.0) * 1.2, 0.0, 1.5))
	if snd:
		audio.play3d("explosion", p, 2.0 * minf(s, 2.0), 150.0 * s, 1.1 - minf(s, 2.0) * 0.1)


func kill(v, attacker, wname: String) -> void:
	if v.dead:
		return
	v.dead = true
	v.hp = 0.0
	v.respawn_t = 8.0
	v.locked = false
	v.lock_target = null
	if v.cat == "inf":
		# soldiers go limp and fall as a ragdoll
		v.start_wreck()
		v.respawn_t = 12.0
		audio.play3d("flesh", v.centre(), -4.0, 20.0)
	elif v.cat != "tank" and wname != "crash" and wname != "zone":
		# shot down in the air: a small blast, then the burning wreck falls
		explosion(v.pos, 1.0)
		v.start_wreck()
		v.respawn_t = 12.0
	elif v.cat == "tank":
		# a knocked-out vehicle stays on the field, burning, until it respawns
		explosion(v.pos, 2.0)
		v.wreck_fx = fx.burning(v)
	else:
		v.visible = false
		explosion(v.pos, 2.4)
		fx.wreck(v.pos + Vector3(0, 2, 0))
	if attacker == null and v.last_hit_by != null and not v.last_hit_by.dead and (wname == "crash" or wname == "zone"):
		attacker = v.last_hit_by
	add_feed(attacker, v, wname)
	if attacker == player and attacker != v:
		kills += 1
	if v == player:
		deaths += 1
		if net and net.active:
			net.event({"t": "k", "killer": attacker.peer if attacker != null and attacker.remote else (net.my_id() if attacker == player else 0), "w": wname})
		var an: String = attacker.nick if attacker != null and attacker != v else ""
		get_tree().create_timer(1.6, false).timeout.connect(func(): player_died.emit(an, wname))
	for m in missiles:
		if m["target"] == v:
			m["target"] = null


func add_feed(a, v, wname: String) -> void:
	if v == null:
		killfeed.append({"txt": wname, "t": 8.0})
		return
	var nm := func(x): return "" if x == null else ("Вы" if x == player else x.nick)
	var wr: String = D.W_RU.get(wname, wname)
	var txt: String = "%s ➜ %s (%s)" % [nm.call(a), nm.call(v), wr] if a != null and a != v else "%s: %s" % [nm.call(v), wr]
	killfeed.append({"txt": txt, "t": 6.0})
	feed_log.append(txt)
	if killfeed.size() > 5:
		killfeed.pop_front()


# ---------------------------------------------------------------- projectiles
## First vehicle the segment passes through; for soldiers the body part is tested (stored in v.hit_part).
func _seg_hit(a: Vector3, b: Vector3, owner, pad: float):
	for v in vehicles:
		if v.dead or not can_hit(owner, v):
			continue
		if v.cat == "inf":
			if _seg_dist2(a, b, v.centre()) < 1.6 and (pad > 0.0 or v.test_hit(a, b) != ""):
				v.hit_part = "torso" if pad > 0.0 else v.test_hit(a, b)
				return v
			continue
		var r: float = v.T["r"] + pad
		if _seg_dist2(a, b, v.pos) < r * r:
			return v
	return null


## Bullet or pellet hitting a soldier: body-part damage, blood, and an instant kill through the head.
func _hit_soldier(v, b: Dictionary) -> void:
	var W: Dictionary = b["W"]
	var dir: Vector3 = b["v"].normalized()
	var part: String = v.hit_part
	hit_stats[part] = hit_stats.get(part, 0) + 1
	v.last_impulse = dir * (6.0 if b["w"] == "shotgun" else 4.0)
	var pt: Vector3 = v.hit_point
	if part == "head":
		fx.blood(pt, dir, 3.0)
		fx.blood_mist(pt, dir)
		if b["owner"] == player:
			flash("ХЕДШОТ!", "red")
			audio.tone("headshot", -2.0)
		damage(v, 1000.0, b["owner"], "headshot")
		return
	fx.blood(pt, dir, 1.0)
	audio.play3d("flesh", pt, -8.0, 12.0)
	var mult := 1.0 if part == "torso" else 0.6
	damage(v, W["dmg"] * mult, b["owner"], b["w"])


func _update_bullets(dt: float) -> void:
	var i := bullets.size() - 1
	while i >= 0:
		var b: Dictionary = bullets[i]
		b["prev"] = b["p"]
		b["v"].y -= G * dt
		b["p"] += b["v"] * dt
		b["life"] -= dt
		var dead: bool = b["life"] <= 0.0
		if not dead:
			var W: Dictionary = b["W"]
			var big: bool = b["w"] == "cannon"
			var hit = _seg_hit(b["prev"], b["p"], b["owner"], 0.0)
			if hit != null and hit.cat == "inf":
				dead = true
				_hit_soldier(hit, b)
				if W.has("splash"):
					splash(b["p"], W["splash"], W["sdmg"], b["owner"], b["w"], hit)
					explosion(b["p"], 1.4 if big else 0.35, big)
			elif hit != null:
				dead = true
				damage(hit, W["dmg"], b["owner"], b["w"])
				if W.has("splash"):
					splash(b["p"], W["splash"], W["sdmg"], b["owner"], b["w"], hit)
					explosion(b["p"], 1.4 if big else 0.35, big)
				else:
					fx.impact(b["p"])
			else:
				var p: Vector3 = b["p"]
				var gh: float = world.surf_h(p.x, p.z)
				if p.y < gh:
					dead = true
					p.y = gh + 0.3
					if W.has("splash"):
						splash(p, W["splash"], W["sdmg"], b["owner"], b["w"])
						explosion(p, 1.4 if big else 0.35, big)
					else:
						fx.impact(p)
		if dead:
			bullets[i] = bullets[bullets.size() - 1]
			bullets.pop_back()
		i -= 1


func _deflect(m: Dictionary, k: float) -> void:
	var sp: float = m["vel"].length()
	m["vel"] = (m["vel"] + Vector3(randf_range(-k, k), randf_range(-k * 0.4, k * 0.8), randf_range(-k, k)) * sp).normalized() * sp


func _update_missiles(dt: float) -> void:
	var i := missiles.size() - 1
	while i >= 0:
		var m: Dictionary = missiles[i]
		i -= 1
		var W: Dictionary = m["W"]
		m["prev"] = m["p"]
		m["life"] -= dt
		m["t"] += dt
		var spd: float = m["vel"].length()
		var vd: Vector3 = m["vel"] / maxf(spd, 1.0)
		if m["t"] < W["burn"]:
			m["vel"] += vd * W["thrust"] * dt
		m["vel"] -= vd * W["drag"] * spd * spd * dt
		m["vel"].y -= G * dt
		if not m["rocket"]:
			var t = m["target"]
			if t != null and not (t is Flare) and (t.dead or t.in_smoke):
				if not t.dead:
					_deflect(m, 0.2)
				t = null
				m["target"] = null
			# radar AAM loses lock in the doppler notch, at very low target speed or during post-stall manoeuvres
			if t != null and not (t is Flare) and m["w"] == "aam" and t.cat == "plane":
				var to: Vector3 = t.pos - m["p"]
				var dist := to.length()
				if dist > 220.0:
					var radial := absf(t.vel.dot(to / dist))
					var ch := 1.8 if t.man != null else 1.1 if t.speed < 95.0 else 0.7 if (radial < 45.0 and t.speed > 140.0) else 0.0
					if ch > 0.0 and randf() < ch * dt:
						if t == player:
							flash("РАКЕТА СОРВАНА МАНЁВРОМ", "grn")
						_deflect(m, 0.25)
						t = null
						m["target"] = null
			if t != null and not (t is Flare):
				for f in flares:
					if f.owner_v != t or m["seen"].has(f):
						continue
					var to: Vector3 = f.p - m["p"]
					if to.length() < 1700.0 and vd.angle_to(to) < 0.6:
						m["seen"][f] = true
						if randf() < 0.5 * (1.0 - f.age / 3.2):
							if t == player:
								flash("РАКЕТА УВЕДЕНА ФЛАЕРАМИ", "grn")
							m["target"] = f
							t = f
							break
			if t != null and m["t"] > 0.2:
				var tp: Vector3 = t.p if t is Flare else t.pos
				var tv: Vector3 = t.v if t is Flare else t.vel
				var r: Vector3 = tp - m["p"]
				var R := maxf(r.length(), 1.0)
				if vd.angle_to(r) > W["gimbal"]:
					if t == player:
						flash("РАКЕТА ПРОМАХНУЛАСЬ", "grn")
					m["target"] = null
				else:
					# proportional navigation: a = N * (omega x v), limited to max G
					var om := r.cross(tv - m["vel"]) / (R * R)
					var a: Vector3 = om.cross(m["vel"]) * W["nav"]
					a.y += G
					var am := a.length()
					var amax: float = W["max_g"] * G
					if am > amax:
						a *= amax / am
					m["vel"] += a * dt - vd * minf(am, amax) * 0.05 * dt
					if _seg_dist2(m["prev"], m["p"] + m["vel"] * dt, tp) < W["prox"] * W["prox"]:
						m["p"] = tp
						_boom(m, null if t is Flare else t)
						_remove_missile(m)
						continue
			elif m["t"] < W["burn"]:
				m["vel"].y += G * dt * 0.9
			if m["t"] > W["burn"] and m["vel"].length() < W["min_spd"]:
				m["life"] = minf(m["life"], 0.4)
		spd = m["vel"].length()
		m["d"] = m["vel"] / maxf(spd, 1.0)
		m["p"] += m["vel"] * dt
		var hit = _seg_hit(m["prev"], m["p"], m["owner"], 1.0)
		if hit != null:
			_boom(m, hit)
			_remove_missile(m)
			continue
		var gh: float = world.surf_h(m["p"].x, m["p"].z)
		if m["p"].y < gh or m["life"] <= 0.0:
			if m["p"].y < gh:
				m["p"].y = gh + 0.5
			_boom(m, null)
			_remove_missile(m)
			continue
		var n: Node3D = m["node"]
		n.global_position = m["p"]
		if m["d"].cross(Vector3.UP).length_squared() > 1e-4:
			n.look_at(m["p"] + m["d"], Vector3.UP)
		if m["t"] > W["burn"] and n.has_node("Flame"):
			n.get_node("Flame").queue_free()
			m["trail"].emitting = false


func _boom(m: Dictionary, hit) -> void:
	var W: Dictionary = m["W"]
	if hit != null:
		damage(hit, W["dmg"], m["owner"], m["w"])
	splash(m["p"], W.get("splash", 14.0), W.get("sdmg", W["dmg"] * 0.35), m["owner"], m["w"], hit)
	explosion(m["p"], 0.9 if m["rocket"] else 1.3)


func _remove_missile(m: Dictionary) -> void:
	missiles.erase(m)
	fx.detach_trail(m["trail"])
	m["node"].queue_free()


func _update_flares(dt: float) -> void:
	var i := flares.size() - 1
	while i >= 0:
		var f = flares[i]
		f.age += dt
		if f.age > 3.2:
			for m in missiles:
				if m["target"] == f:
					m["target"] = null
			fx.detach_trail(f.smoke)
			f.queue_free()
			flares.remove_at(i)
		else:
			f.v.y -= G * 0.5 * dt
			f.v *= 1.0 - 0.7 * dt
			f.p += f.v * dt
			f.global_position = f.p
			f.glow.pixel_size = 0.02 + 0.05 * (1.0 - f.age / 3.2)
		i -= 1


func _update_smokes(dt: float) -> void:
	var i := smokes.size() - 1
	while i >= 0:
		smokes[i]["t"] -= dt
		if smokes[i]["t"] <= 0.0:
			smokes.remove_at(i)
		i -= 1
	for v in vehicles:
		v.in_smoke = false
		if v.dead:
			continue
		for c in smokes:
			if v.pos.distance_to(c["p"]) < c["r"] + v.T["r"] * 0.3:
				v.in_smoke = true
				break


# ---------------------------------------------------------------- bots
## Infantry bot: advance on the enemy, take cover behind nothing in particular, fire short bursts,
## shoot down aircraft with the Stinger, and stay away from tanks it cannot hurt.
func _bot_inf(b, dt: float) -> void:
	var inp: Dictionary = b.inp
	var B: Dictionary = b.bot
	var Df: Dictionary = D.DIFF[settings["diff"]]
	inp["fire"] = false
	inp["fire_pressed"] = false
	inp["flare"] = false
	B["think"] -= dt
	var e: Vector3 = b.eye()
	if B["think"] <= 0.0:
		B["think"] = randf_range(0.5, 0.9)
		var best = null
		var bd := INF
		var air = null
		var ad := INF
		for v in vehicles:
			if v.dead or v.team == b.team:
				continue
			var d: float = v.pos.distance_to(b.pos)
			if v.cat == "plane" or v.cat == "heli":
				if d < 3800.0 and d < ad and has_los(e, v.pos):
					ad = d
					air = v
			elif v.cat == "inf" and d < 420.0 and d < bd and has_los(e, v.pos + Vector3(0, 1.2, 0)):
				bd = d
				best = v
		B["tgt"] = best
		B["air"] = air
		if best == null:
			# nobody in sight: head for the nearest enemy soldier or the enemy side of the village
			var goal = null
			var gd := INF
			for v in vehicles:
				if not v.dead and v.team != b.team and v.cat == "inf":
					var d: float = v.pos.distance_to(b.pos)
					if d < gd:
						gd = d
						goal = v
			var side: Vector2 = INF_SPAWN["red" if b.team == "blue" else "blue"]
			B["wp"] = goal.pos if goal != null else Vector3(side.x, 0, side.y)
	var t = B["tgt"] if B["tgt"] != null and is_instance_valid(B["tgt"]) and not B["tgt"].dead else null
	var air = B.get("air") if B.get("air") != null and is_instance_valid(B.get("air")) and not B.get("air").dead else null
	if t != B["last_t"]:
		B["last_t"] = t
		B["seen_t"] = 0.0
	B["seen_t"] += dt
	B["stuck"] = B.get("stuck", 0.0) - dt
	var st_i: int = b.slot_of("stinger")
	# aircraft overhead and a Stinger in hand: lock and fire
	B["msl_t"] -= dt
	if air != null and st_i >= 0 and b.ammo[st_i] > 0 and settings["shoot"] and B["msl_t"] <= 0.0 and air.pos.distance_to(b.pos) < 3000.0 and (t == null or t.pos.distance_to(b.pos) > 120.0):
		b.slot = st_i
		var dist: float = air.pos.distance_to(e)
		inp["aim"] = (air.pos + air.vel * (dist / 600.0) - e).normalized()
		inp["aim_point"] = air.pos
		inp["move"] = Vector2.ZERO
		if b.locked and b.lock_target == air and B["seen_t"] > Df["react"]:
			if _bot_use(b, "stinger"):
				B["msl_t"] = Df["msl"] * randf_range(0.8, 1.4)
		return
	if b.slot == st_i:
		b.slot = 0
	if t != null:
		var tc: Vector3 = t.pos + Vector3(0, 1.25, 0)
		var dist: float = tc.distance_to(e)
		b.slot = b.slot_of("shotgun") if dist < 14.0 and b.ammo[b.slot_of("shotgun")] > 0 else 0
		if randf() < dt * 1.5:
			# the difficulty setting decides how well bots shoot at the player; bot-vs-bot fights resolve faster
			B["aim_err"] = Vector3(randf_range(-1, 1), randf_range(-0.7, 0.9), randf_range(-1, 1)) * (Df["inf"] if t == player else 0.008)
		var ap: Vector3 = tc + t.vel * (dist / 700.0) + B["aim_err"] * dist
		inp["aim_point"] = ap
		inp["aim"] = (ap - e).normalized()
		# keep moving a little while fighting so they are not sitting ducks
		if randf() < dt * 0.6:
			B["strafe"] = randf_range(-0.35, 0.35)
		inp["move"] = Vector2(B.get("strafe", 0.0), 0.8 if dist > 200.0 else (0.3 if dist > 120.0 else (-0.25 if dist < 20.0 else 0.0)))
		if settings["shoot"] and B["seen_t"] > Df["react"] * 0.7 and dist < 220.0:
			B["burst"] = B.get("burst_t", 0.0)
			B["burst_t"] = B.get("burst_t", 0.0) + dt
			var cycle := 1.6 / maxf(Df["gun"] * 2.0, 0.3)
			if fmod(B["burst_t"], cycle) < 0.45 and b.aim_dir.angle_to(inp["aim"]) < 0.15:
				_bot_use(b, b.weapon())
		return
	# march toward the goal
	var wp: Vector3 = B["wp"] if B["wp"] != null else b.pos
	var to := Vector3(wp.x - b.pos.x, 0, wp.z - b.pos.z)
	if b.blocked > 0.4 and B["stuck"] <= 0.0:
		B["stuck"] = 1.5
		B["detour"] = 1.0 if randf() < 0.5 else -1.0
	var dirv := to.normalized() if to.length() > 1.0 else Vehicle.dir_of(b.heading)
	if B["stuck"] > 0.0:
		dirv = dirv.rotated(Vector3.UP, B.get("detour", 1.0) * 1.3)
	inp["aim"] = dirv
	inp["aim_point"] = b.pos + dirv * 50.0 + Vector3(0, 1.4, 0)
	inp["move"] = Vector2(0, 1.0 if to.length() > 200.0 else 0.8)
	if b.mag[0] < 15:
		b.start_reload()



## Air-defence bot (Pantsir): missiles at aircraft it has locked, 30 mm guns at anything close.
func _bot_aa(b, t, piv: Vector3, fired: bool) -> void:
	var inp: Dictionary = b.inp
	var B: Dictionary = b.bot
	var Df: Dictionary = D.DIFF[settings["diff"]]
	var air = null
	var ad := INF
	for v in vehicles:
		if v.dead or v.team == b.team or v.cat == "tank":
			continue
		var d: float = v.pos.distance_to(b.pos)
		if d < ad and d < 8000.0 and has_los(piv, v.pos):
			ad = d
			air = v
	var tgt = air
	if tgt == null and t != null and t.pos.distance_to(b.pos) < 1500.0 and has_los(piv, t.pos):
		tgt = t
	if tgt == null:
		inp["aim_point"] = b.pos + Vehicle.dir_of(b.heading) * 100.0 + Vector3(0, 30, 0)
		return
	var dist: float = tgt.pos.distance_to(piv)
	var tt: float = dist / D.WEAP["aa30"]["spd"]
	var ap: Vector3 = tgt.pos + Vector3(0, 1.0 if tgt.cat == "inf" else 0.0, 0) + tgt.vel * tt + B["aim_err"] * dist
	ap.y += 0.5 * G * tt * tt
	inp["aim_point"] = ap
	if randf() < 0.02:
		B["aim_err"] = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * Df["err"]
	if not B["can_launch"] or fired:
		return
	if tgt == air and b.locked and b.lock_target == air and B["msl_t"] <= 0.0 and dist > 700.0:
		if _bot_use(b, "sam"):
			B["msl_t"] = Df["msl"] * randf_range(0.5, 0.9)
	elif B["can_shoot"] and dist < (2500.0 if tgt == air else 1500.0) and b.aim_dir.angle_to((ap - piv).normalized()) < 0.05:
		_bot_use(b, "aa30")



func _nearest_enemy(b):
	var best = null
	var bd := INF
	for v in vehicles:
		if v.dead or v.team == b.team or (b.cat == "plane" and v.cat == "inf"):
			continue
		var d: float = v.pos.distance_squared_to(b.pos)
		if d < bd:
			bd = d
			best = v
	return best


func _bot_use(b, wname: String) -> bool:
	var i: int = b.slot_of(wname)
	if i < 0 or b.ammo[i] <= 0 or b.cd.get(wname, 0.0) > 0.0:
		return false
	b.slot = i
	b.inp["fire"] = true
	b.inp["fire_pressed"] = true
	return true


func _bot_think(b, dt: float) -> void:
	var inp: Dictionary = b.inp
	var B: Dictionary = b.bot
	inp["fire"] = false
	inp["fire_pressed"] = false
	inp["flare"] = false
	B["think"] -= dt
	if B["think"] <= 0.0:
		B["think"] = 1.5
		B["tgt"] = _nearest_enemy(b)
	var t = B["tgt"] if B["tgt"] != null and is_instance_valid(B["tgt"]) and not B["tgt"].dead else null
	var threat = null
	var td := INF
	for m in missiles:
		if m["target"] == b:
			var d: float = m["p"].distance_to(b.pos)
			if d < td:
				td = d
				threat = m
	var Df: Dictionary = D.DIFF[settings["diff"]]
	if t != B["last_t"]:
		B["last_t"] = t
		B["seen_t"] = 0.0
	B["seen_t"] += dt
	B["gun_t"] += dt
	var shoot: bool = settings["shoot"] and B["seen_t"] > Df["react"]
	B["can_shoot"] = shoot and fmod(B["gun_t"], 2.6) < 2.6 * Df["gun"]
	B["can_launch"] = shoot
	B["flare_t"] -= dt
	B["msl_t"] -= dt
	B["rkt_t"] -= dt
	var fired := false
	if settings["shoot"] and threat != null and td < 1700.0 and B["flare_t"] <= 0.0:
		B["flare_t"] = 1.2
		if randf() < Df["flare"] and b.slot_of("flare") >= 0:
			inp["flare"] = true
			fired = true
	match b.cat:
		"plane": _bot_plane(b, t, threat, td, dt, fired)
		"heli": _bot_heli(b, t, threat, td, dt, fired)
		_: _bot_tank(b, t, dt, fired)


func _bot_plane(b, t, threat, td: float, dt: float, fired: bool) -> void:
	var inp: Dictionary = b.inp
	var B: Dictionary = b.bot
	var Df: Dictionary = D.DIFF[settings["diff"]]
	var f: Vector3 = b.fwd()
	var aim: Vector3
	if t != null:
		var to: Vector3 = t.pos - b.pos
		var dist := to.length()
		aim = (t.pos + t.vel * (dist / 1250.0) - b.pos).normalized()
		if B["break_t"] <= 0.0 and dist < 500.0 and f.dot(to) / dist > 0.5 and t.vel.dot(to) < 0.0:
			B["break_t"] = 2.5
			B["break_dir"] = (to.cross(Vector3.UP).normalized() + Vector3(0, 0.3, 0)).normalized()
		inp["throttle"] = 1.0 if dist > 2500.0 else 0.8
		if B["can_launch"] and not fired:
			var a := f.angle_to(aim)
			if b.locked and B["msl_t"] <= 0.0 and dist > 800.0 and dist < 3800.0:
				if _bot_use(b, "aam"):
					B["msl_t"] = Df["msl"] * randf_range(0.7, 1.3)
			elif B["can_shoot"] and dist < 900.0 and a < 0.035 + Df["err"]:
				_bot_use(b, "gun")
		aim = (aim + B["aim_err"] * 0.5).normalized()
	else:
		B["wander"] += dt * 0.2
		aim = Vector3(-sin(B["wander"]), 0.02, -cos(B["wander"])).normalized()
		inp["throttle"] = 0.6
	if B["break_t"] > 0.0:
		B["break_t"] -= dt
		aim = B["break_dir"]
	if threat != null and td < 2500.0:
		aim = threat["d"].cross(Vector3.UP).normalized()
		if aim.dot(f) < 0.0:
			aim = -aim
		aim.y = 0.15
		aim = aim.normalized()
		inp["throttle"] = 1.0
	# terrain avoidance with look-ahead along the flight path
	var alt: float = b.pos.y - world.surf_h(b.pos.x, b.pos.z)
	var min_a := alt
	for k in [2.0, 4.0, 7.0]:
		var ah: Vector3 = b.pos + b.vel * k
		min_a = minf(min_a, ah.y - world.surf_h(ah.x, ah.z))
	if min_a < 350.0 or alt < 300.0:
		aim.y = maxf(aim.y, 0.8 if min_a < 150.0 else 0.45)
		aim = aim.normalized()
		inp["throttle"] = 1.0
	if b.pos.y > 3500.0:
		aim.y = minf(aim.y, -0.1)
		aim = aim.normalized()
	var r := Vector2(b.pos.x, b.pos.z).length()
	if r > 3400.0 and Vector2(b.vel.x, b.vel.z).dot(Vector2(b.pos.x, b.pos.z)) > 0.0:
		aim = Vector3(-b.pos.x / r, 0.1, -b.pos.z / r).normalized()
	if randf() < dt * 0.5:
		B["aim_err"] = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * Df["err"]
	inp["aim"] = aim


func _bot_heli(b, t, threat, td: float, dt: float, fired: bool) -> void:
	var inp: Dictionary = b.inp
	var B: Dictionary = b.bot
	var Df: Dictionary = D.DIFF[settings["diff"]]
	inp["up"] = 0.0
	inp["down"] = 0.0
	var desired: float = world.surf_h(b.pos.x, b.pos.z) + 90.0
	if t != null:
		var to: Vector3 = t.pos - b.pos
		var dist := to.length()
		var hd := Vector2(to.x, to.z).length()
		var dir := Vector3(to.x, 0, to.z).normalized()
		if hd < 500.0:
			dir = dir.rotated(Vector3.UP, 1.2 * B["circ"])
			inp["throttle"] = 0.55
		elif hd > 950.0:
			inp["throttle"] = 1.0
		else:
			inp["throttle"] = 0.2
		if threat != null and td < 2000.0:
			dir = dir.rotated(Vector3.UP, 1.4 * B["circ"])
			inp["throttle"] = 1.0
		inp["aim"] = dir
		if t.cat != "tank":
			desired = maxf(desired, minf(t.pos.y, world.surf_h(b.pos.x, b.pos.z) + 400.0))
		inp["aim_point"] = t.pos + Vector3(0, 1.0 if t.cat == "inf" else 0.0, 0) + t.vel * (dist / 850.0) + B["aim_err"] * dist
		if randf() < dt * 0.7:
			B["aim_err"] = Vector3(randf_range(-1, 1), randf_range(-0.5, 0.5), randf_range(-1, 1)) * Df["err"]
		if B["can_launch"] and not fired:
			var aligned: float = b.fixed_dir.angle_to(t.pos - b.pos)
			if b.locked and B["msl_t"] <= 0.0:
				if _bot_use(b, "atgm"):
					B["msl_t"] = Df["msl"] * randf_range(0.8, 1.4)
			elif B["burst"] > 0 and b.cd.get("rkt", 0.0) <= 0.0:
				if _bot_use(b, "rkt"):
					B["burst"] -= 1
			elif B["rkt_t"] <= 0.0 and dist < 1100.0 and aligned < 0.12:
				B["burst"] = 3
				B["rkt_t"] = randf_range(8, 14)
			elif B["can_shoot"] and b.type == "ah64" and dist < 1200.0:
				_bot_use(b, "gun360")
			elif B["can_shoot"] and b.type == "mi24" and dist < 1100.0 and aligned < 0.1:
				_bot_use(b, "sidegun")
	else:
		inp["aim"] = Vehicle.dir_of(b.heading + 0.3)
		inp["throttle"] = 0.3
		inp["aim_point"] = b.pos + inp["aim"] * 200.0
	var ah: Vector3 = b.pos + b.vel * 4.0
	desired = maxf(desired, world.surf_h(ah.x, ah.z) + 50.0)
	var r := Vector2(b.pos.x, b.pos.z).length()
	if r > 4300.0:
		inp["aim"] = Vector3(-b.pos.x / r, 0, -b.pos.z / r)
		inp["throttle"] = 1.0
	if b.pos.y < desired - 6.0:
		inp["up"] = 1.0
	elif b.pos.y > desired + 6.0:
		inp["down"] = 1.0


func _bot_tank(b, t, dt: float, fired: bool) -> void:
	var inp: Dictionary = b.inp
	var B: Dictionary = b.bot
	var Df: Dictionary = D.DIFF[settings["diff"]]
	B["wp_t"] -= dt
	B["stop_t"] -= dt
	B["cwait"] = B.get("cwait", 0.0) - dt
	if B["wp"] == null or B["wp_t"] <= 0.0 or b.blocked > 1.5 or Vector2(B["wp"].x - b.pos.x, B["wp"].z - b.pos.z).length() < 40.0:
		B["wp_t"] = randf_range(15, 30)
		if t != null and t.cat == "tank" and t.pos.distance_to(b.pos) > 900.0:
			B["wp"] = Vector3(t.pos.x + randf_range(-350, 350), 0, t.pos.z + randf_range(-350, 350))
		else:
			var a := randf() * TAU
			var rr := randf_range(200, 2200)
			B["wp"] = Vector3(cos(a) * rr, 0, sin(a) * rr)
		if b.blocked > 1.5:
			b.heading += PI * 0.5
	var dy := angle_difference(b.heading, Vehicle.heading_of(B["wp"] - b.pos))
	inp["left"] = 1.0 if dy > 0.08 else 0.0
	inp["right"] = 1.0 if dy < -0.08 else 0.0
	inp["throttle"] = 0.0 if B["stop_t"] > 0.0 else (0.25 if absf(dy) > 1.0 else 0.7)
	var piv: Vector3 = b.pos + Vector3(0, b.T.get("aim_h", 2.4), 0)
	if b.type == "pantsir":
		_bot_aa(b, t, piv, fired)
		return
	if t != null:
		var dist: float = t.pos.distance_to(b.pos)
		if dist < 2300.0 and has_los(piv, t.pos):
			var tt: float = dist / D.WEAP["cannon"]["spd"]
			var air: bool = t.cat != "tank"
			var mg_i: int = b.slot_of("mg")
			if air and dist < 900.0:
				b.slot = mg_i
			else:
				b.slot = b.slot_of("cannon")
			if b.slot == mg_i:
				inp["aim_point"] = t.pos + Vector3(0, 1.0 if t.cat == "inf" else 0.0, 0) + t.vel * (dist / 900.0)
			else:
				var ap: Vector3 = t.pos + Vector3(0, 1.0 if t.cat == "inf" else 0.0, 0) + t.vel * tt + B["aim_err"] * dist
				ap.y += 0.5 * G * tt * tt + 1.0
				inp["aim_point"] = ap
			if B["can_launch"] and not fired:
				var want: Vector3 = (inp["aim_point"] - piv).normalized()
				if b.slot == mg_i:
					if B["can_shoot"] and b.aim_dir.angle_to(want) < 0.08:
						_bot_use(b, "mg")
				elif b.aim_dir.angle_to(want) < 0.015 and b.cd.get("cannon", 0.0) <= 0.0 and B.get("cwait", 0.0) <= 0.0:
					if _bot_use(b, "cannon"):
						B["cwait"] = 4.0 + randf_range(2, 5)
						B["aim_err"] = Vector3(randf_range(-1, 1), randf_range(-0.4, 0.6), randf_range(-1, 1)) * Df["err"]
						if randf() < 0.4:
							B["stop_t"] = 2.5
			return
	inp["aim_point"] = b.pos + Vehicle.dir_of(b.heading) * 100.0 + Vector3(0, 2.4, 0)
