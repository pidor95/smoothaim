extends SceneTree
## Dev test of the NPC WAR mechanics in the town yard (war paused): hit
## physics, fainting from pain and finishing off, the death throes, blind
## fire after a neck wound (at most 5 s), the player's wounds and death
## (black screen round a white dot), the grenade throw animation, automatic
## fire, the sniper rifles and their scopes, the plate carrier, and the FPV
## drone hovering and flown with the arrows.
## Run: godot -s res://tools/mechanics_test.gd   (env SHOTS=<dir> for PNGs)

var frame := 0
var game: Node
var p: Player
var npc: Npc
var shots_dir := OS.get_environment("SHOTS")
var _step := 0
var _wait := 0
var _mark := {}


func _initialize() -> void:
	change_scene_to_file("res://scenes/game.tscn")


func _shot(shot_name: String) -> void:
	if shots_dir == "":
		return
	root.get_texture().get_image().save_png(shots_dir.path_join(shot_name + ".png"))
	print("shot ", shot_name)


func _aim_at(target: Vector3) -> void:
	var d := (target - p.camera.global_position).normalized()
	p.yaw = atan2(-d.x, -d.z)
	p.pitch = asin(clampf(d.y, -1, 1))
	p.rotation.y = p.yaw
	p.head.rotation = Vector3(p.pitch, 0, 0)


func _fire() -> void:
	p.weapon._cooldown = 0.0
	p.weapon.trigger()


func _spawn(pos: Vector3) -> Npc:
	var n: Npc = game.spawn_npc(pos, 1)
	n.rotation.y = 0.0
	return n


