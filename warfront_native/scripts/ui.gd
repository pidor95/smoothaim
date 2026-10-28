extends Control
## Main menu, pause, death and victory screens. Built for the PC first (a side bar with sections, vehicle cards
## with characteristic bars, key hints) and laid out with large controls so it works the same on a phone.

const D := preload("res://scripts/data.gd")

signal start_bots
signal start_online
signal respawn(type: String)
signal to_menu
signal resume
signal restart
signal quality_changed(q: String)
signal settings_changed

const ACCENT := Color(1.0, 0.74, 0.3)
const INK := Color(0.08, 0.06, 0.02)
const PANEL := Color(0.05, 0.07, 0.085, 0.9)
const MUTED := Color(0.72, 0.77, 0.82)

var settings: Dictionary
var net: Node
var desktop := not OS.has_feature("mobile")
var menu: Control
var side: PanelContainer
var content: Control
var pause_panel: Control
var death_panel: Control
var death_text: Label
var death_choice := ""
var death_buttons := {}
var victory_panel: Control
var victory_text: Label
var nav := {}
var hosts_box: VBoxContainer
var servers_box: VBoxContainer
var status_label: Label
var ip_edit: LineEdit
var nick_edit: LineEdit
var tab_net: Control


func build(s: Dictionary, n: Node) -> void:
	settings = s
	net = n
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fit()
	get_viewport().size_changed.connect(_fit)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = _theme()
	_build_menu()
	_build_pause()
	_build_death()
	_build_victory()
	net.status.connect(func(t): status_label.text = t)
	net.hosts_changed.connect(_refresh_hosts)
	net.servers_changed.connect(_refresh_servers)


func _fit() -> void:
	position = Vector2.ZERO
	size = get_viewport_rect().size


# ---------------------------------------------------------------- look
static func _box(col: Color, rad := 10, border := Color(0, 0, 0, 0), bw := 2) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = col
	b.set_corner_radius_all(rad)
	b.content_margin_left = 16
	b.content_margin_right = 16
	b.content_margin_top = 8
	b.content_margin_bottom = 8
	if border.a > 0.0:
		b.border_color = border
		b.set_border_width_all(bw)
	return b


func _theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 20
	t.set_stylebox("normal", "Button", _box(Color(0.11, 0.14, 0.16, 0.94), 8, Color(1, 1, 1, 0.07)))
	t.set_stylebox("hover", "Button", _box(Color(0.17, 0.21, 0.24, 0.96), 8, Color(ACCENT, 0.55)))
	t.set_stylebox("pressed", "Button", _box(Color(0.85, 0.62, 0.22, 0.96), 8))
	t.set_stylebox("hover_pressed", "Button", _box(Color(0.92, 0.7, 0.3, 0.96), 8))
	t.set_stylebox("disabled", "Button", _box(Color(0.1, 0.11, 0.12, 0.7), 8))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_pressed_color", "Button", INK)
	t.set_color("font_hover_pressed_color", "Button", INK)
	t.set_color("font_hover_color", "Button", Color(1, 0.93, 0.8))
	t.set_stylebox("panel", "PanelContainer", _box(PANEL, 12))
	t.set_stylebox("normal", "LineEdit", _box(Color(0.1, 0.12, 0.14, 0.95), 8, Color(1, 1, 1, 0.15)))
	t.set_constant("separation", "VBoxContainer", 10)
	t.set_constant("separation", "HBoxContainer", 10)
	t.set_font_size("font_size", "Label", 19)
	t.set_stylebox("slider", "HSlider", _box(Color(0.2, 0.23, 0.26), 4))
	t.set_stylebox("grabber_area", "HSlider", _box(Color(ACCENT, 0.8), 4))
	t.set_stylebox("grabber_area_highlight", "HSlider", _box(ACCENT, 4))
	return t


func _label(t: String, sz := 19, col := Color.WHITE) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", sz)
	l.add_theme_color_override("font_color", col)
	# only long texts wrap; short ones keep their natural width inside rows
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if t.length() > 32 else TextServer.AUTOWRAP_OFF
	return l


