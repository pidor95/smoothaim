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
var post: ColorRect
var settings := {"bp": 2, "bh": 2, "bt": 3, "bi": 6, "ba": 3, "vol": 0.8, "diff": 1, "shoot": true, "ammo": false, "sens": 6.0, "vehicle": "su57", "gfx": "high", "nick": "", "ip": "", "servers": [],
	"assault": true, "intro": true}


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.has("server"):
		_run_server(args)
		return
	_load_settings()
	if OS.has_feature("mobile") and not FileAccess.file_exists(SETTINGS_PATH):
		settings["gfx"] = "mid"
	if _arg(args, "quality", "") != "":
		settings["gfx"] = _arg(args, "quality", "")
	post = ColorRect.new()
	post.set_anchors_preset(Control.PRESET_FULL_RECT)
	post.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pm := ShaderMaterial.new()
	pm.shader = preload("res://shaders/sharpen.gdshader")
	post.material = pm
	var post_layer := CanvasLayer.new()
	post_layer.layer = 0
	add_child(post_layer)
	post_layer.add_child(post)
	var layer := CanvasLayer.new()
	layer.layer = 1
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
	net.name = "Net"
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
	ui.restart.connect(func(): _start(false))
	game.match_won.connect(func():
		if game.playing:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			hud.active = false
			hud.queue_redraw()
			game.paused = true
			audio.set_engine("", 0, 1)
			ui.show_death(false)
			ui.show_victory(true, game.kills, game.deaths, game.time))
	ui.quality_changed.connect(_quality)
	ui.settings_changed.connect(_save_settings)
	hud.pause_pressed.connect(func(): _pause(true))
	game.player_died.connect(func(a, w):
		if game.playing and game.player.dead:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			ui.show_death(true, a, w, game.player.type))
	net.connected.connect(func(): _start(true))
	net.disconnected.connect(_to_menu)
	get_tree().root.go_back_requested.connect(_back)
	if args.has("shots"):
		_shots(_arg(args, "out", "user://"))
	elif args.has("play"):
		_play_test(args)
	elif args.has("menushot"):
		var out := _arg(args, "out", "user://")
		for page in [["home", ""], ["garage", "su25"], ["garage", "su24"], ["garage", "soldier"], ["settings", ""], ["online", ""]]:
			if page[1] != "":
				settings["vehicle"] = page[1]
			ui.show_page(page[0])
			for i in 12:
				await get_tree().process_frame
			get_viewport().get_texture().get_image().save_png(out.path_join("menu_%s_%s.png" % [page[0], page[1]]))
			var pg: Control = ui.pages[page[0]]
			print("page ", page[0], " size ", pg.size, " menu ", ui.menu.size, " ui ", ui.size, " child ", pg.get_child(0).size)
		get_tree().quit()


## Dedicated server: ./BoevoyFront-Server.x86_64 --headless -- server name="Мой сервер" port=27015 max=10
func _run_server(args: PackedStringArray) -> void:
	Engine.max_fps = 30
	net = preload("res://scripts/net.gd").new()
	net.name = "Net"
	add_child(net)
	if not net.start_server(_arg(args, "name", "Боевой Фронт"), int(_arg(args, "port", "27015")), int(_arg(args, "max", "10"))):
		get_tree().quit(1)


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
	if post:
		post.visible = settings["gfx"] != "low"
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
	ui.show_victory(false)
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
	if on:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	game.paused = on and not net.active
	ui.show_pause(on, net.active)
	hud.active = not on
	if not on:
		hud.refresh()


func _to_menu() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
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
	ui.show_victory(false)
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
		["su57", Vector3(1975, 26, -1720), Vector3(0.1, 2.2, 0.5)], ["mi24", Vector3(1940, 14, -1700), Vector3(0, -0.8, 0)],
		["pantsir", Vector3(1972, 0, -1652), Vector3(0, 2.4, 0)]]
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


func Vehicle_heading(d: Vector3) -> float:
	return atan2(-d.x, -d.z)


