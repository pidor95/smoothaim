extends Node3D
## Level controller: environment, house, player, HUD, NPC spawning,
## the player's orders, slow motion and the pause menu.

const MAX_BODIES := 10
const TARGET_ALIVE := 4

var house: House
var player: Player
var hud: Hud
var sun := DirectionalLight3D.new()
var kills := 0
var slowmo := false
var auto_spawn := true

var _bodies: Array[Npc] = []
var _spawn_timer := 4.0
var _pause_layer := CanvasLayer.new()
var _pause_panel: Control
var _slowmo_button: Button
var _auto_button: Button
var _ai_button: Button
var _guns_button: Button
var _weapon_layer := CanvasLayer.new()
var _weapon_panel: Control
var _weapon_cards: Array = [] # [button, slot index]
var _weapon_tabs: Array = [] # [tab button, page]
var _immortal_button: Button
var _xray_button: Button
var weapon_menu_open := false
var _npc_layer := CanvasLayer.new()
var _npc_panel: Control
var _npc_cards: Array = [] # [button, kind]
var npc_menu_open := false

## NPC menu cards: [kind, title, description].
const NPC_KINDS := [
	[Npc.SpawnKind.UNARMED, "БЕЗ ОРУЖИЯ", "Безоружные манекены.\nБродят, в панике убегают,\nслушаются приказов."],
	[Npc.SpawnKind.ARMED, "С ПИСТОЛЕТОМ", "У каждого Colt M1911.\nВ безвыходном положении\nможет застрелиться."],
	[Npc.SpawnKind.MIXED, "ВПЕРЕМЕШКУ", "Примерно каждый третий\nс пистолетом,\nостальные без оружия."],
]


func _ready() -> void:
	add_to_group("settings_listeners")
	Blood.clear()
	Gore.clear()
	Engine.time_scale = 1.0
	AudioServer.playback_speed_scale = 1.0
	_build_environment()

	house = ShopLevel.new() if Settings.level == "shop" else House.new()
	add_child(house)

	player = Player.new()
	player.transform = house.player_spawn
	add_child(player)

	var hud_layer := CanvasLayer.new()
	add_child(hud_layer)
	hud = Hud.new()
	hud.player = player
	hud.game = self
	hud_layer.add_child(hud)
	_build_pause_menu()
	_build_weapon_menu()
	_build_npc_menu()
	player.capture_mouse()

	# let the navigation map sync before NPCs start pathing
	await get_tree().physics_frame
	await get_tree().physics_frame
	for i in TARGET_ALIVE:
		spawn_npc(house.npc_spawns[i])


func _build_environment() -> void:
	var env := Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.17, 0.4, 0.78)
	sm.sky_horizon_color = Color(0.66, 0.77, 0.88)
	sm.ground_horizon_color = Color(0.66, 0.77, 0.88)
	sm.ground_bottom_color = Color(0.32, 0.35, 0.4)
	sm.sky_cover = load("res://assets/textures/clouds.png")
	sm.sky_cover_modulate = Color(1, 1, 1, 0.85)
	sm.sun_angle_max = 25.0
	sky.sky_material = sm
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_color = Color(0.8, 0.8, 0.8)
	env.ambient_light_sky_contribution = 0.35
	env.ambient_light_energy = 0.7
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.05
	env.glow_enabled = true
	env.glow_intensity = 0.35
	env.glow_hdr_threshold = 1.2
	env.fog_enabled = true
	env.fog_light_color = Color(0.72, 0.77, 0.83)
	env.fog_density = 0.0018
	env.fog_sky_affect = 0.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	sun.rotation_degrees = Vector3(-52, -38, 0)
	sun.light_energy = 1.5
	sun.light_color = Color(1.0, 0.97, 0.92)
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 45.0
	sun.shadow_blur = 1.5
	add_child(sun)
	on_settings_changed()


func on_settings_changed() -> void:
	sun.shadow_enabled = Settings.shadows


# ------------------------------------------------------------------ NPCs

## `armed`: -1 = as chosen in the NPC menu, 0 / 1 = force.
func spawn_npc(pos: Vector3, armed := -1) -> Npc:
	var npc := Npc.new()
	npc.position = pos
	npc.rotation.y = randf() * TAU
	npc.armed = Npc.roll_armed() if armed < 0 else armed == 1
	add_child(npc)
	npc.died.connect(_on_npc_died)
	return npc


