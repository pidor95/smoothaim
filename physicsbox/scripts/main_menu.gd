extends Node3D
## Main menu: dark red-grid stage with a mannequin you can tap to shoot,
## title, location select and settings.

var cam := Camera3D.new()
var dummy: Npc
var _t := 0.0
var _respawn := -1.0
var _ui := Control.new()
var _main_box: Control
var _play_box: Control
var _settings_box: Control
var _loading: Label


func _ready() -> void:
	get_tree().paused = false
	Engine.time_scale = 1.0
	Blood.clear()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build_stage()
	_build_ui()
	_spawn_dummy()


func _build_stage() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0, 0, 0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.45, 0.2, 0.18)
	env.ambient_light_energy = 0.5
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.8
	env.glow_hdr_threshold = 0.8
	env.fog_enabled = true
	env.fog_light_color = Color(0.0, 0.0, 0.0)
	env.fog_density = 0.06
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var floor_body := StaticBody3D.new()
	floor_body.set_meta("surface", "concrete")
	add_child(floor_body)
	var fm := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(80, 80)
	fm.mesh = pm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_texture = load("res://assets/textures/menu_grid.png")
	mat.albedo_color = Color(1.0, 0.85, 0.85)
	mat.uv1_scale = Vector3(20, 20, 1)
	fm.material_override = mat
	floor_body.add_child(fm)
	var cs := CollisionShape3D.new()
	cs.shape = WorldBoundaryShape3D.new()
	floor_body.add_child(cs)

	var key := SpotLight3D.new()
	key.position = Vector3(1.5, 4.5, 2.5)
	key.light_color = Color(1.0, 0.55, 0.4)
	key.light_energy = 6.0
	key.spot_range = 10.0
	key.spot_angle = 35.0
	key.shadow_enabled = true
	add_child(key)
	key.look_at(Vector3(1.6, 0.8, 0))
	var rim := OmniLight3D.new()
	rim.position = Vector3(2.5, 2.0, -2.0)
	rim.light_color = Color(1, 0.15, 0.1)
	rim.light_energy = 3.0
	rim.omni_range = 6.0
	add_child(rim)

	var hint := Label3D.new()
	hint.text = "Можешь выстрелить в меня :)"
	hint.font_size = 48
	hint.pixel_size = 0.004
	hint.modulate = Color(1, 0.55, 0.15)
	hint.outline_size = 0
	hint.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	hint.position = Vector3(1.6, 2.25, 0)
	add_child(hint)

	cam.fov = 55
	add_child(cam)
	cam.current = true
	_update_camera()


func _spawn_dummy() -> void:
	dummy = Npc.new()
	dummy.display_only = true
	dummy.position = Vector3(1.6, 0, 0)
	dummy.rotation.y = PI * 0.92
	add_child(dummy)
	dummy.died.connect(func(_n, _h): _respawn = 3.5)


func _update_camera() -> void:
	var a := sin(_t * 0.25) * 0.25
	cam.position = Vector3(sin(a) * 5.2, 1.55, cos(a) * 5.2)
	cam.look_at(Vector3(-0.55, 1.1, 0))


func _process(delta: float) -> void:
	_t += delta
	_update_camera()
	if _respawn > 0.0:
		_respawn -= delta
		if _respawn <= 0.0:
			dummy.queue_free()
			Blood.clear()
			Gore.clear()
			_spawn_dummy()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_shoot_at(event.position)


func _shoot_at(screen_pos: Vector2) -> void:
	var from := cam.project_ray_origin(screen_pos)
	var dir := cam.project_ray_normal(screen_pos)
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * 50.0, 1 | 4)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	Sfx.play("gunshot", -4.0)
	if hit.is_empty():
		return
	var c: Object = hit.collider
	if c.has_meta("npc"):
		var npc = c.get_meta("npc")
		var part: String = c.get_meta("part")
		npc.take_hit(c, hit.position, hit.normal, dir, 100.0 if part == "head" else 45.0, 12.0)
	else:
		Blood.dust(hit.position, hit.normal, Color(1, 0.3, 0.2))


# ------------------------------------------------------------------ UI

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.theme = UiKit.make_theme()
	layer.add_child(_ui)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 56)
	_ui.add_child(margin)
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	col.add_theme_constant_override("separation", 14)
	margin.add_child(col)

	var title := UiKit.label("PHYSICS BOX", 96, Color(1, 1, 1))
	title.add_theme_constant_override("outline_size", 14)
	title.add_theme_color_override("font_outline_color", Color(0.65, 0.0, 0.05))
	col.add_child(title)
	col.add_child(UiKit.label("песочница с физикой и кровью", 28, Color(0.75, 0.75, 0.75)))
	var spacer := Control.new()
	spacer.custom_minimum_size.y = 18
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(spacer)

	_main_box = VBoxContainer.new()
	_main_box.add_theme_constant_override("separation", 12)
	col.add_child(_main_box)
	_main_box.add_child(UiKit.button("ИГРАТЬ", func(): _show(_play_box)))
	_main_box.add_child(UiKit.button("НАСТРОЙКИ", func(): _show(_settings_box)))
	_main_box.add_child(UiKit.button("ВЫХОД", func(): get_tree().quit()))

	_play_box = VBoxContainer.new()
	_play_box.add_theme_constant_override("separation", 12)
	col.add_child(_play_box)
	_play_box.add_child(UiKit.label("ВЫБОР ЛОКАЦИИ", 34, Color(1, 0.25, 0.2)))
	for loc in [["ОКОПЫ", "trenches", "Фронт: две линии траншей и нейтральная полоса. Витязь против ополчения, гранаты, FPV-дроны."],
			["ДОМ", "house", "Пять комнат, двор и крыша. Двери, окна и мебель — на физике."],
			["МАГАЗИН", "shop", "Супермаркет: ряды полок с товарами, кассы, холодильники, тележки, склад."]]:
		var b := UiKit.button(loc[0], _start_level.bind(loc[1]), 480)
		b.custom_minimum_size.y = 74
		b.add_theme_font_size_override("font_size", 36)
		_play_box.add_child(b)
		_play_box.add_child(UiKit.label(loc[2], 20, Color(0.7, 0.7, 0.7)))
	_play_box.add_child(UiKit.button("НАЗАД", func(): _show(_main_box)))

	_settings_box = VBoxContainer.new()
	_settings_box.add_theme_constant_override("separation", 10)
	col.add_child(_settings_box)
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = 640
	panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_settings_box.add_child(panel)
	panel.add_child(UiKit.settings_box())
	_settings_box.add_child(UiKit.button("НАЗАД", func():
		Settings.save_settings()
		_show(_main_box)))

	var version := UiKit.label("v%s" % ProjectSettings.get_setting("application/config/version"), 18, Color(0.5, 0.5, 0.5))
	_ui.add_child(version)
	version.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 24)

	_loading = UiKit.label("ЗАГРУЗКА...", 48, Color(1, 1, 1))
	_loading.visible = false
	_ui.add_child(_loading)
	_loading.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	_show(_main_box)


func _show(box: Control) -> void:
	for b in [_main_box, _play_box, _settings_box]:
		b.visible = b == box


func _start_level(level: String) -> void:
	Settings.level = level
	_main_box.get_parent().visible = false
	_loading.visible = true
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().change_scene_to_file("res://scenes/game.tscn")