## Air-to-ground check against assault point B: "bomb" (level release on the CCIP solution), "kh25" (lock and
## launch from 4 km), "storm" (Su-24 launch from 6 km). Prints the fortifications' state and takes screenshots.
func _attack_test(args: PackedStringArray, kind: String, out: String) -> void:
	settings["shoot"] = false
	var o: Dictionary = game.objectives[1]
	if kind == "zu":
		# hover near point B and let its defences shoot at us
		settings["shoot"] = true
		var hp0: float = game.player.hp
		var q: Vector3 = o["p"] + Vector3(300, 0, 900)
		game.player.place(Vector3(q.x, world.height(q.x, q.z) + 120.0, q.z), 0.0, 0.0)
		game.ctrl["thr"] = 0.0
		for i in 900:
			game.reset_camera_to((o["p"] - game.player.pos).normalized())
			await get_tree().process_frame
			if i % 100 == 0:
				print("t=%d hp %d zu aim %s bullets %d dead %s" % [i / 20, game.player.hp, o["units"][1].aim_dir.snapped(Vector3.ONE * 0.01), game.bullets.size(), game.player.dead])
			if game.player.dead:
				break
		print("RESULT zu: hp ", hp0, " -> ", game.player.hp, " feed ", game.feed_log)
		return
	var tgt = o["units"][0] if kind != "storm" else o["units"][2]
	var p = game.player
	var tp: Vector3 = tgt.pos
	var start: Vector3 = {"bomb": Vector3(tp.x, tp.y + 500.0, tp.z + 2500.0), "kh25": Vector3(tp.x, tp.y + 800.0, tp.z + 4200.0),
		"storm": Vector3(tp.x - 400.0, tp.y + 600.0, tp.z + 6000.0)}[kind]
	p.place(start, 0.0, 180.0)
	game.reset_camera_to(Vector3(0, 0, -1))
	var wname: String = {"bomb": "fab250", "kh25": "kh25", "storm": "storm"}[kind]
	game.select_slot(p.slot_of(wname))
	game.ctrl["thr"] = 0.8
	var fired := 0
	var shot_i := 0
	for i in 1600:
		var to: Vector3 = (tp - game.cam.global_position).normalized()
		if kind == "bomb":
			# fly level straight at the target and release when the CCIP mark reaches it
			game.reset_camera_to(Vector3(0, 0.0, -1).normalized())
			var hit = game.bomb_impact(p, wname)
			if fired < 2 and hit != null and hit.z < tp.z + 6.0:
				game.ctrl["fire_pressed"] = true
				game.ctrl["fire"] = true
				fired += 1
				print("release ", fired, " at dist ", roundi(p.pos.distance_to(tp)), " ccip ", hit.round(), " target ", tp.round())
			else:
				game.ctrl["fire"] = false
		else:
			game.reset_camera_to(to)
			if fired == 0 and p.locked and p.lock_target == tgt:
				game.ctrl["fire_pressed"] = true
				fired = 1
				print("launch at ", roundi(p.pos.distance_to(tp)), " m, locked on ", tgt.nick)
		await get_tree().process_frame
		if i % 20 == 0:
			var ms: Array = game.missiles.map(func(m): return "%s %s spd %d agl %d" % [m["w"], m["p"].round(), roundi(m["vel"].length()), roundi(m["p"].y - world.height(m["p"].x, m["p"].z))])
			print("t=%.0f plane %s spd %d lock %s missiles %s" % [i * 0.05, p.pos.round(), p.speed, p.locked, ms])
		if fired > 0 and i % 30 == 0 and DisplayServer.get_name() != "headless" and shot_i < 8:
			get_viewport().get_texture().get_image().save_png(out.path_join("attack_%s_%d.png" % [kind, shot_i]))
			shot_i += 1
		if tgt.dead and game.missiles.is_empty():
			break
	print("RESULT ", kind, ": ", o["units"].map(func(u): return "%s hp %d dead %s" % [u.type, u.hp, u.dead]), " taken ", o["taken"], " feed ", game.feed_log)


