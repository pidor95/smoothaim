class_name Player
extends CharacterBody3D
## First-person player controller (touch + keyboard/mouse).

const SPEED := 4.6
const AIM_SPEED := 2.4
## Sprint (button / joystick pushed hard forward / Shift) while stamina
## lasts; crouch (button / C, Ctrl) - low enough to hide in the fighting trench.
const SPRINT_SPEED := 7.2
const CROUCH_SPEED := 2.0
const JUMP_VELOCITY := 4.8
const GRAVITY := 12.0
const EYE_HEIGHT := 1.62
const CROUCH_EYE := 1.0
const STAND_HEIGHT := 1.8
const CROUCH_HEIGHT := 1.15

var head := Node3D.new()
var camera := Camera3D.new()
## Where the gun points (and the bullets go): the camera rides on the chest
## and sways on its own, the gun in the hands only follows part of that, so
## the gun, its sight and the aiming dot drift about in the picture.
var aim := Node3D.new()
## Share of the camera's sway the gun follows: from the hip, aimed down the
## sights (the eye on the sight), through a scope.
const AIM_FOLLOW := Vector3(0.15, 0.6, 0.85)
var _hand_lag := Vector2.ZERO
var _hand_lag_v := Vector2.ZERO
var _hand_prev := Vector2.ZERO
var weapon: Weapon
var touch_mode := false
var touch_move := Vector2.ZERO
var jump_queued := false
var sprint := false # wants to run (toggled by the HUD button / held Shift)
var sprint_stick := false # joystick pushed hard forward (HUD)
var sprinting := false # actually running now
var crouching := false
var stamina := 1.0
var _eye := EYE_HEIGHT
var _sprint_block := 0.0
var _shape: CapsuleShape3D
var _shape_node: CollisionShape3D
var yaw := 0.0
var pitch := 0.0

var _look_accum := Vector2.ZERO
var _recoil := Vector2.ZERO
var _step_dist := 0.0
var _spawn: Transform3D
var _feet := Area3D.new()

## Immortality (weapon menu): NPC bullets do no harm.
static var immortal := false
## Wounds: every bullet (or fragment) that hits bleeds; the fifth kills.
## Heart rate, blood and consciousness feed the status panel (HUD, bottom
## left); too little blood also kills.
const LETHAL_HITS := 5
const BLOOD_FULL := 5000.0
const BLOOD_DEATH := 2400.0
const RESPAWN_TIME := 8.0
var hits := 0
var blood := BLOOD_FULL
var bleed_rate := 0.0 # ml per second, clots slowly
var bpm := 72.0
var consciousness := 1.0
var dead := false
var death_t := 0.0 # seconds since death: the HUD fades to black round a white dot
var ear_ring := 0.0 # 0..1 ringing in the ears (blasts, hits, death)
var hurt_flash := 0.0 # 1 on a hit, fades (HUD red vignette)
## First aid (the row over the hotbar, keys Z X T M): a bandage slows the
## bleeding, promedol takes the pain away for a while, the medkit patches up
## two wounds; the medic (called over) puts him right. Medkits lying on the
## map refill everything.
const MAX_BANDAGES := 3
const MAX_PROMEDOL := 2
const MAX_MEDKITS := 2
const TREAT_TIMES := {"bandage": 3.0, "promedol": 1.6, "medkit": 6.0}
var bandages := 0
var promedol := 0
var medkits := 0
var painkiller := 0.0 # seconds of promedol left
var treating := "" # what he is putting on now
var treat_t := 0.0
var wants_medic := false # called the medic; one is on the way
var medic_note := "" # HUD line about the medic / a pickup
var medic_note_t := 0.0
var heart_phase := 0.0 # 0..1 within the current beat (HUD ECG)
var _stress := 0.0
var _ring_player := AudioStreamPlayer.new()
var _heart_player := AudioStreamPlayer.new()
var _muffle := AudioEffectLowPassFilter.new()
var _muffle_idx := -1

