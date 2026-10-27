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
var tab_bots: Control
var tab_net: Control
var tab_buttons := []


func build(s: Dictionary, n: Node) -> void:
	settings = s
	net = n
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = _theme()
	_build_menu()
	_build_pause()
	_build_death()
	net.status.connect(func(t): status_label.text = t)
	net.hosts_changed.connect(_refresh_hosts)
	net.servers_changed.connect(_refresh_servers)


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
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
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
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(c)
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(min_w, 0)
	c.add_child(p)
	c.visible = false
	return p


# ---------------------------------------------------------------- main menu
func _build_menu() -> void:
	menu = MarginContainer.new()
	menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		menu.add_theme_constant_override("margin_" + side, 22)
	add_child(menu)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	menu.add_child(row)
	# left: title and vehicles
	var left := PanelContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 1.25
	row.add_child(left)
	var lv := VBoxContainer.new()
	left.add_child(lv)
	lv.add_child(_label("БОЕВОЙ ФРОНТ", 40, Color(1, 0.8, 0.4)))
	lv.add_child(_label("Прохоровка, Белгородская область — настоящая местность по спутниковым снимкам и картам", 16, Color(0.8, 0.85, 0.9)))
	var vscroll := ScrollContainer.new()
	vscroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	lv.add_child(vscroll)
	var sections := VBoxContainer.new()
	sections.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vscroll.add_child(sections)
	for sec in [["ВОЗДУШНАЯ ТЕХНИКА", D.AIR], ["НАЗЕМНАЯ ТЕХНИКА", D.GROUND]]:
		sections.add_child(_label(sec[0], 17, Color(1, 0.8, 0.4)))
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 10)
		grid.add_theme_constant_override("v_separation", 8)
		sections.add_child(grid)
		for t in sec[1]:
			var T: Dictionary = D.TYPES[t]
			var b := Button.new()
			b.toggle_mode = true
			b.text = "%s\n%s · %d HP" % [T["name"], D.kind_of(t), int(T["hp"])]
			b.tooltip_text = T["desc"]
			b.custom_minimum_size = Vector2(0, 64)
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.pressed.connect(_pick_vehicle.bind(t))
			grid.add_child(b)
			vehicle_buttons[t] = b
	var desc := _label("", 15, Color(0.85, 0.88, 0.9))
	desc.name = "Desc"
	lv.add_child(desc)
	lv.add_child(_label("Карта: © участники OpenStreetMap (ODbL) · Sentinel-2 cloudless 2020 © EOX (CC BY-NC-SA 4.0) · рельеф: AWS Terrain Tiles · текстуры: ambientCG, Poly Haven (CC0)", 11, Color(0.6, 0.65, 0.7)))
	# right: tabs
	var right := PanelContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(right)
	var rv := VBoxContainer.new()
	right.add_child(rv)
	var tabs := HBoxContainer.new()
	rv.add_child(tabs)
	for i in 2:
		var tb := _button(["Бой с ботами", "Онлайн"][i], _tab.bind(i), true)
		tb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tabs.add_child(tb)
		tab_buttons.append(tb)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	rv.add_child(scroll)
	var pages := VBoxContainer.new()
	pages.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(pages)
	tab_bots = VBoxContainer.new()
	pages.add_child(tab_bots)
	_stepper(tab_bots, "Самолёты-боты", "bp", 0, 4)
	_stepper(tab_bots, "Вертолёты-боты", "bh", 0, 4)
	_stepper(tab_bots, "Танки-боты", "bt", 0, 6)
	_stepper(tab_bots, "Сложность", "diff", 0, 2, func(v): return D.DIFF[v]["n"])
	_toggle(tab_bots, "Боты стреляют", "shoot")
	_toggle(tab_bots, "Бесконечные боеприпасы", "ammo")
	_common(tab_bots)
	var go := _button("В БОЙ", func(): start_bots.emit())
	go.custom_minimum_size = Vector2(0, 66)
	go.add_theme_font_size_override("font_size", 26)
	rv.add_child(go)
	go.name = "Go"
	tab_net = VBoxContainer.new()
	pages.add_child(tab_net)
	var nr := HBoxContainer.new()
	tab_net.add_child(nr)
	nr.add_child(_label("Позывной", 18))
	nick_edit = LineEdit.new()
	nick_edit.text = settings.get("nick", "")
	nick_edit.placeholder_text = "Игрок"
	nick_edit.max_length = 16
	nick_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nick_edit.text_changed.connect(func(t): settings["nick"] = t.strip_edges(); settings_changed.emit())
	nr.add_child(nick_edit)
	var sh := HBoxContainer.new()
	tab_net.add_child(sh)
	var sl := _label("СЕРВЕРЫ", 18, Color(1, 0.8, 0.4))
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sh.add_child(sl)
	sh.add_child(_button("Обновить", func(): net.refresh_servers(settings["servers"])))
	servers_box = VBoxContainer.new()
	tab_net.add_child(servers_box)
	var ar := HBoxContainer.new()
	tab_net.add_child(ar)
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
	tab_net.add_child(_label("ИГРА ПО WI-FI (без сервера)", 18, Color(1, 0.8, 0.4)))
	tab_net.add_child(_label("Все в одной Wi-Fi сети или на точке доступа с телефона: один создаёт игру, остальные подключаются.", 14, Color(0.8, 0.85, 0.9)))
	tab_net.add_child(_button("Создать игру", func(): start_online.emit()))
	tab_net.add_child(_label("Найденные игры:", 17))
	hosts_box = VBoxContainer.new()
	tab_net.add_child(hosts_box)
	var ir := HBoxContainer.new()
	tab_net.add_child(ir)
	ip_edit = LineEdit.new()
	ip_edit.placeholder_text = "IP хоста, напр. 192.168.1.5"
	ip_edit.text = settings.get("ip", "")
	ip_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ir.add_child(ip_edit)
	ir.add_child(_button("Подключиться", func(): settings["ip"] = ip_edit.text; settings_changed.emit(); net.join(ip_edit.text)))
	status_label = _label("", 16, Color(1, 0.8, 0.45))
	tab_net.add_child(status_label)
	var ips: Array = net.local_ips()
	tab_net.add_child(_label("Ваш IP: " + (", ".join(ips) if ips.size() > 0 else "нет сети"), 15, Color(0.7, 0.75, 0.8)))
	_pick_vehicle(settings["vehicle"])
	_tab(0)


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


