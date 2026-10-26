shader_type spatial;
render_mode specular_schlick_ggx;

uniform vec3 deep_color : source_color = vec3(0.04, 0.14, 0.19);
uniform vec3 shallow_color : source_color = vec3(0.13, 0.30, 0.31);
uniform float radius = 80.0;

varying vec2 local_xz;
varying vec3 world_pos;

void vertex() {
	local_xz = VERTEX.xz;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float d = length(local_xz);
	if (d > radius) {
		discard;
	}
	float t = TIME;
	vec2 p = world_pos.xz;
	float dx = cos(p.x * 0.35 + t * 1.3) * 0.35 + cos((p.x + p.y) * 0.9 + t * 2.3) * 0.25;
	float dz = cos(p.y * 0.42 - t * 1.1) * 0.35 + cos((p.x - p.y) * 0.7 - t * 1.7) * 0.25;
	vec3 n = normalize(vec3(dx * 0.12, 1.0, dz * 0.12));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	ALBEDO = mix(shallow_color, deep_color, smoothstep(0.2, 0.9, d / radius));
	ROUGHNESS = 0.05;
	SPECULAR = 0.7;
}
