extends RefCounted
## Roll-out intro after choosing a vehicle at the airbase: a jet taxis out of the hangar, lines up and takes off
## from the runway, a helicopter lifts off the helipad, ground vehicles drive out of the garage. The game drives
## the vehicle through this script, then hands control to the player in flight / on the move.

const Base := preload("res://scripts/base.gd")
const Vehicle := preload("res://scripts/vehicle.gd")

var game: Node
var v
var kind: String
var t := 0.0
var done := false
var pts := PackedVector2Array()   # path sampled every metre
var s := 0.0                      # distance along the path
var spd := 0.0
var s_roll := 0.0                 # plane: where the take-off roll starts (lined up on the runway)
var alt := 0.0                    # plane: height above the runway after lift-off
var gamma := 0.0                  # plane: climb angle
var pitch := 0.0
var air_t := 0.0
var length := 0.0                 # total intro length estimate, for the camera swing


func _init(g: Node, veh) -> void:
	game = g
	v = veh
	kind = v.cat
	match kind:
		"plane":
			var hx := Base.HANGAR.x + 3.0
			var door := Base.HANGAR.x - Base.HANGAR_D / 2.0
			var path := [Vector2(hx, Base.HANGAR.y), Vector2(door - 20.0, Base.HANGAR.y), Vector2(Base.RW_X + 18.0, Base.HANGAR.y),
				Vector2(Base.RW_X, Base.HANGAR.y - 30.0), Vector2(Base.RW_X, Base.RW_Z1 - 6000.0)]
			pts = _rounded(path, 22.0)
			s_roll = _closest(Vector2(Base.RW_X, Base.HANGAR.y - 40.0))
			length = 26.0
			v.show_gear(true)
		"heli":
			pts = _rounded([Base.HELIPAD, Base.HELIPAD + Vector2(0, -3000)], 10.0)
			length = 11.0
		_:
			pts = _rounded([Base.GARAGE + Vector2(0, 2.0), Base.GARAGE + Vector2(0, -70.0)], 10.0)
			length = 9.0
	_place(0.0)
	v.vel = Vector3.ZERO
	v.speed = 0.0


## Polyline with every inner corner replaced by a quadratic curve, resampled every metre.
static func _rounded(p: Array, r: float) -> PackedVector2Array:
	var dense := PackedVector2Array()
	dense.append(p[0])
	for i in range(1, p.size()):
		var a: Vector2 = p[i - 1]
		var b: Vector2 = p[i]
		if i < p.size() - 1:
			var c: Vector2 = p[i + 1]
			var k1 := b + (a - b).normalized() * minf(r, a.distance_to(b) * 0.45)
			var k2 := b + (c - b).normalized() * minf(r, c.distance_to(b) * 0.45)
			dense.append(k1)
			for q in range(1, 12):
				var u := q / 12.0
				dense.append(k1.lerp(b, u).lerp(b.lerp(k2, u), u))
			dense.append(k2)
		else:
			dense.append(b)
	var out := PackedVector2Array()
	out.append(dense[0])
	var carry := 0.0
	for i in range(1, dense.size()):
		var a := dense[i - 1]
		var b := dense[i]
		var l := a.distance_to(b)
		var d := 1.0 - carry
		while d <= l:
			out.append(a.lerp(b, d / l))
			d += 1.0
		carry = l - (d - 1.0)
	return out


func _closest(q: Vector2) -> float:
	var best := 0
	for i in pts.size():
		if pts[i].distance_squared_to(q) < pts[best].distance_squared_to(q):
			best = i
	return float(best)


func _at(dist: float) -> Vector2:
	var i := clampi(int(dist), 0, pts.size() - 2)
	return pts[i].lerp(pts[i + 1], clampf(dist - i, 0.0, 1.0))


func _heading_at(dist: float) -> float:
	var a := _at(dist)
	var b := _at(dist + 4.0)
	if a.distance_to(b) < 0.01:
		return v.heading
	return Vehicle.heading_of(Vector3(b.x - a.x, 0, b.y - a.y))


func _place(lift: float) -> void:
	var q := _at(s)
	var gy: float = game.world.height(q.x, q.y)
	v.heading = _heading_at(s)
	v.pos = Vector3(q.x, gy + v.gear_h + lift, q.y)
	if kind == "tank":
		v.pos.y = gy
		v.rot = v._terrain_basis()
	else:
		v.rot = Basis.from_euler(Vector3(pitch, v.heading, 0.0))
	v.turret_yaw = v.heading
	v.aim_dir = Vehicle.dir_of(v.heading)
	v.fixed_dir = v.aim_dir
	v.vel = v.fwd() * spd
	v.speed = spd


func _climb_vel() -> Vector3:
	return (Vehicle.dir_of(v.heading) * cos(gamma) + Vector3(0, sin(gamma), 0)) * spd


## Advance the intro; returns true when it is over.
func update(dt: float) -> bool:
	if done:
		return true
	t += dt
	match kind:
		"plane": _plane(dt)
		"heli": _heli(dt)
		_: _ground(dt)
	return done


func _plane(dt: float) -> void:
	var thr := 0.3
	if s < s_roll:
		# taxi out of the hangar and onto the runway
		spd = move_toward(spd, 14.0, 4.0 * dt)
	else:
		thr = 1.0
		spd += 8.0 * dt
	s += spd * dt
	if spd > 78.0:
		# rotate, lift off, gear up and climb away
		air_t += dt
		gamma = minf(gamma + 0.09 * dt, 0.17)
		alt += spd * sin(gamma) * dt
		if alt > 12.0:
			v.show_gear(false)
	pitch = lerpf(pitch, (gamma + 0.1) if spd > 74.0 else 0.0, 1.0 - exp(-2.5 * dt))
	_place(alt)
	v.vel = _climb_vel()
	game.ctrl["thr"] = thr
	for fl in v.flames:
		fl.pixel_size = 0.004 * ((3.4 + randf() * 1.2) if thr > 0.9 else 0.6)
	if air_t > 6.0 or s > pts.size() - 10:
		done = true


func _heli(dt: float) -> void:
	# rotor spool-up, a vertical lift-off, then nose down and away to the north
	var lift := smoothstep(2.5, 6.0, t) * 22.0
	if t > 6.0:
		spd = minf(spd + 5.0 * dt, 45.0)
		lift += (t - 6.0) * 6.0
	s += spd * dt
	pitch = -0.16 * smoothstep(5.5, 7.0, t) + 0.1 * smoothstep(9.5, 11.0, t)
	_place(lift)
	game.ctrl["thr"] = 0.6
	if t > 11.0:
		done = true


func _ground(dt: float) -> void:
	spd = minf(spd + 2.2 * dt, 8.0)
	s += spd * dt
	_place(0.0)
	game.ctrl["thr"] = 0.75
	if s > pts.size() - 3 or t > 14.0:
		done = true


## Fast-forward to the end (the "Skip" button).
func skip() -> void:
	var guard := 0
	while not done and guard < 2000:
		update(0.05)
		guard += 1


## Hand the vehicle over to the player in a flyable / drivable state.
func finish() -> void:
	v.intro = null
	match kind:
		"plane":
			v.show_gear(false)
			v.w = Vector3.ZERO
			v.vel = _climb_vel()
			v.speed = spd
		"heli":
			v.pitch_v = 0.0
			v.roll_v = 0.0
			v.vy = 0.0
			v.yaw_rate = 0.0
			v.vel = Vehicle.dir_of(v.heading) * spd
		_:
			v.fspd = spd
