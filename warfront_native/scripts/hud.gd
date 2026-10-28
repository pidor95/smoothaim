extends Control
## In-battle HUD and touch controls. Everything is drawn here and touches are tracked per finger,
## so the player can steer, change throttle and fire at the same time.

const D := preload("res://scripts/data.gd")

signal pause_pressed

var game: Node
var active := false
var font: Font
var u := 1.0                     # scale: 1 at 720 px screen height
var touches := {}                # finger index -> {"role": String, "pos": Vector2}
var btn := {}                    # id -> {"rect": Rect2, "round": bool}
var joy_area := Rect2()          # infantry: touching here spawns the movement stick
var joy_c := Vector2.ZERO
var joy_k := Vector2.ZERO
var joy_on := false
var desktop := not OS.has_feature("mobile")

const COL_RED := Color(1.0, 0.33, 0.3)
const COL_GRN := Color(0.45, 1.0, 0.6)
const COL_ORG := Color(1.0, 0.7, 0.28)
const COL_BLU := Color(0.45, 0.75, 1.0)
const BG := Color(0.05, 0.08, 0.1, 0.45)


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	font = ThemeDB.fallback_font


func _process(_dt: float) -> void:
	if active:
		queue_redraw()


# ---------------------------------------------------------------- layout
func _layout() -> void:
	var s := get_viewport_rect().size
	size = s
	u = s.y / 720.0
	btn.clear()
	var cat: String = game.player.cat if game.player else "plane"
	btn["skip"] = {"rect": Rect2(s.x / 2.0 - 170 * u, s.y - 120 * u, 340 * u, 64 * u), "round": false}
	if desktop:
		# PC: mouse and keyboard only, no touch buttons; the throttle is just a gauge
		if cat != "inf":
			btn["thr"] = {"rect": Rect2(22 * u, s.y * 0.3, 20 * u, s.y * 0.4), "round": false}
		return
	if cat != "inf":
		btn["thr"] = {"rect": Rect2(26 * u, s.y * 0.2, 74 * u, s.y * 0.52), "round": false}
	else:
		joy_area = Rect2(0, s.y * 0.3, s.x * 0.4, s.y * 0.7)
		btn["reload"] = {"rect": _circ(Vector2(s.x - 315 * u, s.y - 95 * u), 52 * u), "round": true}
	if cat == "heli":
		btn["a"] = {"rect": _circ(Vector2(205 * u, s.y - 235 * u), 50 * u), "round": true}
		btn["b"] = {"rect": _circ(Vector2(205 * u, s.y - 115 * u), 50 * u), "round": true}
	elif cat == "tank":
		btn["a"] = {"rect": _circ(Vector2(195 * u, s.y - 105 * u), 52 * u), "round": true}
		btn["b"] = {"rect": _circ(Vector2(315 * u, s.y - 105 * u), 52 * u), "round": true}
	btn["fire"] = {"rect": _circ(Vector2(s.x - 150 * u, s.y - 165 * u), 88 * u), "round": true}
	if cat != "tank" and cat != "inf":
		btn["flare"] = {"rect": _circ(Vector2(s.x - 315 * u, s.y - 95 * u), 56 * u), "round": true}
	btn["zoom"] = {"rect": _circ(Vector2(s.x - 300 * u, s.y - 240 * u), 44 * u), "round": true}
	btn["pause"] = {"rect": Rect2(s.x - 66 * u, 12 * u, 54 * u, 54 * u), "round": false}
	if game.player and game.player.T.get("maneuver", false):
		var names := ["man", "cobra", "kulbit", "flat"]
		for i in names.size():
			btn[names[i]] = {"rect": Rect2(s.x - 500 * u + i * 118 * u, s.y - 395 * u, 108 * u, 56 * u), "round": false}
	if game.player:
		var n: int = game.player.T["slots"].size()
		var wdt := 132 * u
		var x0 := s.x / 2.0 - (n * wdt + (n - 1) * 10 * u) / 2.0
		for i in n:
			btn["slot%d" % i] = {"rect": Rect2(x0 + i * (wdt + 10 * u), s.y - 82 * u, wdt, 66 * u), "round": false}


static func _circ(c: Vector2, r: float) -> Rect2:
	return Rect2(c - Vector2(r, r), Vector2(r, r) * 2.0)


func _hit(id: String, p: Vector2) -> bool:
	if not btn.has(id):
		return false
	var b: Dictionary = btn[id]
	var r: Rect2 = b["rect"]
	if b["round"]:
		return p.distance_to(r.get_center()) <= r.size.x * 0.5 * 1.1
	return r.grow(6 * u).has_point(p)


