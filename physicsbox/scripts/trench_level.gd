class_name TrenchLevel
extends House
## Level "Trenches": two trench lines facing each other across a cratered
## no-man's land, built in Blender (tools/blender/build_trenches.py). The
## allies (team 0, the player's side) hold the line at +Z, the enemy (team 1)
## the one at -Z. Empties in the map give each side its reinforcement points
## and firing positions.

const MAP := "res://assets/maps/trenches.glb"

## Per team: reinforcement points (rear trench) and firing posts (front trench).
var team_spawns: Array = [[], []]
var team_posts: Array = [[], []]


func _ready() -> void:
	nav_region.name = "Navigation"
	add_child(nav_region)
	geo.name = "Geometry"
	nav_region.add_child(geo)
	props_root.name = "Props"
	add_child(props_root)
	_make_war_materials()
	_build_map()
	_bake_war_navigation()


func _make_war_materials() -> void:
	mats.mud = _tex_mat(Color(0.68, 0.64, 0.6), "res://assets/textures/mud.png", 0.32, 1.0)
	mats.mud.vertex_color_use_as_albedo = true
	mats.planks = _tex_mat(Color(0.72, 0.6, 0.46), "res://assets/textures/wood.png", 0.9, 0.9)
	mats.bark = _tex_mat(Color(0.85, 0.8, 0.75), "res://assets/textures/bark.png", 1.1, 1.0)
	mats.logs = _tex_mat(Color(0.75, 0.68, 0.6), "res://assets/textures/bark.png", 1.4, 1.0)
	mats.sandbag = _tex_mat(Color(1.35, 1.25, 1.0), "res://assets/textures/mud.png", 1.4, 1.0)
	mats.wire = _tex_mat(Color(0.16, 0.15, 0.14), "", 1.0, 0.6)
	mats.wire.metallic = 0.5


func _material_for(mesh_name: String) -> Material:
	if mesh_name.begins_with("Tree"):
		return mats.bark
	match mesh_name:
		"Planks", "Duckboards", "Steps":
			return mats.planks
		"Posts", "WireStakes", "Logs":
			return mats.logs
		"Sandbags":
			return mats.sandbag
		"Wire":
			return mats.wire
	return mats.mud


func _build_map() -> void:
	var scene: Node = load(MAP).instantiate()
	for n in scene.get_children():
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
			if node_name == "Wire" or node_name == "Duckboards" or node_name == "Steps":
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			geo.add_child(mi)
			if node_name == "Terrain":
				_static_trimesh(mesh, xf, "dirt")
			elif node_name.begins_with("Tree"):
				_trunk(xf)
		elif node_name == "Player":
			player_spawn = Transform3D(Basis.IDENTITY, xf.origin)
		elif node_name.begins_with("Spawn") or node_name.begins_with("Post"):
			var team := 0 if node_name[node_name.find("_") - 1] == "A" else 1
			(team_spawns if node_name.begins_with("Spawn") else team_posts)[team].append(xf.origin)
	scene.free()
	npc_spawns.clear()
	for p in team_spawns[0] + team_spawns[1]:
		npc_spawns.append(p)


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


func _bake_war_navigation() -> void:
	var nm := NavigationMesh.new()
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_collision_mask = 1
	nm.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_ROOT_NODE_CHILDREN
	nm.agent_radius = 0.3
	nm.agent_height = 1.75
	nm.agent_max_climb = 0.3
	nm.agent_max_slope = 40.0
	nm.cell_size = 0.25
	nm.cell_height = 0.1
	NavigationServer3D.map_set_cell_height(get_world_3d().navigation_map, 0.1)
	nm.filter_baking_aabb = AABB(Vector3(-45.5, -3.0, -51.5), Vector3(91.0, 6.0, 103.0))
	nav_region.navigation_mesh = nm
	nav_region.bake_navigation_mesh(false)
