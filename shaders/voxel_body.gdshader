shader_type spatial;
// The voxel boxes of bodies, armour and weapons (one MultiMesh each, a box per voxel). The
// instance colour is the voxel's (sRGB, wounds and blood included). INSTANCE_CUSTOM.r carries
// what the voxel is made of, as kind / 16: 0 skin, 1 cloth, 2 leather and hair, 3 iron and
// steel, 4 gold and bronze, 5 wood, 6 bone and stone, 7 gems and ice, 8 fur and hide (the
// default, beasts), 9 flesh (wet, under the skin), 10 scales, 11 chitin (a shell), 12 a
// glowing eye. A material can force one kind for all its boxes (armour plates).
//
// The look: each kind its own roughness and shine, a little grain voxel to voxel, and each box's
// edges a shade darker so the blocks read as blocks even in flat light.

uniform int force_kind = -1;
// For a lone box (not a MultiMesh): its colour, and its half size when it is not a cube.
uniform vec4 tint : source_color = vec4(1.0);
uniform vec3 box_half = vec3(0.0);
uniform float edge_dark : hint_range(0.0, 0.5) = 0.09;
uniform float edge_width : hint_range(0.01, 0.5) = 0.16;
uniform float rim_amount : hint_range(0.0, 1.0) = 0.2;

const float ROUGH[13] = float[](0.58, 0.97, 0.72, 0.34, 0.27, 0.8, 0.62, 0.1, 0.92, 0.3, 0.42, 0.22, 0.2);
const float METAL[13] = float[](0.0, 0.0, 0.0, 0.85, 0.95, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0);
const float SPEC[13] = float[](0.38, 0.16, 0.3, 0.5, 0.5, 0.28, 0.4, 0.75, 0.2, 0.6, 0.55, 0.7, 0.5);
const float GRAIN[13] = float[](0.035, 0.035, 0.06, 0.06, 0.04, 0.09, 0.05, 0.03, 0.08, 0.08, 0.06, 0.04, 0.0);

varying vec3 box_pos;
varying flat float kind_f;
varying flat float seed;
varying flat vec2 status;   // INSTANCE_CUSTOM.g: burning, .b: poisoned (0..1)

void vertex() {
	box_pos = VERTEX;
	kind_f = force_kind >= 0 ? float(force_kind) : (INSTANCE_CUSTOM.a > 0.5 ? floor(INSTANCE_CUSTOM.r * 16.0 + 0.5) : 8.0);
	seed = fract(sin(float(INSTANCE_ID) * 12.9898 + 4.1414) * 43758.5453);
	status = INSTANCE_CUSTOM.a > 0.5 ? INSTANCE_CUSTOM.gb : vec2(0.0);
}

vec3 to_linear(vec3 c) {
	return mix(pow((c + vec3(0.055)) * (1.0 / 1.055), vec3(2.4)), c * (1.0 / 12.92), lessThan(c, vec3(0.04045)));
}

void fragment() {
	int k = int(clamp(kind_f, 0.0, 12.0));
	vec3 c = to_linear(COLOR.rgb) * tint.rgb;
	c *= 1.0 + GRAIN[k] * (seed - 0.5) * 2.0;
	// Distance to the nearest edge of this face of the box, 0 at the edge, 1 in the middle.
	vec3 a = abs(box_pos);
	float m = max(a.x, max(a.y, a.z));
	vec3 q = box_half.x > 0.0 ? clamp(a / box_half, vec3(0.0), vec3(1.0)) : a / max(m, 1e-5);
	float second = q.x + q.y + q.z - 1.0 - min(q.x, min(q.y, q.z));
	float edge = 1.0 - smoothstep(1.0 - edge_width, 1.0, second);
	c *= mix(1.0 - edge_dark, 1.0, edge);
	ALBEDO = c;
	ROUGHNESS = clamp(ROUGH[k] + 0.08 * (seed - 0.5), 0.02, 1.0);
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
		// Burning: the voxel glows from within, flickering, white-yellow at its hottest.
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
