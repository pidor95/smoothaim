class_name MannequinAnims
extends RefCounted
## Animation library authored in Blender (tools/blender/build_mannequin_anims.py).
## Loaded once; NPCs sample and blend the clips themselves and place their
## rigid body parts from the resulting bone transforms.

const BONES := ["pelvis", "chest", "head", "uarm_l", "farm_l", "uarm_r", "farm_r",
		"thigh_l", "shin_l", "thigh_r", "shin_r"]
const PATH := "res://assets/npc/mannequin_anims.glb"

static var _lib: MannequinAnims

var parent := PackedInt32Array()
var rest_local: Array[Transform3D] = []
var rest_rot: Array[Quaternion] = []
var rest_global: Array[Transform3D] = []
var rest_global_inv: Array[Transform3D] = []
var clips := {}


class Clip:
	var anim: Animation
	var length := 1.0
	var rot := PackedInt32Array()
	var pos := -1


static func get_lib() -> MannequinAnims:
	if _lib == null:
		_lib = MannequinAnims.new()
		_lib._load()
	return _lib


func _load() -> void:
	var scene: Node = load(PATH).instantiate()
	var sk: Skeleton3D = scene.find_children("*", "Skeleton3D", true, false)[0]
	for b in BONES:
		var idx := sk.find_bone(b)
		var rest := sk.get_bone_rest(idx)
		rest_local.append(rest)
		rest_rot.append(rest.basis.get_rotation_quaternion())
		var p := sk.get_bone_parent(idx)
		parent.append(BONES.find(sk.get_bone_name(p)) if p >= 0 else -1)
	for i in BONES.size():
		var g := rest_local[i]
		if parent[i] >= 0:
			g = rest_global[parent[i]] * g
		rest_global.append(g)
		rest_global_inv.append(g.affine_inverse())
	var ap: AnimationPlayer = scene.find_children("*", "AnimationPlayer", true, false)[0]
	for name in ap.get_animation_list():
		var a := ap.get_animation(name)
		var c := Clip.new()
		c.anim = a
		c.length = a.length
		c.rot.resize(BONES.size())
		c.rot.fill(-1)
		for t in a.get_track_count():
			var bone := String(a.track_get_path(t)).get_slice(":", 1)
			var bi := BONES.find(bone)
			if bi < 0:
				continue
			match a.track_get_type(t):
				Animation.TYPE_ROTATION_3D:
					c.rot[bi] = t
				Animation.TYPE_POSITION_3D:
					if bi == 0:
						c.pos = t
		clips[name] = c
	scene.free()


## A missing clip falls back to the idle (an error once, not a soldier
## stuck sampling nothing every frame).
func clip(name: String) -> Clip:
	if not clips.has(name):
		push_error("no mannequin clip '%s'" % name)
		clips[name] = clips["idle"]
	return clips[name]


func rot(c: Clip, bone: int, t: float) -> Quaternion:
	var tr := c.rot[bone]
	if tr < 0:
		return rest_rot[bone]
	return c.anim.rotation_track_interpolate(tr, clampf(t, 0.0, c.length))


func pelvis_pos(c: Clip, t: float) -> Vector3:
	if c.pos < 0:
		return rest_local[0].origin
	return c.anim.position_track_interpolate(c.pos, clampf(t, 0.0, c.length))