## Grenades and FPV drones carried; one more comes back every so often.
const MAX_GRENADES := 4
const MAX_DRONES := 2
var grenades := MAX_GRENADES
var drones := MAX_DRONES
var piloting: FpvDrone # flying a drone through its camera
var signal_lost := 0.0 # HUD static after the drone is gone
var shake := 0.0
var drone_arrows := Vector2.ZERO # on-screen arrows while flying the drone (HUD)
var drone_climb := 0.0 # ВЫШЕ / НИЖЕ buttons while flying the drone
var scope_shift := Vector2.ZERO # the eyepiece's shadow drifting with the sway (HUD)
# bodycam: the camera rides on the chest (see _bodycam_motion)
var _last_yaw := 0.0
var _last_pitch := 0.0
var _lag := Vector2.ZERO
var _lag_v := Vector2.ZERO
var _step_phase := 0.0
var _cam_t := 0.0
var _jp := Vector3.ZERO
var _jp_v := Vector3.ZERO
var _jr := Vector3.ZERO
var _jr_v := Vector3.ZERO
var _was_on_floor := true
var _grenade_regen := 0.0
var _drone_regen := 0.0


func _ready() -> void:
	add_to_group("player")
	add_to_group("settings_listeners")
	collision_layer = 16
	collision_mask = 1 | 2 | 8
	floor_snap_length = 0.35
	floor_max_angle = deg_to_rad(50)
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.33
	cap.height = STAND_HEIGHT
	cs.shape = cap
	cs.position = Vector3(0, STAND_HEIGHT / 2.0, 0)
	add_child(cs)
	_shape = cap
	_shape_node = cs

	# feet zone: walking through bodies and gore shoves them around
	_feet.collision_layer = 0
	_feet.collision_mask = 4 | 32
	_feet.monitorable = false
	var fs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.5
	cyl.height = 0.7
	fs.shape = cyl
	fs.position = Vector3(0, 0.35, 0)
	_feet.add_child(fs)
	add_child(_feet)

	head.position = Vector3(0, EYE_HEIGHT, 0)
	add_child(head)
	camera.near = 0.03
	camera.far = 260.0
	camera.current = true
	head.add_child(camera)
	aim.position = head.position
	add_child(aim)
	weapon = Weapon.new()
	weapon.player = self
	aim.add_child(weapon)

	yaw = rotation.y
	_spawn = global_transform
	touch_mode = DisplayServer.is_touchscreen_available() or OS.has_feature("mobile")
	_restock(Settings.carries("medkit"))
	_build_helmet()
	on_settings_changed()

	# ringing ears and a pounding heart; blasts and wounds muffle the world
	var ring: AudioStreamWAV = load("res://assets/sounds/tinnitus.wav").duplicate()
	ring.loop_mode = AudioStreamWAV.LOOP_FORWARD
	ring.loop_end = int(ring.get_length() * ring.mix_rate)
	_ring_player.stream = ring
	_ring_player.volume_db = -80.0
	add_child(_ring_player)
	_heart_player.stream = load("res://assets/sounds/heartbeat.wav")
	add_child(_heart_player)
	_muffle.cutoff_hz = 20000.0
	_muffle_idx = AudioServer.get_bus_effect_count(0)
	AudioServer.add_bus_effect(0, _muffle)


func _exit_tree() -> void:
	for i in AudioServer.get_bus_effect_count(0):
		if AudioServer.get_bus_effect(0, i) == _muffle:
			AudioServer.remove_bus_effect(0, i)
			break


func on_settings_changed() -> void:
	camera.fov = Settings.fov
	if _helmet:
		_helmet.visible = gopro()


## The GoPro on the side of the helmet (Settings.camera): the camera sits
## higher and to the right of the eyes, sees wider, and the helmet's rim
## bulges into the top left corner.
const GOPRO_AT := Vector3(0.1, 0.13, 0.03)
const GOPRO_GUN := Vector3(-0.12, 0.03, -0.05) # the gun sits more in the middle of its view
var _helmet: MeshInstance3D


func gopro() -> bool:
	return Settings.camera == "gopro"


func _build_helmet() -> void:
	_helmet = MeshInstance3D.new()
	var m := SphereMesh.new()
	m.radius = 0.16
	m.height = 0.24
	m.radial_segments = 32
	m.rings = 16
	_helmet.mesh = m
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load(Npc.TEAM_CAMO[0])
	mat.albedo_color = Color(0.5, 0.5, 0.46)
	mat.uv1_triplanar = true
	mat.uv1_scale = Vector3.ONE * 2.5
	mat.roughness = 0.75
	_helmet.material_override = mat
	_helmet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# the helmet's middle is to the left of, above and a touch behind the
	# camera: only its rim shows, in the top left corner
	_helmet.position = Vector3(-0.2, 0.12, -0.03)
	_helmet.rotation = Vector3(0.2, 0.0, -0.35)
	camera.add_child(_helmet)


