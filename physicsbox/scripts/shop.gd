class_name ShopLevel
extends House
## Level "Shop": a supermarket with aisles of shelves full of physics
## products, checkouts, glass-door coolers, a glass storefront, a stock room
## behind a door and a parking lot. Props are modelled in Blender
## (tools/blender/build_shop_props.py); the building reuses House's helpers.

const PROPS_PATH := "res://assets/props/shop.glb"
const SHOP_H := 4.2
const PRODUCTS := ["prod_box", "prod_can", "prod_bottle", "prod_carton", "prod_bag", "prod_jar"]
const PRODUCT_COLORS := [Color(0.85, 0.15, 0.1), Color(0.95, 0.75, 0.15), Color(0.15, 0.45, 0.85),
		Color(0.2, 0.65, 0.3), Color(0.95, 0.95, 0.95), Color(0.55, 0.25, 0.65), Color(0.95, 0.5, 0.1)]
const PRODUCT_MASS := {"prod_box": 0.5, "prod_can": 0.35, "prod_bottle": 1.0, "prod_carton": 1.0,
		"prod_bag": 0.4, "prod_jar": 0.6}

static var _meshes := {}

var _pack_mats := {}
var _decor := {} # [kind, colour] -> transforms, drawn as MultiMeshes (one draw call each)


static func _load_props() -> void:
	if not _meshes.is_empty():
		return
	var scene: Node = load(PROPS_PATH).instantiate()
	for mi in scene.find_children("*", "MeshInstance3D", true, false):
		_meshes[String(mi.name)] = mi.mesh
	scene.free()


func _ready() -> void:
	player_spawn = Transform3D(Basis.IDENTITY, Vector3(0.0, 0.05, -16.0))
	player_spawn.basis = Basis(Vector3.UP, PI)
	npc_spawns = [
		Vector3(-9.5, 0.05, 0.0), Vector3(-5.2, 0.05, 2.0), Vector3(-0.7, 0.05, -1.0), Vector3(3.8, 0.05, 3.0),
		Vector3(8.5, 0.05, 1.0), Vector3(-4.0, 0.05, -7.0), Vector3(4.0, 0.05, -7.5), Vector3(0.0, 0.05, 7.5),
		Vector3(10.5, 0.05, 6.5),
	]
	_load_props()
	nav_region.name = "Navigation"
	add_child(nav_region)
	geo.name = "Geometry"
	nav_region.add_child(geo)
	props_root.name = "Props"
	add_child(props_root)
	_make_materials()
	_build_lot()
	_build_building()
	_build_interior()
	_bake_navigation()


# ------------------------------------------------------------------ helpers

## Static Blender mesh with simple box colliders [[center, size], ...].
func static_mesh(mesh_name: String, pos: Vector3, rot_y: float, shapes: Array, surface := "metal") -> StaticBody3D:
	var b := StaticBody3D.new()
	b.set_meta("surface", surface)
	b.position = pos
	b.rotation.y = rot_y
	geo.add_child(b)
	var mi := MeshInstance3D.new()
	mi.mesh = _meshes[mesh_name]
	b.add_child(mi)
	for s in shapes:
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = s[1]
		cs.shape = sh
		cs.position = s[0]
		b.add_child(cs)
	return b


func _pack_mat(color: Color) -> StandardMaterial3D:
	var key := color.to_html()
	if not _pack_mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.roughness = 0.55
		_pack_mats[key] = m
	return _pack_mats[key]


