extends Node3D
## The blue airbase on the flat fields west of the front line: runway, hangar, helipad, garage and a control tower.
## Players start here and roll out in a short intro (see intro.gd). Positions are in world metres (X east, Z south);
## the runway points north (-Z), towards the enemy.

const Props := preload("res://scripts/props.gd")

const RW_X := -1700.0
const RW_Z0 := 3450.0            # south end (start of the take-off roll)
const RW_Z1 := 1950.0            # north end
const RW_W := 45.0
const HANGAR := Vector2(-1572, 3360)       # door faces west, towards the runway
const HANGAR_R := 15.0
const HANGAR_D := 34.0
const HELIPAD := Vector2(-1595, 3010)
const GARAGE := Vector2(-1600, 2430)       # door faces north
const TOWER := Vector2(-1620, 3200)
## The area levelled for the base, and kept free of trees: [min x, min z, max x, max z].
const FLAT := Rect2(-1760, 1900, 260, 1600)

var world: Node3D


## Blend the terrain inside FLAT (plus a soft border) to a plane fitted to the runway profile.
static func flatten(w: Node3D) -> void:
	var zs: Array[float] = []
	var hs: Array[float] = []
	var z := RW_Z1
	while z <= RW_Z0:
		zs.append(z)
		hs.append(w.height(RW_X, z))
		z += 25.0
	# least-squares line h = k z + c
	var n := float(zs.size())
	var sz := 0.0
	var sh := 0.0
	var szz := 0.0
	var szh := 0.0
	for i in zs.size():
		sz += zs[i]
		sh += hs[i]
		szz += zs[i] * zs[i]
		szh += zs[i] * hs[i]
	var k := (n * szh - sz * sh) / (n * szz - sz * sz)
	var c := (sh - k * sz) / n
	var border := 90.0
	for j in w.N:
		var wz: float = j * w.CELL - w.HALF
		if wz < FLAT.position.y - border or wz > FLAT.end.y + border:
			continue
		for i in w.N:
			var wx: float = i * w.CELL - w.HALF
			if wx < FLAT.position.x - border or wx > FLAT.end.x + border:
				continue
			var dx := maxf(maxf(FLAT.position.x - wx, wx - FLAT.end.x), 0.0)
			var dz := maxf(maxf(FLAT.position.y - wz, wz - FLAT.end.y), 0.0)
			var t := clampf(1.0 - Vector2(dx, dz).length() / border, 0.0, 1.0)
			t = t * t * (3.0 - 2.0 * t)
			var idx: int = j * w.N + i
			w.heights[idx] = lerpf(w.heights[idx], k * wz + c, t)


static func keeps_tree(x: float, z: float) -> bool:
	return not FLAT.grow(25.0).has_point(Vector2(x, z))


func build(w: Node3D) -> void:
	world = w
	_runway()
	_apron(Rect2(RW_X + RW_W / 2.0 - 2.0, HANGAR.y - 26.0, HANGAR.x - HANGAR_D / 2.0 - (RW_X + RW_W / 2.0) + 4.0, 52.0))
	_apron(Rect2(RW_X + RW_W / 2.0 - 2.0, HELIPAD.y - 20.0, HELIPAD.x - RW_X - RW_W / 2.0 + 20.0, 40.0))
	_apron(Rect2(GARAGE.x - 14.0, GARAGE.y - 80.0, 28.0, 90.0))
	_hangar()
	_helipad()
	_garage()
	_tower()


func _gy(x: float, z: float) -> float:
	return world.height(x, z)


## A flat strip that follows the ground, slightly above it.
func _strip(st: SurfaceTool, a: Vector2, b: Vector2, wdt: float, lift: float, uv_scale: float) -> void:
	var d := (b - a)
	var l := d.length()
	var dir := d / l
	var side := Vector2(-dir.y, dir.x) * wdt / 2.0
	var steps := maxi(1, int(l / 10.0))
	for s in steps:
		var p0 := a + dir * (l * s / steps)
		var p1 := a + dir * (l * (s + 1) / steps)
		var q := [p0 - side, p0 + side, p1 + side, p1 - side]
		var v: Array[Vector3] = []
		for p in q:
			v.append(Vector3(p.x, _gy(p.x, p.y) + lift, p.y))
		for t in [0, 2, 1, 0, 3, 2]:
			st.set_normal(Vector3.UP)
			st.set_uv(Vector2(v[t].x, v[t].z) * uv_scale)
			st.add_vertex(v[t])


func _mesh(st: SurfaceTool, m: Material, shadow := false) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _asphalt() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = load("res://assets/textures/Asphalt019_color.jpg")
	m.albedo_color = Color(0.8, 0.8, 0.8)
	m.roughness = 0.9
	return m


