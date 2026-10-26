shader_type sky;

// Golden-hour sky with a bright sun and soft clouds. The clouds do not move,
// so the sky's lighting is computed once instead of every frame.
uniform vec3 top_color : source_color = vec3(0.17, 0.33, 0.60);
uniform vec3 horizon_color : source_color = vec3(0.95, 0.72, 0.54);
uniform vec3 ground_color : source_color = vec3(0.32, 0.30, 0.28);
uniform float cloud_cover : hint_range(0.0, 1.0) = 0.45;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 4; i++) {
		v += noise(p) * amp;
		p = p * 2.03 + vec2(1.7, 9.2);
		amp *= 0.5;
	}
	return v;
}

void sky() {
	vec3 dir = EYEDIR;
	float h = dir.y;
	vec3 col = mix(horizon_color, top_color, pow(clamp(h, 0.0, 1.0), 0.5));
	col = mix(col, ground_color, 1.0 - smoothstep(-0.12, 0.0, h));

	float sun = 0.0;
	if (LIGHT0_ENABLED) {
		sun = max(dot(dir, LIGHT0_DIRECTION), 0.0);
		vec3 sun_color = LIGHT0_COLOR * LIGHT0_ENERGY;
		col += sun_color * (pow(sun, 8.0) * 0.35 + pow(sun, 60.0) * 0.5);
		col += sun_color * smoothstep(0.9993, 0.9997, sun) * 30.0;
	}

	if (h > 0.0) {
		vec2 uv = dir.xz / (h + 0.08) * 1.6;
		float n = fbm(uv + vec2(4.0, 2.0));
		float cover = smoothstep(1.0 - cloud_cover, 1.0 - cloud_cover + 0.3, n);
		float thick = smoothstep(0.4, 0.9, n);
		vec3 lit = mix(vec3(1.0, 0.92, 0.84), vec3(1.0, 0.8, 0.6), pow(sun, 4.0)) * (1.1 + 1.4 * pow(sun, 6.0));
		vec3 cloud = mix(lit, horizon_color * 0.75, thick * 0.6);
		col = mix(col, cloud, cover * smoothstep(0.0, 0.12, h) * 0.92);
	}
	COLOR = col;
}
