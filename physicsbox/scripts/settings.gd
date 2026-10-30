extends Node
## Persistent player settings + input map setup (autoload "Settings").

const PATH := "user://settings.cfg"

var sensitivity := 1.0
var fov := 75.0
var render_scale := 0.9
var shadows := true
var blood_amount := 1.0
var volume := 0.8
var show_fps := false
## Bodycam look: wide lens, distortion, grain, timestamp.
var bodycam := true
## Which camera films the fight (HUD button КАМЕРА): "bodycam" on the chest
## or "gopro" on the side of the helmet (fisheye, the helmet's edge in view).
var camera := "bodycam"
## What the player takes into battle (weapon menu: ОРУЖИЕ / СНАРЯЖЕНИЕ):
## item id -> carried; and which rifles wear the PBS-1 suppressor.
var loadout := {"ak74": true, "svd": true, "asval": true, "grenade": true, "fpv": true, "medkit": true}
var suppressed := {"ak74": false, "svd": false}
## The AK's sight (МОДИФИКАЦИИ): "collimator" (round tube, as on the video)
## or "kobra".
var sight := {"ak74": "collimator"}
## Resources the menu loaded on background threads for the battle (kept
## referenced so they stay in the cache).
var preloaded: Array = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_input()
	load_settings()
	apply()


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		# Phones get a lighter default resolution.
		if OS.has_feature("mobile"):
			render_scale = 0.85
		return
	sensitivity = cfg.get_value("game", "sensitivity", sensitivity)
	fov = cfg.get_value("game", "fov", fov)
	blood_amount = cfg.get_value("game", "blood_amount", blood_amount)
	render_scale = cfg.get_value("video", "render_scale", render_scale)
	if cfg.get_value("video", "quality_rev", 0) < 1:
		render_scale = maxf(render_scale, 0.85) # the picture made a little sharper (once)
	shadows = cfg.get_value("video", "shadows", shadows)
	show_fps = cfg.get_value("video", "show_fps", show_fps)
	bodycam = cfg.get_value("video", "bodycam", bodycam)
	camera = cfg.get_value("video", "camera", camera)
	volume = cfg.get_value("audio", "volume", volume)
	for k in loadout:
		loadout[k] = cfg.get_value("loadout", k, loadout[k])
	for k in suppressed:
		suppressed[k] = cfg.get_value("suppressor", k, suppressed[k])
	for k in sight:
		sight[k] = cfg.get_value("sight", k, sight[k])


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("game", "sensitivity", sensitivity)
	cfg.set_value("game", "fov", fov)
	cfg.set_value("game", "blood_amount", blood_amount)
	cfg.set_value("video", "render_scale", render_scale)
	cfg.set_value("video", "quality_rev", 1)
	cfg.set_value("video", "shadows", shadows)
	cfg.set_value("video", "show_fps", show_fps)
	cfg.set_value("video", "bodycam", bodycam)
	cfg.set_value("video", "camera", camera)
	cfg.set_value("audio", "volume", volume)
	for k in loadout:
		cfg.set_value("loadout", k, loadout[k])
	for k in suppressed:
		cfg.set_value("suppressor", k, suppressed[k])
	for k in sight:
		cfg.set_value("sight", k, sight[k])
	cfg.save(PATH)


func carries(item: String) -> bool:
	return loadout.get(item, true)


func apply() -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(volume, 0.001)))
	get_tree().root.scaling_3d_scale = render_scale
	get_tree().call_group("settings_listeners", "on_settings_changed")


func _setup_input() -> void:
	_key_action("move_forward", [KEY_W])
	_key_action("move_back", [KEY_S])
	_key_action("move_left", [KEY_A])
	_key_action("move_right", [KEY_D])
	# the arrows steer the FPV drone
	_key_action("fpv_up", [KEY_UP])
	_key_action("fpv_down", [KEY_DOWN])
	_key_action("fpv_left", [KEY_LEFT])
	_key_action("fpv_right", [KEY_RIGHT])
	_key_action("jump", [KEY_SPACE])
	_key_action("sprint", [KEY_SHIFT])
	_key_action("crouch", [KEY_C, KEY_CTRL])
	_key_action("reload", [KEY_R])
	_key_action("pause", [KEY_ESCAPE])
	_key_action("weapon_1", [KEY_1])
	_key_action("weapon_2", [KEY_2])
	_key_action("weapon_3", [KEY_3])
	# first aid: bandage, promedol, medkit, call the medic; the camera
	_key_action("bandage", [KEY_Z])
	_key_action("painkiller", [KEY_X])
	_key_action("medkit", [KEY_T])
	_key_action("call_medic", [KEY_M])
	_key_action("camera", [KEY_K])
	_key_action("weapon_next", [KEY_F])
	_key_action("weapon_menu", [KEY_B, KEY_TAB])
	_key_action("grenade", [KEY_G])
	_key_action("drone", [KEY_V])
	_key_action("holster", [KEY_H])
	_key_action("fpv_climb", [KEY_E])
	_key_action("fpv_sink", [KEY_Q])
	for i in 6: # orders on 4..9, then 0 and minus
		_key_action("order_%d" % (i + 1), [KEY_4 + i])
	_key_action("order_7", [KEY_0])
	_key_action("order_8", [KEY_MINUS])
	_mouse_action("fire", MOUSE_BUTTON_LEFT)
	_mouse_action("aim", MOUSE_BUTTON_RIGHT)


func _key_action(action: String, keys: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action, ev)


func _mouse_action(action: String, button: MouseButton) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	InputMap.action_add_event(action, ev)