func _button(t: String, cb: Callable, toggle := false) -> Button:
	var b := Button.new()
	b.text = t
	b.toggle_mode = toggle
	b.custom_minimum_size = Vector2(0, 50 if desktop else 56)
	b.pressed.connect(cb)
	return b


func _accent(b: Button) -> Button:
	b.add_theme_stylebox_override("normal", _box(Color(0.82, 0.58, 0.18, 0.96), 8))
	b.add_theme_stylebox_override("hover", _box(Color(0.95, 0.7, 0.26, 0.98), 8, Color(1, 1, 1, 0.5)))
	b.add_theme_color_override("font_color", INK)
	b.add_theme_color_override("font_hover_color", INK)
	return b


func _big(t: String, cb: Callable, accent := false) -> Button:
	var b := _button(t, cb)
	b.custom_minimum_size = Vector2(0, 70)
	b.add_theme_font_size_override("font_size", 28)
	return _accent(b) if accent else b


func _center_panel(min_w: float) -> PanelContainer:
	var c := CenterContainer.new()
	add_child(c)
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(min_w, 0)
	c.add_child(p)
	c.visible = false
	return p


## Characteristic bar: label, filled track.
func _bar(parent: Control, title: String) -> ProgressBar:
	var r := HBoxContainer.new()
	parent.add_child(r)
	var l := _label(title, 16, MUTED)
	l.custom_minimum_size = Vector2(150, 0)
	r.add_child(l)
	var pb := ProgressBar.new()
	pb.min_value = 0.0
	pb.max_value = 1.0
	pb.show_percentage = false
	pb.custom_minimum_size = Vector2(0, 14)
	pb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pb.add_theme_stylebox_override("background", _box(Color(1, 1, 1, 0.08), 3))
	pb.add_theme_stylebox_override("fill", _box(ACCENT, 3))
	r.add_child(pb)
	return pb


# ---------------------------------------------------------------- main menu
## Side bar on the left (sections), content on the right. Sections: play, vehicles, online, settings.
var pages := {}
var home_name: Label
var home_kind: Label
var home_bars: Array = []
var home_weapons: Label
var garage_list: VBoxContainer
var garage_info: Label
var garage_title: Label
var garage_kind: Label
var garage_bars: Array = []
var garage_weapons: VBoxContainer
var garage_group := 0
var group_buttons: Array = []
var garage_pick := ""
var preview_holder: Node3D
var preview_cam: Camera3D


func _page(name: String) -> VBoxContainer:
	var m := MarginContainer.new()
	content.add_child(m)
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for s in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + s, 22)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	m.add_child(v)
	pages[name] = m
	return v


func _title(parent: Control, t: String, sub := "") -> void:
	parent.add_child(_label(t, 34, ACCENT))
	if sub != "":
		parent.add_child(_label(sub, 16, MUTED))


func _build_menu() -> void:
	menu = Control.new()
	add_child(menu)
	menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	menu.add_child(row)
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# side bar
	side = PanelContainer.new()
	side.custom_minimum_size = Vector2(300, 0)
	side.add_theme_stylebox_override("panel", _box(Color(0.03, 0.045, 0.055, 0.93), 0))
	row.add_child(side)
	var sm := MarginContainer.new()
	for s in ["left", "right", "top", "bottom"]:
		sm.add_theme_constant_override("margin_" + s, 20)
	side.add_child(sm)
	var sv := VBoxContainer.new()
	sv.add_theme_constant_override("separation", 10)
	sm.add_child(sv)
	var logo := _label("БОЕВОЙ\nФРОНТ", 40, ACCENT)
	logo.add_theme_constant_override("line_spacing", -8)
	sv.add_child(logo)
	sv.add_child(_label("Прохоровка · 10×10 км", 15, MUTED))
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 14)
	sv.add_child(gap)
	for item in [["home", "▶  Играть"], ["garage", "◆  Техника"], ["online", "◉  Онлайн"], ["settings", "⚙  Настройки"]]:
		var b := _button(item[1], show_page.bind(item[0]), true)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", 22)
		b.custom_minimum_size = Vector2(0, 58)
		sv.add_child(b)
		nav[item[0]] = b
	var fill := Control.new()
	fill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sv.add_child(fill)
	if desktop:
		sv.add_child(_button("Выход", func(): get_tree().quit()))
	sv.add_child(_label("Версия 2.5", 13, Color(0.5, 0.55, 0.6)))
	content = Control.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(content)
	_build_home()
	_build_garage()
	_build_online_page()
	_build_settings()
	_pick_vehicle(settings["vehicle"])
	show_page("home")


