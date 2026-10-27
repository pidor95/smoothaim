extends Control
## Main menu, pause menu, the drone picker and the settings panel.

const DroneScript := preload("res://scripts/drone.gd")

signal play_pressed
signal resume_pressed
signal restart_pressed
signal menu_pressed

const ACCENT := Color(1.0, 0.56, 0.14)
const INK := Color(0.94, 0.94, 0.91)
const PANEL := Color(0.055, 0.065, 0.085, 0.92)

var _main_box: VBoxContainer
var _pause_box: VBoxContainer
var _settings_panel: PanelContainer
var _drones_panel: PanelContainer
var _net_panel: PanelContainer
var _net_status: Label
var _net_hosts: VBoxContainer
var _net_leave: Button
var _net_ip: LineEdit
## Multiplayer node (scripts/net.gd), set by the game before the menu is added.
var net: Node
var _drone_cards: Array[Button] = []
var _title: Label
var _tagline: Label
var _best: Label
var _help: Label
var _choices := {} # setting key -> Array of Buttons
var _sliders := {} # setting key -> HSlider
var _slider_values := {} # setting key -> Label
var _paused := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = _make_theme()
	_build()
	Settings.changed.connect(_refresh)
	_refresh()


# --- Public ------------------------------------------------------------------

func show_main() -> void:
	_paused = false
	visible = true
	_main_box.visible = true
	_pause_box.visible = false
	_settings_panel.visible = false
	_drones_panel.visible = false
	_net_panel.visible = false
	_title.text = "ДОЛИНА"
	_tagline.text = "FPV · СИМУЛЯТОР ДРОНА"
	_refresh()


func show_pause() -> void:
	_paused = true
	visible = true
	_main_box.visible = false
	_pause_box.visible = true
	_settings_panel.visible = false
	_drones_panel.visible = false
	_net_panel.visible = false
	_title.text = "ПАУЗА"
	_tagline.text = "ДРОН ЗАВИС И ЖДЁТ"
	_refresh()


func hide_all() -> void:
	visible = false


# --- Building ----------------------------------------------------------------

func _font(path: String, weight: int, spacing := 0) -> FontVariation:
	var f := FontVariation.new()
	f.base_font = load(path)
	if weight > 0:
		f.variation_opentype = {"wght": weight}
	f.spacing_glyph = spacing
	return f


func _box(color: Color, border: Color, radius := 14, border_width := 2) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.border_color = border
	sb.set_border_width_all(border_width)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = 22
	sb.content_margin_right = 22
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	sb.anti_aliasing = true
	return sb


func _circle_texture(radius: int, color: Color) -> ImageTexture:
	var d := radius * 2
	var img := Image.create(d, d, false, Image.FORMAT_RGBA8)
	for y in d:
		for x in d:
			var dist := Vector2(x + 0.5 - radius, y + 0.5 - radius).length()
			var a := clampf(radius - dist, 0.0, 1.0)
			img.set_pixel(x, y, Color(color.r, color.g, color.b, a))
	return ImageTexture.create_from_image(img)


