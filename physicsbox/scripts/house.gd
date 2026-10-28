class_name House
extends Node3D
## Level "House": a one-storey house with five rooms, physics furniture,
## breakable windows, hinged doors, a yard and a rooftop reached by stairs.
## Everything is generated in code and a navigation mesh is baked at load.

const H := 3.0 # wall height
const T := 0.2 # wall thickness
const DOOR_H := 2.15
const WIN_BOTTOM := 1.0
const WIN_TOP := 2.2

var player_spawn := Transform3D(Basis(Vector3.UP, PI), Vector3(-2.5, 0.05, -11.0))
var npc_spawns: Array[Vector3] = [
	Vector3(-4.5, 0.05, -3.0), Vector3(-2.0, 0.05, -4.0), Vector3(4.5, 0.05, -3.8),
	Vector3(-4.0, 0.05, 2.6), Vector3(5.5, 0.05, 3.0), Vector3(-6.0, 0.05, -12.0),
	Vector3(6.0, 0.05, -12.0), Vector3(14.0, 0.05, 2.0), Vector3(-14.0, 0.05, 4.0),
]

var nav_region := NavigationRegion3D.new()
var geo := Node3D.new()
var props_root := Node3D.new()
var mats := {}


func _ready() -> void:
	nav_region.name = "Navigation"
	add_child(nav_region)
	geo.name = "Geometry"
	nav_region.add_child(geo)
	props_root.name = "Props"
	add_child(props_root)
	_make_materials()
	_build_ground()
	_build_house()
	_build_furniture()
	_build_yard()
	_bake_navigation()


# ------------------------------------------------------------------ helpers

func _tex_mat(color: Color, tex: String, uv_scale: float, roughness := 0.85) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	if tex != "":
		m.albedo_texture = load(tex)
		m.uv1_triplanar = true
		m.uv1_world_triplanar = true
		m.uv1_scale = Vector3.ONE * uv_scale
	return m


func _make_materials() -> void:
	mats.ground = _tex_mat(Color(0.74, 0.72, 0.69), "res://assets/textures/concrete.png", 0.12, 0.95)
	mats.ext_wall = _tex_mat(Color(0.78, 0.78, 0.77), "res://assets/textures/concrete.png", 0.35)
	mats.int_wall = _tex_mat(Color(0.9, 0.88, 0.84), "res://assets/textures/concrete.png", 0.5, 0.9)
	mats.ceiling = _tex_mat(Color(0.86, 0.86, 0.86), "", 1.0)
	mats.roof = _tex_mat(Color(0.56, 0.56, 0.56), "res://assets/textures/concrete.png", 0.3)
	mats.wood_floor = _tex_mat(Color(0.62, 0.45, 0.3), "res://assets/textures/wood.png", 0.45, 0.6)
	mats.tiles = _tex_mat(Color(0.86, 0.87, 0.88), "res://assets/textures/tiles.png", 0.6, 0.3)
	mats.garage_floor = _tex_mat(Color(0.5, 0.5, 0.5), "res://assets/textures/concrete.png", 0.4)
	mats.wood = _tex_mat(Color(0.5, 0.33, 0.2), "res://assets/textures/wood.png", 1.2, 0.7)
	mats.dark_wood = _tex_mat(Color(0.3, 0.2, 0.13), "res://assets/textures/wood.png", 1.2, 0.7)
	mats.light_wood = _tex_mat(Color(0.78, 0.62, 0.42), "res://assets/textures/wood.png", 1.2, 0.7)
	mats.fabric_grey = _tex_mat(Color(0.32, 0.34, 0.38), "", 1.0, 1.0)
	mats.rug = _tex_mat(Color(0.72, 0.68, 0.6), "", 1.0, 1.0)
	mats.white = _tex_mat(Color(0.93, 0.93, 0.93), "", 1.0, 0.35)
	mats.metal = _tex_mat(Color(0.75, 0.76, 0.78), "", 1.0, 0.35)
	mats.metal.metallic = 0.6
	mats.black = _tex_mat(Color(0.04, 0.04, 0.045), "", 1.0, 0.4)
	mats.screen = _tex_mat(Color(0.02, 0.025, 0.035), "", 1.0, 0.1)
	mats.cardboard = _tex_mat(Color(0.66, 0.5, 0.32), "", 1.0, 0.95)
	mats.red_paint = _tex_mat(Color(0.65, 0.06, 0.05), "", 1.0, 0.3)
	mats.red_paint.metallic = 0.4
	mats.blue_barrel = _tex_mat(Color(0.12, 0.25, 0.55), "", 1.0, 0.5)
	mats.green = _tex_mat(Color(0.2, 0.38, 0.18), "", 1.0, 0.9)
	mats.bark = _tex_mat(Color(0.32, 0.23, 0.16), "", 1.0, 0.95)
	mats.lamp = StandardMaterial3D.new()
	mats.lamp.albedo_color = Color(1, 0.95, 0.85)
	mats.lamp.emission_enabled = true
	mats.lamp.emission = Color(1, 0.9, 0.75)
	mats.lamp.emission_energy_multiplier = 2.0


