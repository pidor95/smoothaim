extends SceneTree
## Dev test for the NPC behaviours: holding ground after a hit, choking on a
## neck wound (knees, then rolling on the floor) until bleeding out, the player's orders and the armed NPC's
## suicide. Run: godot -s res://tools/npc_behaviour_test.gd (env SHOTS=<dir>)

var frame := 0
var game: Node
var npc: Npc
var shots_dir := OS.get_environment("SHOTS")
var _step := 0
var _until := 0 # physics frame to wait for
var _t0 := 0
var _pos0 := Vector3.ZERO
var _max_off := 0.0


func _initialize() -> void:
	change_scene_to_file("res://scenes/game.tscn")


func _shot(shot_name: String) -> void:
	if shots_dir == "":
		return
	root.get_texture().get_image().save_png(shots_dir.path_join(shot_name + ".png"))
	print("shot ", shot_name)


func _aim_at(target: Vector3) -> void:
	var p: Player = game.player
	var d := (target - p.camera.global_position).normalized()
	p.yaw = atan2(-d.x, -d.z)
	p.pitch = asin(clampf(d.y, -1, 1))
	p.rotation.y = p.yaw
	p.head.rotation = Vector3(p.pitch, 0, 0)


func _fire() -> void:
	var w: Weapon = game.player.weapon
	w._cooldown = 0.0
	w.trigger()


func _spawn(pos: Vector3, armed := false) -> Npc:
	for n in get_nodes_in_group("npcs"):
		n.queue_free()
	var n := Npc.new()
	n.armed = armed
	n.position = pos
	game.add_child(n)
	n.died.connect(game._on_npc_died)
	return n


func _now() -> int:
	return Engine.get_physics_frames()


func _wait(sec: float) -> void:
	_until = _now() + int(sec * 60.0)


