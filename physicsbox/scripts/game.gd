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
## Medics per side on the field (the player can call his own over).
const MEDICS := 2
const MEDIC_CALL_RANGE := 150.0
## A medic of his side comes to the wounded player by himself this often
## (no call needed); the clock runs only while he is hurt.
const MEDIC_ROUND := 90.0
## First aid pouches lying about the trenches; one comes back after a while.
const MEDKIT_COUNT := 48
const MEDKIT_BACK := 90.0
const MEDKIT_SCENE := "res://assets/props/medkit.glb"

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
var _medic_wanted := [false, false]
var _medic_round_t := MEDIC_ROUND
var _medic_wait := 0.0
var _medkits: Array = [] # [node, gone_t]

var _bodies: Array[Npc] = []
var _pause_layer := CanvasLayer.new()
var _pause_panel: Control
var _weapon_layer := CanvasLayer.new()
var _weapon_panel: Control
var _weapon_cards: Array = [] # [button, slot index, item id, kind: take / carry / suppressor]
var _weapon_tabs: Array = [] # [tab button, page]
var _immortal_button: Button
var _holster_button: Button
var weapon_menu_open := false
var _loading_layer: CanvasLayer
var _loading_label: Label
var _report_t := 0.0


func _ready() -> void:
	add_to_group("settings_listeners")
	Blood.clear()
	Gore.clear()
	Gore.mesh("stump") # the gore meshes ready before the first blast, not during it
	Engine.time_scale = 1.0
	AudioServer.playback_speed_scale = 1.0
	_build_environment()

	_report("battle: building the front")
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
	_place_medkits()

	# let the navigation map sync before soldiers start pathing
	await get_tree().physics_frame
	await get_tree().physics_frame
	for t in 2:
		for i in TEAM_ALIVE:
			spawn_soldier(t, -1, true)
	_report("battle: started")


## A line in the log (user://logs, the menu's ЖУРНАЛ ОШИБОК shows the last
## run's): memory and what is going on, so a crash on a phone leaves a trace.
func _report(what: String) -> void:
	print("[%s] %s | mem %.0f MB (peak %.0f), video %.0f MB, objects %d, npcs %d, fps %d" % [
			Time.get_time_string_from_system(), what, OS.get_static_memory_usage() / 1048576.0,
			OS.get_static_memory_peak_usage() / 1048576.0, Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
			Performance.get_monitor(Performance.OBJECT_COUNT), get_tree().get_nodes_in_group("npcs").size(),
			Engine.get_frames_per_second()])

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
	# now and then a sniper with an SVD: he takes a post up in a building;
	# each side keeps a couple of medics
	var medic: bool = not assault and (_medic_wanted[team] or (_medics(team) < MEDICS and randf() < 0.35))
	var sniper := not assault and not medic and randf() < SNIPER_CHANCE
	var npc := spawn_npc(at + Vector3(randf_range(-0.4, 0.4), 0, randf_range(-0.4, 0.4)), team, "svd" if sniper else "rifle", medic)
	if medic:
		_medic_wanted[team] = false
		if team == 0 and player.wants_medic:
			npc.send_to.call_deferred(player)
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


func spawn_npc(pos: Vector3, team := 1, weapon := "rifle", medic := false) -> Npc:
	var npc := Npc.new()
	npc.team = team
	npc.weapon = weapon
	npc.medic = medic
	npc.position = pos
	npc.rotation.y = 0.0 if team == 0 else PI
	add_child(npc)
	npc.died.connect(_on_npc_died)
	return npc


func _medics(team: int) -> int:
	var n := 0
	for npc in get_tree().get_nodes_in_group("npcs"):
		if npc.team == team and npc.medic and not npc.dead:
			n += 1
	return n


