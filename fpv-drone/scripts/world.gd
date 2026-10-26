extends Node3D
## Builds the valley procedurally: terrain with grass and trees, a lake,
## a city with streets and towers, mountains around the edge and race gates.

const SIZE := 1400.0
const RES := 200
const CELL := SIZE / RES
const CHUNKS := 8

const CITY_ORIGIN := Vector2(20.0, -280.0) # centre line of the first street
const CITY_PITCH := 52.0
const CITY_BLOCKS := 5
const ROAD_HALF := 6.0
const CITY_CENTER := Vector2(150.0, -150.0)
const CITY_HALF := 136.0
const PARK_A := Vector2i(1, 3)
const PARK_B := Vector2i(3, 1)

const LAKE_CENTER := Vector2(-170.0, -40.0)
const LAKE_RADIUS := 66.0
const WATER_Y := -1.6

const SPAWN := Vector2(-60.0, 90.0)
const SPAWN_Y := 1.0

const GRASS_CHUNK := 60.0
const GRASS_EXTENT := 420.0
const GRASS_TRIES := 1100

const GATE_RADIUS := 4.0
## x, z, height above ground (or above water)
const GATE_PLAN := [
	[-20.0, 45.0, 4.0],
	[-75.0, -15.0, 5.0],
	[-170.0, -40.0, 5.0],
	[-110.0, -135.0, 6.0],
	[20.0, -124.0, 6.0],
	[124.0, -124.0, 8.0],
	[176.0, -176.0, 10.0],
	[176.0, -280.0, 26.0],
	[300.0, -370.0, 18.0],
	[170.0, -480.0, 22.0],
	[0.0, -430.0, 20.0],
	[-160.0, -270.0, 12.0],
	[-125.0, 55.0, 5.0],
	[-58.0, 70.0, 3.5],
]

var heights := PackedFloat32Array()
var normals := PackedVector3Array()
var gates: Array[Node3D] = []
var gate_dirs: Array[Vector3] = []
var grass_multimeshes: Array[MultiMesh] = []
var beacon_material: StandardMaterial3D

var _gate_meshes: Array[MeshInstance3D] = []
var _gate_mat_next: StandardMaterial3D
var _gate_mat_idle: StandardMaterial3D
var _gate_mat_done: StandardMaterial3D
var _rng := RandomNumberGenerator.new()
var _hills := FastNoiseLite.new()
var _ridges := FastNoiseLite.new()
var _detail := FastNoiseLite.new()
var _forest := FastNoiseLite.new()
var _body: StaticBody3D
var _beacons: Array[Vector3] = []


func build() -> void:
	_rng.seed = 1337
	_setup_noise()
	_body = StaticBody3D.new()
	_body.name = "Collision"
	add_child(_body)
	_compute_heights()
	_build_terrain()
	_build_water()
	_build_city()
	_build_trees()
	_build_grass()
	_build_gates()
	_build_launch_pad()


func _setup_noise() -> void:
	_hills.seed = 7
	_hills.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_hills.frequency = 0.0045
	_hills.fractal_type = FastNoiseLite.FRACTAL_FBM
	_hills.fractal_octaves = 4
	_ridges.seed = 21
	_ridges.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_ridges.frequency = 0.0032
	_ridges.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_ridges.fractal_octaves = 5
	_detail.seed = 3
	_detail.frequency = 0.03
	_detail.fractal_octaves = 2
	_forest.seed = 99
	_forest.frequency = 0.012
	_forest.fractal_octaves = 2


# --- Height field ---------------------------------------------------------

## Exact terrain height from the noise functions.
func ground_height(x: float, z: float) -> float:
	var h := _hills.get_noise_2d(x, z) * 9.0
	var d := Vector2(x, z).length()
	var m := smoothstep(360.0, 610.0, d)
	if m > 0.0:
		var r := _ridges.get_noise_2d(x, z) * 0.5 + 0.5
		h += m * (25.0 + 240.0 * r * r) + m * m * 70.0
	var lake := 1.0 - smoothstep(0.55, 1.2, Vector2(x, z).distance_to(LAKE_CENTER) / LAKE_RADIUS)
	h = lerpf(h, -6.0, lake)
	var city := 1.0 - smoothstep(0.0, 45.0, _city_box_distance(x, z))
	h = lerpf(h, -0.3, city)
	var pad := 1.0 - smoothstep(8.0, 32.0, Vector2(x, z).distance_to(SPAWN))
	h = lerpf(h, SPAWN_Y, pad)
	return h