## The КАМЕРА button: bodycam on the chest <-> GoPro on the helmet.
func toggle_camera() -> void:
	Settings.camera = "bodycam" if gopro() else "gopro"
	Settings.save_settings()
	Settings.apply()
	medic_note = "Камера: GoPro на шлеме (4K 60FPS) [экшн-камера]" if gopro() else "Камера: нательная (бодикам)"
	medic_note_t = 2.5


# ------------------------------------------------------------------ first aid

func _restock(full: bool) -> void:
	bandages = 2 if full else 0
	promedol = 1 if full else 0
	medkits = 1 if full else 0


## A medkit picked up off the ground: everything topped up.
func pick_medkit() -> void:
	bandages = MAX_BANDAGES
	promedol = MAX_PROMEDOL
	medkits = mini(medkits + 1, MAX_MEDKITS)
	medic_note = "+ АПТЕЧКА: бинты, промедол"
	medic_note_t = 2.0
	Sfx.play("ui_click", -4.0)


## Starts putting on `what` ("bandage", "promedol", "medkit"): the gun goes
## down for TREAT_TIMES[what] seconds. False when it cannot be done.
func start_treat(what: String) -> bool:
	if dead or treating != "" or piloting or weapon.throwing():
		return false
	var have := {"bandage": bandages, "promedol": promedol, "medkit": medkits}
	if have.get(what, 0) <= 0:
		medic_note = {"bandage": "Бинтов нет", "promedol": "Промедола нет", "medkit": "Аптечек нет"}[what]
		medic_note_t = 1.5
		return false
	match what:
		"bandage":
			bandages -= 1
		"promedol":
			promedol -= 1
		"medkit":
			medkits -= 1
	treating = what
	treat_t = 0.0
	weapon.busy = true
	weapon.trigger_held = false
	weapon.set_aiming(false)
	Sfx.play("ui_click", -10.0)
	return true


func _treat_done() -> void:
	match treating:
		"bandage":
			bleed_rate *= 0.15
			medic_note = "Кровотечение остановлено" if bleed_rate < 1.0 else "Перевязано"
		"promedol":
			painkiller = 120.0
			ear_ring = 0.0
			_stress = 0.0
			medic_note = "Промедол: боль ушла"
		"medkit":
			bleed_rate = 0.0
			hits = maxi(hits - 2, 0)
			blood = minf(blood + 700.0, BLOOD_FULL)
			medic_note = "Раны обработаны"
	medic_note_t = 1.8
	treating = ""
	weapon.busy = false


## Calls a medic over (the game sends the nearest of his side).
func call_medic() -> void:
	if dead:
		return
	wants_medic = true
	var game := get_tree().current_scene
	if game and game.has_method("call_medic"):
		medic_note = game.call_medic()
	medic_note_t = 3.0


## The medic has done his work: all wounds dressed, bleeding stopped.
func medic_heal() -> void:
	wants_medic = false
	hits = 0
	bleed_rate = 0.0
	blood = maxf(blood, 4700.0)
	medic_note = "Медик: раны перевязаны"
	medic_note_t = 2.5


func capture_mouse() -> void:
	if not touch_mode:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Rotate the view by a screen-space delta in pixels (or steer the drone).
func look(delta_px: Vector2, scale := 1.0) -> void:
	if piloting:
		piloting.look_input(delta_px * scale)
		return
	# slower when aiming, much slower through a scope
	var zoom: float = clampf(weapon.current.def.ads_fov * 1.3, 0.28, 0.6)
	var s := 0.13 * Settings.sensitivity * scale * lerpf(1.0, zoom, weapon.aim_t)
	yaw -= deg_to_rad(delta_px.x * s)
	pitch = clampf(pitch - deg_to_rad(delta_px.y * s), deg_to_rad(-88), deg_to_rad(88))
	_look_accum += delta_px * scale


func consume_look_delta() -> Vector2:
	var d := _look_accum
	_look_accum = Vector2.ZERO
	return d


func add_recoil(up: float, side: float) -> void:
	_recoil += Vector2(up, side)


func _unhandled_input(event: InputEvent) -> void:
	if touch_mode:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		look(event.relative, 0.6)
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		capture_mouse()


