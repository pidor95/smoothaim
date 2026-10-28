class_name Door
extends RigidBody3D
## Hinged physics door. The leaf and its pre-fractured chunks are modelled in
## Blender (tools/blender/build_door.py). Bullets pass through it (the gun
## handles penetration) and enough damage splinters it into pieces.

const PATH := "res://assets/props/door.glb"
const MODEL_WIDTH := 0.84
## Fraction of a bullet's power the leaf eats when it is shot through.
const PENETRATION_COST := 0.3

static var _leaf_mesh: Mesh
static var _frags: Array = [] # [mesh, offset]

var width := MODEL_WIDTH
var height := 2.07
var hp := 120.0
var joint: Joint3D
var _sx := 1.0


static func _load() -> void:
	if _leaf_mesh:
		return
	var scene: Node = load(PATH).instantiate()
	for mi in scene.find_children("*", "MeshInstance3D", true, false):
		if mi.name == "door":
			_leaf_mesh = mi.mesh
		else:
			_frags.append([mi.mesh, mi.position])
	scene.free()


func _ready() -> void:
	_load()
	_sx = width / MODEL_WIDTH
	mass = 16.0
	angular_damp = 2.5
	collision_layer = 2
	collision_mask = 1 | 2 | 4
	set_meta("surface", "wood")
	set_meta("penetration", PENETRATION_COST)
	var mi := MeshInstance3D.new()
	mi.mesh = _leaf_mesh
	mi.scale = Vector3(_sx, height / 2.11, 1.0)
	add_child(mi)
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(width, height, 0.05)
	cs.shape = sh
	add_child(cs)


## A bullet went through at `pos`.
func take_bullet(pos: Vector3, dir: Vector3, damage: float) -> void:
	hp -= damage
	apply_impulse(dir * (1.5 + damage * 0.12), pos - global_position)
	if hp <= 0.0:
		shatter(pos, dir)


func shatter(pos: Vector3, dir: Vector3) -> void:
	if is_queued_for_deletion():
		return
	if is_instance_valid(joint):
		joint.queue_free()
	var root := get_tree().current_scene
	var scale_v := Vector3(_sx, height / 2.11, 1.0)
	for f in _frags:
		var mesh: Mesh = f[0]
		var offset: Vector3 = f[1] * scale_v
		var b := RigidBody3D.new()
		b.mass = 1.4
		b.collision_layer = 2
		b.collision_mask = 1 | 2 | 4
		b.angular_damp = 0.6
		b.set_meta("surface", "wood")
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.scale = scale_v
		b.add_child(mi)
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = (mesh.get_aabb().size * scale_v).max(Vector3.ONE * 0.03)
		cs.shape = sh
		cs.position = mesh.get_aabb().get_center() * scale_v
		b.add_child(cs)
		root.add_child(b)
		b.global_transform = global_transform * Transform3D(Basis.IDENTITY, offset)
		var near := 1.0 - clampf(b.global_position.distance_to(pos) / 1.2, 0.0, 1.0)
		b.linear_velocity = linear_velocity + dir * randf_range(1.0, 2.5) * (0.4 + near) \
				+ Vector3(randf_range(-0.6, 0.6), randf_range(0.0, 1.2), randf_range(-0.6, 0.6))
		b.angular_velocity = Vector3(randf_range(-6, 6), randf_range(-6, 6), randf_range(-6, 6))
	for i in 5:
		Blood.dust(pos + Vector3(randf_range(-0.3, 0.3), randf_range(-0.6, 0.6), 0), dir, Color(0.75, 0.6, 0.4))
	Sfx.play_3d("wood_break", pos, 2.0, 0.1)
	queue_free()
