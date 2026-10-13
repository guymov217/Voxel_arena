shader_type spatial;
// Particles drawn as little voxels (shaders/../scripts/game/fx.gd): blood, sparks, embers, fire,
// poison, chips. The particle's colour (its colour ramp) is the albedo, and, for the ones that
// glow, the light too, so a flame cube burns from white through orange to red as it rises.

uniform float emit = 0.0;
uniform float roughness : hint_range(0.0, 1.0) = 0.6;

vec3 to_linear(vec3 c) {
	return mix(pow((c + vec3(0.055)) * (1.0 / 1.055), vec3(2.4)), c * (1.0 / 12.92), lessThan(c, vec3(0.04045)));
}

void fragment() {
	// The ramps are written as sRGB colours (as seen); light works in linear.
	vec3 c = to_linear(COLOR.rgb);
	ALBEDO = c;
	ROUGHNESS = roughness;
	if (emit > 0.0) {
		EMISSION = c * emit;
	}
}
