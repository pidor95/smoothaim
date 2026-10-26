extends Node3D
## Builds the valley procedurally: a 3.6 km map with meadows, highlands,
## two lakes, a city, a village with fields, a wind farm, hot-air balloons,
## a ring of snowy mountains and a race of gates through all of it.
##
## Performance: the terrain is one heightfield split into culled chunks, grass
## only exists in a small ring of chunks around the drone, and trees are grouped
## in tiles that disappear in the distance.

const SIZE := 3600.0
const RES := 320
const CELL := SIZE / RES
const CHUNKS := 16

const CITY_CENTER := Vector2(420.0, -480.0)
const CITY_BLOCKS := 7
const CITY_PITCH := 52.0
const ROAD_HALF := 6.0
const CITY_HALF := CITY_BLOCKS * CITY_PITCH * 0.5 + ROAD_HALF
## Centre line of the first street on each axis.
const CITY_ORIGIN := Vector2(CITY_CENTER.x - CITY_BLOCKS * CITY_PITCH * 0.5, CITY_CENTER.y - CITY_BLOCKS * CITY_PITCH * 0.5)
const PARK_A := Vector2i(1, 5)
const PARK_B := Vector2i(5, 1)

## Lakes: centre x, centre z, radius.
const LAKES := [[-420.0, -120.0, 140.0], [650.0, 520.0, 95.0]]
const WATER_Y := -1.6

const SPAWN := Vector2(-60.0, 90.0)
const VILLAGE := Vector2(-720.0, 600.0)
const WIND_FARM := Vector2(1050.0, -150.0)

const GATE_RADIUS := 4.5
## x, z, height above ground (or above water)
const GATE_PLAN := [
	[-20.0, 30.0, 4.0],
	[-200.0, -60.0, 6.0],
	[-420.0, -120.0, 5.0],
	[-560.0, -380.0, 8.0],
	[-200.0, -560.0, 10.0],
	[238.0, -454.0, 6.0],
	[394.0, -454.0, 8.0],
	[446.0, -506.0, 12.0],
	[498.0, -610.0, 30.0],
	[602.0, -662.0, 40.0],
	[880.0, -330.0, 25.0],
	[1050.0, -150.0, 30.0],
	[650.0, 520.0, 5.0],
	[300.0, 700.0, 8.0],
	[-720.0, 600.0, 12.0],
	[-920.0, 250.0, 15.0],
	[-480.0, 160.0, 6.0],
	[-58.0, 70.0, 3.5],
]

const GRASS_CHUNK := 36.0
const TREE_TILE := 450.0

var heights := PackedFloat32Array()
var normals := PackedVector3Array()
var spawn_y := 1.0
var gates: Array[Node3D] = []
var gate_dirs: Array[Vector3] = []
var beacon_material: StandardMaterial3D

var _village_y := 0.0
var _gate_meshes: Array[MeshInstance3D] = []
var _gate_mat_next: StandardMaterial3D
var _gate_mat_idle: StandardMaterial3D
var _gate_mat_done: StandardMaterial3D
var _rng := RandomNumberGenerator.new()
var _hills := FastNoiseLite.new()
var _highland := FastNoiseLite.new()
var _ridges := FastNoiseLite.new()
var _detail := FastNoiseLite.new()
var _forest := FastNoiseLite.new()
var _body: StaticBody3D
var _beacons: Array[Vector3] = []
var _gate_spots: Array[Vector2] = []
var _blocked: Array[Vector3] = [] # x, z, radius kept free of trees
var _rotors: Array[Node3D] = []
var _balloons: Array[Node3D] = []
var _balloon_bodies: Array[Node3D] = []
var _balloon_paths: Array[Vector4] = [] # centre x, centre z, radius, phase
var _time := 0.0

var _grass_mesh: ArrayMesh
var _grass_chunks := {} # Vector2i -> MultiMeshInstance3D or null when empty
var _grass_pool: Array[MultiMeshInstance3D] = []
var grass_radius := 3
var grass_tries := 500
var _tree_instances: Array[MultiMeshInstance3D] = []