## Hit by a bullet or a fragment (`kind` "bullet"), or caught in a blast
## ("blast": `amount` 0..130 by how close).
func take_damage(amount: float, dir: Vector3, kind := "bullet") -> void:
	if dead:
		return
	hurt_flash = 1.0
	_stress = 1.0
	add_recoil(deg_to_rad(randf_range(1.5, 3.0)), deg_to_rad(randf_range(-2.0, 2.0)))
	if immortal:
		return
	velocity += Vector3(dir.x, 0.0, dir.z) * 1.2
	if kind == "blast":
		ear_ring = maxf(ear_ring, clampf(amount / 50.0, 0.4, 1.0))
		blood -= amount * 6.0
		bleed_rate += amount * 0.08
		if amount >= 75.0:
			die()
		return
	hits += 2 if kind == "sniper" else 1
	_jolt(Vector3(dir.x, 0.0, dir.z) * 0.03, Vector3(-0.06, randf_range(-0.04, 0.04), randf_range(-0.06, 0.06)))
	blood -= randf_range(120.0, 260.0)
	bleed_rate += randf_range(4.0, 7.0)
	ear_ring = maxf(ear_ring, 0.3)
	if hits >= LETHAL_HITS:
		die()


func die() -> void:
	if dead:
		return
	dead = true
	death_t = 0.0
	ear_ring = 1.0
	treating = ""
	weapon.busy = false
	wants_medic = false
	weapon.drop() # slips out of the hands and falls
	if piloting:
		piloting.detonate()


func add_shake(amount: float) -> void:
	shake = maxf(shake, amount)


## Pulls the pin and lobs a grenade where he looks: the arm animation
## (Weapon.start_throw) lets go of it in release_grenade().
func throw_grenade() -> void:
	if grenades <= 0 or dead or piloting or not Settings.carries("grenade"):
		return
	if weapon.start_throw():
		grenades -= 1


func release_grenade() -> void:
	var b := camera.global_basis
	var from := camera.global_position - b.z * 0.45 + b.x * 0.12 + b.y * 0.05
	Grenade.throw(get_tree(), from, -b.z * 14.0 + Vector3.UP * 3.0 + velocity, true, 3.1)


## Sends an FPV drone up from his position and flies it through its camera.
func launch_drone() -> void:
	if piloting:
		exit_drone()
		return
	if drones <= 0 or dead or not Settings.carries("fpv"):
		return
	drones -= 1
	_fly(FpvDrone.new())


## ВЫХОД: the FPV goes off.
func exit_drone() -> void:
	if piloting:
		piloting.exit_pressed()


func _fly(d: FpvDrone) -> void:
	d.team = 0
	d.pilot = self
	d.add_collision_exception_with(self)
	get_tree().current_scene.add_child(d)
	d.global_position = camera.global_position + Vector3.UP * 0.4 - Basis(Vector3.UP, yaw).z * 0.8
	d.rotation.y = yaw
	d._yaw = yaw
	d.velocity = Vector3.UP * 5.0 # pops up off the hand, then hangs
	piloting = d
	touch_move = Vector2.ZERO
	weapon.trigger_held = false


## The drone went off (or its battery died): back to his own eyes.
func drone_lost(d: FpvDrone) -> void:
	if piloting == d:
		piloting = null
		camera.current = true
		signal_lost = 0.7



func _respawn() -> void:
	dead = false
	hits = 0
	blood = BLOOD_FULL
	bleed_rate = 0.0
	bpm = 80.0
	consciousness = 1.0
	ear_ring = 0.0
	global_transform = _spawn
	velocity = Vector3.ZERO
	yaw = _spawn.basis.get_euler().y
	pitch = 0.0
	head.position = Vector3(0.0, EYE_HEIGHT, 0.0)
	aim.transform = head.transform
	_eye = EYE_HEIGHT
	set_crouch(false)
	sprint = false
	stamina = 1.0
	head.rotation.z = 0.0
	weapon.visible = true
	weapon.pick_up()
	painkiller = 0.0
	_restock(Settings.carries("medkit"))