## Height read back from the generated grid (matches the visible mesh).
func grid_height(x: float, z: float) -> float:
	var fx := clampf((x + SIZE * 0.5) / CELL, 0.0, RES - 0.001)
	var fz := clampf((z + SIZE * 0.5) / CELL, 0.0, RES - 0.001)
	var ix := int(fx)
	var iz := int(fz)
	var tx := fx - ix
	var tz := fz - iz
	var i := iz * (RES + 1) + ix
	var top := lerpf(heights[i], heights[i + 1], tx)
	var bottom := lerpf(heights[i + RES + 1], heights[i + RES + 2], tx)
	return lerpf(top, bottom, tz)


func grid_normal(x: float, z: float) -> Vector3:
	var ix := clampi(roundi((x + SIZE * 0.5) / CELL), 0, RES)
	var iz := clampi(roundi((z + SIZE * 0.5) / CELL), 0, RES)
	return normals[iz * (RES + 1) + ix]


## Height of whatever the drone would stand on: terrain or water surface.
func surface_height(x: float, z: float) -> float:
	var h := grid_height(x, z)
	if in_lake(x, z):
		h = maxf(h, WATER_Y)
	return h


func in_lake(x: float, z: float) -> bool:
	return Vector2(x, z).distance_to(LAKE_CENTER) < LAKE_RADIUS * 1.15 and grid_height(x, z) < WATER_Y


func _city_box_distance(x: float, z: float) -> float:
	return maxf(absf(x - CITY_CENTER.x), absf(z - CITY_CENTER.y)) - CITY_HALF


func _compute_heights() -> void:
	var n := RES + 1
	heights.resize(n * n)
	normals.resize(n * n)
	for iz in n:
		for ix in n:
			heights[iz * n + ix] = ground_height(-SIZE * 0.5 + ix * CELL, -SIZE * 0.5 + iz * CELL)
	for iz in n:
		for ix in n:
			var l := heights[iz * n + maxi(ix - 1, 0)]
			var r := heights[iz * n + mini(ix + 1, RES)]
			var u := heights[maxi(iz - 1, 0) * n + ix]
			var d := heights[mini(iz + 1, RES) * n + ix]
			normals[iz * n + ix] = Vector3(l - r, 2.0 * CELL, u - d).normalized()


func _terrain_color(x: float, z: float, h: float, nrm: Vector3) -> Color:
	var v := _detail.get_noise_2d(x, z) * 0.5 + 0.5
	var lush := Color(0.30, 0.46, 0.15)
	var dry := Color(0.50, 0.53, 0.22)
	var c := lush.lerp(dry, v * 0.8)
	var rock := Color(0.42, 0.40, 0.38).lerp(Color(0.30, 0.29, 0.28), v)
	var slope := 1.0 - nrm.y
	var rockiness := clampf(smoothstep(0.18, 0.38, slope) + smoothstep(55.0, 110.0, h), 0.0, 1.0)
	c = c.lerp(rock, rockiness)
	var snow := smoothstep(150.0, 190.0, h + v * 30.0) * (1.0 - smoothstep(0.3, 0.5, slope))
	c = c.lerp(Color(0.93, 0.94, 0.97), snow)
	var shore := 1.0 - smoothstep(0.95, 1.12, Vector2(x, z).distance_to(LAKE_CENTER) / LAKE_RADIUS)
	c = c.lerp(Color(0.62, 0.56, 0.42), shore)
	if _city_box_distance(x, z) < 0.0:
		c = Color(0.3, 0.3, 0.3)
	return c


# --- Terrain ---------------------------------------------------------------

