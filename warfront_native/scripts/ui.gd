extends Control
## Main menu, pause and death screens.

const D := preload("res://scripts/data.gd")

signal start_bots
signal start_online
signal respawn(type: String)
signal to_menu
signal resume
signal quality_changed(q: String)
signal settings_changed

var settings: Dictionary
var net: Node
var menu: Control
var pause_panel: Control
var death_panel: Control
var death_text: Label
var death_choice := ""
var death_buttons := {}
var vehicle_buttons := {}
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
	net.status.connect(func(t): status_label.text = t)
	net.hosts_changed.connect(_refresh_hosts)
	net.servers_changed.connect(_refresh_servers)


func _fit() -> void:
	position = Vector2.ZERO
	size = get_viewport_rect().size


# ---------------------------------------------------------------- look
static func _box(col: Color, rad := 14, border := Color(0, 0, 0, 0)) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = col
	b.set_corner_radius_all(rad)
	b.content_margin_left = 14
	b.content_margin_right = 14
	b.content_margin_top = 8
	b.content_margin_bottom = 8
	if border.a > 0.0:
		b.border_color = border
		b.set_border_width_all(2)
	return b


func _theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 20
	t.set_stylebox("normal", "Button", _box(Color(0.12, 0.15, 0.17, 0.92), 12, Color(1, 1, 1, 0.08)))
	t.set_stylebox("hover", "Button", _box(Color(0.18, 0.22, 0.25, 0.95), 12, Color(1, 1, 1, 0.15)))
	t.set_stylebox("pressed", "Button", _box(Color(0.85, 0.62, 0.22, 0.95), 12))
	t.set_stylebox("hover_pressed", "Button", _box(Color(0.9, 0.68, 0.28, 0.95), 12))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_pressed_color", "Button", Color(0.08, 0.06, 0.02))
	t.set_color("font_hover_pressed_color", "Button", Color(0.08, 0.06, 0.02))
	t.set_stylebox("panel", "PanelContainer", _box(Color(0.05, 0.07, 0.09, 0.82), 18))
	t.set_stylebox("normal", "LineEdit", _box(Color(0.1, 0.12, 0.14, 0.95), 10, Color(1, 1, 1, 0.15)))
	t.set_constant("separation", "VBoxContainer", 10)
	t.set_constant("separation", "HBoxContainer", 10)
	t.set_font_size("font_size", "Label", 19)
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
	b.custom_minimum_size = Vector2(0, 54)
	b.pressed.connect(cb)
	return b


func _center_panel(min_w: float) -> PanelContainer:
	var c := CenterContainer.new()
	add_child(c)
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(min_w, 0)
	c.add_child(p)
	c.visible = false
	return p


# ---------------------------------------------------------------- main menu
## Pages: home (play / vehicles / online / settings), garage with a turning 3D model, online, settings.
var pages := {}
var veh_label: Label
var garage_list: VBoxContainer
var garage_info: Label
var garage_title: Label
var garage_cat := 0
var cat_buttons: Array = []
var garage_pick := ""
var preview_holder: Node3D
var preview_cam: Camera3D


func _page(name: String) -> VBoxContainer:
	var m := MarginContainer.new()
	menu.add_child(m)
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 22)
	var v := VBoxContainer.new()
	m.add_child(v)
	pages[name] = m
	return v


func _header(parent: Control, title: String) -> void:
	var h := HBoxContainer.new()
	parent.add_child(h)
	var back := _button("◀  Назад", func(): show_page("home"))
	back.custom_minimum_size = Vector2(170, 54)
	h.add_child(back)
	var l := _label(title, 30, Color(1, 0.8, 0.4))
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	h.add_child(l)
	var pad := Control.new()
	pad.custom_minimum_size = Vector2(170, 0)
	h.add_child(pad)


func _big(t: String, cb: Callable, accent := false) -> Button:
	var b := _button(t, cb)
	b.custom_minimum_size = Vector2(0, 74)
	b.add_theme_font_size_override("font_size", 28)
	if accent:
		b.add_theme_stylebox_override("normal", _box(Color(0.78, 0.55, 0.18, 0.95), 14))
		b.add_theme_stylebox_override("hover", _box(Color(0.88, 0.64, 0.24, 0.98), 14))
		b.add_theme_color_override("font_color", Color(0.08, 0.06, 0.02))
		b.add_theme_color_override("font_hover_color", Color(0.08, 0.06, 0.02))
	return b


