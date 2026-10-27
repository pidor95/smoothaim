extends Node3D
## Game flow: loading, menu, flight, pause, crash and respawn, race gates.

const WorldScript := preload("res://scripts/world.gd")
const DroneScript := preload("res://scripts/drone.gd")
const HudScript := preload("res://scripts/hud.gd")
const TouchScript := preload("res://scripts/touch_controls.gd")
const MenuScript := preload("res://scripts/menu.gd")
const AudioScript := preload("res://scripts/drone_audio.gd")
const NetScript := preload("res://scripts/net.gd")

enum State { LOADING, MENU, PLAYING, PAUSED, CRASHED }

const BATTERY_FULL := 16.8
const MENU_ORBIT_CENTER := Vector3(250.0, 0.0, -250.0)

var state: State = State.LOADING
var world: WorldScript
var drone: DroneScript
var hud: HudScript
var touch: TouchScript
var menu: MenuScript
var audio: AudioScript
var net: NetScript
var env: Environment
var sun: DirectionalLight3D
var menu_cam: Camera3D
var static_rect: ColorRect
var loading: Label

var next_gate := 0
var lap_time := 0.0
var lap_running := false
var flight_time := 0.0
var battery := BATTERY_FULL
var crash_timer := 0.0

var _menu_angle := 0.6
var _prev_pos := Vector3.ZERO
var _time := 0.0
var _applied_quality := -1
var _smoke := false
## True on phones and tablets; on a PC the on-screen controls are hidden and
## the mouse turns the camera.
var _touch_ui := true
var _kb_throttle := 0.5
var _mouse_look := Vector2.ZERO
var _net_test := ""
var _net_test_t := 0.0
var _net_seen_t := -1.0
var _smoke_t := 0.0
var _smoke_step := 0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	_smoke = args.has("--smoke")
	_touch_ui = DisplayServer.is_touchscreen_available() or args.has("--touch")
	if args.has("--net-host-test"):
		_net_test = "host"
	elif args.has("--net-join-test"):
		_net_test = "join"
	get_tree().quit_on_go_back = false
	_setup_environment()
	var ui := CanvasLayer.new()
	ui.name = "UI"
	add_child(ui)
	loading = Label.new()
	loading.text = "Загрузка долины…"
	loading.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	loading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	loading.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	loading.add_theme_font_override("font", load("res://fonts/RussoOne-Regular.ttf"))
	loading.add_theme_font_size_override("font_size", 40)
	var loading_bg := ColorRect.new()
	loading_bg.color = Color(0.06, 0.07, 0.09)
	loading_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.add_child(loading_bg)
	loading_bg.add_child(loading)
	await get_tree().process_frame
	await get_tree().process_frame

	world = WorldScript.new()
	world.name = "World"
	add_child(world)
	world.build()

	drone = DroneScript.new()
	drone.name = "Drone"
	drone.world = world
	add_child(drone)
	drone.crashed.connect(_on_crashed)

	audio = AudioScript.new()
	add_child(audio)

	menu_cam = Camera3D.new()
	menu_cam.fov = 62.0
	menu_cam.far = 5000.0
	add_child(menu_cam)

	net = NetScript.new()
	net.name = "Net"
	add_child(net)

	_setup_ui(ui)
	loading_bg.queue_free()

	Settings.changed.connect(_apply_settings)
	_apply_settings()
	_place_at_start()
	_enter_menu()
	if _smoke:
		print("SMOKE: world ready, gates=%d" % world.gates.size())
		_start_flight()
	if _net_test != "":
		_start_net_test()


func _setup_environment() -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = load("res://shaders/sky.gdshader")
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_64
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.75
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 6.0
	env.fog_enabled = true
	env.fog_light_color = Color(0.86, 0.74, 0.64)
	env.fog_sun_scatter = 0.3
	env.fog_density = 0.0011
	env.fog_aerial_perspective = 0.5
	env.fog_sky_affect = 0.2
	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_strength = 1.0
	env.glow_bloom = 0.06
	env.glow_hdr_threshold = 1.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	env.set_glow_level(1, 0.6)
	env.set_glow_level(2, 1.0)
	env.set_glow_level(4, 1.0)
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.12
	env.adjustment_contrast = 1.05
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-22.0, 200.0, 0.0)
	sun.light_color = Color(1.0, 0.86, 0.7)
	sun.light_energy = 1.5
	sun.shadow_enabled = true
	sun.shadow_blur = 1.2
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 140.0
	add_child(sun)


