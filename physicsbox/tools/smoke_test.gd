extends SceneTree
## Dev smoke test: loads the house, exercises both weapons on mannequins
## (hit reactions, knockdown + get-up, shotgun guts) and saves screenshots.
## Run: godot -s res://tools/smoke_test.gd   (env SHOTS=<dir> to save PNGs)

var frame := 0
var game: Node
var npc: Npc
var shots_dir := OS.get_environment("SHOTS")
var _wait := 0
var _step := 0
var _knocked_seen := false


func _initialize() -> void:
	root.get_node("Settings").level = "house"
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


func _spawn(pos: Vector3) -> Npc:
	var n: Npc = game.spawn_npc(pos)
	n.rotation.y = 0.0
	return n


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
		p.yaw = 0.0
	if _wait > 0:
		_wait -= 1
		return false
	match _step:
		0:
			npc = _spawn(Vector3(-4.0, 0.05, -1.4))
			_wait = 20
		1:
			_aim_at(npc.chest.global_position)
			_shot("01_pistol_idle")
			_fire()
			print("pistol chest hit: health=", npc.health, " balance=", snappedf(npc.balance, 0.01), " state=", npc.state, " (3=STAGGER)")
			_wait = 6
		2:
			_shot("02_reaction")
			_wait = 30
		3:
			p.weapon.set_aiming(true)
			_wait = 25
		4:
			_aim_at(npc.thigh_l.global_position)
			_shot("03_pistol_ads")
			_fire()
			_wait = 6
		5:
			_shot("04_leg_reaction")
			_wait = 3
		6:
			_aim_at(npc.thigh_r.global_position)
			_fire()
			print("after 3 hits: health=", npc.health, " balance=", snappedf(npc.balance, 0.01), " state=", npc.state)
			_wait = 20
		7:
			print("state (4=KNOCKED): ", npc.state, " dead=", npc.dead)
			_shot("05_knocked")
			_wait = 1
		8:
			if npc.dead:
				# an opened artery can bleed him out before he gets up
				print("died while down (arterial bleeding)")
				npc = _spawn(Vector3(-4.0, 0.05, -1.4))
				_step = 9
				_wait = 10
				return false
			if npc.state == Npc.State.KNOCKED:
				_knocked_seen = true
			if npc.state == Npc.State.GETUP:
				_shot("06_getting_up")
				_step += 1
			elif npc.state == Npc.State.IDLE and _knocked_seen:
				_step += 1
			_wait = 2
			return false
		9:
			_wait = 1
			if npc.state != Npc.State.IDLE:
				return false
			print("got back up: state=", npc.state, " pos=", npc.global_position.snapped(Vector3.ONE * 0.01), " health=", npc.health)
			_shot("07_standing_again")
			p.weapon.set_aiming(false)
			p.weapon.select(1)
			_wait = 30
		10:
			_shot("08_shotgun_idle")
			p.global_position = npc.global_position + Vector3(0, 0, -2.0)
			p.velocity = Vector3.ZERO
			_wait = 3
		11:
			_aim_at(npc.pelvis.global_position + Vector3.UP * 0.15)
			_fire()
			print("shotgun 2m: dead=", npc.dead, " guts=", npc._guts_spilled, " state=", npc.state)
			_wait = 4
		12:
			_shot("09_shotgun_blast")
			_wait = 14
		13:
			_shot("10_pump")
			_wait = 80
		14:
			_shot("11_guts")
			p.weapon.reload()
			_wait = 20
		15:
			_shot("12_shotgun_reload")
			_wait = 50
		16:
			p.weapon.set_aiming(true)
			_wait = 25
		17:
			_shot("13_shotgun_ads")
			print("ammo m500=", p.weapon.ammo, " fps=", Engine.get_frames_per_second())
			quit()
	_step += 1
	return false
