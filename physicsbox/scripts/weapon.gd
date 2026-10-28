class_name Weapon
extends Node3D
## First-person M1911: firing, hit processing, recoil/slide/reload animation,
## muzzle flash and ejected shell casings.

signal fired
signal hit_confirmed(kind: int) # 0 hit, 1 kill, 2 headshot
signal ammo_changed(ammo: int, mag_size: int)

const MAG_SIZE := 7
const MODEL_SCALE := 0.0626 # model is ~3.45 units long, a real M1911 is 0.216 m
const HIP_POS := Vector3(0.15, -0.165, -0.36)
const HIP_ROT := Vector3(0.0, deg_to_rad(4.0), 0.0)
const ADS_POS := Vector3(0.0, -0.0645, -0.25)
const MUZZLE := Vector3(0.0, 0.0302, -0.146)
const EJECT_PORT := Vector3(0.012, 0.05, -0.03)
const SLIDE_PARTS := ["Plane_007", "Plane_010", "Plane_012", "Cylinder_001", "Plane_011"]
const SLIDE_TRAVEL := 0.75 # model units
const RAY_MASK := 1 | 2 | 4
const RELOAD_TIME := 1.4
const DAMAGE := {"head": 100.0, "chest": 40.0, "pelvis": 34.0, "uarm_l": 22.0, "uarm_r": 22.0,
		"farm_l": 18.0, "farm_r": 18.0, "thigh_l": 28.0, "thigh_r": 28.0, "shin_l": 20.0, "shin_r": 20.0}
const MAX_SHELLS := 24

var player: Player
var ammo := MAG_SIZE + 1
var aiming := false
var aim_t := 0.0
var reloading := false

var _sway_root := Node3D.new()
var _gun_root := Node3D.new()
var _model: Node3D
var _slide_nodes: Array[Node3D] = []
var _slide_rest: Array[Vector3] = []
var _flash_root := Node3D.new()
var _flash_light := OmniLight3D.new()
var _flash_time := 0.0
var _cooldown := 0.0
var _recoil := 0.0
var _recoil_vel := 0.0
var _slide := 0.0
var _slide_locked := false
var _reload_t := 0.0
var _sway := Vector2.ZERO
var _bob_phase := 0.0
var _wall_push := 0.0
var _auto_reload := -1.0
var _shells: Array[RigidBody3D] = []
var _shell_mesh: CylinderMesh
var _shell_shape: CylinderShape3D
var _shell_mat: StandardMaterial3D


func _ready() -> void:
	add_child(_sway_root)
	_sway_root.add_child(_gun_root)
	_gun_root.position = HIP_POS
	_gun_root.rotation = HIP_ROT

	_model = load("res://assets/m1911/m1911.fbx").instantiate()
	_model.scale = Vector3.ONE * MODEL_SCALE
	_model.rotation = Vector3(0, PI, 0)
	_gun_root.add_child(_model)
	var gun_mat := StandardMaterial3D.new()
	gun_mat.albedo_texture = load("res://assets/m1911/m1911_albedo.jpg")
	gun_mat.metallic = 0.3
	gun_mat.roughness = 0.5
	for n in _model.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		mi.material_override = gun_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if mi.name in SLIDE_PARTS:
			_slide_nodes.append(mi)
			_slide_rest.append(mi.position)

	_build_hand()
	_build_flash()

	_shell_mesh = CylinderMesh.new()
	_shell_mesh.top_radius = 0.0065
	_shell_mesh.bottom_radius = 0.0065
	_shell_mesh.height = 0.024
	_shell_mesh.radial_segments = 8
	_shell_mesh.rings = 1
	_shell_mat = StandardMaterial3D.new()
	_shell_mat.albedo_color = Color(0.86, 0.64, 0.26)
	_shell_mat.metallic = 1.0
	_shell_mat.roughness = 0.3
	_shell_mesh.material = _shell_mat
	_shell_shape = CylinderShape3D.new()
	_shell_shape.radius = 0.0065
	_shell_shape.height = 0.024
	ammo_changed.emit.call_deferred(ammo, MAG_SIZE)