func _setup_ui(ui: CanvasLayer) -> void:
	hud = HudScript.new()
	ui.add_child(hud)
	touch = TouchScript.new()
	ui.add_child(touch)
	touch.pause_pressed.connect(_pause)
	touch.view_pressed.connect(func() -> void: Settings.put("third_person", not Settings.third_person))

	static_rect = ColorRect.new()
	static_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	static_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sm := ShaderMaterial.new()
	sm.shader = load("res://shaders/static.gdshader")
	static_rect.material = sm
	static_rect.visible = false
	ui.add_child(static_rect)

	net.lap_announced.connect(func(text: String) -> void: hud.show_message(text, "", Color(0.6, 0.85, 1.0), 3.0))

	menu = MenuScript.new()
	menu.net = net
	ui.add_child(menu)
	menu.play_pressed.connect(_start_flight)
	menu.resume_pressed.connect(_resume)
	menu.restart_pressed.connect(_start_flight)
	menu.menu_pressed.connect(_enter_menu)


func _apply_settings() -> void:
	sun.shadow_enabled = Settings.shadows
	env.glow_enabled = Settings.bloom
	var q: int = Settings.quality
	if q != _applied_quality:
		_applied_quality = q
		var vp := get_viewport()
		vp.scaling_3d_scale = [0.55, 0.75, 1.0][q]
		vp.msaa_3d = Viewport.MSAA_2X if q == 2 else Viewport.MSAA_DISABLED
		world.set_grass_quality([2, 3, 3][q], [260, 480, 820][q])
		world.set_tree_distance([850.0, 1300.0, 1900.0][q])
		world.update_grass(drone.global_position, 100)
		RenderingServer.directional_shadow_atlas_set_size([1024, 2048, 4096][q], true)
		sun.directional_shadow_max_distance = [90.0, 140.0, 200.0][q]
		env.fog_density = [0.0009, 0.0006, 0.00045][q]
	drone.camera_tilt_deg = Settings.camera_tilt
	if drone.drone_type != Settings.drone_type:
		drone.set_type(Settings.drone_type)
	if drone.mode != Settings.control_mode:
		drone.mode = Settings.control_mode
		touch.set_mode(Settings.control_mode)
		_sync_throttle()
	audio.enabled = Settings.sound
	audio.set_running(Settings.sound and state == State.PLAYING)
	_update_camera()


func _update_camera() -> void:
	if state == State.MENU or state == State.LOADING:
		menu_cam.current = true
	elif Settings.third_person:
		drone.chase_cam.current = true
	else:
		drone.fpv_cam.current = true
	hud.fpv = not Settings.third_person
	hud.camera_tilt = Settings.camera_tilt
	hud.camera_fov = drone.fpv_cam.fov


# --- Flow --------------------------------------------------------------------

func _enter_menu() -> void:
	state = State.MENU
	drone.active = false
	_place_at_start()
	menu.show_main()
	hud.visible = false
	touch.visible = false
	touch.reset()
	static_rect.visible = false
	audio.set_running(false)
	_capture_mouse(false)
	_update_camera()


func _start_flight() -> void:
	state = State.PLAYING
	menu.hide_all()
	hud.visible = true
	touch.visible = _touch_ui
	touch.reset()
	static_rect.visible = false
	next_gate = 0
	world.highlight_gates(0)
	lap_time = 0.0
	lap_running = false
	flight_time = 0.0
	battery = BATTERY_FULL
	_place_at_start()
	drone.mode = Settings.control_mode
	touch.set_mode(Settings.control_mode)
	_sync_throttle()
	drone.active = true
	audio.set_running(Settings.sound)
	_capture_mouse(true)
	_update_camera()


func _pause() -> void:
	if state != State.PLAYING:
		return
	state = State.PAUSED
	drone.active = false
	touch.visible = false
	touch.reset()
	audio.set_running(false)
	_capture_mouse(false)
	menu.show_pause()


func _resume() -> void:
	if state != State.PAUSED:
		return
	state = State.PLAYING
	menu.hide_all()
	touch.visible = _touch_ui
	_sync_throttle()
	drone.active = true
	_prev_pos = drone.global_position
	audio.set_running(Settings.sound)
	_capture_mouse(true)
	_update_camera()


func _on_crashed(reason: String) -> void:
	state = State.CRASHED
	crash_timer = 1.6
	static_rect.visible = true
	touch.reset()
	audio.set_running(false)
	hud.show_message("КРУШЕНИЕ", reason, Color(1.0, 0.35, 0.3), 1.6)
	Input.vibrate_handheld(250)


