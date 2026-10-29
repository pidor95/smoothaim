class_name Explosion
extends Node3D
## Blast of a grenade or an FPV drone's warhead: flash, fireball, smoke,
## flying dirt and a scorch mark; a shock wave that tears apart, knocks down
## or kills soldiers close by and throws bodies and props about; fragments
## that hit like bullets; damage to the player; everyone near hears it.

const MAX_SCORCHES := 14

static var _tex := {}
static var _mats := {}


## `power` 1 = hand grenade; `by_player` credits the kills.
static func boom(tree: SceneTree, pos: Vector3, power := 1.0, by_player := false, sound := "explosion") -> void:
	var e := Explosion.new()
	tree.current_scene.add_child(e)
	e.global_position = pos
	e._fx(power, sound)
	e._damage(power, by_player)
	tree.create_timer(5.0, false).timeout.connect(e.queue_free)


static func _texture(name: String) -> Texture2D:
	if not _tex.has(name):
		_tex[name] = load("res://assets/textures/%s.png" % name)
	return _tex[name]


static func _sprite_mat(tex: String, additive: bool) -> StandardMaterial3D:
	var key := tex + str(additive)
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_texture = _texture(tex)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.vertex_color_use_as_albedo = true
		m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		if additive:
			m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_mats[key] = m
	return _mats[key]


func _particles(tex: String, additive: bool, amount: int, lifetime: float, vel: Vector2, spread: float,
		gravity: float, size: Vector2, colors: PackedColorArray, grow := 1.0) -> void:
	var p := CPUParticles3D.new()
	var quad := QuadMesh.new()
	quad.material = _sprite_mat(tex, additive)
	p.mesh = quad
	p.amount = amount
	p.lifetime = lifetime
	p.one_shot = true
	p.explosiveness = 0.92
	p.direction = Vector3.UP
	p.spread = spread
	p.initial_velocity_min = vel.x
	p.initial_velocity_max = vel.y
	p.gravity = Vector3(0, gravity, 0)
	p.damping_min = 1.5
	p.damping_max = 3.0
	p.scale_amount_min = size.x
	p.scale_amount_max = size.y
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.4))
	curve.add_point(Vector2(1, grow))
	p.scale_amount_curve = curve
	var ramp := Gradient.new()
	ramp.colors = colors
	p.color_ramp = ramp
	p.angle_min = -180
	p.angle_max = 180
	p.local_coords = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
	p.emitting = true


func _fx(power: float, sound: String) -> void:
	Sfx.play_3d(sound, global_position, 6.0, 0.06)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.65, 0.3)
	light.light_energy = 14.0 * power
	light.omni_range = 9.0 + 6.0 * power
	add_child(light)
	light.position = Vector3.UP * 0.6
	create_tween().tween_property(light, "light_energy", 0.0, 0.35)
	var s := sqrt(power)
	# fireball, smoke column, dirt thrown up
	_particles("fire", true, 14, 0.4, Vector2(2.0, 6.0) * s, 70.0, 2.0, Vector2(0.8, 1.6) * s,
			PackedColorArray([Color(1, 0.9, 0.6, 1), Color(1, 0.45, 0.1, 0.8), Color(0.3, 0.1, 0.05, 0)]), 2.0)
	_particles("smoke", false, 18, 4.0, Vector2(1.5, 4.5) * s, 55.0, 0.6, Vector2(1.2, 2.2) * s,
			PackedColorArray([Color(0.25, 0.22, 0.2, 0.9), Color(0.38, 0.36, 0.34, 0.55), Color(0.5, 0.5, 0.5, 0)]), 3.2)
	_particles("smoke", false, 40, 1.8, Vector2(5.0, 12.0) * s, 35.0, -9.8, Vector2(0.08, 0.22),
			PackedColorArray([Color(0.16, 0.12, 0.09, 1), Color(0.2, 0.15, 0.11, 1), Color(0.2, 0.15, 0.11, 0)]), 1.0)
	# scorch mark on whatever is underneath
	var q := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 0.5, global_position + Vector3.DOWN * 1.5, 1 | 2)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		var d := Decal.new()
		d.texture_albedo = _texture("scorch")
		d.size = Vector3(2.6, 1.2, 2.6) * s
		d.cull_mask = 1
		get_tree().current_scene.add_child(d)
		d.global_position = hit.position
		d.rotation.y = randf() * TAU
		d.add_to_group("scorches")
		var all := get_tree().get_nodes_in_group("scorches")
		if all.size() > MAX_SCORCHES:
			all[0].queue_free()