func _tab(i: int) -> void:
	for k in tab_buttons.size():
		tab_buttons[k].button_pressed = k == i
	tab_bots.visible = i == 0
	tab_net.visible = i == 1
	var go: Control = menu.find_child("Go", true, false)
	if go:
		go.visible = i == 0
	if i == 1:
		net.start_discovery()
		net.refresh_servers(settings["servers"])
	else:
		net.stop_discovery()


func _pick_vehicle(t: String) -> void:
	settings["vehicle"] = t
	for k in vehicle_buttons:
		vehicle_buttons[k].button_pressed = k == t
	var d: Label = menu.find_child("Desc", true, false)
	d.text = D.TYPES[t]["desc"]
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
		_tab(0 if tab_bots.visible else 1)
	else:
		net.stop_discovery()


# ---------------------------------------------------------------- pause and death
func _build_pause() -> void:
	var p := _center_panel(420)
	pause_panel = p.get_parent()
	var v := VBoxContainer.new()
	p.add_child(v)
	v.add_child(_label("ПАУЗА", 30, Color(1, 0.8, 0.4)))
	v.add_child(_label("Управление: тяните по экрану — обзор/наведение, слева — тяга, справа — огонь. Клавиатура: W/S тяга, A/D (R/F) поворот/высота, пробел — огонь, X — флаеры, 1-4 — оружие, C/V/B — манёвры.", 15, Color(0.85, 0.88, 0.9)))
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
	v.add_child(_label("ТЕХНИКА УНИЧТОЖЕНА", 30, Color(1, 0.4, 0.35)))
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
	else:
		death_text.text = {"crash": "Крушение.", "zone": "Вы покинули зону боя."}.get(wname, "Уничтожен.")
	_death_pick(current)
