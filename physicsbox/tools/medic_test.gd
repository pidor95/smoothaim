extends SceneTree
## Dev test of the new kit (war paused): the AK's two sights (round tube
## collimator, Kobra) looked through, the AS Val (hip, sights, its quiet
## shot), the helmet GoPro, first aid (bandage, promedol, medkit, a pouch
## picked up off the ground), a medic patching up a man out cold and the
## player who called him, and the death as on the video.
## Run: godot -s res://tools/medic_test.gd   (env SHOTS=<dir> for PNGs)

var frame := 0
var game: Node
var p: Player
var shots_dir := OS.get_environment("SHOTS")
var _step := 0
var _wait := 0
var S: Node # the Settings autoload (only reachable through the tree here)
var medic: Npc
var hurt: Npc
var foe: Npc
var _t0 := 0


func _initialize() -> void:
	change_scene_to_file("res://scenes/game.tscn")


func _shot(shot_name: String) -> void:
	if shots_dir == "":
		return
	root.get_texture().get_image().save_png(shots_dir.path_join(shot_name + ".png"))
	print("shot ", shot_name)


func _look(yaw: float, pitch := 0.0) -> void:
	p.yaw = yaw
	p.pitch = pitch


## Stand `dist` m from `who` (towards +X) and look at him, gun away.
func _watch(who: Node3D, dist := 3.5) -> void:
	p.weapon.holster()
	p.global_position = who.global_position + Vector3(dist, 0.3, 1.0)
	var d: Vector3 = who.global_position + Vector3.UP * 0.5 - (p.global_position + Vector3.UP * 1.6)
	_look(atan2(-d.x, -d.z), atan2(d.y, Vector2(d.x, d.z).length()))


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
	frame += 1
	if frame < 30:
		return false
	if frame == 30:
		p = game.player
		S = root.get_node("Settings")
		p.touch_mode = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		Npc.ai_enabled = false
		game.set_physics_process(false)
		for n in get_nodes_in_group("npcs"):
			n.queue_free()
		Player.immortal = false
		p.global_position = Vector3(-30, 0.3, 40.0)
		for k in S.loadout:
			S.loadout[k] = true
		S.suppressed.ak74 = false
		S.sight.ak74 = "collimator"
		S.camera = "bodycam"
		S.apply()
		p.weapon.apply_mods()
		p.weapon.select(0, false)
		_look(PI / 2)
		_step = int(OS.get_environment("FROM")) # (env FROM=<step>: start part way through)
	if _wait > 0:
		_wait -= 1
		return false
	var w := p.weapon
	match _step:
		0:
			# a soldier down range to aim at
			foe = game.spawn_npc(p.global_position + Vector3(-25, 0, 0), 1)
			foe.rotation.y = -PI / 2
			_wait = 20
		1:
			_shot("m00_ak_collimator_hip")
			w.set_aiming(true)
			_wait = 40
		2:
			_shot("m01_ak_collimator_ads")
			S.sight.ak74 = "kobra"
			w.apply_mods()
			_wait = 20
		3:
			_shot("m02_ak_kobra_ads")
			S.sight.ak74 = "collimator"
			w.apply_mods()
			w.set_aiming(false)
			w.select(2)
			_wait = 40
		4:
			_shot("m03_val_hip")
			w._cooldown = 0.0
			w.trigger()
			print("VAL shot: id=%s flash=%s quiet=%s heard within %.1f m, sound loaded=%s" % [w.current.def.id, w._flash_root.visible,
					w.suppressed(), w.current.def.alert * Weapon.SUPPRESSED_ALERT, root.get_node("Sfx")._pick("val") != null])
			w.set_aiming(true)
			_wait = 40
		5:
			_shot("m04_val_ads")
			w.set_aiming(false)
			w.select(0)
			p.toggle_camera()
			_wait = 40
		6:
			_shot("m05_gopro")
			p.touch_move = Vector2(0, -1)
			_wait = 25
		7:
			_shot("m06_gopro_walk")
			p.touch_move = Vector2.ZERO
			w.set_aiming(true)
			_wait = 30
		8:
			_shot("m07_gopro_ads")
			w.set_aiming(false)
			p.toggle_camera()
			if foe:
				foe.queue_free()
			# first aid: wounded and bleeding
			p.hits = 3
			p.blood = 3800.0
			p.bleed_rate = 9.0
			p.start_treat("bandage")
			_wait = 30
		9:
			_shot("m08_bandage")
			_wait = 170
		10:
			print("after bandage: bleed %.2f ml/s, bandages %d, treating '%s'" % [p.bleed_rate, p.bandages, p.treating])
			p.start_treat("promedol")
			_wait = 110
		11:
			print("after promedol: painkiller %.0f s, consciousness %.2f" % [p.painkiller, p.consciousness])
			p.start_treat("medkit")
			_wait = 380
		12:
			print("after medkit: hits %d, blood %.0f, medkits %d" % [p.hits, p.blood, p.medkits])
			_shot("m09_after_medkit")
			# a pouch on the ground: walk onto it
			var kit: Node3D = game._medkits[0][0]
			p.global_position = kit.global_position + Vector3(3, 0.3, 0)
			_look(PI / 2, -0.5)
			_wait = 20
		13:
			_shot("m10_medkit_on_ground")
			p.global_position = game._medkits[0][0].global_position + Vector3(0, 0.3, 0)
			_wait = 10
		14:
			game._medkit_pickups(0.1) # (the war's physics step is off in this test)
			print("picked up: bandages %d promedol %d medkits %d, pouch visible=%s" % [p.bandages, p.promedol, p.medkits, game._medkits[0][0].visible])
			# a medic patches up a man out cold
			Npc.ai_enabled = true
			p.global_position = game.house.player_spawn.origin
			hurt = game.spawn_npc(_near(game.house.team_posts[0], p.global_position, 6.0), 0)
			medic = game.spawn_npc(_near(game.house.team_spawns[0], p.global_position, 15.0), 0, "rifle", true)
			medic.post = medic.global_position
			_wait = 40
		15:
			hurt.health = 40.0
			hurt._faint(hurt.chest, hurt.chest.global_position, Vector3(1, 0, 0), 8.0)
			hurt._out_cold = 90.0 # (so he does not come round by himself first)
			print("knocked out: needs medic=%s" % hurt.needs_medic())
			_look(PI / 2 + 0.5, -0.25)
			_t0 = frame
			_wait = 10
		16:
			if medic.state != Npc.State.TREAT and frame - _t0 < 900:
				return false
			print("medic arrived after %.1f s, state TREAT" % ((frame - _t0) / 60.0))
			_watch(medic)
			_wait = 60
		17:
			_shot("m11_medic_treats")
			_t0 = frame
			_wait = 0
		18:
			if hurt.state != Npc.State.GETUP and hurt.state != Npc.State.IDLE and frame - _t0 < 600:
				return false
			print("patched up: state %d, health %.0f, unconscious %s" % [hurt.state, hurt.health, hurt.unconscious])
			_wait = 60
		19:
			_shot("m12_patched_up")
			# the player calls the medic
			p.global_position = game.house.player_spawn.origin
			p.hits = 3
			p.bleed_rate = 6.0
			medic.global_position = p.global_position + Vector3(-10, 0, 12)
			p.call_medic()
			print("call: '%s'" % p.medic_note)
			_t0 = frame
			_wait = 5
		20:
			if medic.state != Npc.State.TREAT and frame - _t0 < 900:
				return false
			var d := medic.global_position - p.global_position
			_look(atan2(-d.x, -d.z), -0.35)
			_wait = 90
		21:
			_shot("m13_medic_on_player")
			_t0 = frame
		22:
			if p.wants_medic and frame - _t0 < 600:
				return false
			print("healed by medic: hits %d, bleed %.1f" % [p.hits, p.bleed_rate])
			p.weapon.select(0)
			Npc.ai_enabled = false
			hurt.queue_free()
			medic.queue_free()
			_look(PI / 2)
			_wait = 20
		23:
			p.die()
			_t0 = frame
		24:
			# the death, as on the video
			var t := (frame - _t0) / 60.0
			var marks := [0.25, 0.7, 1.2, 1.9, 2.6, 3.4, 4.3, 5.4]
			for k in marks.size():
				if frame - _t0 == int(round(marks[k] * 60.0)):
					_shot("m2%d_death_%.1f" % [k, marks[k]])
			if t < 6.0:
				return false
			print("death done: dead=%s" % p.dead)
			_wait = 150
		25:
			print("respawned: dead=%s gun dropped=%s bandages %d" % [p.dead, p.weapon.dropped, p.bandages])
			game.toggle_weapon_menu()
			_wait = 3
		26:
			_shot("m30_menu_guns")
			game._show_weapon_tab(game._weapon_tabs[2][1])
			_wait = 3
		27:
			_shot("m31_menu_mods")
			game.toggle_weapon_menu()
			print("medic test done")
			quit()
	_step += 1
	return false
