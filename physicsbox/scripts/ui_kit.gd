class_name UiKit
extends RefCounted
## Small helpers to build the game's menus in code with a consistent look.

const RED := Color(0.78, 0.04, 0.08)
const DARK := Color(0.06, 0.06, 0.07, 0.92)


static func make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 28
	var normal := _box(Color(0.1, 0.1, 0.11, 0.9), Color(0.3, 0.3, 0.32))
	var hover := _box(Color(0.16, 0.08, 0.09, 0.95), RED)
	var pressed := _box(RED, Color(1, 0.4, 0.4))
	var disabled := _box(Color(0.08, 0.08, 0.08, 0.7), Color(0.18, 0.18, 0.18))
	t.set_stylebox("normal", "Button", normal)
	t.set_stylebox("hover", "Button", hover)
	t.set_stylebox("pressed", "Button", pressed)
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_stylebox("disabled", "Button", disabled)
	t.set_color("font_color", "Button", Color(0.95, 0.95, 0.95))
	t.set_color("font_hover_color", "Button", Color(1, 1, 1))
	t.set_color("font_disabled_color", "Button", Color(0.45, 0.45, 0.45))
	t.set_font_size("font_size", "Button", 30)
	var panel := _box(DARK, Color(0.25, 0.25, 0.27))
	panel.content_margin_left = 28
	panel.content_margin_right = 28
	panel.content_margin_top = 22
	panel.content_margin_bottom = 22
	t.set_stylebox("panel", "PanelContainer", panel)
	t.set_color("font_color", "Label", Color(0.92, 0.92, 0.92))
	var slider_bg := StyleBoxFlat.new()
	slider_bg.bg_color = Color(0.25, 0.25, 0.27)
	slider_bg.content_margin_top = 4
	slider_bg.content_margin_bottom = 4
	var slider_fill := StyleBoxFlat.new()
	slider_fill.bg_color = RED
	slider_fill.content_margin_top = 4
	slider_fill.content_margin_bottom = 4
	t.set_stylebox("slider", "HSlider", slider_bg)
	t.set_stylebox("grabber_area", "HSlider", slider_fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", slider_fill)
	t.set_icon("grabber", "HSlider", _circle_icon(26, Color(1, 1, 1)))
	t.set_icon("grabber_highlight", "HSlider", _circle_icon(26, Color(1, 0.6, 0.6)))
	return t


static func _box(bg: Color, border: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(2)
	s.set_corner_radius_all(6)
	s.content_margin_left = 18
	s.content_margin_right = 18
	s.content_margin_top = 10
	s.content_margin_bottom = 10
	return s


static func _circle_icon(d: int, color: Color) -> ImageTexture:
	var img := Image.create(d, d, false, Image.FORMAT_RGBA8)
	var r := d * 0.5
	for y in d:
		for x in d:
			var dist := Vector2(x + 0.5 - r, y + 0.5 - r).length()
			img.set_pixel(x, y, Color(color, clampf(r - dist, 0.0, 1.0)))
	return ImageTexture.create_from_image(img)


static func button(text: String, callback: Callable, min_width := 360.0) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(min_width, 64)
	b.pressed.connect(func():
		Sfx.play("ui_click")
		callback.call())
	return b


static func label(text: String, size := 28, color := Color(0.92, 0.92, 0.92)) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


## "Name ———o——— value" row. `on_change` receives the new value.
static func slider_row(title: String, min_v: float, max_v: float, step: float, value: float,
		on_change: Callable, fmt := "%.2f") -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	var l := label(title, 26)
	l.custom_minimum_size.x = 250
	row.add_child(l)
	var s := HSlider.new()
	s.min_value = min_v
	s.max_value = max_v
	s.step = step
	s.value = value
	s.custom_minimum_size = Vector2(300, 40)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(s)
	var v := label(fmt % value, 26)
	v.custom_minimum_size.x = 80
	row.add_child(v)
	s.value_changed.connect(func(nv):
		v.text = fmt % nv
		on_change.call(nv))
	return row


static func toggle_row(title: String, value: bool, on_change: Callable) -> CheckButton:
	var c := CheckButton.new()
	c.text = title
	c.button_pressed = value
	c.add_theme_font_size_override("font_size", 26)
	c.toggled.connect(func(on): on_change.call(on))
	return c


## Settings controls shared by the main menu and the pause menu.
static func settings_box() -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	var S = Settings
	box.add_child(slider_row("Чувствительность", 0.2, 3.0, 0.05, S.sensitivity, func(v): _apply_setting("sensitivity", v)))
	box.add_child(slider_row("Поле зрения", 60, 100, 1, S.fov, func(v): _apply_setting("fov", v), "%d"))
	box.add_child(slider_row("Кровь", 0.25, 2.0, 0.05, S.blood_amount, func(v): _apply_setting("blood_amount", v)))
	box.add_child(slider_row("Разрешение 3D", 0.5, 1.0, 0.05, S.render_scale, func(v): _apply_setting("render_scale", v)))
	box.add_child(slider_row("Громкость", 0.0, 1.0, 0.05, S.volume, func(v): _apply_setting("volume", v)))
	box.add_child(toggle_row("Бодикам", S.bodycam, func(on): _apply_setting("bodycam", on)))
	box.add_child(toggle_row("Тени", S.shadows, func(on): _apply_setting("shadows", on)))
	box.add_child(toggle_row("Показывать FPS", S.show_fps, func(on): _apply_setting("show_fps", on)))
	return box


static func _apply_setting(key: String, value: Variant) -> void:
	Settings.set(key, value)
	Settings.apply()