func _make_theme() -> Theme:
	var t := Theme.new()
	t.default_font = _font("res://fonts/Exo2.ttf", 600)
	t.default_font_size = 24

	t.set_stylebox("normal", "Button", _box(Color(0.07, 0.08, 0.1, 0.85), Color(1, 1, 1, 0.12)))
	t.set_stylebox("hover", "Button", _box(Color(0.12, 0.13, 0.16, 0.92), Color(ACCENT, 0.8)))
	t.set_stylebox("pressed", "Button", _box(ACCENT, ACCENT.lightened(0.2)))
	t.set_stylebox("hover_pressed", "Button", _box(ACCENT, ACCENT.lightened(0.3)))
	t.set_stylebox("focus", "Button", _box(Color(0, 0, 0, 0), Color(ACCENT, 0.9)))
	t.set_stylebox("disabled", "Button", _box(Color(0.07, 0.08, 0.1, 0.5), Color(1, 1, 1, 0.05)))
	t.set_color("font_color", "Button", INK)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_focus_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", Color(0.07, 0.05, 0.03))
	t.set_color("font_hover_pressed_color", "Button", Color(0.07, 0.05, 0.03))

	t.set_color("font_color", "Label", INK)

	var panel := _box(PANEL, Color(1, 1, 1, 0.08), 20, 1)
	panel.content_margin_left = 28
	panel.content_margin_right = 28
	panel.content_margin_top = 22
	panel.content_margin_bottom = 22
	t.set_stylebox("panel", "PanelContainer", panel)

	var track := _box(Color(1, 1, 1, 0.16), Color(0, 0, 0, 0), 6, 0)
	track.content_margin_top = 5
	track.content_margin_bottom = 5
	t.set_stylebox("slider", "HSlider", track)
	var fill := _box(ACCENT, Color(0, 0, 0, 0), 6, 0)
	fill.content_margin_top = 5
	fill.content_margin_bottom = 5
	t.set_stylebox("grabber_area", "HSlider", fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", fill)
	var knob := _circle_texture(17, Color.WHITE)
	t.set_icon("grabber", "HSlider", knob)
	t.set_icon("grabber_highlight", "HSlider", _circle_texture(17, ACCENT.lightened(0.4)))

	var bar := _box(Color(1, 1, 1, 0.25), Color(0, 0, 0, 0), 4, 0)
	bar.content_margin_left = 3
	bar.content_margin_right = 3
	t.set_stylebox("grabber", "VScrollBar", bar)
	t.set_stylebox("grabber_highlight", "VScrollBar", bar)
	t.set_stylebox("grabber_pressed", "VScrollBar", bar)
	t.set_stylebox("scroll", "VScrollBar", StyleBoxEmpty.new())
	return t


func _build() -> void:
	# Darken the left side so the menu reads over the 3D scene.
	var shade := TextureRect.new()
	var grad := Gradient.new()
	grad.set_color(0, Color(0.03, 0.035, 0.05, 0.88))
	grad.set_color(1, Color(0.03, 0.035, 0.05, 0.0))
	var gtex := GradientTexture2D.new()
	gtex.gradient = grad
	gtex.fill_from = Vector2(0.0, 0.5)
	gtex.fill_to = Vector2(0.75, 0.5)
	gtex.width = 256
	gtex.height = 8
	shade.texture = gtex
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)

	var column := VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	column.offset_left = 64
	column.offset_top = 40
	column.offset_bottom = -32
	column.offset_right = 64 + 440
	column.add_theme_constant_override("separation", 10)
	add_child(column)

	_title = Label.new()
	_title.add_theme_font_override("font", _font("res://fonts/RussoOne-Regular.ttf", 0, 4))
	_title.add_theme_font_size_override("font_size", 84)
	_title.add_theme_color_override("font_color", Color(1.0, 0.97, 0.92))
	_title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.45))
	_title.add_theme_constant_override("shadow_offset_y", 4)
	column.add_child(_title)

	_tagline = Label.new()
	_tagline.add_theme_font_override("font", _font("res://fonts/JetBrainsMono.ttf", 700, 3))
	_tagline.add_theme_font_size_override("font_size", 18)
	_tagline.add_theme_color_override("font_color", ACCENT)
	column.add_child(_tagline)

	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 18)
	column.add_child(gap)

	_main_box = _button_list(column, [
		["ЛЕТАТЬ", func() -> void: play_pressed.emit()],
		["МУЛЬТИПЛЕЕР", _toggle_net],
		["ДРОН", _toggle_drones],
		["НАСТРОЙКИ", _toggle_settings],
		["ВЫХОД", func() -> void: get_tree().quit()],
	])
	_pause_box = _button_list(column, [
		["ПРОДОЛЖИТЬ", func() -> void: resume_pressed.emit()],
		["ЗАНОВО", func() -> void: restart_pressed.emit()],
		["ДРОН", _toggle_drones],
		["НАСТРОЙКИ", _toggle_settings],
		["В МЕНЮ", func() -> void: menu_pressed.emit()],
	])

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(spacer)

	_best = Label.new()
	_best.add_theme_font_override("font", _font("res://fonts/JetBrainsMono.ttf", 600))
	_best.add_theme_font_size_override("font_size", 18)
	_best.add_theme_color_override("font_color", Color(1, 1, 1, 0.75))
	column.add_child(_best)

	_build_settings()
	_build_drones()
	_build_net()


func _button_list(parent: Control, items: Array) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	parent.add_child(box)
	for item: Array in items:
		var b := Button.new()
		b.text = item[0]
		b.custom_minimum_size = Vector2(320, 64)
		b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", 26)
		var cb: Callable = item[1]
		b.pressed.connect(cb)
		box.add_child(b)
	return box


