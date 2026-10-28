extends SceneTree
## Dev test for gore: neck artery, double headshot (head explodes), heart
## shot, shotgun limb sever + organs. Run: godot -s res://tools/gore_test.gd
## (env SHOTS=<dir> to save PNGs)

var frame := 0
var game: Node
var shots_dir := OS.get_environment("SHOTS")
var _step := 0
var _wait := 0
var a: Npc
var b: Npc
var c: Npc


func _initialize() -> void:
	change_scene_to_file("res://scenes/game.tscn")


func _shot(n: String) -> void:
	if shots_dir != "":
		root.get_texture().get_image().save_png(shots_dir.path_join(n + ".png"))
		print("shot ", n)


func _aim(target: Vector3) -> void:
	var p: Player = game.player
	var d := (target - p.camera.global_position).normalized()
	p.yaw = atan2(-d.x, -d.z)
	p.pitch = asin(clampf(d.y, -1, 1))
	p.rotation.y = p.yaw
	p.head.rotation = Vector3(p.pitch, 0, 0)


func _fire() -> void:
	var cam: Camera3D = game.player.camera
	var q := PhysicsRayQueryParameters3D.create(cam.global_position, cam.global_position - cam.global_basis.z * 30.0, 7)
	var hit := cam.get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty() and hit.collider.has_meta("part"):
		print("  aim -> ", hit.collider.get_meta("part"), " local=", hit.collider.to_local(hit.position).snapped(Vector3.ONE * 0.01))
	game.player.weapon._cooldown = 0.0
	game.player.weapon.aiming = true
	game.player.weapon.aim_t = 1.0 # no spread: deterministic hits
	game.player.velocity = Vector3.ZERO
	game.player.weapon.reloading = false
	game.player.weapon.current.ammo = 6
	game.player.weapon.trigger()


func _process(_d: float) -> bool:
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
		p.global_position = Vector3(-4.0, 0.05, -4.6)
	if _wait > 0:
		_wait -= 1
		return false
	match _step:
		0:
			a = game.spawn_npc(Vector3(-5.2, 0.05, -2.0))
			b = game.spawn_npc(Vector3(-4.0, 0.05, -1.6))
			c = game.spawn_npc(Vector3(-2.8, 0.05, -2.0))
			for n in [a, b, c]:
				n.rotation.y = 0.0
			_wait = 20
		1:
			_aim(a.head.global_position + Vector3(0, -0.14, 0))
			_wait = 2
		2:
			_fire()
			print("neck: arteries=", a._arteries.size(), " health=", snappedf(a.health, 0.1), " dead=", a.dead)
			_wait = 10
		3:
			_shot("g1_neck_fountain")
			_aim(b.head.global_position)
			_wait = 2
		4:
			_aim(b.head.global_position)
			_fire()
			_wait = 2
		5:
			_aim(b.head.global_position)
			_wait = 1
		6:
			_fire()
			if not b.head_gone:
				_aim(b.head.global_position)
				_fire()
			print("double headshot: head_gone=", b.head_gone, " dead=", b.dead)
			_wait = 3
		7:
			_shot("g2_head_explode")
			_wait = 25
		8:
			_shot("g3_head_after")
			_aim(c.chest.global_position + c.chest.global_basis * Vector3(-0.04, 0.05, 0))
			_wait = 2
		9:
			_fire()
			print("heart: dead=", c.dead)
			_wait = 40
		10:
			print("neck victim after time: health=", snappedf(a.health, 0.1), " dead=", a.dead)
			_shot("g4_heart")
			var d: Npc = game.spawn_npc(Vector3(-4.0, 0.05, -2.6))
			d.rotation.y = 0.0
			c = d
			p.weapon.select(1, false)
			p.global_position = Vector3(-4.0, 0.05, -4.4)
			_wait = 15
		11:
			_aim(c.thigh_l.global_position)
			_wait = 2
		12:
			_fire()
			print("shotgun leg: severed=", c._severed.size(), " dead=", c.dead, " pieces=", Gore._live.size())
			_wait = 3
		13:
			_shot("g5_sever")
			_aim(c.chest.global_position)
			_wait = 2
		14:
			_fire()
			print("shotgun chest: organs=", c._guts_spilled, " pieces=", Gore._live.size())
			_wait = 30
		15:
			_shot("g6_organs")
			quit()
	_step += 1
	return false