func _physics_process(delta: float) -> void:
	hurt_flash = maxf(hurt_flash - delta * 1.6, 0.0)
	signal_lost = maxf(signal_lost - delta, 0.0)
	shake = maxf(shake - delta * 1.1, 0.0)
	_grenade_regen += delta
	if _grenade_regen > 20.0:
		_grenade_regen = 0.0
		grenades = mini(grenades + 1, MAX_GRENADES)
	_drone_regen += delta
	if _drone_regen > 40.0:
		_drone_regen = 0.0
		drones = mini(drones + 1, MAX_DRONES)
	painkiller = maxf(painkiller - delta, 0.0)
	medic_note_t = maxf(medic_note_t - delta, 0.0)
	if treating != "":
		treat_t += delta
		if treat_t >= TREAT_TIMES[treating]:
			_treat_done()
	if not touch_mode and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if Input.is_action_just_pressed("grenade"):
			throw_grenade()
		if Input.is_action_just_pressed("drone"):
			launch_drone()
		if Input.is_action_just_pressed("bandage"):
			start_treat("bandage")
		if Input.is_action_just_pressed("painkiller"):
			start_treat("promedol")
		if Input.is_action_just_pressed("medkit"):
			start_treat("medkit")
		if Input.is_action_just_pressed("call_medic"):
			call_medic()
		if Input.is_action_just_pressed("camera"):
			toggle_camera()
	_body_process(delta)
	if dead:
		# the legs go: he drops to the floor (faster and faster), the camera
		# rolls onto its side and lies there; back at the start after a while
		death_t += delta
		var fall := clampf(death_t / 0.9, 0.0, 1.0) * clampf(death_t / 0.9, 0.0, 1.0)
		head.position = Vector3(lerpf(0.0, -0.15, fall), lerpf(_eye, 0.25, fall), lerpf(0.0, 0.2, fall))
		head.rotation = Vector3(lerpf(pitch, 0.35, fall), 0.0, lerpf(0.0, 1.25, fall))
		aim.transform = head.transform
		velocity = Vector3(0, velocity.y - GRAVITY * delta, 0) if not is_on_floor() else Vector3.ZERO
		move_and_slide()
		if death_t >= RESPAWN_TIME:
			_respawn()
		return
	var input := touch_move
	var run_key := false
	if not touch_mode:
		input += Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		if Input.is_action_just_pressed("jump"):
			jump_queued = true
		if Input.is_action_just_pressed("crouch"):
			set_crouch(not crouching)
		run_key = Input.is_action_pressed("sprint")
	input = input.limit_length(1.0)
	if piloting:
		input = Vector2.ZERO # the sticks fly the drone
		jump_queued = false
	if jump_queued and crouching:
		jump_queued = false # jump gets him up first
		set_crouch(false)
	_update_sprint(delta, input, run_key)
	_update_crouch(delta)

	rotation.y = yaw
	var wish := (Basis(Vector3.UP, yaw) * Vector3(input.x, 0.0, input.y))
	var speed := lerpf(SPEED, AIM_SPEED, weapon.aim_t)
	if sprinting:
		speed = SPRINT_SPEED
	elif crouching:
		speed = minf(speed, CROUCH_SPEED)
	var accel := 14.0 if is_on_floor() else 3.0
	velocity.x = move_toward(velocity.x, wish.x * speed, accel * speed * delta)
	velocity.z = move_toward(velocity.z, wish.z * speed, accel * speed * delta)

	if is_on_floor():
		if jump_queued:
			velocity.y = JUMP_VELOCITY
	else:
		velocity.y -= GRAVITY * delta
	jump_queued = false

	var fall_speed := velocity.y
	move_and_slide()
	if is_on_floor() and not _was_on_floor and fall_speed < -3.0:
		var f := clampf(-fall_speed / 8.0, 0.0, 1.5)
		_jolt(Vector3(0.0, -0.06 * f, 0.0), Vector3(-0.06 * f, 0.0, randf_range(-0.03, 0.03) * f))
	_was_on_floor = is_on_floor()
	_push_bodies(wish * speed)
	_kick_loose_bodies()
	_footsteps(delta)

	# the bodycam's wide lens; the GoPro's wider still
	var fov := Settings.fov + (30.0 if gopro() else (14.0 if Settings.bodycam else 0.0))
	var aim_s := smoothstep(0.0, 1.0, weapon.aim_t)
	camera.fov = lerpf(fov, fov * weapon.current.def.ads_fov, aim_s)
	camera.position = GOPRO_AT * (1.0 - aim_s) if gopro() else Vector3.ZERO
	weapon.position = (GOPRO_AT + GOPRO_GUN) * (1.0 - aim_s) if gopro() else Vector3.ZERO
	_helmet.visible = gopro() and not weapon.scoped()
	# camera recoil recovers over time; it never changes where you aim permanently
	_recoil = _recoil.lerp(Vector2.ZERO, clampf(delta * 9.0, 0.0, 1.0))
	var sh := shake * shake * 0.07
	head.rotation = Vector3(pitch + _recoil.x + randf_range(-sh, sh), _recoil.y + randf_range(-sh, sh), randf_range(-sh, sh) * 0.5)
	var base_rot := head.rotation
	_bodycam_motion(delta, Vector2(velocity.x, velocity.z).length())
	# the gun follows the camera's sway only in part (more once aimed)
	var follow := lerpf(AIM_FOLLOW.x, AIM_FOLLOW.z if weapon.current.def.has("scope") else AIM_FOLLOW.y, aim_s)
	var base_pos := Vector3(0.0, _eye, 0.0)
	aim.position = base_pos + (head.position - base_pos) * follow
	aim.rotation = base_rot + (head.rotation - base_rot) * follow + _hand_sway(delta, aim_s)

	if global_position.y < -30.0:
		global_transform = _spawn
		velocity = Vector3.ZERO
		yaw = _spawn.basis.get_euler().y