func _build_settings() -> void:
	_settings_panel = _side_panel()
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_settings_panel.add_child(scroll)

	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 16)
	scroll.add_child(list)
	_panel_header(list, "НАСТРОЙКИ", _toggle_settings)

	_section(list, "ГРАФИКА")
	_choice(list, "Тени", "shadows", ["Выкл", "Вкл"])
	_choice(list, "Блум (свечение)", "bloom", ["Выкл", "Вкл"])
	_choice(list, "Качество", "quality", ["Низкое", "Среднее", "Высокое"])

	_section(list, "УПРАВЛЕНИЕ")
	_choice(list, "Схема", "control_mode", ["Лёгкое", "Казуальное", "Акро"])
	_help = Label.new()
	_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_help.add_theme_font_size_override("font_size", 19)
	_help.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
	list.add_child(_help)
	_slider(list, "Чувствительность", "sensitivity", 0.5, 1.6, 0.05, "×")

	_section(list, "КАМЕРА И ЗВУК")
	_choice(list, "Вид", "third_person", ["FPV", "Сзади"])
	_slider(list, "Наклон FPV-камеры", "camera_tilt", 0.0, 45.0, 1.0, "°")
	_choice(list, "Звук моторов", "sound", ["Выкл", "Вкл"])


func _side_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	panel.offset_left = -640
	panel.offset_right = -40
	panel.offset_top = 32
	panel.offset_bottom = -32
	panel.visible = false
	add_child(panel)
	return panel


func _panel_header(parent: Control, text: String, close_action: Callable) -> void:
	var header := HBoxContainer.new()
	parent.add_child(header)
	var title := Label.new()
	title.text = text
	title.add_theme_font_override("font", _font("res://fonts/RussoOne-Regular.ttf", 0, 2))
	title.add_theme_font_size_override("font_size", 34)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close := Button.new()
	close.text = "ГОТОВО"
	close.custom_minimum_size = Vector2(150, 56)
	close.pressed.connect(close_action)
	header.add_child(close)


func _build_drones() -> void:
	_drones_panel = _side_panel()
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_drones_panel.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 14)
	scroll.add_child(list)
	_panel_header(list, "ВЫБОР ДРОНА", _toggle_drones)

	var group := ButtonGroup.new()
	var fastest := 0.0
	for t: Dictionary in DroneScript.TYPES:
		fastest = maxf(fastest, float(t["speed"]))
	for i in DroneScript.TYPES.size():
		var t: Dictionary = DroneScript.TYPES[i]
		var accent: Color = t["accent"]
		var card := Button.new()
		card.toggle_mode = true
		card.button_group = group
		card.custom_minimum_size = Vector2(0, 128)
		card.add_theme_stylebox_override("pressed", _box(Color(0.1, 0.11, 0.14, 0.95), accent, 14, 3))
		card.add_theme_stylebox_override("hover_pressed", _box(Color(0.12, 0.13, 0.16, 0.95), accent, 14, 3))
		card.pressed.connect(func() -> void: Settings.put("drone_type", i))
		list.add_child(card)
		_drone_cards.append(card)

		var row := HBoxContainer.new()
		row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		row.offset_left = 18
		row.offset_right = -18
		row.offset_top = 14
		row.offset_bottom = -14
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_theme_constant_override("separation", 16)
		card.add_child(row)
		var stripe := ColorRect.new()
		stripe.color = accent
		stripe.custom_minimum_size = Vector2(8, 0)
		stripe.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(stripe)
		var text := VBoxContainer.new()
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text.mouse_filter = Control.MOUSE_FILTER_IGNORE
		text.add_theme_constant_override("separation", 4)
		row.add_child(text)
		var name_label := Label.new()
		name_label.text = t["name"]
		name_label.add_theme_font_override("font", _font("res://fonts/RussoOne-Regular.ttf", 0, 2))
		name_label.add_theme_font_size_override("font_size", 28)
		text.add_child(name_label)
		var about := Label.new()
		about.text = t["about"]
		about.add_theme_font_size_override("font_size", 18)
		about.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
		text.add_child(about)
		var speed_row := HBoxContainer.new()
		speed_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		speed_row.add_theme_constant_override("separation", 12)
		text.add_child(speed_row)
		var speed := Label.new()
		speed.text = "ДО %d КМ/Ч" % roundi(float(t["speed"]))
		speed.add_theme_font_override("font", _font("res://fonts/JetBrainsMono.ttf", 700))
		speed.add_theme_font_size_override("font_size", 18)
		speed.add_theme_color_override("font_color", accent)
		speed_row.add_child(speed)
		var bar_bg := ColorRect.new()
		bar_bg.color = Color(1, 1, 1, 0.12)
		bar_bg.custom_minimum_size = Vector2(200, 8)
		bar_bg.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		speed_row.add_child(bar_bg)
		var bar := ColorRect.new()
		bar.color = accent
		bar.size = Vector2(200.0 * float(t["speed"]) / fastest, 8)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar_bg.add_child(bar)

	var note := Label.new()
	note.text = "Быстрым дронам нужна точность: на 200 км/ч ворота приближаются очень быстро."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_font_size_override("font_size", 18)
	note.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
	list.add_child(note)


