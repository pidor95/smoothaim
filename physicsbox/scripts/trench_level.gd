class_name TrenchLevel
extends Node3D
## The front: two trench systems facing each other across a cratered
## no-man's land several hundred metres long, a town sector with two
## five-storey panel blocks either side of the line, abandoned villages and
## ruins - built in Blender (tools/blender/build_trenches.py and
## build_buildings.py). The allies (team 0, the player's side) hold the line
## at +Z, the enemy (team 1) the one at -Z. Empties in the map give each side
## its reinforcement points and firing positions; the buildings are placed
## from prototypes, with glass panes and hinged doors at their markers.
## The navigation mesh is baked once offline (tools/bake_nav.gd).
## The map is put together a little each frame (`built` when done), so a
## phone never sits frozen long enough for Android to kill the game.

signal built

const MAP := "res://assets/maps/trenches.glb"
const BUILDINGS := "res://assets/maps/buildings.glb"
const NAV := "res://assets/maps/trenches_nav.res"
## The ground's collision: a height grid (tools/bake_heights.gd) cut into
## HeightMapShape3D tiles, not trimesh shapes of the terrain chunks - those
## took ~130 MB and phones ran out of memory.
const HEIGHTS := "res://assets/maps/trenches_height.res"
const HEIGHTS_ORIGIN := Vector2(-270.0, -170.0)
const HEIGHTS_STEP := 0.5
const HEIGHTS_TILE := 64
const NAV_AABB := AABB(Vector3(-270.0, -4.0, -170.0), Vector3(420.0, 26.0, 340.0))

var nav_region := NavigationRegion3D.new()
var geo := Node3D.new()
var props_root := Node3D.new()
var mats := {}
var player_spawn := Transform3D.IDENTITY
## Per team: reinforcement points (rear) and firing posts (front, windows).
var team_spawns: Array = [[], []]
var team_posts: Array = [[], []]

var is_built := false
var progress := 0.0 # 0..1 while building (loading screen)

var _protos := {} # name -> {meshes: [[mesh, material]], shape: Shape3D, markers: [[kind, Transform3D]]}
var _slice := 0


func _ready() -> void:
	nav_region.name = "Navigation"
	add_child(nav_region)
	geo.name = "Geometry"
	nav_region.add_child(geo)
	props_root.name = "Props"
	add_child(props_root)
	_make_materials()
	_build()


func _build() -> void:
	_slice = Time.get_ticks_msec()
	await _load_protos()
	await _build_map()
	await _build_ground()
	NavigationServer3D.map_set_cell_size(get_world_3d().navigation_map, 0.2)
	NavigationServer3D.map_set_cell_height(get_world_3d().navigation_map, 0.1)
	if ResourceLoader.exists(NAV):
		nav_region.navigation_mesh = load(NAV)
	else:
		bake_navigation()
	progress = 1.0
	is_built = true
	built.emit()


## Lets a frame go by every ~25 ms of building.
func _breathe() -> void:
	if Time.get_ticks_msec() - _slice > 25:
		await get_tree().process_frame
		_slice = Time.get_ticks_msec()


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
	const CONCRETE := "res://assets/textures/concrete.png"
	const MUD := "res://assets/textures/mud.png"
	const WOOD := "res://assets/textures/wood.png"
	const BARK := "res://assets/textures/bark.png"
	mats.mud = _tex_mat(Color(0.68, 0.64, 0.6), MUD, 0.32, 1.0)
	mats.mud.vertex_color_use_as_albedo = true
	mats.planks = _tex_mat(Color(0.72, 0.6, 0.46), WOOD, 0.9, 0.9)
	mats.bark = _tex_mat(Color(0.85, 0.8, 0.75), BARK, 1.1, 1.0)
	mats.logs = _tex_mat(Color(0.75, 0.68, 0.6), BARK, 1.4, 1.0)
	mats.sandbag = _tex_mat(Color(1.35, 1.25, 1.0), MUD, 1.4, 1.0)
	mats.wire = _tex_mat(Color(0.16, 0.15, 0.14), "", 1.0, 0.6)
	mats.wire.metallic = 0.5
	# buildings (names from build_buildings.py)
	mats.Panel = _tex_mat(Color(0.8, 0.79, 0.76), CONCRETE, 0.3, 0.95)
	mats.Plinth = _tex_mat(Color(0.5, 0.49, 0.47), CONCRETE, 0.4, 0.95)
	mats.Concrete = _tex_mat(Color(0.66, 0.65, 0.63), CONCRETE, 0.45, 0.95)
	mats.Plaster = _tex_mat(Color(0.6, 0.72, 0.65), CONCRETE, 0.8, 0.9)
	mats.Paint = _tex_mat(Color(0.18, 0.45, 0.41), "", 1.0, 0.5)
	mats.Whitewash = _tex_mat(Color(0.86, 0.86, 0.83), CONCRETE, 0.8, 0.9)
	mats.Lino = _tex_mat(Color(0.62, 0.36, 0.2), WOOD, 0.6, 0.6)
	mats.Frame = _tex_mat(Color(0.85, 0.85, 0.82), "", 1.0, 0.6)
	mats.Metal = _tex_mat(Color(0.24, 0.25, 0.26), "", 1.0, 0.45)
	mats.Metal.metallic = 0.6
	mats.Pipe = _tex_mat(Color(0.92, 0.72, 0.1), "", 1.0, 0.45)
	mats.Roof = _tex_mat(Color(0.2, 0.2, 0.21), CONCRETE, 0.5, 0.9)
	mats.Brick = _tex_mat(Color(0.78, 0.42, 0.3), "res://assets/textures/tiles.png", 0.9, 0.95)
	mats.Planks = mats.planks
	mats.Slate = _tex_mat(Color(0.5, 0.55, 0.52), CONCRETE, 0.6, 0.85)
	mats.Rubble = _tex_mat(Color(0.62, 0.55, 0.5), CONCRETE, 0.7, 1.0)
	mats.Rust = _tex_mat(Color(0.42, 0.25, 0.15), CONCRETE, 0.8, 0.8)
	mats.Rust.metallic = 0.3
	mats.Wood = _tex_mat(Color(0.55, 0.38, 0.25), WOOD, 1.2, 0.7)
	mats.Fabric = _tex_mat(Color(0.32, 0.34, 0.4), "", 1.0, 1.0)


