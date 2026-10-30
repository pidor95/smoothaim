extends SceneTree
## Dev look at the doubled map: the start, the far western trenches, a
## village deep behind the lines, east of the town; memory after loading.
## Run: godot -s res://tools/map_test.gd  (env SHOTS=<dir>)

var frame := 0
var game: Node
var p: Player
var shots_dir := OS.get_environment("SHOTS")
var _k := 0
const SPOTS := [
	["a0_start", Vector3.INF, 0.0],
	["a1_far_west", Vector3(-500, 0, 34), PI / 2],
	["a2_rear_village", Vector3(-410, 0, 186), 0.0],
	["a3_enemy_rear", Vector3(-100, 0, -186), PI],
	["a4_east_fields", Vector3(185, 0, 70), -PI / 2],
]


func _initialize() -> void:
	change_scene_to_file("res://scenes/game.tscn")


func _process(_delta: float) -> bool:
	if game == null or game.get("hud") == null:
		game = current_scene if current_scene and current_scene.has_method("spawn_soldier") else null
		return false
	frame += 1
	if frame == 30:
		p = game.player
		Player.immortal = true
		game._report("map test: loaded")
	if frame >= 40 and (frame - 40) % 40 == 0:
		if _k > 0 and shots_dir != "":
			root.get_texture().get_image().save_png(shots_dir.path_join(SPOTS[_k - 1][0] + ".png"))
			print("shot ", SPOTS[_k - 1][0])
		if _k >= SPOTS.size():
			game._report("map test: done")
			quit()
			return false
		var at: Vector3 = SPOTS[_k][1]
		if at != Vector3.INF:
			var q := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 60, at + Vector3.DOWN * 60, 1)
			var hit := root.get_world_3d().direct_space_state.intersect_ray(q)
			p.global_position = (hit.position if not hit.is_empty() else at) + Vector3.UP * 0.2
			p.velocity = Vector3.ZERO
			p.yaw = SPOTS[_k][2]
			p.pitch = -0.05
		_k += 1
	return false
