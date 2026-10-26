shader_type spatial;
render_mode cull_disabled, specular_disabled;

// Grass clumps drawn with MultiMesh. UV.y runs from 0 at the root to 1 at the tip.
uniform vec3 root_color : source_color = vec3(0.20, 0.33, 0.09);
uniform vec3 tip_color : source_color = vec3(0.62, 0.66, 0.27);
uniform float wind_strength = 0.22;

varying float tip;

void vertex() {
	tip = UV.y;
	vec3 world = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float t = TIME;
	float gust = sin(t * 1.3 + world.x * 0.045 + world.z * 0.03) * 0.5 + 0.5;
	float sway = sin(t * 2.1 + world.x * 0.35 + world.z * 0.27) * (0.4 + gust);
	float bend = tip * tip * wind_strength;
	VERTEX.x += sway * bend;
	VERTEX.z += sway * bend * 0.6;
}

void fragment() {
	vec3 c = mix(root_color, tip_color, tip) * COLOR.rgb;
	ALBEDO = c;
	ROUGHNESS = 0.9;
	BACKLIGHT = vec3(0.35, 0.4, 0.15) * tip;
}
