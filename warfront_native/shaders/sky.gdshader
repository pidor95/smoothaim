// HDR photo sky, toned down: the raw panorama is a deep polarised blue at the zenith, real summer
// steppe skies are paler and milky towards the horizon.
shader_type sky;

uniform sampler2D pano : source_color, filter_linear, repeat_enable;
uniform float energy = 1.0;
uniform float saturation = 0.62;
uniform vec3 haze = vec3(0.78, 0.84, 0.9);

void sky() {
	vec3 d = EYEDIR;
	vec2 uv = vec2(atan(d.x, -d.z) / (2.0 * PI) + 0.5, acos(clamp(d.y, -1.0, 1.0)) / PI);
	vec3 c = texture(pano, uv).rgb;
	float l = dot(c, vec3(0.3, 0.59, 0.11));
	c = mix(vec3(l), c, saturation);
	// milky band near the horizon, ground below it fades to haze colour
	float h = 1.0 - smoothstep(0.0, 0.35, d.y);
	c = mix(c, haze * max(l, 0.9), h * 0.55);
	if (d.y < 0.0) c = haze * 0.9;
	COLOR = c * energy;
}