func build() -> void:
	_rng.seed = 1337
	_setup_noise()
	_body = StaticBody3D.new()
	_body.name = "Collision"
	add_child(_body)
	for g: Array in GATE_PLAN:
		_gate_spots.append(Vector2(float(g[0]), float(g[1])))
	_compute_heights()
	_build_terrain()
	_build_water()
	_build_city()
	_build_village()
	_build_wind_farm()
	_build_balloons()
	_build_trees()
	_grass_mesh = _make_grass_mesh()
	_build_gates()
	_build_launch_pad()


func _setup_noise() -> void:
	_hills.seed = 7
	_hills.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_hills.frequency = 0.0035
	_hills.fractal_octaves = 4
	_highland.seed = 12
	_highland.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_highland.frequency = 0.0011
	_highland.fractal_octaves = 2
	_ridges.seed = 21
	_ridges.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_ridges.frequency = 0.0022
	_ridges.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_ridges.fractal_octaves = 5
	_detail.seed = 3
	_detail.frequency = 0.02
	_detail.fractal_octaves = 2
	_forest.seed = 99
	_forest.frequency = 0.006
	_forest.fractal_octaves = 3
	spawn_y = _raw_height(SPAWN.x, SPAWN.y)
	_village_y = _raw_height(VILLAGE.x, VILLAGE.y)


# --- Height field ---------------------------------------------------------

func _lake_factor(x: float, z: float) -> float:
	var f := 0.0
	for l: Array in LAKES:
		var d := Vector2(x, z).distance_to(Vector2(float(l[0]), float(l[1]))) / float(l[2])
		f = maxf(f, 1.0 - smoothstep(0.55, 1.2, d))
	return f


## Hills and mountains before towns and lakes are cut in.
func _raw_height(x: float, z: float) -> float:
	var p := Vector2(x, z)
	var h := _hills.get_noise_2d(x, z) * 14.0
	# Highlands: rolling ridges in patches, kept away from towns and lakes.
	var keep_flat := minf(smoothstep(320.0, 520.0, p.distance_to(CITY_CENTER)), smoothstep(160.0, 360.0, p.distance_to(SPAWN)))
	keep_flat = minf(keep_flat, smoothstep(260.0, 420.0, p.distance_to(VILLAGE)))
	var mask := smoothstep(0.05, 0.45, _highland.get_noise_2d(x, z)) * keep_flat
	if mask > 0.0:
		var r := _ridges.get_noise_2d(x * 1.7, z * 1.7) * 0.5 + 0.5
		h += mask * (20.0 + 110.0 * r * r)
	var d := p.length()
	var m := smoothstep(1150.0, 1650.0, d)
	if m > 0.0:
		var r2 := _ridges.get_noise_2d(x, z) * 0.5 + 0.5
		h += m * (40.0 + 380.0 * r2 * r2) + m * m * 120.0
	return h


## Exact terrain height from the noise functions.
func ground_height(x: float, z: float) -> float:
	var p := Vector2(x, z)
	var h := _raw_height(x, z)
	h = lerpf(h, -7.0, _lake_factor(x, z))
	h = lerpf(h, -0.3, 1.0 - smoothstep(0.0, 90.0, _city_box_distance(x, z)))
	h = lerpf(h, _village_y, 1.0 - smoothstep(140.0, 230.0, p.distance_to(VILLAGE)))
	h = lerpf(h, spawn_y, 1.0 - smoothstep(10.0, 60.0, p.distance_to(SPAWN)))
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
	if h < WATER_Y and _lake_factor(x, z) > 0.0:
		h = WATER_Y
	return h


func in_lake(x: float, z: float) -> bool:
	return grid_height(x, z) < WATER_Y and _lake_factor(x, z) > 0.0


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


