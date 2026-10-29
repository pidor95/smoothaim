extends Node
## Blood / impact effects manager (autoload "Blood").
## Simulates flying droplets, leaves splats where they land, spawns wounds,
## pools, mist bursts, dust and bullet holes.
## Marks on the static world go into big MultiMeshes (one draw call each) so
## blood stays for the whole round; marks on moving bodies are separate nodes,
## except the wounds in the uniform: a curved patch per hit, in one MultiMesh
## per body part. Bursts (blood mist, dust) reuse a small pool of emitters.

const MAX_DROPS := 420
const MAX_WORLD_SPLATS := 6000
const MAX_BODY_SPLATS := 160
## Only this share of drops that land on a soldier leaves a mark on him
## (each one is a node; his wounds and the soaked cloth show the rest).
const BODY_DROP_MARKS := 0.3
## Wounds in the uniform (wound_atlas.png): cells and patch size.
const WOUND_CELLS := {"entry": [0, 1], "exit": [2], "rip": [3]}
const WOUND_PATCH := 0.2
const WOUNDS_PER_PART := 6
## Burst emitters kept per kind and reused (no node per bullet).
const BURST_POOL := 10
const MAX_WORLD_HOLES := 2000
const MAX_BODY_HOLES := 120
# atlas cells (tools/blender/build_blood_atlas.py)
const CELL_DROPS := [0, 1]
const CELL_SPLASH := [2, 3]
const CELL_SPRAY := 4
const CELL_SMEAR := 5
const CELL_POOLS := [6, 7]
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
var _world_mat := ShaderMaterial.new()
var _body_mat := ShaderMaterial.new()
var _hole_mat: StandardMaterial3D
var _splat_mm := MultiMesh.new()
var _splat_n := 0
var _hole_mm := MultiMesh.new()
var _hole_n := 0
var _puff_mesh := SphereMesh.new()
var _shrink_curve := Curve.new()

var _body_splats: Array = []
var _body_holes: Array = []
var _wound_mat := ShaderMaterial.new()
var _patches := {} # radius (mm) -> curved patch mesh
var _pools := {} # burst kind -> [emitters, next]


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
	var atlas := load("res://assets/textures/blood_atlas.png")
	_world_mat.shader = load("res://assets/shaders/blood_decal_mm.gdshader")
	_world_mat.set_shader_parameter("atlas", atlas)
	_body_mat.shader = load("res://assets/shaders/blood_decal_node.gdshader")
	_body_mat.set_shader_parameter("atlas", atlas)
	_hole_mat = StandardMaterial3D.new()
	_hole_mat.albedo_texture = load("res://assets/textures/bullet_hole.png")
	_hole_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_hole_mat.roughness = 0.9
	_hole_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_splat_mm.transform_format = MultiMesh.TRANSFORM_3D
	_splat_mm.use_custom_data = true
	_splat_mm.mesh = _quad
	_splat_mm.instance_count = MAX_WORLD_SPLATS
	_splat_mm.visible_instance_count = 0
	_add_mm_node(_splat_mm, _world_mat)
	_hole_mm.transform_format = MultiMesh.TRANSFORM_3D
	_hole_mm.mesh = _quad
	_hole_mm.instance_count = MAX_WORLD_HOLES
	_hole_mm.visible_instance_count = 0
	_add_mm_node(_hole_mm, _hole_mat)

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
	_wound_mat.shader = load("res://assets/shaders/wound_decal.gdshader")
	_wound_mat.set_shader_parameter("atlas", load("res://assets/textures/wound_atlas.png"))


func _add_mm_node(mm: MultiMesh, mat: Material) -> void:
	var node := MultiMeshInstance3D.new()
	node.multimesh = mm
	node.material_override = mat
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.custom_aabb = AABB(Vector3(-1000, -1000, -1000), Vector3(2000, 2000, 2000))
	add_child(node)


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _process(_delta: float) -> void:
	var t := _now()
	_world_mat.set_shader_parameter("now", t)
	_body_mat.set_shader_parameter("now", t)


## Removes every effect (new round / "clear bodies and blood").
func clear() -> void:
	_count = 0
	_mm.visible_instance_count = 0
	_splat_n = 0
	_splat_mm.visible_instance_count = 0
	_hole_n = 0
	_hole_mm.visible_instance_count = 0
	for n in _body_splats + _body_holes:
		if is_instance_valid(n):
			n.queue_free()
	_body_splats.clear()
	_body_holes.clear()


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
				splat(hit.position, hit.normal, s, parent, _vel[i])
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

## Basis for a quad lying on a surface; its +X follows `along` when given.
func _surface_basis(normal: Vector3, size: float, along := Vector3.ZERO, spin := 0.0) -> Basis:
	var x := along - normal * along.dot(normal)
	if x.length() < 0.05:
		var up := Vector3.UP if absf(normal.y) < 0.95 else Vector3.FORWARD
		x = up.cross(normal).rotated(normal, randf() * TAU)
	x = x.normalized().rotated(normal, spin)
	var y := normal.cross(x).normalized()
	return Basis(x * size, y * size, normal)