func _process(_delta: float) -> bool:
	if game == null or game.get("hud") == null:
		game = current_scene if current_scene and current_scene.has_method("spawn_soldier") else null
		return false # the front is still being put together
	frame += 1
	if game == null or frame < 30:
		return false
	if frame == 30:
		p = game.player
		p.touch_mode = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		Npc.ai_enabled = false
		game.set_physics_process(false) # no reinforcements, no drones
		for n in get_nodes_in_group("npcs"):
			n.queue_free()
		p.global_position = Vector3(97, 0.3, 7.0)
		p.yaw = 0.0
		Player.immortal = true
	if _wait > 0:
		_wait -= 1
		return false
	match _step:
		0:
			npc = _spawn(Vector3(97, 0.2, 2.0))
			_wait = 30
		1:
			_mark.pos = npc.global_position
			_aim_at(npc.chest.global_position)
			_fire()
			print("AK chest hit: state=%s balance=%.2f pain=%.0f" % [Npc.State.keys()[npc.state], npc.balance, npc._pain])
			_wait = 8
		2:
			_shot("m01_hit_reaction")
			_wait = 30
		3:
			print("shoved back %.2f m by one round" % npc.global_position.distance_to(_mark.pos))
			# a hit on top of a lot of pain: he may faint (45 %) - make sure he does
			npc._pain = 95.0
			_aim_at(npc.chest.global_position)
			_fire()
			if not npc.unconscious and not npc.dead:
				npc._faint(npc.chest, npc.chest.global_position, Vector3.FORWARD, 10.0)
			print("after more hits: state=%s unconscious=%s combatant=%s" % [Npc.State.keys()[npc.state], npc.unconscious, npc.is_combatant()])
			_wait = 120
		4:
			_shot("m02_out_cold")
			print("2 s later: state=%s unconscious=%s dead=%s" % [Npc.State.keys()[npc.state], npc.unconscious, npc.dead])
			# finish him off
			_aim_at(npc.head.global_position)
			for i in 3:
				_fire()
			_mark.limbs = 0.0
			_wait = 2
		5:
			print("finished off: dead=%s spasm time %.1f s" % [npc.dead, npc._spasm_time])
			_step = 50 # measure the throes for 2 s
			_mark.t = 0
			return false
		50:
			var sum := 0.0
			for part in [npc.shin_l, npc.shin_r, npc.farm_l, npc.farm_r]:
				sum += part.angular_velocity.length()
			_mark.limbs += sum
			_mark.t += 1
			if _mark.t == 40:
				_shot("m03_throes")
			if _mark.t >= 120:
				print("death throes: mean limb angular speed %.2f rad/s over 2 s" % (_mark.limbs / 120.0))
				_step = 6
			return false
		6:
			# neck wound on an armed soldier: blind fire for the first seconds only
			npc = _spawn(Vector3(94, 0.2, 2.0))
			_wait = 30
		7:
			npc._wild_left = -1.0
			_aim_at(npc.head.global_position + Vector3(0, -0.1, 0))
			_fire()
			print("neck hit: state=%s neck=%s wild_left=%.1f" % [Npc.State.keys()[npc.state], npc._neck_wound, npc._wild_left])
			npc._wild_left = 5.0 # make it one who shoots, to time it
			_mark.ammo0 = npc._ammo
			_mark.t = 0
			_step = 70
			return false
		70:
			_mark.t += 1
			if _mark.t == 60 * 5 + 20:
				_mark.ammo5 = npc._ammo
			if _mark.t == 60 * 8:
				print("blind fire: shots in first 5 s=%d, after=%d" % [_mark.ammo0 - _mark.ammo5, _mark.ammo5 - npc._ammo])
				_step = 171
			return false
		171:
			# a sniper round: always drops him, goes through the plate
			p.weapon.select(1, false)
			npc = _spawn(Vector3(100, 0.2, 0.0))
			_wait = 30
		172:
			_aim_at(npc.chest.global_position)
			_fire()
			print("SVD chest hit: state=%s dead=%s health=%.0f" % [Npc.State.keys()[npc.state], npc.dead, npc.health])
			_wait = 40
		173:
			_shot("m10_svd_hit")
			# armour: an AK round on the plate
			p.weapon.select(0, false)
			npc = _spawn(Vector3(98.5, 0.2, 1.0))
			_wait = 30
		174:
			var h0 := npc.health
			_aim_at(npc.chest.to_global(Vector3(0.05, 0.05, -0.12)))
			_fire()
			print("AK on the plate: health %.0f -> %.0f, state=%s pain=%.0f" % [h0, npc.health, Npc.State.keys()[npc.state], npc._pain])
			_wait = 30
		175:
			# through the PSO-1
			p.weapon.select(1, false)
			_wait = 30
		176:
			_aim_at(Vector3(97, 4.0, -20.0))
			p.weapon.aiming = true
			_wait = 50
		177:
			_shot("m11_pso_scope")
			p.weapon.aiming = false
			p.weapon.select(0, false)
			_wait = 30
		178:
			_shot("m12_ak_kobra")
			# running: the joystick pushed hard forward
			p.touch_move = Vector2(0, -1)
			p.sprint_stick = true
			_wait = 90
		179:
			print("sprint: speed %.1f m/s, stamina %.2f, sprinting=%s" % [Vector2(p.velocity.x, p.velocity.z).length(), p.stamina, p.sprinting])
			_shot("m13_sprint")
			p.sprint_stick = false
			p.touch_move = Vector2.ZERO
			p.set_crouch(true)
			_wait = 60
		180:
			print("crouched: eye %.2f m, capsule %.2f m" % [p.eye_height(), p._shape.height])
			_shot("m14_crouch")
			p.touch_move = Vector2(0, -1)
			_wait = 30
		181:
			print("crouch walk: %.1f m/s" % Vector2(p.velocity.x, p.velocity.z).length())
			p.touch_move = Vector2.ZERO
			p.set_crouch(false)
			p.global_position = Vector3(97, 0.3, 7.0)
			_step = 8
			_wait = 30
			return false
		8:
			# automatic fire with the touch button held
			var w := p.weapon
			w.select(0, false)
			w.current.ammo = 30
			_aim_at(Vector3(97, 1.0, -5.0))
			w.trigger_held = true
			_mark.t = 0
			_step = 80
			return false
		80:
			_mark.t += 1
			if _mark.t == 60:
				p.weapon.trigger_held = false
				p.weapon.select(0, false)
				print("held fire 1 s: %d rounds left of 30" % p.weapon.current.ammo)
				_step = 9
			return false
		9:
			# grenade: the arm animation, the grenade leaves the hand
			_aim_at(Vector3(97, 3.0, -20.0))
			p.grenades = 4
			p.throw_grenade()
			_mark.nades = get_nodes_in_group("grenades").size()
			_wait = 18
		10:
			_shot("m04_throw_pin")
			_wait = 25
		11:
			_shot("m05_throw_swing")
			print("grenades in the air after the swing: %d (before %d)" % [get_nodes_in_group("grenades").size(), _mark.nades])
			_wait = 150
		12:
			# FPV drone: it must hang in the air with no input
			p.launch_drone()
			_wait = 120
		13:
			_mark.pos = p.piloting.global_position
			_wait = 60
		14:
			print("drone hovering: moved %.2f m in 1 s with no input" % p.piloting.global_position.distance_to(_mark.pos))
			_mark.yaw = p.piloting._yaw
			_mark.pos = p.piloting.global_position
			p.drone_arrows = Vector2(1, 0)
			_wait = 30
		15:
			print("right arrow: turned %.2f rad, moved %.2f m" % [p.piloting._yaw - _mark.yaw, p.piloting.global_position.distance_to(_mark.pos)])
			p.drone_arrows = Vector2(0, 1)
			_mark.pos = p.piloting.global_position
			_wait = 60
			_step = 150
		151:
			print("up arrow (forward) 1 s: flew %.1f m" % p.piloting.global_position.distance_to(_mark.pos))
			_shot("m06_fpv_forward")
			p.drone_arrows = Vector2.ZERO
			_wait = 90
		152:
			print("let go 1.5 s: speed %.2f m/s" % p.piloting.velocity.length())
			p.piloting.detonate()
			_step = 16
			_wait = 90
			return false
		16:
			# the player's wounds: four bullets wound, the fifth kills
			Player.immortal = false
			p.global_position = Vector3(97, 0.3, 7.0)
			for i in 4:
				p.take_damage(16.0, Vector3.FORWARD)
			print("4 hits: dead=%s blood=%.0f bpm=%.0f status ear_ring=%.2f" % [p.dead, p.blood, p.bpm, p.ear_ring])
			_wait = 60
		17:
			_shot("m07_wounded")
			p.take_damage(16.0, Vector3.FORWARD)
			print("5th hit: dead=%s" % p.dead)
			_wait = 50
		18:
			_shot("m08_dying_dot")
			_wait = 140
		19:
			_shot("m09_dead_black")
			print("death_t=%.1f" % p.death_t)
			_wait = 260
		20:
			print("respawned: dead=%s hits=%d blood=%.0f" % [p.dead, p.hits, p.blood])
			quit()
	_step += 1
	return false