## sRGB vertex colour; alpha marks flat farmland around the village.
func _terrain_color(x: float, z: float, h: float, nrm: Vector3) -> Color:
	var v := _detail.get_noise_2d(x, z) * 0.5 + 0.5
	var lush := Color(0.30, 0.47, 0.15)
	var dry := Color(0.52, 0.54, 0.22)
	var c := lush.lerp(dry, v * 0.8)
	# Forest floor is darker.
	c = c.darkened(clampf(_forest.get_noise_2d(x, z) * 0.6, 0.0, 0.25))
	var rock := Color(0.45, 0.42, 0.40).lerp(Color(0.32, 0.30, 0.29), v)
	var slope := 1.0 - nrm.y
	var rockiness := clampf(smoothstep(0.2, 0.42, slope) + smoothstep(120.0, 220.0, h), 0.0, 1.0)
	c = c.lerp(rock, rockiness)
	var snow := smoothstep(260.0, 330.0, h + v * 40.0) * (1.0 - smoothstep(0.35, 0.6, slope))
	c = c.lerp(Color(0.94, 0.95, 0.98), snow)
	c = c.lerp(Color(0.64, 0.58, 0.44), smoothstep(0.1, 0.4, _lake_factor(x, z)))
	if _city_box_distance(x, z) < 0.0:
		c = Color(0.3, 0.3, 0.3)
	var dv := Vector2(x, z).distance_to(VILLAGE)
	var farm := smoothstep(150.0, 190.0, dv) * (1.0 - smoothstep(430.0, 480.0, dv)) * (1.0 - rockiness)
	c.a = farm
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

	var noise_tex := NoiseTexture2D.new()
	noise_tex.width = 256
	noise_tex.height = 256
	noise_tex.seamless = true
	noise_tex.generate_mipmaps = true
	var tex_noise := FastNoiseLite.new()
	tex_noise.frequency = 0.02
	tex_noise.fractal_octaves = 4
	noise_tex.noise = tex_noise
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/terrain.gdshader")
	mat.set_shader_parameter("detail", noise_tex)
	mat.set_shader_parameter("village", VILLAGE)

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
	var shader: Shader = load("res://shaders/water.gdshader")
	for l: Array in LAKES:
		var radius: float = l[2]
		var plane := PlaneMesh.new()
		plane.size = Vector2(radius * 2.7, radius * 2.7)
		var mat := ShaderMaterial.new()
		mat.shader = shader
		mat.set_shader_parameter("radius", radius * 1.3)
		plane.material = mat
		var mi := MeshInstance3D.new()
		mi.mesh = plane
		mi.position = Vector3(float(l[0]), WATER_Y, float(l[1]))
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)


func _build_launch_pad() -> void:
	var pad := CylinderMesh.new()
	pad.top_radius = 2.4
	pad.bottom_radius = 2.6
	pad.height = 0.3
	pad.material = _plain(Color(0.12, 0.13, 0.15), 0.7)
	var mi := MeshInstance3D.new()
	mi.mesh = pad
	mi.position = Vector3(SPAWN.x, spawn_y - 0.1, SPAWN.y)
	add_child(mi)
	var ring := TorusMesh.new()
	ring.inner_radius = 1.7
	ring.outer_radius = 1.95
	ring.material = _glow_material(Color(1.0, 0.55, 0.12), 1.5)
	var ri := MeshInstance3D.new()
	ri.mesh = ring
	ri.scale = Vector3(1.0, 0.25, 1.0)
	ri.position = Vector3(SPAWN.x, spawn_y + 0.06, SPAWN.y)
	add_child(ri)


# --- City ------------------------------------------------------------------

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
	_add_collider_box(center, size)


