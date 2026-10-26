shader_type spatial;

// Facades are drawn procedurally from world position: no textures needed.
// COLOR.rgb is the wall colour, COLOR.a = 1 marks a glass tower.
uniform vec3 window_light : source_color = vec3(1.0, 0.74, 0.42);
uniform float light_energy = 2.2;

varying vec3 world_pos;
varying vec3 world_normal;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 wall = COLOR.rgb;
	float glass = COLOR.a;
	if (abs(world_normal.y) > 0.5) {
		ALBEDO = wall * 0.5;
		ROUGHNESS = 0.95;
	} else {
		float u = abs(world_normal.x) > 0.5 ? world_pos.z : world_pos.x;
		vec2 cell = vec2(u / mix(3.4, 2.6, glass), world_pos.y / 3.6);
		vec2 f = fract(cell);
		vec2 id = floor(cell);
		float mx = mix(0.20, 0.05, glass);
		float my = mix(0.24, 0.10, glass);
		float win = step(mx, f.x) * step(f.x, 1.0 - mx) * step(my, f.y) * step(f.y, 1.0 - my);
		float rnd = hash(id + floor(world_pos.xz / 40.0) * 13.0 + world_normal.xz * 7.0);
		vec3 pane = mix(vec3(0.03, 0.05, 0.07), vec3(0.12, 0.19, 0.24), rnd);
		ALBEDO = mix(wall, pane, win);
		ROUGHNESS = mix(0.85, 0.08, win);
		METALLIC = win * 0.5;
		float lit = win * step(0.8, rnd);
		EMISSION = window_light * lit * light_energy;
	}
}
