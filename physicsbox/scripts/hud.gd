class_name Hud
extends Control
## In-game HUD: the aiming dot, the status panel (heart rate, blood,
## consciousness, bottom left), the hotbar, counters, the death and
## fainting overlays and the multitouch controls (floating joystick, look
## area, fire / aim / jump / reload buttons, drone arrows, the list of
## orders).

const JOY_RADIUS := 80.0

var player: Player
var game: Node

## Everything the hotbar can hold; it shows what the player carries
## (weapon menu, ОРУЖИЕ / СНАРЯЖЕНИЕ).
const SLOT_IDS := ["ak74", "svd", "grenade", "fpv"]
const SLOT_KEYS := ["1", "2", "G", "V"]
const SLOT_W := 100.0
const SLOT_H := 66.0
const ECG_N := 110

var _font: Font
var _ammo := 30
var _mag := 30
var _kills := 0
var _tickets := [0, 0]
var _winner := -1
var _icons := {}
var _ecg := PackedFloat32Array()
var _ecg_t := 0.0

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
	for id in SLOT_IDS:
		_icons[id] = load("res://assets/ui/icon_%s.png" % id)
	_ecg.resize(ECG_N)
	player.weapon.ammo_changed.connect(func(a, m):
		_ammo = a
		_mag = m)


func set_stats(kills: int, tickets: Array, winner: int) -> void:
	_kills = kills
	_tickets = tickets
	_winner = winner


## Shows what was shouted (and how it went) for a moment.
func order_feedback(text: String, note: String) -> void:
	_order_text = "«%s»" % text
	_order_note = note
	_order_t = 1.8


## The hotbar's items: indices into SLOT_IDS of what is carried.
func _slots() -> Array[int]:
	var out: Array[int] = []
	for i in SLOT_IDS.size():
		if Settings.carries(SLOT_IDS[i]):
			out.append(i)
	return out


## Hotbar slots: the guns, the grenade, the FPV drone.
func _slot_rects() -> Array[Rect2]:
	var out: Array[Rect2] = []
	var n := _slots().size()
	var gap := 8.0
	var x0 := size.x * 0.5 - (n * SLOT_W + (n - 1) * gap) * 0.5
	for i in n:
		out.append(Rect2(x0 + i * (SLOT_W + gap), size.y - SLOT_H - 12.0, SLOT_W, SLOT_H))
	return out


## Hotbar slot `k` (of the carried items) pressed.
func use_slot(k: int) -> void:
	var i: int = _slots()[k]
	match SLOT_IDS[i]:
		"grenade":
			player.throw_grenade()
		"fpv":
			reset_touches()
			player.launch_drone()
		_:
			player.weapon.toggle(i) # the gun in hands again: put it away


