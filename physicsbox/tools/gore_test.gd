extends SceneTree
## Dev test of wounds and gore (war paused, in the town yard): AK hits leave
## torn holes in the uniform (entry and exit), a dead body settles and is
## frozen, a shot wakes it, and a drone warhead going off on a soldier tears
## him apart. Reports the costs (gore pieces, decal nodes, emitters).
## Run: godot -s res://tools/gore_test.gd   (env SHOTS=<dir> for PNGs)

var frame := 0
var game: Node
var p: Player
var npc: Npc
var shots_dir := OS.get_environment("SHOTS")
var _step := 0
var _wait := 0
var _mark := {}
var _cam := Camera3D.new() # close-ups, away from the player's bodycam sway


func _initialize() -> void:
	change_scene_to_file("res://scenes/game.tscn")


func _shot(shot_name: String) -> void:
	if shots_dir == "":
		return
	root.get_texture().get_image().save_png(shots_dir.path_join(shot_name + ".png"))
	print("shot ", shot_name)


## A still close-up through the test camera (`target` in the middle).
func _close_up(eye: Vector3, target: Vector3) -> void:
	if not _cam.is_inside_tree():
		_cam.fov = 60.0
		root.add_child(_cam)
	_cam.global_position = eye
	_cam.look_at(target)
	_cam.current = true


func _player_view() -> void:
	p.camera.current = true


func _look_from(eye: Vector3, target: Vector3) -> void:
	p.global_position = eye - Vector3(0, p.eye_height(), 0)
	p.velocity = Vector3.ZERO
	var d := (target - eye).normalized()
	p.yaw = atan2(-d.x, -d.z)
	p.pitch = asin(clampf(d.y, -1, 1))
	p.rotation.y = p.yaw
	p.head.rotation = Vector3(p.pitch, 0, 0)


func _fire_at(target: Vector3) -> void:
	_look_from(p.camera.global_position, target)
	p.weapon._cooldown = 0.0
	p.weapon.trigger()


func _costs(tag: String) -> void:
	var decals := 0
	var wound_mm := 0
	for n in get_nodes_in_group("npcs"):
		for part in n.parts:
			if part.has_meta("wounds"):
				wound_mm += 1
	decals = root.get_node("Blood")._body_splats.size()
	print("%s: gore pieces %d, body blood decals %d, wound multimeshes %d, nodes %d" % [tag,
			Gore._live.filter(func(b): return is_instance_valid(b)).size(), decals, wound_mm,
			Performance.get_monitor(Performance.OBJECT_NODE_COUNT)])


func _process(_delta: float) -> bool:
	if game == null or game.get("hud") == null:
		game = current_scene if current_scene and current_scene.has_method("spawn_soldier") else null
		return false
	frame += 1
	if frame < 30:
		return false
	if frame == 30:
		p = game.player
		p.touch_mode = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		Npc.ai_enabled = false
		game.set_physics_process(false)
		for n in get_nodes_in_group("npcs"):
			n.queue_free()
		Player.immortal = true
		p.weapon.select(0, false)
	if _wait > 0:
		_wait -= 1
		return false
	match _step:
		0:
			npc = game.spawn_npc(Vector3(97, 0.2, 4.0), 1)
			npc.rotation.y = PI # facing the player (+Z)
			npc.health = 9999.0 # soaks the rounds to show the holes standing
			npc.display_only = true # and does not fall over
			_look_from(Vector3(97, 1.5, 9.0), Vector3(97, 1.2, 4.0))
			_wait = 20
		1:
			# rounds into the chest (the plates stop the middle), the arms, the thighs
			for t in [Vector3(-0.17, 1.25, 0.1), Vector3(0.16, 1.05, 0.1), Vector3(-0.27, 1.3, 0.05), Vector3(0.1, 0.7, 0.05),
					Vector3(-0.1, 0.62, 0.05), Vector3(0.0, 0.95, 0.12)]:
				npc.state = Npc.State.IDLE
				_fire_at(npc.global_position + t)
			_costs("after 6 rounds")
			_wait = 8
		2:
			# he faces the player: the rounds went in at the front...
			_close_up(npc.chest.global_position + Vector3(0.25, 0.1, 1.1), npc.chest.global_position + Vector3(0, -0.25, 0))
			_wait = 4
		3:
			_shot("g00_entry_wounds")
			_wait = 60
		4:
			# ...and out at the back
			_close_up(npc.chest.global_position + Vector3(-0.25, 0.1, -1.1), npc.chest.global_position + Vector3(0, -0.25, 0))
			_wait = 4
		5:
			_shot("g02_exit_wounds")
			_player_view()
			# now kill him and watch the body settle
			npc.display_only = false
			npc.health = 10.0
			_look_from(Vector3(97, 1.5, 9.0), Vector3(97, 1.0, 4.0))
			_fire_at(npc.chest.global_position + Vector3(0.1, 0, 0))
			_mark.t = 0
			_wait = 1
		6:
			_mark.t += 1
			if _mark.t % 60 == 0:
				var fast := npc.parts.map(func(q): return "%s %.2f/%.2f" % [q.name, q.linear_velocity.length(), q.angular_velocity.length()]) \
						if not npc._settled else []
				print("t=%.0f still %.2f %s" % [_mark.t / 60.0, npc._still_t, fast])
			if not npc._settled and _mark.t < 600:
				_step -= 1
			else:
				print("dead=%s settled after %.1f s, parts frozen=%s" % [npc.dead, _mark.t / 60.0, npc.parts.all(func(q): return q.freeze)])
				_shot("g03_settled")
			_wait = 1
		7:
			_fire_at(npc.chest.global_position)
			print("shot the body: settled=%s chest frozen=%s" % [npc._settled, npc.chest.freeze])
			_wait = 30
		8:
			# a drone warhead going off right on a soldier
			_costs("before the drone")
			var n2: Npc = game.spawn_npc(Vector3(93, 0.2, 2.0), 1)
			_mark.n2 = n2
			_look_from(Vector3(93, 2.2, 10.0), Vector3(93, 0.8, 2.0))
			_wait = 20
		9:
			var n2: Npc = _mark.n2
			_close_up(n2.chest.global_position + Vector3(2.5, 1.6, 4.5), n2.chest.global_position + Vector3(0, -0.4, 0))
			Explosion.boom(self, n2.chest.global_position + Vector3(0, 0, 0.4), 1.4, true, "blast_big")
			_wait = 10
		10:
			var n2: Npc = _mark.n2
			print("torn apart: dead=%s severed %d, head gone %s, guts %s" % [n2.dead, n2._severed.size(), n2.head_gone, n2._guts_spilled])
			_costs("right after the blast")
			_shot("g04_fpv_blast")
			_wait = 30
		11:
			_shot("g05_fpv_aftermath")
			var n2: Npc = _mark.n2
			_close_up(n2.chest.global_position + Vector3(1.2, 1.4, 1.6), n2.chest.global_position)
			_wait = 150
		12:
			_shot("g06_fpv_scattered")
			_costs("3 s after")
			_wait = 400
		13:
			var asleep := Gore._live.filter(func(b): return is_instance_valid(b) and b.freeze).size()
			print("gore pieces frozen at rest: %d of %d" % [asleep, Gore._live.filter(func(b): return is_instance_valid(b)).size()])
			print("gore test done")
			quit()
	_step += 1
	return false
