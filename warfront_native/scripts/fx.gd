extends Node3D
## Visual effects: explosions, impacts, smoke trails, smoke screens, flares, tracers.

var smoke_mat: StandardMaterial3D
var fire_mat: StandardMaterial3D
var quad: QuadMesh
var impacts: Array[CPUParticles3D] = []
var impact_i := 0
var tracer_mesh := ImmediateMesh.new()
var tracer_mi := MeshInstance3D.new()


func _ready() -> void:
	smoke_mat = StandardMaterial3D.new()
	smoke_mat.albedo_texture = preload("res://assets/fx/smoke.png")
	smoke_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smoke_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smoke_mat.vertex_color_use_as_albedo = true
	smoke_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	smoke_mat.billboard_keep_scale = true
	fire_mat = smoke_mat.duplicate()
	fire_mat.albedo_texture = preload("res://assets/fx/fire.png")
	fire_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	quad = QuadMesh.new()
	for i in 28:
		var e := _emitter(smoke_mat, 8, 1.4)
		e.one_shot = true
		e.emitting = false
		e.explosiveness = 1.0
		e.direction = Vector3.UP
		e.spread = 35.0
		e.initial_velocity_min = 2.0
		e.initial_velocity_max = 5.0
		e.gravity = Vector3(0, -2.0, 0)
		e.damping_min = 2.0
		e.damping_max = 3.0
		e.scale_amount_min = 1.2
		e.scale_amount_max = 2.6
		e.scale_amount_curve = _curve(0.5, 1.0)
		e.color_ramp = _ramp(Color(0.55, 0.5, 0.42, 0.75), Color(0.55, 0.5, 0.42, 0.0))
		impacts.append(e)
	var tm := StandardMaterial3D.new()
	tm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tm.vertex_color_use_as_albedo = true
	tm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	tm.cull_mode = BaseMaterial3D.CULL_DISABLED
	tracer_mi.mesh = tracer_mesh
	tracer_mi.material_override = tm
	tracer_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	tracer_mi.extra_cull_margin = 16384.0
	add_child(tracer_mi)


static func _curve(a: float, b: float) -> Curve:
	var c := Curve.new()
	c.add_point(Vector2(0, a))
	c.add_point(Vector2(1, b))
	return c


static func _ramp(a: Color, b: Color, mid := Color(0, 0, 0, -1.0), at := 0.3) -> Gradient:
	var g := Gradient.new()
	g.set_color(0, a)
	g.set_color(1, b)
	if mid.a >= 0.0:
		g.add_point(at, mid)
	return g


func _emitter(mat: Material, amount: int, life: float, parent: Node = null) -> CPUParticles3D:
	var e := CPUParticles3D.new()
	var q := QuadMesh.new()
	q.material = mat
	e.mesh = q
	e.amount = amount
	e.lifetime = life
	e.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	e.local_coords = false
	(parent if parent else self).add_child(e)
	return e


func _free_later(n: Node, t: float) -> void:
	get_tree().create_timer(t, false).timeout.connect(n.queue_free)


## Dust puff where a bullet hits the ground (reused emitters).
func impact(p: Vector3, big := false) -> void:
	var e := impacts[impact_i]
	impact_i = (impact_i + 1) % impacts.size()
	e.global_position = p
	e.scale_amount_min = 2.5 if big else 1.0
	e.scale_amount_max = 5.0 if big else 2.2
	e.restart()


