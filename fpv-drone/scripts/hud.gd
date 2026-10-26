extends Control
## FPV on-screen display (OSD): battery, timers, altitude, speed, artificial
## horizon, gate counter and a marker that points to the next gate.

var fpv := true
var speed_kmh := 0.0
var altitude := 0.0
var battery := 16.8
var flight_time := 0.0
var gate_index := 0
var gate_count := 0
var lap_time := 0.0
var lap_running := false
var best_lap := 0.0
var pitch := 0.0
var roll := 0.0
var camera_tilt := 20.0
var camera_fov := 80.0
var throttle := 0.0
var mode_text := "ANGLE"

var target_screen := Vector2.ZERO
var target_behind := false
var target_distance := 0.0

var _message := ""
var _sub_message := ""
var _message_time := 0.0
var _message_color := Color.WHITE

var _mono: FontVariation
var _title: Font

const WHITE := Color(1, 1, 1, 0.95)
const SHADOW := Color(0, 0, 0, 0.8)
const AMBER := Color(1.0, 0.66, 0.2)
const RED := Color(1.0, 0.3, 0.25)
const GREEN := Color(0.45, 1.0, 0.55)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_mono = FontVariation.new()
	_mono.base_font = load("res://fonts/JetBrainsMono.ttf")
	_mono.variation_opentype = {"wght": 700}
	_title = load("res://fonts/RussoOne-Regular.ttf")


func show_message(text: String, sub := "", color := Color.WHITE, seconds := 2.6) -> void:
	_message = text
	_sub_message = sub
	_message_color = color
	_message_time = seconds


static func format_time(t: float) -> String:
	var minutes := int(t / 60.0)
	var seconds := t - minutes * 60.0
	return "%02d:%05.2f" % [minutes, seconds]


func _process(delta: float) -> void:
	if _message_time > 0.0:
		_message_time -= delta
	queue_redraw()


func _side_insets() -> Vector2:
	var win := DisplayServer.window_get_size()
	if win.x <= 0:
		return Vector2.ZERO
	var safe := DisplayServer.get_display_safe_area()
	var k := size.x / float(win.x)
	return Vector2(maxf(0.0, safe.position.x) * k, maxf(0.0, win.x - safe.end.x) * k)