func _runway() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_strip(st, Vector2(RW_X, RW_Z0 + 20.0), Vector2(RW_X, RW_Z1 - 20.0), RW_W, 0.12, 0.08)
	_mesh(st, _asphalt())
	# markings: centre dashes, edge lines, threshold piano keys and the runway numbers' blocks
	var mk := SurfaceTool.new()
	mk.begin(Mesh.PRIMITIVE_TRIANGLES)
	var z := RW_Z0 - 80.0
	while z > RW_Z1 + 80.0:
		_strip(mk, Vector2(RW_X, z), Vector2(RW_X, z - 30.0), 0.9, 0.16, 1.0)
		z -= 60.0
	for s in [-1.0, 1.0]:
		_strip(mk, Vector2(RW_X + s * (RW_W / 2.0 - 1.5), RW_Z0 + 10.0), Vector2(RW_X + s * (RW_W / 2.0 - 1.5), RW_Z1 - 10.0), 0.8, 0.16, 1.0)
	for end in [[RW_Z0 - 6.0, -1.0], [RW_Z1 + 6.0, 1.0]]:
		for k in 10:
			var x := RW_X - RW_W / 2.0 + 4.0 + k * 4.1 + (2.0 if k >= 5 else 0.0)
			_strip(mk, Vector2(x, end[0]), Vector2(x, end[0] + end[1] * 30.0), 1.8, 0.16, 1.0)
	var white := StandardMaterial3D.new()
	white.albedo_color = Color(0.92, 0.92, 0.9)
	white.roughness = 0.8
	_mesh(mk, white)


func _apron(r: Rect2) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cz := r.position.y + r.size.y / 2.0
	_strip(st, Vector2(r.position.x, cz), Vector2(r.end.x, cz), r.size.y, 0.1, 0.08)
	_mesh(st, Props.concrete())


## Arched hangar: a half cylinder along X, open at the west end.
func _hangar() -> void:
	var gy := _gy(HANGAR.x, HANGAR.y)
	var n := 18
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var x0 := HANGAR.x - HANGAR_D / 2.0
	var x1 := HANGAR.x + HANGAR_D / 2.0
	for k in n:
		var a0 := PI * k / n
		var a1 := PI * (k + 1) / n
		var p0 := Vector3(0, sin(a0) * HANGAR_R, cos(a0) * HANGAR_R)
		var p1 := Vector3(0, sin(a1) * HANGAR_R, cos(a1) * HANGAR_R)
		var nm := (p0 + p1).normalized()
		for v in [[x0, p0], [x1, p0], [x1, p1], [x0, p0], [x1, p1], [x0, p1]]:
			# both sides, so the inside is drawn too
			st.set_normal(nm)
			st.set_uv(Vector2(v[0] * 0.25, (PI * k / n) * HANGAR_R * 0.25))
			st.add_vertex(Vector3(v[0], gy + v[1].y, HANGAR.y + v[1].z))
		for v in [[x0, p0], [x1, p1], [x1, p0], [x0, p0], [x0, p1], [x1, p1]]:
			st.set_normal(-nm)
			st.set_uv(Vector2(v[0] * 0.25, (PI * k / n) * HANGAR_R * 0.25))
			st.add_vertex(Vector3(v[0], gy + v[1].y, HANGAR.y + v[1].z))
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.44, 0.48, 0.42)
	metal.roughness = 0.6
	metal.metallic = 0.4
	_mesh(st, metal, true)
	# back wall (a fan of triangles) and the floor
	var wall := SurfaceTool.new()
	wall.begin(Mesh.PRIMITIVE_TRIANGLES)
	var c := Vector3(x1, gy, HANGAR.y)
	for k in n:
		var a0 := PI * k / n
		var a1 := PI * (k + 1) / n
		for v in [c, Vector3(x1, gy + sin(a0) * HANGAR_R, HANGAR.y + cos(a0) * HANGAR_R), Vector3(x1, gy + sin(a1) * HANGAR_R, HANGAR.y + cos(a1) * HANGAR_R)]:
			wall.set_normal(Vector3.LEFT)
			wall.add_vertex(v)
		for v in [c, Vector3(x1, gy + sin(a1) * HANGAR_R, HANGAR.y + cos(a1) * HANGAR_R), Vector3(x1, gy + sin(a0) * HANGAR_R, HANGAR.y + cos(a0) * HANGAR_R)]:
			wall.set_normal(Vector3.RIGHT)
			wall.add_vertex(v)
	_mesh(wall, metal, true)
	var floor_n := Node3D.new()
	add_child(floor_n)
	Props.box(floor_n, Vector3(HANGAR_D, 0.3, HANGAR_R * 2.0), Vector3(HANGAR.x, gy - 0.12, HANGAR.y), Props.concrete())
	# a light strip and a tool cart inside so the hangar is not an empty shell
	Props.box(floor_n, Vector3(HANGAR_D - 4.0, 0.15, 0.6), Vector3(HANGAR.x, gy + HANGAR_R - 0.6, HANGAR.y), Props.mat("lamp", Color(1, 0.95, 0.8), 0.3))
	Props.box(floor_n, Vector3(1.6, 1.0, 0.9), Vector3(x1 - 3.0, gy + 0.55, HANGAR.y + 9.0), Props.mat("cart", Color(0.75, 0.2, 0.12), 0.5))