## Spawns a mannequin a few metres in front of the player (snapped to the navmesh).
func spawn_in_front(armed := -1) -> void:
	var cam := player.camera
	var fwd := -cam.global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var from := cam.global_position
	var dist := 4.0
	var q := PhysicsRayQueryParameters3D.create(from, from + fwd * dist, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		dist = maxf(from.distance_to(hit.position) - 0.6, 1.2)
	var target := player.global_position + fwd * dist
	var map := get_world_3d().navigation_map
	var p := NavigationServer3D.map_get_closest_point(map, target)
	if p == Vector3.ZERO or p.distance_to(target) > 3.0:
		p = target
	var npc := spawn_npc(p + Vector3.UP * 0.05, armed)
	var to_player := player.global_position - npc.global_position
	npc.rotation.y = atan2(-to_player.x, -to_player.z)
	Sfx.play("ui_click")


func _alive_count() -> int:
	var n := 0
	for npc in get_tree().get_nodes_in_group("npcs"):
		if not npc.dead:
			n += 1
	return n


func _on_npc_died(npc: Npc, _headshot: bool) -> void:
	if not npc.suicided:
		kills += 1
	_bodies.append(npc)
	while _bodies.size() > MAX_BODIES:
		var old: Npc = _bodies.pop_front()
		if is_instance_valid(old):
			old.queue_free()


func clear_bodies() -> void:
	for b in _bodies:
		if is_instance_valid(b):
			b.queue_free()
	_bodies.clear()
	for g in get_tree().get_nodes_in_group("dropped_guns"):
		g.queue_free()
	Blood.clear()
	Gore.clear()


# ------------------------------------------------------------------ orders

## Shouts order `index` (Npc.ORDERS). The mannequin under the crosshair takes
## it; with nobody there, everyone close by who can see the player does.
func give_order(index: int) -> void:
	var o: Array = Npc.ORDERS[index]
	var targets := _order_targets()
	var obeyed := 0
	for npc in targets:
		if npc.order(o[0]):
			obeyed += 1
	var note := ""
	if targets.is_empty():
		note = "никого рядом"
	elif obeyed == 0:
		note = "не реагирует"
	hud.order_feedback(o[1], note)


func _order_targets() -> Array[Npc]:
	var out: Array[Npc] = []
	var from := player.camera.global_position
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, from - player.camera.global_basis.z * 40.0, 1 | 2 | 4)
	q.exclude = [player.get_rid()]
	var hit := space.intersect_ray(q)
	if not hit.is_empty() and hit.collider.has_meta("npc"):
		var n: Npc = hit.collider.get_meta("npc")
		if is_instance_valid(n) and not n.dead:
			out.append(n)
			return out
	for n in get_tree().get_nodes_in_group("npcs"):
		if n.dead or n.center().distance_to(from) > 14.0:
			continue
		var los := PhysicsRayQueryParameters3D.create(from, n.center(), 1 | 2)
		los.exclude = [player.get_rid()]
		if space.intersect_ray(los).is_empty():
			out.append(n)
	return out


func _physics_process(delta: float) -> void:
	_spawn_timer -= delta
	if auto_spawn and _spawn_timer <= 0.0:
		_spawn_timer = 5.0
		if _alive_count() < TARGET_ALIVE:
			var options: Array[Vector3] = []
			for p in house.npc_spawns:
				if p.distance_to(player.global_position) > 9.0:
					options.append(p)
			if not options.is_empty():
				spawn_npc(options[randi() % options.size()])


func _process(_delta: float) -> void:
	hud.set_stats(kills, _alive_count(), slowmo)
	if not player.touch_mode:
		if Input.is_action_just_pressed("spawn_npc"):
			spawn_in_front()
		if Input.is_action_just_pressed("slowmo"):
			toggle_slowmo()
		if Input.is_action_just_pressed("toggle_ai"):
			toggle_ai()
		if Input.is_action_just_pressed("weapon_menu"):
			toggle_weapon_menu()
		if Input.is_action_just_pressed("npc_menu"):
			toggle_npc_menu()
		for i in Npc.ORDERS.size():
			if Input.is_action_just_pressed("order_%d" % (i + 1)):
				give_order(i)


## AI on/off: with AI off mannequins stand still (they still react to hits).
func toggle_ai() -> void:
	Npc.ai_enabled = not Npc.ai_enabled
	if _ai_button:
		_ai_button.text = "ИИ манекенов: ВКЛ" if Npc.ai_enabled else "ИИ манекенов: ВЫКЛ"


func toggle_slowmo() -> void:
	slowmo = not slowmo
	Engine.time_scale = 0.3 if slowmo else 1.0
	AudioServer.playback_speed_scale = 0.55 if slowmo else 1.0
	if _slowmo_button:
		_slowmo_button.text = "Замедление: ВКЛ" if slowmo else "Замедление: ВЫКЛ"


# ------------------------------------------------------------------ pause

