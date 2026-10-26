shader_type spatial;

// Road grid for the city: roads run along every `pitch` metres from `origin`.
uniform vec2 origin = vec2(20.0, -280.0);
uniform float pitch = 52.0;
uniform float road_half = 6.0;
uniform vec2 park_a = vec2(1.0, 3.0);
uniform vec2 park_b = vec2(3.0, 1.0);

varying vec3 world_pos;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_pos.xz - origin;
	vec2 m = mod(p + pitch * 0.5, pitch) - pitch * 0.5;
	vec2 a = abs(m);
	float grain = hash(floor(world_pos.xz * 3.0)) * 0.05;

	vec3 asphalt = vec3(0.040, 0.042, 0.047) + grain * 0.3;
	vec3 sidewalk = vec3(0.22, 0.21, 0.19) + grain;
	vec3 plaza = vec3(0.15, 0.145, 0.135) + grain;
	vec3 park = vec3(0.06, 0.13, 0.03) + grain * 0.4;

	vec2 block = floor(p / pitch);
	bool is_park = all(equal(block, park_a)) || all(equal(block, park_b));

	float road_x = step(a.x, road_half);
	float road_z = step(a.y, road_half);
	float on_road = max(road_x, road_z);
	float on_walk = max(step(a.x, road_half + 3.0), step(a.y, road_half + 3.0)) * (1.0 - on_road);

	vec3 col = is_park ? park : plaza;
	col = mix(col, sidewalk, on_walk);
	col = mix(col, asphalt, on_road);

	float dash_x = road_x * (1.0 - road_z) * step(a.x, 0.12) * step(0.5, fract(p.y / 6.0));
	float dash_z = road_z * (1.0 - road_x) * step(a.y, 0.12) * step(0.5, fract(p.x / 6.0));
	float cross_x = road_x * step(road_half + 0.6, a.y) * step(a.y, road_half + 3.2) * step(0.5, fract(m.x * 0.9));
	float cross_z = road_z * step(road_half + 0.6, a.x) * step(a.x, road_half + 3.2) * step(0.5, fract(m.y * 0.9));
	float paint = max(max(dash_x, dash_z), max(cross_x, cross_z));
	col = mix(col, vec3(0.70, 0.67, 0.58), paint);

	ALBEDO = col;
	ROUGHNESS = mix(0.95, 0.75, on_road);
}