func _add_collider_box(center: Vector3, size: Vector3) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = center
	_body.add_child(cs)


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
	_add_collider_box(Vector3(CITY_CENTER.x, -0.5, CITY_CENTER.y), Vector3(CITY_HALF * 2.0, 1.0, CITY_HALF * 2.0))

	var unit: Array = BoxMesh.new().get_mesh_arrays()
	_unit_verts = unit[Mesh.ARRAY_VERTEX]
	_unit_norms = unit[Mesh.ARRAY_NORMAL]
	_unit_idx = unit[Mesh.ARRAY_INDEX]

	var palette: Array[Color] = [
		Color(0.72, 0.66, 0.56), Color(0.60, 0.58, 0.55), Color(0.55, 0.36, 0.28),
		Color(0.78, 0.75, 0.68), Color(0.44, 0.46, 0.50), Color(0.66, 0.52, 0.40),
	]
	var glass_tints: Array[Color] = [
		Color(0.36, 0.48, 0.56), Color(0.30, 0.38, 0.42), Color(0.46, 0.52, 0.55), Color(0.42, 0.40, 0.36),
	]

	var park_trees: Array[Vector3] = []
	for bi in CITY_BLOCKS:
		for bj in CITY_BLOCKS:
			var x0 := CITY_ORIGIN.x + bi * CITY_PITCH + ROAD_HALF + 3.0
			var z0 := CITY_ORIGIN.y + bj * CITY_PITCH + ROAD_HALF + 3.0
			var inner := CITY_PITCH - 2.0 * (ROAD_HALF + 3.0)
			if Vector2i(bi, bj) == PARK_A or Vector2i(bi, bj) == PARK_B:
				for t in 10:
					park_trees.append(Vector3(x0 + _rng.randf_range(3.0, inner - 3.0), 0.0, z0 + _rng.randf_range(3.0, inner - 3.0)))
				continue
			var center := Vector2(x0 + inner * 0.5, z0 + inner * 0.5)
			var dc := clampf(center.distance_to(CITY_CENTER) / (CITY_HALF * 1.3), 0.0, 1.0)
			var tall := lerpf(150.0, 16.0, pow(dc, 0.8))
			if dc < 0.55 and _rng.randf() < 0.5:
				var w := _rng.randf_range(22.0, 28.0)
				var d := _rng.randf_range(22.0, 28.0)
				var h := tall * _rng.randf_range(0.8, 1.25)
				var tint := glass_tints[_rng.randi() % glass_tints.size()].srgb_to_linear()
				tint.a = 1.0
				_add_box(Vector3(center.x, h * 0.5, center.y), Vector3(w, h, d), tint)
				var top_h := h * _rng.randf_range(0.12, 0.25)
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
					var h := maxf(8.0, tall * _rng.randf_range(0.25, 0.8))
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
	var city_mesh := MeshInstance3D.new()
	city_mesh.mesh = mesh
	add_child(city_mesh)

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

	_queued_trees.append_array(park_trees)


# --- Village ---------------------------------------------------------------