func _build_home() -> void:
	var home := _page("home")
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	home.add_child(spacer)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	home.add_child(row)
	# selected vehicle card
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_stretch_ratio = 1.3
	row.add_child(card)
	var cv := VBoxContainer.new()
	card.add_child(cv)
	cv.add_child(_label("ВАША ТЕХНИКА", 14, MUTED))
	home_name = _label("", 36, Color.WHITE)
	cv.add_child(home_name)
	home_kind = _label("", 17, ACCENT)
	cv.add_child(home_kind)
	for t in ["Скорость", "Броня", "Огневая мощь", "Манёвренность"]:
		home_bars.append(_bar(cv, t))
	home_weapons = _label("", 15, MUTED)
	home_weapons.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cv.add_child(home_weapons)
	var ch := HBoxContainer.new()
	cv.add_child(ch)
	var change := _button("Сменить технику", show_page.bind("garage"))
	change.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ch.add_child(change)
	# mode and start
	var mp := PanelContainer.new()
	mp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(mp)
	var mv := VBoxContainer.new()
	mp.add_child(mv)
	mv.add_child(_label("ОПЕРАЦИЯ", 14, MUTED))
	mv.add_child(_label("Штурм высот", 30))
	mv.add_child(_label("Уничтожьте укрепления на точках A, B и C: бункер, зенитку ЗУ-23 и склад боеприпасов. Вылет с авиабазы: самолёты — из ангара на полосу, вертолёты — с площадки, бронетехника — из гаража.", 15, MUTED))
	_toggle(mv, "Точки штурма", "assault")
	mv.add_child(_big("В БОЙ", func(): start_bots.emit(), true))
	if desktop:
		home.add_child(_label("Мышь — обзор · ЛКМ — огонь · ПКМ — прицел · колесо или 1-6 — оружие · W/S — тяга · A/D — поворот · X — флаеры · Пробел — пропустить взлёт · Esc — пауза", 14, Color(0.65, 0.7, 0.75)))
	home.add_child(_label("Карта: © участники OpenStreetMap (ODbL) · Sentinel-2 cloudless 2020 © EOX (CC BY-NC-SA 4.0) · рельеф: AWS Terrain Tiles · текстуры: ambientCG, Poly Haven (CC0)", 11, Color(0.6, 0.64, 0.68)))


