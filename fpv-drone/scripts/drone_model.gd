extends Node3D
## Visual model of a 5-inch black X-frame quad. Uses res://models/drone.* when
## present, otherwise builds a carbon frame with motors, props and an FPV camera.

const CUSTOM_MODEL_PATHS := [
	"res://models/drone.glb", "res://models/drone.gltf",
	"res://models/drone.fbx", "res://models/drone.obj",
]
## Extra rotation for imported models whose nose does not point to -Z.
const CUSTOM_MODEL_ROTATION := Vector3(0.0, 0.0, 0.0)
## Diagonal motor-to-motor size of the model, in metres.
const TARGET_SIZE := 0.26
const MODEL_LAYER := 2

var _props: Array[Node3D] = []
var _prop_dirs: Array[float] = []
var _leds: StandardMaterial3D


func _ready() -> void:
	if not _load_custom():
		_build_default()
	_set_layer(self)


func _load_custom() -> bool:
	for path: String in CUSTOM_MODEL_PATHS:
		if not ResourceLoader.exists(path):
			continue
		var res := load(path)
		var node: Node3D = null
		if res is PackedScene:
			node = (res as PackedScene).instantiate() as Node3D
		elif res is Mesh:
			var mi := MeshInstance3D.new()
			mi.mesh = res as Mesh
			node = mi
		if node == null:
			continue
		var holder := Node3D.new()
		holder.rotation_degrees = CUSTOM_MODEL_ROTATION
		holder.add_child(node)
		add_child(holder)
		var box := _bounds(holder, Transform3D())
		var longest := maxf(box.size.x, box.size.z)
		if longest > 0.0001:
			var s := TARGET_SIZE * 1.15 / longest
			holder.scale = Vector3(s, s, s)
			holder.position = -box.get_center() * s
		return true
	return false


func _bounds(node: Node, xform: Transform3D) -> AABB:
	var box := AABB()
	var first := true
	var local := xform
	if node is Node3D:
		local = xform * (node as Node3D).transform
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		box = local * (node as MeshInstance3D).mesh.get_aabb()
		first = false
	for child in node.get_children():
		var cb := _bounds(child, local)
		if cb.size == Vector3.ZERO:
			continue
		box = cb if first else box.merge(cb)
		first = false
	return box


func _set_layer(node: Node) -> void:
	if node is VisualInstance3D:
		(node as VisualInstance3D).layers = MODEL_LAYER
	for child in node.get_children():
		_set_layer(child)