func refresh() -> void:
	touches.clear()
	_layout()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and game:
		_layout()


# ---------------------------------------------------------------- touch input
func _input(e: InputEvent) -> void:
	if not active or game.player == null:
		return
	# desktop: the mouse is captured during battle, moves the camera, LMB fires, RMB aims, Esc pauses
	if desktop:
		if e is InputEventKey and e.pressed and not e.echo and e.keycode == KEY_ESCAPE:
			pause_pressed.emit()
			get_viewport().set_input_as_handled()
			return
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			if e is InputEventMouseMotion:
				game.look(e.relative.x, e.relative.y)
				return
			if e is InputEventMouseButton:
				var c: Dictionary = game.ctrl
				if e.button_index == MOUSE_BUTTON_LEFT:
					if e.pressed and not c["fire"]:
						c["fire_pressed"] = true
					c["fire"] = e.pressed
				elif e.button_index == MOUSE_BUTTON_RIGHT:
					c["zoom"] = e.pressed
				elif e.button_index == MOUSE_BUTTON_WHEEL_UP and e.pressed:
					game.select_slot(posmod(game.ctrl["slot"] - 1, game.player.T["slots"].size()))
				elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN and e.pressed:
					game.select_slot(posmod(game.ctrl["slot"] + 1, game.player.T["slots"].size()))
				get_viewport().set_input_as_handled()
				return
			if (e is InputEventScreenTouch or e is InputEventScreenDrag) and e.device == InputEvent.DEVICE_ID_EMULATION:
				return
		elif e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			if game.player.intro != null and _hit("skip", e.position):
				game.skip_intro()
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			get_viewport().set_input_as_handled()
			return
	if e is InputEventScreenTouch:
		var t := e as InputEventScreenTouch
		if t.pressed:
			_press(t.index, t.position)
		else:
			_release(t.index)
		get_viewport().set_input_as_handled()
	elif e is InputEventScreenDrag:
		var d := e as InputEventScreenDrag
		if touches.has(d.index):
			var tr: Dictionary = touches[d.index]
			match tr["role"]:
				"look", "fire":
					game.look(d.relative.x, d.relative.y)
				"joy":
					var v := (d.position - joy_c) / (95.0 * u)
					if v.length() > 1.0:
						v = v.normalized()
					joy_k = v
					game.ctrl["move"] = Vector2(v.x, -v.y) * (1.0 if v.length() > 0.9 else 0.85)
				"thr":
					_set_thr(d.position.y)
			tr["pos"] = d.position
		get_viewport().set_input_as_handled()


func _on_button(p: Vector2) -> bool:
	for k in btn:
		if _hit(k, p):
			return true
	return false


func _press(i: int, p: Vector2) -> void:
	var c: Dictionary = game.ctrl
	var role := "look"
	if game.player.cat == "inf" and joy_area.has_point(p) and not joy_on and not _on_button(p):
		joy_on = true
		joy_c = p
		joy_k = Vector2.ZERO
		touches[i] = {"role": "joy", "pos": p}
		return
	for k in btn:
		if not _hit(k, p):
			continue
		if k.begins_with("slot"):
			game.select_slot(int(k.substr(4)))
			role = "none"
		if k == "skip":
			if game.player.intro != null:
				game.skip_intro()
			role = "none"
			break
		elif game.player.intro != null:
			continue
		match k:
			"pause":
				pause_pressed.emit()
				role = "none"
			"zoom":
				c["zoom"] = not c["zoom"]
				role = "none"
			"man":
				c["man"] = not c["man"]
				game.audio.tone("click", -8.0, 1.4 if c["man"] else 0.8)
				role = "none"
			"cobra", "kulbit", "flat":
				game.maneuver(k)
				role = "none"
			"reload":
				c["reload"] = true
				role = "none"
			"fire":
				if not c["fire"]:
					c["fire_pressed"] = true
				c["fire"] = true
				role = "fire"
			"flare":
				c["flare"] = true
				role = "flare"
			"a", "b":
				c[k] = true
				role = k
			"thr":
				role = "thr"
				_set_thr(p.y)
		break
	touches[i] = {"role": role, "pos": p}


func _release(i: int) -> void:
	if not touches.has(i):
		return
	var role: String = touches[i]["role"]
	touches.erase(i)
	var c: Dictionary = game.ctrl
	match role:
		"joy":
			joy_on = false
			c["move"] = Vector2.ZERO
		"fire": c["fire"] = false
		"flare": c["flare"] = false
		"a", "b": c[role] = false


