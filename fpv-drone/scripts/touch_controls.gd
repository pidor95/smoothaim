extends Control
## On-screen controls with real multitouch. Casual mode: left stick flies
## forward/back and turns, right stick climbs and descends. Acro mode: left
## stick is throttle (stays where released) and yaw, right stick pitch and roll.
## Easy mode: arrow buttons. A swipe on the free part of the screen turns the camera.

signal pause_pressed
signal view_pressed

const BUTTONS := ["fwd", "back", "up", "down"]

var mode: int = 1
## Left stick: x = turn, y = forward (up is positive).
var stick_l := Vector2.ZERO
## Right stick: y = climb (up is positive). x is always 0.
var stick_r := Vector2.ZERO
var buttons := {}

var _touches := {} # touch index -> target name
var _origins := {} # touch index -> stick centre
var _last := {} # touch index -> last position, for camera swipes
var _look := Vector2.ZERO
var _label_font: FontVariation


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_label_font = FontVariation.new()
	_label_font.base_font = load("res://fonts/Exo2.ttf")
	_label_font.variation_opentype = {"wght": 700}
	reset()


func set_mode(m: int) -> void:
	mode = m
	reset()


func reset() -> void:
	_touches.clear()
	_origins.clear()
	_last.clear()
	_look = Vector2.ZERO
	stick_l = Vector2.ZERO
	stick_r = Vector2.ZERO
	for b: String in BUTTONS:
		buttons[b] = false
	queue_redraw()


## Puts the acro throttle stick at a value (0..1), e.g. hover after a respawn.
func set_throttle(value: float) -> void:
	stick_l.y = clampf(value, 0.0, 1.0) * 2.0 - 1.0
	queue_redraw()


func is_down(button: String) -> float:
	return 1.0 if buttons.get(button, false) else 0.0


## Swipe movement since the last call, in canvas pixels.
func consume_look() -> Vector2:
	var v := _look
	_look = Vector2.ZERO
	return v


# --- Layout ------------------------------------------------------------------

## Left and right screen insets (notches, rounded corners) in canvas units.
func _side_insets() -> Vector2:
	var win := DisplayServer.window_get_size()
	if win.x <= 0:
		return Vector2.ZERO
	var safe := DisplayServer.get_display_safe_area()
	var k := size.x / float(win.x)
	return Vector2(maxf(0.0, safe.position.x) * k, maxf(0.0, win.x - safe.end.x) * k)


func _radius() -> float:
	return clampf(size.y * 0.16, 70.0, 125.0)


func _home(left: bool) -> Vector2:
	var r := _radius()
	var ins := _side_insets()
	var y := size.y - r - 46.0
	if left:
		return Vector2(ins.x + r + 70.0, y)
	return Vector2(size.x - ins.y - r - 70.0, y)


func _button_center(b: String) -> Vector2:
	var d := _radius() * 0.62
	match b:
		"fwd":
			return _home(true) + Vector2(0, -d)
		"back":
			return _home(true) + Vector2(0, d)
		"up":
			return _home(false) + Vector2(0, -d)
		"down":
			return _home(false) + Vector2(0, d)
	return Vector2.ZERO


func _button_radius() -> float:
	return _radius() * 0.5


func _pause_center() -> Vector2:
	return Vector2(size.x - _side_insets().y - 56.0, 52.0)


func _view_center() -> Vector2:
	return _pause_center() - Vector2(84.0, 0.0)


# --- Input -------------------------------------------------------------------