func _clear(space: PhysicsDirectSpaceState3D, a: Vector3, b: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(a, b, 1 | 2)
	return space.intersect_ray(q).is_empty()


func _damage(power: float, by_player: bool) -> void:
	var space := get_world_3d().direct_space_state
	var center := global_position + Vector3.UP * 0.25
	var radius := 7.0 * power
	# shock wave on soldiers in sight of the blast
	for n in get_tree().get_nodes_in_group("npcs"):
		var c: Vector3 = n.center()
		var d := c.distance_to(center)
		if d > radius or not _clear(space, center, c):
			continue
		n.last_hit_by_player = by_player
		# a drone's warhead going off on him (or a grenade at his feet) tears him apart
		if (power >= 1.3 and d < 1.8) or d < 0.7:
			n.torn_apart(center, power)
			continue
		n.blast(center, 1.0 - d / radius, power)
	# fragments: they fly out and hit like bullets
	var frags := int(50 * power)
	for i in frags:
		var dir := Vector3(randf_range(-1, 1), randf_range(0.0, 0.8), randf_range(-1, 1)).normalized()
		var q := PhysicsRayQueryParameters3D.create(center, center + dir * 18.0, 1 | 2 | 4 | 16)
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			continue
		var col: Object = hit.collider
		var dist := center.distance_to(hit.position)
		var f := 1.0 - dist / 18.0
		if col is Player:
			(col as Player).take_damage(10.0 * f + 4.0, dir)
		elif col.has_meta("npc"):
			var npc = col.get_meta("npc")
			if is_instance_valid(npc):
				npc.last_hit_by_player = by_player
				npc.take_hit(col, hit.position, hit.normal, dir, 26.0 * f + 6.0, 2.5, 0.35)
		elif col.get_meta("surface", "") == "glass" and col.has_method("shatter"):
			col.shatter(hit.position, dir)
		elif i % 3 == 0:
			Blood.bullet_hole(hit.position, hit.normal, col as Node3D if col is RigidBody3D else null)
	# the player: blast and a shaken camera
	var player := get_tree().get_first_node_in_group("player") as Player
	if player:
		var pc := player.global_position + Vector3.UP * 1.0
		var d := pc.distance_to(center)
		if d < radius * 0.85 and _clear(space, center, pc):
			player.take_damage(130.0 * pow(1.0 - d / (radius * 0.85), 1.4), (pc - center).normalized(), "blast")
		player.add_shake(clampf(1.3 - d / 22.0, 0.0, 1.0) * power)
		player.ear_ring = maxf(player.ear_ring, clampf(1.0 - d / 14.0, 0.0, 1.0) * power)
		player.add_stress(clampf(1.0 - d / 30.0, 0.0, 1.0))
	# loose bodies, gore and props are thrown about
	var sphere := SphereShape3D.new()
	sphere.radius = radius
	var sq := PhysicsShapeQueryParameters3D.new()
	sq.shape = sphere
	sq.transform = Transform3D(Basis.IDENTITY, center)
	sq.collision_mask = 2 | 4 | 32
	for r in space.intersect_shape(sq, 96):
		var rb := r.collider as RigidBody3D
		if rb != null and rb.has_meta("settled"): # a body or a piece at rest: up it goes again
			if rb.has_meta("npc") and is_instance_valid(rb.get_meta("npc")):
				rb.get_meta("npc").wake_ragdoll()
			else:
				rb.freeze = false
				rb.remove_meta("settled")
		if rb == null or rb.freeze:
			continue
		var away := rb.global_position - center
		var d := away.length()
		var push := (away / maxf(d, 0.1) + Vector3.UP * 0.5).normalized()
		rb.apply_central_impulse(push * rb.mass * 9.0 * power * (1.0 - d / radius))
	for n in get_tree().get_nodes_in_group("npcs"):
		if n.global_position.distance_to(center) < 45.0:
			n.alert(center)
	for door in get_tree().get_nodes_in_group("doors"):
		if door.global_position.distance_to(center) < 3.0 * power and door.has_method("take_bullet"):
			door.take_bullet(door.global_position, (door.global_position - center).normalized(), 200.0)