func explosion(p: Vector3, s: float, ground: bool) -> void:
	var root := Node3D.new()
	add_child(root)
	root.global_position = p
	var fire := _emitter(fire_mat, int(14 * s) + 6, 0.7, root)
	fire.one_shot = true
	fire.explosiveness = 0.95
	fire.spread = 180.0
	fire.initial_velocity_min = 4.0 * s
	fire.initial_velocity_max = 14.0 * s
	fire.damping_min = 8.0
	fire.damping_max = 12.0
	fire.gravity = Vector3(0, 3, 0)
	fire.scale_amount_min = 4.0 * s
	fire.scale_amount_max = 9.0 * s
	fire.scale_amount_curve = _curve(0.6, 1.3)
	fire.color_ramp = _ramp(Color(1, 0.95, 0.75, 1), Color(0.6, 0.15, 0.02, 0), Color(1, 0.55, 0.15, 0.9), 0.35)
	var sparks := _emitter(fire_mat, int(10 * s) + 4, 1.1, root)
	sparks.one_shot = true
	sparks.explosiveness = 1.0
	sparks.direction = Vector3.UP
	sparks.spread = 80.0
	sparks.initial_velocity_min = 20.0 * s
	sparks.initial_velocity_max = 45.0 * s
	sparks.gravity = Vector3(0, -9.8, 0)
	sparks.scale_amount_min = 0.5
	sparks.scale_amount_max = 1.2
	sparks.color_ramp = _ramp(Color(1, 0.8, 0.4, 1), Color(1, 0.4, 0.1, 0))
	var sm := _emitter(smoke_mat, int(10 * s) + 6, 5.0, root)
	sm.position = Vector3(0, 1, 0)
	sm.one_shot = true
	sm.explosiveness = 0.85
	sm.direction = Vector3.UP
	sm.spread = 60.0
	sm.initial_velocity_min = 3.0 * s
	sm.initial_velocity_max = 9.0 * s
	sm.damping_min = 1.5
	sm.damping_max = 2.5
	sm.gravity = Vector3(0, 1.2, 0)
	sm.scale_amount_min = 6.0 * s
	sm.scale_amount_max = 12.0 * s
	sm.scale_amount_curve = _curve(0.4, 1.6)
	sm.color_ramp = _ramp(Color(0.16, 0.15, 0.14, 0.85), Color(0.35, 0.34, 0.32, 0.0))
	if ground:
		var dust := _emitter(smoke_mat, int(12 * s) + 4, 3.0, root)
		dust.one_shot = true
		dust.explosiveness = 1.0
		dust.direction = Vector3(1, 0.15, 0)
		dust.spread = 180.0
		dust.flatness = 0.9
		dust.initial_velocity_min = 10.0 * s
		dust.initial_velocity_max = 18.0 * s
		dust.damping_min = 6.0
		dust.damping_max = 8.0
		dust.scale_amount_min = 3.0 * s
		dust.scale_amount_max = 7.0 * s
		dust.scale_amount_curve = _curve(0.5, 1.4)
		dust.color_ramp = _ramp(Color(0.48, 0.42, 0.33, 0.7), Color(0.5, 0.45, 0.37, 0))
	for e in root.get_children():
		(e as CPUParticles3D).emitting = true
	var light := OmniLight3D.new()
	light.light_color = Color(1, 0.65, 0.3)
	light.light_energy = 6.0 * s
	light.omni_range = 30.0 * s
	light.shadow_enabled = false
	root.add_child(light)
	var tw := create_tween()
	tw.tween_property(light, "light_energy", 0.0, 0.4)
	_free_later(root, 6.0)


## Thin smoke trail behind a missile or rocket; returns the emitter so the caller can stop it.
func trail(parent: Node3D, rocket: bool) -> CPUParticles3D:
	var e := _emitter(smoke_mat, 40 if rocket else 90, 1.6 if rocket else 3.2, parent)
	e.position = Vector3(0, 0, 1.8)
	e.direction = Vector3(0, 0, 1)
	e.spread = 8.0
	e.initial_velocity_min = 1.0
	e.initial_velocity_max = 3.0
	e.gravity = Vector3(0, 0.6, 0)
	e.scale_amount_min = 1.0
	e.scale_amount_max = 1.6
	e.scale_amount_curve = _curve(0.6, 3.0 if rocket else 4.5)
	e.color_ramp = _ramp(Color(0.92, 0.9, 0.86, 0.75), Color(0.85, 0.85, 0.85, 0.0))
	e.emitting = true
	var glow := Sprite3D.new()
	glow.texture = preload("res://assets/fx/glow.png")
	glow.material_override = _glow_mat()
	glow.modulate = Color(1, 0.75, 0.4)
	glow.pixel_size = 0.02
	glow.position = Vector3(0, 0, 1.2)
	glow.name = "Flame"
	parent.add_child(glow)
	return e


var _gm: StandardMaterial3D
func _glow_mat() -> StandardMaterial3D:
	if _gm == null:
		_gm = StandardMaterial3D.new()
		_gm.albedo_texture = preload("res://assets/fx/glow.png")
		_gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_gm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_gm.vertex_color_use_as_albedo = true
		_gm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	return _gm