func _build_village() -> void:
	var walls: Array[Transform3D] = []
	var wall_cols: Array[Color] = []
	var roofs: Array[Transform3D] = []
	var roof_cols: Array[Color] = []
	var wall_palette: Array[Color] = [Color(0.93, 0.90, 0.82), Color(0.95, 0.86, 0.62), Color(0.80, 0.86, 0.90), Color(0.88, 0.76, 0.66)]
	var roof_palette: Array[Color] = [Color(0.62, 0.18, 0.12), Color(0.42, 0.24, 0.16), Color(0.28, 0.32, 0.36), Color(0.70, 0.36, 0.16)]
	var placed: Array[Vector2] = []
	var tries := 400
	while tries > 0 and placed.size() < 34:
		tries -= 1
		var a := _rng.randf() * TAU
		var r := sqrt(_rng.randf()) * 125.0
		var p := VILLAGE + Vector2(cos(a), sin(a)) * r
		var ok := p.distance_to(VILLAGE) > 22.0
		for q in placed:
			if q.distance_to(p) < 19.0:
				ok = false
				break
		for g in _gate_spots:
			if g.distance_to(p) < 18.0:
				ok = false
				break
		if not ok:
			continue
		placed.append(p)
		var w := _rng.randf_range(7.0, 10.0)
		var d := _rng.randf_range(8.0, 12.0)
		var h := _rng.randf_range(4.0, 6.5)
		var roof_h := _rng.randf_range(2.5, 4.0)
		var y := ground_height(p.x, p.y)
		# Face the village centre.
		var basis := Basis(Vector3.UP, atan2(VILLAGE.x - p.x, VILLAGE.y - p.y))
		walls.append(Transform3D(basis * Basis.from_scale(Vector3(w, h, d)), Vector3(p.x, y + h * 0.5 - 0.3, p.y)))
		wall_cols.append(wall_palette[_rng.randi() % wall_palette.size()].srgb_to_linear())
		roofs.append(Transform3D(basis * Basis.from_scale(Vector3(w + 0.8, roof_h, d + 0.6)), Vector3(p.x, y + h - 0.3 + roof_h * 0.5, p.y)))
		roof_cols.append(roof_palette[_rng.randi() % roof_palette.size()].srgb_to_linear())
		_add_collider_box(Vector3(p.x, y + (h + roof_h) * 0.5, p.y), Vector3(maxf(w, d), h + roof_h, maxf(w, d)))
		_blocked.append(Vector3(p.x, p.y, 10.0))
	var box := BoxMesh.new()
	box.material = _instanced_material(0.85)
	var prism := PrismMesh.new()
	prism.material = _instanced_material(0.7)
	_multimesh(box, walls, wall_cols)
	_multimesh(prism, roofs, roof_cols)
	# A church spire marks the village square.
	var spire := CylinderMesh.new()
	spire.top_radius = 0.0
	spire.bottom_radius = 3.2
	spire.height = 16.0
	spire.radial_segments = 4
	spire.material = _plain(Color(0.28, 0.34, 0.38), 0.6)
	var tower := BoxMesh.new()
	tower.size = Vector3(6.0, 18.0, 6.0)
	tower.material = _plain(Color(0.94, 0.92, 0.86), 0.9)
	var church := Vector3(VILLAGE.x + 40.0, _village_y, VILLAGE.y - 30.0)
	var ti := MeshInstance3D.new()
	ti.mesh = tower
	ti.position = church + Vector3(0, 9.0, 0)
	add_child(ti)
	var si := MeshInstance3D.new()
	si.mesh = spire
	si.position = church + Vector3(0, 26.0, 0)
	si.rotation.y = PI * 0.25
	add_child(si)
	_add_collider_box(church + Vector3(0, 17.0, 0), Vector3(6.5, 34.0, 6.5))
	_blocked.append(Vector3(church.x, church.z, 12.0))


# --- Wind farm and balloons --------------------------------------------------

func _build_wind_farm() -> void:
	var white := _plain(Color(0.92, 0.93, 0.95), 0.5)
	var tower_mesh := CylinderMesh.new()
	tower_mesh.top_radius = 1.1
	tower_mesh.bottom_radius = 2.0
	tower_mesh.height = 70.0
	tower_mesh.radial_segments = 12
	tower_mesh.material = white
	var nacelle := BoxMesh.new()
	nacelle.size = Vector3(3.2, 3.2, 9.0)
	nacelle.material = white
	var blade := BoxMesh.new()
	blade.size = Vector3(1.8, 30.0, 0.35)
	blade.material = white
	var tip_mat := _plain(Color(0.85, 0.15, 0.1), 0.5)
	var tip := BoxMesh.new()
	tip.size = Vector3(1.0, 4.0, 0.4)
	tip.material = tip_mat
	var count := 0
	for i in 12:
		if count >= 9:
			break
		var a := TAU * i / 12.0 + 0.2
		var p := WIND_FARM + Vector2(cos(a), sin(a)) * (170.0 + 60.0 * float(i % 2))
		var near_gate := false
		for g in _gate_spots:
			if g.distance_to(p) < 45.0:
				near_gate = true
		if near_gate:
			continue
		count += 1
		var y := ground_height(p.x, p.y)
		var turbine := Node3D.new()
		turbine.position = Vector3(p.x, y, p.y)
		turbine.rotation.y = 0.6
		add_child(turbine)
		var t := MeshInstance3D.new()
		t.mesh = tower_mesh
		t.position.y = 35.0
		turbine.add_child(t)
		var nm := MeshInstance3D.new()
		nm.mesh = nacelle
		nm.position = Vector3(0, 71.0, 1.5)
		turbine.add_child(nm)
		var rotor := Node3D.new()
		rotor.position = Vector3(0, 71.0, -3.6)
		rotor.rotation.z = _rng.randf() * TAU
		turbine.add_child(rotor)
		for b in 3:
			var arm := Node3D.new()
			arm.rotation.z = TAU * b / 3.0
			rotor.add_child(arm)
			var bm := MeshInstance3D.new()
			bm.mesh = blade
			bm.position.y = 16.0
			arm.add_child(bm)
			var tm := MeshInstance3D.new()
			tm.mesh = tip
			tm.position.y = 29.5
			arm.add_child(tm)
		_rotors.append(rotor)
		var shape := CylinderShape3D.new()
		shape.radius = 2.0
		shape.height = 74.0
		var cs := CollisionShape3D.new()
		cs.shape = shape
		cs.position = Vector3(p.x, y + 37.0, p.y)
		_body.add_child(cs)
		_blocked.append(Vector3(p.x, p.y, 14.0))


