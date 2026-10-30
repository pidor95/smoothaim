extends SceneTree
## Quick headless check of the medic's logic: a man out cold, a medic
## nearby; his states over time, then the player calling him.
## Run: godot --headless -s res://tools/medic_ai_test.gd

var frame := 0
var game: Node
var medic: Npc
var hurt: Npc
var p: Player
var _t0 := 0
var _phase := 0


func _initialize() -> void:
	change_scene_to_file("res://scenes/game.tscn")


## The point of `pts` closest to `dist` metres from `at`.
func _near(pts: Array, at: Vector3, dist: float) -> Vector3:
	var best: Vector3 = pts[0]
	for q in pts:
		if absf(q.distance_to(at) - dist) < absf(best.distance_to(at) - dist):
			best = q
	return best


func _process(_delta: float) -> bool:
	if game == null or game.get("hud") == null:
		game = current_scene if current_scene and current_scene.has_method("spawn_soldier") else null
		return false
	if frame == 35 and NavigationServer3D.map_get_closest_point(root.get_world_3d().navigation_map, game.player.global_position) == Vector3.ZERO:
		return false # (the big navigation map takes a few seconds to sync)
	frame += 1
	if frame == 30:
		p = game.player
		game.set_physics_process(false)
		for n in get_nodes_in_group("npcs"):
			n.queue_free()
		Player.immortal = true
	if frame == 40:
		# all in the trenches: the player at his start in the front trench, the
		# man down at a post along it, the medic in the rear trench
		p.global_position = game.house.player_spawn.origin
		hurt = game.spawn_npc(_near(game.house.team_posts[0], p.global_position, 6.0), 0)
		medic = game.spawn_npc(_near(game.house.team_spawns[0], p.global_position, 15.0), 0, "rifle", true)
		medic.post = medic.global_position
	if frame == 80:
		hurt.health = 40.0
		hurt._faint(hurt.chest, hurt.chest.global_position, Vector3(1, 0, 0), 8.0)
		hurt._out_cold = 90.0
		_t0 = frame
		_phase = 1
	if _phase >= 1 and (frame - _t0) % 30 == 0:
		var tgt: Node3D = hurt if _phase == 1 else p
		print("t=%.1f medic state=%d treat=%.1f dist=%.1f has_patient=%s v=%.1f fin=%s next=%s at=%s tgt=%s | hurt state=%d uncon=%s | p hits=%d wants=%s" % [
				(frame - _t0) / 60.0, medic.state, medic._treat_t, medic.global_position.distance_to(tgt.global_position),
				medic._patient != null, medic.velocity.length(), medic._agent.is_navigation_finished(),
				medic._agent.get_next_path_position() - medic.global_position, medic.global_position, medic._agent.target_position,
				hurt.state, hurt.unconscious, p.hits, p.wants_medic])
	if _phase == 1 and (hurt.state == Npc.State.GETUP or frame - _t0 > 2400):
		print("phase 1 end: hurt state %d hp %.0f" % [hurt.state, hurt.health])
		_phase = 2
		_t0 = frame
		p.hits = 3
		p.bleed_rate = 5.0
		p.call_medic()
		print("call: %s" % p.medic_note)
	if _phase == 2 and (not p.wants_medic or frame - _t0 > 2400):
		print("phase 2 end: hits %d bleed %.1f" % [p.hits, p.bleed_rate])
		quit()
	return false
