extends Node3D
## The battlefield: real terrain of Prokhorovka (Belgorod region), satellite imagery, OSM buildings and forests.
## Axes: X east, Y up, Z south; the map is centred on the origin.

const SIZE := 10400.0
const HALF := SIZE / 2.0
const N := 513
const CELL := SIZE / (N - 1)
const CHUNKS := 16
const CHUNK_CELLS := (N - 1) / CHUNKS
const WATER_LEVEL := -100.0

var heights := PackedFloat32Array()
var buildings: Array = []        # [{c: Vector2, ax: Vector2, ay: Vector2, half: Vector2, top: float}]
var bgrid := {}                  # Vector2i cell -> indices into buildings, for fast hit tests
const BCELL := 100.0
var quality := "high"            # high / mid / low
var sun: DirectionalLight3D
var env: Environment


func build(q: String) -> void:
	quality = q
	var f := FileAccess.open("res://assets/map/height.bin", FileAccess.READ)
	heights = f.get_buffer(f.get_length()).to_float32_array()
	_environment()
	_terrain()
	_trees()
	_buildings()
	_water()
	_outer()


# ---------------------------------------------------------------- heights
func h_at(i: int, j: int) -> float:
	return heights[clampi(j, 0, N - 1) * N + clampi(i, 0, N - 1)]


## Exact height of the rendered terrain triangles at a world point.
func height(x: float, z: float) -> float:
	var fx := clampf((x + HALF) / CELL, 0.0, N - 1.001)
	var fz := clampf((z + HALF) / CELL, 0.0, N - 1.001)
	var i := int(fx)
	var j := int(fz)
	var u := fx - i
	var v := fz - j
	var k := j * N + i
	if u + v <= 1.0:
		return heights[k] + (heights[k + 1] - heights[k]) * u + (heights[k + N] - heights[k]) * v
	return heights[k + N + 1] + (heights[k + N] - heights[k + N + 1]) * (1.0 - u) + (heights[k + 1] - heights[k + N + 1]) * (1.0 - v)


func normal(x: float, z: float) -> Vector3:
	var e := 2.0
	return Vector3(height(x - e, z) - height(x + e, z), 2.0 * e, height(x, z - e) - height(x, z + e)).normalized()


# ---------------------------------------------------------------- environment
func _environment() -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var pm := ShaderMaterial.new()
	pm.shader = load("res://shaders/sky.gdshader")
	pm.set_shader_parameter("pano", load("res://assets/sky/sky.hdr"))
	sky.sky_material = pm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 1.1
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.05
	env.tonemap_white = 6.0
	env.fog_enabled = true
	env.fog_light_color = Color(0.70, 0.76, 0.83)
	env.fog_density = 0.00006
	env.fog_sky_affect = 0.0
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.1
	env.adjustment_saturation = 1.06
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-46.0, -35.0, 0.0)
	sun.light_energy = 1.35
	sun.light_color = Color(1.0, 0.96, 0.9)
	sun.shadow_enabled = quality != "low"
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 380.0 if quality == "high" else 220.0
	sun.shadow_blur = 1.2
	add_child(sun)


# ---------------------------------------------------------------- terrain
func _grid_mesh(i0: int, j0: int, cells: int, step: int) -> ArrayMesh:
	var n := cells / step + 1
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var idx := PackedInt32Array()
	for b in n:
		for a in n:
			var i := i0 + a * step
			var j := j0 + b * step
			verts.append(Vector3(i * CELL - HALF, h_at(i, j), j * CELL - HALF))
			norms.append(Vector3(h_at(i - 1, j) - h_at(i + 1, j), 2.0 * CELL, h_at(i, j - 1) - h_at(i, j + 1)).normalized())
	for b in n - 1:
		for a in n - 1:
			var p := b * n + a
			idx.append_array([p, p + 1, p + n, p + n, p + 1, p + n + 1])
	# skirts hide cracks between neighbouring chunks of different detail
	var ring: Array[int] = []
	for a in n: ring.append(a)
	for b in range(1, n): ring.append(b * n + n - 1)
	for a in range(n - 2, -1, -1): ring.append((n - 1) * n + a)
	for b in range(n - 2, 0, -1): ring.append(b * n)
	var base := verts.size()
	for r in ring:
		verts.append(verts[r] - Vector3(0, 6, 0))
		norms.append(norms[r])
	for k in ring.size():
		var a0: int = ring[k]
		var a1: int = ring[(k + 1) % ring.size()]
		var s0 := base + k
		var s1 := base + (k + 1) % ring.size()
		idx.append_array([a0, s0, a1, a1, s0, s1])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