## The player called for a medic: the nearest one of his side runs over;
## with none close by the next reinforcement is one. Returns the HUD line.
func call_medic() -> String:
	var m := medic_for_player()
	if m:
		return "Медик идёт — %d м" % int(m.global_position.distance_to(player.global_position))
	var best: Npc = null
	var best_d := MEDIC_CALL_RANGE
	for npc in get_tree().get_nodes_in_group("npcs"):
		if npc.team != 0 or not npc.medic or not npc.is_combatant():
			continue
		var d: float = npc.global_position.distance_to(player.global_position)
		if d < best_d:
			best = npc
			best_d = d
	if best and best.send_to(player):
		return "МЕДИК! — идёт, %d м" % int(best_d)
	_medic_wanted[0] = true
	_reinforce_t[0] = minf(_reinforce_t[0], 0.5)
	return "МЕДИК! — рядом нет, придёт с подкреплением"


## Every MEDIC_ROUND seconds of being hurt the nearest medic comes over and
## patches the player up on his own.
func _medic_rounds(delta: float) -> void:
	var hurt := not player.dead and (player.hits > 0 or player.bleed_rate > 0.5 or player.blood < Player.BLOOD_FULL - 400.0)
	if player.wants_medic:
		# called, but nobody is on the way (the medic was killed, none came
		# with the reinforcements yet): ask again every 20 s
		_medic_wait = _medic_wait + delta if medic_for_player() == null else 0.0
		if _medic_wait > 20.0:
			_medic_wait = 0.0
			call_medic()
		return
	if not hurt:
		_medic_round_t = MEDIC_ROUND
		return
	_medic_round_t -= delta
	if _medic_round_t > 0.0:
		return
	_medic_round_t = MEDIC_ROUND
	player.wants_medic = true
	var note := call_medic()
	if note.begins_with("МЕДИК! — идёт"):
		player.medic_note = "Медик сам идёт к вам: " + note.get_slice("идёт, ", 1)
	else:
		player.medic_note = "Медик придёт с подкреплением"
	player.medic_note_t = 3.0


## The medic on his way to (or working on) the player.
func medic_for_player() -> Npc:
	for npc in get_tree().get_nodes_in_group("npcs"):
		if npc.medic and not npc.dead and npc._patient == player:
			return npc
	return null


