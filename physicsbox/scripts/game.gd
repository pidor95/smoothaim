extends Node3D
## Level controller: environment, house, player, HUD, NPC spawning,
## slow motion and the pause menu.

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


func _ready() -> void:
	add_to_group("settings_listeners")
	Blood.clear()
	Engine.time_scale = 1.0
	AudioServer.playback_speed_scale = 1.0
	_build_environment()

	house = House.new()
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

func spawn_npc(pos: Vector3) -> Npc:
	var npc := Npc.new()
	npc.position = pos
	npc.rotation.y = randf() * TAU
	add_child(npc)
	npc.died.connect(_on_npc_died)
	return npc


## Spawns a mannequin a few metres in front of the player (snapped to the navmesh).
func spawn_in_front() -> void:
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
	var npc := spawn_npc(p + Vector3.UP * 0.05)
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
	Blood.clear()


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
			game.toggle_pause()
			get_viewport().set_input_as_handled()

	func _notification(what: int) -> void:
		if what == NOTIFICATION_WM_GO_BACK_REQUEST:
			game.toggle_pause()
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
	left.add_child(UiKit.button("Главное меню", _to_menu))

	var right := VBoxContainer.new()
	right.custom_minimum_size.x = 560
	right.add_theme_constant_override("separation", 10)
	cols.add_child(right)
	right.add_child(UiKit.label("НАСТРОЙКИ", 34))
	right.add_child(UiKit.settings_box())
	root.visible = false


func _to_menu() -> void:
	Settings.save_settings()
	get_tree().paused = false
	Engine.time_scale = 1.0
	AudioServer.playback_speed_scale = 1.0
	Blood.clear()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
