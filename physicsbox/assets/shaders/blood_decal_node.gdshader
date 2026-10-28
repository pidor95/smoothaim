// Blood marks glued to moving bodies (one MeshInstance each).
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, specular_schlick_ggx;
#include "res://assets/shaders/blood_decal.gdshaderinc"

instance uniform vec4 decal = vec4(0.0, 0.0, 1.0, 0.0);

void fragment() {
	vec3 albedo;
	float rough;
	vec3 nmap;
	float alpha;
	if (!blood_surface(UV, decal, albedo, rough, nmap, alpha)) {
		discard;
	}
	ALBEDO = albedo;
	ROUGHNESS = rough;
	SPECULAR = 0.35;
	NORMAL_MAP = nmap;
	ALPHA = alpha;
}