func _material_for(mesh_name: String) -> Material:
	if mesh_name.begins_with("Tree"):
		return mats.bark
	match mesh_name.get_slice("_", 0):
		"Planks", "Duckboards", "Steps":
			return mats.planks
		"Posts", "WireStakes", "Logs":
			return mats.logs
		"Sandbags":
			return mats.sandbag
		"Wire":
			return mats.wire
	return mats.mud


## Building prototypes: meshes with their materials, one collision shape
## (shared by every copy) and the markers.
func _load_protos() -> void:
	var scene: Node = load(BUILDINGS).instantiate()
	for p in scene.get_children():
		var proto_name := String(p.name).trim_prefix("P_")
		var entry := {"meshes": [], "shape": null, "markers": []}
		for c in p.get_children():
			var n := String(c.name)
			if c is MeshInstance3D:
				if n.begins_with("C__"):
					entry.shape = (c.mesh as Mesh).create_trimesh_shape()
					await _breathe()
				else:
					entry.meshes.append([c.mesh, mats.get(n.get_slice("__", 0), mats.Concrete), c.transform])
			else:
				entry.markers.append([n.get_slice("__", 0), c.transform])
		_protos[proto_name] = entry
	scene.free()


func _build_map() -> void:
	var scene: Node = load(MAP).instantiate()
	var count := scene.get_child_count()
	for k in count:
		var n := scene.get_child(k)
		progress = 0.1 + 0.85 * k / count
		await _breathe()
		var node_name := String(n.name)
		var xf: Transform3D = n.transform
		if n is MeshInstance3D:
			var mesh: Mesh = n.mesh
			if node_name.begins_with("C_"):
				_static_trimesh(mesh, xf, "dirt")
				continue
			var mi := MeshInstance3D.new()
			mi.name = node_name
			mi.mesh = mesh
			mi.transform = xf
			mi.material_override = _material_for(node_name)
			if node_name.begins_with("Wire") or node_name.begins_with("Duckboards") or node_name.begins_with("Steps"):
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				mi.visibility_range_end = 90.0
			if node_name.get_slice("_", 0) in ["Planks", "Posts", "Sandbags", "Logs", "WireStakes"]:
				mi.visibility_range_end = 110.0 # small stuff: gone in the haze anyway
			geo.add_child(mi)
			if node_name.begins_with("Terrain"):
				if not ResourceLoader.exists(HEIGHTS):
					_static_trimesh(mesh, xf, "dirt")
			elif node_name.begins_with("Tree"):
				mi.visibility_range_end = 140.0
				_trunk(xf)
		elif node_name == "Player":
			player_spawn = Transform3D(Basis.IDENTITY, xf.origin)
		elif node_name.begins_with("B_"):
			_place_building(node_name.get_slice("_", 1), node_name.get_slice("_", 2), xf)
		elif node_name.begins_with("Spawn") or node_name.begins_with("Post"):
			var team := 0 if node_name[node_name.find("_") - 1] == "A" else 1
			(team_spawns if node_name.begins_with("Spawn") else team_posts)[team].append(xf.origin)
	scene.free()