func _set_thr(y: float) -> void:
	if not btn.has("thr"):
		return
	var r: Rect2 = btn["thr"]["rect"]
	var v := clampf(1.0 - (y - r.position.y) / r.size.y, 0.0, 1.0)
	if game.player and game.player.cat == "tank" and absf(v - 0.5) < 0.06:
		v = 0.5
	game.ctrl["thr"] = v


# ---------------------------------------------------------------- drawing helpers
func _text(p: Vector2, t: String, sz: float, col := Color.WHITE, align := HORIZONTAL_ALIGNMENT_LEFT, wdt := -1.0) -> void:
	var fs := int(sz * u * 1.3)
	if align != HORIZONTAL_ALIGNMENT_LEFT and wdt < 0.0:
		var w := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		p.x -= w / 2.0 if align == HORIZONTAL_ALIGNMENT_CENTER else w
		align = HORIZONTAL_ALIGNMENT_LEFT
	draw_string_outline(font, p, t, align, wdt, fs, maxi(2, int(sz * 0.25 * u)), Color(0, 0, 0, 0.6))
	draw_string(font, p, t, align, wdt, fs, col)


func _panel(r: Rect2, col := BG, rad := 10.0) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(int(rad * u))
	draw_style_box(sb, r)


func _button(id: String, label: String, on := false, sub := "") -> void:
	if not btn.has(id):
		return
	var b: Dictionary = btn[id]
	var r: Rect2 = b["rect"]
	var bg := Color(0.95, 0.75, 0.3, 0.55) if on else Color(0.08, 0.1, 0.12, 0.42)
	if b["round"]:
		var c := r.get_center()
		draw_circle(c, r.size.x / 2.0, bg)
		draw_arc(c, r.size.x / 2.0, 0, TAU, 48, Color(1, 1, 1, 0.55), 2.0 * u, true)
		_text(c + Vector2(0, 8 * u), label, 22 if r.size.x > 120 * u else 18, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	else:
		_panel(r, bg, 10)
		_text(r.get_center() + Vector2(0, (0 if sub == "" else -4) * u + 7 * u), label, 18, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
		if sub != "":
			_text(r.get_center() + Vector2(0, 24 * u), sub, 14, Color(1, 1, 1, 0.8), HORIZONTAL_ALIGNMENT_CENTER)


func _screen(p: Vector3) -> Variant:
	var cam: Camera3D = game.cam
	if cam.is_position_behind(p):
		return null
	return cam.unproject_position(p)


# ---------------------------------------------------------------- drawing
func _draw() -> void:
	if not active or game.player == null:
		return
	var p = game.player
	var T: Dictionary = p.T
	var c: Dictionary = game.ctrl
	var s := size
	var wname: String = p.weapon()
	var W: Dictionary = D.WEAP[wname]
	_objective_markers()
	if p.intro != null:
		_draw_intro(p)
		return
	# labels over other vehicles
	for v in game.vehicles:
		if v == p or v.dead or v.cat == "struct":
			continue
		var sp = _screen(v.pos + Vector3(0, v.T["r"] + 2.0, 0))
		var d: float = v.pos.distance_to(p.pos)
		if sp == null or d > 9000.0 or (v.cat == "inf" and d > (1500.0 if v.team == p.team else 350.0)):
			continue
		var col := COL_BLU if v.team == p.team else COL_RED
		var txt: String = ("%s " % v.nick if d < 3000.0 else "") + ("%d м" % roundi(d) if d < 1000.0 else "%.1f км" % (d / 1000.0))
		_text(sp, txt, 15, col, HORIZONTAL_ALIGNMENT_CENTER)
		draw_line(sp + Vector2(-5, 6) * u, sp + Vector2(0, 12) * u, col, 2.0 * u)
		draw_line(sp + Vector2(5, 6) * u, sp + Vector2(0, 12) * u, col, 2.0 * u)
	# crosshair
	var ctr := s / 2.0
	var ch := Color(1, 1, 1, 0.85)
	var gap := 6.0
	if p.cat == "inf" and W.has("spread"):
		var cam0: Camera3D = game.cam
		gap = 4.0 + tan(W["spread"] * (1.0 + p.speed * 0.35) * (0.45 if c["zoom"] else 1.0) * 2.0) / tan(deg_to_rad(cam0.fov) / 2.0) * s.y / (2.0 * u)
	# aiming down the sights the rifle's own sights do the job: only a small dot stays
	var ads: bool = p.cat == "inf" and c["zoom"] and wname != "stinger"
	for a in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
		if not ads:
			draw_line(ctr + a * gap * u, ctr + a * (gap + 10) * u, ch, 2.0 * u)
	if p.cat == "inf":
		draw_circle(ctr, 1.6 * u, ch)
	if game.hit_t > 0.0:
		for a in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			draw_line(ctr + a * 9 * u, ctr + a * 20 * u, COL_RED, 3.0 * u)
	if not p.dead:
		if p.cat == "plane":
			var np = _screen(p.pos + p.aim_dir * 700.0)
			if np != null:
				draw_arc(np, 13 * u, 0, TAU, 24, COL_GRN, 2.0 * u)
				draw_line(np + Vector2(-26, 0) * u, np + Vector2(-13, 0) * u, COL_GRN, 2.0 * u)
				draw_line(np + Vector2(13, 0) * u, np + Vector2(26, 0) * u, COL_GRN, 2.0 * u)
		elif not W.get("homing", false) and wname != "flare" and wname != "smoke" and p.cat != "inf":
			var piv: Vector3 = p.pos + Vector3(0, T.get("aim_h", 2.4), 0) if p.cat == "tank" else p.chin_pos()
			var dir: Vector3 = p.fixed_dir if wname == "rkt" else p.aim_dir
			var dist := maxf(50.0, piv.distance_to(p.inp["aim_point"]))
			var gp = _screen(piv + dir * dist)
			if gp != null:
				draw_arc(gp, 10 * u, 0, TAU, 20, COL_ORG, 2.0 * u)
				draw_circle(gp, 2.0 * u, COL_ORG)
		if W.get("bomb", false):
			_draw_ccip(p, wname)
		if wname == "storm" and not p.locked:
			var ap: Vector3 = p.inp["aim_point"]
			var tp = _screen(Vector3(ap.x, game.world.height(ap.x, ap.z), ap.z))
			if tp != null:
				draw_rect(Rect2(tp - Vector2(14, 14) * u, Vector2(28, 28) * u), COL_ORG, false, 2.0 * u)
				_text(tp + Vector2(0, 34 * u), "точка удара", 14, COL_ORG, HORIZONTAL_ALIGNMENT_CENTER)
		if W.get("homing", false):
			var cam: Camera3D = game.cam
			var rpx := tan(W["cone"]) / tan(deg_to_rad(cam.fov) / 2.0) * s.y / 2.0
			draw_arc(ctr, rpx, 0, TAU, 64, Color(1, 1, 1, 0.35), 1.5 * u)
			if p.lock_target != null and is_instance_valid(p.lock_target):
				var lp = _screen(p.lock_target.pos)
				if lp != null:
					var k: float = 1.0 if p.locked else p.lock_time / W["lock_t"]
					var sz: float = (56.0 if p.locked else 90.0 - 34.0 * k) * u
					var col := COL_RED if p.locked else COL_ORG
					draw_rect(Rect2(lp - Vector2(sz, sz) / 2.0, Vector2(sz, sz)), col, false, 2.5 * u)
					_text(lp + Vector2(0, sz / 2.0 + 18 * u), "ЗАХВАТ" if p.locked else "наведение…", 15, col, HORIZONTAL_ALIGNMENT_CENTER)
	# damage flash
	if game.dmg_t > 0.0:
		draw_rect(Rect2(Vector2.ZERO, s), Color(0.8, 0.05, 0.02, 0.28 * game.dmg_t / 0.4))
	# top-left: vehicle, health, flight data
	_panel(Rect2(14 * u, 12 * u, 330 * u, 92 * u))
	_text(Vector2(28 * u, 40 * u), T["name"], 21)
	var hpk: float = maxf(0.0, p.hp) / T["hp"]
	draw_rect(Rect2(28 * u, 52 * u, 300 * u, 10 * u), Color(0, 0, 0, 0.4))
	draw_rect(Rect2(28 * u, 52 * u, 300 * u * hpk, 10 * u), COL_GRN if hpk > 0.5 else COL_ORG if hpk > 0.25 else COL_RED)
	var alt: int = roundi(p.pos.y - game.world.surf_h(p.pos.x, p.pos.z))
	var st := "%d км/ч" % roundi(p.speed * 3.6)
	if p.cat == "plane":
		st += "  M%.2f  %.1fG  α%d°" % [p.mach, p.gload, roundi(rad_to_deg(p.aoa))]
	if p.cat != "tank" and p.cat != "inf":
		st += "  ВЫС %d м" % alt
	if p.cat == "inf" and p.sprinting:
		st += "  БЕГ"
	_text(Vector2(28 * u, 88 * u), st, 16, Color(0.9, 0.95, 1.0))
	_objective_bar()
	# top-right: score, kill feed, radar
	_text(Vector2(s.x - 470 * u, 40 * u), "Уничтожено: %d  ·  Потери: %d" % [game.kills, game.deaths], 16)
	var y := 66.0
	for k in game.killfeed:
		_text(Vector2(s.x - 470 * u, y * u), k["txt"], 14, Color(1, 1, 1, 0.9))
		y += 20.0
	_radar(Rect2(s.x - 188 * u, 76 * u, 170 * u, 170 * u))
	_button("pause", "II")
	if desktop:
		_draw_desktop(p, T)
	# warnings
	var warns: Array = []
	if game.flash_t > 0.0:
		warns.append([game.flash_txt, {"grn": COL_GRN, "org": COL_ORG, "red": COL_RED}.get(game.flash_cls, COL_GRN)])
	var near: float = game.missile_threat(p)
	if near >= 0.0 and not p.dead:
		warns.append(["⚠ РАКЕТА %.1f км%s" % [near / 1000.0, " — ФЛАЕРЫ!" if near < 1600.0 and p.cat != "tank" else ""], COL_RED])
	if not p.dead and game.being_locked(p):
		warns.append(["ВАС ЗАХВАТЫВАЮТ", COL_ORG])
	if p.in_smoke:
		warns.append(["В ДЫМУ: ракеты не наводятся", COL_BLU])
	if p.cat == "plane" and p.stalled:
		warns.append(["СВАЛИВАНИЕ: дайте тягу", COL_RED])
	if p.cat == "plane" and alt < 120 and p.vel.y < -15.0:
		warns.append(["ВЫСОТА!", COL_RED])
	var r := Vector2(p.pos.x, p.pos.z).length()
	if r > D.ZONE and not p.dead:
		warns.append(["ВЕРНИТЕСЬ В ЗОНУ БОЯ (%d с)" % maxi(0, ceili(8.0 - p.zone_t)), COL_RED])
	if not game.infinite_ammo(p) and p.ammo[p.slot] <= 0:
		warns.append(["Нет боеприпасов: выберите другой слот", COL_ORG])
	y = 150.0
	for wv in warns:
		_text(Vector2(s.x / 2.0, y * u), wv[0], 22, wv[1], HORIZONTAL_ALIGNMENT_CENTER)
		y += 32.0
	# infantry: movement stick and ammo; vehicles: throttle
	if p.cat == "inf":
		_draw_infantry(p, W)
	else:
		_draw_throttle(p, c)
	# buttons
	_button("fire", "ОГОНЬ", c["fire"])
	_button("flare", "ФЛАЕРЫ", c["flare"])
	_button("zoom", "ПРИЦЕЛ" if p.cat == "inf" else "ZOOM", c["zoom"])
	_button("reload", "R")
	if p.cat == "heli":
		_button("a", "▲", c["a"])
		_button("b", "▼", c["b"])
	elif p.cat == "tank":
		_button("a", "◀", c["a"])
		_button("b", "▶", c["b"])
	_button("man", "СВМ", c["man"])
	_button("cobra", "Кобра")
	_button("kulbit", "Кульбит")
	_button("flat", "Разворот")
	for i in T["slots"].size():
		var sl: Dictionary = T["slots"][i]
		var Wi: Dictionary = D.WEAP[sl["w"]]
		var ammo_t := "∞" if game.infinite_ammo(p) else str(p.ammo[i])
		if p.cat == "inf" and Wi.has("mag") and not game.infinite_ammo(p):
			ammo_t = "%d / %d" % [p.mag[i], p.ammo[i] - p.mag[i]]
		_button("slot%d" % i, "%d  %s" % [i + 1, sl["n"]], i == p.slot, ammo_t)
		var cdv: float = p.cd.get(sl["w"], 0.0)
		if not Wi["auto"] and cdv > 0.0 and btn.has("slot%d" % i):
			var br: Rect2 = btn["slot%d" % i]["rect"]
			draw_rect(Rect2(br.position.x, br.end.y - 5 * u, br.size.x * clampf(cdv * Wi["rate"], 0.0, 1.0), 5 * u), COL_ORG)


func _draw_infantry(p, W: Dictionary) -> void:
	var s := size
	if joy_on:
		draw_circle(joy_c, 95.0 * u, Color(0.05, 0.08, 0.1, 0.35))
		draw_arc(joy_c, 95.0 * u, 0, TAU, 48, Color(1, 1, 1, 0.45), 2.0 * u, true)
		draw_circle(joy_c + joy_k * 95.0 * u, 38.0 * u, Color(1, 1, 1, 0.55))
	elif not desktop:
		var c0 := Vector2(170 * u, s.y - 190 * u)
		draw_arc(c0, 95.0 * u, 0, TAU, 48, Color(1, 1, 1, 0.2), 2.0 * u, true)
		_text(c0 + Vector2(0, 8 * u), "ХОДЬБА", 15, Color(1, 1, 1, 0.45), HORIZONTAL_ALIGNMENT_CENTER)
	if W.has("mag"):
		var txt := "%d / %d" % [p.mag[p.slot], p.ammo[p.slot] - p.mag[p.slot]]
		_text(Vector2(s.x - 200 * u, s.y - 300 * u), txt, 26, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
		if p.reload_t > 0.0:
			_text(Vector2(s.x / 2.0, s.y / 2.0 + 60 * u), "ПЕРЕЗАРЯДКА…", 18, COL_ORG, HORIZONTAL_ALIGNMENT_CENTER)
	if desktop and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		_text(Vector2(s.x / 2.0, s.y - 110 * u), "Щёлкните по экрану, чтобы управлять мышью (Esc — пауза)", 15, Color(1, 1, 1, 0.8), HORIZONTAL_ALIGNMENT_CENTER)


func _draw_throttle(p, c: Dictionary) -> void:
	if not btn.has("thr"):
		return
	var tr: Rect2 = btn["thr"]["rect"]
	_panel(tr, BG, 12)
	var thr: float = c["thr"]
	if p.cat == "tank":
		var t := thr * 2.0 - 1.0
		var mid := tr.position.y + tr.size.y / 2.0
		var fill := Rect2(tr.position.x, mid if t < 0.0 else mid - tr.size.y / 2.0 * t, tr.size.x, absf(t) * tr.size.y / 2.0)
		draw_rect(fill, Color(0.45, 1.0, 0.6, 0.35))
		draw_line(Vector2(tr.position.x, mid), Vector2(tr.end.x, mid), Color(1, 1, 1, 0.5), 2.0 * u)
		var tt := "СТОП" if absf(t) < 0.08 else ("ВПЕРЁД %d%%" % roundi(t * 100) if t > 0.0 else "НАЗАД %d%%" % roundi(-t * 100))
		_text(Vector2(tr.position.x, tr.end.y + 24 * u), tt, 15)
	else:
		var ab: bool = p.cat == "plane" and thr > 0.85
		draw_rect(Rect2(tr.position.x, tr.end.y - tr.size.y * thr, tr.size.x, tr.size.y * thr), Color(1.0, 0.6, 0.25, 0.45) if ab else Color(0.45, 1.0, 0.6, 0.35))
		if p.cat == "plane":
			var ly := tr.end.y - tr.size.y * 0.85
			draw_line(Vector2(tr.position.x, ly), Vector2(tr.end.x, ly), Color(1, 0.6, 0.25, 0.8), 2.0 * u)
		_text(Vector2(tr.position.x, tr.end.y + 24 * u), ("ТЯГА %d%%" if p.cat == "plane" else "СКОРОСТЬ %d%%") % roundi(thr * 100) + (" ФОРСАЖ" if ab else ""), 15)
	var ky := tr.end.y - tr.size.y * thr
	draw_rect(Rect2(tr.position.x - 6 * u, ky - 5 * u, tr.size.x + 12 * u, 10 * u), Color.WHITE)


func _radar(r: Rect2) -> void:
	var p = game.player
	draw_circle(r.get_center(), r.size.x / 2.0, Color(0.03, 0.08, 0.05, 0.55))
	var R := r.size.x / 2.0
	var cc := r.get_center()
	draw_arc(cc, R * 0.5, 0, TAU, 40, Color(0.47, 1, 0.63, 0.25), 1.0)
	draw_arc(cc, R, 0, TAU, 48, Color(0.47, 1, 0.63, 0.4), 1.5)
	var rng := 7000.0 if p.cat == "plane" else 4500.0 if p.cat == "heli" else 3000.0
	var yaw: float = game.cam_yaw
	var plot := func(pos: Vector3, col: Color, sz: float):
		var d: Vector3 = pos - p.pos
		# rotate so the camera direction points up on the radar
		var fwd := Vector2(-sin(yaw), -cos(yaw))
		var right := Vector2(cos(yaw), -sin(yaw))
		var q := Vector2(Vector2(d.x, d.z).dot(right), -Vector2(d.x, d.z).dot(fwd)) / rng * R
		if q.length() > R - 3.0:
			q = q.normalized() * (R - 3.0)
		draw_rect(Rect2(cc + q - Vector2(sz, sz) / 2.0, Vector2(sz, sz)), col)
	for sm in game.smokes:
		plot.call(sm["p"], Color(0.8, 0.8, 0.8, 0.6), 6.0 * u)
	for m in game.missiles:
		if not m["rocket"]:
			plot.call(m["p"], Color(1, 1, 0.3) if m["target"] == p else Color.WHITE, 3.0 * u)
	for v in game.vehicles:
		if v == p or v.dead:
			continue
		plot.call(v.pos, COL_BLU if v.team == p.team else COL_RED, (6.0 if v.cat == "tank" else 5.0) * u)
	for o in game.objectives:
		var d: Vector3 = o["p"] - p.pos
		var fwd := Vector2(-sin(yaw), -cos(yaw))
		var right := Vector2(cos(yaw), -sin(yaw))
		var q := Vector2(Vector2(d.x, d.z).dot(right), -Vector2(d.x, d.z).dot(fwd)) / rng * R
		if q.length() > R - 8.0:
			q = q.normalized() * (R - 8.0)
		_text(cc + q + Vector2(0, 5 * u), o["n"], 12, COL_BLU if o["taken"] else COL_ORG, HORIZONTAL_ALIGNMENT_CENTER)
	draw_colored_polygon(PackedVector2Array([cc + Vector2(0, -7) * u, cc + Vector2(-5, 5) * u, cc + Vector2(5, 5) * u]), COL_GRN)


# ---------------------------------------------------------------- assault points, intro, bombs, PC panels
func _objective_bar() -> void:
	if game.objectives.is_empty():
		return
	var n: int = game.objectives.size()
	var w := 84.0 * u
	var x0 := size.x / 2.0 - (n * w + (n - 1) * 8 * u) / 2.0
	for i in n:
		var o: Dictionary = game.objectives[i]
		var r := Rect2(x0 + i * (w + 8 * u), 12 * u, w, 46 * u)
		_panel(r, Color(0.1, 0.3, 0.55, 0.6) if o["taken"] else Color(0.45, 0.12, 0.08, 0.55), 8)
		_text(Vector2(r.position.x + 12 * u, r.position.y + 31 * u), o["n"], 22, Color.WHITE)
		var left: int = game.objective_left(o)
		_text(Vector2(r.end.x - 10 * u, r.position.y + 29 * u), "✔" if o["taken"] else "%d/%d" % [left, o["units"].size()], 14,
			Color(0.8, 0.95, 1.0) if o["taken"] else Color(1, 0.85, 0.75), HORIZONTAL_ALIGNMENT_RIGHT, -1.0)


func _objective_markers() -> void:
	var p = game.player
	for o in game.objectives:
		var q = _screen(o["p"] + Vector3(0, 25, 0))
		if q == null:
			continue
		var col := COL_BLU if o["taken"] else COL_ORG
		var c: Vector2 = q
		var pts := PackedVector2Array([c + Vector2(0, -16) * u, c + Vector2(16, 0) * u, c + Vector2(0, 16) * u, c + Vector2(-16, 0) * u, c + Vector2(0, -16) * u])
		draw_polyline(pts, col, 2.5 * u, true)
		_text(c + Vector2(0, 7 * u), o["n"], 16, col, HORIZONTAL_ALIGNMENT_CENTER)
		var d: float = p.pos.distance_to(o["p"])
		_text(c + Vector2(0, 36 * u), ("%d м" % roundi(d)) if d < 1000.0 else ("%.1f км" % (d / 1000.0)), 13, col, HORIZONTAL_ALIGNMENT_CENTER)
		# fortification labels when close
		if d < 2500.0 and not o["taken"]:
			for v in o["units"]:
				if v.dead:
					continue
				var vp = _screen(v.pos + Vector3(0, 5, 0))
				if vp != null:
					_text(vp, v.T["name"], 13, COL_RED, HORIZONTAL_ALIGNMENT_CENTER)


func _draw_intro(p) -> void:
	var s := size
	var t: String = {"plane": "ВЗЛЁТ С АВИАБАЗЫ", "heli": "ВЗЛЁТ С ВЕРТОЛЁТНОЙ ПЛОЩАДКИ"}.get(p.cat, "ВЫЕЗД ИЗ ГАРАЖА")
	_panel(Rect2(s.x / 2.0 - 260 * u, 70 * u, 520 * u, 54 * u), Color(0.03, 0.05, 0.06, 0.6), 8)
	_text(Vector2(s.x / 2.0, 106 * u), t, 24, Color(1, 0.85, 0.5), HORIZONTAL_ALIGNMENT_CENTER)
	_text(Vector2(s.x / 2.0, 150 * u), p.T["name"] + " · " + D.kind_of(p.type), 17, Color(0.9, 0.95, 1.0), HORIZONTAL_ALIGNMENT_CENTER)
	_button("skip", "ПРОПУСТИТЬ  ▶" + ("    [Пробел]" if desktop else ""))


## CCIP: where a bomb released right now would land, joined to the flight path marker.
func _draw_ccip(p, wname: String) -> void:
	var fp = _screen(p.pos + p.vel.normalized() * 500.0)
	var hit = game.bomb_impact(p, wname)
	if hit == null:
		if fp != null:
			_text(fp + Vector2(0, 40 * u), "БОМБЫ: ВНЕ ДАЛЬНОСТИ", 15, COL_ORG, HORIZONTAL_ALIGNMENT_CENTER)
		return
	var hp = _screen(hit)
	if hp == null:
		return
	if fp != null:
		draw_line(fp, hp, Color(COL_GRN, 0.7), 1.5 * u)
	draw_arc(hp, 16 * u, 0, TAU, 32, COL_GRN, 2.5 * u)
	draw_circle(hp, 3 * u, COL_GRN)
	var d: float = p.pos.distance_to(hit)
	_text(hp + Vector2(0, 38 * u), "CCIP  %d м" % roundi(d), 14, COL_GRN, HORIZONTAL_ALIGNMENT_CENTER)


## PC: weapon list with keys at the bottom right, key hints at the bottom left.
func _draw_desktop(p, T: Dictionary) -> void:
	var s := size
	var n: int = T["slots"].size()
	var rw := 300.0 * u
	var rh := 32.0 * u
	var y0 := s.y - 24 * u - n * (rh + 4 * u)
	for i in n:
		var sl: Dictionary = T["slots"][i]
		var Wi: Dictionary = D.WEAP[sl["w"]]
		var r := Rect2(s.x - rw - 20 * u, y0 + i * (rh + 4 * u), rw, rh)
		var on: bool = i == p.slot
		_panel(r, Color(0.9, 0.65, 0.2, 0.7) if on else Color(0.04, 0.06, 0.08, 0.55), 6)
		var col := Color(0.08, 0.06, 0.02) if on else Color.WHITE
		_text(Vector2(r.position.x + 10 * u, r.position.y + 23 * u), "%d" % (i + 1), 15, col if on else Color(1, 0.8, 0.45))
		_text(Vector2(r.position.x + 36 * u, r.position.y + 23 * u), sl["n"], 15, col)
		var ammo_t := "∞" if game.infinite_ammo(p) else str(p.ammo[i])
		if p.cat == "inf" and Wi.has("mag") and not game.infinite_ammo(p):
			ammo_t = "%d / %d" % [p.mag[i], p.ammo[i] - p.mag[i]]
		_text(Vector2(r.end.x - 10 * u, r.position.y + 23 * u), ammo_t, 15, col, HORIZONTAL_ALIGNMENT_RIGHT, -1.0)
		var cdv: float = p.cd.get(sl["w"], 0.0)
		if not Wi["auto"] and cdv > 0.0:
			draw_rect(Rect2(r.position.x, r.end.y - 3 * u, r.size.x * clampf(cdv * Wi["rate"], 0.0, 1.0), 3 * u), COL_ORG)
	var hints: Array
	match p.cat:
		"plane":
			hints = ["W/S — тяга", "Мышь — курс", "ЛКМ — огонь", "ПКМ — приближение", "X — флаеры"]
			if T.get("maneuver", false):
				hints.append("M — СВМ · C/V/B — манёвры")
		"heli":
			hints = ["W/S — скорость", "A/D — высота", "Мышь — курс и прицел", "ЛКМ — огонь", "X — флаеры"]
		"tank":
			hints = ["W/S — ход", "A/D — поворот", "Мышь — башня", "ЛКМ — огонь", "ПКМ — прицел"]
		_:
			hints = ["WASD — ходьба", "Shift — бег", "ЛКМ — огонь", "ПКМ — прицел", "R — перезарядка"]
	hints.append("1-%d / колесо — оружие" % n)
	hints.append("Esc — пауза")
	var y := s.y - 20 * u - hints.size() * 20 * u
	for h in hints:
		_text(Vector2(60 * u, y), h, 13, Color(0.92, 0.95, 1.0, 0.85))
		y += 20 * u
