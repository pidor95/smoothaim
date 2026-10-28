// Blood splats/pools drawn as one MultiMesh (INSTANCE_CUSTOM = cell, born, tint, grow).
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, specular_schlick_ggx;
#include "res://assets/shaders/blood_decal.gdshaderinc"

varying vec4 custom;

void vertex() {
	custom = INSTANCE_CUSTOM;
}

void fragment() {
	vec3 albedo;
	float rough;
	vec3 nmap;
	float alpha;
	if (!blood_surface(UV, custom, albedo, rough, nmap, alpha)) {
		discard;
	}
	ALBEDO = albedo;
	ROUGHNESS = rough;
	SPECULAR = 0.35;
	NORMAL_MAP = nmap;
	ALPHA = alpha;
}
