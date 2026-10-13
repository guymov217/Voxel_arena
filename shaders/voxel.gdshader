shader_type spatial;
// The voxel art (art/voxel/*.glb, scripts/game/voxel_art.gd). The mesh carries each voxel's
// colour with the corner occlusion already baked in; this adds a little grain per voxel (found
// from the model-space position, so it stays put on moving doors) and the material's shading.
// Embers glow and flicker.

uniform float voxel_size = 0.1;
uniform float grain : hint_range(0.0, 0.5) = 0.07;
uniform float roughness : hint_range(0.0, 1.0) = 0.9;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;
uniform float specular : hint_range(0.0, 1.0) = 0.4;
uniform float emission = 0.0;
uniform float flicker = 0.0;

varying vec3 local_pos;
varying vec3 local_nrm;

float hash(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.x + p.y) * p.z);
}

void vertex() {
	local_pos = VERTEX;
	local_nrm = NORMAL;
}

void fragment() {
	vec3 cell = floor(local_pos / voxel_size - local_nrm * 0.5 + 0.0001);
	float n = hash(cell);
	float n2 = hash(cell + 17.0);
	vec3 c = COLOR.rgb * (1.0 + grain * (n - 0.5) * 2.0);
	ALBEDO = c;
	ROUGHNESS = clamp(roughness * (0.88 + 0.24 * n2), 0.0, 1.0);
	METALLIC = metallic;
	SPECULAR = specular;
	if (emission > 0.0) {
		float f = 1.0 + flicker * (0.22 * sin(TIME * 7.0 + n * 40.0) + 0.12 * sin(TIME * 17.0 + n2 * 25.0));
		EMISSION = c * emission * f;
	}
}