## Leave a trail hanging in the air after its missile is gone.
func detach_trail(e: CPUParticles3D) -> void:
	if not is_instance_valid(e):
		return
	e.reparent(self)
	e.emitting = false
	_free_later(e, e.lifetime + 0.5)


func flare_node() -> Node3D:
	var n: Node3D = preload("res://scripts/flare.gd").new()
	add_child(n)
	var g := Sprite3D.new()
	g.texture = preload("res://assets/fx/glow.png")
	g.material_override = _glow_mat()
	g.modulate = Color(1, 0.9, 0.7)
	g.pixel_size = 0.05
	n.add_child(g)
	var e := _emitter(smoke_mat, 30, 2.0, n)
	e.initial_velocity_min = 0.2
	e.initial_velocity_max = 0.8
	e.gravity = Vector3(0, 0.5, 0)
	e.scale_amount_min = 1.2
	e.scale_amount_max = 2.0
	e.scale_amount_curve = _curve(0.6, 2.5)
	e.color_ramp = _ramp(Color(0.95, 0.95, 0.95, 0.5), Color(0.9, 0.9, 0.9, 0))
	e.emitting = true
	n.glow = g
	n.smoke = e
	return n


## Smoke screen: a dense cloud that blocks missile seekers for ~18 s.
func smoke_screen(p: Vector3, r: float) -> void:
	var e := _emitter(smoke_mat, 60, 19.0)
	e.global_position = p
	e.one_shot = true
	e.explosiveness = 0.9
	e.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	e.emission_sphere_radius = r * 0.25
	e.direction = Vector3(1, 0.2, 0)
	e.spread = 180.0
	e.flatness = 0.6
	e.initial_velocity_min = r * 0.4
	e.initial_velocity_max = r * 0.9
	e.damping_min = r * 0.3
	e.damping_max = r * 0.45
	e.gravity = Vector3(0, 0.15, 0)
	e.scale_amount_min = 14.0
	e.scale_amount_max = 22.0
	e.scale_amount_curve = _curve(0.5, 1.4)
	e.color_ramp = _ramp(Color(0.86, 0.87, 0.88, 0.95), Color(0.86, 0.87, 0.88, 0.0), Color(0.86, 0.87, 0.88, 0.9), 0.75)
	e.emitting = true
	_free_later(e, 21.0)


## Black smoke column over a wreck.
func wreck(p: Vector3) -> void:
	var e := _emitter(smoke_mat, 24, 6.0)
	e.global_position = p
	e.one_shot = true
	e.explosiveness = 0.2
	e.direction = Vector3.UP
	e.spread = 15.0
	e.initial_velocity_min = 5.0
	e.initial_velocity_max = 9.0
	e.scale_amount_min = 5.0
	e.scale_amount_max = 9.0
	e.scale_amount_curve = _curve(0.5, 2.5)
	e.color_ramp = _ramp(Color(0.1, 0.09, 0.08, 0.8), Color(0.3, 0.3, 0.3, 0.0))
	e.emitting = true
	_free_later(e, 8.0)


## Draw all tracers as camera-facing streaks.
func draw_tracers(bullets: Array, cam: Vector3) -> void:
	tracer_mesh.clear_surfaces()
	if bullets.is_empty():
		return
	tracer_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 0
	for b in bullets:
		var a: Vector3 = b["p"]
		var bv: Vector3 = b["v"]
		var e: Vector3 = a - bv * float(b["len"])
		var dist := a.distance_to(cam)
		var wdt := 0.08 + dist * 0.0012
		var side := (e - a).cross(cam - a)
		if side.length_squared() < 1e-6:
			continue
		side = side.normalized() * wdt
		var c: Color = b["col"]
		var c2 := Color(c.r, c.g, c.b, 0.0)
		for v in [[a - side, c], [a + side, c], [e + side, c2], [a - side, c], [e + side, c2], [e - side, c2]]:
			tracer_mesh.surface_set_color(v[1])
			tracer_mesh.surface_add_vertex(v[0])
		n += 1
		if n > 600:
			break
	tracer_mesh.surface_end()
