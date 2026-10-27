// Ground: real satellite image for colour at a distance, CC0 photo textures for detail up close.
// Detail textures are divided by their own average colour (their smallest mip), so they add grain
// without changing the satellite colours. Roads and tracks from OpenStreetMap use their own textures.
shader_type spatial;
render_mode diffuse_lambert, specular_disabled;

uniform sampler2D sat : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D splat : filter_linear_mipmap, repeat_disable;
uniform sampler2D grass_c : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_c : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D road_c : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D road_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D gravel_c : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float map_size = 10400.0;
uniform float detail_dist = 1400.0;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

// luminance-only detail: keeps the satellite hue, adds the texture's light and shade
float detail(sampler2D t, vec2 uv) {
	float c = dot(texture(t, uv).rgb, vec3(0.3, 0.59, 0.11));
	float avg = dot(textureLod(t, vec2(0.5), 12.0).rgb, vec3(0.3, 0.59, 0.11));
	return c / max(avg, 0.04);
}

void fragment() {
	// mirrored outside the map, so the land continues seamlessly past the playable square
	vec2 muv = 1.0 - abs(mod(wpos.xz / map_size + 0.5, 2.0) - 1.0);
	vec3 macro = texture(sat, muv).rgb;
	vec4 sp = texture(splat, muv);
	// under the forest the image shows the canopy: lighten it to a leaf-litter floor
	float forest = smoothstep(0.3, 0.7, sp.b);
	vec3 floor_c = mix(vec3(dot(macro, vec3(0.3, 0.59, 0.11))), macro, 0.55) * 1.3 + vec3(0.04, 0.03, 0.0);
	macro = mix(macro, floor_c, forest * 0.8);
	float dist = length(wpos - CAMERA_POSITION_WORLD);
	float near = 1.0 - smoothstep(detail_dist * 0.25, detail_dist, dist);
	vec2 uv = wpos.xz / 3.5;
	vec2 uv2 = wpos.xz / 23.0;
	// greener, brighter pixels are vegetation, browner ones bare soil
	float veg = clamp((macro.g - macro.r) * 8.0 + 0.4, 0.0, 1.0);
	float g = detail(grass_c, uv) * (0.88 + 0.24 * detail(grass_c, uv2));
	float d = detail(dirt_c, uv * 0.8);
	float grain = mix(d, g, veg);
	vec3 col = macro * mix(1.0, grain, near * 0.85);
	// sun-bleached, slightly less saturated grass than the raw image
	col = mix(vec3(dot(col, vec3(0.3, 0.59, 0.11))), col, 0.72) * vec3(1.1, 1.05, 0.9);
	// paved roads (OSM asphalt) and dirt tracks
	float asph = smoothstep(0.25, 0.7, sp.r);
	float track = smoothstep(0.25, 0.7, sp.g);
	vec3 rc = texture(road_c, uv * 0.6).rgb * 0.9;
	vec3 tc = texture(gravel_c, uv).rgb * vec3(0.78, 0.72, 0.6);
	col = mix(col, mix(macro * 0.6 + 0.12, rc, near), asph * 0.9);
	col = mix(col, mix(macro * 0.8 + vec3(0.06, 0.05, 0.03), tc * (macro * 1.8 + 0.25), near), track * 0.75);
	ALBEDO = col;
	vec3 n = mix(texture(dirt_n, uv * 0.8).rgb, texture(grass_n, uv).rgb, veg);
	n = mix(n, texture(road_n, uv * 0.6).rgb, asph);
	NORMAL_MAP = mix(vec3(0.5, 0.5, 1.0), n, near);
	NORMAL_MAP_DEPTH = 1.2;
	ROUGHNESS = 1.0;
}
