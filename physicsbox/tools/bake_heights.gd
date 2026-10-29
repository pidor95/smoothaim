extends SceneTree
## Bakes the terrain's collision height grid once (assets/maps/trenches_height.res):
## the Terrain_<i>_<j> chunks of trenches.glb (each a regular grid with
## a 0.5 / 1 / 2 m step) sampled every 0.5 m into one float image, padded to
## whole 32 m tiles, heights doubled (see _height). The game makes HeightMapShape3D tiles of it instead of
## trimesh shapes (a fraction of the memory: the trimesh terrain alone took
## ~130 MB and phones ran out).
## Run after rebuilding the map:  godot --headless -s res://tools/bake_heights.gd

const MAP := "res://assets/maps/trenches.glb"
const OUT := "res://assets/maps/trenches_height.res"
const X0 := -270.0
const Z0 := -170.0
const CHX := 30.0
const CHZ := 34.0
const STEP := 0.5
const TILE := 64 # samples per tile edge (65 with the shared border)


func _initialize() -> void:
	var t0 := Time.get_ticks_msec()
	var scene: Node = load(MAP).instantiate()
	var chunks := {} # Vector2i(i, j) -> [grid step, cells x, cells z, PackedFloat32Array heights]
	var max_i := 0
	var max_j := 0
	for c in scene.get_children():
		if not (c is MeshInstance3D and String(c.name).begins_with("Terrain_")):
			continue
		var ij := Vector2i(int(String(c.name).get_slice("_", 1)), int(String(c.name).get_slice("_", 2)))
		max_i = maxi(max_i, ij.x)
		max_j = maxi(max_j, ij.y)
		var xf: Transform3D = c.transform
		var verts: PackedVector3Array = (c.mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var x0 := X0 + ij.x * CHX
		var z0 := Z0 + ij.y * CHZ
		var xs := {}
		for v in verts:
			xs[snappedf((xf * v).x, 0.01)] = true
		var step := CHX / (xs.size() - 1)
		var nx := int(round(CHX / step)) + 1
		var nz := int(round(CHZ / step)) + 1
		var h := PackedFloat32Array()
		h.resize(nx * nz)
		h.fill(-1e9)
		for v in verts:
			var p := xf * v
			var k := clampi(int(round((p.x - x0) / step)), 0, nx - 1)
			var q := clampi(int(round((p.z - z0) / step)), 0, nz - 1)
			h[q * nx + k] = maxf(h[q * nx + k], p.y) # the skirts hang lower: the top wins
		chunks[ij] = [step, nx, nz, h]
	scene.free()
	var w := int(round((max_i + 1) * CHX / STEP)) + 1
	var d := int(round((max_j + 1) * CHZ / STEP)) + 1
	var tw := int(ceil(float(w - 1) / TILE)) * TILE + 1
	var td := int(ceil(float(d - 1) / TILE)) * TILE + 1
	var data := PackedFloat32Array()
	data.resize(tw * td)
	for sz in td:
		var z := Z0 + mini(sz, d - 1) * STEP
		for sx in tw:
			var x := X0 + mini(sx, w - 1) * STEP
			data[sz * tw + sx] = _height(chunks, x, z, max_i, max_j) * 2.0
	var img := Image.create_from_data(tw, td, false, Image.FORMAT_RF, data.to_byte_array())
	var err := ResourceSaver.save(img, OUT, ResourceSaver.FLAG_COMPRESS)
	print("baked heights %dx%d (map %dx%d) in %.1fs (err %d)" % [tw, td, w, d, (Time.get_ticks_msec() - t0) / 1000.0, err])
	quit()


## The chunk's surface at (x, z): bilinear in its own grid cell. Stored
## doubled: the game scales each tile by 0.5 (uniformly - samples 0.5 m apart).
func _height(chunks: Dictionary, x: float, z: float, max_i: int, max_j: int) -> float:
	var i := clampi(int(floor((x - X0) / CHX)), 0, max_i)
	var j := clampi(int(floor((z - Z0) / CHZ)), 0, max_j)
	var c: Array = chunks[Vector2i(i, j)]
	var step: float = c[0]
	var nx: int = c[1]
	var nz: int = c[2]
	var h: PackedFloat32Array = c[3]
	var fx := clampf((x - (X0 + i * CHX)) / step, 0.0, nx - 1.0)
	var fz := clampf((z - (Z0 + j * CHZ)) / step, 0.0, nz - 1.0)
	var k := mini(int(fx), nx - 2)
	var q := mini(int(fz), nz - 2)
	var u := fx - k
	var v := fz - q
	var a := lerpf(h[q * nx + k], h[q * nx + k + 1], u)
	var b := lerpf(h[(q + 1) * nx + k], h[(q + 1) * nx + k + 1], u)
	return lerpf(a, b, v)
