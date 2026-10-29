class_name Grenade
extends RigidBody3D
## RGD-5 hand grenade (model from Blender, tools/blender/build_explosives.py):
## bounces about on physics and goes off when its fuse burns down. The F-1s
## the drop drone lets go of (`impact`) go off when they hit something.

const SCENE := "res://assets/weapons/grenade.glb"

var fuse := 3.5
var by_player := false
var impact := false # goes off on the first hit (dropped from a drone)
var scene_path := SCENE
var power := 1.0
var _age := 0.0
var _clinked := false
static var _material: PhysicsMaterial


## Throws a live grenade from `from` with velocity `vel`.
static func throw(tree: SceneTree, from: Vector3, vel: Vector3, thrower_is_player: bool, fuse_time := 3.5,
		scene := "", on_impact := false) -> Grenade:
	var g := Grenade.new()
	g.by_player = thrower_is_player
	g.fuse = fuse_time
	g.impact = on_impact
	if scene != "":
		g.scene_path = scene
		g.power = 1.25 # the F-1: a heavier charge and far more fragments
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
	sh.radius = 0.034 if scene_path == SCENE else 0.03
	cs.shape = sh
	add_child(cs)
	var model: Node3D = (load(scene_path) as PackedScene).instantiate()
	add_child(model)
	contact_monitor = true
	max_contacts_reported = 2
	body_entered.connect(func(_b):
		if impact and _age > 0.1:
			fuse = 0.0
		elif not _clinked and linear_velocity.length() > 2.0:
			_clinked = true
			Sfx.play_3d("metal_hit", global_position, -10.0, 0.2))


func _physics_process(delta: float) -> void:
	fuse -= delta
	_age += delta
	if fuse <= 0.0:
		Explosion.boom(get_tree(), global_position, power, by_player)
		queue_free()