func _build_net() -> void:
	_net_panel = _side_panel()
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_net_panel.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 14)
	scroll.add_child(list)
	_panel_header(list, "МУЛЬТИПЛЕЕР", _toggle_net)

	var intro := Label.new()
	intro.text = "Играйте вместе в одной Wi-Fi сети: на телефонах и на ПК. Один создаёт игру, остальные подключаются."
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.add_theme_font_size_override("font_size", 18)
	intro.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
	list.add_child(intro)

	var name_label := Label.new()
	name_label.text = "Имя пилота"
	list.add_child(name_label)
	var name_edit := LineEdit.new()
	name_edit.text = Settings.player_name
	name_edit.max_length = 20
	name_edit.custom_minimum_size = Vector2(0, 54)
	name_edit.text_changed.connect(_on_name_changed)
	name_edit.focus_exited.connect(Settings.save)
	list.add_child(name_edit)

	var host := Button.new()
	host.text = "СОЗДАТЬ ИГРУ"
	host.custom_minimum_size = Vector2(0, 58)
	host.pressed.connect(_on_host)
	list.add_child(host)

	_section(list, "НАЙДЕННЫЕ ИГРЫ")
	_net_hosts = VBoxContainer.new()
	_net_hosts.add_theme_constant_override("separation", 8)
	list.add_child(_net_hosts)

	_section(list, "ПОДКЛЮЧИТЬСЯ ПО АДРЕСУ")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	list.add_child(row)
	_net_ip = LineEdit.new()
	_net_ip.placeholder_text = "192.168.0.5"
	_net_ip.custom_minimum_size = Vector2(0, 54)
	_net_ip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_net_ip)
	var join := Button.new()
	join.text = "ВОЙТИ"
	join.custom_minimum_size = Vector2(130, 54)
	join.pressed.connect(_on_join_address)
	row.add_child(join)

	_net_status = Label.new()
	_net_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_net_status.add_theme_font_override("font", _font("res://fonts/JetBrainsMono.ttf", 600))
	_net_status.add_theme_font_size_override("font_size", 17)
	_net_status.add_theme_color_override("font_color", ACCENT)
	list.add_child(_net_status)

	_net_leave = Button.new()
	_net_leave.text = "ОТКЛЮЧИТЬСЯ"
	_net_leave.custom_minimum_size = Vector2(0, 54)
	_net_leave.pressed.connect(func() -> void: net.leave())
	list.add_child(_net_leave)

	if net != null:
		net.status_changed.connect(_refresh_net)
	_refresh_net()


func _on_name_changed(text: String) -> void:
	if text.strip_edges() != "":
		Settings.player_name = text.strip_edges()


func _on_host() -> void:
	Settings.save()
	net.host()


func _on_join_address() -> void:
	_on_join(_net_ip.text)


func _on_join(address: String) -> void:
	Settings.save()
	net.join(address)


func _refresh_net() -> void:
	if net == null or _net_status == null:
		return
	_net_status.text = net.status
	_net_leave.visible = net.is_online()
	for child in _net_hosts.get_children():
		child.queue_free()
	if net.hosts.is_empty():
		var none := Label.new()
		none.text = "Ищу игры в сети…" if not net.is_online() else "Ты уже в игре"
		none.add_theme_font_size_override("font_size", 18)
		none.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
		_net_hosts.add_child(none)
		return
	for ip: String in net.hosts:
		var info: Dictionary = net.hosts[ip]
		var b := Button.new()
		b.text = "%s · игроков %d · %s" % [info["name"], int(info["players"]), ip]
		b.custom_minimum_size = Vector2(0, 54)
		b.add_theme_font_size_override("font_size", 19)
		b.pressed.connect(_on_join.bind(ip))
		_net_hosts.add_child(b)


