class_name Hud
extends Control
## In-game HUD: crosshair, hit markers, counters and the multitouch controls
## (floating joystick, look area, fire / aim / jump / reload buttons, the
## list of orders).

const JOY_RADIUS := 80.0

var player: Player
var game: Node

var _font: Font
var _hit_t := 0.0
var _hit_kind := 0
var _ammo := 8
var _mag := 7
var _kills := 0
var _tickets := [0, 0]
var _winner := -1
var _slowmo := false
var _fire_flash := 0.0

var _joy_index := -1
var _joy_origin := Vector2.ZERO
var _joy_pos := Vector2.ZERO
var _look_index := -1
var _look_last := Vector2.ZERO
var _fire_index := -1
var _fire_last := Vector2.ZERO
var _held := {} # button key -> touch index
var _orders_open := false
var _order_text := ""
var _order_note := ""
var _order_t := 0.0
var _order_pressed := -1
var _order_pressed_t := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = ThemeDB.fallback_font
	player.weapon.hit_confirmed.connect(_on_hit)
	player.weapon.ammo_changed.connect(func(a, m):
		_ammo = a
		_mag = m)
	player.weapon.fired.connect(func(): _fire_flash = 1.0)


func set_stats(kills: int, tickets: Array, winner: int, slowmo: bool) -> void:
	_kills = kills
	_tickets = tickets
	_winner = winner
	_slowmo = slowmo


## Shows what was shouted (and how it went) for a moment.
func order_feedback(text: String, note: String) -> void:
	_order_text = "«%s»" % text
	_order_note = note
	_order_t = 1.8


func _on_hit(kind: int) -> void:
	_hit_kind = kind
	_hit_t = 0.28 if kind == 0 else 0.45



func _buttons() -> Dictionary:
	var s := size
	if player.piloting:
		# flying the drone: sticks, the trigger and a way back
		return {
			"fire": {"pos": Vector2(s.x - 170, s.y - 175), "r": 76.0, "text": "ПОДРЫВ"},
			"fpv": {"pos": Vector2(s.x - 80, s.y - 430), "r": 40.0, "text": "ВЫХОД"},
		}
	var aim_on := player.weapon.aiming
	return {
		"nade": {"pos": Vector2(s.x - 430, s.y - 170), "r": 40.0, "text": "ГРАНАТА %d" % player.grenades},
		"fpv": {"pos": Vector2(s.x - 80, s.y - 430), "r": 40.0, "text": "FPV %d" % player.drones},
		"fire": {"pos": Vector2(s.x - 170, s.y - 175), "r": 76.0, "text": "ОГОНЬ"},
		"aim": {"pos": Vector2(s.x - 335, s.y - 92), "r": 48.0, "text": "ПРИЦЕЛ" if not aim_on else "[ ПРИЦЕЛ ]"},
		"jump": {"pos": Vector2(s.x - 72, s.y - 335), "r": 44.0, "text": "ПРЫЖОК"},
		"reload": {"pos": Vector2(s.x - 200, s.y - 365), "r": 40.0, "text": "R"},
		"fire_left": {"pos": Vector2(110, s.y - 360), "r": 50.0, "text": "ОГОНЬ"},
		"pause": {"pos": Vector2(s.x - 50, 50), "r": 32.0, "text": "II"},
		"spawn": {"pos": Vector2(s.x - 130, 50), "r": 32.0, "text": "+"},
		"slowmo": {"pos": Vector2(s.x - 210, 50), "r": 32.0, "text": "x0.3"},
		"ai": {"pos": Vector2(s.x - 290, 50), "r": 32.0, "text": "ИИ"},
		"weapons": {"pos": Vector2(s.x - 375, 50), "r": 36.0, "text": "ОРУЖ."},
		"orders": {"pos": Vector2(s.x - 462, 50), "r": 36.0, "text": "ПРИКАЗ"},
		"switch": {"pos": Vector2(s.x - 320, s.y - 250), "r": 42.0, "text": "СМЕНА"},
	}


# ------------------------------------------------------------------ touch input

