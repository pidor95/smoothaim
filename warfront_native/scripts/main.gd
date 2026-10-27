extends Node3D
## Boots the game: loads the map, then wires the menu, the match, the HUD and networking together.
## Test modes (command line, after "--"): "shots out=DIR" renders fixed viewpoints, "play out=DIR vehicle=su57"
## starts a bot match and saves screenshots while it runs.

const SETTINGS_PATH := "user://settings.json"

var world: Node3D
var cam: Camera3D
var fx: Node3D
var audio: Node
var net: Node
var game: Node3D
var hud: Control
var ui: Control
var loading: Label
var settings := {"bp": 2, "bh": 2, "bt": 3, "diff": 0, "shoot": true, "ammo": false, "sens": 6.0, "vehicle": "su57", "gfx": "high", "nick": "", "ip": ""}


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	_load_settings()
	if OS.has_feature("mobile") and not FileAccess.file_exists(SETTINGS_PATH):
		settings["gfx"] = "mid"
	if _arg(args, "quality", "") != "":
		settings["gfx"] = _arg(args, "quality", "")
	var layer := CanvasLayer.new()
	add_child(layer)
	loading = Label.new()
	loading.text = "Загрузка карты…"
	loading.add_theme_font_size_override("font_size", 34)
	loading.set_anchors_preset(Control.PRESET_CENTER)
	layer.add_child(loading)
	cam = Camera3D.new()
	cam.far = 16000.0
	cam.fov = 65.0
	add_child(cam)
	await get_tree().process_frame
	await get_tree().process_frame
	_build_world()
	loading.visible = false
	fx = preload("res://scripts/fx.gd").new()
	add_child(fx)
	audio = preload("res://scripts/audio.gd").new()
	add_child(audio)
	net = preload("res://scripts/net.gd").new()
	add_child(net)
	game = preload("res://scripts/game.gd").new()
	add_child(game)
	game.setup(world, fx, audio, cam, net, settings)
	net.game = game
	hud = preload("res://scripts/hud.gd").new()
	hud.game = game
	layer.add_child(hud)
	ui = preload("res://scripts/ui.gd").new()
	layer.add_child(ui)
	ui.build(settings, net)
	ui.start_bots.connect(func(): _start(false))
	ui.start_online.connect(_host)
	ui.respawn.connect(_respawn)
	ui.to_menu.connect(_to_menu)
	ui.resume.connect(func(): _pause(false))
	ui.quality_changed.connect(_quality)
	ui.settings_changed.connect(_save_settings)
	hud.pause_pressed.connect(func(): _pause(true))
	game.player_died.connect(func(a, w): if game.playing and game.player.dead: ui.show_death(true, a, w, game.player.type))
	net.connected.connect(func(): _start(true))
	net.disconnected.connect(_to_menu)
	get_tree().root.go_back_requested.connect(_back)
	if args.has("shots"):
		_shots(_arg(args, "out", "user://"))
	elif args.has("play"):
		_play_test(args)


func _arg(args: PackedStringArray, key: String, def: String) -> String:
	for a in args:
		if a.begins_with(key + "="):
			return a.substr(key.length() + 1)
	return def


func _build_world() -> void:
	world = preload("res://scripts/world.gd").new()
	add_child(world)
	var t0 := Time.get_ticks_msec()
	world.build(settings["gfx"])
	print("world built in ", Time.get_ticks_msec() - t0, " ms")


func _quality(q: String) -> void:
	settings["gfx"] = q
	_save_settings()
	loading.visible = true
	await get_tree().process_frame
	await get_tree().process_frame
	world.queue_free()
	_build_world()
	game.world = world
	loading.visible = false


func _load_settings() -> void:
	if not FileAccess.file_exists(SETTINGS_PATH):
		return
	var d = JSON.parse_string(FileAccess.get_file_as_string(SETTINGS_PATH))
	if not (d is Dictionary):
		return
	for k in d:
		if not settings.has(k):
			continue
		var cur = settings[k]
		if cur is int and (d[k] is float or d[k] is int):
			settings[k] = int(d[k])
		elif cur is float and (d[k] is float or d[k] is int):
			settings[k] = float(d[k])
		elif typeof(d[k]) == typeof(cur):
			settings[k] = d[k]


func _save_settings() -> void:
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(settings))


# ---------------------------------------------------------------- flow
func _start(online: bool) -> void:
	ui.show_menu(false)
	ui.show_death(false)
	ui.show_pause(false, online)
	game.start(settings["vehicle"], online)
	hud.active = true
	hud.refresh()


func _host() -> void:
	var nick: String = settings.get("nick", "")
	if net.host(nick if nick != "" else "Игрок"):
		_start(true)


func _respawn(t: String) -> void:
	ui.show_death(false)
	game.respawn_player(t if t != "" else game.player.type)
	hud.refresh()