func _build_terrain() -> void:
	var n := RES + 1
	var colors := PackedColorArray()
	colors.resize(n * n)
	for iz in n:
		for ix in n:
			var i := iz * n + ix
			colors[i] = _terrain_color(-SIZE * 0.5 + ix * CELL, -SIZE * 0.5 + iz * CELL, heights[i], normals[i])

	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.roughness = 0.95

	var per := RES / CHUNKS
	for cz in CHUNKS:
		for cx in CHUNKS:
			var verts := PackedVector3Array()
			var norms := PackedVector3Array()
			var cols := PackedColorArray()
			var idx := PackedInt32Array()
			for iz in range(cz * per, cz * per + per + 1):
				for ix in range(cx * per, cx * per + per + 1):
					var i := iz * n + ix
					verts.append(Vector3(-SIZE * 0.5 + ix * CELL, heights[i], -SIZE * 0.5 + iz * CELL))
					norms.append(normals[i])
					cols.append(colors[i])
			var w := per + 1
			for r in per:
				for c in per:
					var a := r * w + c
					var b := a + w
					# Godot treats clockwise triangles as front faces.
					idx.append(a)
					idx.append(a + 1)
					idx.append(b + 1)
					idx.append(a)
					idx.append(b + 1)
					idx.append(b)
			var arrays := []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = verts
			arrays[Mesh.ARRAY_NORMAL] = norms
			arrays[Mesh.ARRAY_COLOR] = cols
			arrays[Mesh.ARRAY_INDEX] = idx
			var mesh := ArrayMesh.new()
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			mesh.surface_set_material(0, mat)
			var mi := MeshInstance3D.new()
			mi.mesh = mesh
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mi)

	var shape := HeightMapShape3D.new()
	shape.map_width = n
	shape.map_depth = n
	var data := PackedFloat32Array()
	data.resize(n * n)
	for i in n * n:
		data[i] = heights[i] / CELL
	shape.map_data = data
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.scale = Vector3(CELL, CELL, CELL)
	_body.add_child(cs)


func _build_water() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(LAKE_RADIUS * 2.6, LAKE_RADIUS * 2.6)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/water.gdshader")
	mat.set_shader_parameter("radius", LAKE_RADIUS * 1.28)
	plane.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = plane
	mi.position = Vector3(LAKE_CENTER.x, WATER_Y, LAKE_CENTER.y)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _build_launch_pad() -> void:
	var pad := CylinderMesh.new()
	pad.top_radius = 2.4
	pad.bottom_radius = 2.6
	pad.height = 0.3
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.12, 0.13, 0.15)
	mat.roughness = 0.7
	pad.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = pad
	mi.position = Vector3(SPAWN.x, SPAWN_Y - 0.1, SPAWN.y)
	add_child(mi)
	var ring := TorusMesh.new()
	ring.inner_radius = 1.7
	ring.outer_radius = 1.95
	var ring_mat := StandardMaterial3D.new()
	ring_mat.albedo_color = Color(1.0, 0.55, 0.12)
	ring_mat.emission_enabled = true
	ring_mat.emission = Color(1.0, 0.5, 0.1)
	ring_mat.emission_energy_multiplier = 1.5
	ring.material = ring_mat
	var ri := MeshInstance3D.new()
	ri.mesh = ring
	ri.scale = Vector3(1.0, 0.25, 1.0)
	ri.position = Vector3(SPAWN.x, SPAWN_Y + 0.06, SPAWN.y)
	add_child(ri)


# --- City ------------------------------------------------------------------