func _build_balloons() -> void:
	var colors: Array[Color] = [Color(0.95, 0.25, 0.2), Color(1.0, 0.75, 0.1), Color(0.2, 0.55, 0.95), Color(0.55, 0.85, 0.3), Color(0.9, 0.4, 0.8)]
	var spots: Array[Vector2] = [Vector2(-150, -250), Vector2(150, 250), Vector2(-500, 380), Vector2(800, 150), Vector2(-850, -500)]
	var basket_mesh := BoxMesh.new()
	basket_mesh.size = Vector3(2.4, 1.6, 2.4)
	basket_mesh.material = _plain(Color(0.45, 0.3, 0.18), 0.9)
	for i in spots.size():
		var envelope := SphereMesh.new()
		envelope.radius = 9.0
		envelope.height = 21.0
		envelope.radial_segments = 16
		envelope.rings = 10
		envelope.material = _plain(colors[i], 0.55)
		var skirt := CylinderMesh.new()
		skirt.top_radius = 5.5
		skirt.bottom_radius = 1.8
		skirt.height = 7.0
		skirt.radial_segments = 16
		skirt.material = envelope.material
		var balloon := Node3D.new()
		add_child(balloon)
		var e := MeshInstance3D.new()
		e.mesh = envelope
		balloon.add_child(e)
		var s := MeshInstance3D.new()
		s.mesh = skirt
		s.position.y = -11.5
		balloon.add_child(s)
		var bk := MeshInstance3D.new()
		bk.mesh = basket_mesh
		bk.position.y = -18.5
		balloon.add_child(bk)
		_balloons.append(balloon)
		# A separate static body that follows the balloon, so it can be hit.
		var body := StaticBody3D.new()
		var shape := SphereShape3D.new()
		shape.radius = 9.5
		var cs := CollisionShape3D.new()
		cs.shape = shape
		body.add_child(cs)
		add_child(body)
		_balloon_bodies.append(body)
		var p := spots[i]
		_balloon_paths.append(Vector4(p.x, p.y, _rng.randf_range(60.0, 120.0), _rng.randf() * TAU))
	_update_balloons()


func _update_balloons() -> void:
	for i in _balloons.size():
		var path := _balloon_paths[i]
		var a := path.w + _time * 0.012 * (1.0 + 0.2 * i)
		var x := path.x + cos(a) * path.z
		var z := path.y + sin(a) * path.z
		var y := maxf(ground_height(x, z), WATER_Y) + 70.0 + 15.0 * i + sin(_time * 0.2 + i) * 4.0
		_balloons[i].position = Vector3(x, y, z)
		_balloon_bodies[i].position = Vector3(x, y, z)


func _process(delta: float) -> void:
	_time += delta
	for r in _rotors:
		r.rotate_object_local(Vector3.FORWARD, delta * 0.9)
	_update_balloons()


# --- Trees -----------------------------------------------------------------

var _queued_trees: Array[Vector3] = []


func _tree_allowed(x: float, z: float) -> bool:
	if _city_box_distance(x, z) < 8.0:
		return false
	if _lake_factor(x, z) > 0.0:
		return false
	var p := Vector2(x, z)
	if p.distance_to(SPAWN) < 28.0:
		return false
	for g in _gate_spots:
		if g.distance_to(p) < 14.0:
			return false
	for b in _blocked:
		if Vector2(b.x, b.y).distance_to(p) < b.z:
			return false
	return true