func _build_hand() -> void:
	var glove := StandardMaterial3D.new()
	glove.albedo_color = Color(0.035, 0.035, 0.04)
	glove.roughness = 0.85
	var sleeve := StandardMaterial3D.new()
	sleeve.albedo_color = Color(0.05, 0.05, 0.055)
	sleeve.roughness = 0.95

	# fist wrapped around the grip
	var fist := MeshInstance3D.new()
	var fm := CapsuleMesh.new()
	fm.radius = 0.024
	fm.height = 0.085
	fist.mesh = fm
	fist.material_override = glove
	fist.position = Vector3(0.0, -0.038, 0.04)
	fist.rotation = Vector3(deg_to_rad(-18), 0, 0)
	fist.scale = Vector3(1.05, 1.0, 1.35)
	_gun_root.add_child(fist)
	# thumb along the frame
	var thumb := MeshInstance3D.new()
	var tm := CapsuleMesh.new()
	tm.radius = 0.009
	tm.height = 0.05
	thumb.mesh = tm
	thumb.material_override = glove
	thumb.position = Vector3(-0.016, -0.008, 0.012)
	thumb.rotation = Vector3(deg_to_rad(-80), 0, 0)
	_gun_root.add_child(thumb)
	# forearm: from the wrist back towards the lower right of the screen
	var wrist := Vector3(0.0, -0.06, 0.07)
	var elbow := Vector3(0.12, -0.25, 0.5)
	var arm := MeshInstance3D.new()
	var am := CapsuleMesh.new()
	am.radius = 0.042
	am.height = wrist.distance_to(elbow) + 0.08
	arm.mesh = am
	arm.material_override = sleeve
	var axis := (elbow - wrist).normalized()
	var side := axis.cross(Vector3.FORWARD).normalized()
	arm.basis = Basis(side, axis, side.cross(axis)).orthonormalized()
	arm.position = (wrist + elbow) * 0.5
	_gun_root.add_child(arm)
	for m in [fist, thumb, arm]:
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _build_flash() -> void:
	_flash_root.position = MUZZLE
	_gun_root.add_child(_flash_root)
	var front_mat := _additive_mat("res://assets/textures/muzzle_flash.png")
	var side_mat := _additive_mat("res://assets/textures/muzzle_flash_side.png")
	var front := MeshInstance3D.new()
	var fq := QuadMesh.new()
	fq.size = Vector2(0.13, 0.13)
	front.mesh = fq
	front.material_override = front_mat
	front.name = "Front"
	_flash_root.add_child(front)
	for i in 2:
		var side := MeshInstance3D.new()
		var sq := QuadMesh.new()
		sq.size = Vector2(0.2, 0.07)
		side.mesh = sq
		side.material_override = side_mat
		side.rotation = Vector3(PI / 2 * i, PI / 2, 0)
		side.position = Vector3(0, 0, -0.1)
		_flash_root.add_child(side)
	for c in _flash_root.get_children():
		(c as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_flash_root.visible = false
	_flash_light.light_color = Color(1.0, 0.72, 0.38)
	_flash_light.light_energy = 3.0
	_flash_light.omni_range = 4.5
	_flash_light.position = MUZZLE + Vector3(0, 0, -0.08)
	_flash_light.visible = false
	_gun_root.add_child(_flash_light)


func _additive_mat(path: String) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_texture = load(path)
	m.albedo_color = Color(1.4, 1.1, 0.8)
	return m


# ------------------------------------------------------------------ actions

## Trigger pull (semi-automatic: one shot per press).
func trigger() -> void:
	if reloading or _cooldown > 0.0:
		return
	if ammo <= 0:
		Sfx.play("dry_fire")
		_cooldown = 0.25
		_auto_reload = 0.3
		return
	ammo -= 1
	_cooldown = 0.11
	_slide_locked = ammo == 0
	_slide = 1.0
	_recoil_vel += 26.0
	_flash_time = 0.05
	_flash_root.visible = true
	_flash_light.visible = true
	_flash_root.get_node("Front").rotation.z = randf() * TAU
	_flash_root.scale = Vector3.ONE * randf_range(0.8, 1.2)
	Sfx.play("gunshot", 0.0, 0.05)
	player.add_recoil(deg_to_rad(randf_range(2.2, 3.0)), deg_to_rad(randf_range(-0.6, 0.6)))
	_eject_shell()
	_shoot()
	_alert_npcs()
	fired.emit()
	ammo_changed.emit(ammo, MAG_SIZE)


func reload() -> void:
	if reloading or ammo >= MAG_SIZE + 1:
		return
	reloading = true
	_reload_t = 0.0
	Sfx.play("reload")


func set_aiming(value: bool) -> void:
	aiming = value


func _alert_npcs() -> void:
	var pos := global_position
	for n in get_tree().get_nodes_in_group("npcs"):
		if n.global_position.distance_to(pos) < 26.0:
			n.alert(pos)


func _shoot() -> void:
	var cam := get_viewport().get_camera_3d()
	var from := cam.global_position
	var spread := deg_to_rad(lerpf(1.4, 0.0, aim_t) + player.velocity.length() * 0.25 * (1.0 - aim_t))
	var fwd := -cam.global_basis.z
	var dir := fwd.rotated(cam.global_basis.x, randf_range(-spread, spread)).rotated(cam.global_basis.y, randf_range(-spread, spread)).normalized()
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * 300.0, RAY_MASK)
	q.exclude = [player.get_rid()]
	for _i in 4:
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			return
		var collider: Object = hit.collider
		var pos: Vector3 = hit.position
		var normal: Vector3 = hit.normal
		if collider.has_meta("npc"):
			var npc = collider.get_meta("npc")
			if is_instance_valid(npc):
				var part: String = collider.get_meta("part")
				var kind: int = npc.take_hit(collider, pos, normal, dir, DAMAGE.get(part, 25.0), 11.0 if not npc.dead else 7.0)
				hit_confirmed.emit(kind)
				Sfx.play("hitmarker", -6.0 if kind == 0 else -2.0)
			return
		var surface: String = collider.get_meta("surface", "concrete")
		if surface == "glass" and collider.has_method("shatter"):
			collider.shatter(pos, dir)
			var ex: Array[RID] = q.exclude
			ex.append(collider.get_rid())
			q.exclude = ex
			q.from = pos
			continue
		_impact(collider, pos, normal, dir, surface)
		return