## One shop product as a light physics body standing on `pos`.
func product(kind: String, pos: Vector3, rot_y: float, physics := true) -> void:
	var mesh: Mesh = _meshes[kind]
	var aabb := mesh.get_aabb()
	var color: Color = PRODUCT_COLORS[randi() % PRODUCT_COLORS.size()]
	# meshes keep their Blender origins; put the bottom centre on `pos`
	var offset := -Vector3(aabb.get_center().x, aabb.position.y, aabb.get_center().z)
	if not physics:
		var key := [kind, color]
		if not _decor.has(key):
			_decor[key] = []
		_decor[key].append(Transform3D(Basis(Vector3.UP, rot_y), pos) * Transform3D(Basis.IDENTITY, offset))
		return
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.set_surface_override_material(0, _pack_mat(color))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = offset
	var b := RigidBody3D.new()
	b.mass = PRODUCT_MASS.get(kind, 0.5)
	b.collision_layer = 2
	b.collision_mask = 1 | 2 | 4
	b.set_meta("surface", "metal" if kind == "prod_can" else ("glass_static" if kind == "prod_bottle" else "soft"))
	b.position = pos
	b.rotation.y = rot_y
	b.can_sleep = true
	b.sleeping = true
	b.add_child(mi)
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = aabb.size * Vector3(0.95, 1.0, 0.95)
	cs.shape = sh
	cs.position = Vector3(0, aabb.size.y * 0.5, 0)
	b.add_child(cs)
	props_root.add_child(b)


func _flush_decor() -> void:
	for key in _decor:
		var xforms: Array = _decor[key]
		# MultiMeshInstance3D has no per-surface override, so tint a mesh copy
		var mesh: Mesh = (_meshes[key[0]] as Mesh).duplicate()
		mesh.surface_set_material(0, _pack_mat(key[1]))
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = xforms.size()
		for i in xforms.size():
			mm.set_instance_transform(i, xforms[i])
		var node := MultiMeshInstance3D.new()
		node.multimesh = mm
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		geo.add_child(node)
	_decor.clear()


## Fills one shelf board: a few physics items on the eye-level board of the
## aisle shelves, everything else is static decor.
func stock_shelf(origin: Vector3, rot_y: float, width: float, physics: bool) -> void:
	var kind: String = PRODUCTS[randi() % PRODUCTS.size()]
	var aabb := (_meshes[kind] as Mesh).get_aabb()
	var step := maxf(aabb.size.x, 0.075) + 0.03
	var count := int((width - 0.1) / step)
	var basis := Basis(Vector3.UP, rot_y)
	for i in count:
		if randf() < 0.12:
			continue # an empty slot here and there
		var x := -width * 0.5 + 0.05 + step * (i + 0.5)
		product(kind, origin + basis * Vector3(x, 0.005, 0), rot_y + randf_range(-0.08, 0.08), physics and i % 2 == 0)


# ------------------------------------------------------------------ level

func _build_lot() -> void:
	var asphalt := _tex_mat(Color(0.22, 0.22, 0.24), "res://assets/textures/concrete.png", 0.2, 0.95)
	var line := _tex_mat(Color(0.9, 0.9, 0.85), "", 1.0, 0.8)
	box(Vector3(0, -0.52, 0), Vector3(140, 1.0, 140), mats.ground)
	deco(Vector3(0, -0.012, -16.5), Vector3(30.0, 0.02, 13.0), asphalt)
	for i in 9:
		deco(Vector3(-12.0 + i * 3.0, -0.0, -17.5), Vector3(0.12, 0.012, 5.0), line)
	# curb in front of the storefront
	box(Vector3(0, 0.06, -9.9), Vector3(28.0, 0.12, 1.6), mats.ext_wall)
	# parked car
	var car := Vector3(-7.5, 0, -17.5)
	box(car + Vector3(0, 0.62, 0), Vector3(1.85, 0.7, 4.3), mats.blue_barrel, "metal")
	box(car + Vector3(0, 1.22, 0.3), Vector3(1.65, 0.55, 2.2), mats.screen, "glass_static")
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			var w := MeshInstance3D.new()
			var wm := CylinderMesh.new()
			wm.top_radius = 0.34
			wm.bottom_radius = 0.34
			wm.height = 0.26
			w.mesh = wm
			w.material_override = mats.black
			w.position = car + Vector3(0.86 * sx, 0.34, 1.35 * sz)
			w.rotation.z = PI / 2
			geo.add_child(w)
	# loose carts on the lot and by the entrance
	for c in [[Vector3(4.0, 0.05, -14.0), 0.4], [Vector3(6.5, 0.05, -18.0), -1.2], [Vector3(-1.8, 0.05, -10.6), 0.1],
			[Vector3(-2.5, 0.05, -10.6), 0.05]]:
		_cart(c[0], c[1])


