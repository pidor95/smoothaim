class_name GlassPane
extends StaticBody3D
## Window pane that shatters into physics shards when shot.

static var _mat: StandardMaterial3D
static var _shard_mat: StandardMaterial3D

var size := Vector3(1, 1, 0.02)


static func materials() -> void:
	if _mat:
		return
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = Color(0.72, 0.86, 0.92, 0.22)
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.roughness = 0.05
	_mat.metallic_specular = 1.0
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_shard_mat = _mat.duplicate()
	_shard_mat.albedo_color = Color(0.72, 0.86, 0.92, 0.45)


func _ready() -> void:
	materials()
	set_meta("surface", "glass")
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	add_child(cs)


func shatter(hit_pos: Vector3, dir: Vector3) -> void:
	Sfx.play_3d("glass_break", hit_pos, 0.0, 0.1)
	var root := get_tree().current_scene
	var cols := 4
	var rows := 3
	var w := size.x / cols
	var h := size.y / rows
	for cx in cols:
		for cy in rows:
			var shard := RigidBody3D.new()
			shard.mass = 0.3
			shard.collision_layer = 32
			shard.collision_mask = 1 | 2
			var sw := w * randf_range(0.6, 1.0)
			var shh := h * randf_range(0.6, 1.0)
			var mi := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(sw, shh, 0.012)
			mi.mesh = bm
			mi.material_override = _shard_mat
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			shard.add_child(mi)
			var cs := CollisionShape3D.new()
			var sh := BoxShape3D.new()
			sh.size = Vector3(sw, shh, 0.012)
			cs.shape = sh
			shard.add_child(cs)
			root.add_child(shard)
			var local := Vector3(-size.x / 2 + w * (cx + 0.5), -size.y / 2 + h * (cy + 0.5), 0)
			shard.global_transform = global_transform * Transform3D(Basis(Vector3(0, 0, 1), randf_range(-0.6, 0.6)), local)
			var near := 1.0 - clampf(shard.global_position.distance_to(hit_pos) / 1.2, 0.0, 1.0)
			shard.linear_velocity = dir * (0.6 + near * 4.0) + Vector3(randf_range(-0.5, 0.5), randf_range(0, 0.8), randf_range(-0.5, 0.5))
			shard.angular_velocity = Vector3(randf_range(-8, 8), randf_range(-8, 8), randf_range(-8, 8))
			get_tree().create_timer(randf_range(8.0, 12.0), false).timeout.connect(shard.queue_free)
	queue_free()