func _build_garage() -> void:
	var gar := _page("garage")
	_title(gar, "Техника")
	var tabs := HBoxContainer.new()
	gar.add_child(tabs)
	for i in D.GROUPS.size():
		var b := _button(D.GROUPS[i][0], _group.bind(i), true)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tabs.add_child(b)
		group_buttons.append(b)
	var grow := HBoxContainer.new()
	grow.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grow.add_theme_constant_override("separation", 16)
	gar.add_child(grow)
	var gl := PanelContainer.new()
	gl.custom_minimum_size = Vector2(300, 0)
	grow.add_child(gl)
	var gscroll := ScrollContainer.new()
	gscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	gl.add_child(gscroll)
	garage_list = VBoxContainer.new()
	garage_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gscroll.add_child(garage_list)
	# preview in the middle, characteristics on the right
	var svc := SubViewportContainer.new()
	svc.stretch = true
	svc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	svc.size_flags_stretch_ratio = 1.3
	svc.custom_minimum_size = Vector2(0, 200)
	grow.add_child(svc)
	var sv := SubViewport.new()
	sv.own_world_3d = true
	sv.transparent_bg = true
	sv.msaa_3d = Viewport.MSAA_2X
	svc.add_child(sv)
	var root := Node3D.new()
	sv.add_child(root)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.6, 0.68)
	env.ambient_light_energy = 1.0
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	we.environment = env
	root.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, -30, 0)
	sun.light_energy = 1.6
	root.add_child(sun)
	preview_cam = Camera3D.new()
	preview_cam.fov = 35.0
	root.add_child(preview_cam)
	preview_holder = Node3D.new()
	root.add_child(preview_holder)
	var info := PanelContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grow.add_child(info)
	var iscroll := ScrollContainer.new()
	iscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	info.add_child(iscroll)
	var iv := VBoxContainer.new()
	iv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	iscroll.add_child(iv)
	garage_title = _label("", 30, Color.WHITE)
	iv.add_child(garage_title)
	garage_kind = _label("", 16, ACCENT)
	iv.add_child(garage_kind)
	for t in ["Скорость", "Броня", "Огневая мощь", "Манёвренность"]:
		garage_bars.append(_bar(iv, t))
	garage_info = _label("", 15, MUTED)
	garage_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	iv.add_child(garage_info)
	iv.add_child(_label("ВООРУЖЕНИЕ", 14, MUTED))
	garage_weapons = VBoxContainer.new()
	garage_weapons.add_theme_constant_override("separation", 2)
	iv.add_child(garage_weapons)
	var pick := HBoxContainer.new()
	gar.add_child(pick)
	var filler := Control.new()
	filler.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pick.add_child(filler)
	var choose := _accent(_button("Выбрать", func(): _pick_vehicle(garage_pick); show_page("home")))
	choose.custom_minimum_size = Vector2(260, 58)
	pick.add_child(choose)
	var go := _accent(_button("Выбрать и в бой", func(): _pick_vehicle(garage_pick); start_bots.emit()))
	go.custom_minimum_size = Vector2(260, 58)
	pick.add_child(go)


func _build_online_page() -> void:
	var on := _page("online")
	_title(on, "Онлайн", "Игра по сети: выделенные серверы или Wi-Fi без сервера")
	var opanel := PanelContainer.new()
	opanel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	on.add_child(opanel)
	var oscroll := ScrollContainer.new()
	oscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	opanel.add_child(oscroll)
	tab_net = VBoxContainer.new()
	tab_net.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	oscroll.add_child(tab_net)
	_build_online(tab_net)