func _build_city() -> void:
	var ground := PlaneMesh.new()
	ground.size = Vector2(CITY_HALF * 2.0, CITY_HALF * 2.0)
	var gmat := ShaderMaterial.new()
	gmat.shader = load("res://shaders/city_ground.gdshader")
	gmat.set_shader_parameter("origin", CITY_ORIGIN)
	gmat.set_shader_parameter("pitch", CITY_PITCH)
	gmat.set_shader_parameter("road_half", ROAD_HALF)
	gmat.set_shader_parameter("park_a", Vector2(PARK_A))
	gmat.set_shader_parameter("park_b", Vector2(PARK_B))
	ground.material = gmat
	var gi := MeshInstance3D.new()
	gi.mesh = ground
	gi.position = Vector3(CITY_CENTER.x, 0.0, CITY_CENTER.y)
	gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(gi)
	var floor_shape := BoxShape3D.new()
	floor_shape.size = Vector3(CITY_HALF * 2.0, 1.0, CITY_HALF * 2.0)
	var fcs := CollisionShape3D.new()
	fcs.shape = floor_shape
	fcs.position = Vector3(CITY_CENTER.x, -0.5, CITY_CENTER.y)
	_body.add_child(fcs)

	var unit: Array = BoxMesh.new().get_mesh_arrays()
	_unit_verts = unit[Mesh.ARRAY_VERTEX]
	_unit_norms = unit[Mesh.ARRAY_NORMAL]
	_unit_idx = unit[Mesh.ARRAY_INDEX]

	var palette: Array[Color] = [
		Color(0.72, 0.66, 0.56), Color(0.60, 0.58, 0.55), Color(0.55, 0.36, 0.28),
		Color(0.78, 0.75, 0.68), Color(0.44, 0.46, 0.50), Color(0.66, 0.52, 0.40),
	]
	var glass_tints: Array[Color] = [
		Color(0.36, 0.48, 0.56), Color(0.30, 0.38, 0.42), Color(0.46, 0.52, 0.55),
	]

	var park_trees: Array[Vector2] = []
	for bi in CITY_BLOCKS:
		for bj in CITY_BLOCKS:
			var x0 := CITY_ORIGIN.x + bi * CITY_PITCH + ROAD_HALF + 3.0
			var z0 := CITY_ORIGIN.y + bj * CITY_PITCH + ROAD_HALF + 3.0
			var inner := CITY_PITCH - 2.0 * (ROAD_HALF + 3.0)
			if Vector2i(bi, bj) == PARK_A or Vector2i(bi, bj) == PARK_B:
				for t in 9:
					park_trees.append(Vector2(x0 + _rng.randf_range(3.0, inner - 3.0), z0 + _rng.randf_range(3.0, inner - 3.0)))
				continue
			var center := Vector2(x0 + inner * 0.5, z0 + inner * 0.5)
			var dc := clampf(center.distance_to(CITY_CENTER) / 190.0, 0.0, 1.0)
			var tall := lerpf(100.0, 16.0, dc)
			if dc < 0.55 and _rng.randf() < 0.45:
				var w := _rng.randf_range(22.0, 28.0)
				var d := _rng.randf_range(22.0, 28.0)
				var h := tall * _rng.randf_range(0.85, 1.3)
				var tint := glass_tints[_rng.randi() % glass_tints.size()].srgb_to_linear()
				tint.a = 1.0
				_add_box(Vector3(center.x, h * 0.5, center.y), Vector3(w, h, d), tint)
				var top_h := h * _rng.randf_range(0.15, 0.3)
				_add_box(Vector3(center.x, h + top_h * 0.5, center.y), Vector3(w * 0.62, top_h, d * 0.62), tint)
				_beacons.append(Vector3(center.x, h + top_h + 1.2, center.y))
				continue
			var lot := inner * 0.5
			for li in 2:
				for lj in 2:
					if _rng.randf() < 0.1:
						continue
					var lc := Vector2(x0 + lot * (li + 0.5), z0 + lot * (lj + 0.5))
					var w := _rng.randf_range(11.0, lot - 2.0)
					var d := _rng.randf_range(11.0, lot - 2.0)
					var h := maxf(8.0, tall * _rng.randf_range(0.3, 0.9))
					var col := palette[_rng.randi() % palette.size()].srgb_to_linear()
					col.a = 0.0
					_add_box(Vector3(lc.x, h * 0.5, lc.y), Vector3(w, h, d), col)
					if h > 45.0:
						var top_h := _rng.randf_range(6.0, 14.0)
						_add_box(Vector3(lc.x, h + top_h * 0.5, lc.y), Vector3(w * 0.6, top_h, d * 0.6), col)
						_beacons.append(Vector3(lc.x, h + top_h + 1.0, lc.y))

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _bverts
	arrays[Mesh.ARRAY_NORMAL] = _bnorms
	arrays[Mesh.ARRAY_COLOR] = _bcols
	arrays[Mesh.ARRAY_INDEX] = _bidx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var bmat := ShaderMaterial.new()
	bmat.shader = load("res://shaders/building.gdshader")
	mesh.surface_set_material(0, bmat)
	var bi_node := MeshInstance3D.new()
	bi_node.mesh = mesh
	add_child(bi_node)

	# Red aircraft-warning lights on the tall roofs.
	var sphere := SphereMesh.new()
	sphere.radius = 0.6
	sphere.height = 1.2
	sphere.radial_segments = 8
	sphere.rings = 4
	beacon_material = StandardMaterial3D.new()
	beacon_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	beacon_material.albedo_color = Color(1.0, 0.1, 0.05)
	beacon_material.emission_enabled = true
	beacon_material.emission = Color(1.0, 0.08, 0.04)
	beacon_material.emission_energy_multiplier = 4.0
	sphere.material = beacon_material
	var bx: Array[Transform3D] = []
	var bc: Array[Color] = []
	for p in _beacons:
		bx.append(Transform3D(Basis(), p))
		bc.append(Color.WHITE)
	var beacons := _multimesh(sphere, bx, bc)
	beacons.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	for p in park_trees:
		_queued_trees.append(Vector3(p.x, 0.0, p.y))


