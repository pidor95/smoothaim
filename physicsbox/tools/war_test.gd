extends SceneTree
## Dev test for the war: loads the trench map, lets both sides fight for a
## while (player immortal) and reports what happened; saves screenshots.
## Run: godot -s res://tools/war_test.gd   (env SHOTS=<dir>, SECONDS=<n>)

var frame := 0
var game: Node
var shots_dir := OS.get_environment("SHOTS")
var duration := float(OS.get_environment("SECONDS")) if OS.get_environment("SECONDS") != "" else 30.0
var _t0 := 0
var _next_report := 5.0
var _shot_k := 0
var _deaths := [0, 0]
var _downed_seen := 0


func _initialize() -> void:
	change_scene_to_file("res://scenes/game.tscn")


func _shot(shot_name: String) -> void:
	if shots_dir == "":
		return
	root.get_texture().get_image().save_png(shots_dir.path_join(shot_name + ".png"))
	print("shot ", shot_name)


func _process(_delta: float) -> bool:
	frame += 1
	if frame == 5:
		game = current_scene
	if game == null or frame < 20:
		return false
	var p: Player = game.player
	if frame == 20:
		p.touch_mode = true
		Player.immortal = true
		_t0 = Engine.get_physics_frames()
	var t := (Engine.get_physics_frames() - _t0) / 60.0
	if t >= _next_report:
		_next_report += 5.0
		var counts := {}
		var teams := [0, 0]
		var downed := 0
		for n in get_nodes_in_group("npcs"):
			if n.dead:
				continue
			teams[n.team] += 1
			var key: String = Npc.State.keys()[n.state]
			counts[key] = counts.get(key, 0) + 1
			if n._downed:
				downed += 1
		_downed_seen = maxi(_downed_seen, downed)
		print("t=%.0f alive %s tickets %s states %s downed %d kills %d" % [t, teams, game.tickets, counts, downed, game.kills])
		# look at the fight: from the player's trench towards the enemy, then from above
		var sp: Vector3 = game.house.player_spawn.origin
		var cam_pos: Vector3 = [sp + Vector3(0, 1.3, -0.2), sp + Vector3(0, 14, 8), Vector3(97, 1.6, 8), Vector3(97, 6.6, 18.8)][_shot_k % 4]
		p.global_position = cam_pos - Vector3(0, 1.62, 0)
		p.velocity = Vector3.ZERO
		p.yaw = 0.0 if _shot_k % 4 != 2 else PI
		p.pitch = [-0.05, -0.45, 0.1, -0.1][_shot_k % 4]
		p.rotation.y = p.yaw
		p.head.rotation = Vector3(p.pitch, 0, 0)
	if t >= _next_report - 4.9 and t < _next_report - 4.8 and _shot_k < 12:
		_shot("w%02d" % _shot_k)
		_shot_k += 1
	if t >= duration:
		print("done: tickets ", game.tickets, " max downed at once ", _downed_seen, " kills ", game.kills)
		quit()
	return false