func _build_settings() -> void:
	var st := _page("settings")
	_title(st, "Настройки")
	var srow := HBoxContainer.new()
	srow.size_flags_vertical = Control.SIZE_EXPAND_FILL
	srow.add_theme_constant_override("separation", 16)
	st.add_child(srow)
	var sp1 := PanelContainer.new()
	sp1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	srow.add_child(sp1)
	var sc1 := ScrollContainer.new()
	sc1.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sp1.add_child(sc1)
	var s1 := VBoxContainer.new()
	s1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc1.add_child(s1)
	s1.add_child(_label("БОТЫ", 18, ACCENT))
	_stepper(s1, "Сложность", "diff", 0, D.DIFF.size() - 1, func(v): return D.DIFF[v]["n"])
	_stepper(s1, "Самолёты", "bp", 0, 4)
	_stepper(s1, "Вертолёты", "bh", 0, 4)
	_stepper(s1, "Танки и ЗРПК", "bt", 0, 6)
	_stepper(s1, "Пехота врага", "bi", 0, 12)
	_stepper(s1, "Пехота союзников", "ba", 0, 10)
	_toggle(s1, "Боты стреляют", "shoot")
	var sp2 := PanelContainer.new()
	sp2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	srow.add_child(sp2)
	var sc2 := ScrollContainer.new()
	sc2.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sp2.add_child(sc2)
	var s2 := VBoxContainer.new()
	s2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc2.add_child(s2)
	s2.add_child(_label("ИГРА", 18, ACCENT))
	_common(s2)
	_toggle(s2, "Анимация вылета с базы", "intro")
	_toggle(s2, "Бесконечные боеприпасы", "ammo")
	var vr := HBoxContainer.new()
	s2.add_child(vr)
	var vl := _label("Громкость", 18)
	vl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vr.add_child(vl)
	var vol := HSlider.new()
	vol.min_value = 0
	vol.max_value = 1
	vol.step = 0.05
	vol.value = settings.get("vol", 0.8)
	vol.custom_minimum_size = Vector2(220, 40)
	vol.value_changed.connect(func(v):
		settings["vol"] = v
		AudioServer.set_bus_volume_db(0, linear_to_db(maxf(v, 0.001)))
		settings_changed.emit())
	vr.add_child(vol)
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(float(settings.get("vol", 0.8)), 0.001)))
	s2.add_child(_label("УПРАВЛЕНИЕ", 18, ACCENT))
	s2.add_child(_label("ПК: мышь — обзор, ЛКМ — огонь, ПКМ — прицел, колесо или 1-6 — оружие, Esc — пауза. Пехота: WASD, Shift — бег, R — перезарядка. Техника: W/S — тяга, A/D — поворот (вертолёт: высота), X — флаеры, C/V/B — манёвры Су-57, Пробел — пропустить взлёт.", 14, MUTED))
	s2.add_child(_label("Телефон: тяните по экрану — обзор, слева — тяга или джойстик ходьбы, справа — огонь и оружие.", 14, MUTED))


func _build_online(parent: VBoxContainer) -> void:
	var nr := HBoxContainer.new()
	parent.add_child(nr)
	nr.add_child(_label("Позывной", 18))
	nick_edit = LineEdit.new()
	nick_edit.text = settings.get("nick", "")
	nick_edit.placeholder_text = "Игрок"
	nick_edit.max_length = 16
	nick_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nick_edit.text_changed.connect(func(t): settings["nick"] = t.strip_edges(); settings_changed.emit())
	nr.add_child(nick_edit)
	var sh := HBoxContainer.new()
	parent.add_child(sh)
	var sl := _label("СЕРВЕРЫ", 18, ACCENT)
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sh.add_child(sl)
	sh.add_child(_button("Обновить", func(): net.refresh_servers(settings["servers"])))
	servers_box = VBoxContainer.new()
	parent.add_child(servers_box)
	var ar := HBoxContainer.new()
	parent.add_child(ar)
	var add_edit := LineEdit.new()
	add_edit.placeholder_text = "адрес сервера, напр. 185.10.20.30:27015"
	add_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ar.add_child(add_edit)
	ar.add_child(_button("Добавить", func():
		var a := add_edit.text.strip_edges()
		if a != "" and not settings["servers"].has(a):
			settings["servers"].append(a)
			settings_changed.emit()
			net.refresh_servers(settings["servers"])
		add_edit.text = ""))
	parent.add_child(_label("ИГРА ПО WI-FI (без сервера)", 18, ACCENT))
	parent.add_child(_label("Все в одной Wi-Fi сети или на точке доступа с телефона: один создаёт игру, остальные подключаются.", 14, MUTED))
	parent.add_child(_button("Создать игру", func(): start_online.emit()))
	parent.add_child(_label("Найденные игры:", 17))
	hosts_box = VBoxContainer.new()
	parent.add_child(hosts_box)
	var ir := HBoxContainer.new()
	parent.add_child(ir)
	ip_edit = LineEdit.new()
	ip_edit.placeholder_text = "IP хоста, напр. 192.168.1.5"
	ip_edit.text = settings.get("ip", "")
	ip_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ir.add_child(ip_edit)
	ir.add_child(_button("Подключиться", func(): settings["ip"] = ip_edit.text; settings_changed.emit(); net.join(ip_edit.text)))
	status_label = _label("", 16, Color(1, 0.8, 0.45))
	parent.add_child(status_label)
	var ips: Array = net.local_ips()
	parent.add_child(_label("Ваш IP: " + (", ".join(ips) if ips.size() > 0 else "нет сети"), 15, Color(0.7, 0.75, 0.8)))


