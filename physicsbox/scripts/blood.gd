extends Node
## Blood / impact effects manager (autoload "Blood").
## Simulates flying droplets, leaves splats where they land, spawns wounds,
## pools, mist bursts, dust and bullet holes.

const MAX_DROPS := 420
const MAX_SPLATS := 200
const MAX_HOLES := 60
const DROP_MASK := 1 | 2
const GRAVITY := Vector3(0.0, -9.8, 0.0)
const DROP_LIFETIME := 3.5

var _pos := PackedVector3Array()
var _vel := PackedVector3Array()
var _size := PackedFloat32Array()
var _age := PackedFloat32Array()
var _count := 0

var _mm: MultiMesh
var _mm_node: MultiMeshInstance3D
var _ray := PhysicsRayQueryParameters3D.new()

var _quad := QuadMesh.new()
var _splat_mats: Array[StandardMaterial3D] = []
var _wound_mat: StandardMaterial3D
var _pool_mat: StandardMaterial3D
var _hole_mat: StandardMaterial3D
var _puff_mesh := SphereMesh.new()
var _shrink_curve := Curve.new()

var _splats: Array = []
var _splat_i := 0
var _holes: Array = []
var _hole_i := 0


func _ready() -> void:
	_pos.resize(MAX_DROPS)
	_vel.resize(MAX_DROPS)
	_size.resize(MAX_DROPS)
	_age.resize(MAX_DROPS)
	_ray.collision_mask = DROP_MASK
	_ray.hit_back_faces = false

	var drop_mesh := SphereMesh.new()
	drop_mesh.radius = 0.5
	drop_mesh.height = 1.0
	drop_mesh.radial_segments = 6
	drop_mesh.rings = 3
	var drop_mat := StandardMaterial3D.new()
	drop_mat.albedo_color = Color(0.55, 0.01, 0.025)
	drop_mat.roughness = 0.15
	drop_mesh.material = drop_mat
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.mesh = drop_mesh
	_mm.instance_count = MAX_DROPS
	_mm.visible_instance_count = 0
	_mm_node = MultiMeshInstance3D.new()
	_mm_node.multimesh = _mm
	_mm_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mm_node.custom_aabb = AABB(Vector3(-1000, -1000, -1000), Vector3(2000, 2000, 2000))
	add_child(_mm_node)

	_quad.size = Vector2.ONE
	for i in 6:
		_splat_mats.append(_decal_material("res://assets/textures/splat_%d.png" % i, Color(1, 1, 1)))
	_wound_mat = _decal_material("res://assets/textures/splat_0.png", Color(0.6, 0.6, 0.6))
	_pool_mat = _decal_material("res://assets/textures/pool.png", Color(0.9, 0.9, 0.9))
	_pool_mat.roughness = 0.05
	_hole_mat = _decal_material("res://assets/textures/bullet_hole.png", Color(1, 1, 1))
	_hole_mat.roughness = 0.9

	# burst particles are tiny low-poly droplets/chips that shrink away
	_puff_mesh.radius = 0.5
	_puff_mesh.height = 1.0
	_puff_mesh.radial_segments = 5
	_puff_mesh.rings = 2
	var puff_mat := StandardMaterial3D.new()
	puff_mat.vertex_color_use_as_albedo = true
	puff_mat.roughness = 0.3
	_puff_mesh.material = puff_mat
	_shrink_curve.add_point(Vector2(0, 1.0))
	_shrink_curve.add_point(Vector2(0.7, 0.8))
	_shrink_curve.add_point(Vector2(1, 0.0))