func _build_menu() -> void:
	menu = Control.new()
	add_child(menu)
	menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# home
	var home := _page("home")
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 24)
	home.add_child(row)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 1.4
	row.add_child(left)
	var title := _label("БОЕВОЙ ФРОНТ", 64, Color(1, 0.8, 0.4))
	title.add_theme_constant_override("outline_size", 10)
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	left.add_child(title)
	var sub := _label("Прохоровка, Белгородская область — настоящая местность", 20, Color(0.92, 0.95, 1))
	sub.add_theme_constant_override("outline_size", 6)
	sub.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	left.add_child(sub)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(spacer)
	var card := PanelContainer.new()
	left.add_child(card)
	var cv := VBoxContainer.new()
	card.add_child(cv)
	cv.add_child(_label("ВАША ТЕХНИКА", 15, Color(0.75, 0.8, 0.85)))
	veh_label = _label("", 26)
	cv.add_child(veh_label)
	left.add_child(_label("Карта: © участники OpenStreetMap (ODbL) · Sentinel-2 cloudless 2020 © EOX (CC BY-NC-SA 4.0) · рельеф: AWS Terrain Tiles · текстуры: ambientCG, Poly Haven (CC0)", 11, Color(0.75, 0.78, 0.82)))
	var right := PanelContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(right)
	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", 14)
	right.add_child(rv)
	rv.add_child(_big("В БОЙ", func(): start_bots.emit(), true))
	rv.add_child(_big("ТЕХНИКА", func(): show_page("garage")))
	rv.add_child(_big("ОНЛАЙН", func(): show_page("online")))
	rv.add_child(_big("НАСТРОЙКИ", func(): show_page("settings")))
	# garage
	var gar := _page("garage")
	_header(gar, "ВЫБОР ТЕХНИКИ")
	var grow := HBoxContainer.new()
	grow.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grow.add_theme_constant_override("separation", 18)
	gar.add_child(grow)
	var gl := PanelContainer.new()
	gl.custom_minimum_size = Vector2(380, 0)
	grow.add_child(gl)
	var glv := VBoxContainer.new()
	gl.add_child(glv)
	var cats := HBoxContainer.new()
	glv.add_child(cats)
	for i in 3:
		var cb := _button(["Воздух", "Земля", "Пехота"][i], func(): pass, true)
		cb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cats.add_child(cb)
		cat_buttons.append(cb)
	for i in 3:
		cat_buttons[i].pressed.connect(func():
			garage_cat = i
			for k in 3:
				cat_buttons[k].button_pressed = k == i
			_fill_garage())
	cat_buttons[0].button_pressed = true
	var gscroll := ScrollContainer.new()
	gscroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	gscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	glv.add_child(gscroll)
	garage_list = VBoxContainer.new()
	garage_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gscroll.add_child(garage_list)
	var gr := PanelContainer.new()
	gr.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grow.add_child(gr)
	var grv := VBoxContainer.new()
	gr.add_child(grv)
	garage_title = _label("", 30, Color(1, 0.85, 0.5))
	grv.add_child(garage_title)
	var svc := SubViewportContainer.new()
	svc.stretch = true
	svc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	svc.custom_minimum_size = Vector2(0, 220)
	grv.add_child(svc)
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
	garage_info = _label("", 16, Color(0.88, 0.9, 0.94))
	grv.add_child(garage_info)
	grv.add_child(_big("ВЫБРАТЬ", func(): _pick_vehicle(garage_pick); show_page("home"), true))
	# online
	var on := _page("online")
	_header(on, "ОНЛАЙН")
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
	# settings
	var st := _page("settings")
	_header(st, "НАСТРОЙКИ")
	var srow := HBoxContainer.new()
	srow.size_flags_vertical = Control.SIZE_EXPAND_FILL
	srow.add_theme_constant_override("separation", 18)
	st.add_child(srow)
	var sp1 := PanelContainer.new()
	sp1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	srow.add_child(sp1)
	var s1 := VBoxContainer.new()
	sp1.add_child(s1)
	s1.add_child(_label("БОТЫ", 20, Color(1, 0.8, 0.4)))
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
	var s2 := VBoxContainer.new()
	sp2.add_child(s2)
	s2.add_child(_label("ИГРА", 20, Color(1, 0.8, 0.4)))
	_common(s2)
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
	s2.add_child(_label("ПК: мышь — обзор (щёлкните по экрану), ЛКМ — огонь, ПКМ — прицел, колесо — оружие, Esc — пауза. Пехота: WASD — ходьба, Shift — бег, R — перезарядка. Техника: W/S — тяга, A/D — поворот или высота, X — флаеры, C/V/B — манёвры Су-57.", 14, Color(0.8, 0.84, 0.9)))
	_pick_vehicle(settings["vehicle"])
	show_page("home")


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
	var sl := _label("СЕРВЕРЫ", 18, Color(1, 0.8, 0.4))
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
	parent.add_child(_label("ИГРА ПО WI-FI (без сервера)", 18, Color(1, 0.8, 0.4)))
	parent.add_child(_label("Все в одной Wi-Fi сети или на точке доступа с телефона: один создаёт игру, остальные подключаются.", 14, Color(0.8, 0.85, 0.9)))
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
	if name == "online":
		net.start_discovery()
		net.refresh_servers(settings["servers"])
		_refresh_hosts()
	else:
		net.stop_discovery()
	if name == "garage":
		garage_pick = settings["vehicle"]
		var t: Dictionary = D.TYPES[garage_pick]
		garage_cat = 2 if t["cat"] == "inf" else (1 if t["cat"] == "tank" else 0)
		_fill_garage()


