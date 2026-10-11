shader_type spatial;
// Spectators in the stands (one MultiMesh): each bobs, jumps and throws its arms up as the
// fight gets exciting. UV2.x tags the box a vertex belongs to: 0 tunic, 1 head, 2 left arm,
// 3 right arm, 4 legs. INSTANCE_CUSTOM: skin colour (rgb) and a phase (a).
uniform float excitement : hint_range(0.0, 1.0) = 0.2;
varying vec3 col;

void vertex() {
	float tag = UV2.x;
	float ph = INSTANCE_CUSTOM.a;
	float t = TIME * (3.0 + ph * 2.5) + ph * 40.0;
	float keen = step(0.55 - excitement * 0.5, fract(ph * 7.31));
	float jump = max(0.0, sin(t)) * 0.13 * excitement * keen;
	vec3 lift = vec3(0.0, jump + sin(TIME * 0.7 + ph * 9.0) * 0.008, 0.0);
	if (tag > 1.5 && tag < 3.5) {
		float side = tag > 2.5 ? 1.0 : -1.0;
		float raise = clamp(excitement * 1.6 - 0.3 + 0.35 * sin(t * 1.3), 0.0, 1.0) * 2.7 * mix(0.25, 1.0, keen);
		vec3 sh = vec3(side * 0.16, 0.44, 0.0);
		vec3 p = VERTEX - sh;
		float a = raise * side;
		p = vec3(p.x * cos(a) - p.y * sin(a), p.x * sin(a) + p.y * cos(a), p.z);
		VERTEX = p + sh;
	}
	VERTEX += lift;
	if (tag > 0.5 && tag < 1.5) {
		col = INSTANCE_CUSTOM.rgb;
	} else if (tag > 3.5) {
		col = COLOR.rgb * 0.45;
	} else if (tag > 1.5) {
		col = mix(COLOR.rgb, INSTANCE_CUSTOM.rgb, 0.5);
	} else {
		col = COLOR.rgb;
	}
}

void fragment() {
	ALBEDO = col;
	ROUGHNESS = 0.9;
}
