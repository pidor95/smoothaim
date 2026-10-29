extends Node3D
## Level controller: environment, the front, player, HUD, the war (two
## teams of soldiers with tickets and reinforcements that keep coming on
## their own), the player's orders and the pause menu.

const MAX_BODIES := 12
## Soldiers on their feet per side, and each side's tickets (lives).
const TEAM_ALIVE := 9
const TICKETS := 120
## The war is fought round the player: reinforcements come up and posts are
## taken this close to him (the front is far bigger than that).
const ACTION_RADIUS := 75.0
## This share of the men holding the line are snipers.
const SNIPER_CHANCE := 0.18

var house: TrenchLevel
var player: Player
var hud: Hud
var sun := DirectionalLight3D.new()
var kills := 0
var tickets := [TICKETS, TICKETS]
var winner := -1 # side that won the round, while the banner shows
var _round_end_t := 0.0
var _reinforce_t := [2.0, 2.0]
var _drone_t := randf_range(25.0, 45.0)
var _team_points: Array = [[], []] # [team] -> reinforcement points

var _bodies: Array[Npc] = []
var _pause_layer := CanvasLayer.new()
var _pause_panel: Control
var _weapon_layer := CanvasLayer.new()
var _weapon_panel: Control
var _weapon_cards: Array = [] # [button, slot index]
var _weapon_tabs: Array = [] # [tab button, page]
var _immortal_button: Button
var weapon_menu_open := false
var _loading_layer: CanvasLayer
var _loading_label: Label


func _ready() -> void:
	add_to_group("settings_listeners")
	Blood.clear()
	Gore.clear()
	Engine.time_scale = 1.0
	AudioServer.playback_speed_scale = 1.0
	_build_environment()

	house = TrenchLevel.new()
	add_child(house)
	if not house.is_built:
		_show_loading()
		await house.built
		_loading_layer.queue_free()

	player = Player.new()
	player.transform = house.player_spawn
	add_child(player)

	var hud_layer := CanvasLayer.new()
	add_child(hud_layer)
	hud = Hud.new()
	hud.player = player
	hud.game = self
	hud_layer.add_child(hud)
	add_child(Bodycam.new())
	_build_pause_menu()
	_build_weapon_menu()
	player.capture_mouse()
	_setup_teams()

	# let the navigation map sync before soldiers start pathing
	await get_tree().physics_frame
	await get_tree().physics_frame
	for t in 2:
		for i in TEAM_ALIVE:
			spawn_soldier(t, -1, true)


## While the front is being put together: a black screen with the progress.
func _show_loading() -> void:
	_loading_layer = CanvasLayer.new()
	_loading_layer.layer = 20
	add_child(_loading_layer)
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.02, 0.02)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_loading_layer.add_child(bg)
	_loading_label = UiKit.label("ЗАГРУЗКА ФРОНТА…", 44, Color(1, 1, 1))
	_loading_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_loading_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_loading_label.grow_vertical = Control.GROW_DIRECTION_BOTH
	_loading_layer.add_child(_loading_label)


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
	sun.rotation_degrees = Vector3(-52, -38, 0)
	sun.light_energy = 1.5
	sun.light_color = Color(1.0, 0.97, 0.92)
	if true:
		# overcast autumn front: low brown-grey sky, haze, weak sun
		sm.sky_top_color = Color(0.36, 0.35, 0.34)
		sm.sky_horizon_color = Color(0.62, 0.58, 0.53)
		sm.ground_horizon_color = Color(0.62, 0.58, 0.53)
		sm.ground_bottom_color = Color(0.25, 0.22, 0.2)
		sm.sky_cover_modulate = Color(0.55, 0.53, 0.52, 1.0)
		sm.sun_angle_max = 40.0
		env.ambient_light_energy = 0.6
		env.ambient_light_sky_contribution = 0.6
		env.fog_light_color = Color(0.44, 0.42, 0.4)
		env.fog_density = 0.016
		env.tonemap_exposure = 0.92
		sun.rotation_degrees = Vector3(-30, -150, 0)
		sun.light_energy = 0.6
		sun.light_color = Color(1.0, 0.9, 0.78)
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 55.0
	sun.shadow_blur = 1.5
	add_child(sun)
	on_settings_changed()


func on_settings_changed() -> void:
	sun.shadow_enabled = Settings.shadows


# ------------------------------------------------------------------ NPCs

## Reinforcement points and firing posts per side (empties in the map).
func _setup_teams() -> void:
	_team_points = house.team_spawns
	Npc.war_posts = house.team_posts


## The points of `pts` within ACTION_RADIUS of the player (the nearest few
## when none are).
func _near_player(pts: Array, radius := ACTION_RADIUS) -> Array:
	var at := player.global_position
	var out := pts.filter(func(p): return Vector2(p.x - at.x, p.z - at.z).length() < radius)
	if out.size() < 3:
		out = pts.duplicate()
		out.sort_custom(func(a, b): return a.distance_squared_to(at) < b.distance_squared_to(at))
		out = out.slice(0, mini(6, out.size()))
	return out