func _respawn() -> void:
	static_rect.visible = false
	if next_gate > 0:
		var i := next_gate - 1
		var pos := world.gates[i].global_position + world.gate_dirs[i] * 5.0
		pos.y = maxf(pos.y, world.surface_height(pos.x, pos.z) + 1.0)
		var target := world.gates[next_gate].global_position if next_gate < world.gates.size() else pos + world.gate_dirs[i]
		drone.reset_to(pos, atan2(-(target.x - pos.x), -(target.z - pos.z)))
	else:
		_place_at_start()
	_prev_pos = drone.global_position
	_sync_throttle()
	state = State.PLAYING
	drone.active = true
	audio.set_running(Settings.sound)


## Puts the acro throttle at hover so the drone does not drop after a reset.
func _sync_throttle() -> void:
	var hover := drone.acro_hover_throttle()
	drone.in_throttle_abs = hover
	_kb_throttle = hover
	touch.set_throttle(hover)


func _capture_mouse(on: bool) -> void:
	if _touch_ui or _smoke:
		return
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if on else Input.MOUSE_MODE_VISIBLE


func _place_at_start() -> void:
	var start := Vector3(WorldScript.SPAWN.x, world.spawn_y + 0.3, WorldScript.SPAWN.y)
	var g0 := world.gates[0].global_position
	drone.reset_to(start, atan2(-(g0.x - start.x), -(g0.z - start.z)))
	_prev_pos = start


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if state == State.PLAYING:
			_pause()
		elif state == State.PAUSED:
			_resume()
		elif state == State.MENU:
			get_tree().quit()
	elif (what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED) and not _smoke:
		_pause()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if state == State.PLAYING:
			_pause()
		elif state == State.PAUSED:
			_resume()
	elif event is InputEventKey and event.is_pressed() and not event.is_echo():
		var key := (event as InputEventKey).keycode
		if key == KEY_C:
			Settings.put("third_person", not Settings.third_person)
		elif key == KEY_F11:
			var fs := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if fs else DisplayServer.WINDOW_MODE_FULLSCREEN)
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_mouse_look += (event as InputEventMouseMotion).relative
	elif event is InputEventMouseButton and event.is_pressed() and state == State.PLAYING and not _touch_ui:
		_capture_mouse(true)


# --- Per frame ---------------------------------------------------------------

func _process(delta: float) -> void:
	if state == State.LOADING:
		return
	_time += delta
	if world.beacon_material:
		world.beacon_material.emission_energy_multiplier = 5.0 if fmod(_time, 1.5) < 0.2 else 0.4
	match state:
		State.MENU:
			_orbit_menu_camera(delta)
		State.PLAYING:
			_gather_input()
			flight_time += delta
			battery = maxf(13.6, battery - (0.0015 + drone.throttle_level * 0.006) * delta)
			if lap_running:
				lap_time += delta
			_check_gate()
			audio.update(drone.throttle_level, drone.velocity.length(), delta)
		State.CRASHED:
			crash_timer -= delta
			(static_rect.material as ShaderMaterial).set_shader_parameter("amount", clampf(crash_timer / 0.5, 0.0, 1.0))
			if crash_timer <= 0.0:
				_respawn()
	world.update_grass(drone.global_position)
	net.local_pos = drone.global_position
	net.local_rot = drone.quaternion
	net.local_type = drone.drone_type
	net.local_gate = next_gate
	net.local_flying = state == State.PLAYING or state == State.CRASHED
	if _net_test != "":
		_net_test_update(delta)
	if hud.visible:
		_update_hud()
	if _smoke:
		_smoke_update(delta)


func _orbit_menu_camera(delta: float) -> void:
	_menu_angle += delta * 0.045
	var c := MENU_ORBIT_CENTER
	menu_cam.global_position = c + Vector3(cos(_menu_angle) * 650.0, 230.0 + sin(_menu_angle * 0.7) * 40.0, sin(_menu_angle) * 650.0)
	menu_cam.look_at(c + Vector3(0.0, 30.0, 0.0), Vector3.UP)


static func _axis(positive: Key, negative: Key) -> float:
	return float(Input.is_key_pressed(positive)) - float(Input.is_key_pressed(negative))


static func _deadzone(v: Vector2) -> Vector2:
	if v.length() < 0.12:
		return Vector2.ZERO
	return v