func _hit(pos: Vector2) -> String:
	if pos.distance_to(_pause_center()) < 40.0:
		return "pause"
	if pos.distance_to(_view_center()) < 40.0:
		return "view"
	if mode >= 1:
		var zone := _radius() * 1.7
		if pos.distance_to(_home(true)) < zone:
			return "lstick"
		if pos.distance_to(_home(false)) < zone:
			return "rstick"
	else:
		for b: String in BUTTONS:
			if pos.distance_to(_button_center(b)) < _button_radius() * 1.25:
				return b
	return "look"


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event is InputEventScreenTouch:
		var touch := make_input_local(event) as InputEventScreenTouch
		if touch.pressed:
			var target := _hit(touch.position)
			if target == "pause":
				pause_pressed.emit()
			elif target == "view":
				view_pressed.emit()
			else:
				_touches[touch.index] = target
				_last[touch.index] = touch.position
				if target == "lstick" or target == "rstick":
					var home := _home(target == "lstick")
					var fixed := mode == 2 and target == "lstick" # throttle needs a fixed centre
					_origins[touch.index] = home if fixed or touch.position.distance_to(home) < _radius() * 1.2 else touch.position
				_apply(touch.index, touch.position)
		else:
			_release(touch.index)
	elif event is InputEventScreenDrag:
		var drag := make_input_local(event) as InputEventScreenDrag
		if _touches.has(drag.index):
			_apply(drag.index, drag.position)


func _apply(index: int, pos: Vector2) -> void:
	var target: String = _touches[index]
	var last: Vector2 = _last.get(index, pos)
	_last[index] = pos
	if target == "look":
		_look += pos - last
		return
	if target == "lstick" or target == "rstick":
		var origin: Vector2 = _origins[index]
		var v := (pos - origin) / _radius()
		if target == "rstick" and mode == 1:
			v.x = 0.0
		if v.length() > 1.0:
			v = v.normalized()
		var value := Vector2(v.x, -v.y)
		if target == "lstick":
			stick_l = value
		else:
			stick_r = value
	else:
		var now := _hit(pos)
		if now in BUTTONS and now != target:
			buttons[target] = false
			_touches[index] = now
			target = now
		buttons[target] = true
	queue_redraw()


func _release(index: int) -> void:
	if not _touches.has(index):
		return
	var target: String = _touches[index]
	_touches.erase(index)
	_origins.erase(index)
	_last.erase(index)
	if target == "lstick":
		# In acro the throttle stays where the finger left it.
		stick_l = Vector2(0.0, stick_l.y) if mode == 2 else Vector2.ZERO
	elif target == "rstick":
		stick_r = Vector2.ZERO
	elif target in BUTTONS:
		buttons[target] = false
	queue_redraw()


# --- Drawing -----------------------------------------------------------------

func _origin_for(target: String) -> Vector2:
	for idx: int in _touches:
		if _touches[idx] == target:
			return _origins[idx]
	return _home(target == "lstick")


func _draw() -> void:
	if mode == 2:
		_draw_stick(_origin_for("lstick"), stick_l, "ГАЗ %d%% · ПОВОРОТ" % roundi((stick_l.y + 1.0) * 50.0), false)
		_draw_stick(_origin_for("rstick"), stick_r, "НАКЛОН · КРЕН", false)
	elif mode == 1:
		_draw_stick(_origin_for("lstick"), stick_l, "ВПЕРЁД · ПОВОРОТ", false)
		_draw_stick(_origin_for("rstick"), stick_r, "ВВЕРХ · ВНИЗ", true)
	else:
		for b: String in BUTTONS:
			_draw_button(b)
		_draw_caption(_home(true) + Vector2(0, -_radius() * 1.3), "ВПЕРЁД · НАЗАД")
		_draw_caption(_home(false) + Vector2(0, -_radius() * 1.3), "ВВЕРХ · ВНИЗ")
	_draw_caption(Vector2(size.x * 0.5, size.y - 64.0), "проведи по экрану, чтобы повернуть камеру")
	_draw_round_button(_pause_center(), "pause")
	_draw_round_button(_view_center(), "view")


func _draw_caption(center: Vector2, text: String) -> void:
	var w := 460.0
	var pos := center + Vector2(-w * 0.5, 0)
	draw_string_outline(_label_font, pos, text, HORIZONTAL_ALIGNMENT_CENTER, w, 17, 5, Color(0, 0, 0, 0.55))
	draw_string(_label_font, pos, text, HORIZONTAL_ALIGNMENT_CENTER, w, 17, Color(1, 1, 1, 0.75))