## Bleeding, heart rate, consciousness, the ringing in the ears.
func _body_process(delta: float) -> void:
	if not dead:
		blood -= bleed_rate * delta
		bleed_rate *= exp(-delta / 30.0) # clotting
		if blood <= BLOOD_DEATH and not immortal:
			blood = BLOOD_DEATH
			die()
	consciousness = 0.0 if dead else clampf((blood - BLOOD_DEATH) / (4300.0 - BLOOD_DEATH), 0.0, 1.0) * (1.0 - ear_ring * 0.25)
	if painkiller > 0.0 and not dead: # promedol keeps him on his feet a while longer
		consciousness = minf(consciousness + 0.3, 1.0)
	_stress = maxf(_stress - delta * 0.06, 0.0)
	var target := 72.0 + Vector2(velocity.x, velocity.z).length() * 5.0 + _stress * 38.0 + hits * 8.0 \
			+ (BLOOD_FULL - blood) / 35.0 - (14.0 if painkiller > 0.0 else 0.0)
	if dead:
		target = maxf(0.0, 40.0 - death_t * 25.0) # the heart stops
	bpm = move_toward(bpm, target, delta * (14.0 if target > bpm else 4.0))
	if bpm > 1.0:
		heart_phase += delta * bpm / 60.0
		if heart_phase >= 1.0:
			heart_phase = fmod(heart_phase, 1.0)
			# you hear your own heart once it pounds or you are badly hurt
			var loud := clampf((bpm - 105.0) / 50.0, 0.0, 1.0) + (1.0 - consciousness) * 0.8 + (0.6 if dead else 0.0)
			if loud > 0.05:
				_heart_player.volume_db = linear_to_db(clampf(loud, 0.0, 1.0)) - 4.0
				_heart_player.play()
	ear_ring = move_toward(ear_ring, 0.0, delta * (0.05 if dead else 0.09))
	var ring_v := ear_ring * (1.0 if not dead else clampf(1.0 - death_t / RESPAWN_TIME, 0.0, 1.0))
	_ring_player.volume_db = linear_to_db(maxf(ring_v * 0.6, 0.0001))
	if ring_v > 0.01 and not _ring_player.playing:
		_ring_player.play()
	elif ring_v <= 0.01 and _ring_player.playing:
		_ring_player.stop()
	# the world goes dull and far away
	var dull := maxf(ear_ring, 1.0 - consciousness)
	_muffle.cutoff_hz = lerpf(20000.0, 450.0, clampf(dull, 0.0, 1.0) ** 0.7)


## The gun's own wander in the hands, on top of the camera's: it bobs with
## the steps (out of step with the chest), rises and falls with the breath,
## and trails quick turns; much less once aimed.
func _hand_sway(delta: float, aim_s: float) -> Vector3:
	var hspeed := Vector2(velocity.x, velocity.z).length()
	var gait := clampf(hspeed / SPEED, 0.0, 1.5) * (0.6 if crouching else 1.0)
	var ph := _step_phase * PI
	var t := _cam_t
	var calm := 1.0 - aim_s * 0.75
	var bob := Vector3(sin(ph * 2.0 + 0.8) * 0.03, sin(ph + 1.1) * 0.05, 0.0) * gait
	var breath := Vector3(sin(t * 1.1) * 0.01 + sin(t * 0.43) * 0.007, sin(t * 0.67 + 2.0) * 0.011, 0.0) \
			* (1.0 + clampf((bpm - 75.0) / 40.0, 0.0, 2.0)) * (1.0 + _stress)
	# turning: the hands trail the turn and swing past
	var dt := maxf(delta, 0.001)
	var target := Vector2(clampf(-(pitch - _hand_prev.x) / dt * 0.04, -0.1, 0.1),
			clampf(-wrapf(yaw - _hand_prev.y, -PI, PI) / dt * 0.05, -0.14, 0.14))
	_hand_prev = Vector2(pitch, yaw)
	_hand_lag_v += ((target - _hand_lag) * 60.0 - _hand_lag_v * 9.0) * delta
	_hand_lag += _hand_lag_v * delta
	return (bob + breath + Vector3(_hand_lag.x, _hand_lag.y, 0.0)) * calm


