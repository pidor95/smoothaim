extends Node3D
## Main menu: dark red-grid stage with a soldier you can tap to shoot,
## title, "to battle" (first the kit screen: what to take into the fight),
## settings and the model credits.

var cam := Camera3D.new()
var dummy: Npc
var _t := 0.0
var _respawn := -1.0
var _ui := Control.new()
var _main_box: Control
var _credits_box: Control
var _settings_box: Control
var _log_box: Control
var _log_text: Label
var _loading: Label
var _margin: Control
var _loadout: Control
var _loadout_refresh: Array[Callable] = []
## The kit screen's cards: what can be taken into the fight.
const KIT := [
	["ak74", "АК-74М", "Автомат 5,45 мм, 30 патронов,\nкруглый коллиматор или «Кобра»."],
	["asval", "АС «Вал»", "Бесшумный автомат 9×39 мм,\n20 патронов, глушитель встроен."],
	["svd", "СВД + ПСО-1", "Снайперская винтовка, 10 патронов,\nоптика ×4, пробивает бронеплиты."],
	["grenade", "Гранаты РГД-5", "×4, бросок анимацией,\nпополняются со временем."],
	["fpv", "FPV-дрон", "Камикадзе с зарядом ПГ-7:\nлетишь через его камеру."],
	["medkit", "Аптечка", "Бинты ×2, промедол, аптечка:\nостановить кровь, снять боль."],
]
const PRELOAD := ["res://scenes/game.tscn", "res://assets/maps/trenches.glb", "res://assets/maps/buildings.glb",
		"res://assets/maps/trenches_nav.res", "res://assets/weapons/ak74_fp.glb", "res://assets/weapons/svd_fp.glb", "res://assets/weapons/asval_fp.glb",
		"res://assets/props/medkit.glb",
		"res://assets/weapons/grenade_fp.glb", "res://assets/npc/npc_rifle.glb", "res://assets/npc/npc_svd.glb",
		"res://assets/npc/soldier_gear.glb", "res://assets/npc/mannequin_anims.glb",
		"res://assets/weapons/suppressor.glb", "res://assets/npc/gibs.glb", "res://assets/textures/wound_atlas.png"]


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
	_margin = margin
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	col.add_theme_constant_override("separation", 14)
	margin.add_child(col)

	var title := UiKit.label("NPC WAR", 104, Color(1, 1, 1))
	title.add_theme_constant_override("outline_size", 14)
	title.add_theme_color_override("font_outline_color", Color(0.65, 0.0, 0.05))
	col.add_child(title)
	col.add_child(UiKit.label("окопная война: витязь против ополчения", 28, Color(0.75, 0.75, 0.75)))
	var spacer := Control.new()
	spacer.custom_minimum_size.y = 18
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(spacer)

	_main_box = VBoxContainer.new()
	_main_box.add_theme_constant_override("separation", 12)
	col.add_child(_main_box)
	var play := UiKit.button("В БОЙ", _show_loadout, 420)
	play.custom_minimum_size.y = 80
	play.add_theme_font_size_override("font_size", 40)
	_main_box.add_child(play)
	_main_box.add_child(UiKit.button("НАСТРОЙКИ", func(): _show(_settings_box)))
	_main_box.add_child(UiKit.button("АВТОРЫ МОДЕЛЕЙ", func(): _show(_credits_box)))
	_main_box.add_child(UiKit.button("ВЫХОД", func(): get_tree().quit()))

	_credits_box = VBoxContainer.new()
	_credits_box.add_theme_constant_override("separation", 10)
	col.add_child(_credits_box)
	_credits_box.add_child(UiKit.label("Модели со Sketchfab (CC-BY 4.0):", 28, Color(1, 0.25, 0.2)))
	for line in ["«AK-74M» — SeveN (sketchfab.com/SeveN-Models)",
			"«Grenade RGD-5» — _Alexandr (sketchfab.com/a_l_e_x_a_n_d_e_r)",
			"«FPV kamikaze drone Low-poly» — Kvasovich (sketchfab.com/Kvasovich)",
			"«SVD \"Dragunov\"» — Sergei3D (sketchfab.com/Sergei3D)",
			"«Low-Poly EKP-1S-03 Kobra Red Dot Sight» — Mivoriss57 (sketchfab.com/Mivoriss57)",
			"«PBS-1 Silencer for AK-74 5.45x39» — 3dYaroslav (sketchfab.com/3dYaroslav)",
			"«AS Val» — SLIVA21 (sketchfab.com/SLIVA21)",
			"«Aim Point Pro Red Dot Sight» — armoredwave (sketchfab.com/armoredwave)",
			"«Tactical FIRST AID KIT» — ruskoschey (sketchfab.com/ruskoschey)",
			"Остальное — сделано в Blender скриптами проекта."]:
		_credits_box.add_child(UiKit.label(line, 22, Color(0.8, 0.8, 0.8)))
	_credits_box.add_child(UiKit.button("НАЗАД", func(): _show(_main_box)))

	_settings_box = VBoxContainer.new()
	_settings_box.add_theme_constant_override("separation", 10)
	col.add_child(_settings_box)
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = 640
	panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_settings_box.add_child(panel)
	panel.add_child(UiKit.settings_box())
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	_settings_box.add_child(row)
	row.add_child(UiKit.button("НАЗАД", func():
		Settings.save_settings()
		_show(_main_box), 300))
	row.add_child(UiKit.button("ЖУРНАЛ ОШИБОК", _show_log, 320))

	# the log of the last run (the one that froze or crashed): to copy and send
	_log_box = VBoxContainer.new()
	_log_box.add_theme_constant_override("separation", 10)
	col.add_child(_log_box)
	_log_box.add_child(UiKit.label("Журнал прошлого запуска (последние строки):", 26, Color(1, 0.25, 0.2)))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(1080, 300)
	_log_box.add_child(scroll)
	_log_text = UiKit.label("", 15, Color(0.85, 0.85, 0.85))
	_log_text.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	_log_text.custom_minimum_size.x = 1060
	scroll.add_child(_log_text)
	var log_row := HBoxContainer.new()
	log_row.add_theme_constant_override("separation", 14)
	_log_box.add_child(log_row)
	log_row.add_child(UiKit.button("КОПИРОВАТЬ", func(): DisplayServer.clipboard_set(_log_text.text), 300))
	log_row.add_child(UiKit.button("НАЗАД", func(): _show(_settings_box), 300))

	var version := UiKit.label("v%s" % ProjectSettings.get_setting("application/config/version"), 18, Color(0.5, 0.5, 0.5))
	_ui.add_child(version)
	version.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 24)

	_build_loadout()

	_loading = UiKit.label("ЗАГРУЗКА...", 48, Color(1, 1, 1))
	_loading.visible = false
	_ui.add_child(_loading)
	_loading.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	_show(_main_box)