## Lives outside the pausable tree so Esc / Android "back" can also unpause.
class PauseWatcher extends Node:
	var game: Node

	func _unhandled_input(event: InputEvent) -> void:
		if event.is_action_pressed("pause"):
			_back()
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("weapon_menu") and game.weapon_menu_open:
			game.toggle_weapon_menu()
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("npc_menu") and game.npc_menu_open:
			game.toggle_npc_menu()
			get_viewport().set_input_as_handled()

	func _back() -> void:
		if game.weapon_menu_open:
			game.toggle_weapon_menu()
		elif game.npc_menu_open:
			game.toggle_npc_menu()
		else:
			game.toggle_pause()

	func _notification(what: int) -> void:
		if what == NOTIFICATION_WM_GO_BACK_REQUEST:
			_back()
		elif what == NOTIFICATION_APPLICATION_FOCUS_OUT and game.player and game.player.touch_mode and not get_tree().paused:
			game.toggle_pause()


func toggle_pause() -> void:
	var p := not get_tree().paused
	get_tree().paused = p
	_pause_panel.visible = p
	hud.reset_touches()
	if p:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		Settings.save_settings()
		player.capture_mouse()


func _build_pause_menu() -> void:
	_pause_layer.layer = 10
	_pause_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_pause_layer)
	var watcher := PauseWatcher.new()
	watcher.game = self
	_pause_layer.add_child(watcher)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.theme = UiKit.make_theme()
	_pause_layer.add_child(root)
	_pause_panel = root
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 34)
	panel.add_child(cols)

	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 10)
	cols.add_child(left)
	left.add_child(UiKit.label("ПАУЗА", 44, Color(1, 0.2, 0.2)))
	left.add_child(UiKit.button("Продолжить", toggle_pause))
	left.add_child(UiKit.button("Оружие", func():
		toggle_pause()
		toggle_weapon_menu()))
	left.add_child(UiKit.button("+1 манекен", func(): spawn_in_front()))
	left.add_child(UiKit.button("+5 манекенов", func():
		for i in 5:
			spawn_npc(house.npc_spawns[randi() % house.npc_spawns.size()])))
	left.add_child(UiKit.button("Убрать тела и кровь", clear_bodies))
	_slowmo_button = UiKit.button("Замедление: ВЫКЛ", toggle_slowmo)
	left.add_child(_slowmo_button)
	_auto_button = UiKit.button("Авто-спавн: ВКЛ", func():
		auto_spawn = not auto_spawn
		_auto_button.text = "Авто-спавн: ВКЛ" if auto_spawn else "Авто-спавн: ВЫКЛ")
	left.add_child(_auto_button)
	_ai_button = UiKit.button("ИИ манекенов: ВКЛ" if Npc.ai_enabled else "ИИ манекенов: ВЫКЛ", toggle_ai)
	left.add_child(_ai_button)
	left.add_child(UiKit.button("Выбор манекенов", func():
		toggle_pause()
		toggle_npc_menu()))
	left.add_child(UiKit.button("Главное меню", _to_menu))
	for b in left.get_children():
		if b is Button:
			b.custom_minimum_size.y = 44

	var right := VBoxContainer.new()
	right.custom_minimum_size.x = 560
	right.add_theme_constant_override("separation", 10)
	cols.add_child(right)
	right.add_child(UiKit.label("НАСТРОЙКИ", 34))
	right.add_child(UiKit.settings_box())
	root.visible = false


# ------------------------------------------------------------------ weapon menu

func toggle_weapon_menu() -> void:
	weapon_menu_open = not weapon_menu_open
	get_tree().paused = weapon_menu_open
	_weapon_panel.visible = weapon_menu_open
	hud.reset_touches()
	if weapon_menu_open:
		_refresh_weapon_cards()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		player.capture_mouse()


func _toggle_page(desc: String) -> VBoxContainer:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 18)
	page.custom_minimum_size = Vector2(784, 330)
	page.alignment = BoxContainer.ALIGNMENT_CENTER
	page.add_child(UiKit.label(desc, 24, Color(0.85, 0.85, 0.85)))
	var b := UiKit.button("", func(): pass, 420)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	page.add_child(b)
	return page


func _show_weapon_tab(page: Control) -> void:
	for t in _weapon_tabs:
		t[1].visible = t[1] == page
		t[0].button_pressed = t[1] == page


func _refresh_weapon_cards() -> void:
	_immortal_button.text = "БЕССМЕРТИЕ: " + ("ВКЛ" if Player.immortal else "ВЫКЛ")
	_xray_button.text = "РЕНТГЕН: " + ("ВКЛ" if Npc.xray else "ВЫКЛ")
	for c in _weapon_cards:
		var b: Button = c[0]
		var held: bool = player.weapon.slots[c[1]] == player.weapon.current
		b.text = "В РУКАХ" if held else "ВЗЯТЬ"
		b.disabled = held