## Where the aiming dot is on screen: the point the gun points at, 50 m out.
func aim_screen() -> Vector2:
	var at := aim.global_position - aim.global_basis.z * 50.0
	if camera.is_position_behind(at):
		return get_viewport().get_visible_rect().size * 0.5
	return camera.unproject_position(at)


func add_stress(amount: float) -> void:
	_stress = clampf(_stress + amount, 0.0, 1.0)


## Bodycam: the camera rides on the chest, not in the eyes. It trails quick
## turns and swings past, dips and rolls with every footfall (harder at a
## run), sways from foot to foot, breathes and drifts standing (heavier with
## a racing heart), and jolts on landing, on every shot and every hit. With
## the "Бодикам" setting off the motion is much gentler.
func _bodycam_motion(delta: float, hspeed: float) -> void:
	var k := (0.6 if gopro() else 1.0) if Settings.bodycam or gopro() else 0.35
	var aim := weapon.aim_t
	var dt := maxf(delta, 0.001)
	var turn_rate := wrapf(yaw - _last_yaw, -PI, PI) / dt
	var pitch_rate := (pitch - _last_pitch) / dt
	_last_yaw = yaw
	_last_pitch = pitch
	var lag_target := Vector2(clampf(-pitch_rate * 0.03, -0.1, 0.1), clampf(-turn_rate * 0.035, -0.14, 0.14)) * k
	_lag_v += ((lag_target - _lag) * 80.0 - _lag_v * 10.0) * delta
	_lag += _lag_v * delta
	# footfalls: each foot coming down knocks the camera
	var gait := clampf(hspeed / SPEED, 0.0, 1.4) * (1.0 - aim * 0.6) * (0.6 if crouching else 1.0)
	if is_on_floor() and hspeed > 0.3:
		var stride := 0.95 if hspeed > SPEED * 0.85 else 0.75
		var prev := _step_phase
		_step_phase += hspeed * delta / stride
		if floorf(_step_phase) != floorf(prev):
			var foot := 1.0 if int(floorf(_step_phase)) % 2 == 0 else -1.0
			var hard := clampf(hspeed / SPEED, 0.4, 1.4) * (1.0 - aim * 0.6)
			_jolt(Vector3(foot * 0.004, -0.02, 0.0) * hard, Vector3(-0.022, foot * 0.012, foot * 0.026) * hard)
	var ph := _step_phase * PI
	var sway := Vector3(sin(ph) * 0.028, -absf(sin(ph)) * 0.026, 0.0) * gait
	var sway_rot := Vector3(sin(ph * 2.0) * 0.009, sin(ph) * 0.014, sin(ph) * 0.032) * gait
	# standing still: breathing and the drift of a body that never is still
	_cam_t += delta
	var t := _cam_t
	var breathe := Vector3(sin(t * 1.4) * 0.004 + sin(t * 0.37) * 0.005, sin(t * 0.53 + 1.0) * 0.006 + sin(t * 0.21) * 0.004,
			sin(t * 0.71) * 0.005) * (1.0 + clampf((bpm - 75.0) / 45.0, 0.0, 2.0))
	_jp_v += (-_jp * 160.0 - _jp_v * 12.0) * delta
	_jp += _jp_v * delta
	_jr_v += (-_jr * 140.0 - _jr_v * 10.0) * delta
	_jr += _jr_v * delta
	head.position = Vector3(0.0, _eye, 0.0) + (sway + _jp) * k
	head.rotation += (sway_rot + breathe * (1.0 - aim * 0.4) + _jr) * k + Vector3(_lag.x, _lag.y, -_lag.y * 0.5)
	scope_shift = Vector2(-_lag.y - (sway_rot.y + _jr.y) * k, _lag.x + (sway_rot.x + _jr.x) * k) * 1.4


