class_name Weapon
extends Node3D
## First-person weapons: AK-74M with a red dot and the SVD sniper rifle.
## Each viewmodel (gun + gloved hands) and its animations come from Blender
## (tools/blender/build_sketchfab_kit.py); scoped rifles look through the
## scope (HUD overlay) when aimed. This script
## plays them and adds sway, bob, aiming, firing, hit processing, muzzle
## flash and ejected shells. A rifle can wear the PBS-1 suppressor (weapon
## menu, МОДИФИКАЦИИ): no flash, a quiet shot only soldiers close by hear.
## The guns can be put away (empty hands) and left out of the kit.

signal fired
signal ammo_changed(ammo: int, capacity: int)
signal weapon_changed(weapon_name: String)

const RAY_MASK := 1 | 2 | 4
const MAX_SHELLS := 24
const DEFS := [
	{
		"id": "ak74", "name": "АК-74М", "scene": "res://assets/weapons/ak74_fp.glb",
		"title": "АК-74М + «Кобра»", "desc": "Автомат 5,45 мм, как у солдат, с коллиматором.",
		"stats": ["Урон: 36 (голова — насмерть)", "Магазин: 30", "Темп: 650 выстр/мин"],
		"capacity": 30, "pellets": 1, "impulse": 12.0, "cooldown": 0.092, "power": 1.4, "auto": true,
		"damage": {"head": 100.0, "chest": 36.0, "pelvis": 32.0, "uarm_l": 20.0, "uarm_r": 20.0, "farm_l": 16.0,
				"farm_r": 16.0, "thigh_l": 26.0, "thigh_r": 26.0, "shin_l": 18.0, "shin_r": 18.0},
		"spread_hip": 1.8, "spread_ads": 0.12, "falloff_start": 120.0, "falloff_min": 0.7,
		"sound": "rifle", "suppressor": Vector3(0.036, 0.036, 0.2),
		"shell": "rifle", "shell_at": 0.0, "alert": 30.0, "flash": 1.1, "cam_recoil": 1.35,
		"yaw": 3.0, "ads_dist": 0.4, "ads_fov": 0.7, "fire_last": "", "reload_empty": "reload_empty",
	},
	{
		"id": "svd", "name": "СВД", "scene": "res://assets/weapons/svd_fp.glb", "scope": "pso",
		"title": "СВД + ПСО-1", "desc": "Снайперская винтовка 7,62×54R, полуавтомат.",
		"stats": ["Урон: 90 (пробивает тела)", "Магазин: 10", "Прицел ПСО-1 ×4"],
		"capacity": 10, "pellets": 1, "impulse": 26.0, "cooldown": 0.32, "power": 3.0, "auto": false,
		"damage": {"head": 100.0, "chest": 90.0, "pelvis": 80.0, "uarm_l": 50.0, "uarm_r": 50.0, "farm_l": 45.0,
				"farm_r": 45.0, "thigh_l": 65.0, "thigh_r": 65.0, "shin_l": 50.0, "shin_r": 50.0},
		"spread_hip": 2.6, "spread_ads": 0.03, "falloff_start": 400.0, "falloff_min": 0.85,
		"sound": "sniper", "suppressor": Vector3(0.042, 0.042, 0.25),
		"shell": "rifle", "shell_at": 0.0, "alert": 60.0, "flash": 1.4, "cam_recoil": 4.5,
		"yaw": 2.5, "ads_dist": 0.1, "ads_fov": 0.22, "fire_last": "", "reload_empty": "",
	},
]
## Bullet power lost going through each body part (power 1 = pistol round).
const FLESH_COST := {"head": 0.9, "chest": 0.8, "pelvis": 0.8, "uarm_l": 0.45, "uarm_r": 0.45,
		"farm_l": 0.35, "farm_r": 0.35, "thigh_l": 0.55, "thigh_r": 0.55, "shin_l": 0.45, "shin_r": 0.45}
