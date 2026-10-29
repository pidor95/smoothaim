// Bullet / fragment wounds on a soldier's uniform (wound_atlas.png, from
// tools/blender/build_wound_atlas.py): curved patches in a MultiMesh per body
// part (scripts/blood.gd). INSTANCE_CUSTOM, all in 0..1 (the Compatibility
// renderer keeps it as 8 bits a channel): r = atlas cell / 4, b = rotation /
// TAU, a = size - 0.5.
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, specular_schlick_ggx;

uniform sampler2D atlas : source_color, filter_linear_mipmap, repeat_disable;

varying vec4 wound;

void vertex() {
	wound = INSTANCE_CUSTOM;
}

void fragment() {
	float cell = floor(wound.r * 4.0 + 0.5);
	float rot = wound.b * 6.2831853;
	vec2 c = (UV - 0.5) / (wound.a + 0.5);
	float s = sin(rot);
	float co = cos(rot);
	c = vec2(c.x * co - c.y * s, c.x * s + c.y * co);
	if (length(c) > 0.5) {
		discard;
	}
	vec2 uv = (c + 0.5 + vec2(mod(cell, 2.0), floor(cell / 2.0))) * 0.5;
	vec4 t = texture(atlas, uv);
	if (t.a < 0.02) {
		discard;
	}
	float wet = clamp((t.r - t.g) * 3.0, 0.0, 1.0); // blood and flesh shine, cloth does not
	ALBEDO = t.rgb;
	ROUGHNESS = mix(0.92, 0.28, wet);
	SPECULAR = mix(0.2, 0.45, wet);
	ALPHA = t.a;
}