var _unit_verts := PackedVector3Array()
var _unit_norms := PackedVector3Array()
var _unit_idx := PackedInt32Array()
var _bverts := PackedVector3Array()
var _bnorms := PackedVector3Array()
var _bcols := PackedColorArray()
var _bidx := PackedInt32Array()


## Adds one building box to the merged city mesh and to the collision body.
func _add_box(center: Vector3, size: Vector3, color: Color) -> void:
	var base := _bverts.size()
	for p in _unit_verts:
		_bverts.append(p * size + center)
	_bnorms.append_array(_unit_norms)
	for i in _unit_verts.size():
		_bcols.append(color)
	for i in _unit_idx:
		_bidx.append(i + base)
	var shape := BoxShape3D.new()
	shape.size = size
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = center
	_body.add_child(cs)


# --- Trees -----------------------------------------------------------------

var _queued_trees: Array[Vector3] = []


func _build_trees() -> void:
	var gate_spots: Array[Vector2] = []
	for g: Array in GATE_PLAN:
		var gx: float = g[0]
		var gz: float = g[1]
		gate_spots.append(Vector2(gx, gz))

	var spots: Array[Vector3] = []
	spots.append_array(_queued_trees)
	var tries := 9000
	while tries > 0 and spots.size() < 1300:
		tries -= 1
		var x := _rng.randf_range(-660.0, 660.0)
		var z := _rng.randf_range(-660.0, 660.0)
		if _city_box_distance(x, z) < 8.0:
			continue
		if Vector2(x, z).distance_to(LAKE_CENTER) < LAKE_RADIUS * 1.2:
			continue
		if Vector2(x, z).distance_to(SPAWN) < 26.0:
			continue
		var blocked := false
		for g in gate_spots:
			if g.distance_to(Vector2(x, z)) < 12.0:
				blocked = true
				break
		if blocked:
			continue
		var h := grid_height(x, z)
		if h > 160.0 or grid_normal(x, z).y < 0.8:
			continue
		if _forest.get_noise_2d(x, z) < -0.05:
			continue
		spots.append(Vector3(x, h, z))

	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.16
	trunk.bottom_radius = 0.26
	trunk.height = 3.0
	trunk.radial_segments = 6
	trunk.rings = 1
	var trunk_mat := StandardMaterial3D.new()
	trunk_mat.albedo_color = Color(0.32, 0.22, 0.14)
	trunk_mat.vertex_color_use_as_albedo = true
	trunk.material = trunk_mat

	var pine := CylinderMesh.new()
	pine.top_radius = 0.0
	pine.bottom_radius = 2.3
	pine.height = 7.5
	pine.radial_segments = 8
	pine.rings = 2
	var pine_mat := StandardMaterial3D.new()
	pine_mat.albedo_color = Color(0.13, 0.27, 0.13)
	pine_mat.vertex_color_use_as_albedo = true
	pine_mat.roughness = 0.9
	pine.material = pine_mat

	var leafy := SphereMesh.new()
	leafy.radius = 2.6
	leafy.height = 4.6
	leafy.radial_segments = 9
	leafy.rings = 5
	var leafy_mat := StandardMaterial3D.new()
	leafy_mat.albedo_color = Color(0.25, 0.40, 0.12)
	leafy_mat.vertex_color_use_as_albedo = true
	leafy_mat.roughness = 0.9
	leafy.material = leafy_mat

	var trunk_x: Array[Transform3D] = []
	var trunk_c: Array[Color] = []
	var pine_x: Array[Transform3D] = []
	var pine_c: Array[Color] = []
	var leafy_x: Array[Transform3D] = []
	var leafy_c: Array[Color] = []

	var pine_shape := CylinderShape3D.new()
	pine_shape.radius = 1.5
	pine_shape.height = 9.0
	var leafy_shape := CylinderShape3D.new()
	leafy_shape.radius = 2.0
	leafy_shape.height = 7.0

	for p in spots:
		var s := _rng.randf_range(0.75, 1.35)
		var is_pine := p.y > 22.0 or _rng.randf() < 0.3
		var rot := Basis(Vector3.UP, _rng.randf() * TAU)
		var shade := Color(1, 1, 1).darkened(_rng.randf_range(0.0, 0.3))
		trunk_x.append(Transform3D(rot.scaled(Vector3(s, s, s)), p + Vector3(0, 1.4 * s, 0)))
		trunk_c.append(shade)
		var cs := CollisionShape3D.new()
		cs.scale = Vector3(s, s, s)
		if is_pine:
			pine_x.append(Transform3D(rot.scaled(Vector3(s, s, s)), p + Vector3(0, 6.2 * s, 0)))
			pine_c.append(shade)
			cs.shape = pine_shape
			cs.position = p + Vector3(0, 4.5 * s, 0)
		else:
			leafy_x.append(Transform3D(rot.scaled(Vector3(s, s * _rng.randf_range(0.85, 1.15), s)), p + Vector3(0, 4.6 * s, 0)))
			leafy_c.append(shade)
			cs.shape = leafy_shape
			cs.position = p + Vector3(0, 3.5 * s, 0)
		_body.add_child(cs)

	_multimesh(trunk, trunk_x, trunk_c)
	_multimesh(pine, pine_x, pine_c)
	_multimesh(leafy, leafy_x, leafy_c)