## One building from its prototype at `xf`; `side` A / B / N says whose
## firing positions its windows are (N: both sides').
func _place_building(proto_name: String, side: String, xf: Transform3D) -> void:
	var p: Dictionary = _protos.get(proto_name, {})
	if p.is_empty():
		return
	var root := Node3D.new()
	root.name = "%s_%d" % [proto_name, geo.get_child_count()]
	root.transform = xf
	geo.add_child(root)
	for m in p.meshes:
		var mi := MeshInstance3D.new()
		mi.mesh = m[0]
		mi.material_override = m[1]
		mi.transform = m[2]
		mi.visibility_range_end = 220.0
		root.add_child(mi)
	if p.shape:
		var b := StaticBody3D.new()
		b.set_meta("surface", "concrete")
		var cs := CollisionShape3D.new()
		cs.shape = p.shape
		b.add_child(cs)
		root.add_child(b)
	for mk in p.markers:
		var kind: String = mk[0]
		var t: Transform3D = xf * (mk[1] as Transform3D)
		var size: Vector3 = (mk[1] as Transform3D).basis.get_scale()
		var flat := Transform3D(t.basis.orthonormalized(), t.origin)
		match kind:
			"Glass":
				var pane := GlassPane.new()
				pane.size = Vector3(size.x, size.y, 0.02)
				pane.transform = flat
				props_root.add_child(pane)
			"Door":
				_door(flat, size.x, size.y)
			"Post":
				if side != "B":
					team_posts[0].append(t.origin)
				if side != "A":
					team_posts[1].append(t.origin)


func _door(t: Transform3D, width: float, height: float) -> void:
	var leaf := Door.new()
	leaf.width = width
	leaf.height = height
	leaf.transform = t
	leaf.add_to_group("doors")
	props_root.add_child(leaf)
	var joint := HingeJoint3D.new()
	props_root.add_child(joint)
	joint.global_transform = Transform3D(t.basis * Basis(Vector3.RIGHT, -PI / 2), t * Vector3(-width * 0.5, 0, 0))
	joint.set_flag(HingeJoint3D.FLAG_USE_LIMIT, true)
	joint.set_param(HingeJoint3D.PARAM_LIMIT_LOWER, deg_to_rad(-95))
	joint.set_param(HingeJoint3D.PARAM_LIMIT_UPPER, deg_to_rad(95))
	joint.node_b = joint.get_path_to(leaf)
	leaf.joint = joint


## The ground's collision tiles, 32 x 32 m each (65 x 65 samples 0.5 m
## apart: square, so Jolt makes a real height field of them). The grid holds
## the heights doubled and each tile is scaled by 0.5 uniformly.
func _build_ground() -> void:
	if not ResourceLoader.exists(HEIGHTS):
		return
	var img: Image = load(HEIGHTS)
	var n := HEIGHTS_TILE
	var body := StaticBody3D.new()
	body.name = "Ground"
	body.set_meta("surface", "dirt")
	geo.add_child(body)
	for tj in (img.get_height() - 1) / n:
		for ti in (img.get_width() - 1) / n:
			var sh := HeightMapShape3D.new()
			sh.map_width = n + 1
			sh.map_depth = n + 1
			sh.map_data = img.get_region(Rect2i(ti * n, tj * n, n + 1, n + 1)).get_data().to_float32_array()
			var cs := CollisionShape3D.new()
			cs.shape = sh
			var centre := HEIGHTS_ORIGIN + Vector2(ti * n + n * 0.5, tj * n + n * 0.5) * HEIGHTS_STEP
			cs.transform = Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * HEIGHTS_STEP), Vector3(centre.x, 0.0, centre.y))
			body.add_child(cs)
		await _breathe()


func _static_trimesh(mesh: Mesh, xf: Transform3D, surface: String) -> void:
	var b := StaticBody3D.new()
	b.transform = xf
	b.set_meta("surface", surface)
	var cs := CollisionShape3D.new()
	cs.shape = mesh.create_trimesh_shape()
	b.add_child(cs)
	geo.add_child(b)


func _trunk(xf: Transform3D) -> void:
	var b := StaticBody3D.new()
	b.set_meta("surface", "wood")
	b.position = xf.origin + Vector3.UP * 1.5
	var cs := CollisionShape3D.new()
	var sh := CylinderShape3D.new()
	sh.radius = 0.16 * xf.basis.get_scale().x
	sh.height = 3.0
	cs.shape = sh
	b.add_child(cs)
	geo.add_child(b)


## Bakes the navigation mesh from the static colliders (slow on a phone:
## tools/bake_nav.gd saves it to NAV once).
func bake_navigation() -> void:
	var nm := NavigationMesh.new()
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_collision_mask = 1
	nm.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_ROOT_NODE_CHILDREN
	nm.agent_radius = 0.2 # one cell: stair flights and doorways stay open
	nm.agent_height = 1.75
	nm.agent_max_climb = 0.3
	nm.agent_max_slope = 40.0
	nm.cell_size = 0.2
	nm.cell_height = 0.1
	nm.filter_baking_aabb = NAV_AABB
	nav_region.navigation_mesh = nm
	nav_region.bake_navigation_mesh(false)