func _gather_input() -> void:
	var delta := get_process_delta_time()
	var jl := _deadzone(Vector2(Input.get_joy_axis(0, JOY_AXIS_LEFT_X), -Input.get_joy_axis(0, JOY_AXIS_LEFT_Y)))
	var jr := _deadzone(Vector2(Input.get_joy_axis(0, JOY_AXIS_RIGHT_X), -Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y)))
	var pad := not Input.get_connected_joypads().is_empty()
	# Swiping the screen or moving the mouse turns the drone and tilts the camera.
	var look := (touch.consume_look() + _mouse_look * 0.6) * Settings.sensitivity
	_mouse_look = Vector2.ZERO
	drone.add_yaw(-look.x * 0.006)
	drone.look_pitch = clampf(drone.look_pitch - look.y * 0.004, -0.8, 0.8)
	match drone.mode:
		Settings.Controls.CASUAL:
			drone.in_pitch = clampf(touch.stick_l.y + _axis(KEY_UP, KEY_DOWN) + jl.y, -1.0, 1.0)
			drone.in_yaw = clampf(touch.stick_l.x + _axis(KEY_D, KEY_A) + jl.x, -1.0, 1.0)
			drone.in_throttle = clampf(touch.stick_r.y + _axis(KEY_W, KEY_S) + jr.y, -1.0, 1.0)
			drone.in_roll = clampf(_axis(KEY_RIGHT, KEY_LEFT) + jr.x, -1.0, 1.0)
		Settings.Controls.ACRO:
			# Mode 2 like a real radio: left stick throttle + yaw, right stick pitch + roll.
			_kb_throttle = clampf(_kb_throttle + _axis(KEY_W, KEY_S) * 0.7 * delta, 0.0, 1.0)
			if pad:
				drone.in_throttle_abs = (jl.y + 1.0) * 0.5
			elif _touch_ui:
				drone.in_throttle_abs = (touch.stick_l.y + 1.0) * 0.5
			else:
				drone.in_throttle_abs = _kb_throttle
			drone.in_yaw = clampf(touch.stick_l.x + _axis(KEY_D, KEY_A) + jl.x, -1.0, 1.0)
			drone.in_pitch = clampf(touch.stick_r.y + _axis(KEY_UP, KEY_DOWN) + jr.y, -1.0, 1.0)
			drone.in_roll = clampf(touch.stick_r.x + _axis(KEY_RIGHT, KEY_LEFT) + jr.x, -1.0, 1.0)
		_:
			drone.in_forward = clampf(touch.is_down("fwd") - touch.is_down("back") + _axis(KEY_UP, KEY_DOWN) + jl.y, -1.0, 1.0)
			drone.in_turn = clampf(_axis(KEY_RIGHT, KEY_LEFT) + _axis(KEY_D, KEY_A) + jl.x, -1.0, 1.0)
			drone.in_lift = clampf(touch.is_down("up") - touch.is_down("down") + _axis(KEY_W, KEY_S) + jr.y, -1.0, 1.0)


func _check_gate() -> void:
	var p := drone.global_position
	if next_gate < world.gates.size():
		var g := world.gates[next_gate].global_position
		var n := world.gate_dirs[next_gate]
		var d0 := (_prev_pos - g).dot(n)
		var d1 := (p - g).dot(n)
		if d0 < 0.0 and d1 >= 0.0:
			var hit := _prev_pos.lerp(p, d0 / (d0 - d1))
			if hit.distance_to(g) < WorldScript.GATE_RADIUS:
				_gate_passed()
	_prev_pos = p


func _gate_passed() -> void:
	if next_gate == 0:
		lap_running = true
		lap_time = 0.0
	next_gate += 1
	if next_gate >= world.gates.size():
		lap_running = false
		var best: float = Settings.best_lap
		net.announce_lap(lap_time, best <= 0.0 or lap_time < best)
		if best <= 0.0 or lap_time < best:
			Settings.put("best_lap", lap_time)
			hud.show_message("НОВЫЙ РЕКОРД", HudScript.format_time(lap_time), Color(0.45, 1.0, 0.55), 3.5)
		else:
			hud.show_message("КРУГ ПРОЙДЕН", HudScript.format_time(lap_time), Color.WHITE, 3.0)
		next_gate = 0
	else:
		hud.show_message("+", "", Color(1.0, 0.66, 0.2), 0.35)
	world.highlight_gates(next_gate)
	Input.vibrate_handheld(40)


func _update_hud() -> void:
	hud.speed_kmh = drone.velocity.length() * 3.6
	hud.altitude = drone.altitude()
	hud.battery = battery - drone.throttle_level * 0.5
	hud.flight_time = flight_time
	hud.gate_index = next_gate
	hud.gate_count = world.gates.size()
	hud.lap_time = lap_time
	hud.lap_running = lap_running
	hud.best_lap = Settings.best_lap
	hud.pitch = drone.pitch + drone.look_pitch
	hud.roll = drone.roll
	hud.throttle = drone.throttle_level
	hud.mode_text = ["EASY", "ANGLE", "ACRO"][drone.mode] + " · " + str(DroneScript.TYPES[drone.drone_type]["name"])
	hud.players = net.scoreboard()
	hud.keyboard_hint = not _touch_ui
	hud.camera_fov = drone.fpv_cam.fov
	var cam := get_viewport().get_camera_3d()
	if cam and next_gate < world.gates.size():
		var gp := world.gates[next_gate].global_position
		hud.target_behind = cam.is_position_behind(gp)
		hud.target_screen = cam.unproject_position(gp)
		hud.target_distance = drone.global_position.distance_to(gp)


