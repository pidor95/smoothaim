// Contrast-limited sharpening over the rendered 3D frame (clears the "soft" look of mobile MSAA and
// distant textures) plus a light vignette.
shader_type canvas_item;

uniform sampler2D screen : hint_screen_texture, filter_nearest;
uniform float amount = 0.45;
uniform float vignette = 0.18;

void fragment() {
	vec2 px = SCREEN_PIXEL_SIZE;
	vec3 c = texture(screen, SCREEN_UV).rgb;
	vec3 a = texture(screen, SCREEN_UV + vec2(px.x, 0.0)).rgb;
	vec3 b = texture(screen, SCREEN_UV - vec2(px.x, 0.0)).rgb;
	vec3 d = texture(screen, SCREEN_UV + vec2(0.0, px.y)).rgb;
	vec3 e = texture(screen, SCREEN_UV - vec2(0.0, px.y)).rgb;
	vec3 mn = min(c, min(min(a, b), min(d, e)));
	vec3 mx = max(c, max(max(a, b), max(d, e)));
	// less sharpening where the local contrast is already high (edges would ring)
	float k = amount * (1.0 - smoothstep(0.15, 0.6, max(mx.r, max(mx.g, mx.b)) - min(mn.r, min(mn.g, mn.b))));
	vec3 s = clamp(c + (4.0 * c - a - b - d - e) * k, mn, mx);
	vec2 v = SCREEN_UV - 0.5;
	s *= 1.0 - vignette * dot(v, v) * 2.0;
	COLOR = vec4(s, 1.0);
}