func show_page(name: String) -> void:
	for k in pages:
		pages[k].visible = k == name
	for k in nav:
		nav[k].button_pressed = k == name
	if name == "online":
		net.start_discovery()
		net.refresh_servers(settings["servers"])
		_refresh_hosts()
	else:
		net.stop_discovery()
	if name == "garage":
		garage_pick = settings["vehicle"]
		for i in D.GROUPS.size():
			if D.GROUPS[i][1].has(garage_pick):
				garage_group = i
		_fill_garage()


func _group(i: int) -> void:
	garage_group = i
	_fill_garage()


func _fill_garage() -> void:
	for k in group_buttons.size():
		group_buttons[k].button_pressed = k == garage_group
	for c in garage_list.get_children():
		c.queue_free()
	var list: Array = D.GROUPS[garage_group][1]
	for t in list:
		var T: Dictionary = D.TYPES[t]
		var b := _button("%s\n%s · %d HP" % [T["name"], D.kind_of(t), int(T["hp"])], _garage_select.bind(t), true)
		b.custom_minimum_size = Vector2(0, 72)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.set_meta("type", t)
		garage_list.add_child(b)
	_garage_select(garage_pick if list.has(garage_pick) else list[0])


func _fill_stats(bars: Array, t: String) -> void:
	var st: Array = D.STATS.get(t, [0.5, 0.5, 0.5, 0.5])
	for i in bars.size():
		bars[i].value = st[i]


func _garage_select(t: String) -> void:
	garage_pick = t
	for b in garage_list.get_children():
		if b is Button and b.has_meta("type"):
			b.button_pressed = b.get_meta("type") == t
	var T: Dictionary = D.TYPES[t]
	garage_title.text = T["name"]
	garage_kind.text = "%s · прочность %d · до %d км/ч" % [D.kind_of(t), int(T["hp"]), int(T["vmax"] * 3.6)]
	garage_info.text = T["desc"]
	_fill_stats(garage_bars, t)
	for c in garage_weapons.get_children():
		c.queue_free()
	for i in T["slots"].size():
		var s: Dictionary = T["slots"][i]
		var r := HBoxContainer.new()
		garage_weapons.add_child(r)
		var k := _label("%d" % (i + 1), 15, ACCENT)
		k.custom_minimum_size = Vector2(22, 0)
		r.add_child(k)
		var n := _label(s["n"], 16)
		n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		r.add_child(n)
		r.add_child(_label("×%d" % s["a"], 15, MUTED))
	for c in preview_holder.get_children():
		c.queue_free()
	var m: Node3D
	if T["cat"] == "inf":
		m = preload("res://scripts/soldier.gd").preview_node()
	else:
		m = load("res://assets/models/%s.glb" % T["model"]).instantiate()
	preview_holder.add_child(m)
	# frame the model
	var box := AABB()
	var first := true
	for mi in m.find_children("*", "MeshInstance3D", true, false):
		var gi := mi as MeshInstance3D
		var bb: AABB = gi.get_aabb()
		var xf: Transform3D = m.global_transform.affine_inverse() * gi.global_transform if m.is_inside_tree() else gi.transform
		bb = xf * bb
		box = bb if first else box.merge(bb)
		first = false
	m.position = -box.get_center()
	var r := box.size.length() * 0.5
	preview_cam.position = Vector3(0, r * 0.45, r * 2.5)
	preview_cam.look_at(Vector3.ZERO, Vector3.UP)


func _process(dt: float) -> void:
	if preview_holder and pages.has("garage") and pages["garage"].visible and menu.visible:
		preview_holder.rotate_y(dt * 0.5)