func _impact(collider: Object, pos: Vector3, normal: Vector3, dir: Vector3, surface: String) -> void:
	var body: Node3D = collider as Node3D
	if collider is RigidBody3D:
		var rb := collider as RigidBody3D
		rb.apply_impulse(dir * 7.0, pos - rb.global_position)
		Blood.bullet_hole(pos, normal, rb)
	else:
		Blood.bullet_hole(pos, normal, body if body is AnimatableBody3D else null)
	match surface:
		"wood":
			Sfx.play_3d("wood_hit", pos)
			Blood.dust(pos, normal, Color(0.55, 0.4, 0.25))
		"metal":
			Sfx.play_3d("metal_hit", pos)
			Blood.dust(pos, normal, Color(0.7, 0.7, 0.7))
		"soft":
			Sfx.play_3d("wood_hit", pos, -6.0)
			Blood.dust(pos, normal, Color(0.8, 0.8, 0.8))
		_:
			Sfx.play_3d("wall_hit", pos)
			Blood.dust(pos, normal)


func _eject_shell() -> void:
	var s := RigidBody3D.new()
	s.mass = 0.012
	s.collision_layer = 32
	s.collision_mask = 1 | 2
	s.continuous_cd = true
	s.contact_monitor = true
	s.max_contacts_reported = 1
	var mi := MeshInstance3D.new()
	mi.mesh = _shell_mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	s.add_child(mi)
	var cs := CollisionShape3D.new()
	cs.shape = _shell_shape
	s.add_child(cs)
	get_tree().current_scene.add_child(s)
	var cam_basis := get_viewport().get_camera_3d().global_basis
	s.global_transform = Transform3D(cam_basis * Basis(Vector3.FORWARD, PI / 2), _gun_root.to_global(EJECT_PORT))
	s.linear_velocity = player.velocity + cam_basis * Vector3(randf_range(1.6, 2.4), randf_range(1.8, 2.6), randf_range(-0.2, 0.4))
	s.angular_velocity = Vector3(randf_range(-25, 25), randf_range(-25, 25), randf_range(-25, 25))
	var state := {"played": 0}
	s.body_entered.connect(func(_b):
		if state.played < 2 and s.linear_velocity.length() > 0.6:
			state.played += 1
			Sfx.play_3d("shell", s.global_position, -4.0 - state.played * 5.0, 0.15)
	)
	_shells.append(s)
	if _shells.size() > MAX_SHELLS:
		var old: RigidBody3D = _shells.pop_front()
		if is_instance_valid(old):
			old.queue_free()


