shader_type spatial;
// The arena's floor (Arena.sand_material): fine sand and packed earth, smooth and continuous.
// Each is a 2 mm-a-pixel map (tools/gen_textures.py floor) laid on in world space, twice at two
// sizes and angles and blended by a slow noise, so no tile repeats; the two meet by their
// heights (sand drifts into the earth's hollows first). Where each lies: earth trodden bare in
// the middle where the fights are and in patches about, raked rings of sand further out, damp
// dark sand along the foot of the wall, paler dry drifts.

uniform sampler2D sand_alb : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D sand_nrm : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D earth_alb : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D earth_nrm : filter_linear_mipmap_anisotropic, repeat_enable;
uniform float tile = 4.0;                // metres a map covers
uniform float radius = 15.0;             // the arena's
uniform float tint = 0.8;                // a shade down: bright sand under a high sun glared
uniform float bump = 1.0;
uniform float voxel = 0.05;              // the sand's grain as the game's voxels: its colour in cells
uniform float voxel_fade = 18.0;         // past this the cells blend back into smooth sand (m)

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

mat2 rot(float a) {
	return mat2(vec2(cos(a), sin(a)), vec2(-sin(a), cos(a)));
}

// One map sampled at a place in two ways (a size and an angle each), blended: its colour and
// height (rgb, a) and its slope in the world's x and z.
vec4 layer(sampler2D alb, sampler2D nrm, vec2 xz, vec2 cxz, float mixw, out vec2 slope) {
	mat2 r2 = rot(2.1);
	vec2 uv1 = xz / tile;
	vec2 uv2 = r2 * xz / (tile * 1.43) + vec2(0.37, 0.71);
	// The colour is read at `cxz` (a voxel's middle, near the eye), the slope where it is.
	vec2 c1 = cxz / tile;
	vec2 c2 = r2 * cxz / (tile * 1.43) + vec2(0.37, 0.71);
	// A voxel's colour is the sand round it, averaged (a lower mip): a single dark grain of the
	// map does not make a whole dark voxel. A little of the grain itself is kept over it.
	vec4 cv = mix(textureLod(alb, c1, 3.0), textureLod(alb, c2, 3.0), mixw);
	vec4 fine = mix(texture(alb, uv1), texture(alb, uv2), mixw);
	vec4 a = vec4(mix(cv.rgb, fine.rgb, 0.3), fine.a);
	vec3 n1 = texture(nrm, uv1).rgb * 2.0 - 1.0;
	vec3 n2 = texture(nrm, uv2).rgb * 2.0 - 1.0;
	// The map's slope (along u, along v) turned back into the world's x and z.
	vec2 g1 = vec2(n1.x, -n1.y) / max(0.2, n1.z);
	vec2 g2 = transpose(r2) * (vec2(n2.x, -n2.y) / max(0.2, n2.z));
	slope = mix(g1, g2, mixw);
	return a;
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = wpos.xz;
	float r = length(p);
	float mixw = smoothstep(0.3, 0.7, fbm(p * 0.16 + 3.1));
	vec2 gs;
	vec2 ge;
	// The game's voxels in the sand, as in its walls and bodies: each 5 cm cell one colour, a
	// touch lighter or darker than the next, but no seams or bevels between them (those read as
	// a floor of tiles). Far off they blend back into the smooth sand, where they would shimmer.
	vec2 cell = floor(p / voxel);
	float vk = 1.0 - smoothstep(voxel_fade * 0.6, voxel_fade, length(wpos - CAMERA_POSITION_WORLD));
	vec2 cp = mix(p, (cell + 0.5) * voxel, vk);
	vec4 s = layer(sand_alb, sand_nrm, p, cp, mixw, gs);
	vec4 e = layer(earth_alb, earth_nrm, p + vec2(11.3, -7.9), cp + vec2(11.3, -7.9), 1.0 - mixw, ge);
	float vj = mix(1.0, 0.965 + 0.07 * hash(cell), vk);
	s.rgb *= vj;
	e.rgb *= vj;
	// How bare the earth is: trodden to it in the middle, in patches about, never at the wall.
	float trod = 1.0 - smoothstep(1.5, 7.5, r + (fbm(p * 0.5 + 9.0) - 0.5) * 3.0);
	float patches = smoothstep(0.6, 0.85, fbm(p * 0.12 + 17.0));
	float bare = clamp(trod * (0.25 + 0.45 * fbm(p * 0.35)) + patches * 0.45, 0.0, 1.0);
	bare *= 1.0 - smoothstep(radius - 3.0, radius - 1.0, r);
	// Sand settles in the hollows of the earth first.
	float k = smoothstep(-0.25, 0.25, bare - 0.5 + (e.a - s.a) * 0.45) * 0.85;
	// Trodden earth here is the sand's own, packed: its colour only a little darker and browner.
	vec3 earth = mix(e.rgb, s.rgb * vec3(0.86, 0.8, 0.74), 0.45);
	vec3 col = mix(s.rgb, earth, k);
	vec2 slope = mix(gs, ge, k) * bump;
	// Drifts of paler dry sand and darker patches, metres across.
	float drift = fbm(p * 0.09 + 5.0);
	col *= mix(0.9, 1.08, smoothstep(0.25, 0.75, drift)) * mix(1.0, 0.94, k * fbm(p * 0.6));
	// Raked rings away from the middle: shallow grooves round the arena, on the sand only.
	float raked = smoothstep(6.5, 9.0, r) * (1.0 - smoothstep(radius - 1.6, radius - 0.6, r)) * (1.0 - k);
	float wave = sin(r * 10.5 + fbm(p * 0.8) * 1.5);
	col *= 1.0 - 0.05 * raked * (0.5 + 0.5 * wave);
	vec2 radial = r > 0.01 ? p / r : vec2(0.0);
	slope += radial * cos(r * 10.5 + fbm(p * 0.8) * 1.5) * raked * 0.22;
	// Damp, darker sand along the foot of the wall, where the shade lies.
	float damp = smoothstep(radius - 1.8, radius - 0.1, r) * (0.75 + 0.25 * fbm(p * 1.3));
	col = mix(col, col * vec3(0.7, 0.66, 0.62), damp * 0.8);
	// The fine detail fades with distance, where it would only shimmer.
	float near = 1.0 - smoothstep(25.0, 45.0, length(wpos - CAMERA_POSITION_WORLD));
	slope *= mix(0.35, 1.0, near);
	vec3 n_world = normalize(vec3(-slope.x, 1.0, -slope.y));
	NORMAL = normalize((VIEW_MATRIX * vec4(n_world, 0.0)).xyz);
	ALBEDO = col * tint;
	ROUGHNESS = mix(0.95, 0.88, k) - 0.12 * damp;
	SPECULAR = 0.3;
	// The hollows a touch darker (sand in the lee of a ripple, a crack in the earth).
	AO = mix(1.0, 0.75 + 0.25 * mix(s.a, e.a, k), 0.6);
	AO_LIGHT_AFFECT = 0.25;
}