## Close shotgun blasts that put this many pellets into the torso spill the
## organs; into a limb, tear it off.
const GORE_PELLETS := 3
const GUTS_RANGE := 4.0
const SEVER_RANGE := 3.5
## The PBS-1 (Blender, tools/blender/build_suppressor.py): 1 m long along -Z,
## scaled per rifle by DEFS "suppressor" (diameter, diameter, length).
const SUPPRESSOR_SCENE := "res://assets/weapons/suppressor.glb"
const SUPPRESSOR_MODEL_D := 0.266 # its diameter at 1 m length
## How far soldiers hear a suppressed shot, as a share of the open one.
const SUPPRESSED_ALERT := 0.22


class Slot:
	var def: Dictionary
	var root: Node3D
	var anim: AnimationPlayer
	var skel: Skeleton3D
	var muzzle := -1
	var eject := -1
	var ammo := 0
	var ads := Transform3D.IDENTITY
	var suppressor: Node3D


## The grenade throw (grenade_fp.glb, "throw"): the hand lets go at this time.
const THROW_SCENE := "res://assets/weapons/grenade_fp.glb"
const THROW_RELEASE := 25.0 / 30.0

var player: Player
var trigger_held := false # touch fire button held (automatic fire)
var aiming := false
var aim_t := 0.0
var reloading := false
var holstered := false # the gun is put away: empty hands
var slots: Array[Slot] = []
var current: Slot
var ammo: int:
	get:
		return current.ammo if current else 0

var _sway_root := Node3D.new()
var _holder := Node3D.new()
var _flash_root := Node3D.new()
var _flash_light := OmniLight3D.new()
var _flash_time := 0.0
var _cooldown := 0.0
var _reload_left := 0.0
var _events: Array = [] # [time_left, callable]
var _sway := Vector2.ZERO
var _bob_phase := 0.0
var _wall_push := 0.0
var _auto_reload := -1.0
var _shells: Array[RigidBody3D] = []
var _shell_meshes := {}
var _shell_shapes := {}
var _throw_root: Node3D
var _throw_anim: AnimationPlayer
var _throw_t := -1.0
var _released := false
var _lower := 0.0 # gun lowered out of view while the other hand throws
var _sprint_t := 0.0 # gun swung across the chest while running


