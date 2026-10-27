extends Node
## Game settings shared by every scene. Saved to user://settings.cfg.

signal changed

const PATH := "user://settings.cfg"

enum Controls { EASY, CASUAL, ACRO }
enum Quality { LOW, MEDIUM, HIGH }

var shadows := true
var bloom := true
var control_mode: int = Controls.CASUAL
var quality: int = Quality.MEDIUM
var camera_tilt := 20.0
var sensitivity := 1.0
var sound := true
var third_person := false
var best_lap := 0.0
var drone_type := 0
var player_name := "Пилот %d" % (randi() % 900 + 100)

const _KEYS := [
	"shadows", "bloom", "control_mode", "quality", "camera_tilt",
	"sensitivity", "sound", "third_person", "best_lap", "drone_type",
	"player_name",
]


func _ready() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		save() # keeps the generated pilot name
		return
	for key: String in _KEYS:
		if cfg.has_section_key("game", key):
			set(key, cfg.get_value("game", key))


func save() -> void:
	var cfg := ConfigFile.new()
	for key: String in _KEYS:
		cfg.set_value("game", key, get(key))
	cfg.save(PATH)


## Changes one setting, saves it and notifies listeners.
func put(key: String, value: Variant) -> void:
	set(key, value)
	save()
	changed.emit()
