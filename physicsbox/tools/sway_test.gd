extends SceneTree
## Dev test: the hip dot drifts about the picture with the chest camera
## (walking, turning, firing) and the bullet goes where the dot is; memory.
## Run: godot -s res://tools/sway_test.gd  (env SHOTS=<dir>)

var frame := 0
var game: Node
var p: Player
var shots_dir := OS.get_environment("SHOTS")
var _min := Vector2(1e9, 1e9)
var _max := Vector2(-1e9, -1e9)


func _initialize() -> void:
	change_scene_to_file("res://scenes/game.tscn")


func _shot(n: String) -> void:
	if shots_dir != "":
		root.get_texture().get_image().save_png(shots_dir.path_join(n + ".png"))
		print("shot ", n)


func _process(_delta: float) -> bool:
	if game == null or game.get("hud") == null:
		game = current_scene if current_scene and current_scene.has_method("spawn_soldier") else null
		return false
	frame += 1
	if frame == 30:
		p = game.player
		p.touch_mode = true
		Player.immortal = true
		Npc.ai_enabled = false
		game._report("sway test: loaded")
	if frame >= 40 and frame < 220:
		p.touch_move = Vector2(0, -1) # walking forward
		if frame > 130:
			p.look(Vector2(6, 0)) # and turning
		var d := p.aim_screen()
		_min = Vector2(minf(_min.x, d.x), minf(_min.y, d.y))
		_max = Vector2(maxf(_max.x, d.x), maxf(_max.y, d.y))
		if frame == 100:
			_shot("s00_walk_dot")
		if frame == 170:
			_shot("s01_turn_dot")
	if frame == 220:
		p.touch_move = Vector2.ZERO
		var c := root.get_visible_rect().size * 0.5
		print("hip dot range over walking + turning: x %.0f..%.0f y %.0f..%.0f (screen centre %.0f, %.0f)" % [_min.x, _max.x, _min.y, _max.y, c.x, c.y])
	if frame == 260:
		# where a bullet would go vs where the dot is
		var from := p.aim.global_position
		var to := from - p.aim.global_basis.z * 60.0
		var q := PhysicsRayQueryParameters3D.create(from, to, 1 | 2)
		q.exclude = [p.get_rid()]
		var hit := root.get_world_3d().direct_space_state.intersect_ray(q)
		var at: Vector3 = hit.position if not hit.is_empty() else to
		print("bullet line on screen %s, dot %s" % [p.camera.unproject_position(at), p.aim_screen()])
		p.weapon.set_aiming(true)
	if frame == 300:
		_shot("s02_ads")
		game._report("sway test: done")
		quit()
	return false