## A knock to the chest camera: `pos` metres, `rot` radians (peak).
func _jolt(pos: Vector3, rot: Vector3) -> void:
	_jp_v += pos * 20.0
	_jr_v += rot * 20.0


## Every shot shoves the camera on the chest.
func cam_kick(strength: float) -> void:
	_jolt(Vector3(0.0, 0.0, 0.01) * strength, Vector3(0.02, randf_range(-0.008, 0.008), randf_range(-0.02, 0.02)) * strength)


func _push_bodies(wish_vel: Vector3) -> void:
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		var body := c.get_collider() as RigidBody3D
		if body == null:
			continue
		var push := -c.get_normal()
		push.y = 0.0
		if push.length() < 0.1:
			continue
		push = push.normalized()
		var target := maxf(wish_vel.dot(push), 0.0)
		var current := body.linear_velocity.dot(push)
		var need := target - current
		if need > 0.0:
			body.apply_impulse(push * need * minf(body.mass, 20.0) * 0.35, c.get_position() - body.global_position)


func _kick_loose_bodies() -> void:
	var hv := Vector3(velocity.x, 0.0, velocity.z)
	var speed := hv.length()
	if speed < 0.5:
		return
	for b in _feet.get_overlapping_bodies():
		var rb := b as RigidBody3D
		if rb != null and rb.has_meta("settled"): # walked into a body at rest: it moves again
			if rb.has_meta("npc") and is_instance_valid(rb.get_meta("npc")):
				rb.get_meta("npc").wake_ragdoll()
			else:
				rb.freeze = false
				rb.remove_meta("settled")
		if rb == null or rb.freeze:
			continue
		var away := rb.global_position - global_position
		away.y = 0.0
		var push := (hv / speed * 0.7 + away.normalized() * 0.3) * speed * minf(rb.mass, 6.0) * 0.05
		rb.apply_central_impulse(push + Vector3.UP * 0.02 * minf(rb.mass, 6.0))


## Running: only forward-ish, not aiming, not crouched, while there is
## breath left. Firing or aiming stops it.
func _update_sprint(delta: float, input: Vector2, run_key: bool) -> void:
	_sprint_block = maxf(_sprint_block - delta, 0.0)
	var want := (sprint or sprint_stick or run_key) and input.y < -0.5 and not piloting and _sprint_block <= 0.0 \
			and weapon.aim_t < 0.1 and not weapon.throwing() and stamina > 0.05
	if want and crouching:
		set_crouch(false)
	sprinting = want and not crouching and is_on_floor()
	if sprinting:
		stamina = maxf(stamina - delta / 9.0, 0.0)
		add_stress(delta * 0.05)
		if stamina <= 0.05:
			sprint = false
	else:
		stamina = minf(stamina + delta / 6.0, 1.0)
	if input.length() < 0.2:
		sprint = false


## Shooting stops the run for a moment (the gun comes up first).
func block_sprint(sec: float) -> void:
	_sprint_block = maxf(_sprint_block, sec)
	sprinting = false


func set_crouch(on: bool) -> void:
	if on == crouching:
		return
	if not on:
		# room to stand up?
		var from := global_position + Vector3.UP * (CROUCH_HEIGHT - 0.05)
		var q := PhysicsRayQueryParameters3D.create(from, global_position + Vector3.UP * (STAND_HEIGHT + 0.05), 1 | 2)
		q.exclude = [get_rid()]
		if not get_world_3d().direct_space_state.intersect_ray(q).is_empty():
			return
	crouching = on
	if on:
		sprint = false
	var h := CROUCH_HEIGHT if on else STAND_HEIGHT
	_shape.height = h
	_shape_node.position.y = h / 2.0


## Eyes go down / up smoothly.
func _update_crouch(delta: float) -> void:
	_eye = move_toward(_eye, CROUCH_EYE if crouching else EYE_HEIGHT, delta * 3.5)


func eye_height() -> float:
	return _eye


func _footsteps(delta: float) -> void:
	if not is_on_floor():
		return
	var hspeed := Vector2(velocity.x, velocity.z).length()
	_step_dist += hspeed * delta
	if _step_dist > (2.6 if sprinting else 2.1):
		_step_dist = 0.0
		Sfx.play("footstep", -15.0 if crouching else (-7.0 if sprinting else -10.0), 0.12)