func _show(box: Control) -> void:
	for b in [_main_box, _credits_box, _settings_box, _log_box]:
		b.visible = b == box
	_margin.visible = true
	_loadout.visible = false


# ------------------------------------------------------------------ kit screen

## Before the battle: a card for every gun and piece of kit - take it or
## leave it, the AK's sight, the SVD's suppressor. The choices stick
## (Settings) and the hotbar shows only what was taken.
func _build_loadout() -> void:
	_loadout = Control.new()
	_loadout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ui.add_child(_loadout)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.02, 0.025, 0.86)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_loadout.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_loadout.add_child(center)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	center.add_child(col)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 18)
	col.add_child(top)
	var back := UiKit.button("◀ НАЗАД", func():
		Settings.save_settings()
		_show(_main_box), 200)
	back.custom_minimum_size.y = 56
	top.add_child(back)
	var title := UiKit.label("ОРУЖИЕ И СНАРЯЖЕНИЕ НА БОЙ", 34, Color(1, 1, 1))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top.add_child(title)
	var go := UiKit.button("В БОЙ ▶", func():
		Settings.save_settings()
		_start_game(), 240)
	go.custom_minimum_size.y = 56
	go.add_theme_color_override("font_color", Color(1, 0.85, 0.5))
	top.add_child(go)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	col.add_child(grid)
	for it in KIT:
		grid.add_child(_kit_card(it[0], it[1], it[2]))
	_loadout.visible = false