func _build_trees() -> void:
	var spots: Array[Vector3] = []
	spots.append_array(_queued_trees)
	var tries := 40000
	while tries > 0 and spots.size() < 7500:
		tries -= 1
		var x := _rng.randf_range(-1700.0, 1700.0)
		var z := _rng.randf_range(-1700.0, 1700.0)
		var forest := _forest.get_noise_2d(x, z)
		# Dense forests where the noise is high, scattered trees elsewhere.
		if forest < 0.15 and _rng.randf() > 0.12:
			continue
		var dv := Vector2(x, z).distance_to(VILLAGE)
		if dv > 140.0 and dv < 480.0:
			continue # farmland
		if not _tree_allowed(x, z):
			continue
		var h := grid_height(x, z)
		if h > 260.0 or grid_normal(x, z).y < 0.8:
			continue
		spots.append(Vector3(x, h, z))

	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.16
	trunk.bottom_radius = 0.26
	trunk.height = 3.0
	trunk.radial_segments = 5
	trunk.rings = 1
	trunk.material = _instanced_material(0.9, Color(0.32, 0.22, 0.14))

	var pine := CylinderMesh.new()
	pine.top_radius = 0.0
	pine.bottom_radius = 2.3
	pine.height = 7.5
	pine.radial_segments = 7
	pine.rings = 2
	pine.material = _instanced_material(0.9, Color(0.13, 0.27, 0.13))

	var leafy := SphereMesh.new()
	leafy.radius = 2.6
	leafy.height = 4.6
	leafy.radial_segments = 8
	leafy.rings = 4
	leafy.material = _instanced_material(0.9, Color(0.25, 0.40, 0.12))

	var pine_shape := CylinderShape3D.new()
	pine_shape.radius = 1.4
	pine_shape.height = 9.0
	var leafy_shape := CylinderShape3D.new()
	leafy_shape.radius = 1.9
	leafy_shape.height = 7.0

	# Group trees in tiles so that distant tiles can be hidden.
	var tiles := {}
	for p in spots:
		var key := Vector2i(floori(p.x / TREE_TILE), floori(p.z / TREE_TILE))
		if not tiles.has(key):
			tiles[key] = [[], [], [], [], [], []]
		var t: Array = tiles[key]
		var s := _rng.randf_range(0.75, 1.4)
		var is_pine := p.y > 30.0 or _rng.randf() < 0.35
		var rot := Basis(Vector3.UP, _rng.randf() * TAU)
		var shade := Color(1, 1, 1).darkened(_rng.randf_range(0.0, 0.3))
		t[0].append(Transform3D(rot.scaled(Vector3(s, s, s)), p + Vector3(0, 1.4 * s, 0)))
		t[1].append(shade)
		var cs := CollisionShape3D.new()
		cs.scale = Vector3(s, s, s)
		if is_pine:
			t[2].append(Transform3D(rot.scaled(Vector3(s, s, s)), p + Vector3(0, 6.2 * s, 0)))
			t[3].append(shade)
			cs.shape = pine_shape
			cs.position = p + Vector3(0, 4.5 * s, 0)
		else:
			t[4].append(Transform3D(rot.scaled(Vector3(s, s * _rng.randf_range(0.85, 1.15), s)), p + Vector3(0, 4.6 * s, 0)))
			t[5].append(shade)
			cs.shape = leafy_shape
			cs.position = p + Vector3(0, 3.5 * s, 0)
		_body.add_child(cs)

	var meshes: Array[Mesh] = [trunk, pine, leafy]
	for key: Vector2i in tiles:
		var t: Array = tiles[key]
		for m in 3:
			var xf: Array[Transform3D] = []
			xf.assign(t[m * 2])
			var cl: Array[Color] = []
			cl.assign(t[m * 2 + 1])
			if xf.is_empty():
				continue
			var mmi := _multimesh(meshes[m], xf, cl)
			if m == 0:
				mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_tree_instances.append(mmi)
	set_tree_distance(1300.0)


## Hides tree tiles beyond this distance from the camera.
func set_tree_distance(distance: float) -> void:
	for mmi in _tree_instances:
		mmi.visibility_range_end = distance
		mmi.visibility_range_end_margin = 50.0


