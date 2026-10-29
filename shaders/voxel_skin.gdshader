shader_type spatial;
// The smooth skin over a gladiator's voxels (VoxelSkin): each quad in its voxel's colour (sRGB,
// wounds and blood included) and, in CUSTOM0, what the voxel is made of (kind / 16, the kinds
// of voxel_body.gdshader), whether it burns (.g) or is poisoned (.b) and its seed (.a). The same
// shine, glow and fire as the voxel boxes; no box edges or corner shading, it is one surface.

uniform float rim_amount : hint_range(0.0, 1.0) = 0.2;

const float ROUGH[13] = float[](0.58, 0.97, 0.72, 0.34, 0.38, 0.8, 0.62, 0.1, 0.92, 0.3, 0.42, 0.22, 0.2);
const float METAL[13] = float[](0.0, 0.0, 0.0, 0.85, 0.7, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0);
const float SPEC[13] = float[](0.38, 0.16, 0.3, 0.5, 0.5, 0.28, 0.4, 0.75, 0.2, 0.6, 0.55, 0.7, 0.5);

varying flat float kind_f;
varying flat float seed;
varying flat vec2 status;

void vertex() {
	kind_f = floor(CUSTOM0.r * 16.0 + 0.5);
	status = CUSTOM0.gb;
	seed = CUSTOM0.a;
}

vec3 to_linear(vec3 c) {
	return mix(pow((c + vec3(0.055)) * (1.0 / 1.055), vec3(2.4)), c * (1.0 / 12.92), lessThan(c, vec3(0.04045)));
}

void fragment() {
	int k = int(clamp(kind_f, 0.0, 12.0));
	vec3 c = to_linear(COLOR.rgb);
	ALBEDO = c;
	ROUGHNESS = ROUGH[k];
	METALLIC = METAL[k];
	SPECULAR = SPEC[k];
	if (k == 12) {
		EMISSION += c * (2.2 + 0.4 * sin(TIME * 2.0 + seed * 6.0));
	}
	if (k == 0) {
		// Skin: light through the thin edges, warm.
		BACKLIGHT = c * vec3(0.16, 0.07, 0.05);
	}
	if (status.x > 0.0) {
		// Burning: glows from within, flickering, white-yellow at its hottest.
		float f = 0.65 + 0.35 * sin(TIME * (9.0 + seed * 7.0) + seed * 40.0) + 0.15 * sin(TIME * 23.0 + seed * 11.0);
		vec3 fire = mix(vec3(1.0, 0.22, 0.03), vec3(1.0, 0.62, 0.18), seed);
		EMISSION += fire * status.x * f * 3.0;
	}
	if (status.y > 0.0) {
		// Poisoned: a slow sickly green pulse, wet.
		float p = 0.6 + 0.4 * sin(TIME * 3.0 + seed * 20.0);
		EMISSION += vec3(0.25, 0.85, 0.08) * status.y * p * 0.9;
		ROUGHNESS = mix(ROUGHNESS, 0.15, status.y);
	}
	RIM = rim_amount * (k == 3 || k == 4 ? 0.3 : 1.0);
	RIM_TINT = 0.6;
}