func _mesh_box(size: Vector3) -> BoxMesh:
	var bm := BoxMesh.new()
	bm.size = size
	return bm


## Static box with collision (part of the navigation source geometry).
func box(center: Vector3, size: Vector3, mat: Material, surface := "concrete", parent: Node = null) -> StaticBody3D:
	var b := StaticBody3D.new()
	b.position = center
	b.set_meta("surface", surface)
	(parent if parent else geo).add_child(b)
	var mi := MeshInstance3D.new()
	mi.mesh = _mesh_box(size)
	mi.material_override = mat
	b.add_child(mi)
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	b.add_child(cs)
	return b


## Visual-only box.
func deco(center: Vector3, size: Vector3, mat: Material, parent: Node = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _mesh_box(size)
	mi.material_override = mat
	mi.position = center
	(parent if parent else geo).add_child(mi)
	return mi


## Physics prop built from boxes / cylinders.
## parts: [[offset, size, material, shape("box"|"cyl")], ...]; cylinder size = (radius, height, 0)
func prop(pos: Vector3, parts: Array, mass: float, surface := "wood", rot_y := 0.0) -> RigidBody3D:
	var b := RigidBody3D.new()
	b.mass = mass
	b.collision_layer = 2
	b.collision_mask = 1 | 2 | 4
	b.set_meta("surface", surface)
	b.position = pos
	b.rotation.y = rot_y
	b.angular_damp = 0.4
	for p in parts:
		var offset: Vector3 = p[0]
		var size: Vector3 = p[1]
		var mi := MeshInstance3D.new()
		var cs := CollisionShape3D.new()
		if p.size() > 3 and p[3] == "cyl":
			var cm := CylinderMesh.new()
			cm.top_radius = size.x
			cm.bottom_radius = size.x
			cm.height = size.y
			cm.radial_segments = 16
			mi.mesh = cm
			var sh := CylinderShape3D.new()
			sh.radius = size.x
			sh.height = size.y
			cs.shape = sh
		else:
			mi.mesh = _mesh_box(size)
			var sh := BoxShape3D.new()
			sh.size = size
			cs.shape = sh
		mi.material_override = p[2]
		mi.position = offset
		cs.position = offset
		b.add_child(mi)
		b.add_child(cs)
	props_root.add_child(b)
	return b


## Axis-aligned wall from a to b (x/z plane) with openings
## [from, to, bottom, top, kind] measured along the wall; kind: "window", "door", "hole".
func wall(a: Vector2, b: Vector2, openings: Array, mat: Material, height := H, y0 := 0.0) -> void:
	var horizontal := absf(a.y - b.y) < 0.001
	var start := minf(a.x, b.x) if horizontal else minf(a.y, b.y)
	var end := maxf(a.x, b.x) if horizontal else maxf(a.y, b.y)
	var fixed := a.y if horizontal else a.x
	openings.sort_custom(func(p, q): return p[0] < q[0])
	var cursor := start
	for o in openings:
		if o[0] > cursor:
			_wall_seg(horizontal, fixed, cursor, o[0], y0, y0 + height, mat)
		if o[2] > 0.0:
			_wall_seg(horizontal, fixed, o[0], o[1], y0, y0 + o[2], mat)
		if o[3] < height:
			_wall_seg(horizontal, fixed, o[0], o[1], y0 + o[3], y0 + height, mat)
		match o[4]:
			"window":
				_window(horizontal, fixed, o[0], o[1], y0 + o[2], y0 + o[3])
			"door":
				_door(horizontal, fixed, o[0], o[1])
		cursor = o[1]
	if cursor < end:
		_wall_seg(horizontal, fixed, cursor, end, y0, y0 + height, mat)


func _wall_seg(horizontal: bool, fixed: float, s: float, e: float, y0: float, y1: float, mat: Material) -> void:
	var along := (s + e) * 0.5
	var length := e - s
	if length <= 0.001 or y1 - y0 <= 0.001:
		return
	if horizontal:
		box(Vector3(along, (y0 + y1) * 0.5, fixed), Vector3(length, y1 - y0, T), mat)
	else:
		box(Vector3(fixed, (y0 + y1) * 0.5, along), Vector3(T, y1 - y0, length), mat)


func _window(horizontal: bool, fixed: float, s: float, e: float, y0: float, y1: float) -> void:
	var along := (s + e) * 0.5
	var pane := GlassPane.new()
	pane.size = Vector3(e - s - 0.02, y1 - y0 - 0.02, 0.02)
	pane.position = Vector3(along, (y0 + y1) * 0.5, fixed) if horizontal else Vector3(fixed, (y0 + y1) * 0.5, along)
	if not horizontal:
		pane.rotation.y = PI / 2
	add_child(pane) # not navigation geometry
	# sill
	var sill := Vector3(e - s + 0.1, 0.05, T + 0.12)
	if not horizontal:
		sill = Vector3(T + 0.12, 0.05, e - s + 0.1)
	deco(Vector3(pane.position.x, y0 - 0.025, pane.position.z), sill, mats.white)


func _door(horizontal: bool, fixed: float, s: float, e: float) -> void:
	var leaf := Door.new()
	leaf.width = e - s - 0.06
	leaf.height = DOOR_H - 0.04
	var along := (s + e) * 0.5
	leaf.position = Vector3(along, DOOR_H * 0.5 + 0.01, fixed) if horizontal else Vector3(fixed, DOOR_H * 0.5 + 0.01, along)
	if not horizontal:
		leaf.rotation.y = PI / 2
	add_child(leaf)
	var hinge_local := Vector3(-leaf.width * 0.5, 0, 0)
	var joint := HingeJoint3D.new()
	add_child(joint)
	joint.global_transform = Transform3D(Basis(Vector3.RIGHT, -PI / 2), leaf.global_transform * hinge_local)
	joint.set_flag(HingeJoint3D.FLAG_USE_LIMIT, true)
	joint.set_param(HingeJoint3D.PARAM_LIMIT_LOWER, deg_to_rad(-95))
	joint.set_param(HingeJoint3D.PARAM_LIMIT_UPPER, deg_to_rad(95))
	joint.node_b = joint.get_path_to(leaf)
	leaf.joint = joint


func _light(pos: Vector3, energy := 0.7, light_range := 7.0) -> void:
	var l := OmniLight3D.new()
	l.position = pos
	l.light_color = Color(1.0, 0.88, 0.72)
	l.light_energy = energy
	l.omni_range = light_range
	l.shadow_enabled = false
	add_child(l)
	deco(pos + Vector3(0, 0.22, 0), Vector3(0.5, 0.06, 0.5), mats.lamp, self)


# ------------------------------------------------------------------ level

func _build_ground() -> void:
	box(Vector3(0, -0.52, 0), Vector3(140, 1.0, 140), mats.ground)
	# driveway
	deco(Vector3(10.5, -0.012, -11.0), Vector3(4.0, 0.02, 10.0), mats.garage_floor)
	# path to the front door
	deco(Vector3(-2.5, -0.012, -9.0), Vector3(1.6, 0.02, 6.0), mats.garage_floor)


func _build_house() -> void:
	# floors (top at y = 0)
	box(Vector3(-3.5, -0.05, -2.5), Vector3(9.0, 0.1, 7.0), mats.wood_floor, "wood") # living
	box(Vector3(4.5, -0.05, -2.5), Vector3(7.0, 0.1, 7.0), mats.tiles) # kitchen
	box(Vector3(-4.5, -0.05, 3.5), Vector3(7.0, 0.1, 5.0), mats.wood_floor, "wood") # bedroom
	box(Vector3(1.0, -0.05, 3.5), Vector3(4.0, 0.1, 5.0), mats.tiles) # bathroom
	box(Vector3(5.5, -0.05, 3.5), Vector3(5.0, 0.1, 5.0), mats.garage_floor) # garage

	# exterior walls
	wall(Vector2(-8.1, -6), Vector2(8.1, -6), [
		[-7.0, -5.6, WIN_BOTTOM, WIN_TOP, "window"],
		[-3.0, -2.0, 0.0, DOOR_H, "door"],
		[-1.2, 0.2, WIN_BOTTOM, WIN_TOP, "window"],
		[2.6, 4.0, WIN_BOTTOM, WIN_TOP, "window"],
		[5.0, 6.4, WIN_BOTTOM, WIN_TOP, "window"],
	], mats.ext_wall)
	wall(Vector2(-8.1, 6), Vector2(8.1, 6), [
		[-4.6, -3.2, WIN_BOTTOM, WIN_TOP, "window"],
		[0.4, 1.2, 1.5, 2.1, "window"],
		[4.3, 7.0, 0.0, 2.5, "hole"],
	], mats.ext_wall)
	wall(Vector2(-8, -6), Vector2(-8, 6), [
		[-3.2, -1.8, WIN_BOTTOM, WIN_TOP, "window"],
		[2.8, 4.2, WIN_BOTTOM, WIN_TOP, "window"],
	], mats.ext_wall)
	wall(Vector2(8, -6), Vector2(8, 6), [
		[-3.6, -2.2, WIN_BOTTOM, WIN_TOP, "window"],
		[2.2, 3.4, 1.2, 2.2, "window"],
	], mats.ext_wall)

	# interior walls
	wall(Vector2(-7.9, 1), Vector2(7.9, 1), [
		[-4.0, -3.1, 0.0, DOOR_H, "door"],
		[0.0, 0.9, 0.0, DOOR_H, "door"],
		[5.0, 5.9, 0.0, DOOR_H, "door"],
	], mats.int_wall)
	wall(Vector2(1, -5.9), Vector2(1, 0.9), [[-4.0, -1.4, 0.0, 2.4, "hole"]], mats.int_wall)
	wall(Vector2(-1, 1.1), Vector2(-1, 5.9), [], mats.int_wall)
	wall(Vector2(3, 1.1), Vector2(3, 5.9), [], mats.int_wall)

	# roof slab + ceiling underside + parapet
	box(Vector3(0, 3.1, 0), Vector3(16.6, 0.2, 12.6), mats.roof)
	deco(Vector3(0, 2.995, 0), Vector3(16.0, 0.01, 12.0), mats.ceiling)
	var p_h := 0.55
	var py := 3.2 + p_h * 0.5
	box(Vector3(0, py, -6.2), Vector3(16.6, p_h, 0.2), mats.ext_wall)
	box(Vector3(0, py, 6.2), Vector3(16.6, p_h, 0.2), mats.ext_wall)
	box(Vector3(-8.2, py, 0), Vector3(0.2, p_h, 12.6), mats.ext_wall)
	box(Vector3(8.2, py, -2.55), Vector3(0.2, p_h, 7.5), mats.ext_wall)
	box(Vector3(8.2, py, 4.6), Vector3(0.2, p_h, 3.2), mats.ext_wall)

	# rooftop clutter
	box(Vector3(-4.0, 3.6, 3.5), Vector3(1.6, 0.8, 1.2), mats.metal, "metal") # AC unit
	box(Vector3(3.0, 3.45, -3.0), Vector3(0.8, 0.5, 0.8), mats.metal, "metal")

	# outdoor stairs to the roof (ramp collider, visual steps)
	var steps := 13
	var rise := 3.25 / steps
	var run := 0.36
	var x0 := 8.25
	var width := 1.2
	var z_top := 1.5
	for i in steps:
		var top := rise * (i + 1)
		var z1 := z_top + run * (steps - i)
		deco(Vector3(x0 + width * 0.5, top * 0.5, z1 - run * 0.5), Vector3(width, top, run), mats.ext_wall)
	var run_total := run * steps
	var ramp := StaticBody3D.new()
	ramp.set_meta("surface", "concrete")
	geo.add_child(ramp)
	var ramp_len := sqrt(run_total * run_total + 3.25 * 3.25)
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(width, 0.1, ramp_len)
	cs.shape = sh
	ramp.add_child(cs)
	var angle := atan2(3.25, run_total)
	ramp.transform = Transform3D(Basis(Vector3.RIGHT, angle), Vector3(x0 + width * 0.5, 3.25 * 0.5 - 0.02, z_top + run_total * 0.5))
	box(Vector3(x0 + width * 0.5, 3.2, z_top - 0.2), Vector3(width, 0.1, 0.5), mats.ext_wall) # landing
	# railing wall on the outer side
	box(Vector3(x0 + width + 0.05, 1.9, z_top + run_total * 0.5 - 0.15), Vector3(0.1, 3.8, run_total + 0.6), mats.ext_wall)

	# room lights
	_light(Vector3(-3.5, 2.7, -2.5), 0.8, 8.0)
	_light(Vector3(4.5, 2.7, -2.5), 0.8, 7.5)
	_light(Vector3(-4.5, 2.7, 3.5), 0.6, 6.0)
	_light(Vector3(1.0, 2.7, 3.5), 0.5, 4.5)
	_light(Vector3(5.5, 2.7, 3.5), 0.6, 6.0)


func _build_furniture() -> void:
	var M := mats
	# ---------------- living room
	deco(Vector3(-4.0, 0.006, -2.4), Vector3(3.2, 0.012, 2.2), M.rug) # rug
	# sofa
	prop(Vector3(-4.0, 0.0, -0.05), [
		[Vector3(0, 0.22, 0), Vector3(2.2, 0.44, 0.9), M.fabric_grey],
		[Vector3(0, 0.68, 0.36), Vector3(2.2, 0.5, 0.18), M.fabric_grey],
		[Vector3(-1.02, 0.55, 0), Vector3(0.16, 0.22, 0.9), M.fabric_grey],
		[Vector3(1.02, 0.55, 0), Vector3(0.16, 0.22, 0.9), M.fabric_grey],
	], 60.0, "soft")
	# coffee table
	prop(Vector3(-4.0, 0.0, -1.9), _table_parts(Vector3(1.2, 0.06, 0.6), 0.42, M.dark_wood), 12.0)
	# TV stand + TV
	box(Vector3(-4.0, 0.25, -5.62), Vector3(1.8, 0.5, 0.45), M.dark_wood, "wood")
	prop(Vector3(-4.0, 0.5, -5.62), [
		[Vector3(0, 0.03, 0), Vector3(0.4, 0.06, 0.25), M.black],
		[Vector3(0, 0.12, 0), Vector3(0.08, 0.14, 0.06), M.black],
		[Vector3(0, 0.55, 0), Vector3(1.3, 0.75, 0.07), M.screen],
	], 12.0, "metal")
	# bookshelf
	box(Vector3(-7.72, 1.0, -4.6), Vector3(0.35, 2.0, 1.6), M.wood, "wood")
	for i in 7:
		prop(Vector3(-7.68, 2.12, -5.2 + i * 0.18), [[Vector3.ZERO, Vector3(0.18, 0.24, 0.05), [M.red_paint, M.blue_barrel, M.green, M.cardboard][i % 4]]], 0.6, "soft")
	# floor lamp
	prop(Vector3(-7.3, 0.0, 0.3), [
		[Vector3(0, 0.02, 0), Vector3(0.35, 0.04, 0.35), M.black],
		[Vector3(0, 0.8, 0), Vector3(0.04, 1.5, 0.04), M.black],
		[Vector3(0, 1.62, 0), Vector3(0.38, 0.3, 0.38), M.lamp],
	], 5.0, "metal")
	# cardboard boxes
	for p in [Vector3(0.0, 0.25, -5.3), Vector3(0.05, 0.75, -5.25), Vector3(-0.6, 0.25, -5.35), Vector3(-0.3, 0.2, -4.6)]:
		var s := 0.5 if p.y > 0.21 else 0.4
		prop(p, [[Vector3.ZERO, Vector3(s, s, s), M.cardboard]], 3.0, "soft", randf_range(-0.3, 0.3))

	# ---------------- kitchen
	box(Vector3(4.1, 0.45, -5.6), Vector3(5.2, 0.9, 0.6), M.white, "wood")
	deco(Vector3(4.1, 0.915, -5.6), Vector3(5.24, 0.03, 0.64), M.dark_wood)
	box(Vector3(7.6, 0.45, -1.6), Vector3(0.6, 0.9, 2.4), M.white, "wood")
	deco(Vector3(7.6, 0.915, -1.6), Vector3(0.64, 0.03, 2.44), M.dark_wood)
	prop(Vector3(7.35, 0.0, -5.5), [[Vector3(0, 0.95, 0), Vector3(0.8, 1.9, 0.7), M.metal]], 90.0, "metal")
	prop(Vector3(4.5, 0.0, -2.4), _table_parts(Vector3(1.6, 0.06, 0.9), 0.75, M.light_wood), 22.0)
	for c in [[Vector3(3.5, 0, -2.4), -PI / 2], [Vector3(5.5, 0, -2.4), PI / 2], [Vector3(4.5, 0, -1.6), 0.0], [Vector3(4.5, 0, -3.2), PI]]:
		prop(c[0], _chair_parts(M.light_wood), 6.0, "wood", c[1])
	for i in 6:
		var x := 2.2 + i * 0.55
		prop(Vector3(x, 0.99, -5.55 + randf_range(-0.1, 0.1)), [[Vector3.ZERO, Vector3(0.034, 0.12, 0), [M.red_paint, M.metal, M.green][i % 3], "cyl"]], 0.35, "metal")
	prop(Vector3(2.0, 0.0, -0.4), [[Vector3(0, 0.3, 0), Vector3(0.22, 0.6, 0), M.metal, "cyl"]], 4.0, "metal")

	# ---------------- bedroom
	box(Vector3(-5.5, 0.22, 4.85), Vector3(1.7, 0.44, 2.15), M.dark_wood, "wood")
	box(Vector3(-5.5, 0.55, 4.85), Vector3(1.6, 0.22, 2.05), M.white, "soft")
	deco(Vector3(-5.5, 0.67, 4.55), Vector3(1.64, 0.04, 1.4), M.blue_barrel)
	box(Vector3(-5.5, 0.75, 5.92), Vector3(1.7, 1.1, 0.08), M.dark_wood, "wood")
	prop(Vector3(-5.9, 0.73, 5.55), [[Vector3.ZERO, Vector3(0.55, 0.13, 0.32), M.white]], 1.0, "soft")
	prop(Vector3(-5.1, 0.73, 5.55), [[Vector3.ZERO, Vector3(0.55, 0.13, 0.32), M.white]], 1.0, "soft")
	box(Vector3(-2.0, 1.05, 5.6), Vector3(1.4, 2.1, 0.6), M.wood, "wood")
	prop(Vector3(-7.4, 0.0, 5.55), [[Vector3(0, 0.25, 0), Vector3(0.45, 0.5, 0.4), M.wood]], 8.0)
	prop(Vector3(-7.4, 0.5, 5.55), [
		[Vector3(0, 0.02, 0), Vector3(0.14, 0.04, 0.14), M.black],
		[Vector3(0, 0.25, 0), Vector3(0.24, 0.2, 0.24), M.lamp],
	], 1.2, "metal")

	# ---------------- bathroom
	var tub := Vector3(2.4, 0.0, 4.9)
	box(tub + Vector3(0, 0.04, 0), Vector3(0.8, 0.08, 1.7), M.white, "metal")
	box(tub + Vector3(-0.36, 0.3, 0), Vector3(0.08, 0.6, 1.7), M.white, "metal")
	box(tub + Vector3(0.36, 0.3, 0), Vector3(0.08, 0.6, 1.7), M.white, "metal")
	box(tub + Vector3(0, 0.3, -0.81), Vector3(0.8, 0.6, 0.08), M.white, "metal")
	box(tub + Vector3(0, 0.3, 0.81), Vector3(0.8, 0.6, 0.08), M.white, "metal")
	box(Vector3(-0.5, 0.21, 5.55), Vector3(0.4, 0.42, 0.55), M.white, "metal")
	box(Vector3(-0.5, 0.62, 5.83), Vector3(0.45, 0.4, 0.18), M.white, "metal")
	box(Vector3(0.9, 0.42, 5.72), Vector3(0.6, 0.84, 0.45), M.white, "metal")
	deco(Vector3(0.9, 1.55, 5.89), Vector3(0.55, 0.7, 0.02), M.metal) # mirror

	# ---------------- garage
	box(Vector3(7.5, 0.45, 3.4), Vector3(0.7, 0.9, 2.0), M.dark_wood, "wood")
	for p in [Vector3(4.0, 0.4, 2.0), Vector3(4.05, 1.2, 2.0), Vector3(4.95, 0.4, 1.9)]:
		prop(p, [[Vector3.ZERO, Vector3(0.78, 0.78, 0.78), M.wood]], 18.0, "wood", randf_range(-0.15, 0.15))
	for p in [Vector3(3.8, 0.45, 4.6), Vector3(4.5, 0.45, 5.1), Vector3(6.0, 0.45, 2.0)]:
		prop(p, [[Vector3.ZERO, Vector3(0.3, 0.9, 0), M.blue_barrel, "cyl"]], 28.0, "metal")


func _table_parts(top: Vector3, height: float, mat: Material) -> Array:
	var parts := [[Vector3(0, height - top.y * 0.5, 0), top, mat]]
	var lx := top.x * 0.5 - 0.06
	var lz := top.z * 0.5 - 0.06
	var leg_h := height - top.y
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			parts.append([Vector3(lx * sx, leg_h * 0.5, lz * sz), Vector3(0.06, leg_h, 0.06), mat])
	return parts


func _chair_parts(mat: Material) -> Array:
	var parts := [[Vector3(0, 0.45, 0), Vector3(0.44, 0.05, 0.44), mat],
		[Vector3(0, 0.75, 0.2), Vector3(0.44, 0.5, 0.04), mat]]
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			parts.append([Vector3(0.19 * sx, 0.215, 0.19 * sz), Vector3(0.04, 0.43, 0.04), mat])
	return parts


func _build_yard() -> void:
	var M := mats
	# low concrete fence around the plot, gate at the front
	var f_h := 1.1
	box(Vector3(0, f_h * 0.5, 22), Vector3(44.2, f_h, 0.25), M.ext_wall)
	box(Vector3(-22, f_h * 0.5, 0), Vector3(0.25, f_h, 44.2), M.ext_wall)
	box(Vector3(22, f_h * 0.5, 0), Vector3(0.25, f_h, 44.2), M.ext_wall)
	box(Vector3(-13.25, f_h * 0.5, -22), Vector3(17.5, f_h, 0.25), M.ext_wall)
	box(Vector3(13.25, f_h * 0.5, -22), Vector3(17.5, f_h, 0.25), M.ext_wall)

	# trees
	for p in [Vector3(-15, 0, -14), Vector3(-17, 0, 8), Vector3(16, 0, 12), Vector3(-9, 0, 16), Vector3(6, 0, 17), Vector3(17, 0, -4)]:
		var trunk := StaticBody3D.new()
		trunk.set_meta("surface", "wood")
		trunk.position = p
		geo.add_child(trunk)
		var tm := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.16
		cm.bottom_radius = 0.24
		cm.height = 3.2
		tm.mesh = cm
		tm.material_override = M.bark
		tm.position.y = 1.6
		trunk.add_child(tm)
		var cs := CollisionShape3D.new()
		var sh := CylinderShape3D.new()
		sh.radius = 0.22
		sh.height = 3.2
		cs.shape = sh
		cs.position.y = 1.6
		trunk.add_child(cs)
		for k in 3:
			var crown := MeshInstance3D.new()
			var sm := SphereMesh.new()
			var r := randf_range(1.1, 1.6)
			sm.radius = r
			sm.height = r * 2.0
			crown.mesh = sm
			crown.material_override = M.green
			crown.position = Vector3(randf_range(-0.6, 0.6), 3.3 + k * 0.6, randf_range(-0.6, 0.6))
			trunk.add_child(crown)

	# parked car on the driveway
	var car := Vector3(10.5, 0, -11.5)
	box(car + Vector3(0, 0.62, 0), Vector3(1.85, 0.7, 4.3), M.red_paint, "metal")
	box(car + Vector3(0, 1.22, 0.3), Vector3(1.65, 0.55, 2.2), M.screen, "glass_static")
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			var w := MeshInstance3D.new()
			var wm := CylinderMesh.new()
			wm.top_radius = 0.34
			wm.bottom_radius = 0.34
			wm.height = 0.26
			w.mesh = wm
			w.material_override = M.black
			w.position = car + Vector3(0.86 * sx, 0.34, 1.35 * sz)
			w.rotation.z = PI / 2
			geo.add_child(w)

	# shooting range corner: crates and barrels in the yard
	for p in [Vector3(-14, 0.4, -4), Vector3(-14.9, 0.4, -4.2), Vector3(-14.4, 1.2, -4.1), Vector3(-12, 0.4, 11)]:
		prop(p, [[Vector3.ZERO, Vector3(0.78, 0.78, 0.78), M.wood]], 18.0, "wood", randf_range(-0.3, 0.3))
	for p in [Vector3(12.5, 0.45, 6), Vector3(13.2, 0.45, 6.4), Vector3(-6, 0.45, -16)]:
		prop(p, [[Vector3.ZERO, Vector3(0.3, 0.9, 0), M.red_paint, "cyl"]], 28.0, "metal")


func _bake_navigation() -> void:
	var nm := NavigationMesh.new()
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_collision_mask = 1
	nm.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_ROOT_NODE_CHILDREN
	nm.agent_radius = 0.25
	nm.agent_height = 1.75
	nm.agent_max_climb = 0.25
	nm.agent_max_slope = 40.0
	nm.cell_size = 0.25
	nm.cell_height = 0.25
	nm.filter_baking_aabb = AABB(Vector3(-21.8, -1, -21.8), Vector3(43.6, 3.9, 43.6))
	nav_region.navigation_mesh = nm
	nav_region.bake_navigation_mesh(false)