func _helipad() -> void:
	var gy := _gy(HELIPAD.x, HELIPAD.y)
	var n := Node3D.new()
	n.position = Vector3(HELIPAD.x, gy, HELIPAD.y)
	add_child(n)
	Props.cyl(n, 14.0, 14.5, 0.4, Vector3(0, 0.1, 0), Props.concrete(), Vector3.ZERO, 32)
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 10.6
	tm.outer_radius = 11.4
	tm.rings = 32
	ring.mesh = tm
	ring.scale = Vector3(1, 0.05, 1)
	ring.position = Vector3(0, 0.31, 0)
	ring.material_override = Props.mat("yellow", Color(0.95, 0.75, 0.1), 0.7)
	n.add_child(ring)
	var wm := Props.mat("paint_w", Color(0.95, 0.95, 0.92), 0.7)
	Props.box(n, Vector3(1.2, 0.05, 8.0), Vector3(-2.5, 0.32, 0), wm)
	Props.box(n, Vector3(1.2, 0.05, 8.0), Vector3(2.5, 0.32, 0), wm)
	Props.box(n, Vector3(4.0, 0.05, 1.2), Vector3(0, 0.32, 0), wm)
	# windsock mast
	Props.cyl(n, 0.08, 0.1, 6.0, Vector3(16.5, 3.0, -6.0), Props.steel(), Vector3.ZERO, 6)
	Props.cyl(n, 0.25, 0.5, 2.2, Vector3(17.6, 5.8, -6.0), Props.mat("sock", Color(1.0, 0.4, 0.1), 0.8), Vector3(0, 0, PI / 2), 8)


## Garage with its door to the north: walls, roof and a dark inside.
func _garage() -> void:
	var gy := _gy(GARAGE.x, GARAGE.y)
	var n := Node3D.new()
	n.position = Vector3(GARAGE.x, gy, GARAGE.y)
	add_child(n)
	var wall := Props.mat("brick", Color(0.62, 0.55, 0.5), 0.9, "res://assets/textures/Ground037_color.jpg", 0.2)
	var w := 13.0
	var d := 16.0
	var h := 7.5
	Props.box(n, Vector3(0.6, h, d), Vector3(-w / 2.0, h / 2.0, 0), wall)
	Props.box(n, Vector3(0.6, h, d), Vector3(w / 2.0, h / 2.0, 0), wall)
	Props.box(n, Vector3(w + 0.6, h, 0.6), Vector3(0, h / 2.0, d / 2.0), wall)
	Props.box(n, Vector3(w + 1.6, 0.5, d + 1.0), Vector3(0, h + 0.25, 0), Props.mat("roof", Color(0.32, 0.34, 0.33), 0.7, "", 1.0, 0.3))
	Props.box(n, Vector3(w + 0.6, 1.4, 0.6), Vector3(0, h - 0.7, -d / 2.0), wall)
	Props.box(n, Vector3(w, 0.2, d), Vector3(0, 0.05, 0), Props.concrete())
	# raised roller door
	Props.box(n, Vector3(w - 0.4, 0.8, 0.3), Vector3(0, h - 1.7, -d / 2.0 + 0.2), Props.mat("door", Color(0.5, 0.52, 0.4), 0.6, "", 1.0, 0.3))


func _tower() -> void:
	var gy := _gy(TOWER.x, TOWER.y)
	var n := Node3D.new()
	n.position = Vector3(TOWER.x, gy, TOWER.y)
	add_child(n)
	var wall := Props.mat("tower", Color(0.85, 0.83, 0.78), 0.9)
	Props.box(n, Vector3(6, 9, 6), Vector3(0, 4.5, 0), wall)
	Props.box(n, Vector3(7.5, 3, 7.5), Vector3(0, 10.5, 0), Props.mat("glass", Color(0.15, 0.25, 0.3), 0.1, "", 1.0, 0.6))
	Props.box(n, Vector3(8.2, 0.5, 8.2), Vector3(0, 12.2, 0), wall)
	Props.cyl(n, 0.1, 0.1, 4.0, Vector3(2.5, 14.4, 2.5), Props.steel(), Vector3.ZERO, 6)
	for k in 2:
		Props.cyl(n, 3.0, 3.0, 5.0, Vector3(-14.0 - k * 7.5, 2.5, 12.0), Props.mat("fueltank", Color(0.75, 0.76, 0.72), 0.5, "", 1.0, 0.4), Vector3.ZERO, 20)