# --- Automated check used by CI ---------------------------------------------

func _smoke_update(delta: float) -> void:
	_smoke_t += delta
	var t := _smoke_t
	match _smoke_step:
		0:
			if drone.drone_type != 2:
				Settings.put("drone_type", 2)
			touch.stick_l = Vector2(0.0, 1.0)
			touch.stick_r = Vector2(0.0, 0.25)
			if t > 3.0:
				print("SMOKE: rocket speed after 3 s = %d km/h" % roundi(drone.velocity.length() * 3.6))
				_shot("fpv_casual")
				Settings.put("third_person", true)
				Settings.put("control_mode", Settings.Controls.ACRO)
				_smoke_step = 1
		1:
			touch.stick_r = Vector2(0.5, 0.2)
			if t > 5.0:
				print("SMOKE: acro roll=%.2f pitch=%.2f alt=%d" % [drone.roll, drone.pitch, roundi(drone.altitude())])
				_shot("chase")
				Settings.put("third_person", false)
				Settings.put("control_mode", Settings.Controls.EASY)
				_smoke_step = 2
		2:
			touch.buttons["fwd"] = true
			touch.buttons["up"] = true
			if t > 7.5:
				_shot("fpv_easy")
				touch.reset()
				drone.reset_to(Vector3(150.0, 60.0, -300.0), atan2(-(420.0 - 150.0), -(-480.0 + 300.0)))
				_smoke_step = 3
		3:
			if t > 9.0:
				_shot("city")
				Settings.put("third_person", true)
				drone.reset_to(Vector3(-600.0, 40.0, 420.0), atan2(-(-720.0 + 600.0), -(600.0 - 420.0)))
				_smoke_step = 4
		4:
			if t > 10.5:
				_shot("village_chase")
				Settings.put("third_person", false)
				Settings.put("control_mode", Settings.Controls.CASUAL)
				_pause()
				_smoke_step = 5
		5:
			if t > 11.5:
				_shot("pause")
				menu._toggle_settings()
				_smoke_step = 7
		7:
			if t > 12.5:
				_shot("settings")
				menu._toggle_settings()
				menu._toggle_drones()
				_smoke_step = 8
		8:
			if t > 13.5:
				_shot("drones")
				menu._toggle_drones()
				_resume()
				_enter_menu()
				_smoke_step = 6
		6:
			if t > 15.5:
				_shot("menu")
				print("SMOKE OK")
				get_tree().quit()


func _shot(label: String) -> void:
	var tex := get_viewport().get_texture()
	if tex == null:
		return
	var img := tex.get_image()
	if img == null or img.is_empty():
		print("SHOT %s: no image (headless)" % label)
		return
	img.resize(640, 360, Image.INTERPOLATE_BILINEAR)
	var b64 := Marshalls.raw_to_base64(img.save_jpg_to_buffer(0.7))
	var parts := ceili(b64.length() / 3000.0)
	for i in parts:
		print("SHOT %s %d/%d %s" % [label, i + 1, parts, b64.substr(i * 3000, 3000)])


# --- Automated multiplayer check used by CI ------------------------------------
# One process runs with --net-host-test, another with --net-join-test; both must
# see each other's drone.

func _start_net_test() -> void:
	Settings.player_name = "CI-" + _net_test
	if _net_test == "host":
		net.host()
	else:
		net.join("127.0.0.1")
	_start_flight()


func _net_test_update(delta: float) -> void:
	_net_test_t += delta
	if net.pilots.size() > 0:
		var r: Node = net.pilots.values()[0]
		if r.get("pilot_name") != "":
			if _net_seen_t < 0.0:
				_net_seen_t = _net_test_t
				print("NET OK: %s sees %s" % [Settings.player_name, r.get("pilot_name")])
			# Keep sending a while longer so the other side sees us too.
			if _net_test_t - _net_seen_t > 4.0:
				get_tree().quit()
			return
	if _net_test_t > 60.0:
		print("NET FAIL: %s saw nobody (%s)" % [Settings.player_name, net.status])
		get_tree().quit()