func _fill_garage() -> void:
	for k in cat_buttons.size():
		cat_buttons[k].button_pressed = k == garage_cat
	for c in garage_list.get_children():
		c.queue_free()
	var list: Array = [D.AIR, D.GROUND, D.INF][garage_cat]
	for t in list:
		var T: Dictionary = D.TYPES[t]
		var b := _button("%s\n%s · %d HP" % [T["name"], D.kind_of(t), int(T["hp"])], _garage_select.bind(t), true)
		b.custom_minimum_size = Vector2(0, 70)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.button_pressed = t == garage_pick
		garage_list.add_child(b)
	if not list.has(garage_pick):
		_garage_select(list[0])
	else:
		_garage_select(garage_pick)


func _garage_select(t: String) -> void:
	garage_pick = t
	for b in garage_list.get_children():
		if b is Button:
			b.button_pressed = b.text.begins_with(D.TYPES[t]["name"] + "\n")
	var T: Dictionary = D.TYPES[t]
	garage_title.text = T["name"]
	var weapons: Array = []
	for s in T["slots"]:
		weapons.append("%s ×%d" % [s["n"], s["a"]])
	garage_info.text = "%s\nПрочность: %d · Скорость: до %d км/ч\nВооружение: %s" % [T["desc"], int(T["hp"]), int(T["vmax"] * 3.6), ", ".join(weapons)]
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
	preview_cam.position = Vector3(0, r * 0.45, r * 2.6)
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
	minus.custom_minimum_size = Vector2(58, 50)
	plus.custom_minimum_size = Vector2(58, 50)
	r.add_child(minus)
	r.add_child(val)
	r.add_child(plus)
	show.call()


func _toggle(parent: Control, title: String, key: String) -> void:
	var b := _button(title, func(): pass, true)
	b.button_pressed = settings[key]
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
	settings["vehicle"] = t
	veh_label.text = "%s  ·  %s" % [D.TYPES[t]["name"], D.kind_of(t)]
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


# ---------------------------------------------------------------- pause and death
func _build_pause() -> void:
	var p := _center_panel(420)
	pause_panel = p.get_parent()
	var v := VBoxContainer.new()
	p.add_child(v)
	v.add_child(_label("ПАУЗА", 30, Color(1, 0.8, 0.4)))
	v.add_child(_label("Телефон: тяните по экрану — обзор, слева — тяга (у пехоты — джойстик ходьбы), справа — огонь. ПК: мышь — обзор, ЛКМ — огонь, ПКМ — прицел, WASD, Shift — бег, R — перезарядка, X — флаеры, 1-4 — оружие, C/V/B — манёвры.", 15, Color(0.85, 0.88, 0.9)))
	v.add_child(_button("Продолжить", func(): resume.emit()))
	v.add_child(_button("Выйти в меню", func(): to_menu.emit()))


func show_pause(on: bool, online: bool) -> void:
	pause_panel.visible = on
	(pause_panel.get_child(0).get_child(0).get_child(0) as Label).text = "ПАУЗА" if not online else "МЕНЮ (бой идёт)"


func _build_death() -> void:
	var p := _center_panel(640)
	death_panel = p.get_parent()
	var v := VBoxContainer.new()
	p.add_child(v)
	v.add_child(_label("ВЫ ПОГИБЛИ", 30, Color(1, 0.4, 0.35)))
	death_text = _label("", 18)
	v.add_child(death_text)
	var g := GridContainer.new()
	g.columns = 3
	v.add_child(g)
	for t in D.ORDER:
		var b := _button(D.TYPES[t]["name"], _death_pick.bind(t), true)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		g.add_child(b)
		death_buttons[t] = b
	var r := HBoxContainer.new()
	v.add_child(r)
	var go := _button("В бой", func(): respawn.emit(death_choice))
	go.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.add_child(go)
	var back := _button("В меню", func(): to_menu.emit())
	back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.add_child(back)


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
