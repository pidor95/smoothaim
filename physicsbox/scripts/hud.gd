class_name Hud
extends Control
## In-game HUD: crosshair, hit markers, counters and the multitouch controls
## (floating joystick, look area, fire / aim / jump / reload buttons).

const JOY_RADIUS := 80.0

var player: Player
var game: Node

var _font: Font
var _hit_t := 0.0
var _hit_kind := 0
var _popup_t := 0.0
var _popup_text := ""
var _ammo := 8
var _mag := 7
var _kills := 0
var _alive := 0
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


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = ThemeDB.fallback_font
	player.weapon.hit_confirmed.connect(_on_hit)
	player.weapon.ammo_changed.connect(func(a, m):
		_ammo = a
		_mag = m)
	player.weapon.fired.connect(func(): _fire_flash = 1.0)


func set_stats(kills: int, alive: int, slowmo: bool) -> void:
	_kills = kills
	_alive = alive
	_slowmo = slowmo


func popup(text: String) -> void:
	_popup_text = text
	_popup_t = 1.2


func _on_hit(kind: int) -> void:
	_hit_kind = kind
	_hit_t = 0.28 if kind == 0 else 0.45
	if kind == 2:
		popup("ХЕДШОТ")
	elif kind == 1:
		popup("УБИТ")


func _buttons() -> Dictionary:
	var s := size
	var aim_on := player.weapon.aiming
	return {
		"fire": {"pos": Vector2(s.x - 170, s.y - 175), "r": 76.0, "text": "ОГОНЬ"},
		"aim": {"pos": Vector2(s.x - 335, s.y - 92), "r": 48.0, "text": "ПРИЦЕЛ" if not aim_on else "[ ПРИЦЕЛ ]"},
		"jump": {"pos": Vector2(s.x - 72, s.y - 335), "r": 44.0, "text": "ПРЫЖОК"},
		"reload": {"pos": Vector2(s.x - 200, s.y - 365), "r": 40.0, "text": "R"},
		"fire_left": {"pos": Vector2(110, s.y - 360), "r": 50.0, "text": "ОГОНЬ"},
		"pause": {"pos": Vector2(s.x - 50, 50), "r": 32.0, "text": "II"},
		"spawn": {"pos": Vector2(s.x - 130, 50), "r": 32.0, "text": "+"},
		"slowmo": {"pos": Vector2(s.x - 210, 50), "r": 32.0, "text": "x0.3"},
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


func _touch_down(i: int, p: Vector2) -> void:
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
	_popup_t = maxf(_popup_t - delta, 0.0)
	_fire_flash = maxf(_fire_flash - delta * 6.0, 0.0)
	queue_redraw()


func _draw() -> void:
	if player == null:
		return
	var c := size * 0.5
	var aim := player.weapon.aim_t

	# crosshair
	if aim < 0.6:
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

	# popup text (HEADSHOT)
	if _popup_t > 0.0:
		var a := clampf(_popup_t / 0.4, 0.0, 1.0)
		var fs := 44
		var w := _font.get_string_size(_popup_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var pos := c + Vector2(-w * 0.5, 90 - (1.2 - _popup_t) * 20.0)
		draw_string_outline(_font, pos, _popup_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 6, Color(0, 0, 0, 0.6 * a))
		draw_string(_font, pos, _popup_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 0.12, 0.08, a))

	# counters
	_text(Vector2(24, 44), "УБИЙСТВ: %d" % _kills, 28, Color(1, 1, 1, 0.9))
	_text(Vector2(24, 78), "МАНЕКЕНОВ: %d" % _alive, 22, Color(1, 1, 1, 0.7))
	if _slowmo:
		_text(Vector2(24, 108), "ЗАМЕДЛЕНИЕ", 22, Color(1, 0.35, 0.3, 0.9))
	if Settings.show_fps:
		_text(Vector2(24, size.y - 20), "FPS %d" % Engine.get_frames_per_second(), 20, Color(0.6, 1, 0.6, 0.9))
	var ammo_text := "%d / ∞" % _ammo if not player.weapon.reloading else "ПЕРЕЗАРЯДКА"
	var ammo_pos := Vector2(size.x * 0.5 - 60, size.y - 28)
	if not player.touch_mode:
		ammo_pos = Vector2(size.x - 220, size.y - 30)
	_text(ammo_pos, ammo_text, 30, Color(1, 1, 1, 0.9) if _ammo > 0 else Color(1, 0.3, 0.25, 0.95))
	if not player.touch_mode:
		_text(Vector2(24, size.y - 50), "WASD — ходьба, ЛКМ — огонь, ПКМ — прицел, R — перезарядка", 18, Color(1, 1, 1, 0.55))
		_text(Vector2(24, size.y - 26), "E — манекен, Q — замедление, Esc — пауза", 18, Color(1, 1, 1, 0.55))
		return

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
		var held: bool = _held.has(key) or (key == "aim" and player.weapon.aiming) or (key == "slowmo" and _slowmo)
		var fill := Color(0.75, 0.05, 0.08, 0.45) if held else Color(0, 0, 0, 0.25)
		if key == "fire":
			fill = Color(0.75, 0.05, 0.08, 0.55 if held else 0.3)
		draw_circle(b.pos, b.r, fill)
		draw_arc(b.pos, b.r, 0, TAU, 48, Color(1, 1, 1, 0.5), 2.0, true)
		var fs := 22 if b.r > 45 else 18
		if key in ["pause", "spawn", "slowmo", "reload"]:
			fs = 26 if b.text.length() <= 2 else 18
		var w := _font.get_string_size(b.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(_font, b.pos + Vector2(-w * 0.5, fs * 0.35), b.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.85))


func _text(pos: Vector2, text: String, fs: int, col: Color) -> void:
	draw_string_outline(_font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 5, Color(0, 0, 0, 0.5 * col.a))
	draw_string(_font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


func _line_outlined(a: Vector2, b: Vector2, col: Color, w: float) -> void:
	draw_line(a, b, Color(0, 0, 0, col.a * 0.6), w + 2.0, true)
	draw_line(a, b, col, w, true)