func _buttons() -> Dictionary:
	var s := size
	if player.piloting:
		# flying the drone: it hovers; the arrows fly it (▲ forward where the
		# camera looks, ▼ back, ◀ ▶ turn), ВЫШЕ / НИЖЕ, the trigger, a way back
		var a := Vector2(s.x - 420, s.y - 200)
		return {
			"fire": {"pos": Vector2(s.x - 150, s.y - 175), "r": 76.0, "text": "ПОДРЫВ"},
			"exit": {"pos": Vector2(s.x - 80, s.y - 430), "r": 40.0, "text": "ВЫХОД"},
			"up": {"pos": a + Vector2(0, -82), "r": 42.0, "text": "▲"},
			"down": {"pos": a + Vector2(0, 82), "r": 42.0, "text": "▼"},
			"left": {"pos": a + Vector2(-82, 0), "r": 42.0, "text": "◀"},
			"right": {"pos": a + Vector2(82, 0), "r": 42.0, "text": "▶"},
			"climb": {"pos": Vector2(s.x - 150, s.y - 365), "r": 40.0, "text": "ВЫШЕ"},
			"sink": {"pos": Vector2(s.x - 250, s.y - 300), "r": 40.0, "text": "НИЖЕ"},
		}
	var aim_on := player.weapon.aiming
	return {
		"fire": {"pos": Vector2(s.x - 170, s.y - 185), "r": 76.0, "text": "ОГОНЬ"},
		"aim": {"pos": Vector2(s.x - 335, s.y - 110), "r": 48.0, "text": "ПРИЦЕЛ" if not aim_on else "[ ПРИЦЕЛ ]"},
		"jump": {"pos": Vector2(s.x - 72, s.y - 345), "r": 44.0, "text": "ПРЫЖОК"},
		"reload": {"pos": Vector2(s.x - 200, s.y - 375), "r": 40.0, "text": "R"},
		"fire_left": {"pos": Vector2(110, s.y - 380), "r": 50.0, "text": "ОГОНЬ"},
		"sprint": {"pos": Vector2(110, s.y - 500), "r": 42.0, "text": "БЕГ"},
		"crouch": {"pos": Vector2(s.x - 62, s.y - 105), "r": 44.0, "text": "ПРИСЕД"},
		"pause": {"pos": Vector2(s.x - 50, 50), "r": 32.0, "text": "II"},
		"weapons": {"pos": Vector2(s.x - 135, 50), "r": 36.0, "text": "ОРУЖ."},
		"orders": {"pos": Vector2(s.x - 222, 50), "r": 36.0, "text": "ПРИКАЗ"},
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
	if not player.piloting:
		var slots := _slot_rects()
		for k in slots.size():
			if slots[k].grow(4).has_point(p):
				use_slot(k)
				return
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
					player.weapon.trigger_held = true
					if key == "fire" and _fire_index == -1:
						_fire_index = i
						_fire_last = p
				"aim":
					player.weapon.set_aiming(not player.weapon.aiming)
				"jump":
					player.jump_queued = true
				"sprint":
					player.sprint = not player.sprint
				"crouch":
					player.set_crouch(not player.crouching)
				"reload":
					player.weapon.reload()
				"pause":
					game.toggle_pause()
				"weapons":
					game.toggle_weapon_menu()
				"orders":
					_orders_open = not _orders_open
				"exit":
					reset_touches()
					player.exit_drone()
			_update_held()
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
		# pushed hard forward, past the ring: run
		player.sprint_stick = v.length() > 1.3 and v.y < -0.75
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
		player.sprint_stick = false
	if i == _look_index:
		_look_index = -1
	if i == _fire_index:
		_fire_index = -1
	for key in _held.keys():
		if _held[key] == i:
			_held.erase(key)
	_update_held()


## Held buttons drive automatic fire and the drone's arrows.
func _update_held() -> void:
	player.weapon.trigger_held = _held.has("fire") or _held.has("fire_left")
	var arrows := Vector2.ZERO
	if _held.has("left"):
		arrows.x -= 1.0
	if _held.has("right"):
		arrows.x += 1.0
	if _held.has("up"):
		arrows.y += 1.0
	if _held.has("down"):
		arrows.y -= 1.0
	player.drone_arrows = arrows
	player.drone_climb = (1.0 if _held.has("climb") else 0.0) - (1.0 if _held.has("sink") else 0.0)


## Drop every touch (used when pausing).
func reset_touches() -> void:
	_joy_index = -1
	_look_index = -1
	_fire_index = -1
	_held.clear()
	if player:
		player.touch_move = Vector2.ZERO
		player.sprint_stick = false
		player.weapon.trigger_held = false
		player.drone_arrows = Vector2.ZERO
		player.drone_climb = 0.0


# ------------------------------------------------------------------ drawing

func _process(delta: float) -> void:
	# ECG trace: one sample every 1/40 s from where the heart is in its beat
	_ecg_t += delta
	while _ecg_t > 0.025:
		_ecg_t -= 0.025
		_ecg = _ecg.slice(1)
		_ecg.append(_ecg_value(player.heart_phase) if player.bpm > 1.0 else randf_range(-0.02, 0.02))
	_order_t = maxf(_order_t - delta, 0.0)
	_order_pressed_t = maxf(_order_pressed_t - delta, 0.0)
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

	# fading out: dark tunnel closing in as blood runs out
	var faint := 1.0 - player.consciousness
	if not player.dead and faint > 0.15:
		var f := (faint - 0.15) / 0.85
		for k in 8:
			var inset := k * 26.0
			draw_rect(Rect2(Vector2(inset, inset), size - Vector2(inset, inset) * 2.0), Color(0, 0, 0, 0.11 * f), false, 26.0)
		draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.3 * f * (0.8 + 0.2 * sin(Time.get_ticks_msec() * 0.004))))
	if not player.dead and player.hurt_flash > 0.0:
		var f := player.hurt_flash
		for k in 6: # red vignette: bands darker towards the edges
			var inset := k * 18.0
			draw_rect(Rect2(Vector2(inset, inset), size - Vector2(inset, inset) * 2.0), Color(0.8, 0.0, 0.0, 0.07 * f), false, 18.0)

	if player.weapon.scoped() and not player.piloting and not player.dead:
		_draw_scope(player.weapon.current.def.scope)
	# a small white dot for shots from the hip (no scope)
	if aim < 0.6 and not player.piloting and not player.dead:
		var a := 1.0 - aim / 0.6
		draw_circle(c, 3.0, Color(0, 0, 0, 0.45 * a))
		draw_circle(c, 2.0, Color(1, 1, 1, 0.95 * a))

	# counters
	_text(Vector2(24, 44), "УБИЙСТВ: %d" % _kills, 26, Color(1, 1, 1, 0.9))
	_draw_score()
	if Player.immortal:
		_text(Vector2(24, 76), "БЕССМЕРТИЕ", 20, Color(0.5, 1, 0.6, 0.9))
	# the last order shouted
	if _order_t > 0.0:
		var a := clampf(_order_t / 0.4, 0.0, 1.0)
		var w := _font.get_string_size(_order_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 34).x
		_text(Vector2(c.x - w * 0.5, 150), _order_text, 34, Color(1, 0.85, 0.35, a))
		if _order_note != "":
			var nw := _font.get_string_size(_order_note, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
			_text(Vector2(c.x - nw * 0.5, 182), _order_note, 22, Color(1, 1, 1, 0.75 * a))
	if Settings.show_fps:
		_text(Vector2(24, 104), "FPS %d" % Engine.get_frames_per_second(), 20, Color(0.6, 1, 0.6, 0.9))
	_draw_status()
	if not player.piloting:
		_draw_hotbar()
		_draw_stamina()
	if player.weapon.reloading:
		var t := "ПЕРЕЗАРЯДКА"
		_text(Vector2(c.x - _font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x * 0.5, size.y - SLOT_H - 30), t, 24, Color(1, 0.85, 0.4, 0.95))
	if player.dead:
		_draw_death()
		return
	if not player.touch_mode:
		_text(Vector2(24, 132), "WASD ход · Shift бег · C присед · ЛКМ огонь · ПКМ прицел/оптика · R перезарядка · 1 АК, 2 СВД · H убрать оружие · G граната · V FPV · B меню · Esc пауза", 16, Color(1, 1, 1, 0.5))
		_text(Vector2(24, 154), "Дрон: висит сам; ↑ вперёд, ↓ назад, ← → поворот, E выше, Q ниже, мышь — камера · Приказы: 4–9, 0, −", 16, Color(1, 1, 1, 0.5))
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
	var base := _joy_origin if _joy_index != -1 else Vector2(420, size.y - 230)
	var knob := _joy_pos if _joy_index != -1 else base
	knob = base + (knob - base).limit_length(JOY_RADIUS)
	draw_circle(base, JOY_RADIUS, Color(0, 0, 0, 0.18))
	draw_arc(base, JOY_RADIUS, 0, TAU, 48, Color(1, 1, 1, 0.35), 2.0, true)
	draw_circle(knob, 34, Color(1, 1, 1, 0.35 if _joy_index != -1 else 0.2))

	# buttons
	var buttons := _buttons()
	for key in buttons:
		var b: Dictionary = buttons[key]
		var held: bool = _held.has(key) or (key == "aim" and player.weapon.aiming) or (key == "orders" and _orders_open) \
				or (key == "sprint" and (player.sprint or player.sprinting)) or (key == "crouch" and player.crouching)
		var fill := Color(0.75, 0.05, 0.08, 0.45) if held else Color(0, 0, 0, 0.25)
		if key == "fire":
			fill = Color(0.75, 0.05, 0.08, 0.55 if held else 0.3)
		draw_circle(b.pos, b.r, fill)
		draw_arc(b.pos, b.r, 0, TAU, 48, Color(1, 1, 1, 0.5), 2.0, true)
		var fs := 22 if b.r > 45 else 18
		if key in ["pause", "reload", "up", "down", "left", "right"]:
			fs = 26
		elif key == "crouch":
			fs = 15
		var w := _font.get_string_size(b.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(_font, b.pos + Vector2(-w * 0.5, fs * 0.35), b.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.85))


## Looking through the scope: black all round the eyepiece, a dark rim and
## the PSO-1 reticle (chevrons, drop marks, rangefinder).
func _draw_scope(kind: String) -> void:
	var c := size * 0.5 + player.scope_shift * size.y
	var r := size.y * 0.47
	var ink := Color(0.02, 0.02, 0.02, 0.95)
	# outside the eyepiece: black
	draw_arc(c, r + size.x * 0.5, 0, TAU, 96, Color(0, 0, 0), size.x, false)
	for k in 6:
		draw_arc(c, r - k * 7.0, 0, TAU, 96, Color(0, 0, 0, 0.32 - k * 0.05), 8.0, true)
	var u := r / 10.0 # reticle unit
	var o := size * 0.5 # the reticle stays on the line of the bore
	if kind == "pso":
		var red := Color(0.85, 0.08, 0.05, 0.95)
		for k in 4: # the aiming chevron and three below it (300..1000 m)
			var p := o + Vector2(0, k * u * 1.0)
			var w := u * (0.55 if k == 0 else 0.4)
			draw_polyline(PackedVector2Array([p + Vector2(-w, w * 0.9), p, p + Vector2(w, w * 0.9)]), red if k == 0 else ink, 2.0, true)
		draw_line(o + Vector2(-r * 0.93, 0), o + Vector2(-u * 1.2, 0), ink, 2.0)
		draw_line(o + Vector2(u * 1.2, 0), o + Vector2(r * 0.93, 0), ink, 2.0)
		for k in range(1, 11): # windage marks
			var h := u * (0.45 if k % 5 == 0 else 0.25)
			for sgn in [-1.0, 1.0]:
				var x: float = o.x + sgn * (u * 1.2 + k * u * 0.7)
				draw_line(Vector2(x, o.y), Vector2(x, o.y + h), ink, 1.5)
		# rangefinder: the curve fitted to a 1.7 m man
		var pts := PackedVector2Array()
		for k in 9:
			var x := o.x - u * 7.2 + k * u * 0.8
			pts.append(Vector2(x, o.y + u * 2.4 + u * 1.7 * pow(k / 8.0, 1.6)))
		draw_polyline(pts, ink, 1.5, true)
		draw_line(Vector2(o.x - u * 7.2, o.y + u * 4.1), Vector2(o.x - u * 0.8, o.y + u * 4.1), ink, 1.5)
		for k in [2, 4, 6, 8, 10]:
			draw_string(_font, Vector2(o.x - u * 7.4 + (k - 2) * u * 0.8, o.y + u * 2.2), str(k), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, ink)


## ECG shape over one beat (phase 0..1): P wave, QRS spike, T wave.
func _ecg_value(ph: float) -> float:
	var v := 0.0
	v += 0.12 * exp(-pow((ph - 0.06) / 0.025, 2.0))
	v -= 0.12 * exp(-pow((ph - 0.135) / 0.008, 2.0))
	v += 1.0 * exp(-pow((ph - 0.15) / 0.01, 2.0))
	v -= 0.25 * exp(-pow((ph - 0.17) / 0.01, 2.0))
	v += 0.22 * exp(-pow((ph - 0.36) / 0.045, 2.0))
	return v


## Bottom-left panel like a soldier's vitals: state, heart rate (pulsing
## heart and an ECG trace), blood volume, consciousness.
func _draw_status() -> void:
	var p := player
	var w := 340.0
	var h := 132.0
	var o := Vector2(14, size.y - h - 14)
	draw_rect(Rect2(o, Vector2(w, h)), Color(0.04, 0.045, 0.05, 0.72))
	draw_rect(Rect2(o, Vector2(w, h)), Color(1, 1, 1, 0.08), false, 1.0)
	var state := "Боеспособен"
	var scol := Color(0.92, 0.95, 0.92)
	if p.dead:
		state = "Погиб"
		scol = Color(1, 0.3, 0.25)
	elif Player.immortal:
		state = "Бессмертие"
		scol = Color(0.5, 1, 0.6)
	elif p.consciousness < 0.35:
		state = "Теряет сознание"
		scol = Color(1, 0.45, 0.3)
	elif p.hits >= 3:
		state = "Тяжело ранен (%d)" % p.hits
		scol = Color(1, 0.55, 0.35)
	elif p.hits > 0:
		state = "Ранен (%d)" % p.hits
		scol = Color(1, 0.85, 0.45)
	# person icon
	var pi := o + Vector2(22, 24)
	draw_circle(pi + Vector2(0, -5), 5.0, scol)
	draw_rect(Rect2(pi + Vector2(-8, 2), Vector2(16, 8)), scol)
	draw_string(_font, o + Vector2(40, 31), state, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, scol)
	# ECG trace in the top right corner of the panel
	var ex := o.x + w - 128.0
	var ey := o.y + 22.0
	var pts := PackedVector2Array()
	for i in ECG_N:
		pts.append(Vector2(ex + i * (120.0 / ECG_N), ey - _ecg[i] * 15.0))
	draw_polyline(pts, Color(0.35, 0.95, 0.5, 0.9), 1.6, true)
	var rows := [
		["heart", "%d уд/мин" % int(round(p.bpm)), clampf(p.bpm / 180.0, 0.0, 1.0), Color(0.36, 0.86, 0.45)],
		["blood", "%d мл" % int(round(p.blood)), clampf(p.blood / Player.BLOOD_FULL, 0.0, 1.0), Color(0.86, 0.16, 0.16)],
		["eye", "%d%%" % int(round(p.consciousness * 100.0)), p.consciousness, Color(0.45, 0.65, 1.0)],
	]
	for k in rows.size():
		var r: Array = rows[k]
		var y := o.y + 58.0 + k * 26.0
		var ic := Vector2(o.x + 22, y - 6)
		var col: Color = r[3]
		match r[0]:
			"heart":
				var beat := 1.0 + 0.3 * exp(-p.heart_phase * 9.0) if p.bpm > 1.0 else 1.0
				var hs := 6.0 * beat
				draw_circle(ic + Vector2(-hs * 0.5, -hs * 0.3), hs * 0.55, Color(0.9, 0.2, 0.22))
				draw_circle(ic + Vector2(hs * 0.5, -hs * 0.3), hs * 0.55, Color(0.9, 0.2, 0.22))
				draw_colored_polygon(PackedVector2Array([ic + Vector2(-hs * 1.05, -hs * 0.1), ic + Vector2(hs * 1.05, -hs * 0.1), ic + Vector2(0, hs * 1.1)]), Color(0.9, 0.2, 0.22))
			"blood":
				draw_circle(ic + Vector2(0, 2), 5.0, Color(0.85, 0.12, 0.12))
				draw_colored_polygon(PackedVector2Array([ic + Vector2(-4.6, 0.5), ic + Vector2(4.6, 0.5), ic + Vector2(0, -8)]), Color(0.85, 0.12, 0.12))
			"eye":
				draw_arc(ic, 7.0, PI * 1.15, PI * 1.85, 10, Color(0.85, 0.9, 1.0), 2.0, true)
				draw_arc(ic + Vector2(0, -6), 7.0, PI * 0.15, PI * 0.85, 10, Color(0.85, 0.9, 1.0), 2.0, true)
				draw_circle(ic + Vector2(0, -3), 2.6, Color(0.85, 0.9, 1.0))
		draw_string(_font, Vector2(o.x + 40, y), r[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color(0.95, 0.95, 0.95))
		var bx := o.x + 150.0
		var bw := w - 166.0
		draw_rect(Rect2(bx, y - 9, bw, 6), Color(1, 1, 1, 0.12))
		draw_rect(Rect2(bx, y - 9, bw * float(r[2]), 6), col)


## Hotbar: the guns carried, grenades, drones; the gun in hands is outlined
## (none when it is put away).
func _draw_hotbar() -> void:
	var slots := _slot_rects()
	var items := _slots()
	var held := -1 if player.weapon.holstered else player.weapon.slots.find(player.weapon.current)
	var counts := []
	for k in player.weapon.slots.size():
		counts.append("%d" % (_ammo if held == k else player.weapon.slots[k].ammo))
	counts += ["×%d" % player.grenades, "×%d" % player.drones]
	for k in slots.size():
		var i: int = items[k]
		var r: Rect2 = slots[k]
		var on := i == held
		draw_rect(r, Color(0.05, 0.05, 0.06, 0.7 if on else 0.5))
		draw_rect(r, Color(1, 0.8, 0.3, 0.95) if on else Color(1, 1, 1, 0.25), false, 2.0 if on else 1.0)
		var tex: Texture2D = _icons[SLOT_IDS[i]]
		var tr := r.grow(-6)
		tr.size.y -= 12
		var ts := tex.get_size()
		var sc := minf(tr.size.x / ts.x, tr.size.y / ts.y)
		var dst := Rect2(tr.get_center() - ts * sc * 0.5, ts * sc)
		var empty: bool = (SLOT_IDS[i] == "grenade" and player.grenades == 0) or (SLOT_IDS[i] == "fpv" and player.drones == 0)
		draw_texture_rect(tex, dst, false, Color(1, 1, 1, 0.35 if empty else 1.0))
		draw_string(_font, r.position + Vector2(5, 15), SLOT_KEYS[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 0.6))
		var cnt: String = counts[i]
		var cw := _font.get_string_size(cnt, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
		draw_string(_font, r.end - Vector2(cw + 6, 6), cnt, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 1, 1, 0.92))


## Breath for running: a thin bar over the hotbar while it is not full.
func _draw_stamina() -> void:
	if player.stamina >= 0.999:
		return
	var slots := _slot_rects()
	if slots.is_empty():
		return
	var x0 := slots[0].position.x
	var w := slots[slots.size() - 1].end.x - x0
	var y := slots[0].position.y - 10.0
	draw_rect(Rect2(x0, y, w, 4), Color(0, 0, 0, 0.5))
	var col := Color(0.95, 0.85, 0.3, 0.9) if player.stamina > 0.25 else Color(1, 0.35, 0.25, 0.9)
	draw_rect(Rect2(x0, y, w * player.stamina, 4), col)


## Dying: ringing ears, the picture goes black round a white point that
## shrinks and goes out.
func _draw_death() -> void:
	var t := player.death_t
	var c := size * 0.5
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.25, 0.0, 0.0, clampf(0.5 - t, 0.0, 0.5)))
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, clampf((t - 0.15) / 1.2, 0.0, 1.0)))
	var dot := clampf(1.0 - (t - 1.2) / 3.0, 0.0, 1.0)
	if t > 0.4 and dot > 0.0:
		var r := lerpf(3.0, 26.0, dot * dot)
		for k in 4:
			draw_circle(c, r * (2.6 - k * 0.5), Color(1, 1, 1, 0.06 * dot))
		draw_circle(c, r, Color(1, 1, 1, dot))
	if t > 4.2:
		var a := clampf((t - 4.2) / 0.8, 0.0, 0.8)
		var txt := "ВЫ ПОГИБЛИ"
		_text(Vector2(c.x - _font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 30).x * 0.5, c.y + 60), txt, 30, Color(0.8, 0.8, 0.8, a))


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
	var bat := int(d.battery / d.battery_max * 100.0)
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
	var t2 := "ДЖОЙСТИК: вперёд — быстрее, назад — медленнее · СТРЕЛКИ или свайп — курс и высота · ПОДРЫВ"
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
