extends Node
## Persistent player settings + input map setup (autoload "Settings").

const PATH := "user://settings.cfg"

var sensitivity := 1.0
var fov := 75.0
var render_scale := 0.85
var shadows := true
var blood_amount := 1.0
var volume := 0.8
var show_fps := false
## Level chosen in the main menu ("house" / "shop"); not saved.
var level := "trenches"


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
			render_scale = 0.75
		return
	sensitivity = cfg.get_value("game", "sensitivity", sensitivity)
	fov = cfg.get_value("game", "fov", fov)
	blood_amount = cfg.get_value("game", "blood_amount", blood_amount)
	render_scale = cfg.get_value("video", "render_scale", render_scale)
	shadows = cfg.get_value("video", "shadows", shadows)
	show_fps = cfg.get_value("video", "show_fps", show_fps)
	volume = cfg.get_value("audio", "volume", volume)


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("game", "sensitivity", sensitivity)
	cfg.set_value("game", "fov", fov)
	cfg.set_value("game", "blood_amount", blood_amount)
	cfg.set_value("video", "render_scale", render_scale)
	cfg.set_value("video", "shadows", shadows)
	cfg.set_value("video", "show_fps", show_fps)
	cfg.set_value("audio", "volume", volume)
	cfg.save(PATH)


func apply() -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(volume, 0.001)))
	get_tree().root.scaling_3d_scale = render_scale
	get_tree().call_group("settings_listeners", "on_settings_changed")


func _setup_input() -> void:
	_key_action("move_forward", [KEY_W, KEY_UP])
	_key_action("move_back", [KEY_S, KEY_DOWN])
	_key_action("move_left", [KEY_A, KEY_LEFT])
	_key_action("move_right", [KEY_D, KEY_RIGHT])
	_key_action("jump", [KEY_SPACE])
	_key_action("reload", [KEY_R])
	_key_action("spawn_npc", [KEY_E])
	_key_action("slowmo", [KEY_Q])
	_key_action("pause", [KEY_ESCAPE])
	_key_action("weapon_1", [KEY_1])
	_key_action("weapon_2", [KEY_2])
	_key_action("weapon_next", [KEY_F])
	_key_action("toggle_ai", [KEY_T])
	_key_action("weapon_menu", [KEY_B, KEY_TAB])
	_key_action("grenade", [KEY_G])
	_key_action("drone", [KEY_V])
	for i in 7: # orders on 3..9, then 0
		_key_action("order_%d" % (i + 1), [KEY_3 + i])
	_key_action("order_8", [KEY_0])
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
