extends RefCounted
## Procedural models built from primitives: assault-point fortifications (bunker, ZU-23-2 AA gun, ammo depot)
## and the blue airbase buildings. Models face -Z with the origin on the ground, like the vehicle models.
## Moving parts use the same node names the vehicles use: "Turret" (yaw) > "Gun" (pitch).

static var _mats := {}


static func mat(key: String, col: Color, rough := 0.85, tex := "", uv := 1.0, metal := 0.0) -> StandardMaterial3D:
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	m.metallic = metal
	if tex != "":
		m.albedo_texture = load(tex)
		m.uv1_triplanar = true
		m.uv1_world_triplanar = true
		m.uv1_scale = Vector3.ONE * uv
	_mats[key] = m
	return m


static func concrete() -> StandardMaterial3D:
	return mat("concrete", Color(0.72, 0.71, 0.68), 0.9, "res://assets/textures/Gravel023_color.jpg", 0.12)


static func earth() -> StandardMaterial3D:
	return mat("earth", Color(0.62, 0.55, 0.42), 1.0, "res://assets/textures/Ground048_color.jpg", 0.15)


static func olive() -> StandardMaterial3D:
	return mat("olive", Color(0.3, 0.34, 0.2), 0.7, "", 1.0, 0.2)


static func sandbag() -> StandardMaterial3D:
	return mat("sandbag", Color(0.66, 0.6, 0.45), 1.0, "res://assets/textures/Ground054_color.jpg", 0.6)


static func dark() -> StandardMaterial3D:
	return mat("dark", Color(0.05, 0.05, 0.05), 1.0)


static func steel() -> StandardMaterial3D:
	return mat("steel", Color(0.18, 0.19, 0.2), 0.45, "", 1.0, 0.7)