func _mark_xform(pos: Vector3, normal: Vector3, size: float, along := Vector3.ZERO, spin := 0.0) -> Transform3D:
	return Transform3D(_surface_basis(normal, size, along, spin), pos + normal * randf_range(0.003, 0.009))


func _add_world(xform: Transform3D, cell: int, tint: float, grow := 0.0) -> void:
	var i := _splat_n % MAX_WORLD_SPLATS
	_splat_mm.set_instance_transform(i, xform)
	_splat_mm.set_instance_custom_data(i, Color(cell, _now(), tint, grow))
	_splat_n += 1
	_splat_mm.visible_instance_count = mini(_splat_n, MAX_WORLD_SPLATS)


func _add_body(parent: Node3D, xform: Transform3D, cell: int, tint: float) -> void:
	var m := MeshInstance3D.new()
	m.mesh = _quad
	m.material_override = _body_mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(m)
	m.global_transform = xform
	m.set_instance_shader_parameter("decal", Vector4(cell, _now(), tint, 0.0))
	_body_splats.append(m)
	while _body_splats.size() > MAX_BODY_SPLATS:
		var old = _body_splats.pop_front()
		if is_instance_valid(old):
			old.queue_free()


## Blood mark where a drop landed. The shape follows how it hit: slow drops
## leave round crowns, fast slanted ones splash along their travel, specks
## become fine spray.
func splat(pos: Vector3, normal: Vector3, size: float, parent: Node3D = null, vel := Vector3.ZERO) -> void:
	var cell: int = CELL_DROPS[randi() % 2]
	var along := Vector3.ZERO
	var spin := 0.0
	var tangential := vel - normal * vel.dot(normal)
	if size < 0.2 and randf() < 0.35:
		cell = CELL_SPRAY
	elif tangential.length() > 1.6:
		cell = CELL_SPLASH[randi() % 2]
		along = tangential
		spin = -0.5 if cell == 3 else 0.0
		size *= 1.35
	var xform := _mark_xform(pos, normal, size * 1.15, along, spin)
	var tint := randf_range(0.8, 1.15)
	if parent != null and is_instance_valid(parent):
		if parent.has_meta("npc") and randf() < BODY_DROP_MARKS:
			_add_body(parent, xform, cell, tint)
	else:
		_add_world(xform, cell, tint)


## Wound mark glued to a body part.
func wound(part: Node3D, pos: Vector3, normal: Vector3) -> void:
	_add_body(part, _mark_xform(pos, normal, randf_range(0.08, 0.12)), CELL_DROPS[randi() % 2], 0.7)


## A wound in the uniform where a round (or a fragment) went in or out:
## the hole, torn flesh, frayed cloth, the blood soaking out. `frame` is the
## part's visual in the part's space (a capsule along its Y, `radius`,
## `length` long); the patch is curved round it. kind: entry / exit / rip.
func body_wound(part: Node3D, frame: Transform3D, radius: float, length: float, pos: Vector3, kind := "entry") -> void:
	var mmi: MultiMeshInstance3D = part.get_meta("wounds") if part.has_meta("wounds") else null
	if mmi == null:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = _patch(radius)
		mm.instance_count = WOUNDS_PER_PART
		mm.visible_instance_count = 0
		mmi = MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = _wound_mat
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.transform = frame
		mmi.visibility_range_end = 60.0
		mmi.set_meta("n", 0)
		part.add_child(mmi)
		part.set_meta("wounds", mmi)
	var v := frame.affine_inverse() * part.to_local(pos)
	var half := maxf(length * 0.5 - radius * 0.4, 0.0)
	var xf := Transform3D(Basis(Vector3.UP, atan2(v.x, v.z)), Vector3(0.0, clampf(v.y, -half, half), 0.0))
	var cells: Array = WOUND_CELLS.get(kind, [0])
	var scale: float = {"entry": randf_range(0.85, 1.0), "exit": randf_range(1.0, 1.15), "rip": randf_range(0.9, 1.1)}.get(kind, 1.0)
	var n: int = mmi.get_meta("n")
	var i := n % WOUNDS_PER_PART
	mmi.multimesh.set_instance_transform(i, xf)
	# all in 0..1 (wound_decal.gdshader): cell / 4, -, turn, size - 0.5
	mmi.multimesh.set_instance_custom_data(i, Color(cells[randi() % cells.size()] / 4.0, 0.0, randf(), scale - 0.5))
	mmi.set_meta("n", n + 1)
	mmi.multimesh.visible_instance_count = mini(n + 1, WOUNDS_PER_PART)


