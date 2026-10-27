extends Node
## Sound: positional one-shots from a pool, the player's engine loop and cockpit tones.

const LOOPS := ["jet", "heli", "tank", "lock"]
var streams := {}
var pool: Array[AudioStreamPlayer3D] = []
var pool_i := 0
var engine := AudioStreamPlayer.new()
var lock := AudioStreamPlayer.new()
var ui := AudioStreamPlayer.new()
var warn := AudioStreamPlayer.new()


func _ready() -> void:
	for n in ["jet", "heli", "tank", "gun", "mg", "cannon", "explosion", "missile", "rocket", "flare", "smoke", "hit", "beep", "lock", "warn", "click",
			"ak", "shotgun", "reload", "flesh", "headshot", "step"]:
		var s: AudioStreamWAV = load("res://assets/sounds/%s.wav" % n)
		if n in LOOPS:
			s = s.duplicate()
			s.loop_mode = AudioStreamWAV.LOOP_FORWARD
			s.loop_begin = 0
			s.loop_end = int(s.get_length() * s.mix_rate)
		streams[n] = s
	for i in 24:
		var p := AudioStreamPlayer3D.new()
		p.unit_size = 40.0
		p.max_distance = 4000.0
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		add_child(p)
		pool.append(p)
	for p in [engine, lock, ui, warn]:
		add_child(p)
	lock.stream = streams["lock"]
	lock.volume_db = -14.0


func play3d(n: String, at: Vector3, vol_db := 0.0, unit := 40.0, pitch := 1.0) -> void:
	var p := pool[pool_i]
	pool_i = (pool_i + 1) % pool.size()
	p.stream = streams[n]
	p.global_position = at
	p.volume_db = vol_db
	p.unit_size = unit
	p.pitch_scale = pitch * randf_range(0.94, 1.06)
	p.play()


func tone(n: String, vol_db := -8.0, pitch := 1.0) -> void:
	var p := warn if n == "warn" else ui
	if not streams.has(n):
		return
	p.stream = streams[n]
	p.volume_db = vol_db
	p.pitch_scale = pitch
	p.play()


func set_engine(kind: String, level: float, pitch: float) -> void:
	if kind == "":
		engine.stop()
		return
	if engine.stream != streams[kind]:
		engine.stream = streams[kind]
	if not engine.playing:
		engine.play()
	engine.volume_db = linear_to_db(clampf(level, 0.001, 1.0))
	engine.pitch_scale = pitch


func set_lock(on: bool) -> void:
	if on and not lock.playing:
		lock.play()
	elif not on and lock.playing:
		lock.stop()