# --- Grass (streamed around the drone) ---------------------------------------

func _make_grass_mesh() -> ArrayMesh:
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
	if _lake_factor(x, z) > 0.12:
		return false
	if Vector2(x, z).distance_to(SPAWN) < 3.0:
		return false
	var dv := Vector2(x, z).distance_to(VILLAGE)
	if dv > 160.0 and dv < 470.0:
		return false # fields have their own texture
	if grid_normal(x, z).y < 0.9:
		return false
	return grid_height(x, z) < 160.0


## Changes grass density: ring radius in chunks and blades per chunk.
func set_grass_quality(radius: int, tries: int) -> void:
	grass_radius = radius
	grass_tries = tries
	for key: Vector2i in _grass_chunks.keys():
		_drop_grass_chunk(key)


func _drop_grass_chunk(key: Vector2i) -> void:
	var mmi: MultiMeshInstance3D = _grass_chunks[key]
	_grass_chunks.erase(key)
	if mmi != null:
		mmi.visible = false
		_grass_pool.append(mmi)


## Keeps grass chunks built around `focus`. Builds at most `budget` new chunks.
func update_grass(focus: Vector3, budget := 2) -> void:
	var c := Vector2i(floori(focus.x / GRASS_CHUNK), floori(focus.z / GRASS_CHUNK))
	for key: Vector2i in _grass_chunks.keys():
		if absi(key.x - c.x) > grass_radius + 1 or absi(key.y - c.y) > grass_radius + 1:
			_drop_grass_chunk(key)
	var built := 0
	for r in grass_radius + 1:
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dz)) != r:
					continue
				var key := c + Vector2i(dx, dz)
				if _grass_chunks.has(key):
					continue
				_build_grass_chunk(key)
				built += 1
				if built >= budget:
					return


func _build_grass_chunk(key: Vector2i) -> void:
	var x0 := key.x * GRASS_CHUNK
	var z0 := key.y * GRASS_CHUNK
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key)
	var xforms: Array[Transform3D] = []
	var cols: Array[Color] = []
	if Vector2(x0, z0).length() < 1250.0:
		for i in grass_tries:
			var x := x0 + rng.randf() * GRASS_CHUNK
			var z := z0 + rng.randf() * GRASS_CHUNK
			if not _grass_ok(x, z):
				continue
			var s := rng.randf_range(0.8, 1.5)
			var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.8, 1.4), s))
			xforms.append(Transform3D(basis, Vector3(x, grid_height(x, z) - 0.04, z)))
			var tone := 0.75 + 0.4 * (_detail.get_noise_2d(x, z) * 0.5 + 0.5)
			cols.append(Color(tone, tone, tone * 0.9))
	if xforms.is_empty():
		_grass_chunks[key] = null
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = _grass_mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		mm.set_instance_color(i, cols[i])
	var mmi: MultiMeshInstance3D
	if _grass_pool.is_empty():
		mmi = MultiMeshInstance3D.new()
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)
	else:
		mmi = _grass_pool.pop_back()
	mmi.multimesh = mm
	mmi.visibility_range_end = GRASS_CHUNK * (grass_radius + 0.3)
	mmi.visible = true
	_grass_chunks[key] = mmi


# --- Gates -----------------------------------------------------------------

func gate_position(i: int) -> Vector3:
	var g: Array = GATE_PLAN[i]
	var x: float = g[0]
	var z: float = g[1]
	var base := ground_height(x, z)
	if _lake_factor(x, z) > 0.3:
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
		var prev := positions[i - 1] if i > 0 else Vector3(SPAWN.x, spawn_y, SPAWN.y)
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


# --- Helpers ---------------------------------------------------------------

func _glow_material(color: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	m.roughness = 0.4
	return m


func _plain(color: Color, roughness: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	return m


## Material whose colour comes from the MultiMesh instance colour.
func _instanced_material(roughness: float, base := Color.WHITE) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = base
	m.vertex_color_use_as_albedo = true
	m.roughness = roughness
	return m


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
