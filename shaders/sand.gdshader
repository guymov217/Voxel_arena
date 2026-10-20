shader_type spatial;
// The arena's sand, 10 cm voxels seen from above (Arena.sand_material): each voxel its own
// colour from the voxel texture and its own little height, the cracks between them shaded and
// bevelled; over that the life of the place: raked rings, trampled sand in the middle where the
// fights are, damp dark sand along the wall, drifts of paler dry sand.

uniform sampler2D voxels : source_color, filter_nearest_mipmap, repeat_enable;
uniform float tex_span = 32.0;          // metres the voxel texture covers
uniform float cell = 0.1;                // a voxel (m)
uniform float radius = 15.0;             // the arena's
uniform float tint = 0.74;               // a shade down: bright sand under a high sun glared
uniform float detail_fade = 30.0;        // the bevels fade out this far from the eye (m)

varying vec3 wpos;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

float fbm(vec2 p) {
	return vnoise(p) * 0.55 + vnoise(p * 2.1 + 7.3) * 0.3 + vnoise(p * 4.3 + 1.7) * 0.15;
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = wpos.xz;
	vec2 c = floor(p / cell);
	vec2 f = fract(p / cell);            // where in its voxel
	float h = hash(c);
	vec3 col = texture(voxels, (c + 0.5) * cell / tex_span + 0.5).rgb;
	float r = length(p);
	// Each voxel a touch lighter or darker, as grains lie.
	col *= 0.9 + 0.2 * h;
	// Drifts of paler dry sand and darker patches, a few metres across.
	float drift = fbm(p * 0.22);
	col *= mix(0.88, 1.1, smoothstep(0.3, 0.75, drift));
	// The middle trampled by the fights: darker, the grain churned.
	float trod = 1.0 - smoothstep(2.5, 8.0, r);
	col *= 1.0 - 0.1 * trod * (0.6 + 0.4 * vnoise(p * 1.7));
	// Raked rings away from the middle: grooves round the arena.
	float rake = 0.5 + 0.5 * sin(r * 10.5);
	float raked = smoothstep(6.0, 8.5, r) * (1.0 - smoothstep(radius - 1.2, radius - 0.4, r));
	col *= 1.0 - 0.08 * raked * rake;
	// Damp, darker sand along the foot of the wall, where the shade lies.
	float damp = smoothstep(radius - 1.6, radius - 0.1, r);
	col = mix(col, col * vec3(0.72, 0.68, 0.64), damp * 0.8);
	// Bevelled voxels: the crack between two voxels shaded, each a little higher or lower than
	// its neighbours, the slope along its edges caught by the light (faded with distance, where
	// it would only shimmer).
	float near = 1.0 - smoothstep(detail_fade * 0.5, detail_fade, length(wpos - CAMERA_POSITION_WORLD));
	// Each voxel a little higher or lower than its neighbours: an edge falls into shade where
	// the neighbour stands higher and catches the light where it is lower, so the sand reads as
	// grains of every height, not a laid floor of tiles.
	float hx0 = hash(c + vec2(-1.0, 0.0));
	float hx1 = hash(c + vec2(1.0, 0.0));
	float hz0 = hash(c + vec2(0.0, -1.0));
	float hz1 = hash(c + vec2(0.0, 1.0));
	float bw = 0.16;
	float wx0 = 1.0 - smoothstep(0.0, bw, f.x);
	float wx1 = 1.0 - smoothstep(0.0, bw, 1.0 - f.x);
	float wz0 = 1.0 - smoothstep(0.0, bw, f.y);
	float wz1 = 1.0 - smoothstep(0.0, bw, 1.0 - f.y);
	float step_x0 = hx0 - h;
	float step_x1 = hx1 - h;
	float step_z0 = hz0 - h;
	float step_z1 = hz1 - h;
	float edge = clamp(max(max(step_x0 * wx0, step_x1 * wx1), max(step_z0 * wz0, step_z1 * wz1)), 0.0, 1.0);
	col *= 1.0 - 0.22 * edge * near;
	vec2 slope = vec2(step_x1 * wx1 - step_x0 * wx0, step_z1 * wz1 - step_z0 * wz0) * 0.5 * near;
	// The rake's grooves tilt the surface too.
	float groove = cos(r * 10.5) * raked * 0.35 * near;
	vec2 radial = r > 0.01 ? p / r : vec2(0.0);
	slope += radial * groove;
	vec3 n_world = normalize(vec3(slope.x, 1.0, slope.y));
	NORMAL = normalize((VIEW_MATRIX * vec4(n_world, 0.0)).xyz);
	ALBEDO = col * tint;
	ROUGHNESS = 0.96 - 0.12 * damp;
	SPECULAR = 0.25;
	AO = 1.0 - 0.3 * edge * near;
	AO_LIGHT_AFFECT = 0.4;
}
