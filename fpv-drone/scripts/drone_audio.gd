extends Node
## Motor whine and wind noise, generated procedurally (no audio files).

const RATE := 22050

var enabled := true

var _motor := AudioStreamPlayer.new()
var _wind := AudioStreamPlayer.new()


func _ready() -> void:
	_motor.stream = _make_motor()
	_motor.volume_db = -60.0
	add_child(_motor)
	_wind.stream = _make_wind()
	_wind.volume_db = -60.0
	add_child(_wind)


func set_running(on: bool) -> void:
	if on and enabled:
		if not _motor.playing:
			_motor.play()
			_wind.play()
	else:
		_motor.stop()
		_wind.stop()


func update(throttle: float, speed: float, delta: float) -> void:
	if not _motor.playing:
		return
	var k := 1.0 - exp(-8.0 * delta)
	_motor.pitch_scale = lerpf(_motor.pitch_scale, 0.75 + throttle * 1.5 + speed * 0.004, k)
	_motor.volume_db = linear_to_db(0.18 + throttle * 0.5) - 6.0
	_wind.volume_db = linear_to_db(clampf(speed / 40.0, 0.0, 1.0) * 0.7 + 0.002) - 4.0


static func _saw(x: float) -> float:
	return 2.0 * (x - floorf(x + 0.5))


func _make_motor() -> AudioStreamWAV:
	var n := RATE # one second; 100 Hz base loops cleanly
	var data := PackedByteArray()
	data.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		var s := _saw(t * 100.0) * 0.4 + _saw(t * 200.0) * 0.2 + sin(TAU * t * 300.0) * 0.12 + sin(TAU * t * 50.0) * 0.15
		lp += (rng.randf_range(-1.0, 1.0) - lp) * 0.2
		s += lp * 0.25
		data.encode_s16(i * 2, int(clampf(s * 0.7, -1.0, 1.0) * 32767.0))
	return _wav(data, n)


func _make_wind() -> AudioStreamWAV:
	var n := RATE * 2
	var data := PackedByteArray()
	data.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	var lp := 0.0
	var lp2 := 0.0
	for i in n:
		lp += (rng.randf_range(-1.0, 1.0) - lp) * 0.08
		lp2 += (lp - lp2) * 0.15
		var fade := minf(1.0, minf(i, n - i) / 800.0)
		data.encode_s16(i * 2, int(clampf(lp2 * 3.0 * fade, -1.0, 1.0) * 32767.0))
	return _wav(data, n)


func _wav(data: PackedByteArray, frames: int) -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = data
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = frames
	return wav
