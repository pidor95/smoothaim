extends SceneTree
## Dev test of the main menu's kit screen (В БОЙ): the cards, toggling one,
## the AK's sight. Run: godot -s res://tools/menu_test.gd  (env SHOTS=<dir>)

var frame := 0
var shots_dir := OS.get_environment("SHOTS")


func _initialize() -> void:
	change_scene_to_file("res://scenes/main_menu.tscn")


func _shot(shot_name: String) -> void:
	if shots_dir != "":
		root.get_texture().get_image().save_png(shots_dir.path_join(shot_name + ".png"))
		print("shot ", shot_name)


func _process(_delta: float) -> bool:
	frame += 1
	var menu := current_scene
	if menu == null or not menu.has_method("_show_loadout"):
		return false
	var S := root.get_node("Settings")
	match frame:
		20:
			_shot("u00_menu")
			for k in S.loadout:
				S.loadout[k] = true
			S.loadout.svd = false
			S.sight.ak74 = "collimator"
			menu._show_loadout()
		30:
			_shot("u01_loadout")
			print("kit screen visible=%s cards=%d" % [menu._loadout.visible, menu._loadout_refresh.size()])
			quit()
	return false