# --- Grass -----------------------------------------------------------------

func _grass_mesh() -> ArrayMesh:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	for k in 5:
		var a := k * TAU / 5.0 + 0.4
		var dir := Vector3(cos(a), 0.0, sin(a))
		var side := Vector3(-sin(a), 0.0, cos(a))
		var off := Vector3(sin(a * 3.0), 0.0, cos(a * 2.0)) * 0.14
		var half_w := 0.07
		var hgt := 0.45 + 0.1 * float(k % 3)
		verts.append(off - dir * half_w)
		verts.append(off + dir * half_w)
		verts.append(off + Vector3(0.0, hgt, 0.0) + side * 0.12)
		uvs.append(Vector2(0.0, 0.0))
		uvs.append(Vector2(1.0, 0.0))
		uvs.append(Vector2(0.5, 1.0))
		for j in 3:
			norms.append(Vector3.UP)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/grass.gdshader")
	mesh.surface_set_material(0, mat)
	return mesh


func _grass_ok(x: float, z: float) -> bool:
	if _city_box_distance(x, z) < 1.0:
		return false
	if Vector2(x, z).distance_to(LAKE_CENTER) < LAKE_RADIUS * 1.02:
		return false
	if Vector2(x, z).distance_to(SPAWN) < 3.0:
		return false
	if grid_normal(x, z).y < 0.9:
		return false
	return grid_height(x, z) < 40.0