## A soldier of `team` at a reinforcement point near the fighting: some hold
## their own line, the rest go over the top for the enemy's.
## `assault`: -1 = by chance, 0 / 1 = force. `start`: the first wave also
## takes the front posts straight away.
func spawn_soldier(team: int, assault_mode := -1, start := false) -> Npc:
	var pts: Array = _near_player(_team_points[team])
	var assault := randf() < (0.4 if team == 0 else 0.55) if assault_mode < 0 else assault_mode == 1
	var posts: Array = _near_player(Npc.war_posts[1 - team if assault else team], ACTION_RADIUS * 0.8)
	var at: Vector3 = pts[randi() % pts.size()]
	if start and not assault:
		var own: Array = _near_player(Npc.war_posts[team], ACTION_RADIUS * 0.8)
		at = own[randi() % own.size()]
	# now and then a sniper with an SVD: he takes a post up in a building
	var sniper := not assault and randf() < SNIPER_CHANCE
	var npc := spawn_npc(at + Vector3(randf_range(-0.4, 0.4), 0, randf_range(-0.4, 0.4)), team, "svd" if sniper else "rifle")
	npc.role = "assault" if assault else "hold"
	if sniper:
		var high := (Npc.war_posts[team] as Array).filter(func(p): return p.y > 3.0)
		high = _near_player(high, ACTION_RADIUS * 1.6) if not high.is_empty() else high
		if not high.is_empty():
			posts = high
	if not posts.is_empty():
		npc.post = posts[randi() % posts.size()]
	return npc


## The enemy sends an FPV drone from behind his lines after the player or
## one of the player's side.
func send_enemy_drone() -> FpvDrone:
	var targets: Array[Node3D] = []
	if not player.dead:
		targets += [player, player]
	for n in get_tree().get_nodes_in_group("npcs"):
		if n.team == 0 and n.is_combatant():
			targets.append(n)
	if targets.is_empty() or _team_points[1].is_empty():
		return null
	var d := FpvDrone.new()
	d.team = 1
	d.target = targets[randi() % targets.size()]
	add_child(d)
	d.global_position = _team_points[1][randi() % _team_points[1].size()] + Vector3.UP * 12.0
	return d


func spawn_npc(pos: Vector3, team := 1, weapon := "rifle") -> Npc:
	var npc := Npc.new()
	npc.team = team
	npc.weapon = weapon
	npc.position = pos
	npc.rotation.y = 0.0 if team == 0 else PI
	add_child(npc)
	npc.died.connect(_on_npc_died)
	return npc


## Soldiers of `team` still in the fight (not dead, down or out cold).
func _alive(team: int) -> int:
	var n := 0
	for npc in get_tree().get_nodes_in_group("npcs"):
		if npc.team == team and npc.is_combatant():
			n += 1
	return n


func _living(team: int) -> int:
	var n := 0
	for npc in get_tree().get_nodes_in_group("npcs"):
		if npc.team == team and not npc.dead:
			n += 1
	return n


func _on_npc_died(npc: Npc, _headshot: bool) -> void:
	if npc.last_hit_by_player and npc.team == 1 and not npc.suicided:
		kills += 1
	if winner < 0:
		tickets[npc.team] = maxi(tickets[npc.team] - 1, 0)
		if tickets[npc.team] == 0:
			winner = 1 - npc.team
			_round_end_t = 8.0
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
	if player == null:
		return
	if winner >= 0:
		_round_end_t -= delta
		if _round_end_t <= 0.0:
			# next round: fresh tickets, the fight goes on
			winner = -1
			tickets = [TICKETS, TICKETS]
		return
	_drone_t -= delta
	if _drone_t <= 0.0:
		_drone_t = randf_range(35.0, 70.0)
		send_enemy_drone()
	for t in 2:
		_reinforce_t[t] -= delta
		if _reinforce_t[t] <= 0.0:
			_reinforce_t[t] = randf_range(2.5, 5.0)
			if _alive(t) < TEAM_ALIVE and _living(t) < TEAM_ALIVE + 5 and tickets[t] > _living(t):
				spawn_soldier(t)


func _process(_delta: float) -> void:
	if hud == null:
		if is_instance_valid(_loading_label):
			_loading_label.text = "ЗАГРУЗКА ФРОНТА… %d%%" % int(house.progress * 100.0)
		return
	hud.set_stats(kills, tickets, winner)
	if not player.touch_mode:
		if Input.is_action_just_pressed("weapon_menu"):
			toggle_weapon_menu()
		for i in Npc.ORDERS.size():
			if Input.is_action_just_pressed("order_%d" % (i + 1)):
				give_order(i)


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

	func _back() -> void:
		if game.weapon_menu_open:
			game.toggle_weapon_menu()
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
	left.add_child(UiKit.button("Убрать тела и кровь", clear_bodies))
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
	var immortal_page := _toggle_page("Пули и осколки не наносят вам урона.\nБез бессмертия: пятая пуля убивает, раны кровоточат,\nпри смерти — возрождение в своей траншее.")
	_immortal_button = immortal_page.get_child(1)
	_immortal_button.pressed.connect(func():
		Player.immortal = not Player.immortal
		_refresh_weapon_cards())
	col.add_child(immortal_page)
	for t in [["ОРУЖИЕ", row], ["БЕССМЕРТИЕ", immortal_page]]:
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


func _to_menu() -> void:
	Settings.save_settings()
	get_tree().paused = false
	Blood.clear()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
