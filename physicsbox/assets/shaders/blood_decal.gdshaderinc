// Shared blood decal look: atlas shape (Blender render), thickness from the
// blurred alpha (thick = darker, glossy, raised edge), drying over time and
// growing pools. Included by the MultiMesh and the per-node variants.
uniform sampler2D atlas : hint_default_transparent, filter_linear_mipmap, repeat_disable;
uniform float now = 0.0;
uniform vec3 fresh_color : source_color = vec3(0.52, 0.02, 0.025);
uniform vec3 dry_color : source_color = vec3(0.24, 0.025, 0.018);
uniform float dry_time = 90.0;

// d = (cell, born, tint, grow seconds)
bool blood_surface(vec2 uv, vec4 d, out vec3 albedo, out float rough, out vec3 nmap, out float alpha) {
	float age = max(now - d.y, 0.0);
	if (d.w > 0.0) {
		float g = clamp(age / d.w, 0.12, 1.0);
		g = 1.0 - (1.0 - g) * (1.0 - g); // ease out like a spreading pool
		uv = (uv - 0.5) / g + 0.5;
		if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) {
			return false;
		}
	}
	float c = floor(d.x + 0.5);
	vec2 auv = (vec2(mod(c, 4.0), floor(c / 4.0)) + clamp(uv, 0.004, 0.996)) / vec2(4.0, 2.0);
	float a = texture(atlas, auv).a;
	float thick = textureLod(atlas, auv, 3.0).a;
	float e = 2.0 / 1024.0;
	float tx = textureLod(atlas, auv + vec2(e, 0.0), 2.0).a - textureLod(atlas, auv - vec2(e, 0.0), 2.0).a;
	float ty = textureLod(atlas, auv + vec2(0.0, e), 2.0).a - textureLod(atlas, auv - vec2(0.0, e), 2.0).a;
	float dry = clamp(age / dry_time, 0.0, 1.0);
	albedo = mix(fresh_color, dry_color, dry * 0.8) * mix(1.15, 0.72, thick) * d.z;
	rough = mix(0.16, 0.55, dry) + (1.0 - thick) * 0.12;
	nmap = normalize(vec3(-tx * 3.0, ty * 3.0, 1.0)) * 0.5 + 0.5;
	alpha = smoothstep(0.3, 0.6, a) * mix(0.97, 0.9, dry);
	return alpha > 0.002;
}
