extends SceneTree
## Bakes the front's navigation mesh once and saves it next to the map
## (assets/maps/trenches_nav.res), so the game does not bake on the phone.
## Run after rebuilding the map:  godot --headless -s res://tools/bake_nav.gd
## (the level script is loaded at run time: it needs the autoloads)

const NAV := "res://assets/maps/trenches_nav.res"


func _initialize() -> void:
	var t0 := Time.get_ticks_msec()
	if FileAccess.file_exists(NAV):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(NAV))
	await process_frame
	var level: Node3D = load("res://scripts/trench_level.gd").new() # with no saved mesh it bakes in _ready
	root.add_child(level)
	if not level.is_built:
		await level.built
	await physics_frame
	var nm: NavigationMesh = level.nav_region.navigation_mesh
	var err := ResourceSaver.save(nm, NAV)
	print("baked nav: polygons=%d vertices=%d in %.1fs (err %d)" % [nm.get_polygon_count(), nm.vertices.size(),
			(Time.get_ticks_msec() - t0) / 1000.0, err])
	# spot checks: is there floor where soldiers must walk? (a polygon under the point)
	for p in [level.player_spawn.origin, Vector3(97, 0.0, 14.5), Vector3(97, 0.0, 16.15), Vector3(96.4, 0.0, 16.8),
			Vector3(96.4, 0.45, 18.5), Vector3(97, 0.9, 20.5), Vector3(100.65, 3.7, 18.5), Vector3(100.65, 12.1, 18.5)]:
		print("nav under %s: %s" % [p, _covered(nm, p)])
	quit()


func _covered(nm: NavigationMesh, p: Vector3) -> String:
	var verts := nm.vertices
	for i in nm.get_polygon_count():
		var poly := nm.get_polygon(i)
		var inside := false
		var ys := 0.0
		var n := poly.size()
		for k in n:
			var a := verts[poly[k]]
			var b := verts[poly[(k + 1) % n]]
			ys += a.y
			if (a.z > p.z) != (b.z > p.z) and p.x < (b.x - a.x) * (p.z - a.z) / (b.z - a.z) + a.x:
				inside = not inside
		if inside and absf(ys / n - p.y) < 0.6:
			return "yes (poly y %.2f)" % (ys / n)
	return "NO"
