shader_type canvas_item;
// Bodycam look over the 3D view: a wide lens with barrel distortion,
// colour fringes towards the edges, a cold, flat, slightly washed-out
// grade, sensor grain, a dark vignette and a faint rolling band.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear, repeat_disable;
uniform float distortion = 0.32;
uniform float aberration = 0.006;
uniform float grain = 0.06;
uniform float vignette = 0.75;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 px = SCREEN_PIXEL_SIZE;
	float aspect = px.y / px.x;
	vec2 c = SCREEN_UV - 0.5;
	vec2 cc = c * vec2(aspect, 1.0);
	float r2 = dot(cc, cc);
	float corner = 0.25 * (aspect * aspect + 1.0);
	// barrel: sample further out the further from the centre, scaled so
	// the corners stay the corners
	float k = (1.0 + distortion * r2) / (1.0 + distortion * corner);
	vec2 uv = 0.5 + c * k;
	vec2 dir = c * aberration * (0.4 + r2 * 3.0);
	vec3 col;
	col.r = texture(screen_tex, uv + dir).r;
	col.g = texture(screen_tex, uv).g;
	col.b = texture(screen_tex, uv - dir).b;
	// grade: less saturation, lifted blacks, cool highlights
	float l = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(vec3(l), col, 0.72);
	col = col * vec3(0.96, 1.0, 1.04) * 0.93 + 0.035;
	col = mix(col, col * col * (3.0 - 2.0 * col), 0.35);
	// sensor grain and a slow rolling band
	float n = hash(floor(SCREEN_UV / px / 1.5) + fract(TIME * 13.0) * 97.0) - 0.5;
	col += n * grain;
	col *= 1.0 - 0.025 * smoothstep(0.0, 0.03, abs(fract(SCREEN_UV.y * 0.7 - TIME * 0.11) - 0.5) - 0.47);
	// vignette
	col *= 1.0 - vignette * smoothstep(0.25, 1.05, sqrt(r2 / corner) * 1.05);
	COLOR = vec4(col, 1.0);
}
