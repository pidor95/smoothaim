extends SceneTree
## Dev test of the kit (war paused): the gun put away and taken back out,
## items left out of the kit (hotbar), the PBS-1 suppressor (no flash, a
## short alert radius) and the weapon menu's pages; a look along the
## longer western trench.
## Run: godot -s res://tools/kit_test.gd   (env SHOTS=<dir> for PNGs)

var frame := 0
var game: Node
var p: Player
var npc: Npc
var shots_dir := OS.get_environment("SHOTS")
var _step := 0
var _wait := 0
var _mark := {}
var S: Node # the Settings autoload (only reachable through the tree here)


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
		Player.immortal = true
		p.global_position = Vector3(-30, 0.3, 40.0)
		for k in S.loadout:
			S.loadout[k] = true
		S.suppressed.ak74 = false
		p.weapon.apply_mods()
	if _wait > 0:
		_wait -= 1
		return false
	var w := p.weapon
	match _step:
		0:
			# put the gun away and take it back out from the hotbar
			game.hud.use_slot(0)
			print("holster: holstered=%s gun visible=%s" % [w.holstered, w.current.root.visible])
			_wait = 20
		1:
			print("after holster: gun visible=%s, trigger blocked ammo=%d" % [w.current.root.visible, w.ammo])
			w._cooldown = 0.0
			w.trigger()
			print("fired while holstered: ammo=%d (30 = no shot)" % w.ammo)
			_shot("k00_holstered")
			game.hud.use_slot(0)
			_wait = 25
		2:
			print("drawn again: holstered=%s visible=%s" % [w.holstered, w.current.root.visible])
			# leave the SVD and the FPV out of the kit
			S.loadout.svd = false
			S.loadout.fpv = false
			w.apply_mods()
			print("hotbar slots with SVD and FPV left out: %s" % [game.hud._slots().map(func(i): return Hud.SLOT_IDS[i])])
			w.select(1)
			print("select SVD (left out): current=%s" % w.current.def.id)
			_shot("k01_hotbar_kit")
			S.loadout.svd = true
			S.loadout.fpv = true
			w.apply_mods()
			_wait = 5
		3:
			# the suppressor: no flash, a short alert radius
			S.suppressed.ak74 = true
			w.apply_mods()
			npc = game.spawn_npc(p.global_position + Vector3(12, 0, 0), 1)
			npc.rotation.y = PI
			p.yaw = PI / 2
			p.pitch = 0.0
			_wait = 30
		4:
			w._cooldown = 0.0
			w.trigger()
			print("suppressed shot: flash visible=%s light=%s suppressor visible=%s heard within %.1f m" % [w._flash_root.visible,
					w._flash_light.visible, w.current.suppressor.visible, w.current.def.alert * Weapon.SUPPRESSED_ALERT])
			_wait = 2
		5:
			_shot("k02_suppressed")
			w.set_aiming(true)
			_wait = 30
		6:
			_shot("k03_suppressed_ads")
			w.set_aiming(false)
			S.suppressed.ak74 = false
			w.apply_mods()
			w._cooldown = 0.0
			w.trigger()
			print("open shot: flash visible=%s heard within %.1f m" % [w._flash_root.visible, w.current.def.alert])
			npc.queue_free()
			_wait = 10
		7:
			# along the western stretch of the front trench
			var f: Array = game.house.team_posts[0].filter(func(q): return q.x < -200.0)
			print("western posts: %d" % f.size())
			if not f.is_empty():
				p.global_position = f[0]
				p.yaw = PI / 2
				p.pitch = 0.0
			_wait = 30
		8:
			_shot("k09_west_trench")
			game.toggle_weapon_menu()
			_wait = 3
		9:
			_shot("k10_menu_guns")
			game._show_weapon_tab(game._weapon_tabs[1][1])
			_wait = 3
		10:
			_shot("k11_menu_kit")
			game._show_weapon_tab(game._weapon_tabs[2][1])
			_wait = 3
		11:
			_shot("k12_menu_mods")
			game.toggle_weapon_menu()
			print("kit test done")
			quit()
	_step += 1
	return false