var terrain_mat: ShaderMaterial


func _terrain() -> void:
	var mat := ShaderMaterial.new()
	terrain_mat = mat
	mat.shader = load("res://shaders/terrain.gdshader")
	mat.set_shader_parameter("sat", load("res://assets/map/satellite.jpg"))
	mat.set_shader_parameter("splat", load("res://assets/map/splat.png"))
	mat.set_shader_parameter("grass_c", load("res://assets/textures/Grass004_color.jpg"))
	mat.set_shader_parameter("grass_n", load("res://assets/textures/Grass004_normal.jpg"))
	mat.set_shader_parameter("dirt_c", load("res://assets/textures/Ground048_color.jpg"))
	mat.set_shader_parameter("dirt_n", load("res://assets/textures/Ground048_normal.jpg"))
	mat.set_shader_parameter("road_c", load("res://assets/textures/Asphalt019_color.jpg"))
	mat.set_shader_parameter("road_n", load("res://assets/textures/Asphalt019_normal.jpg"))
	mat.set_shader_parameter("gravel_c", load("res://assets/textures/Gravel023_color.jpg"))
	mat.set_shader_parameter("map_size", SIZE)
	var near_end := 1700.0 if quality != "low" else 1100.0
	for cj in CHUNKS:
		for ci in CHUNKS:
			var i0 := ci * CHUNK_CELLS
			var j0 := cj * CHUNK_CELLS
			for lod in 2:
				var mi := MeshInstance3D.new()
				mi.mesh = _grid_mesh(i0, j0, CHUNK_CELLS, 1 if lod == 0 else 4)
				mi.material_override = mat
				if lod == 0:
					mi.visibility_range_end = near_end
					mi.visibility_range_end_margin = 60.0
				else:
					mi.visibility_range_begin = near_end
					mi.visibility_range_begin_margin = 60.0
					mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				add_child(mi)


# ---------------------------------------------------------------- vegetation
func _tree_mesh() -> ArrayMesh:
	# two crossed unit quads, base at y=0; left atlas half on the first, right half on the second
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for q in 2:
		var d := Vector3(1, 0, 0) if q == 0 else Vector3(0, 0, 1)
		var u0 := 0.5 * q
		var c := [-d * 0.5, d * 0.5, d * 0.5 + Vector3.UP, -d * 0.5 + Vector3.UP]
		var uv := [Vector2(u0, 1), Vector2(u0 + 0.5, 1), Vector2(u0 + 0.5, 0), Vector2(u0, 0)]
		for t in [0, 1, 2, 0, 2, 3]:
			st.set_uv(uv[t])
			st.set_normal(Vector3.UP)
			st.add_vertex(c[t])
	return st.commit()