# ------------------------------------------------------------------ animation

func _process(frame_delta: float) -> void:
	# springs below go unstable with huge steps, so cap the step on slow frames
	var delta := minf(frame_delta, 1.0 / 30.0)
	_cooldown -= frame_delta
	if _auto_reload > 0.0:
		_auto_reload -= frame_delta
		if _auto_reload <= 0.0:
			reload()

	if not player.touch_mode and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if Input.is_action_just_pressed("fire"):
			trigger()
		if Input.is_action_just_pressed("reload"):
			reload()
		aiming = Input.is_action_pressed("aim")

	var aim_target := 1.0 if aiming and not reloading else 0.0
	aim_t = move_toward(aim_t, aim_target, delta * 6.0)
	var a := smoothstep(0.0, 1.0, aim_t)

	# flash
	if _flash_time > 0.0:
		_flash_time -= frame_delta
		if _flash_time <= 0.0:
			_flash_root.visible = false
			_flash_light.visible = false

	# recoil spring
	_recoil_vel += (-_recoil * 260.0 - _recoil_vel * 22.0) * delta
	_recoil = clampf(_recoil + _recoil_vel * delta, -0.6, 1.6)

	# slide: snaps back instantly, returns quickly (unless locked open on empty)
	if not _slide_locked:
		_slide = move_toward(_slide, 0.0, delta * 14.0)
	for i in _slide_nodes.size():
		_slide_nodes[i].position = _slide_rest[i] + Vector3(0, 0, -SLIDE_TRAVEL * _slide)

	# reload
	var reload_pose := 0.0
	if reloading:
		_reload_t += frame_delta
		reload_pose = sin(clampf(_reload_t / RELOAD_TIME, 0.0, 1.0) * PI)
		if _reload_t >= RELOAD_TIME * 0.85 and _slide_locked:
			_slide_locked = false
		if _reload_t >= RELOAD_TIME:
			reloading = false
			ammo = MAG_SIZE + (1 if ammo > 0 else 0)
			ammo_changed.emit(ammo, MAG_SIZE)

	# sway from looking + bob from walking
	var look := player.consume_look_delta()
	_sway = _sway.lerp(Vector2(clampf(-look.x * 0.0009, -0.03, 0.03), clampf(look.y * 0.0009, -0.03, 0.03)), clampf(delta * 10.0, 0.0, 1.0))
	var hspeed := Vector2(player.velocity.x, player.velocity.z).length()
	if player.is_on_floor():
		_bob_phase += delta * hspeed * 2.0
	var bob_amt := clampf(hspeed / 4.6, 0.0, 1.0) * (1.0 - a * 0.85)
	var bob := Vector3(sin(_bob_phase) * 0.012, -absf(cos(_bob_phase)) * 0.01, 0.0) * bob_amt

	# pull the gun back when standing against a wall
	var cam := get_viewport().get_camera_3d()
	var wall := 0.0
	if cam:
		var q := PhysicsRayQueryParameters3D.create(cam.global_position, cam.global_position - cam.global_basis.z * 0.75, 1 | 2)
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		if not hit.is_empty():
			wall = 0.75 - cam.global_position.distance_to(hit.position)
	_wall_push = lerpf(_wall_push, wall, clampf(delta * 12.0, 0.0, 1.0))

	var base_pos := HIP_POS.lerp(ADS_POS, a)
	var base_rot := HIP_ROT.lerp(Vector3.ZERO, a)
	var recoil_scale := lerpf(1.0, 0.55, a)
	var pos := base_pos + bob + Vector3(_sway.x, _sway.y, 0.0)
	pos += Vector3(0.0, 0.004, 0.045) * _recoil * recoil_scale
	pos += Vector3(0.0, -0.09, 0.06) * reload_pose
	pos += Vector3(0.0, -0.02, _wall_push * 0.6)
	var rot := base_rot + Vector3(0.22 * _recoil * recoil_scale, 0.0, 0.0)
	rot += Vector3(0.5, 0.25, 0.7) * reload_pose
	rot.x += _wall_push * 1.2
	_gun_root.position = pos
	_gun_root.rotation = rot