func _build_grass() -> void:
	var mesh := _grass_mesh()
	var count := ceili(GRASS_EXTENT * 2.0 / GRASS_CHUNK)
	for cz in count:
		for cx in count:
			var x0 := -GRASS_EXTENT + cx * GRASS_CHUNK
			var z0 := -GRASS_EXTENT + cz * GRASS_CHUNK
			var mid := Vector2(x0, z0) + Vector2.ONE * GRASS_CHUNK * 0.5
			if mid.length() > 560.0 or _city_box_distance(mid.x, mid.y) < -GRASS_CHUNK:
				continue
			var xforms: Array[Transform3D] = []
			var cols: Array[Color] = []
			for i in GRASS_TRIES:
				var x := x0 + _rng.randf() * GRASS_CHUNK
				var z := z0 + _rng.randf() * GRASS_CHUNK
				if not _grass_ok(x, z):
					continue
				var s := _rng.randf_range(0.8, 1.5)
				var basis := Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(s, s * _rng.randf_range(0.8, 1.4), s))
				xforms.append(Transform3D(basis, Vector3(x, grid_height(x, z) - 0.04, z)))
				var tone := 0.75 + 0.4 * (_detail.get_noise_2d(x, z) * 0.5 + 0.5)
				cols.append(Color(tone, tone, tone * 0.9))
			if xforms.is_empty():
				continue
			var mmi := _multimesh(mesh, xforms, cols)
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mmi.visibility_range_end = 140.0
			grass_multimeshes.append(mmi.multimesh)


## Shows a fraction (0..1) of the generated grass, for the quality setting.
func set_grass_density(fraction: float) -> void:
	for mm in grass_multimeshes:
		mm.visible_instance_count = int(mm.instance_count * fraction)


# --- Gates -----------------------------------------------------------------

func gate_position(i: int) -> Vector3:
	var g: Array = GATE_PLAN[i]
	var x: float = g[0]
	var z: float = g[1]
	var base := ground_height(x, z)
	if Vector2(x, z).distance_to(LAKE_CENTER) < LAKE_RADIUS:
		base = maxf(base, WATER_Y)
	if _city_box_distance(x, z) < 0.0:
		base = 0.0
	var above: float = g[2]
	return Vector3(x, base + above, z)


func _build_gates() -> void:
	_gate_mat_next = _glow_material(Color(1.0, 0.55, 0.1), 4.0)
	_gate_mat_idle = _glow_material(Color(0.85, 0.9, 1.0), 0.7)
	_gate_mat_done = _glow_material(Color(0.3, 1.0, 0.45), 1.2)
	var torus := TorusMesh.new()
	torus.inner_radius = GATE_RADIUS - 0.35
	torus.outer_radius = GATE_RADIUS + 0.3
	torus.rings = 40
	torus.ring_segments = 10
	var font: Font = load("res://fonts/RussoOne-Regular.ttf")
	var positions: Array[Vector3] = []
	for i in GATE_PLAN.size():
		positions.append(gate_position(i))
	for i in positions.size():
		var prev := positions[i - 1] if i > 0 else Vector3(SPAWN.x, SPAWN_Y, SPAWN.y)
		var next := positions[i + 1] if i < positions.size() - 1 else positions[i] + (positions[i] - prev)
		var dir := (next - prev).normalized()
		var flat := Vector3(dir.x, dir.y * 0.4, dir.z).normalized()
		var gate := Node3D.new()
		gate.name = "Gate%d" % (i + 1)
		add_child(gate)
		gate.position = positions[i]
		gate.look_at(positions[i] + flat, Vector3.UP)
		var mi := MeshInstance3D.new()
		mi.mesh = torus
		mi.rotation_degrees = Vector3(90.0, 0.0, 0.0)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		gate.add_child(mi)
		var label := Label3D.new()
		label.text = str(i + 1)
		label.font = font
		label.font_size = 96
		label.pixel_size = 0.02
		label.outline_size = 18
		label.modulate = Color(1, 1, 1, 0.95)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.position = Vector3(0.0, GATE_RADIUS + 1.6, 0.0)
		gate.add_child(label)
		gates.append(gate)
		gate_dirs.append(-gate.global_transform.basis.z)
		_gate_meshes.append(mi)
	highlight_gates(0)


## Colours gates: passed ones green, the next one orange, the rest pale.
func highlight_gates(next_index: int) -> void:
	for i in _gate_meshes.size():
		var mat := _gate_mat_idle
		if i < next_index:
			mat = _gate_mat_done
		elif i == next_index:
			mat = _gate_mat_next
		_gate_meshes[i].material_override = mat


func _glow_material(color: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	m.roughness = 0.4
	return m


# --- Helpers ---------------------------------------------------------------

func _multimesh(mesh: Mesh, xforms: Array[Transform3D], colors: Array[Color]) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		mm.set_instance_color(i, colors[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	add_child(mmi)
	return mmi
