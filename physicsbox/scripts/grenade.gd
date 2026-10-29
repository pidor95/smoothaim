class_name Grenade
extends RigidBody3D
## RGD-5 hand grenade (model from Blender, tools/blender/build_explosives.py):
## bounces about on physics and goes off when its fuse burns down.

const SCENE := "res://assets/weapons/grenade.glb"

var fuse := 3.5
var by_player := false
var _clinked := false
static var _material: PhysicsMaterial


## Throws a live grenade from `from` with velocity `vel`.
static func throw(tree: SceneTree, from: Vector3, vel: Vector3, thrower_is_player: bool, fuse_time := 3.5) -> Grenade:
	var g := Grenade.new()
	g.by_player = thrower_is_player
	g.fuse = fuse_time
	tree.current_scene.add_child(g)
	g.global_position = from
	g.linear_velocity = vel
	g.angular_velocity = Vector3(randf_range(-12, 12), randf_range(-12, 12), randf_range(-12, 12))
	return g


func _ready() -> void:
	add_to_group("grenades")
	mass = 0.31
	collision_layer = 32
	collision_mask = 1 | 2 | 4
	continuous_cd = true
	linear_damp = 0.1
	angular_damp = 0.6
	if _material == null:
		_material = PhysicsMaterial.new()
		_material.bounce = 0.3
		_material.friction = 0.8
	physics_material_override = _material
	var cs := CollisionShape3D.new()
	var sh := SphereShape3D.new()
	sh.radius = 0.034
	cs.shape = sh
	add_child(cs)
	var model: Node3D = (load(SCENE) as PackedScene).instantiate()
	add_child(model)
	contact_monitor = true
	max_contacts_reported = 2
	body_entered.connect(func(_b):
		if not _clinked and linear_velocity.length() > 2.0:
			_clinked = true
			Sfx.play_3d("metal_hit", global_position, -10.0, 0.2))


func _physics_process(delta: float) -> void:
	fuse -= delta
	if fuse <= 0.0:
		Explosion.boom(get_tree(), global_position, 1.0, by_player)
		queue_free()
