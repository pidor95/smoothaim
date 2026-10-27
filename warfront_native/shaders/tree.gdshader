// Tree billboards: two crossed quads per tree, textures baked in Blender from 3D Sapling trees.
// INSTANCE_CUSTOM.r = species row in the atlas, .g = brightness variation, .b = wind phase.
shader_type spatial;
render_mode cull_disabled, diffuse_lambert, specular_disabled;

uniform sampler2D atlas : source_color, filter_linear_mipmap, repeat_disable;
uniform float rows = 5.0;
uniform float time_scale = 1.0;

varying float shade;
varying float facing;

void vertex() {
	float row = INSTANCE_CUSTOM.r;
	UV.y = (UV.y + row) / rows;
	float h = max(VERTEX.y, 0.0);
	// gentle wind sway that grows with height
	float ph = INSTANCE_CUSTOM.b * 6.283;
	VERTEX.x += sin(TIME * 1.3 + ph) * 0.012 * h * h * 0.05;
	VERTEX.z += cos(TIME * 1.1 + ph) * 0.010 * h * h * 0.05;
	shade = INSTANCE_CUSTOM.g;
	// how squarely this quad faces the camera; edge-on quads fade out instead of showing as stripes
	vec3 qn = UV.x < 0.5 ? vec3(0.0, 0.0, 1.0) : vec3(1.0, 0.0, 0.0);
	vec3 wn = normalize((MODEL_MATRIX * vec4(qn, 0.0)).xyz);
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	facing = abs(dot(wn, normalize(CAMERA_POSITION_WORLD - wp)));
	// light the crown as a volume: normals point up and outwards instead of flat to the quad
	NORMAL = normalize(vec3(VERTEX.x, 0.6 + UV.y, VERTEX.z) + vec3(0.0, 0.8, 0.0));
}

void fragment() {
	vec4 c = texture(atlas, UV);
	if (c.a < mix(0.98, 0.45, smoothstep(0.12, 0.42, facing))) discard;
	// darker lower crown, per-tree colour variation
	float ao = mix(0.72, 1.0, smoothstep(0.0, 0.7, 1.0 - fract(UV.y * rows)));
	ALBEDO = c.rgb * shade * ao;
	// light passing through the leaves keeps shaded crowns from going black
	BACKLIGHT = c.rgb * 0.6;
	ROUGHNESS = 0.9;
	SPECULAR = 0.1;
}
