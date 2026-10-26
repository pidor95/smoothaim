shader_type spatial;
render_mode diffuse_burley;

// Terrain: vertex colour (sRGB) broken up by a tiling noise texture at three
// scales, plus patchwork fields around the village where COLOR.a = 1.
uniform sampler2D detail : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec2 village = vec2(0.0);

varying vec3 world_pos;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_pos.xz;
	float n1 = texture(detail, p * 0.0025).r;
	float n2 = texture(detail, p * 0.031).r;
	float n3 = texture(detail, p * 0.27).r;
	vec3 c = pow(COLOR.rgb, vec3(2.2));

	// Fields: rotated grid of plots, each with its own crop and furrows.
	float farm = COLOR.a;
	if (farm > 0.01) {
		vec2 q = p - village;
		float ang = 0.35;
		vec2 r = vec2(q.x * cos(ang) - q.y * sin(ang), q.x * sin(ang) + q.y * cos(ang));
		vec2 cell = floor(r / vec2(70.0, 44.0));
		float kind = hash(cell);
		vec3 crop = vec3(0.38, 0.30, 0.06); // ripe wheat
		if (kind < 0.3) {
			crop = vec3(0.16, 0.26, 0.04); // young crop
		} else if (kind < 0.5) {
			crop = vec3(0.17, 0.10, 0.05); // ploughed soil
		} else if (kind < 0.62) {
			crop = vec3(0.30, 0.25, 0.05); // sunflower yellow-green
		}
		float rows = 0.85 + 0.15 * sin(r.x * 2.6 + kind * 10.0);
		vec2 f = fract(r / vec2(70.0, 44.0));
		float hedge = 1.0 - step(0.02, f.x) * step(f.x, 0.98) * step(0.03, f.y) * step(f.y, 0.97);
		vec3 field = mix(crop * rows, vec3(0.05, 0.10, 0.03), hedge);
		c = mix(c, field, farm);
	}

	c *= 0.75 + 0.4 * n1;
	c *= 0.86 + 0.28 * n2;
	c *= 0.9 + 0.2 * n3;
	ALBEDO = c;
	ROUGHNESS = 0.95;
}
