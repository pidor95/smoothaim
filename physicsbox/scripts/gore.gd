class_name Gore
extends RefCounted
## Physical gore pieces (skull fragments, brain, eyes, organs, flesh chunks)
## built in Blender (tools/blender/build_gibs.py). Pieces are small rigid
## bodies that bounce around, leave blood where they land and are recycled.

const PATH := "res://assets/npc/gibs.glb"
const MAX_PIECES := 80
const LAYER_DEBRIS := 32

static var _meshes := {}
static var _shapes := {}
static var _live: Array[RigidBody3D] = []


static func _load() -> void:
	if not _meshes.is_empty():
		return
	var scene: Node = load(PATH).instantiate()
	for mi in scene.find_children("*", "MeshInstance3D", true, false):
		var m: Mesh = mi.mesh
		_meshes[String(mi.name)] = m
		var aabb := m.get_aabb()
		var sh := BoxShape3D.new()
		sh.size = (aabb.size * 0.85).max(Vector3.ONE * 0.015)
		_shapes[String(mi.name)] = [sh, aabb.get_center()]
	scene.free()


static func mesh(piece: String) -> Mesh:
	_load()
	return _meshes[piece]


## Throws one piece. `skin` replaces surface 0 (skull fragments use it for skin).
static func spawn(piece: String, xform: Transform3D, vel: Vector3, skin: Material = null, mass := 0.15) -> RigidBody3D:
	_load()
	var tree := Engine.get_main_loop() as SceneTree
	var root := tree.current_scene
	if root == null or not _meshes.has(piece):
		return null
	var b := RigidBody3D.new()
	b.mass = mass
	b.collision_layer = LAYER_DEBRIS
	b.collision_mask = 1 | 2
	b.linear_damp = 0.15
	b.angular_damp = 0.8
	b.set_meta("surface", "flesh")
	var mi := MeshInstance3D.new()
	mi.mesh = _meshes[piece]
	if skin:
		mi.set_surface_override_material(0, skin)
	b.add_child(mi)
	var cs := CollisionShape3D.new()
	cs.shape = _shapes[piece][0]
	cs.position = _shapes[piece][1]
	b.add_child(cs)
	b.contact_monitor = true
	b.max_contacts_reported = 1
	root.add_child(b)
	b.global_transform = xform
	b.linear_velocity = vel
	b.angular_velocity = Vector3(randf_range(-12, 12), randf_range(-12, 12), randf_range(-12, 12))
	var marks := {"n": 0}
	b.body_entered.connect(func(_other):
		if marks.n < 2 and b.linear_velocity.length() > 1.0:
			marks.n += 1
			Blood.splat(b.global_position + Vector3.DOWN * 0.02, Vector3.UP, randf_range(0.12, 0.28))
	)
	_live.append(b)
	while _live.size() > MAX_PIECES:
		var old: RigidBody3D = _live.pop_front()
		if is_instance_valid(old):
			old.queue_free()
	return b


## Burst of blocky flesh chunks flying out along `dir`.
static func chunks(pos: Vector3, dir: Vector3, count: int, speed := 4.0) -> void:
	for i in count:
		var d := (dir + Vector3(randf_range(-0.7, 0.7), randf_range(-0.2, 0.9), randf_range(-0.7, 0.7))).normalized()
		spawn("chunk_%d" % (randi() % 3), Transform3D(Basis.from_euler(Vector3(randf(), randf(), randf()) * TAU), pos),
				d * randf_range(speed * 0.4, speed), null, 0.08)


static func clear() -> void:
	for b in _live:
		if is_instance_valid(b):
			b.queue_free()
	_live.clear()