func _build_weapon_menu() -> void:
	_weapon_layer.layer = 11
	_weapon_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_weapon_layer)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.theme = UiKit.make_theme()
	_weapon_layer.add_child(root)
	_weapon_panel = root
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 16)
	center.add_child(col)
	# tabs: weapons | immortality | x-ray
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 12)
	tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(tabs)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	col.add_child(row)
	var immortal_page := _toggle_page("Пули манекенов не наносят вам урона.\nБез бессмертия: 100 здоровья, раны медленно\nзатягиваются, при смерти — возрождение на старте.")
	_immortal_button = immortal_page.get_child(1)
	_immortal_button.pressed.connect(func():
		Player.immortal = not Player.immortal
		_refresh_weapon_cards())
	col.add_child(immortal_page)
	var xray_page := _toggle_page("Манекены просвечиваются: видно скелет, сердце\nи каждый раневой канал (красные линии по ходу пули).\nЧасти тела светятся от синего к оранжевому по урону.")
	_xray_button = xray_page.get_child(1)
	_xray_button.pressed.connect(func():
		Npc.set_xray(not Npc.xray, get_tree())
		_refresh_weapon_cards())
	col.add_child(xray_page)
	for t in [["ОРУЖИЕ", row], ["БЕССМЕРТИЕ", immortal_page], ["РЕНТГЕН ПОВРЕЖДЕНИЙ", xray_page]]:
		var page: Control = t[1]
		var tb := UiKit.button(t[0], func(): _show_weapon_tab(page), 250)
		tb.toggle_mode = true
		tabs.add_child(tb)
		_weapon_tabs.append([tb, page])
	_show_weapon_tab(row)
	for i in player.weapon.slots.size():
		var d: Dictionary = player.weapon.slots[i].def
		var card := PanelContainer.new()
		row.add_child(card)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 6)
		card.add_child(v)
		var icon := TextureRect.new()
		icon.texture = load("res://assets/ui/icon_%s.png" % d.id)
		icon.custom_minimum_size = Vector2(380, 190)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		v.add_child(icon)
		v.add_child(UiKit.label(d.title, 34, Color(1, 1, 1)))
		v.add_child(UiKit.label(d.desc, 20, Color(0.75, 0.75, 0.75)))
		for line in d.stats:
			v.add_child(UiKit.label(line, 22, Color(0.9, 0.85, 0.7)))
		var idx := i
		var b := UiKit.button("ВЗЯТЬ", func():
			player.weapon.select(idx)
			toggle_weapon_menu(), 380)
		v.add_child(b)
		_weapon_cards.append([b, i])
	var close := UiKit.button("ЗАКРЫТЬ", toggle_weapon_menu, 300)
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(close)
	root.visible = false


# ------------------------------------------------------------------ NPC menu

func toggle_npc_menu() -> void:
	npc_menu_open = not npc_menu_open
	get_tree().paused = npc_menu_open
	_npc_panel.visible = npc_menu_open
	hud.reset_touches()
	if npc_menu_open:
		_refresh_npc_cards()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		player.capture_mouse()


func _refresh_npc_cards() -> void:
	for c in _npc_cards:
		var b: Button = c[0]
		var chosen: bool = c[1] == Npc.spawn_kind
		b.text = "ВЫБРАНО" if chosen else "ВЫБРАТЬ"
		b.disabled = chosen


func _build_npc_menu() -> void:
	_npc_layer.layer = 11
	_npc_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_npc_layer)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.theme = UiKit.make_theme()
	_npc_layer.add_child(root)
	_npc_panel = root
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 16)
	center.add_child(col)
	col.add_child(UiKit.label("МАНЕКЕНЫ", 44, Color(1, 0.2, 0.2)))
	col.add_child(UiKit.label("Кто появляется: кнопка «+», авто-спавн, «+5»", 20, Color(0.75, 0.75, 0.75)))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	col.add_child(row)
	for k in NPC_KINDS:
		var kind: int = k[0]
		var card := PanelContainer.new()
		row.add_child(card)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 8)
		card.add_child(v)
		v.add_child(UiKit.label(k[1], 32, Color(1, 1, 1)))
		var desc := UiKit.label(k[2], 20, Color(0.75, 0.75, 0.75))
		desc.custom_minimum_size.y = 90
		v.add_child(desc)
		var b := UiKit.button("ВЫБРАТЬ", func():
			Npc.spawn_kind = kind
			_refresh_npc_cards(), 300)
		v.add_child(b)
		_npc_cards.append([b, kind])
		if kind != Npc.SpawnKind.MIXED:
			v.add_child(UiKit.button("+1 СЕЙЧАС", func():
				toggle_npc_menu()
				spawn_in_front(1 if kind == Npc.SpawnKind.ARMED else 0), 300))
	var close := UiKit.button("ЗАКРЫТЬ", toggle_npc_menu, 300)
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(close)
	root.visible = false


func _to_menu() -> void:
	Settings.save_settings()
	get_tree().paused = false
	Engine.time_scale = 1.0
	AudioServer.playback_speed_scale = 1.0
	Blood.clear()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