func _cart(pos: Vector3, rot_y: float) -> void:
	var mesh: Mesh = _meshes["cart"]
	var aabb := mesh.get_aabb()
	var b := RigidBody3D.new()
	b.mass = 12.0
	b.collision_layer = 2
	b.collision_mask = 1 | 2 | 4
	b.set_meta("surface", "metal")
	b.position = pos
	b.rotation.y = rot_y
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = -Vector3(aabb.get_center().x, aabb.position.y, aabb.get_center().z)
	b.add_child(mi)
	var basket := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(0.55, 0.45, 0.9)
	basket.shape = sh
	basket.position = Vector3(0, 0.62, 0)
	b.add_child(basket)
	var base := CollisionShape3D.new()
	var sh2 := BoxShape3D.new()
	sh2.size = Vector3(0.5, 0.12, 0.85)
	base.shape = sh2
	base.position = Vector3(0, 0.08, 0)
	b.add_child(base)
	props_root.add_child(b)


func _build_building() -> void:
	var tiles := _tex_mat(Color(0.88, 0.88, 0.86), "res://assets/textures/tiles.png", 0.35, 0.25)
	var wall_mat := _tex_mat(Color(0.86, 0.86, 0.83), "res://assets/textures/concrete.png", 0.4)
	var facade := _tex_mat(Color(0.72, 0.1, 0.08), "", 1.0, 0.5)
	box(Vector3(0, -0.05, 0), Vector3(26.0, 0.1, 18.0), tiles)
	# storefront: low wall, glass panels, entrance in the middle
	var front: Array = []
	var x := -12.8
	while x < 12.6:
		var x2 := minf(x + 2.4, 12.8)
		if x2 > -1.6 and x < 1.6:
			x = 1.6
			continue
		front.append([x + 0.05, x2 - 0.05, 0.5, 3.2, "window"])
		x = x2
	front.append([-1.6, 1.6, 0.0, 2.8, "hole"])
	wall(Vector2(-13.1, -9), Vector2(13.1, -9), front, mats.ext_wall, SHOP_H)
	wall(Vector2(-13.1, 9), Vector2(13.1, 9), [], wall_mat, SHOP_H)
	wall(Vector2(-13, -9), Vector2(-13, 9), [], wall_mat, SHOP_H)
	wall(Vector2(13, -9), Vector2(13, 9), [], wall_mat, SHOP_H)
	# stock room in the back right corner, behind a door
	wall(Vector2(8.5, 4.5), Vector2(12.9, 4.5), [[9.6, 10.6, 0.0, DOOR_H, "door"]], wall_mat, SHOP_H)
	wall(Vector2(8.5, 4.6), Vector2(8.5, 8.9), [], wall_mat, SHOP_H)
	# roof, ceiling, facade band and sign
	box(Vector3(0, SHOP_H + 0.1, 0), Vector3(26.6, 0.2, 18.6), mats.roof)
	deco(Vector3(0, SHOP_H - 0.005, 0), Vector3(26.0, 0.01, 18.0), mats.ceiling)
	deco(Vector3(0, SHOP_H - 0.35, -9.12), Vector3(26.4, 0.7, 0.04), facade)
	var sign_label := Label3D.new()
	sign_label.text = "ПРОДУКТЫ 24"
	sign_label.font_size = 160
	sign_label.pixel_size = 0.004
	sign_label.outline_size = 0
	sign_label.modulate = Color(1, 1, 1)
	sign_label.position = Vector3(0, SHOP_H - 0.35, -9.15)
	sign_label.rotation.y = PI
	geo.add_child(sign_label)
	# ceiling light panels in rows + a few real lights
	for lx in [-9.0, -4.5, 0.0, 4.5, 9.0]:
		for lz in [-6.0, -1.0, 4.0]:
			var lamp := MeshInstance3D.new()
			lamp.mesh = _meshes["lamp"]
			lamp.position = Vector3(lx, SHOP_H - 0.04, lz)
			lamp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			geo.add_child(lamp)
	for lp in [Vector3(-6.5, 3.8, -4.0), Vector3(0, 3.8, -4.0), Vector3(6.5, 3.8, -4.0),
			Vector3(-6.5, 3.8, 4.0), Vector3(0, 3.8, 4.0), Vector3(6.5, 3.8, 4.0)]:
		var l := OmniLight3D.new()
		l.position = lp
		l.light_color = Color(1.0, 0.97, 0.9)
		l.light_energy = 0.9
		l.omni_range = 8.5
		add_child(l)