func _pause(on: bool) -> void:
	game.paused = on and not net.active
	ui.show_pause(on, net.active)
	hud.active = not on
	if not on:
		hud.refresh()


func _to_menu() -> void:
	net.close()
	game.playing = false
	game.paused = false
	game.clear()
	audio.set_engine("", 0, 1)
	audio.set_lock(false)
	hud.active = false
	hud.queue_redraw()
	ui.show_pause(false, false)
	ui.show_death(false)
	ui.show_menu(true)


func _back() -> void:
	if game.playing:
		_pause(not ui.pause_panel.visible)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and game and game.playing and not net.active:
		_pause(true)


# ---------------------------------------------------------------- test modes
## Renders a few viewpoints to PNG files and quits.
func _shots(out: String) -> void:
	ui.visible = false
	game.set_process(false)
	var views := [
		["tank_field", Vector3(-1500, 0, 1200), Vector3(-1100, 0, 900), 2.6],
		["village", Vector3(1150, 0, -1150), Vector3(1700, 0, -1350), 6.0],
		["air_low", Vector3(-2500, 0, 2500), Vector3(0, 0, 0), 180.0],
		["air_high", Vector3(-3500, 0, 4200), Vector3(500, 0, -500), 900.0],
		["forest_edge", Vector3(-3000, 0, 3500), Vector3(-3400, 0, 3900), 3.0],
		["village_close", Vector3(2050, 0, -80), Vector3(2300, 0, -300), 5.0],
		["tank", Vector3(1960, 0, -1640), Vector3(1985, 0, -1660), 3.0],
	]
	var models := [["abrams", Vector3(1985, 0, -1660), Vector3(0, 0.6, 0)], ["apache", Vector3(2010, 18, -1700), Vector3.ZERO],
		["su57", Vector3(1975, 26, -1720), Vector3(0.1, 2.2, 0.5)], ["mi24", Vector3(1940, 14, -1700), Vector3(0, -0.8, 0)]]
	for m in models:
		var n: Node3D = load("res://assets/models/%s.glb" % m[0]).instantiate()
		add_child(n)
		var p: Vector3 = m[1]
		n.global_position = Vector3(p.x, world.height(p.x, p.z) + p.y, p.z)
		n.rotation = m[2]
	for v in views:
		var p: Vector3 = v[1]
		var t: Vector3 = v[2]
		p.y = world.height(p.x, p.z) + float(v[3])
		t.y = world.height(t.x, t.z) + float(v[3]) * 0.6
		cam.global_position = p
		cam.look_at(t, Vector3.UP)
		for i in 6:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png(out.path_join(String(v[0]) + ".png"))
		print("shot ", v[0])
	get_tree().quit()


## Starts a bot match with the given vehicle, flies/drives a little and saves screenshots.
func _play_test(args: PackedStringArray) -> void:
	var out := _arg(args, "out", "user://")
	var vt := _arg(args, "vehicle", "su57")
	settings["vehicle"] = vt
	settings["bp"] = int(_arg(args, "bp", "2"))
	settings["bh"] = int(_arg(args, "bh", "2"))
	settings["bt"] = int(_arg(args, "bt", "3"))
	_start(false)
	var p = game.player
	if vt == "abrams":
		p.pos = Vector3(2150, 0, 150)
		p.pos.y = world.height(p.pos.x, p.pos.z)
		p.heading = 0.6
		p.turret_yaw = 0.6
		game.cam_yaw = 0.6
	var frames := int(_arg(args, "frames", "240"))
	var every := int(_arg(args, "every", "60"))
	var t0 := Time.get_ticks_msec()
	for i in frames:
		game.ctrl["fire"] = (i / 30) % 3 == 0
		if i % 60 == 40:
			game.ctrl["fire_pressed"] = true
			if p.cat != "plane":
				game.select_slot(1 if i % 120 == 40 else 0)
		if i == 20 and p.cat == "plane":
			game.select_slot(1)
		if i % 50 == 25:
			game.ctrl["flare"] = true
		elif i % 50 == 30:
			game.ctrl["flare"] = false
		if i == 150 and p.T.get("maneuver", false):
			game.maneuver("cobra")
		await get_tree().process_frame
		if i % every == every - 1:
			get_viewport().get_texture().get_image().save_png(out.path_join("%s_%03d.png" % [vt, i]))
			print("play shot ", i, " fps ", Engine.get_frames_per_second(), " vehicles ", game.vehicles.size(), " missiles ", game.missiles.size(), " bullets ", game.bullets.size(), " hp ", p.hp, " dead ", p.dead)
	print("play test done in ", Time.get_ticks_msec() - t0, " ms; kills ", game.kills, " deaths ", game.deaths, " feed ", game.feed_log)
	get_tree().quit()
