shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
// A burning or poisoned patch of sand (scripts/game/throwables.gd), drawn on the sand's own
// 10 cm voxel grid: each cell flickers between two colours, the edge ragged cell by cell.

uniform vec4 color_a : source_color = vec4(1.0, 0.6, 0.15, 0.8);
uniform vec4 color_b : source_color = vec4(0.5, 0.08, 0.02, 0.6);
uniform float radius = 1.0;
uniform float glow = 2.0;
uniform float speed = 3.0;

varying vec3 world_pos;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 cell = floor(world_pos.xz / 0.1);
	vec2 centre = (cell + 0.5) * 0.1;
	vec2 o = NODE_POSITION_WORLD.xz;
	// Each pool its own splash: stretched one way, a lobed edge, droplets thrown round it.
	float zs = hash(floor(o * 10.0) + 0.5);
	float ang = zs * 6.2832;
	vec2 dv = centre - o;
	vec2 rd = vec2(dv.x * cos(ang) + dv.y * sin(ang), -dv.x * sin(ang) + dv.y * cos(ang));
	rd.x /= 1.0 + 0.45 * zs;
	rd.y /= 1.0 - 0.15 * zs;
	float a = atan(dv.y, dv.x);
	float blob = 0.8 + 0.16 * sin(a * 3.0 + zs * 17.0) + 0.09 * sin(a * 5.0 + zs * 41.0) + 0.05 * sin(a * 11.0 + zs * 7.0);
	float d = length(rd) / max(radius, 0.01);
	float rag = hash(cell + 3.7) * 0.18;
	float edge_k = 1.0;
	if (d > blob - rag) {
		float far = (d - blob) / (0.5 * blob);
		if (far > 1.0 || hash(cell + 7.1) > 0.16 * (1.0 - far)) {
			discard;
		}
		edge_k = 0.7;
	}
	d = d / max(blob, 0.1);
	float t = floor(TIME * speed + hash(cell) * 9.0);
	float n = hash(cell + t * 1.618);
	vec3 col = mix(color_b.rgb, color_a.rgb, n * n);
	ALBEDO = col;
	EMISSION = col * glow * (0.5 + n);
	ALPHA = mix(color_b.a, color_a.a, n) * clamp((1.0 - d) * 4.0, 0.3, 1.0) * edge_k;
}