func _gondola(pos: Vector3, rot_y: float) -> void:
	var shapes := [[Vector3(0, 0.075, 0), Vector3(2.0, 0.15, 0.9)], [Vector3(0, 0.925, 0), Vector3(2.0, 1.55, 0.05)],
			[Vector3(0, 1.7, 0), Vector3(2.0, 0.04, 0.9)]]
	for y in [0.55, 0.95, 1.35]:
		for side in [-1, 1]:
			shapes.append([Vector3(0, y, side * 0.235), Vector3(1.9, 0.03, 0.42)])
	static_mesh("gondola", pos, rot_y, shapes)
	var basis := Basis(Vector3.UP, rot_y)
	for side in [-1, 1]:
		for y in [0.15, 0.55, 0.95, 1.35]:
			var o := pos + basis * Vector3(0, y + 0.015, side * 0.26)
			# products face out of the shelf (their labels are on local -Z)
			stock_shelf(o, rot_y + (PI if side > 0 else 0.0), 1.9, y == 0.95)


func _build_interior() -> void:
	# four aisles of double-sided shelves (each row = 3 units along Z)
	for ax in [-9.5, -5.0, -0.5, 4.0]:
		for i in 3:
			_gondola(Vector3(ax, 0, -1.5 + i * 2.0), PI / 2)
	# wall shelves along the left wall
	for i in 6:
		var pos := Vector3(-12.7, 0, -5.0 + i * 2.0)
		static_mesh("wall_shelf", pos, -PI / 2, [[Vector3(0, 0.075, 0), Vector3(2.0, 0.15, 0.5)],
				[Vector3(0, 1.0, 0.23), Vector3(2.0, 2.0, 0.04)], [Vector3(0, 0.55, 0), Vector3(1.95, 0.03, 0.45)],
				[Vector3(0, 0.95, 0), Vector3(1.95, 0.03, 0.45)], [Vector3(0, 1.35, 0), Vector3(1.95, 0.03, 0.45)],
				[Vector3(0, 1.75, 0), Vector3(1.95, 0.03, 0.45)]], "wood")
		for y in [0.15, 0.55, 0.95, 1.35, 1.75]:
			stock_shelf(pos + Vector3(0, y + 0.015, 0), -PI / 2, 1.9, false)
	# coolers along the back wall
	for i in 8:
		var fp := Vector3(-11.0 + i * 1.3, 0, 8.55)
		static_mesh("freezer", fp, 0.0, [[Vector3(0, 1.0, 0), Vector3(1.25, 2.0, 0.7)]])
		for y in [0.12, 0.51, 0.91, 1.31]:
			stock_shelf(fp + Vector3(0, y + 0.01, -0.02), 0.0, 1.1, false)
	# checkouts by the entrance
	for cx in [-7.5, -4.5, 4.5, 7.5]:
		static_mesh("checkout", Vector3(cx, 0, -6.0), PI / 2, [[Vector3(0, 0.45, 0), Vector3(1.8, 0.9, 0.6)]])
	# stock room: boxes and a pallet
	for p in [Vector3(10.0, 0.4, 6.2), Vector3(10.9, 0.4, 6.0), Vector3(10.4, 1.2, 6.1), Vector3(12.0, 0.4, 7.8),
			Vector3(11.2, 0.4, 8.0)]:
		prop(p, [[Vector3.ZERO, Vector3(0.78, 0.78, 0.78), mats.cardboard]], 8.0, "soft", randf_range(-0.3, 0.3))
	for i in 3:
		_cart(Vector3(-11.5 + i * 0.7, 0.05, -7.6), PI)
	_flush_decor()