func _stepper(parent: Control, title: String, key: String, lo: int, hi: int, fmt := Callable()) -> void:
	var r := HBoxContainer.new()
	parent.add_child(r)
	var l := _label(title, 18)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.add_child(l)
	var val := _label("", 20, Color(1, 0.85, 0.5))
	val.custom_minimum_size = Vector2(110, 0)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var show := func(): val.text = str(fmt.call(int(settings[key])) if fmt.is_valid() else int(settings[key]))
	var minus := _button("−", func(): settings[key] = clampi(int(settings[key]) - 1, lo, hi); show.call(); settings_changed.emit())
	var plus := _button("+", func(): settings[key] = clampi(int(settings[key]) + 1, lo, hi); show.call(); settings_changed.emit())
	minus.custom_minimum_size = Vector2(54, 46 if desktop else 52)
	plus.custom_minimum_size = Vector2(54, 46 if desktop else 52)
	r.add_child(minus)
	r.add_child(val)
	r.add_child(plus)
	show.call()


func _toggle(parent: Control, title: String, key: String) -> void:
	var b := CheckButton.new()
	b.text = title
	b.button_pressed = settings.get(key, true)
	b.custom_minimum_size = Vector2(0, 46 if desktop else 54)
	b.add_theme_font_size_override("font_size", 18)
	b.toggled.connect(func(on): settings[key] = on; settings_changed.emit())
	parent.add_child(b)


func _common(parent: Control) -> void:
	var q := HBoxContainer.new()
	parent.add_child(q)
	var l := _label("Графика", 18)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	q.add_child(l)
	var group := ButtonGroup.new()
	for item in [["low", "Низкая"], ["mid", "Средняя"], ["high", "Высокая"]]:
		var b := _button(item[1], func(): pass, true)
		b.button_group = group
		b.button_pressed = settings["gfx"] == item[0]
		b.toggled.connect(func(on): if on and settings["gfx"] != item[0]: quality_changed.emit(item[0]))
		q.add_child(b)
	var sr := HBoxContainer.new()
	parent.add_child(sr)
	var sl := _label("Чувствительность", 18)
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sr.add_child(sl)
	var slider := HSlider.new()
	slider.min_value = 2
	slider.max_value = 12
	slider.step = 0.5
	slider.value = settings["sens"]
	slider.custom_minimum_size = Vector2(220, 40)
	slider.value_changed.connect(func(v): settings["sens"] = v; settings_changed.emit())
	sr.add_child(slider)


func _pick_vehicle(t: String) -> void:
	if not D.TYPES.has(t) or D.TYPES[t]["cat"] == "struct":
		t = "su57"
	settings["vehicle"] = t
	var T: Dictionary = D.TYPES[t]
	home_name.text = T["name"]
	home_kind.text = D.kind_of(t)
	_fill_stats(home_bars, t)
	var w: Array = []
	for s in T["slots"]:
		w.append("%s ×%d" % [s["n"], s["a"]])
	home_weapons.text = ", ".join(w)
	settings_changed.emit()


func _refresh_hosts() -> void:
	for c in hosts_box.get_children():
		c.queue_free()
	for ip in net.hosts:
		hosts_box.add_child(_button("%s  (%s)" % [net.hosts[ip]["name"], ip], func(): net.join(ip)))
	if net.hosts.is_empty():
		hosts_box.add_child(_label("— поиск игр в сети… —", 15, Color(0.6, 0.65, 0.7)))


func _refresh_servers() -> void:
	for c in servers_box.get_children():
		c.queue_free()
	for key in net.servers:
		var e: Dictionary = net.servers[key]
		var info := "нет ответа" if e["players"] < 0 else "%d/%d игроков · %d мс" % [e["players"], e["max"], e["ping"]]
		var b := _button("%s   —   %s" % [e["name"], info], func(): net.join(e["host"], e["port"]))
		b.disabled = e["players"] >= 0 and e["players"] >= e["max"]
		servers_box.add_child(b)
	if net.servers.is_empty():
		servers_box.add_child(_label("Серверов пока нет — добавьте адрес своего сервера ниже (как запустить сервер: файл SERVER.md).", 14, Color(0.6, 0.65, 0.7)))