func _input(event: InputEvent) -> void:
	if player == null or not player.touch_mode or get_tree().paused:
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			_touch_down(event.index, event.position)
		else:
			_touch_up(event.index)
	elif event is InputEventScreenDrag:
		_touch_drag(event.index, event.position)


## Pills of the order list (opened with the ПРИКАЗ button).
func _order_rects() -> Array[Rect2]:
	var out: Array[Rect2] = []
	var n := Npc.ORDERS.size()
	var h := clampf((size.y - 400.0) / n, 36.0, 52.0)
	for i in n:
		out.append(Rect2(size.x - 595, 96 + i * h, 230, h - 6))
	return out


func _touch_down(i: int, p: Vector2) -> void:
	if _orders_open:
		var rects := _order_rects()
		for k in rects.size():
			if rects[k].grow(4).has_point(p):
				game.give_order(k)
				_order_pressed = k
				_order_pressed_t = 0.2
				return
	var buttons := _buttons()
	for key in buttons:
		var b: Dictionary = buttons[key]
		if p.distance_to(b.pos) <= b.r * 1.2:
			_held[key] = i
			match key:
				"fire", "fire_left":
					player.weapon.trigger()
					if key == "fire" and _fire_index == -1:
						_fire_index = i
						_fire_last = p
				"aim":
					player.weapon.set_aiming(not player.weapon.aiming)
				"jump":
					player.jump_queued = true
				"reload":
					player.weapon.reload()
				"pause":
					game.toggle_pause()
				"spawn":
					game.spawn_in_front()
				"slowmo":
					game.toggle_slowmo()
				"ai":
					game.toggle_ai()
				"switch":
					player.weapon.next_weapon()
				"weapons":
					game.toggle_weapon_menu()
				"orders":
					_orders_open = not _orders_open
				"nade":
					player.throw_grenade()
				"fpv":
					reset_touches()
					player.launch_drone()
			return
	if p.x < size.x * 0.42 and p.y > size.y * 0.25 and _joy_index == -1:
		_joy_index = i
		_joy_origin = p
		_joy_pos = p
		return
	if _look_index == -1:
		_look_index = i
		_look_last = p


func _touch_drag(i: int, p: Vector2) -> void:
	if i == _joy_index:
		_joy_pos = p
		var v := (p - _joy_origin) / JOY_RADIUS
		player.touch_move = v.limit_length(1.0)
	elif i == _look_index:
		player.look(p - _look_last)
		_look_last = p
	elif i == _fire_index:
		player.look(p - _fire_last)
		_fire_last = p


func _touch_up(i: int) -> void:
	if i == _joy_index:
		_joy_index = -1
		player.touch_move = Vector2.ZERO
	if i == _look_index:
		_look_index = -1
	if i == _fire_index:
		_fire_index = -1
	for key in _held.keys():
		if _held[key] == i:
			_held.erase(key)


## Drop every touch (used when pausing).
func reset_touches() -> void:
	_joy_index = -1
	_look_index = -1
	_fire_index = -1
	_held.clear()
	if player:
		player.touch_move = Vector2.ZERO


# ------------------------------------------------------------------ drawing

func _process(delta: float) -> void:
	_hit_t = maxf(_hit_t - delta, 0.0)
	_order_t = maxf(_order_t - delta, 0.0)
	_order_pressed_t = maxf(_order_pressed_t - delta, 0.0)
	_fire_flash = maxf(_fire_flash - delta * 6.0, 0.0)
	queue_redraw()


