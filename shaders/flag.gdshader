shader_type spatial;
render_mode cull_disabled;
// A banner or awning cloth rippling in the wind: the free end (UV.x = 1) moves most.
uniform vec4 color_a : source_color = vec4(0.6, 0.1, 0.08, 1.0);
uniform vec4 color_b : source_color = vec4(0.85, 0.7, 0.3, 1.0);
uniform float stripes = 0.0;
uniform float wave = 0.08;

void vertex() {
	float w = UV.x;
	VERTEX.z += sin(TIME * 3.0 + UV.x * 7.0 + NODE_POSITION_WORLD.x) * wave * w;
	VERTEX.y += sin(TIME * 2.3 + UV.x * 5.0) * wave * 0.3 * w;
}

void fragment() {
	float s = stripes > 0.0 ? step(0.5, fract(UV.y * stripes)) : 0.0;
	ALBEDO = mix(color_a.rgb, color_b.rgb, s);
	ROUGHNESS = 0.95;
	BACKLIGHT = vec3(0.3);
}
