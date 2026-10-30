class_name Bodycam
extends CanvasLayer
## Bodycam look (setting "Бодикам"): a post-process over the 3D view
## (assets/shaders/bodycam.gdshader) and the camera's stamp in the corner -
## model, serial, date and time, a blinking record dot. Lies under the HUD.
## With the helmet GoPro (Settings.camera) the same layer gives its fisheye
## look and its own stamp.

var _rect := ColorRect.new()
var _stamp := Label.new()
var _rec := Label.new()
var _serial := "X%d%s" % [randi_range(60000000, 69999999), "ABCDEFGHJK"[randi() % 10]]


func _ready() -> void:
	layer = 0
	add_to_group("settings_listeners")
	_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := ShaderMaterial.new()
	m.shader = load("res://assets/shaders/bodycam.gdshader")
	_rect.material = m
	add_child(_rect)
	for l in [_stamp, _rec]:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		l.add_theme_font_size_override("font_size", 19)
		l.add_theme_color_override("font_color", Color(1, 1, 1, 0.92))
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
		l.add_theme_constant_override("outline_size", 5)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(l)
	_stamp.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_stamp.offset_left = -520
	_stamp.offset_right = -24
	_stamp.offset_top = 100
	_rec.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_rec.offset_left = -200
	_rec.offset_right = -24
	_rec.offset_top = 150
	_rec.add_theme_color_override("font_color", Color(1, 0.2, 0.15, 0.95))
	on_settings_changed()


func on_settings_changed() -> void:
	var gopro := Settings.camera == "gopro"
	visible = Settings.bodycam or gopro
	var m := _rect.material as ShaderMaterial
	m.set_shader_parameter("distortion", 1.4 if gopro else 0.32)
	m.set_shader_parameter("aberration", 0.003 if gopro else 0.004)
	m.set_shader_parameter("grain", 0.015 if gopro else 0.025)
	m.set_shader_parameter("vignette", 0.45 if gopro else 0.75)
	m.set_shader_parameter("saturation", 1.12 if gopro else 0.72)
	m.set_shader_parameter("band", 0.0 if gopro else 1.0)
	m.set_shader_parameter("tint", Vector3(1.02, 1.0, 0.97) if gopro else Vector3(0.96, 1.0, 1.04))


func _process(_delta: float) -> void:
	if not visible:
		return
	# the drone's own video has its own look
	var p := get_tree().get_first_node_in_group("player") as Player
	var on := p == null or (p.piloting == null and p.signal_lost <= 0.0)
	_rect.visible = on
	_stamp.visible = on
	_rec.visible = on
	var d := Time.get_datetime_dict_from_system(true)
	if Settings.camera == "gopro":
		_stamp.text = "4K 60FPS  ▮▮▮▯ 87%%\nHELMET-CAM // GOPRO HERO  %04d-%02d-%02d %02d:%02d:%02d" % [d.year, d.month, d.day, d.hour, d.minute, d.second]
	else:
		_stamp.text = "%04d-%02d-%02d T%02d:%02d:%02dZ\nAXON BODY 4  %s" % [d.year, d.month, d.day, d.hour, d.minute, d.second, _serial]
	_rec.text = "● REC" if Time.get_ticks_msec() / 600 % 2 == 0 else "  REC"