func _ready() -> void:
	add_child(_sway_root)
	_sway_root.add_child(_holder)
	for def in DEFS:
		var s := Slot.new()
		s.def = def
		s.root = load(def.scene).instantiate()
		_holder.add_child(s.root)
		s.anim = s.root.find_children("*", "AnimationPlayer", true, false)[0]
		s.skel = s.root.find_children("*", "Skeleton3D", true, false)[0]
		s.muzzle = s.skel.find_bone("muzzle")
		s.eject = s.skel.find_bone("eject")
		var sight := s.root.to_local(s.skel.to_global(s.skel.get_bone_global_rest(s.skel.find_bone("sight")).origin))
		s.ads = Transform3D(Basis.IDENTITY, Vector3(0, 0, -def.ads_dist)) \
				* Transform3D(Basis(Vector3.UP, -deg_to_rad(def.yaw)), Vector3.ZERO) \
				* Transform3D(Basis.IDENTITY, -sight)
		s.ammo = def.capacity
		for mi in s.root.find_children("*", "MeshInstance3D", true, false):
			(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		s.root.visible = false
		s.anim.play("idle")
		_fit_suppressor(s)
		slots.append(s)
	_build_flash()
	_build_shells()
	_throw_root = load(THROW_SCENE).instantiate()
	add_child(_throw_root)
	_throw_anim = _throw_root.find_children("*", "AnimationPlayer", true, false)[0]
	for mi in _throw_root.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_throw_root.visible = false
	var first := _first_carried()
	if first < 0: # no gun in the kit: empty hands
		current = slots[0]
		holstered = true
	else:
		select(first, false)
	apply_mods()


## The PBS-1 screwed onto the muzzle bone, along the bore (the viewmodel is
## built turned by `yaw`), hidden until the rifle wears it.
func _fit_suppressor(s: Slot) -> void:
	var size: Vector3 = s.def.suppressor
	var mount := BoneAttachment3D.new()
	mount.bone_name = "muzzle"
	s.skel.add_child(mount)
	var to_skel := s.root.global_transform.affine_inverse() * s.skel.global_transform
	var bone := to_skel * s.skel.get_bone_global_rest(s.muzzle)
	var bore := Basis(Vector3.UP, deg_to_rad(s.def.yaw))
	var want := Transform3D(bore.scaled(Vector3(size.x, size.y, size.z) / Vector3(SUPPRESSOR_MODEL_D, SUPPRESSOR_MODEL_D, 1.0)),
			bone.origin + bore * Vector3(0, 0, 0.015)) # a little over the muzzle brake it replaces
	var can: Node3D = load(SUPPRESSOR_SCENE).instantiate()
	mount.add_child(can)
	can.transform = bone.affine_inverse() * want
	for mi in can.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	s.suppressor = mount


## Applies the weapon menu's choices: suppressors on or off, guns left out
## of the kit (the one in hands goes back if it was left out).
func apply_mods() -> void:
	for s in slots:
		s.suppressor.visible = suppressed(s)
	if not carried(slots.find(current)) and not holstered:
		var other := _first_carried()
		if other >= 0:
			select(other)
		else:
			holster()


func suppressed(s: Slot = null) -> bool:
	return Settings.suppressed.get((s if s else current).def.id, false)


func carried(index: int) -> bool:
	return Settings.carries(slots[index].def.id)


func _first_carried() -> int:
	for i in slots.size():
		if carried(i):
			return i
	return -1


func _build_flash() -> void:
	add_child(_flash_root)
	var front := MeshInstance3D.new()
	var fq := QuadMesh.new()
	fq.size = Vector2(0.13, 0.13)
	front.mesh = fq
	front.material_override = _additive_mat("res://assets/textures/muzzle_flash.png")
	front.name = "Front"
	_flash_root.add_child(front)
	var side_mat := _additive_mat("res://assets/textures/muzzle_flash_side.png")
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
	_flash_light.visible = false
	add_child(_flash_light)


func _additive_mat(path: String) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_texture = load(path)
	m.albedo_color = Color(1.4, 1.1, 0.8)
	return m


func _build_shells() -> void:
	var brass := StandardMaterial3D.new()
	brass.albedo_color = Color(0.86, 0.64, 0.26)
	brass.metallic = 1.0
	brass.roughness = 0.3
	var hull := StandardMaterial3D.new()
	hull.albedo_color = Color(0.62, 0.06, 0.05)
	hull.roughness = 0.45
	var steel := StandardMaterial3D.new() # lacquered steel 5.45 cases
	steel.albedo_color = Color(0.42, 0.36, 0.2)
	steel.metallic = 0.7
	steel.roughness = 0.4
	for kind in ["rifle", "shotgun"]:
		var r := 0.005 if kind == "rifle" else 0.0105
		var h := 0.039 if kind == "rifle" else 0.068
		var m := CylinderMesh.new()
		m.top_radius = r
		m.bottom_radius = r
		m.height = h
		m.radial_segments = 8
		m.rings = 1
		m.material = steel if kind == "rifle" else hull
		_shell_meshes[kind] = m
		var sh := CylinderShape3D.new()
		sh.radius = r
		sh.height = h
		_shell_shapes[kind] = sh


# ------------------------------------------------------------------ switching

func select(index: int, animate := true) -> void:
	var s := slots[index]
	if not carried(index):
		return
	if s == current and not holstered:
		return
	if current:
		current.root.visible = false
	holstered = false
	current = s
	s.root.visible = true
	reloading = false
	_events.clear()
	_auto_reload = -1.0
	if animate:
		s.anim.play("draw")
		s.anim.queue("idle")
		_cooldown = s.anim.get_animation("draw").length * 0.8
		Sfx.play("ui_click", -6.0)
	else:
		s.anim.play("idle")
	weapon_changed.emit(s.def.name)
	ammo_changed.emit(s.ammo, s.def.capacity)


## Puts the gun away (back on its sling): empty hands. Picking a gun on the
## hotbar (or the same one again) takes it back out.
func holster() -> void:
	if holstered:
		return
	holstered = true
	aiming = false
	reloading = false
	trigger_held = false
	_events.clear()
	Sfx.play("ui_click", -8.0)
	weapon_changed.emit("")


## Hotbar / keys on a gun: out if it is away, away if it is already in hands.
func toggle(index: int) -> void:
	if slots[index] == current and not holstered:
		holster()
	else:
		select(index)


## Starts the grenade throw: the gun drops out of view, the right hand comes
## up with the grenade, the left pulls the ring, the arm swings over and
## lets go (player.release_grenade). False when busy.
func start_throw() -> bool:
	if _throw_t >= 0.0 or player.dead:
		return false
	_throw_t = 0.0
	_released = false
	reloading = false
	_events.clear()
	current.anim.play("idle")
	_throw_root.visible = true
	_throw_anim.stop()
	_throw_anim.play("throw")
	current.root.visible = not holstered
	return true


## Looking through a scope: the HUD draws it and the viewmodel is hidden.
func scoped() -> bool:
	return current.def.has("scope") and aim_t > 0.85 and _throw_t < 0.0 and not holstered


func throwing() -> bool:
	return _throw_t >= 0.0


func next_weapon() -> void:
	var i := slots.find(current)
	for k in slots.size():
		i = (i + 1) % slots.size()
		if carried(i):
			select(i)
			return


func weapon_name() -> String:
	return current.def.name


# ------------------------------------------------------------------ actions

## Trigger pull (one shot per press; the shotgun also needs its pump cycle).
func trigger() -> void:
	if player.piloting:
		player.piloting.trigger_pressed()
		return
	if holstered:
		return
	if player.sprinting or _sprint_t > 0.3:
		player.block_sprint(0.7) # the gun comes up from the run first
		return
	if reloading or _cooldown > 0.0 or player.dead or _throw_t >= 0.0:
		return
	var d := current.def
	if current.ammo <= 0:
		Sfx.play("dry_fire")
		_cooldown = 0.25
		_auto_reload = 0.3
		return
	current.ammo -= 1
	_cooldown = d.cooldown
	var anim_name: String = "fire"
	if current.ammo == 0 and d.fire_last != "":
		anim_name = d.fire_last
	current.anim.stop()
	current.anim.play(anim_name)
	if anim_name != d.fire_last:
		current.anim.queue("idle")
	var quiet := suppressed()
	if not quiet: # the suppressor swallows the flash
		_flash_time = 0.05
		_flash_root.visible = true
		_flash_light.visible = true
		_flash_light.light_energy = 3.0 * d.flash
		_flash_root.scale = Vector3.ONE * randf_range(0.8, 1.2) * d.flash
		_flash_root.get_node("Front").rotation.z = randf() * TAU
		_place_flash()
		Sfx.play(d.sound, 0.0, 0.05)
	else:
		Sfx.play(d.sound + "_sup", -3.0, 0.05)
	var kick: float = d.cam_recoil
	player.add_recoil(deg_to_rad(kick * randf_range(0.85, 1.15)), deg_to_rad(randf_range(-0.25, 0.25) * kick))
	if d.shell_at <= 0.0:
		_eject_shell()
	else:
		_events.append([d.shell_at, _eject_shell])
	_shoot()
	_alert_npcs(d.alert * (SUPPRESSED_ALERT if quiet else 1.0))
	player.add_stress(0.06)
	player.cam_kick(kick / 2.0)
	fired.emit()
	ammo_changed.emit(current.ammo, d.capacity)


func reload() -> void:
	var d := current.def
	if holstered or reloading or current.ammo >= d.capacity or _cooldown > 0.3:
		return
	reloading = true
	var anim_name := "reload"
	if current.ammo == 0 and d.reload_empty != "":
		anim_name = d.reload_empty
	current.anim.stop()
	current.anim.play(anim_name)
	current.anim.queue("idle")
	_reload_left = current.anim.get_animation(anim_name).length


func set_aiming(value: bool) -> void:
	aiming = value and not holstered


func _alert_npcs(radius: float) -> void:
	var pos := global_position
	for n in get_tree().get_nodes_in_group("npcs"):
		if n.global_position.distance_to(pos) < radius:
			n.alert(pos)


func _shoot() -> void:
	var d := current.def
	var cam := get_viewport().get_camera_3d()
	var from := cam.global_position
	var spread_deg: float = lerpf(d.spread_hip, d.spread_ads, aim_t) + player.velocity.length() * 0.25 * (1.0 - aim_t)
	var spread := deg_to_rad(spread_deg)
	var fwd := -cam.global_basis.z
	var space := get_world_3d().direct_space_state
	var part_hits := {} # npc -> {part name: [count, part, pos, normal, dist]}
	var played_impact := false
	for pellet in d.pellets:
		# uniform spread inside a cone
		var a := randf() * TAU
		var r := sqrt(randf()) * spread
		var dir := fwd.rotated(cam.global_basis.x, sin(a) * r).rotated(cam.global_basis.y, cos(a) * r).normalized()
		var q := PhysicsRayQueryParameters3D.create(from, from + dir * 300.0, RAY_MASK)
		q.exclude = [player.get_rid()]
		# the bullet keeps going through flesh, glass and doors while it has power
		var power: float = d.power
		for _i in 6:
			var hit := space.intersect_ray(q)
			if hit.is_empty():
				break
			var collider: Object = hit.collider
			var pos: Vector3 = hit.position
			var normal: Vector3 = hit.normal
			var dist := from.distance_to(pos)
			var falloff := clampf(1.0 - (dist - d.falloff_start) / 20.0, d.falloff_min, 1.0) * minf(power, 1.0)
			var cost := 99.0
			if collider.has_meta("npc"):
				var npc = collider.get_meta("npc")
				if is_instance_valid(npc):
					var part: String = collider.get_meta("part")
					var fx := 1.0 if d.pellets == 1 else 0.45
					var impulse: float = d.impulse * (1.0 if not npc.dead else 0.7) * falloff
					npc.last_hit_by_player = true
					npc.take_hit(collider, pos, normal, dir, d.damage.get(part, 10.0) * falloff, impulse, fx)
					if not part_hits.has(npc):
						part_hits[npc] = {}
					var e: Array = part_hits[npc].get(part, [0, collider, pos, normal, dist])
					e[0] += 1
					part_hits[npc][part] = e
					cost = FLESH_COST.get(part, 0.8)
			elif collider.has_meta("drone"):
				collider.take_bullet(pos, dir, 0.0)
			elif collider.get_meta("surface", "") == "glass" and collider.has_method("shatter"):
				collider.shatter(pos, dir)
				cost = 0.05
			elif collider.has_meta("penetration"):
				cost = collider.get_meta("penetration")
				_impact(collider, pos, normal, dir, collider.get_meta("surface", "wood"), not played_impact, falloff)
				played_impact = true
				if power > cost:
					_exit_hole(collider, pos, dir)
				if collider.has_method("take_bullet"):
					collider.take_bullet(pos, dir, d.damage.chest * falloff)
			else:
				_impact(collider, pos, normal, dir, collider.get_meta("surface", "concrete"), not played_impact, falloff)
				played_impact = true
			if power <= cost:
				break
			power -= cost
			var ex: Array[RID] = q.exclude
			ex.append(collider.get_rid())
			q.exclude = ex
			q.from = pos + dir * 0.01
	for npc in part_hits:
		if not is_instance_valid(npc):
			continue
		for part in part_hits[npc]:
			var e: Array = part_hits[npc][part]
			if e[0] < GORE_PELLETS:
				continue
			if part == "chest" or part == "pelvis":
				if e[4] < GUTS_RANGE and (e[4] < 2.2 or randf() < 0.6):
					npc.spill_organs(e[1], e[2], e[3], fwd)
			elif part != "head" and e[4] < SEVER_RANGE:
				npc.sever(e[1], fwd)


## Exit hole + splinters on the far side of something the bullet went through.
func _exit_hole(collider: Object, pos: Vector3, dir: Vector3) -> void:
	var body := collider as CollisionObject3D
	var q := PhysicsRayQueryParameters3D.create(pos + dir * 0.4, pos, body.collision_layer)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty() or hit.collider != collider:
		return
	Blood.bullet_hole(hit.position, hit.normal, body as Node3D)
	Blood.dust(hit.position, dir, Color(0.75, 0.6, 0.4))


func _impact(collider: Object, pos: Vector3, normal: Vector3, dir: Vector3, surface: String, sound: bool, power: float) -> void:
	var body: Node3D = collider as Node3D
	if collider is RigidBody3D:
		var rb := collider as RigidBody3D
		rb.apply_impulse(dir * current.def.impulse * 0.65 * power, pos - rb.global_position)
		Blood.bullet_hole(pos, normal, rb)
	else:
		Blood.bullet_hole(pos, normal, body if body is AnimatableBody3D else null)
	var snd := "wall_hit"
	var col := Color(0.75, 0.73, 0.7)
	match surface:
		"wood":
			snd = "wood_hit"
			col = Color(0.55, 0.4, 0.25)
		"metal":
			snd = "metal_hit"
			col = Color(0.7, 0.7, 0.7)
		"soft":
			snd = "wood_hit"
			col = Color(0.8, 0.8, 0.8)
		"dirt":
			col = Color(0.36, 0.28, 0.2)
		"flesh":
			snd = ""
			col = Color(0.5, 0.02, 0.03)
	if sound and snd != "":
		Sfx.play_3d(snd, pos, -3.0 if surface == "soft" else 0.0)
	Blood.dust(pos, normal, col)


func _bone_world(bone: int) -> Transform3D:
	return current.skel.global_transform * current.skel.get_bone_global_pose(bone)


func _place_flash() -> void:
	var cam := get_viewport().get_camera_3d()
	var muzzle := _bone_world(current.muzzle).origin
	_flash_root.global_transform = Transform3D(cam.global_basis, muzzle).scaled_local(_flash_root.scale)
	_flash_light.global_position = muzzle - cam.global_basis.z * 0.08


func _eject_shell() -> void:
	var kind: String = current.def.shell
	var s := RigidBody3D.new()
	s.mass = 0.012 if kind == "rifle" else 0.03
	s.collision_layer = 32
	s.collision_mask = 1 | 2
	s.continuous_cd = true
	var mi := MeshInstance3D.new()
	mi.mesh = _shell_meshes[kind]
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	s.add_child(mi)
	var cs := CollisionShape3D.new()
	cs.shape = _shell_shapes[kind]
	s.add_child(cs)
	get_tree().current_scene.add_child(s)
	var cam_basis := get_viewport().get_camera_3d().global_basis
	s.global_transform = Transform3D(cam_basis * Basis(Vector3.FORWARD, PI / 2), _bone_world(current.eject).origin)
	s.linear_velocity = player.velocity + cam_basis * Vector3(randf_range(1.6, 2.4), randf_range(1.8, 2.6), randf_range(-0.2, 0.4))
	s.angular_velocity = Vector3(randf_range(-25, 25), randf_range(-25, 25), randf_range(-25, 25))
	_shells.append(s)
	if _shells.size() > MAX_SHELLS:
		var old: RigidBody3D = _shells.pop_front()
		if is_instance_valid(old):
			old.queue_free()


# ------------------------------------------------------------------ per frame

func _process(frame_delta: float) -> void:
	# springs below go unstable with huge steps, so cap the step on slow frames
	var delta := minf(frame_delta, 1.0 / 30.0)
	_cooldown -= frame_delta
	if _auto_reload > 0.0:
		_auto_reload -= frame_delta
		if _auto_reload <= 0.0:
			reload()
	for i in range(_events.size() - 1, -1, -1):
		_events[i][0] -= frame_delta
		if _events[i][0] <= 0.0:
			var cb: Callable = _events[i][1]
			_events.remove_at(i)
			cb.call()
	if reloading:
		_reload_left -= frame_delta
		if _reload_left <= 0.0:
			reloading = false
			var d := current.def
			current.ammo = d.capacity
			ammo_changed.emit(current.ammo, d.capacity)

	if _throw_t >= 0.0:
		_throw_t += frame_delta
		if not _released and _throw_t >= THROW_RELEASE:
			_released = true
			player.release_grenade()
		if _throw_t >= _throw_anim.current_animation_length:
			_throw_t = -1.0
			_throw_root.visible = false
			if not holstered:
				current.anim.play("draw")
				current.anim.queue("idle")
			_cooldown = 0.3
	_lower = move_toward(_lower, 1.0 if _throw_t >= 0.0 and _throw_t < _throw_anim.current_animation_length - 0.25 else 0.0, delta * 5.0)
	var held := trigger_held
	if not player.touch_mode and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not player.dead:
		held = held or Input.is_action_pressed("fire")
		if Input.is_action_just_pressed("fire"):
			trigger()
		if Input.is_action_just_pressed("reload"):
			reload()
		if Input.is_action_just_pressed("weapon_1"):
			toggle(0)
		if Input.is_action_just_pressed("weapon_2"):
			toggle(1)
		if Input.is_action_just_pressed("weapon_next"):
			next_weapon()
		if Input.is_action_just_pressed("holster"):
			holster()
		aiming = Input.is_action_pressed("aim") and not holstered
	if held and current.def.auto and _cooldown <= 0.0 and current.ammo > 0 and not holstered:
		trigger()

	var aim_target := 1.0 if aiming and not reloading and _throw_t < 0.0 and not holstered else 0.0
	aim_t = move_toward(aim_t, aim_target, delta * 6.0)
	var a := smoothstep(0.0, 1.0, aim_t)

	if _flash_time > 0.0:
		_flash_time -= frame_delta
		_place_flash()
		if _flash_time <= 0.0:
			_flash_root.visible = false
			_flash_light.visible = false

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
		var reach := 0.75 if current.def.pellets == 1 else 1.0
		var q := PhysicsRayQueryParameters3D.create(cam.global_position, cam.global_position - cam.global_basis.z * reach, 1 | 2)
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		if not hit.is_empty():
			wall = reach - cam.global_position.distance_to(hit.position)
	_wall_push = lerpf(_wall_push, wall, clampf(delta * 12.0, 0.0, 1.0))

	current.root.visible = not scoped() and not holstered
	var low := smoothstep(0.0, 1.0, _lower)
	_sprint_t = move_toward(_sprint_t, 1.0 if player.sprinting else 0.0, delta * 5.0)
	var run := smoothstep(0.0, 1.0, _sprint_t)
	var offset := Transform3D(Basis(Vector3.RIGHT, _wall_push * 1.0 - low * 0.9 - run * 0.25) * Basis(Vector3.UP, run * 0.7)
			* Basis(Vector3.BACK, run * 0.35),
			bob + Vector3(_sway.x * (1.0 - a * 0.6) - run * 0.06, _sway.y * (1.0 - a * 0.6) - low * 0.35 - run * 0.06, _wall_push * 0.5 + run * 0.04))
	_holder.transform = offset * Transform3D.IDENTITY.interpolate_with(current.ads, a)