func _trees() -> void:
	var meta: Array = JSON.parse_string(FileAccess.get_file_as_string("res://assets/trees/trees.json"))
	var f := FileAccess.open("res://assets/map/trees.bin", FileAccess.READ)
	var data := f.get_buffer(f.get_length()).to_float32_array()
	var count := data.size() / 4
	var keep := 1 if quality == "high" else 2 if quality == "mid" else 4
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/tree.gdshader")
	mat.set_shader_parameter("atlas", load("res://assets/trees/trees_atlas.png"))
	var mesh := _tree_mesh()
	var per_chunk := {}
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for t in count:
		if t % keep != 0:
			continue
		var x := data[t * 4]
		var z := data[t * 4 + 1]
		var kind := int(data[t * 4 + 2])
		var s := data[t * 4 + 3]
		var sp: int
		var target_h: float
		match kind:
			0: sp = 0 if rng.randf() < 0.55 else 1; target_h = rng.randf_range(14, 21)
			1: sp = 2 if rng.randf() < 0.5 else 3; target_h = rng.randf_range(11, 17)
			2: sp = 4; target_h = rng.randf_range(18, 26)
			_: sp = 2; target_h = rng.randf_range(3, 6)
		var m: Dictionary = meta[sp]
		var k: float = target_h * s / float(m["tree_height"]) * float(m["size"])
		var narrow := 0.55 if sp == 4 else 1.0
		var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(k * narrow, k, k * narrow))
		var key := Vector2i(clampi(int((x + HALF) / SIZE * CHUNKS), 0, CHUNKS - 1), clampi(int((z + HALF) / SIZE * CHUNKS), 0, CHUNKS - 1))
		if not per_chunk.has(key):
			per_chunk[key] = []
		per_chunk[key].append([Transform3D(b, Vector3(x, height(x, z) - 0.3, z)), Color(float(sp), rng.randf_range(0.82, 1.12), rng.randf(), 0)])
	var vis := 1900.0 if quality == "high" else 1300.0 if quality == "mid" else 900.0
	for key in per_chunk:
		var list: Array = per_chunk[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = mesh
		mm.instance_count = list.size()
		for n in list.size():
			mm.set_instance_transform(n, list[n][0])
			mm.set_instance_custom_data(n, list[n][1])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = mat
		mmi.visibility_range_end = vis
		mmi.visibility_range_end_margin = 120.0
		mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if quality == "high" else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)


# ---------------------------------------------------------------- buildings
func _buildings() -> void:
	var scene: PackedScene = load("res://assets/models/buildings.glb")
	var b := scene.instantiate()
	add_child(b)
	for mi in b.find_children("*", "MeshInstance3D", true, false):
		mi.visibility_range_end = 3200.0
	# collision boxes (oriented along the longest wall) for shells and vehicles
	var v: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/map/vectors.json"))
	for bd in v["buildings"]:
		var p: Array = bd["p"]
		if p.size() < 3:
			continue
		var best := 0.0
		var ax := Vector2.RIGHT
		for i in p.size():
			var a := Vector2(p[i][0], p[i][1])
			var c := Vector2(p[(i + 1) % p.size()][0], p[(i + 1) % p.size()][1])
			if a.distance_to(c) > best:
				best = a.distance_to(c)
				ax = (c - a).normalized()
		var ay := Vector2(-ax.y, ax.x)
		var mn := Vector2(INF, INF)
		var mx := Vector2(-INF, -INF)
		for q in p:
			var pt := Vector2(q[0], q[1])
			var l := Vector2(pt.dot(ax), pt.dot(ay))
			mn = mn.min(l)
			mx = mx.max(l)
		var cl := (mn + mx) / 2.0
		var c := ax * cl.x + ay * cl.y
		var top := height(c.x, c.y) + (float(bd["h"]) if bd["h"] != null else 5.0)
		var half := (mx - mn) / 2.0
		buildings.append({"c": c, "ax": ax, "ay": ay, "half": half, "top": top})
		var r := half.length()
		for gx in range(int(floor((c.x - r) / BCELL)), int(floor((c.x + r) / BCELL)) + 1):
			for gz in range(int(floor((c.y - r) / BCELL)), int(floor((c.y + r) / BCELL)) + 1):
				var k := Vector2i(gx, gz)
				if not bgrid.has(k):
					bgrid[k] = []
				bgrid[k].append(buildings.size() - 1)