func _draw() -> void:
	if player == null:
		return
	var c := size * 0.5
	var aim := player.weapon.aim_t

	if player.piloting or player.signal_lost > 0.0:
		_draw_fpv()
	else:
		_draw_grenade_warning()

	# taking fire / down
	if player.dead:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.35, 0.0, 0.0, 0.55))
		var t := "ВЫ ПОГИБЛИ"
		var tw := _font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 44).x
		_text(Vector2(c.x - tw * 0.5, c.y - 10), t, 44, Color(1, 0.85, 0.85, 0.95))
	elif player.hurt_flash > 0.0:
		var f := player.hurt_flash
		for k in 6: # red vignette: bands darker towards the edges
			var inset := k * 18.0
			draw_rect(Rect2(Vector2(inset, inset), size - Vector2(inset, inset) * 2.0), Color(0.8, 0.0, 0.0, 0.07 * f), false, 18.0)

	# crosshair
	if aim < 0.6 and not player.piloting:
		var a := 1.0 - aim / 0.6
		var spread := 7.0 + _fire_flash * 10.0 + Vector2(player.velocity.x, player.velocity.z).length() * 2.0
		var col := Color(1, 1, 1, 0.9 * a)
		for d in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
			_line_outlined(c + d * spread, c + d * (spread + 9.0), col, 2.0)
		draw_circle(c, 1.5, Color(1, 1, 1, 0.8 * a))

	# hit marker
	if _hit_t > 0.0:
		var t := _hit_t / (0.28 if _hit_kind == 0 else 0.45)
		var col := Color(1, 1, 1, t) if _hit_kind == 0 else Color(1, 0.15, 0.1, t)
		var g := 7.0 + (1.0 - t) * 4.0
		var l := 9.0 if _hit_kind == 0 else 13.0
		for d in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			var n: Vector2 = d.normalized()
			_line_outlined(c + n * g, c + n * (g + l), col, 2.5)

	# counters
	_text(Vector2(24, 44), "УБИЙСТВ: %d" % _kills, 28, Color(1, 1, 1, 0.9))
	_draw_score()
	var status_y := 108.0
	if _slowmo:
		_text(Vector2(24, status_y), "ЗАМЕДЛЕНИЕ", 22, Color(1, 0.35, 0.3, 0.9))
		status_y += 28.0
	if not Npc.ai_enabled:
		_text(Vector2(24, status_y), "ИИ ОТКЛЮЧЁН", 22, Color(1, 0.75, 0.3, 0.9))
		status_y += 28.0
	if Player.immortal:
		_text(Vector2(24, status_y), "БЕССМЕРТИЕ", 22, Color(0.5, 1, 0.6, 0.9))
		status_y += 28.0
	# the last order shouted
	if _order_t > 0.0:
		var a := clampf(_order_t / 0.4, 0.0, 1.0)
		var w := _font.get_string_size(_order_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 34).x
		_text(Vector2(c.x - w * 0.5, 150), _order_text, 34, Color(1, 0.85, 0.35, a))
		if _order_note != "":
			var nw := _font.get_string_size(_order_note, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
			_text(Vector2(c.x - nw * 0.5, 182), _order_note, 22, Color(1, 1, 1, 0.75 * a))
	if Settings.show_fps:
		_text(Vector2(24, size.y - 20), "FPS %d" % Engine.get_frames_per_second(), 20, Color(0.6, 1, 0.6, 0.9))
	var ammo_text := "%s   %d / ∞" % [player.weapon.weapon_name(), _ammo] if not player.weapon.reloading else "ПЕРЕЗАРЯДКА"
	var ammo_pos := Vector2(size.x * 0.5 - 110, size.y - 28)
	if not player.touch_mode:
		ammo_pos = Vector2(size.x - 220, size.y - 30)
	_text(ammo_pos, ammo_text, 30, Color(1, 1, 1, 0.9) if _ammo > 0 else Color(1, 0.3, 0.25, 0.95))
	if not Player.immortal:
		var hp_pos := Vector2(size.x * 0.5 - 330, size.y - 28) if player.touch_mode else Vector2(size.x - 220, size.y - 66)
		var hp := int(ceil(player.health))
		_text(hp_pos, "ЗДОРОВЬЕ %d" % hp, 26, Color(1, 1, 1, 0.85) if hp > 35 else Color(1, 0.25, 0.2, 0.95))
	if not player.touch_mode:
		_text(Vector2(24, size.y - 50), "WASD — ходьба, ЛКМ — огонь, ПКМ — прицел, R — перезарядка", 18, Color(1, 1, 1, 0.55))
		_text(Vector2(24, size.y - 26), "1/2/F — оружие, G — граната, V — FPV-дрон (ещё раз — подрыв), B — меню оружия, E — враг, Q — замедление, T — ИИ, Esc — пауза", 18, Color(1, 1, 1, 0.55))
		_text(Vector2(24, size.y - 74), "Приказы: 3 стоять, 4 руки вверх, 5 на колени, 6 брось оружие, 7 ко мне, 8 проваливай, 9 вольно, 0 застрелись", 18, Color(1, 1, 1, 0.55))
		return

	# order list
	if _orders_open:
		var rects := _order_rects()
		for k in rects.size():
			var r: Rect2 = rects[k]
			var hot := k == _order_pressed and _order_pressed_t > 0.0
			draw_rect(r, Color(0.75, 0.05, 0.08, 0.6) if hot else Color(0, 0, 0, 0.4))
			draw_rect(r, Color(1, 1, 1, 0.45), false, 2.0)
			var label: String = Npc.ORDERS[k][1]
			var fs := 20
			var lw := _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			draw_string(_font, r.get_center() + Vector2(-lw * 0.5, fs * 0.35), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.9))

	# joystick
	var base := _joy_origin if _joy_index != -1 else Vector2(190, size.y - 175)
	var knob := _joy_pos if _joy_index != -1 else base
	knob = base + (knob - base).limit_length(JOY_RADIUS)
	draw_circle(base, JOY_RADIUS, Color(0, 0, 0, 0.18))
	draw_arc(base, JOY_RADIUS, 0, TAU, 48, Color(1, 1, 1, 0.35), 2.0, true)
	draw_circle(knob, 34, Color(1, 1, 1, 0.35 if _joy_index != -1 else 0.2))

	# buttons
	var buttons := _buttons()
	for key in buttons:
		var b: Dictionary = buttons[key]
		var held: bool = _held.has(key) or (key == "aim" and player.weapon.aiming) or (key == "slowmo" and _slowmo) \
				or (key == "ai" and not Npc.ai_enabled) or (key == "orders" and _orders_open)
		var fill := Color(0.75, 0.05, 0.08, 0.45) if held else Color(0, 0, 0, 0.25)
		if key == "fire":
			fill = Color(0.75, 0.05, 0.08, 0.55 if held else 0.3)
		draw_circle(b.pos, b.r, fill)
		draw_arc(b.pos, b.r, 0, TAU, 48, Color(1, 1, 1, 0.5), 2.0, true)
		var fs := 22 if b.r > 45 else 18
		if key in ["pause", "spawn", "slowmo", "reload", "ai"]:
			fs = 26 if b.text.length() <= 2 else 18
		elif key == "nade" or key == "fpv":
			fs = 15
		var w := _font.get_string_size(b.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(_font, b.pos + Vector2(-w * 0.5, fs * 0.35), b.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.85))