func _draw_stick(c: Vector2, v: Vector2, caption: String, vertical_only: bool) -> void:
	var r := _radius()
	if vertical_only:
		# A slot instead of a circle: this stick only moves up and down.
		var slot := Rect2(c - Vector2(r * 0.45, r), Vector2(r * 0.9, r * 2.0))
		draw_rect(slot, Color(0.05, 0.06, 0.08, 0.28))
		draw_rect(slot, Color(1, 1, 1, 0.35), false, 2.5)
		draw_line(c + Vector2(-r * 0.3, 0), c + Vector2(r * 0.3, 0), Color(1.0, 0.62, 0.2, 0.7), 3.0)
	else:
		draw_circle(c, r, Color(0.05, 0.06, 0.08, 0.28))
		draw_arc(c, r, 0.0, TAU, 64, Color(1, 1, 1, 0.35), 2.5, true)
		draw_line(c + Vector2(-r * 0.85, 0), c + Vector2(r * 0.85, 0), Color(1, 1, 1, 0.12), 2.0)
		draw_line(c + Vector2(0, -r * 0.85), c + Vector2(0, r * 0.85), Color(1, 1, 1, 0.12), 2.0)
	var knob := c + Vector2(v.x, -v.y) * r
	draw_circle(knob, r * 0.36, Color(1, 1, 1, 0.22))
	draw_arc(knob, r * 0.36, 0.0, TAU, 40, Color(1, 1, 1, 0.85), 3.0, true)
	draw_circle(knob, r * 0.1, Color(1.0, 0.62, 0.2, 0.9))
	_draw_caption(c + Vector2(0, -r - 16.0), caption)


func _draw_button(b: String) -> void:
	var c := _button_center(b)
	var r := _button_radius()
	var down: bool = buttons.get(b, false)
	draw_circle(c, r, Color(1.0, 0.56, 0.14, 0.85) if down else Color(0.05, 0.06, 0.08, 0.35))
	draw_arc(c, r, 0.0, TAU, 48, Color(1, 1, 1, 0.55), 2.5, true)
	var dir := Vector2.UP if b == "fwd" or b == "up" else Vector2.DOWN
	var side := Vector2(-dir.y, dir.x)
	var a := r * 0.42
	var col := Color(0.08, 0.06, 0.04) if down else Color(1, 1, 1, 0.92)
	if b == "up" or b == "down":
		# Double chevron marks the altitude buttons.
		for k in 2:
			var o := c + dir * (a * 0.55 * (k - 0.5) * 1.6)
			draw_polyline(PackedVector2Array([o - dir * a * 0.2 + side * a, o + dir * a * 0.45, o - dir * a * 0.2 - side * a]), col, 5.0, true)
	else:
		draw_colored_polygon(PackedVector2Array([c + dir * a, c - dir * a * 0.6 + side * a * 0.85, c - dir * a * 0.6 - side * a * 0.85]), col)


func _draw_round_button(c: Vector2, kind: String) -> void:
	draw_circle(c, 32.0, Color(0.05, 0.06, 0.08, 0.45))
	draw_arc(c, 32.0, 0.0, TAU, 40, Color(1, 1, 1, 0.5), 2.0, true)
	if kind == "pause":
		draw_rect(Rect2(c + Vector2(-10, -12), Vector2(7, 24)), Color.WHITE)
		draw_rect(Rect2(c + Vector2(3, -12), Vector2(7, 24)), Color.WHITE)
	else:
		# Camera icon: body and lens.
		draw_rect(Rect2(c + Vector2(-15, -9), Vector2(24, 18)), Color.WHITE)
		draw_colored_polygon(PackedVector2Array([c + Vector2(9, -2), c + Vector2(17, -8), c + Vector2(17, 8), c + Vector2(9, 2)]), Color.WHITE)
