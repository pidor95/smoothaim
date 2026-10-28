extends Node
## Sound effect player with voice pools (autoload "Sfx").

const SOUNDS := {
	"gunshot": ["gunshot"],
	"dry_fire": ["dry_fire"],
	"reload": ["reload"],
	"shotgun_shot": ["shotgun_shot"],
	"shotgun_reload": ["shotgun_reload"],
	"shotgun_pump": ["shotgun_pump"],
	"wall_hit": ["wall_hit_0", "wall_hit_1"],
	"wood_hit": ["wood_hit"],
	"metal_hit": ["metal_hit"],
	"glass_break": ["glass_break"],
	"footstep": ["footstep_0", "footstep_1", "footstep_2"],
	"ui_click": ["ui_click"],
	"hitmarker": ["hitmarker"],
}
const VOICES_3D := 24
const VOICES_2D := 8

var _streams := {}
var _players_3d: Array[AudioStreamPlayer3D] = []
var _players_2d: Array[AudioStreamPlayer] = []
var _next_3d := 0
var _next_2d := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for key in SOUNDS:
		var list: Array[AudioStream] = []
		for file in SOUNDS[key]:
			list.append(load("res://assets/sounds/%s.wav" % file))
		_streams[key] = list
	for i in VOICES_3D:
		var p := AudioStreamPlayer3D.new()
		p.unit_size = 5.0
		p.max_distance = 70.0
		p.attenuation_filter_cutoff_hz = 9000.0
		add_child(p)
		_players_3d.append(p)
	for i in VOICES_2D:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players_2d.append(p)


func _pick(sound: String) -> AudioStream:
	var list: Array = _streams.get(sound, [])
	if list.is_empty():
		return null
	return list[randi() % list.size()]


## Positional sound in the 3D world.
func play_3d(sound: String, pos: Vector3, volume_db := 0.0, pitch_var := 0.08) -> void:
	var stream := _pick(sound)
	if stream == null:
		return
	var p := _players_3d[_next_3d]
	_next_3d = (_next_3d + 1) % VOICES_3D
	p.stream = stream
	p.global_position = pos
	p.volume_db = volume_db
	p.pitch_scale = randf_range(1.0 - pitch_var, 1.0 + pitch_var)
	p.play()


## Non-positional sound (player's own gun, UI).
func play(sound: String, volume_db := 0.0, pitch_var := 0.04) -> void:
	var stream := _pick(sound)
	if stream == null:
		return
	var p := _players_2d[_next_2d]
	_next_2d = (_next_2d + 1) % VOICES_2D
	p.stream = stream
	p.volume_db = volume_db
	p.pitch_scale = randf_range(1.0 - pitch_var, 1.0 + pitch_var)
	p.play()