func _section(parent: Control, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", _font("res://fonts/JetBrainsMono.ttf", 700, 3))
	l.add_theme_font_size_override("font_size", 16)
	l.add_theme_color_override("font_color", ACCENT)
	parent.add_child(l)


func _choice(parent: Control, label: String, key: String, options: Array) -> void:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	parent.add_child(row)
	var l := Label.new()
	l.text = label
	row.add_child(l)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	row.add_child(buttons)
	var group := ButtonGroup.new()
	var list: Array[Button] = []
	for i in options.size():
		var b := Button.new()
		b.text = options[i]
		b.toggle_mode = true
		b.button_group = group
		b.custom_minimum_size = Vector2(0, 54)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 20)
		b.pressed.connect(_on_choice.bind(key, i))
		buttons.add_child(b)
		list.append(b)
	_choices[key] = list


func _slider(parent: Control, label: String, key: String, lo: float, hi: float, step: float, unit: String) -> void:
	var row := VBoxContainer.new()
	parent.add_child(row)
	var top := HBoxContainer.new()
	row.add_child(top)
	var l := Label.new()
	l.text = label
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(l)
	var value := Label.new()
	value.add_theme_font_override("font", _font("res://fonts/JetBrainsMono.ttf", 700))
	value.add_theme_color_override("font_color", ACCENT)
	top.add_child(value)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.custom_minimum_size = Vector2(0, 48)
	s.set_meta("unit", unit)
	s.value_changed.connect(_on_slider.bind(key))
	row.add_child(s)
	_sliders[key] = s
	_slider_values[key] = value


# --- Behaviour ---------------------------------------------------------------

func _toggle_settings() -> void:
	_toggle_panel(_settings_panel)


func _toggle_drones() -> void:
	_toggle_panel(_drones_panel)


func _toggle_net() -> void:
	_toggle_panel(_net_panel)


## Opens one side panel (closing the other one) or closes it if it is open.
func _toggle_panel(panel: PanelContainer) -> void:
	var open := not panel.visible
	_settings_panel.visible = false
	_drones_panel.visible = false
	_net_panel.visible = false
	panel.visible = open
	if net != null:
		if _net_panel.visible:
			net.start_discovery()
		else:
			net.stop_discovery()
	# On narrow screens the panel would cover the buttons, so hide them meanwhile.
	var room := size.x - 640.0 > 64.0 + 440.0
	_main_box.visible = not _paused and (room or not open)
	_pause_box.visible = _paused and (room or not open)
	_refresh()


func _on_choice(key: String, index: int) -> void:
	var current: Variant = Settings.get(key)
	if current is bool:
		Settings.put(key, index == 1)
	else:
		Settings.put(key, index)


func _on_slider(value: float, key: String) -> void:
	var label: Label = _slider_values[key]
	var s: HSlider = _sliders[key]
	var unit: String = s.get_meta("unit")
	label.text = ("%d" % roundi(value) if unit == "°" else "%.2f" % value) + unit
	if not is_equal_approx(float(Settings.get(key)), value):
		Settings.put(key, value)


func _refresh() -> void:
	for key: String in _choices:
		var value: Variant = Settings.get(key)
		var index := (1 if value else 0) if value is bool else int(value)
		var list: Array[Button] = _choices[key]
		for i in list.size():
			list[i].set_pressed_no_signal(i == index)
	for key: String in _sliders:
		var s: HSlider = _sliders[key]
		s.set_value_no_signal(float(Settings.get(key)))
		_on_slider(s.value, key)
	if Settings.control_mode == Settings.Controls.ACRO:
		_help.text = "Как настоящий FPV-дрон. Левый стик: газ (остаётся там, где отпустил) и поворот. Правый стик: наклон и крен. Дрон сам не выравнивается, можно делать флипы. Газ сам не держит высоту."
	elif Settings.control_mode == Settings.Controls.EASY:
		_help.text = "Слева: вперёд и назад. Справа: вверх и вниз. Поворот: проведи пальцем по экрану. Дрон сам держит высоту."
	else:
		_help.text = "Левый стик: вперёд, назад и поворот. Правый стик: вверх и вниз (центр = зависание). Пальцем по экрану тоже можно поворачивать камеру."
	if Settings.best_lap > 0.0:
		_best.text = "ЛУЧШИЙ КРУГ  %s" % _format_time(Settings.best_lap)
	else:
		_best.text = "18 ВОРОТ · ОЗЁРА, ГОРОД, ДЕРЕВНЯ И ГОРЫ"
	for i in _drone_cards.size():
		_drone_cards[i].set_pressed_no_signal(i == Settings.drone_type)


static func _format_time(t: float) -> String:
	var minutes := int(t / 60.0)
	return "%02d:%05.2f" % [minutes, t - minutes * 60.0]