func _kit_card(id: String, title: String, desc: String) -> Control:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(380, 0)
	var on_box := StyleBoxFlat.new()
	on_box.bg_color = Color(0.1, 0.09, 0.06, 0.98)
	on_box.border_color = Color(1, 0.78, 0.3)
	on_box.set_border_width_all(3)
	on_box.set_corner_radius_all(6)
	on_box.set_content_margin_all(12)
	var off_box := on_box.duplicate() as StyleBoxFlat
	off_box.bg_color = Color(0.06, 0.06, 0.07, 0.98)
	off_box.border_color = Color(0.25, 0.25, 0.27)
	off_box.set_border_width_all(2)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	card.add_child(v)
	var icon := TextureRect.new()
	icon.texture = load("res://assets/ui/icon_%s.png" % id)
	icon.custom_minimum_size = Vector2(340, 96)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	v.add_child(icon)
	v.add_child(UiKit.label(title, 25, Color(1, 1, 1)))
	v.add_child(UiKit.label(desc, 15, Color(0.72, 0.72, 0.72)))
	var take := _kit_button(func():
		Settings.loadout[id] = not Settings.carries(id)
		_refresh_loadout())
	v.add_child(take)
	var extra: Button = null
	if id == "ak74":
		extra = _kit_button(func():
			Settings.sight["ak74"] = "kobra" if Settings.sight.get("ak74", "collimator") == "collimator" else "collimator"
			_refresh_loadout())
	elif id == "svd":
		extra = _kit_button(func():
			Settings.suppressed["svd"] = not Settings.suppressed.get("svd", false)
			_refresh_loadout())
	if extra:
		v.add_child(extra)
	_loadout_refresh.append(func():
		var on := Settings.carries(id)
		card.add_theme_stylebox_override("panel", on_box if on else off_box)
		icon.modulate = Color(1, 1, 1, 1.0 if on else 0.35)
		take.text = "✓ БЕРУ" if on else "НЕ БЕРУ"
		if id == "ak74":
			extra.text = "ПРИЦЕЛ: " + ("КОЛЛИМАТОР" if Settings.sight.get("ak74", "collimator") == "collimator" else "«КОБРА»")
		elif id == "svd":
			extra.text = "ГЛУШИТЕЛЬ ПБС-1: " + ("ДА" if Settings.suppressed.get("svd", false) else "НЕТ"))
	return card


func _kit_button(callback: Callable) -> Button:
	var b := UiKit.button("", callback, 340)
	b.custom_minimum_size.y = 44
	b.add_theme_font_size_override("font_size", 21)
	return b


func _refresh_loadout() -> void:
	for f in _loadout_refresh:
		f.call()


func _show_loadout() -> void:
	_refresh_loadout()
	_margin.visible = false
	_loadout.visible = true


## The newest log of an earlier run (Godot keeps a few in user://logs; the
## current run writes godot.log): its last lines, memory reports included.
func _show_log() -> void:
	var files := Array(DirAccess.get_files_at("user://logs")).filter(func(f): return f != "godot.log" and f.ends_with(".log"))
	files.sort()
	var text := "Журнала прошлого запуска нет."
	if not files.is_empty():
		var lines := FileAccess.get_file_as_string("user://logs/" + files[-1]).split("\n")
		text = "%s\n%s" % [files[-1], "\n".join(lines.slice(maxi(0, lines.size() - 60)))]
	_log_text.text = text
	_show(_log_box)


## The heavy files (map, buildings, weapons, soldiers) are read on
## background threads while the menu keeps drawing; they stay cached in
## Settings.preloaded for the battle scene.
func _start_game() -> void:
	_main_box.get_parent().visible = false
	_loadout.visible = false
	_loading.visible = true
	for path in PRELOAD:
		ResourceLoader.load_threaded_request(path, "", true)
	var pending: Array = PRELOAD.duplicate()
	while not pending.is_empty():
		await get_tree().process_frame
		var done := 0.0
		for path in pending.duplicate():
			var prog := []
			var st := ResourceLoader.load_threaded_get_status(path, prog)
			if st == ResourceLoader.THREAD_LOAD_LOADED or st == ResourceLoader.THREAD_LOAD_FAILED \
					or st == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
				if st == ResourceLoader.THREAD_LOAD_LOADED:
					Settings.preloaded.append(ResourceLoader.load_threaded_get(path))
				pending.erase(path)
			else:
				done += prog[0] if not prog.is_empty() else 0.0
		var total := PRELOAD.size()
		_loading.text = "ЗАГРУЗКА… %d%%" % int((total - pending.size() + done) * 100.0 / total)
	get_tree().change_scene_to_packed(load("res://scenes/game.tscn"))