## First aid pouches about the trenches and the firing posts of both sides,
## on the ground; walking over one picks it up.
func _place_medkits() -> void:
	var spots: Array = []
	for t in 2:
		spots += house.team_posts[t]
		spots += house.team_spawns[t]
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var space := get_world_3d().direct_space_state
	var scene: PackedScene = load(MEDKIT_SCENE)
	var taken: Array[Vector3] = []
	var tries := 0
	while _medkits.size() < MEDKIT_COUNT and tries < 600 and not spots.is_empty():
		tries += 1
		var at: Vector3 = spots[rng.randi() % spots.size()] + Vector3(rng.randf_range(-1.2, 1.2), 0.0, rng.randf_range(-1.2, 1.2))
		if taken.any(func(p): return p.distance_to(at) < 12.0):
			continue
		var q := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 1.2, at + Vector3.DOWN * 2.0, 1)
		var hit := space.intersect_ray(q)
		if hit.is_empty() or hit.normal.y < 0.8:
			continue
		var kit: Node3D = scene.instantiate()
		add_child(kit)
		kit.global_transform = Transform3D(Basis(Vector3.UP, rng.randf() * TAU), hit.position)
		for mi in kit.find_children("*", "MeshInstance3D", true, false):
			(mi as MeshInstance3D).visibility_range_end = 70.0
			(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		taken.append(at)
		_medkits.append([kit, 0.0])


func _medkit_pickups(delta: float) -> void:
	if player.dead:
		return
	var at := player.global_position
	for m in _medkits:
		var kit: Node3D = m[0]
		if not kit.visible:
			m[1] -= delta
			if m[1] <= 0.0:
				kit.visible = true
			continue
		var d := kit.global_position - at
		if absf(d.y) < 1.4 and Vector2(d.x, d.z).length() < 1.1:
			kit.visible = false
			m[1] = MEDKIT_BACK
			player.pick_medkit()


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
	_medkit_pickups(delta)
	_medic_rounds(delta)
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


func _process(delta: float) -> void:
	if hud == null:
		if is_instance_valid(_loading_label):
			_loading_label.text = "ЗАГРУЗКА ФРОНТА… %d%%" % int(house.progress * 100.0)
		return
	hud.set_stats(kills, tickets, winner)
	_report_t += delta
	if _report_t > 30.0:
		_report_t = 0.0
		_report("battle")
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


## Every button's text and state from the current choices.
func _refresh_weapon_cards() -> void:
	_immortal_button.text = "БЕССМЕРТИЕ: " + ("ВКЛ" if Player.immortal else "ВЫКЛ")
	var w := player.weapon
	for c in _weapon_cards:
		var b: Button = c[0]
		var id: String = c[2]
		var i: int = c[1]
		var carried := Settings.carries(id)
		match c[3]:
			"take":
				var held: bool = w.slots[i] == w.current and not w.holstered
				b.text = "В РУКАХ" if held else "ВЗЯТЬ В РУКИ"
				b.disabled = held or not carried
			"carry":
				b.text = "В СНАРЯЖЕНИИ ✓" if carried else "УБРАНО — ВЕРНУТЬ"
			"suppressor":
				b.text = "ГЛУШИТЕЛЬ: УСТАНОВЛЕН" if Settings.suppressed.get(id, false) else "ГЛУШИТЕЛЬ: СНЯТ"
			"sight":
				var sd: Dictionary = w.slots[i].def.sights
				b.text = "ПРИЦЕЛ: " + String(sd[w.sight_of(w.slots[i])].title).to_upper()
	_holster_button.text = "ОРУЖИЕ УБРАНО (руки свободны)" if w.holstered else "УБРАТЬ ОРУЖИЕ ИЗ РУК"
	_holster_button.disabled = w.holstered


func _small_button(text: String, callback: Callable, width := 340.0) -> Button:
	var b := UiKit.button(text, callback, width)
	b.custom_minimum_size.y = 50
	b.add_theme_font_size_override("font_size", 22)
	return b


func _icon(id: String, sz: Vector2) -> TextureRect:
	var icon := TextureRect.new()
	icon.texture = load("res://assets/ui/icon_%s.png" % id)
	icon.custom_minimum_size = sz
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	return icon


func _card(parent: Control) -> VBoxContainer:
	var card := PanelContainer.new()
	parent.add_child(card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 5)
	card.add_child(v)
	return v


## Taking a gun in hand, leaving things out of the kit, the suppressor:
## the choices stick (Settings) and take effect at once.
func _set_carried(id: String, on: bool) -> void:
	Settings.loadout[id] = on
	player.weapon.apply_mods()
	Settings.save_settings()
	_refresh_weapon_cards()


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
	col.add_theme_constant_override("separation", 14)
	center.add_child(col)
	# tabs: weapons | kit | modifications | immortality, and the way out
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 10)
	tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(tabs)
	var w := player.weapon

	# ОРУЖИЕ: take a gun in hand, leave it out of the kit, put it away
	var guns := VBoxContainer.new()
	guns.add_theme_constant_override("separation", 12)
	col.add_child(guns)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	guns.add_child(row)
	for i in w.slots.size():
		var d: Dictionary = w.slots[i].def
		var v := _card(row)
		v.add_child(_icon(d.id, Vector2(300, 110)))
		v.add_child(UiKit.label(d.title, 28, Color(1, 1, 1)))
		v.add_child(UiKit.label(d.desc, 15, Color(0.75, 0.75, 0.75)))
		for line in d.stats:
			v.add_child(UiKit.label(line, 16, Color(0.9, 0.85, 0.7)))
		var idx := i
		var id: String = d.id
		var take := _small_button("ВЗЯТЬ В РУКИ", func():
			w.select(idx)
			toggle_weapon_menu(), 300)
		v.add_child(take)
		_weapon_cards.append([take, i, id, "take"])
		var carry := _small_button("", func(): _set_carried(id, not Settings.carries(id)), 300)
		v.add_child(carry)
		_weapon_cards.append([carry, i, id, "carry"])
	_holster_button = _small_button("", func():
		w.holster()
		_refresh_weapon_cards(), 520)
	_holster_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	guns.add_child(_holster_button)

	# СНАРЯЖЕНИЕ: grenades and drones taken along or left behind
	var kit := HBoxContainer.new()
	kit.add_theme_constant_override("separation", 16)
	kit.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(kit)
	for it in [["grenade", "Гранаты РГД-5", "Бросок анимацией, ×4,\nпополняются со временем."],
			["fpv", "FPV-дрон", "Камикадзе с зарядом ПГ-7:\nлетишь через его камеру."],
			["medkit", "Аптечка", "Бинты ×2, промедол, аптечка\nв начале боя и после гибели."]]:
		var v := _card(kit)
		v.add_child(_icon(it[0], Vector2(250, 125)))
		v.add_child(UiKit.label(it[1], 26, Color(1, 1, 1)))
		v.add_child(UiKit.label(it[2], 17, Color(0.75, 0.75, 0.75)))
		var id: String = it[0]
		var b := _small_button("", func(): _set_carried(id, not Settings.carries(id)), 250)
		v.add_child(b)
		_weapon_cards.append([b, -1, id, "carry"])

	# МОДИФИКАЦИИ: the PBS-1 on each rifle
	var mods := HBoxContainer.new()
	mods.add_theme_constant_override("separation", 20)
	mods.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(mods)
	for i in w.slots.size():
		var d: Dictionary = w.slots[i].def
		var v := _card(mods)
		v.add_child(_icon(d.id, Vector2(300, 100)))
		v.add_child(UiKit.label(d.title, 26, Color(1, 1, 1)))
		var id: String = d.id
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 8)
		line.add_child(_icon("suppressor", Vector2(90, 45)))
		if d.get("integral", false):
			line.add_child(UiKit.label("Глушитель встроен", 20, Color(0.9, 0.85, 0.7)))
			v.add_child(line)
			v.add_child(UiKit.label("Стреляет тихо всегда: вспышки нет,\nсолдаты слышат только вблизи.", 15, Color(0.75, 0.75, 0.75)))
			continue
		line.add_child(UiKit.label("Глушитель ПБС-1", 20, Color(0.9, 0.85, 0.7)))
		v.add_child(line)
		v.add_child(UiKit.label("Нет вспышки у ствола, выстрел тихий:\nсолдаты слышат его только вблизи.", 15, Color(0.75, 0.75, 0.75)))
		var b := _small_button("", func():
			Settings.suppressed[id] = not Settings.suppressed.get(id, false)
			w.apply_mods()
			Settings.save_settings()
			_refresh_weapon_cards(), 300)
		v.add_child(b)
		_weapon_cards.append([b, i, id, "suppressor"])
		if d.has("sights"):
			# the AK: the round tube collimator (as on the video) or the Kobra
			var sb := _small_button("", func():
				var names: Array = d.sights.keys()
				Settings.sight[id] = names[(names.find(w.sight_of(w.slots[i])) + 1) % names.size()]
				w.apply_mods()
				Settings.save_settings()
				_refresh_weapon_cards(), 300)
			v.add_child(sb)
			_weapon_cards.append([sb, i, id, "sight"])

	var immortal_page := _toggle_page("Пули и осколки не наносят вам урона.\nБез бессмертия: пятая пуля убивает, раны кровоточат,\nпри смерти — возрождение в своей траншее.")
	_immortal_button = immortal_page.get_child(1)
	_immortal_button.pressed.connect(func():
		Player.immortal = not Player.immortal
		_refresh_weapon_cards())
	col.add_child(immortal_page)
	for t in [["ОРУЖИЕ", guns], ["СНАРЯЖЕНИЕ", kit], ["МОДИФИКАЦИИ", mods], ["БЕССМЕРТИЕ", immortal_page]]:
		var page: Control = t[1]
		var tb := _small_button(t[0], func(): _show_weapon_tab(page), 200)
		tb.toggle_mode = true
		tabs.add_child(tb)
		_weapon_tabs.append([tb, page])
	var close := _small_button("✕", toggle_weapon_menu, 64)
	tabs.add_child(close)
	_show_weapon_tab(guns)
	root.visible = false


func _to_menu() -> void:
	Settings.save_settings()
	get_tree().paused = false
	Blood.clear()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
