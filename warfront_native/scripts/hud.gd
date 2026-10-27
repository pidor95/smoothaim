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
	btn["thr"] = {"rect": Rect2(26 * u, s.y * 0.2, 74 * u, s.y * 0.52), "round": false}
	if cat == "heli":
		btn["a"] = {"rect": _circ(Vector2(175 * u, s.y - 235 * u), 50 * u), "round": true}
		btn["b"] = {"rect": _circ(Vector2(175 * u, s.y - 115 * u), 50 * u), "round": true}
	elif cat == "tank":
		btn["a"] = {"rect": _circ(Vector2(175 * u, s.y - 105 * u), 52 * u), "round": true}
		btn["b"] = {"rect": _circ(Vector2(295 * u, s.y - 105 * u), 52 * u), "round": true}
	btn["fire"] = {"rect": _circ(Vector2(s.x - 150 * u, s.y - 165 * u), 88 * u), "round": true}
	if cat != "tank":
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
				"thr":
					_set_thr(d.position.y)
			tr["pos"] = d.position
		get_viewport().set_input_as_handled()


func _press(i: int, p: Vector2) -> void:
	var c: Dictionary = game.ctrl
	var role := "look"
	for k in btn:
		if not _hit(k, p):
			continue
		if k.begins_with("slot"):
			game.select_slot(int(k.substr(4)))
			role = "none"
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
		"fire": c["fire"] = false
		"flare": c["flare"] = false
		"a", "b": c[role] = false


func _set_thr(y: float) -> void:
	var r: Rect2 = btn["thr"]["rect"]
	var v := clampf(1.0 - (y - r.position.y) / r.size.y, 0.0, 1.0)
	if game.player and game.player.cat == "tank" and absf(v - 0.5) < 0.06:
		v = 0.5
	game.ctrl["thr"] = v


# ---------------------------------------------------------------- drawing helpers
func _text(p: Vector2, t: String, sz: float, col := Color.WHITE, align := HORIZONTAL_ALIGNMENT_LEFT, wdt := -1.0) -> void:
	var fs := int(sz * u * 1.3)
	if align == HORIZONTAL_ALIGNMENT_CENTER and wdt < 0.0:
		var w := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		p.x -= w / 2.0
		align = HORIZONTAL_ALIGNMENT_LEFT
	draw_string_outline(font, p, t, align, wdt, fs, int(5 * u), Color(0, 0, 0, 0.6))
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
	# labels over other vehicles
	for v in game.vehicles:
		if v == p or v.dead:
			continue
		var sp = _screen(v.pos + Vector3(0, v.T["r"] + 2.0, 0))
		var d: float = v.pos.distance_to(p.pos)
		if sp == null or d > 9000.0:
			continue
		var col := COL_BLU if v.team == p.team else COL_RED
		var txt: String = ("%s " % v.nick if d < 3000.0 else "") + "%.1f км" % (d / 1000.0)
		_text(sp, txt, 15, col, HORIZONTAL_ALIGNMENT_CENTER)
		draw_line(sp + Vector2(-5, 6) * u, sp + Vector2(0, 12) * u, col, 2.0 * u)
		draw_line(sp + Vector2(5, 6) * u, sp + Vector2(0, 12) * u, col, 2.0 * u)
	# crosshair
	var ctr := s / 2.0
	var ch := Color(1, 1, 1, 0.85)
	for a in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
		draw_line(ctr + a * 6 * u, ctr + a * 16 * u, ch, 2.0 * u)
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
		elif not W.get("homing", false) and wname != "flare" and wname != "smoke":
			var piv: Vector3 = p.pos + Vector3(0, 2.4, 0) if p.cat == "tank" else p.chin_pos()
			var dir: Vector3 = p.fixed_dir if wname == "rkt" else p.aim_dir
			var dist := maxf(50.0, piv.distance_to(p.inp["aim_point"]))
			var gp = _screen(piv + dir * dist)
			if gp != null:
				draw_arc(gp, 10 * u, 0, TAU, 20, COL_ORG, 2.0 * u)
				draw_circle(gp, 2.0 * u, COL_ORG)
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
	if p.cat != "tank":
		st += "  ВЫС %d м" % alt
	_text(Vector2(28 * u, 88 * u), st, 16, Color(0.9, 0.95, 1.0))
	# top-right: score, kill feed, radar
	_text(Vector2(s.x - 470 * u, 40 * u), "Уничтожено: %d  ·  Потери: %d" % [game.kills, game.deaths], 16)
	var y := 66.0
	for k in game.killfeed:
		_text(Vector2(s.x - 470 * u, y * u), k["txt"], 14, Color(1, 1, 1, 0.9))
		y += 20.0
	_radar(Rect2(s.x - 188 * u, 76 * u, 170 * u, 170 * u))
	_button("pause", "II")
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
	# throttle
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
	# buttons
	_button("fire", "ОГОНЬ", c["fire"])
	_button("flare", "ФЛАЕРЫ", c["flare"])
	_button("zoom", "ZOOM", c["zoom"])
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
		var ammo_t := "∞" if game.infinite_ammo(p) else str(p.ammo[i])
		_button("slot%d" % i, "%d  %s" % [i + 1, sl["n"]], i == p.slot, ammo_t)
		var Wi: Dictionary = D.WEAP[sl["w"]]
		var cdv: float = p.cd.get(sl["w"], 0.0)
		if not Wi["auto"] and cdv > 0.0:
			var br: Rect2 = btn["slot%d" % i]["rect"]
			draw_rect(Rect2(br.position.x, br.end.y - 5 * u, br.size.x * clampf(cdv * Wi["rate"], 0.0, 1.0), 5 * u), COL_ORG)


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
	draw_colored_polygon(PackedVector2Array([cc + Vector2(0, -7) * u, cc + Vector2(-5, 5) * u, cc + Vector2(5, 5) * u]), COL_GRN)