## Flying the FPV drone: analog video look (scan lines, noise, dark edges)
## and its on-screen display; static when the link is gone.
func _draw_fpv() -> void:
	var c := size * 0.5
	if player.piloting == null:
		for k in 260:
			var v := randf()
			draw_rect(Rect2(randf() * size.x, randf() * size.y, randf_range(6, 40), randf_range(2, 6)), Color(v, v, v, 0.9))
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.1, 0.1, 0.1, 0.55))
		var t := "НЕТ СИГНАЛА"
		_text(Vector2(c.x - _font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 40).x * 0.5, c.y), t, 40, Color(1, 1, 1))
		return
	var d := player.piloting
	for y in range(0, int(size.y), 4):
		draw_line(Vector2(0, y), Vector2(size.x, y), Color(0, 0, 0, 0.08))
	for k in 40:
		var v := randf()
		draw_rect(Rect2(randf() * size.x, randf() * size.y, randf_range(2, 14), 2), Color(v, v, v, 0.12))
	for k in 5:
		var inset := k * 22.0
		draw_rect(Rect2(Vector2(inset, inset), size - Vector2(inset, inset) * 2.0), Color(0, 0, 0, 0.09), false, 22.0)
	# OSD
	var w := Color(1, 1, 1, 0.9)
	var bat := int(d.battery / FpvDrone.BATTERY * 100.0)
	_text(Vector2(40, 200), "FPV", 24, w)
	_text(Vector2(40, 232), "БАТ %d%%" % bat, 22, w if bat > 25 or int(Time.get_ticks_msec() / 300) % 2 == 0 else Color(1, 0.3, 0.2))
	_text(Vector2(40, 260), "СКОР %d км/ч" % int(d.velocity.length() * 3.6), 22, w)
	_text(Vector2(40, 288), "ВЫС %.0f м" % (d.global_position.y + 0.5), 22, w)
	if int(Time.get_ticks_msec() / 500) % 2 == 0:
		draw_circle(Vector2(size.x - 120, 140), 7, Color(1, 0.1, 0.1))
		_text(Vector2(size.x - 108, 148), "REC", 20, w)
	draw_arc(c, 16, 0, TAU, 24, w, 2.0, true)
	for dir in [Vector2.LEFT, Vector2.RIGHT]:
		draw_line(c + dir * 22, c + dir * 46, w, 2.0)
	var t2 := "ДЖОЙСТИК: вперёд — быстрее, назад — медленнее · свайп — курс · ПОДРЫВ"
	if player.touch_mode:
		draw_string(_font, Vector2(c.x - _font.get_string_size(t2, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x * 0.5, size.y - 18), t2, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 1, 1, 0.6))


