extends SceneTree
## Long war run to hunt leaks and hitches: every 15 s of game time prints
## memory, object / node / orphan counts, physics bodies, NPCs, effects, and
## the slowest frame since the last report (what it was busy with).
## Run: godot --headless --fixed-fps 60 -s res://tools/soak_test.gd  (env SECONDS=<n>)

var game: Node
var duration := float(OS.get_environment("SECONDS")) if OS.get_environment("SECONDS") != "" else 360.0
var _t0 := -1
var _next := 0.0
var _last_us := 0
var _worst_ms := 0.0
var _worst_at := 0.0
var _frames_over := 0


func _initialize() -> void:
	change_scene_to_file("res://scenes/game.tscn")


func _process(_delta: float) -> bool:
	var now := Time.get_ticks_usec()
	var ms := (now - _last_us) / 1000.0 if _last_us > 0 else 0.0
	_last_us = now
	if game == null or game.get("hud") == null:
		game = current_scene if current_scene and current_scene.has_method("spawn_soldier") else null
		return false
	if _t0 < 0:
		_t0 = Engine.get_physics_frames()
		Player.immortal = true
		game.player.touch_mode = true
	var t := (Engine.get_physics_frames() - _t0) / 60.0
	if ms > _worst_ms:
		_worst_ms = ms
		_worst_at = t
	if ms > 100.0:
		_frames_over += 1
	if t >= _next:
		_next += 15.0
		var groups := {}
		for g in ["npcs", "grenades", "drones", "dropped_guns", "doors"]:
			groups[g] = get_nodes_in_group(g).size()
		var dead := 0
		for n in get_nodes_in_group("npcs"):
			if n.dead:
				dead += 1
		print("t=%4.0f mem %.0f MB (peak %.0f) vmem %.0f MB objects %d nodes %d orphans %d bodies %d/%d npcs %d (dead %d) %s worst %.0f ms @%.0f, >100ms: %d" % [
				t, OS.get_static_memory_usage() / 1048576.0, OS.get_static_memory_peak_usage() / 1048576.0,
				Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
				Performance.get_monitor(Performance.OBJECT_COUNT), Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
				Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT),
				Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS), Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS),
				groups.npcs, dead, groups, _worst_ms, _worst_at, _frames_over])
		_worst_ms = 0.0
		_frames_over = 0
	if t >= duration:
		print("soak done, kills ", game.kills, " tickets ", game.tickets)
		quit()
	return false