func _mat(color: Color, roughness := 0.5, metallic := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	m.metallic = metallic
	return m


func _box(size: Vector3, pos: Vector3, mat: Material, rot := Vector3.ZERO, parent: Node3D = null) -> MeshInstance3D:
	if parent == null:
		parent = self
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi


func _cyl(radius: float, height: float, pos: Vector3, mat: Material, parent: Node3D = null, segments := 16) -> MeshInstance3D:
	if parent == null:
		parent = self
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = segments
	mesh.rings = 1
	mesh.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	parent.add_child(mi)
	return mi


func _build_default() -> void:
	var carbon := _mat(Color(0.035, 0.035, 0.04), 0.35, 0.2)
	var carbon_edge := _mat(Color(0.09, 0.09, 0.1), 0.6)
	var alu := _mat(Color(0.75, 0.42, 0.12), 0.3, 0.8)
	var motor_mat := _mat(Color(0.08, 0.08, 0.09), 0.3, 0.7)
	var bell := _mat(Color(0.12, 0.12, 0.13), 0.25, 0.9)
	var tpu := _mat(Color(1.0, 0.45, 0.08), 0.7)
	var battery_mat := _mat(Color(0.1, 0.1, 0.11), 0.6)
	var label_mat := _mat(Color(0.95, 0.75, 0.1), 0.5)
	var strap_mat := _mat(Color(0.75, 0.05, 0.05), 0.8)
	var lens_mat := _mat(Color(0.02, 0.02, 0.03), 0.05, 0.6)
	var prop_mat := _mat(Color(0.05, 0.05, 0.06, 0.9), 0.4)
	_leds = StandardMaterial3D.new()
	_leds.albedo_color = Color(1.0, 0.2, 0.1)
	_leds.emission_enabled = true
	_leds.emission = Color(1.0, 0.15, 0.05)
	_leds.emission_energy_multiplier = 3.0

	# Bottom plate and arms in a true X.
	_box(Vector3(0.05, 0.004, 0.11), Vector3(0, 0, 0), carbon)
	var arm_len := TARGET_SIZE * 0.5
	for i in 4:
		var angle := deg_to_rad(45.0 + 90.0 * i)
		var dir := Vector3(sin(angle), 0.0, cos(angle))
		var arm := _box(Vector3(0.018, 0.005, arm_len), dir * arm_len * 0.5, carbon, Vector3(0.0, angle, 0.0))
		arm.position.y = -0.001
		var tip := dir * arm_len
		_cyl(0.0125, 0.012, tip + Vector3(0, 0.008, 0), motor_mat)
		_cyl(0.013, 0.008, tip + Vector3(0, 0.017, 0), bell)
		_cyl(0.0025, 0.012, tip + Vector3(0, 0.025, 0), alu, self, 8)
		var prop := Node3D.new()
		prop.position = tip + Vector3(0, 0.024, 0)
		add_child(prop)
		for b in 3:
			var pivot := Node3D.new()
			pivot.rotation.y = TAU * b / 3.0
			prop.add_child(pivot)
			_box(Vector3(0.062, 0.0015, 0.011), Vector3(0.031, 0, 0), prop_mat, Vector3(0.12, 0.0, 0.0), pivot)
		_props.append(prop)
		_prop_dirs.append(1.0 if i % 2 == 0 else -1.0)
		# Small arm guards, as on many freestyle frames.
		_box(Vector3(0.006, 0.012, 0.022), tip + dir * 0.008 + Vector3(0, -0.006, 0), tpu, Vector3(0.0, angle, 0.0))

	# Standoffs, top plate and stack.
	for sx: float in [-0.018, 0.018]:
		for sz: float in [-0.035, 0.035]:
			_cyl(0.0025, 0.026, Vector3(sx, 0.014, sz), alu, self, 8)
	_box(Vector3(0.04, 0.003, 0.09), Vector3(0, 0.028, 0), carbon_edge)
	_box(Vector3(0.03, 0.012, 0.03), Vector3(0, 0.012, 0.0), _mat(Color(0.05, 0.25, 0.12), 0.5))

	# Battery strapped on top.
	_box(Vector3(0.036, 0.03, 0.075), Vector3(0, 0.046, 0.008), battery_mat)
	_box(Vector3(0.037, 0.012, 0.03), Vector3(0, 0.05, 0.012), label_mat)
	_box(Vector3(0.042, 0.033, 0.012), Vector3(0, 0.045, -0.015), strap_mat)
	_box(Vector3(0.042, 0.033, 0.012), Vector3(0, 0.045, 0.03), strap_mat)

	# FPV camera in an orange TPU mount at the front, tilted up.
	var cam := Node3D.new()
	cam.position = Vector3(0, 0.014, -0.05)
	cam.rotation_degrees = Vector3(20.0, 0.0, 0.0)
	add_child(cam)
	_box(Vector3(0.024, 0.022, 0.022), Vector3.ZERO, carbon_edge, Vector3.ZERO, cam)
	_box(Vector3(0.004, 0.026, 0.02), Vector3(-0.015, 0, 0), tpu, Vector3.ZERO, cam)
	_box(Vector3(0.004, 0.026, 0.02), Vector3(0.015, 0, 0), tpu, Vector3.ZERO, cam)
	var lens := _cyl(0.008, 0.012, Vector3(0, 0, -0.016), lens_mat, cam, 12)
	lens.rotation_degrees = Vector3(90.0, 0.0, 0.0)

	# Video antenna at the back and a rear LED strip.
	var antenna := _cyl(0.002, 0.06, Vector3(0, 0.05, 0.055), carbon_edge, self, 6)
	antenna.rotation_degrees = Vector3(-35.0, 0.0, 0.0)
	var cap := _cyl(0.007, 0.018, Vector3(0, 0.077, 0.075), tpu, self, 10)
	cap.rotation_degrees = Vector3(-35.0, 0.0, 0.0)
	_box(Vector3(0.03, 0.004, 0.004), Vector3(0, 0.004, 0.056), _leds)


## Spins the props; throttle is 0..1.
func update_props(delta: float, throttle: float) -> void:
	var speed := 30.0 + throttle * 90.0
	for i in _props.size():
		_props[i].rotate_y(_prop_dirs[i] * speed * delta)
