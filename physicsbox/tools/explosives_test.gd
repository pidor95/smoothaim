extends SceneTree
## Dev test for grenades and FPV drones (town yard of the front): a grenade among
## enemy soldiers, an enemy drone hunting the player, and the player flying
## his own drone into the enemy. Run: godot -s res://tools/explosives_test.gd
## (env SHOTS=<dir> to save PNGs)

var frame := 0
var game: Node
var shots_dir := OS.get_environment("SHOTS")
var _step := 0
var _until := 0
var _men: Array[Npc] = []
var _drone: FpvDrone
var _hp0 := 0.0


func _initialize() -> void:
	change_scene_to_file("res://scenes/game.tscn")


func _shot(shot_name: String) -> void:
	if shots_dir == "":
		return
	root.get_texture().get_image().save_png(shots_dir.path_join(shot_name + ".png"))
	print("shot ", shot_name)


func _now() -> int:
	return Engine.get_physics_frames()


func _wait(sec: float) -> void:
	_until = _now() + int(sec * 60.0)


func _look(p: Player, at: Vector3) -> void:
	var d := (at - p.camera.global_position).normalized()
	p.yaw = atan2(-d.x, -d.z)
	p.pitch = asin(clampf(d.y, -1, 1))
	p.rotation.y = p.yaw
	p.head.rotation = Vector3(p.pitch, 0, 0)


func _report(label: String) -> void:
	var dead := 0
	var downed := 0
	var severed := 0
	for m in _men:
		if not is_instance_valid(m):
			continue
		dead += int(m.dead)
		downed += int(m._downed and not m.dead)
		severed += m._severed.size()
	print(label, ": dead ", dead, " downed ", downed, " limbs off ", severed)


func _process(_delta: float) -> bool:
	frame += 1
	if frame == 5:
		game = current_scene
	if game == null or frame < 30:
		return false
	var p: Player = game.player
	if frame == 30:
		p.touch_mode = true
		Npc.ai_enabled = false
		game.set_physics_process(false) # no reinforcements, no drones
		for n in get_nodes_in_group("npcs"):
			n.queue_free()
		p.global_position = Vector3(0 + 97.0, 0.4, 9.0)
		return false
	if _drone and is_instance_valid(_drone) and _drone.pilot and _men.size() > 0 and is_instance_valid(_men[0]):
		# steer the player's drone over the trees, then down onto the group
		var aim := _men[0].center()
		if Vector2(aim.x - _drone.global_position.x, aim.z - _drone.global_position.z).length() > 7.0:
			aim.y += 5.0
		var to := aim - _drone.global_position
		_drone._yaw = atan2(-to.x, -to.z)
		_drone._pitch = atan2(to.y, Vector2(to.x, to.z).length())
	if _now() < _until:
		return false
	match _step:
		0:
			for i in 4:
				var m: Npc = game.spawn_npc(Vector3(-1.5 + i + 97.0, 0.4, 0.0 + (i % 2) * 0.8), 1)
				_men.append(m)
			_wait(0.6)
		1:
			_look(p, Vector3(0 + 97.0, 0.8, 0))
			Grenade.throw(self, Vector3(0.2 + 97.0, 0.5, 0.4), Vector3.ZERO, true, 0.8)
			_wait(0.82)
		2:
			_shot("x01_grenade_blast")
			_wait(0.6)
		3:
			_shot("x02_after_grenade")
			_report("grenade")
			print("player kills ", game.kills, " shake ", snappedf(p.shake, 0.01))
			_wait(2.0)
		4:
			_shot("x03_smoke")
			Player.immortal = false
			_hp0 = p.blood
			_drone = game.send_enemy_drone()
			_drone.target = p
			_drone.global_position = Vector3(0 + 97.0, 8, -20)
			_wait(1.0)
		5:
			_look(p, _drone.global_position)
			_shot("x04_enemy_drone")
			_wait(0.1)
		6:
			if not is_instance_valid(_drone):
				print("enemy drone hit: player blood ", _hp0, " -> ", p.blood, " hits ", p.hits, " dead ", p.dead)
				_drone = null
				_wait(0.5)
				_step = 7
			return false
		7:
			if p.dead:
				p._respawn()
			Player.immortal = true
			p.global_position = Vector3(0 + 97.0, 0.4, 14.0)
			_men.clear()
			for i in 3:
				_men.append(game.spawn_npc(Vector3(-1.0 + i + 97.0, 0.4, -6.0), 1))
			_wait(0.5)
		8:
			_look(p, Vector3(0 + 97.0, 1, -6))
			p.launch_drone()
			_drone = p.piloting
			print("piloting: ", _drone != null, " drones left ", p.drones)
			_wait(0.7)
		9:
			_shot("x05_fpv_view")
			_wait(0.1)
		10:
			if p.piloting == null:
				_shot("x06_signal_lost")
				_report("fpv strike")
				_drone = null
				_wait(1.0)
				_step = 11
			return false
		11:
			_look(p, Vector3(0, 0.5, -6))
			_shot("x07_after_fpv")
			quit()
	_step += 1
	return false