## Starts a bot match with the given vehicle, flies/drives a little and saves screenshots.
func _play_test(args: PackedStringArray) -> void:
	var out := _arg(args, "out", "user://")
	var vt := _arg(args, "vehicle", "su57")
	settings["vehicle"] = vt
	settings["bp"] = int(_arg(args, "bp", "2"))
	settings["bh"] = int(_arg(args, "bh", "2"))
	settings["bt"] = int(_arg(args, "bt", "3"))
	settings["intro"] = not args.has("nointro")
	if args.has("noassault"):
		settings["assault"] = false
	var join := _arg(args, "join", "")
	if join != "":
		net.refresh_servers([join])
		for i in 30:
			await get_tree().process_frame
		print("servers: ", net.servers)
		net.join(join)
		await net.connected
		print("connected as ", net.my_id())
	else:
		_start(false)
	var p = game.player
	if vt == "abrams":
		p.pos = Vector3(2150, 0, 150)
		p.pos.y = world.height(p.pos.x, p.pos.z)
		p.heading = 0.6
		p.turret_yaw = 0.6
		game.cam_yaw = 0.6
	if args.has("rag"):
		# three soldiers killed at once: headshot, chest shot, nearby explosion; filmed from the side
		settings["bi"] = 0
		settings["ba"] = 0
		game.clear()
		_start(false)
		p = game.player
		var c := Vector3(1600, 0, 900)
		p.place(Vector3(c.x, world.height(c.x, c.z), c.z + 30), 0.0, 0.0)
		var targets := []
		for k in 3:
			var en = game._new_vehicle("soldier", "red", {"bot": true, "name": "Цель"})
			game.spawn(en)
			var q := Vector3(c.x - 4 + k * 4, 0, c.z)
			en.place(Vector3(q.x, world.height(q.x, q.z), q.z), 0.0, 0.0)
			en.bot["think"] = 999.0
			en.inp["move"] = Vector2(0, 0.6 if k == 1 else 0.0)
			en.bot["wp"] = en.pos
			targets.append(en)
		for i in 20:
			await get_tree().process_frame
		var shot := Vector3(0, 0, -1)
		targets[0].hit_part = "head"
		targets[0].last_impulse = shot * 4.0
		game.damage(targets[0], 1000.0, p, "headshot")
		targets[1].hit_part = "torso"
		targets[1].hit_point = targets[1].jp[1].lerp(targets[1].jp[2], 0.3)
		targets[1].last_impulse = shot * 4.0
		game.damage(targets[1], 1000.0, p, "ak")
		game.splash(targets[2].pos + Vector3(1.5, 0.3, 0.5), 8.0, 300.0, p, "rkt")
		print("after kill: ", targets.map(func(t): return [t.dead, t.ragdoll, t.hp]))
		for i in 160:
			game.paused = false
			await get_tree().process_frame
			if i % 10 == 0 or (i < 40 and i % 3 == 0):
				print("i=", i, " ", targets.map(func(t): return [t.dead, t.ragdoll, snappedf(t.jp[0].y - world.height(t.jp[0].x, t.jp[0].z), 0.01)]))
				if args.has("dbg"):
					var t0 = targets[1]
					var hs := []
					for j in 15:
						hs.append(snappedf(t0.jp[j].y - world.height(t0.jp[j].x, t0.jp[j].z), 0.01))
					print("   joints ", hs, " pelvis ", t0.jp[2].round())
			if i in [3, 7, 11, 15, 19, 26]:
				game.paused = true
				for rep in 2:
					cam.global_position = c + Vector3(6.5, world.height(c.x, c.z) + 1.5, 4.5)
					cam.look_at(c + Vector3(0, world.height(c.x, c.z) + 0.6, -0.5), Vector3.UP)
					cam.fov = 60.0
					await get_tree().process_frame
				if DisplayServer.get_name() != "headless":
					get_viewport().get_texture().get_image().save_png(out.path_join("rag_%03d.png" % i))
		get_tree().quit()
		return
	if args.has("win"):
		for o in game.objectives:
			for u in o["units"]:
				game.kill(u, game.player, "fab500")
		for i in 100:
			await get_tree().process_frame
		print("WIN taken ", game.objectives.map(func(o): return o["taken"]), " won ", game.won, " victory shown ", ui.victory_panel.visible, " feed ", game.feed_log.size())
		if DisplayServer.get_name() != "headless":
			get_viewport().get_texture().get_image().save_png(out.path_join("victory.png"))
		get_tree().quit()
		return
	if _arg(args, "attack", "") != "":
		await _attack_test(args, _arg(args, "attack", ""), out)
		get_tree().quit()
		return
	if args.has("stall"):
		# fly into a deep stall with thrust vectoring on, then let go and watch the recovery
		game.ctrl["man"] = true
		game.ctrl["thr"] = float(_arg(args, "thr", "0.15"))
		for i in 400:
			game.cam_pitch = 1.4 if i < 160 else 0.0
			if i == 160:
				game.ctrl["man"] = false
				game.ctrl["thr"] = 1.0
			await get_tree().process_frame
			if i % 20 == 0:
				print("stall t=%.1f spd=%d aoa=%d alt=%d pitch=%d stalled=%s dead=%s" % [i * 0.05, p.speed, rad_to_deg(p.aoa), p.pos.y, rad_to_deg(asin(clampf(p.fwd().y, -1, 1))), p.stalled, p.dead])
		get_tree().quit()
		return
	if vt == "soldier":
		game.ctrl["move"] = Vector2(0, 0.9)
		game.cam_yaw = p.heading
		if args.has("front"):
			# start next to the enemy squad so the fight is in view
			var c: Vector2 = game.INF_SPAWN["red"] + Vector2(-40, 140)
			p.place(Vector3(c.x, world.height(c.x, c.y), c.y), 0.3, 0.0)
			game.cam_yaw = 0.3
			game.ctrl["move"] = Vector2(0, 0.3)
	var frames := int(_arg(args, "frames", "240"))
	var every := int(_arg(args, "every", "60"))
	var t0 := Time.get_ticks_msec()
	var skip_at := int(_arg(args, "skipat", "-1"))
	var slot_at := int(_arg(args, "slot", "-1"))
	for i in frames:
		if i == skip_at:
			game.skip_intro()
		if slot_at >= 0 and i > skip_at:
			game.select_slot(slot_at)
			game.ctrl["fire"] = false
			await get_tree().process_frame
			if i % every == every - 1 and DisplayServer.get_name() != "headless":
				get_viewport().get_texture().get_image().save_png(out.path_join("%s_%03d.png" % [vt, i]))
			continue
		game.ctrl["fire"] = (i / 30) % 3 == 0
		if args.has("ads") and vt == "soldier":
			game.ctrl["zoom"] = i >= frames / 2
			game.ctrl["fire"] = false
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
		if args.has("infstat") and i % 200 == 0:
			var md := INF
			var alive := 0
			for a in game.vehicles:
				if a.cat != "inf" or a.dead:
					continue
				alive += 1
				for b in game.vehicles:
					if b.cat == "inf" and not b.dead and b.team != a.team:
						md = minf(md, a.pos.distance_to(b.pos))
			print("inf t=%d alive=%d closest_enemy=%.0f bullets=%d" % [i / 20, alive, md, game.bullets.size()])
		if i % every == every - 1:
			if DisplayServer.get_name() != "headless":
				get_viewport().get_texture().get_image().save_png(out.path_join("%s_%03d.png" % [vt, i]))
			print("play shot ", i, " pos ", p.pos.round(), " alt ", roundi(p.pos.y - world.height(p.pos.x, p.pos.z)), " spd ", roundi(p.speed), " intro ", p.intro != null, " fps ", Engine.get_frames_per_second(), " vehicles ", game.vehicles.size(), " missiles ", game.missiles.size(), " bullets ", game.bullets.size(), " hp ", p.hp, " dead ", p.dead)
	print("play test done in ", Time.get_ticks_msec() - t0, " ms; kills ", game.kills, " deaths ", game.deaths, " feed ", game.feed_log, " hits ", game.hit_stats, " remotes ", net.remotes.keys(), " vehicles ", game.vehicles.size())
	get_tree().quit()