func _text(font: Font, pos: Vector2, text: String, font_size: int, color := WHITE, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	draw_string_outline(font, pos, text, align, width, font_size, 6, SHADOW)
	draw_string(font, pos, text, align, width, font_size, color)


func _draw() -> void:
	var ins := _side_insets()
	var left := ins.x + 36.0
	var right := size.x - ins.y - 36.0
	var center := size * 0.5

	# Battery and flight time, top left.
	var cells := battery / 4.0
	var bat_color := WHITE
	if cells < 3.5:
		bat_color = RED
	elif cells < 3.7:
		bat_color = AMBER
	_text(_mono, Vector2(left, 50), "4S %5.2fV" % battery, 24, bat_color)
	_text(_mono, Vector2(left, 80), "%4.2fV/CELL" % cells, 16, Color(1, 1, 1, 0.7))
	_text(_mono, Vector2(left, 108), "FLY " + format_time(flight_time).substr(0, 5), 20)

	# Gates and lap, top centre.
	var w := 520.0
	_text(_title, Vector2(center.x - w * 0.5, 52), "ВОРОТА %d / %d" % [mini(gate_index + 1, gate_count), gate_count], 30, WHITE, HORIZONTAL_ALIGNMENT_CENTER, w)
	var lap := "КРУГ " + (format_time(lap_time) if lap_running else "--:--.--")
	if best_lap > 0.0:
		lap += "   ЛУЧШИЙ " + format_time(best_lap)
	_text(_mono, Vector2(center.x - w * 0.5, 82), lap, 18, Color(1, 1, 1, 0.85), HORIZONTAL_ALIGNMENT_CENTER, w)

	# Altitude and speed at the sides of the screen centre.
	_text(_mono, Vector2(left, center.y - 30), "ALT", 16, Color(1, 1, 1, 0.65))
	_text(_mono, Vector2(left, center.y + 2), "%d м" % roundi(altitude), 28)
	_text(_mono, Vector2(right - 200, center.y - 30), "SPD", 16, Color(1, 1, 1, 0.65), HORIZONTAL_ALIGNMENT_RIGHT, 200)
	_text(_mono, Vector2(right - 200, center.y + 2), "%d км/ч" % roundi(speed_kmh), 28, WHITE, HORIZONTAL_ALIGNMENT_RIGHT, 200)

	# Mode and throttle, bottom centre.
	_text(_mono, Vector2(center.x - 200, size.y - 30), "%s  THR %3d%%" % [mode_text, roundi(throttle * 100.0)], 18, Color(1, 1, 1, 0.8), HORIZONTAL_ALIGNMENT_CENTER, 400)

	if fpv:
		_draw_horizon(center)
	_draw_target(center)

	if _message_time > 0.0:
		var a := clampf(_message_time / 0.4, 0.0, 1.0)
		var c := _message_color
		c.a = a
		_text(_title, Vector2(0, center.y - 70), _message, 56, c, HORIZONTAL_ALIGNMENT_CENTER, size.x)
		if _sub_message != "":
			_text(_mono, Vector2(0, center.y - 30), _sub_message, 24, Color(1, 1, 1, a), HORIZONTAL_ALIGNMENT_CENTER, size.x)


func _draw_horizon(center: Vector2) -> void:
	var focal := (size.y * 0.5) / tan(deg_to_rad(camera_fov) * 0.5)
	var offset := tan(clampf(pitch + deg_to_rad(camera_tilt), -1.2, 1.2)) * focal
	draw_set_transform(center, roll, Vector2.ONE)
	var col := Color(1, 1, 1, 0.7)
	draw_line(Vector2(-150, offset), Vector2(-50, offset), col, 3.0, true)
	draw_line(Vector2(50, offset), Vector2(150, offset), col, 3.0, true)
	draw_line(Vector2(-150, offset), Vector2(-150, offset + 10), col, 3.0, true)
	draw_line(Vector2(150, offset), Vector2(150, offset + 10), col, 3.0, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# Fixed crosshair.
	draw_line(center + Vector2(-18, 0), center + Vector2(-6, 0), WHITE, 3.0)
	draw_line(center + Vector2(6, 0), center + Vector2(18, 0), WHITE, 3.0)
	draw_line(center + Vector2(0, 6), center + Vector2(0, 14), WHITE, 3.0)


func _draw_target(center: Vector2) -> void:
	if gate_count == 0:
		return
	var p := target_screen
	var margin := 70.0
	var on_screen := not target_behind and Rect2(Vector2(margin, margin), size - Vector2(margin, margin) * 2.0).has_point(p)
	var dist_text := "%d м" % roundi(target_distance)
	if on_screen:
		var r := 16.0
		var pts := PackedVector2Array([p + Vector2(0, -r), p + Vector2(r, 0), p + Vector2(0, r), p + Vector2(-r, 0), p + Vector2(0, -r)])
		draw_polyline(pts, SHADOW, 6.0, true)
		draw_polyline(pts, AMBER, 3.0, true)
		_text(_mono, p + Vector2(-80, r + 24), dist_text, 18, AMBER, HORIZONTAL_ALIGNMENT_CENTER, 160)
		return
	var dir := (p - center)
	if target_behind:
		dir = -dir
	if dir.length() < 1.0:
		dir = Vector2.DOWN
	dir = dir.normalized()
	var edge := center + dir * minf(size.x * 0.5 - margin - 40.0, size.y * 0.5 - margin)
	var side := Vector2(-dir.y, dir.x)
	var tri := PackedVector2Array([edge + dir * 22.0, edge - dir * 10.0 + side * 16.0, edge - dir * 10.0 - side * 16.0])
	draw_colored_polygon(tri, AMBER)
	_text(_mono, edge - dir * 40.0 + Vector2(-80, 8), dist_text, 18, AMBER, HORIZONTAL_ALIGNMENT_CENTER, 160)