func show_menu(on: bool) -> void:
	menu.visible = on
	if on:
		_refresh_hosts()
		show_page("home")
	else:
		net.stop_discovery()


# ---------------------------------------------------------------- pause, death and victory
func _build_pause() -> void:
	var p := _center_panel(460)
	pause_panel = p.get_parent()
	var v := VBoxContainer.new()
	p.add_child(v)
	v.add_child(_label("ПАУЗА", 30, ACCENT))
	v.add_child(_label("Esc — продолжить. Мышь — обзор, ЛКМ — огонь, ПКМ — прицел, WASD, Shift — бег, R — перезарядка, X — флаеры, 1-6 — оружие, C/V/B — манёвры." if desktop
		else "Тяните по экрану — обзор, слева — тяга (у пехоты — джойстик ходьбы), справа — огонь и оружие.", 15, MUTED))
	v.add_child(_accent(_button("Продолжить", func(): resume.emit())))
	v.add_child(_button("Выйти в меню", func(): to_menu.emit()))


func show_pause(on: bool, online: bool) -> void:
	pause_panel.visible = on
	(pause_panel.get_child(0).get_child(0).get_child(0) as Label).text = "ПАУЗА" if not online else "МЕНЮ (бой идёт)"


func _build_death() -> void:
	var p := _center_panel(760)
	death_panel = p.get_parent()
	var v := VBoxContainer.new()
	p.add_child(v)
	v.add_child(_label("ВЫ ПОГИБЛИ", 30, Color(1, 0.4, 0.35)))
	death_text = _label("", 18)
	v.add_child(death_text)
	v.add_child(_label("Техника для следующего вылета:", 15, MUTED))
	for grp in D.GROUPS:
		var r := HBoxContainer.new()
		v.add_child(r)
		var gl := _label(grp[0], 15, MUTED)
		gl.custom_minimum_size = Vector2(130, 0)
		r.add_child(gl)
		for t in grp[1]:
			var b := _button(D.TYPES[t]["name"], _death_pick.bind(t), true)
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			b.custom_minimum_size = Vector2(0, 44 if desktop else 50)
			r.add_child(b)
			death_buttons[t] = b
	var r2 := HBoxContainer.new()
	v.add_child(r2)
	var go := _accent(_button("В бой", func(): respawn.emit(death_choice)))
	go.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r2.add_child(go)
	var back := _button("В меню", func(): to_menu.emit())
	back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r2.add_child(back)


func _death_pick(t: String) -> void:
	death_choice = t
	for k in death_buttons:
		death_buttons[k].button_pressed = k == t
	settings["vehicle"] = t
	settings_changed.emit()


func show_death(on: bool, attacker := "", wname := "", current := "") -> void:
	death_panel.visible = on
	if not on:
		return
	if attacker != "":
		death_text.text = "Вас уничтожил: %s (%s)" % [attacker, D.W_RU.get(wname, wname)]
		if wname == "headshot":
			death_text.text = "Хедшот от: %s" % attacker
	else:
		death_text.text = {"crash": "Крушение.", "zone": "Вы покинули зону боя."}.get(wname, "Уничтожен.")
	_death_pick(current)


func _build_victory() -> void:
	var p := _center_panel(560)
	victory_panel = p.get_parent()
	var v := VBoxContainer.new()
	p.add_child(v)
	v.add_child(_label("ПОБЕДА!", 44, ACCENT))
	v.add_child(_label("Все точки штурма захвачены", 20))
	victory_text = _label("", 17, MUTED)
	v.add_child(victory_text)
	var r := HBoxContainer.new()
	v.add_child(r)
	var again := _accent(_button("Новый бой", func(): restart.emit()))
	again.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.add_child(again)
	var back := _button("В меню", func(): to_menu.emit())
	back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.add_child(back)


func show_victory(on: bool, kills := 0, deaths := 0, secs := 0.0) -> void:
	victory_panel.visible = on
	if on:
		victory_text.text = "Время боя: %d:%02d · уничтожено: %d · потери: %d" % [int(secs) / 60, int(secs) % 60, kills, deaths]
