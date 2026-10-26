shader_type canvas_item;

// Analog video static shown when the drone crashes.
uniform float amount : hint_range(0.0, 1.0) = 1.0;

float rnd(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 px = floor(FRAGCOORD.xy / 3.0);
	float n = rnd(px + vec2(floor(TIME * 60.0) * 1.37, floor(TIME * 60.0) * 0.71));
	float lines = 0.8 + 0.2 * sin(FRAGCOORD.y * 0.8 + TIME * 50.0);
	float roll = smoothstep(0.0, 0.05, abs(fract(UV.y - TIME * 0.7) - 0.5));
	COLOR = vec4(vec3(n * lines * (0.6 + 0.4 * roll)), amount * 0.94);
}