func _decal_material(path: String, tint: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(path)
	m.albedo_color = tint
	# alpha blending: alpha scissor rendered decals black on some Vulkan drivers
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.18
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	return m


## Removes every effect (called when leaving a level).
func clear() -> void:
	_count = 0
	_mm.visible_instance_count = 0
	for n in _splats + _holes:
		if is_instance_valid(n):
			n.queue_free()
	_splats.clear()
	_holes.clear()
	_splat_i = 0
	_hole_i = 0


func _scene_root() -> Node:
	return get_tree().current_scene


# ---------------------------------------------------------------- droplets

## Fires `count` droplets from `origin` roughly along `dir`.
func spray(origin: Vector3, dir: Vector3, count: int, speed_min: float, speed_max: float,
		spread := 0.35, size_min := 0.012, size_max := 0.03) -> void:
	count = int(round(count * Settings.blood_amount))
	dir = dir.normalized()
	for i in count:
		if _count >= MAX_DROPS:
			return
		var d := (dir + Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * spread).normalized()
		_pos[_count] = origin
		_vel[_count] = d * randf_range(speed_min, speed_max)
		_size[_count] = randf_range(size_min, size_max)
		_age[_count] = 0.0
		_count += 1


## A single slow drop (bleeding wounds).
func drip(origin: Vector3, size := 0.02) -> void:
	if _count >= MAX_DROPS:
		return
	_pos[_count] = origin
	_vel[_count] = Vector3(randf_range(-0.15, 0.15), -0.3, randf_range(-0.15, 0.15))
	_size[_count] = size
	_age[_count] = 0.0
	_count += 1


func _physics_process(delta: float) -> void:
	if _count == 0:
		_mm.visible_instance_count = 0
		return
	var space := _mm_node.get_world_3d().direct_space_state
	var i := 0
	while i < _count:
		var p := _pos[i]
		var v := _vel[i] + GRAVITY * delta
		v *= 1.0 - 0.35 * delta
		var np := p + v * delta
		_age[i] += delta
		_ray.from = p
		_ray.to = np
		var hit := space.intersect_ray(_ray)
		if not hit.is_empty() or _age[i] > DROP_LIFETIME:
			if not hit.is_empty():
				var s := _size[i] * randf_range(14.0, 24.0)
				var parent: Node3D = hit.collider if hit.collider is RigidBody3D else null
				splat(hit.position, hit.normal, s, parent)
			_count -= 1
			_pos[i] = _pos[_count]
			_vel[i] = _vel[_count]
			_size[i] = _size[_count]
			_age[i] = _age[_count]
			continue
		_pos[i] = np
		_vel[i] = v
		var speed := v.length()
		var basis := Basis.IDENTITY
		if speed > 0.05:
			var fwd := v / speed
			var up := Vector3.UP if absf(fwd.y) < 0.98 else Vector3.RIGHT
			basis = Basis.looking_at(fwd, up)
		var sz := _size[i]
		basis = basis * Basis.from_scale(Vector3(sz, sz, sz * (1.0 + minf(speed * 0.35, 3.0))))
		_mm.set_instance_transform(i, Transform3D(basis, np))
		i += 1
	_mm.visible_instance_count = _count


# ---------------------------------------------------------------- surface marks

func _surface_basis(normal: Vector3, size: float) -> Basis:
	var up := Vector3.UP if absf(normal.y) < 0.95 else Vector3.FORWARD
	var b := Basis.looking_at(-normal, up)
	b = b * Basis(Vector3(0, 0, 1), randf() * TAU)
	return b * Basis.from_scale(Vector3(size, size, 1.0))


func _place(node: MeshInstance3D, pos: Vector3, normal: Vector3, size: float, parent: Node3D) -> void:
	var root := _scene_root()
	if root == null:
		node.free()
		return
	if parent != null and is_instance_valid(parent):
		parent.add_child(node)
	else:
		root.add_child(node)
	node.global_transform = Transform3D(_surface_basis(normal, size), pos + normal * randf_range(0.003, 0.009))


func _push_splat(node: MeshInstance3D) -> void:
	if _splats.size() < MAX_SPLATS:
		_splats.append(node)
	else:
		var old = _splats[_splat_i]
		if is_instance_valid(old):
			old.queue_free()
		_splats[_splat_i] = node
		_splat_i = (_splat_i + 1) % MAX_SPLATS


func _new_quad(mat: Material) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = _quad
	m.material_override = mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return m


## Flat blood mark on a surface.
func splat(pos: Vector3, normal: Vector3, size: float, parent: Node3D = null) -> void:
	var m := _new_quad(_splat_mats[randi() % _splat_mats.size()])
	_place(m, pos, normal, size, parent)
	_push_splat(m)


## Wound mark glued to a body part.
func wound(part: Node3D, pos: Vector3, normal: Vector3) -> void:
	var m := _new_quad(_wound_mat)
	_place(m, pos, normal, randf_range(0.07, 0.12), part)
	_push_splat(m)


## Growing pool under a body. Returns the node so the caller can grow it.
func pool(pos: Vector3, normal: Vector3) -> MeshInstance3D:
	var m := _new_quad(_pool_mat)
	_place(m, pos, normal, 1.0, null)
	m.global_position = pos + normal * 0.004
	_push_splat(m)
	return m


func bullet_hole(pos: Vector3, normal: Vector3, parent: Node3D = null) -> void:
	var m := _new_quad(_hole_mat)
	_place(m, pos, normal, randf_range(0.05, 0.07), parent)
	if _holes.size() < MAX_HOLES:
		_holes.append(m)
	else:
		var old = _holes[_hole_i]
		if is_instance_valid(old):
			old.queue_free()
		_holes[_hole_i] = m
		_hole_i = (_hole_i + 1) % MAX_HOLES


# ---------------------------------------------------------------- particle bursts

func _burst(pos: Vector3, dir: Vector3, amount: int, color: Color, speed: float, spread: float,
		lifetime: float, size: float, gravity: float) -> void:
	var root := _scene_root()
	if root == null or amount <= 0:
		return
	var p := CPUParticles3D.new()
	p.emitting = false
	p.top_level = true
	p.position = pos
	p.mesh = _puff_mesh
	p.amount = amount
	p.lifetime = lifetime
	p.one_shot = true
	p.explosiveness = 1.0
	p.local_coords = false
	p.direction = dir.normalized() if dir.length() > 0.01 else Vector3.UP
	p.spread = spread
	p.initial_velocity_min = speed * 0.3
	p.initial_velocity_max = speed
	p.gravity = Vector3(0, -gravity, 0)
	p.damping_min = speed * 0.3
	p.damping_max = speed * 0.8
	p.scale_amount_min = size * 0.5
	p.scale_amount_max = size * 1.4
	p.scale_amount_curve = _shrink_curve
	p.color = color
	root.add_child(p)
	p.emitting = true
	get_tree().create_timer(lifetime + 0.3, false).timeout.connect(p.queue_free)


## Burst of fine blood specks (bullet entry / exit).
func mist(pos: Vector3, dir: Vector3, strength := 1.0) -> void:
	_burst(pos, dir, int(26 * strength * Settings.blood_amount) + 6, Color(0.5, 0.01, 0.025),
			3.5 * strength, 38.0, 0.55, 0.022, 7.0)


## Debris chips for non-flesh impacts.
func dust(pos: Vector3, normal: Vector3, color := Color(0.75, 0.73, 0.7)) -> void:
	_burst(pos, normal, 12, color, 3.0, 35.0, 0.6, 0.02, 9.0)