## Does the point hit a building? (2D oriented box test plus height)
func building_hit(p: Vector3, pad := 0.0) -> bool:
	var k := Vector2i(int(floor(p.x / BCELL)), int(floor(p.z / BCELL)))
	if not bgrid.has(k):
		return false
	for i in bgrid[k]:
		var b: Dictionary = buildings[i]
		if p.y > b["top"]:
			continue
		var d: Vector2 = Vector2(p.x, p.z) - b["c"]
		var hx: Vector2 = b["half"]
		if absf(d.dot(b["ax"])) < hx.x + pad and absf(d.dot(b["ay"])) < hx.y + pad:
			return true
	return false


## Ground or roof height under a point (for aircraft, shells and the camera).
func surf_h(x: float, z: float) -> float:
	var h := height(x, z)
	var k := Vector2i(int(floor(x / BCELL)), int(floor(z / BCELL)))
	if bgrid.has(k):
		for i in bgrid[k]:
			var b: Dictionary = buildings[i]
			var d: Vector2 = Vector2(x, z) - b["c"]
			var hx: Vector2 = b["half"]
			if absf(d.dot(b["ax"])) < hx.x and absf(d.dot(b["ay"])) < hx.y:
				h = maxf(h, b["top"])
	return h


# ---------------------------------------------------------------- beyond the map edge
## Farmland continues past the playable square so aircraft never see the edge of the world:
## a ring whose inner edge follows the terrain border, textured with the satellite image mirrored outwards.
func _outer() -> void:
	var far := 40000.0
	var base := 0.0
	var ring_in: Array[Vector3] = []
	var step := 8
	for k in range(0, N - 1, step):
		ring_in.append(Vector3(k * CELL - HALF, h_at(k, 0), -HALF))
	for k in range(0, N - 1, step):
		ring_in.append(Vector3(HALF, h_at(N - 1, k), k * CELL - HALF))
	for k in range(N - 1, 0, -step):
		ring_in.append(Vector3(k * CELL - HALF, h_at(k, N - 1), HALF))
	for k in range(N - 1, 0, -step):
		ring_in.append(Vector3(-HALF, h_at(0, k), k * CELL - HALF))
	for p in ring_in:
		base += p.y
	base /= ring_in.size()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := ring_in.size()
	for i in n:
		var a0 := ring_in[i] - Vector3(0, 1.0, 0)
		var a1 := ring_in[(i + 1) % n] - Vector3(0, 1.0, 0)
		# project the inner edge outwards from the centre onto the far square, flattening to the mean height
		var b0 := Vector3(a0.x, 0, a0.z) * (far / maxf(absf(a0.x), absf(a0.z)))
		var b1 := Vector3(a1.x, 0, a1.z) * (far / maxf(absf(a1.x), absf(a1.z)))
		var m0 := a0.lerp(Vector3(b0.x, base, b0.z), 0.12)
		var m1 := a1.lerp(Vector3(b1.x, base, b1.z), 0.12)
		m0.y = lerpf(a0.y, base, 0.6)
		m1.y = lerpf(a1.y, base, 0.6)
		b0.y = base
		b1.y = base
		for q in [[a0, m0, a1], [a1, m0, m1], [m0, b0, m1], [m1, b0, b1]]:
			for v in q:
				st.set_normal(Vector3.UP)
				st.add_vertex(v)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = terrain_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


# ---------------------------------------------------------------- water
func _water() -> void:
	var v: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/map/vectors.json"))
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.13, 0.22, 0.24)
	mat.metallic = 0.2
	mat.roughness = 0.08
	for poly in v["water"]:
		var pts := PackedVector2Array()
		for q in poly:
			pts.append(Vector2(q[0], q[1]))
		var tri := Geometry2D.triangulate_polygon(pts)
		if tri.is_empty():
			continue
		var lvl := INF
		for q in pts:
			lvl = minf(lvl, height(q.x, q.y))
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for i in tri:
			st.set_normal(Vector3.UP)
			st.add_vertex(Vector3(pts[i].x, lvl + 0.4, pts[i].y))
		var mi := MeshInstance3D.new()
		mi.mesh = st.commit()
		mi.material_override = mat
		add_child(mi)