static func box(parent: Node3D, size: Vector3, p: Vector3, m: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = m
	mi.position = p
	mi.rotation = rot
	parent.add_child(mi)
	return mi


static func cyl(parent: Node3D, r_top: float, r_bot: float, h: float, p: Vector3, m: Material, rot := Vector3.ZERO, seg := 16) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r_top
	cm.bottom_radius = r_bot
	cm.height = h
	cm.radial_segments = seg
	cm.rings = 1
	mi.mesh = cm
	mi.material_override = m
	mi.position = p
	mi.rotation = rot
	parent.add_child(mi)
	return mi


## A ring of sandbags (two rows of boxes) with a gap facing -Z.
static func sandbags(parent: Node3D, r: float, gap := 0.6) -> void:
	var n := int(TAU * r / 0.9)
	for row in 2:
		for i in n:
			var a := (i + row * 0.5) / n * TAU
			if absf(angle_difference(a, PI / 2)) < gap:
				continue
			var q := Vector3(cos(a) * r, 0.2 + row * 0.36, -sin(a) * r)
			box(parent, Vector3(0.9, 0.36, 0.5), q, sandbag(), Vector3(0, a + PI / 2, 0))


static func build(kind: String) -> Node3D:
	var root := Node3D.new()
	match kind:
		"bunker": _bunker(root)
		"zu23": _zu23(root)
		"depot": _depot(root)
	return root


static func _bunker(root: Node3D) -> void:
	# earth mound around a concrete pillbox, firing slit facing -Z
	cyl(root, 5.4, 8.0, 2.4, Vector3(0, 0.9, 0.6), earth(), Vector3.ZERO, 20)
	box(root, Vector3(7.0, 2.6, 5.4), Vector3(0, 1.3, 0), concrete())
	box(root, Vector3(8.2, 0.6, 6.6), Vector3(0, 2.85, 0), concrete())
	box(root, Vector3(3.6, 0.42, 0.4), Vector3(0, 1.75, -2.6), dark())
	box(root, Vector3(1.4, 0.3, 0.4), Vector3(-2.6, 1.75, -2.6), dark())
	box(root, Vector3(1.4, 0.3, 0.4), Vector3(2.6, 1.75, -2.6), dark())
	box(root, Vector3(1.2, 1.9, 0.6), Vector3(2.2, 0.95, 2.9), dark())
	# a gun barrel poking out of the slit
	cyl(root, 0.05, 0.06, 1.2, Vector3(0, 1.75, -3.0), steel(), Vector3(PI / 2, 0, 0), 8)
	for s in [-1.0, 1.0]:
		for k in 3:
			box(root, Vector3(0.9, 0.36, 0.5), Vector3(s * (4.6 + k * 0.1), 0.2 + k * 0.34, -3.6 + k * 0.2), sandbag(), Vector3(0, s * 0.5, 0))
	var flag := Node3D.new()
	root.add_child(flag)
	cyl(flag, 0.04, 0.05, 5.0, Vector3(-3.0, 5.4, 1.5), steel(), Vector3.ZERO, 6)
	box(flag, Vector3(1.6, 1.0, 0.04), Vector3(-2.15, 7.3, 1.5), mat("redflag", Color(0.75, 0.08, 0.06), 0.9))


static func _zu23(root: Node3D) -> void:
	sandbags(root, 3.4, 0.5)
	# folded travel wheels and the base
	box(root, Vector3(1.9, 0.32, 3.4), Vector3(0, 0.45, 0), olive())
	for s in [-1.0, 1.0]:
		cyl(root, 0.45, 0.45, 0.28, Vector3(s * 1.15, 0.45, 0.3), mat("tyre", Color(0.06, 0.06, 0.06), 0.95), Vector3(0, 0, PI / 2))
		box(root, Vector3(0.3, 0.2, 1.4), Vector3(s * 1.4, 0.2, -1.2), olive(), Vector3(0, s * 0.5, 0))
	var turret := Node3D.new()
	turret.name = "Turret"
	turret.position = Vector3(0, 0.62, 0)
	root.add_child(turret)
	cyl(turret, 0.55, 0.65, 0.2, Vector3(0, 0.1, 0), olive())
	box(turret, Vector3(1.3, 0.55, 1.1), Vector3(0, 0.45, 0.15), olive())
	for s in [-1.0, 1.0]:
		box(turret, Vector3(0.36, 0.08, 0.36), Vector3(s * 0.75, 0.55, 0.75), dark())
		box(turret, Vector3(0.36, 0.5, 0.08), Vector3(s * 0.75, 0.8, 0.95), dark())
	var gun := Node3D.new()
	gun.name = "Gun"
	gun.position = Vector3(0, 0.62, 0)
	turret.add_child(gun)
	box(gun, Vector3(0.62, 0.34, 1.5), Vector3(0, 0.0, -0.1), olive())
	for s in [-1.0, 1.0]:
		cyl(gun, 0.045, 0.06, 2.6, Vector3(s * 0.17, 0.05, -2.0), steel(), Vector3(PI / 2, 0, 0), 8)
		cyl(gun, 0.07, 0.07, 0.35, Vector3(s * 0.17, 0.05, -3.2), steel(), Vector3(PI / 2, 0, 0), 8)
		box(gun, Vector3(0.28, 0.42, 0.5), Vector3(s * 0.48, 0.05, 0.1), mat("ammo", Color(0.25, 0.29, 0.17), 0.7))


static func _depot(root: Node3D) -> void:
	box(root, Vector3(14, 0.2, 11), Vector3(0, 0.05, 0), concrete())
	# canvas tent over crates, stacks of ammunition boxes and fuel barrels around it
	var tent := MeshInstance3D.new()
	var pm := PrismMesh.new()
	pm.size = Vector3(6.5, 3.0, 8.0)
	tent.mesh = pm
	tent.material_override = mat("canvas", Color(0.33, 0.37, 0.24), 0.95)
	tent.position = Vector3(-2.5, 1.6, 0)
	root.add_child(tent)
	var crate := mat("crate", Color(0.42, 0.4, 0.24), 0.8)
	var wood := mat("wood", Color(0.5, 0.38, 0.24), 0.9)
	for k in 9:
		var x := 2.0 + (k % 3) * 1.3
		var z := -3.0 + (k / 3) * 1.0
		for h in 1 + (k * 7) % 3:
			box(root, Vector3(1.2, 0.55, 0.85), Vector3(x, 0.45 + h * 0.56, z), crate if (k + h) % 2 else wood)
	for k in 6:
		cyl(root, 0.3, 0.3, 0.9, Vector3(3.0 + (k % 3) * 0.66, 0.6, 2.6 + (k / 3) * 0.66), mat("barrel", Color(0.45, 0.16, 0.1), 0.6, "", 1.0, 0.3), Vector3.ZERO, 10)
	sandbags(root, 7.6, 0.35)
