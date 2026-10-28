extends SceneTree
## Dev smoke test: loads the house, shoots mannequins and saves screenshots.
## Run: godot -s res://tools/smoke_test.gd   (env SHOTS=<dir> to save PNGs)

var frame := 0
var game: Node
var npc: Npc
var shots_dir := OS.get_environment("SHOTS")
var log_lines: Array[String] = []


func _initialize() -> void:
	change_scene_to_file("res://scenes/game.tscn")


func _shot(name: String) -> void:
	if shots_dir == "":
		return
	var img := root.get_texture().get_image()
	img.save_png(shots_dir.path_join(name + ".png"))
	print("shot ", name)


func _aim_at(target: Vector3) -> void:
	var p: Player = game.player
	var eye := p.camera.global_position
	var d := (target - eye).normalized()
	p.yaw = atan2(-d.x, -d.z)
	p.pitch = asin(clampf(d.y, -1, 1))
	p.rotation.y = p.yaw
	p.head.rotation = Vector3(p.pitch, 0, 0)


func _process(_delta: float) -> bool:
	frame += 1
	if frame == 5:
		game = current_scene
	if frame == 20:
		game.player.touch_mode = true # show touch HUD, avoid mouse-capture logic
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if game == null:
		return false
	var p: Player = game.player
	match frame:
		60:
			print("npcs: ", get_nodes_in_group("npcs").size())
			_shot("01_spawn")
		61:
			# step into the house through the front door
			p.global_position = Vector3(-4.0, 0.05, -4.5)
			p.yaw = 0.0
		70:
			_shot("02_living")
		80:
			for n in get_nodes_in_group("npcs"):
				n.queue_free()
		82:
			npc = game.spawn_npc(Vector3(-4.0, 0.05, -1.4))
			npc.rotation.y = 0.0
			npc.display_only = true
		100:
			_aim_at(npc.chest.global_position)
		101:
			p.weapon.set_aiming(true)
		125:
			_shot("03_ads")
			p.weapon.trigger()
			print("after body shot: health=", npc.health, " dead=", npc.dead)
		128:
			_shot("04_fire")
			_report_ragdoll()
		150:
			_aim_at(npc.head.global_position)
		152:
			p.weapon.trigger()
			print("after head shot: dead=", npc.dead)
		156:
			_shot("05_headshot")
		175:
			_shot("06_falling")
		260:
			_shot("07_ragdoll")
			_report_ragdoll()
		261:
			p.weapon.set_aiming(false)
			_aim_at(npc.chest.global_position)
		262:
			p.weapon.trigger()
		268:
			p.weapon.trigger()
		275:
			p.weapon.trigger()
		400:
			_shot("08_pool")
			_report_ragdoll()
			print("ammo ", p.weapon.ammo)
		401:
			p.global_position = Vector3(0.0, 0.05, -12)
			p.yaw = 0.0
			p.pitch = deg_to_rad(5)
			p.weapon.reload()
		420:
			_shot("09_outside")
		421:
			p.global_position = Vector3(4.5, 0.05, 0.2)
			p.yaw = 0.0
			p.pitch = deg_to_rad(-12)
		440:
			_shot("10_kitchen")
		441:
			for i in 3:
				game.spawn_npc(Vector3(4.5 + i * 0.6, 0.05, -1.0))
		450:
			p.global_position = Vector3(2.0, 3.35, 0.0)
			p.yaw = PI * 0.75
			p.pitch = deg_to_rad(-20)
		470:
			_shot("11_roof")
		700:
			var moved := 0
			for n in get_nodes_in_group("npcs"):
				if not n.dead:
					print("npc ", n.name, " state=", n.state, " pos=", n.global_position.snapped(Vector3.ONE * 0.1))
			print("fps=", Engine.get_frames_per_second())
			quit()
	return false


func _report_ragdoll() -> void:
	var pl: Player = game.player
	print("player pos=", pl.global_position.snapped(Vector3.ONE * 0.01), " cam=", pl.camera.global_position.snapped(Vector3.ONE * 0.01), " wall=", pl.weapon._wall_push, " aim=", pl.weapon.aim_t, " reloading=", pl.weapon.reloading)
	for c in game.get_children():
		if c is CPUParticles3D:
			print("particles at ", c.global_position.snapped(Vector3.ONE * 0.01), " amount=", c.amount, " color=", c.color)
	var t_thigh := npc.thigh_l.global_transform
	var t_shin := npc.shin_l.global_transform
	var rel := t_thigh.basis.inverse() * t_shin.basis
	var e := rel.get_euler()
	print("knee L rel euler(deg)=", Vector3(rad_to_deg(e.x), rad_to_deg(e.y), rad_to_deg(e.z)).snapped(Vector3.ONE))
	var t_u := npc.uarm_l.global_transform
	var t_f := npc.farm_l.global_transform
	var e2 := (t_u.basis.inverse() * t_f.basis).get_euler()
	print("elbow L rel euler(deg)=", Vector3(rad_to_deg(e2.x), rad_to_deg(e2.y), rad_to_deg(e2.z)).snapped(Vector3.ONE))
	print("chest pos=", npc.chest.global_position.snapped(Vector3.ONE * 0.01), " head pos=", npc.head.global_position.snapped(Vector3.ONE * 0.01))
	var d := npc.head.global_position.distance_to(npc.chest.global_position)
	print("head-chest dist=", snappedf(d, 0.01), " (rest 0.39)")