## A square patch bent round a capsule of `radius` (axis Y), centred on +Z,
## standing a few mm off the cloth.
func _patch(radius: float) -> ArrayMesh:
	var key := int(round(radius * 1000.0))
	if _patches.has(key):
		return _patches[key]
	var r := radius + 0.004
	var w := WOUND_PATCH
	var arc := minf(w / r, 2.6) # wraps at most ~150 degrees
	var nx := 8
	var ny := 6
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in ny + 1:
		for i in nx + 1:
			var u := float(i) / nx
			var vv := float(j) / ny
			var a := (u - 0.5) * arc
			st.set_uv(Vector2(0.5 + (u - 0.5) * arc * r / w, vv))
			st.set_normal(Vector3(sin(a), 0.0, cos(a)))
			st.add_vertex(Vector3(sin(a) * r, (0.5 - vv) * w, cos(a) * r))
	for j in ny:
		for i in nx:
			var k := j * (nx + 1) + i
			st.add_index(k)
			st.add_index(k + 1)
			st.add_index(k + nx + 1)
			st.add_index(k + 1)
			st.add_index(k + nx + 2)
			st.add_index(k + nx + 1)
	var m := st.commit()
	_patches[key] = m
	return m


## Pool spreading under a body over `grow` seconds (stays for the round).
func pool(pos: Vector3, normal: Vector3, size: float, grow := 10.0) -> void:
	var xform := _mark_xform(pos, normal, size)
	xform.origin = pos + normal * 0.004
	_add_world(xform, CELL_POOLS[randi() % 2], randf_range(0.8, 1.0), grow)


## Smear left when something bloody slides along a surface.
func smear(pos: Vector3, normal: Vector3, along: Vector3, size: float) -> void:
	_add_world(_mark_xform(pos, normal, size, along), CELL_SMEAR, 0.9)


func bullet_hole(pos: Vector3, normal: Vector3, parent: Node3D = null) -> void:
	var xform := _mark_xform(pos, normal, randf_range(0.05, 0.07))
	if parent != null and is_instance_valid(parent) and not parent is StaticBody3D:
		var m := MeshInstance3D.new()
		m.mesh = _quad
		m.material_override = _hole_mat
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(m)
		m.global_transform = xform
		_body_holes.append(m)
		while _body_holes.size() > MAX_BODY_HOLES:
			var old = _body_holes.pop_front()
			if is_instance_valid(old):
				old.queue_free()
		return
	_hole_mm.set_instance_transform(_hole_n % MAX_WORLD_HOLES, xform)
	_hole_n += 1
	_hole_mm.visible_instance_count = mini(_hole_n, MAX_WORLD_HOLES)


# ---------------------------------------------------------------- particle bursts

## One burst from the pool of `kind` (the oldest emitter is reused):
## a fixed number of particles each, so nothing is reallocated per shot.
func _burst(kind: String, pos: Vector3, dir: Vector3, amount: int, color: Color, speed: float, spread: float,
		lifetime: float, size: float, gravity: float) -> void:
	if amount <= 0:
		return
	if not _pools.has(kind):
		var list: Array[CPUParticles3D] = []
		for i in BURST_POOL:
			var e := CPUParticles3D.new()
			e.emitting = false
			e.top_level = true
			e.mesh = _puff_mesh
			e.amount = amount
			e.lifetime = lifetime
			e.one_shot = true
			e.explosiveness = 1.0
			e.local_coords = false
			e.scale_amount_curve = _shrink_curve
			e.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(e)
			list.append(e)
		_pools[kind] = [list, 0]
	var pool: Array = _pools[kind]
	var p: CPUParticles3D = pool[0][pool[1]]
	pool[1] = (pool[1] + 1) % BURST_POOL
	p.global_position = pos
	p.direction = dir.normalized() if dir.length() > 0.01 else Vector3.UP
	p.spread = spread
	p.initial_velocity_min = speed * 0.3
	p.initial_velocity_max = speed
	p.gravity = Vector3(0, -gravity, 0)
	p.damping_min = speed * 0.3
	p.damping_max = speed * 0.8
	p.scale_amount_min = size * 0.5
	p.scale_amount_max = size * 1.4
	p.color = color
	p.restart()


## Burst of fine blood specks (bullet entry / exit).
func mist(pos: Vector3, dir: Vector3, strength := 1.0) -> void:
	# (strength makes it faster and bigger: the count is fixed per pool)
	_burst("mist", pos, dir, int(26 * Settings.blood_amount) + 6, Color(0.5, 0.01, 0.025),
			3.5 * strength, 38.0, 0.55, 0.022 * clampf(sqrt(strength), 0.7, 1.8), 7.0)


## Debris chips for non-flesh impacts.
func dust(pos: Vector3, normal: Vector3, color := Color(0.75, 0.73, 0.7)) -> void:
	_burst("dust", pos, normal, 12, color, 3.0, 35.0, 0.6, 0.02, 9.0)