## A live enemy grenade close by: a red marker round the crosshair in its direction.
func _draw_grenade_warning() -> void:
	var c := size * 0.5
	for g in get_tree().get_nodes_in_group("grenades"):
		if g.by_player:
			continue
		var to: Vector3 = g.global_position - player.global_position
		if to.length() > 9.0:
			continue
		var local := player.camera.global_basis.inverse() * to
		var ang := atan2(local.x, -local.z)
		var p := c + Vector2(sin(ang), -cos(ang)) * 130.0
		draw_circle(p, 22, Color(0.8, 0.05, 0.05, 0.8))
		var t := "!"
		draw_string(_font, p + Vector2(-5, 10), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color(1, 1, 1))
		_text(p + Vector2(-46, 46), "ГРАНАТА", 18, Color(1, 0.4, 0.3))


## Team score at the top (tickets left on each side), and the round's
## outcome when one side runs out.
func _draw_score() -> void:
	var cx := size.x * 0.4
	var y := 14.0
	var cols := [Color(0.12, 0.3, 0.75, 0.75), Color(0.7, 0.12, 0.1, 0.75)]
	for t in 2:
		var w := 190.0
		var x := cx - w - 4.0 if t == 0 else cx + 4.0
		draw_rect(Rect2(x, y, w, 40), cols[t])
		var name: String = Npc.TEAM_NAMES[t]
		var num := str(_tickets[t])
		var fs := 18
		if t == 0:
			draw_string(_font, Vector2(x + 10, y + 27), name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.95))
			draw_string(_font, Vector2(x + w - 12 - _font.get_string_size(num, HORIZONTAL_ALIGNMENT_LEFT, -1, 28).x, y + 30), num, HORIZONTAL_ALIGNMENT_LEFT, -1, 28, Color(1, 1, 1))
		else:
			draw_string(_font, Vector2(x + 12, y + 30), num, HORIZONTAL_ALIGNMENT_LEFT, -1, 28, Color(1, 1, 1))
			var nw := _font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			draw_string(_font, Vector2(x + w - 10 - nw, y + 27), name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.95))
	if _winner >= 0:
		var t := "ПОБЕДА" if _winner == 0 else "ПОРАЖЕНИЕ"
		var tw := _font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 56).x
		_text(Vector2(size.x * 0.5 - tw * 0.5, size.y * 0.32), t, 56, Color(0.5, 0.75, 1) if _winner == 0 else Color(1, 0.35, 0.3))


func _text(pos: Vector2, text: String, fs: int, col: Color) -> void:
	draw_string_outline(_font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 5, Color(0, 0, 0, 0.5 * col.a))
	draw_string(_font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


func _line_outlined(a: Vector2, b: Vector2, col: Color, w: float) -> void:
	draw_line(a, b, Color(0, 0, 0, col.a * 0.6), w + 2.0, true)
	draw_line(a, b, col, w, true)
