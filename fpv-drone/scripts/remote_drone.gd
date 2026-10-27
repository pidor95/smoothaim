extends Node3D
## Another pilot's drone in multiplayer: smoothly follows the received state
## and shows the pilot's name above it.

const ModelScript := preload("res://scripts/drone_model.gd")
const DroneScript := preload("res://scripts/drone.gd")

var pilot_name := ""
var gate := 0

var _model: ModelScript
var _label: Label3D
var _type := -1
var _target_pos := Vector3.ZERO
var _target_rot := Quaternion.IDENTITY
var _has_state := false


func _ready() -> void:
	_model = ModelScript.new()
	_model.render_layer = 1
	# Twice the real size, so other pilots are easy to spot.
	_model.scale = Vector3.ONE * 2.0
	add_child(_model)
	_label = Label3D.new()
	_label.font = load("res://fonts/RussoOne-Regular.ttf")
	_label.font_size = 40
	_label.outline_size = 10
	_label.pixel_size = 0.0012
	_label.fixed_size = true
	_label.no_depth_test = true
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.position = Vector3(0, 0.6, 0)
	add_child(_label)
	visible = false


func apply_state(pos: Vector3, rot: Quaternion, type: int, flying: bool, new_name: String, new_gate: int) -> void:
	pilot_name = new_name
	gate = new_gate
	_label.text = new_name
	if type != _type:
		_type = clampi(type, 0, DroneScript.TYPES.size() - 1)
		var t: Dictionary = DroneScript.TYPES[_type]
		_model.restyle(t["accent"], t["arms"])
		_label.modulate = t["accent"].lightened(0.3)
	_target_pos = pos
	_target_rot = rot.normalized()
	if not _has_state:
		global_position = pos
		quaternion = _target_rot
		_has_state = true
	visible = flying


func _process(delta: float) -> void:
	if not _has_state:
		return
	var k := 1.0 - exp(-14.0 * delta)
	global_position = global_position.lerp(_target_pos, k)
	quaternion = quaternion.slerp(_target_rot, k)
	_model.update_props(delta, 0.6)