func _process(_delta: float) -> bool:
	frame += 1
	if frame == 5:
		game = current_scene
	if game == null or frame < 30:
		return false
	var p: Player = game.player
	if frame == 30:
		p.touch_mode = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		Npc.ai_enabled = false
		game.auto_spawn = false
		for n in get_nodes_in_group("npcs"):
			n.queue_free()
		p.global_position = Vector3(-4.0, 0.05, -4.5)
		return false
	if _now() < _until:
		if npc and is_instance_valid(npc) and _step == 2:
			var off := npc.global_position - _pos0
			_max_off = maxf(_max_off, Vector2(off.x, off.z).length())
		return false
	match _step:
		0:
			npc = _spawn(Vector3(-4.0, 0.05, -1.4))
			_wait(0.5)
		1:
			_pos0 = npc.global_position
			_aim_at(npc.chest.global_position)
			_fire()
			print("chest hit: state=", npc.state, " (3=STAGGER)")
			_wait(0.25)
		2:
			_shot("b01_holding_ground")
			_wait(1.2)
		3:
			var off := npc.global_position - _pos0
			print("held ground: max travel %.2f m, end %.2f m, state=%d" % [_max_off, Vector2(off.x, off.z).length(), npc.state])
			npc = _spawn(Vector3(-4.0, 0.05, -1.4))
			_wait(0.5)
		4:
			_aim_at(npc.head.to_global(Vector3(0, -0.13, -0.03)))
			_fire()
			_t0 = _now()
			print("neck hit: state=", npc.state, " (7=CHOKE) health=", npc.health, " neck=", npc._neck_wound)
			_wait(1.2)
		5:
			_shot("b02_choking")
			_wait(0.1)
		6:
			if npc._choke_phase >= 3:
				print("rolling on the floor after %.1f s, health=%.0f" % [(_now() - _t0) / 60.0, npc.health])
				_wait(1.3)
				_step = 7
			return false
		7:
			_shot("b03_choking_floor")
			_wait(0.1)
		8:
			if npc.dead:
				print("bled out after %.1f s (state %d)" % [(_now() - _t0) / 60.0, npc.state])
				_wait(1.5)
				_step = 9
			elif _now() - _t0 > 60 * 60:
				print("FAIL: still alive after 60 s")
				quit(1)
			return false
		9:
			_shot("b04_bled_out")
			npc = _spawn(Vector3(-4.0, 0.05, -1.4))
			_wait(0.5)
		10:
			_aim_at(npc.chest.global_position)
			game.give_order(2) # на колени
			print("order kneel: state=", npc.state, " (8=ORDER) order=", npc._order)
			_wait(1.5)
		11:
			print("kneeling pelvis y=%.2f" % npc.pelvis.global_position.y)
			_shot("b05_kneel")
			game.give_order(1) # руки вверх
			_wait(1.5)
		12:
			_shot("b06_hands_up")
			print("hands up: order=", npc._order, " farm_l y=%.2f" % npc.farm_l.global_position.y)
			game.give_order(6)
			npc = _spawn(Vector3(-4.0, 0.05, -1.4), true)
			_wait(0.6)
		13:
			_aim_at(npc.chest.global_position)
			_shot("b07_armed")
			print("armed=", npc.armed, " gun=", npc._gun != null)
			npc._start_suicide()
			_wait(1.2)
		14:
			_shot("b08_gun_to_temple")
			var muzzle: Vector3 = npc._gun.global_transform * Npc.GUN_MUZZLE
			print("muzzle to head centre %.3f m" % muzzle.distance_to(npc.head.global_position))
			_wait(0.1)
		15:
			if npc.dead:
				print("suicide: dead=", npc.dead, " suicided=", npc.suicided, " dropped guns=", get_nodes_in_group("dropped_guns").size(), " kills=", game.kills)
				_wait(0.15)
				_step = 16
			return false
		16:
			_shot("b09_after_shot")
			npc = _spawn(Vector3(-4.0, 0.05, -1.4), true)
			_wait(0.5)
		17:
			_aim_at(npc.chest.global_position)
			game.give_order(3) # брось оружие
			print("drop order: armed=", npc.armed, " order=", npc._order, " dropped guns=", get_nodes_in_group("dropped_guns").size())
			_wait(1.5)
		18:
			_shot("b10_dropped_gun")
			npc = _spawn(Vector3(-4.0, 0.05, -1.4), true)
			_wait(0.6)
		19:
			_aim_at(npc.chest.global_position)
			_shot("b11_armed_ready")
			game.give_order(7) # застрелись
			print("suicide order: suicide_t=", npc._suicide_t)
			_wait(0.1)
		20:
			if npc.dead:
				print("ordered suicide: suicided=", npc.suicided)
				_step = 21
			return false
		21:
			npc = _spawn(Vector3(-4.0, 0.05, -1.4), true)
			Npc.ai_enabled = true
			_wait(0.4)
		22:
			npc._start_fight()
			_t0 = _now()
			_wait(1.0)
		23:
			_shot("b12_npc_aiming")
			_wait(3.0)
		24:
			print("fight: state=", npc.state, " (9=SHOOT) ammo=", npc._ammo, " player hp=", p.health, " dead=", p.dead)
			Npc.ai_enabled = false
			p._respawn()
			p.global_position = Vector3(-4.0, 0.05, -4.5)
			npc = _spawn(Vector3(-4.0, 0.05, -1.4), true)
			_wait(0.5)
		25:
			_aim_at(npc.head.to_global(Vector3(0, -0.13, -0.03)))
			_fire()
			_wait(1.5)
		26:
			_shot("b13_choking_firing")
			_wait(3.0)
		27:
			print("choking armed: phase=", npc._choke_phase, " ammo=", npc._ammo, " player hp=", p.health)
			_shot("b14_choking_floor_firing")
			Player.immortal = true
			Npc.set_xray(true, self)
			npc = _spawn(Vector3(-4.0, 0.05, -1.4))
			_wait(0.5)
		28:
			_aim_at(npc.chest.global_position)
			_fire()
			_wait(0.2)
		29:
			_aim_at(npc.thigh_l.global_position)
			_fire()
			_wait(1.5)
		30:
			_shot("b15_xray")
			print("xray: channels=", npc._channels.size(), " nodes=", npc._xray_nodes.size())
			quit()
	_step += 1
	return false
