shader_type spatial;
// Spectators in the stands (one MultiMesh): each bobs, jumps and throws its arms up as the
// fight gets exciting. UV2.x tags the box a vertex belongs to: 0 tunic, 1 head, 2 left arm,
// 3 right arm, 4 legs, 5 hair, 6 hat, 7 belt, 8 eyes, 9 sash. UV2.y is a baked shade (faces
// turned up lit, down in shadow, darker toward each box's foot). INSTANCE_CUSTOM: skin colour
// (rgb) and a phase (a), which also picks each one's hair, and who wears a hat or a sash.
uniform float excitement : hint_range(0.0, 1.0) = 0.2;
varying vec3 col;

float h1(float x) {
	return fract(sin(x * 91.3458) * 47453.5453);
}

void vertex() {
	float tag = UV2.x;
	float shade = UV2.y > 0.0 ? UV2.y : 1.0;
	float ph = INSTANCE_CUSTOM.a;
	float t = TIME * (3.0 + ph * 2.5) + ph * 40.0;
	float keen = step(0.55 - excitement * 0.5, fract(ph * 7.31));
	float jump = max(0.0, sin(t)) * 0.13 * excitement * keen;
	vec3 lift = vec3(0.0, jump + sin(TIME * 0.7 + ph * 9.0) * 0.008, 0.0);
	if (tag > 1.5 && tag < 3.5) {
		float side = tag > 2.5 ? 1.0 : -1.0;
		// Up to nearly straight over the head: thrown out wide, they reached into the next man's.
		float raise = clamp(excitement * 1.6 - 0.3 + 0.35 * sin(t * 1.3), 0.0, 1.0) * 2.95 * mix(0.25, 1.0, keen);
		vec3 sh = vec3(side * 0.16, 0.44, 0.0);
		vec3 p = VERTEX - sh;
		float a = raise * side;
		p = vec3(p.x * cos(a) - p.y * sin(a), p.x * sin(a) + p.y * cos(a), p.z);
		VERTEX = p + sh;
	}
	// Not everyone has a hat or a sash: the boxes of those who don't fold away to nothing.
	bool has_hat = h1(ph + 0.17) < 0.28;
	bool has_sash = h1(ph + 0.53) < 0.4;
	if ((tag > 5.5 && tag < 6.5 && !has_hat) || (tag > 8.5 && !has_sash)) {
		VERTEX = vec3(0.0, 0.3, 0.0);
	}
	VERTEX += lift;
	vec3 tunic = COLOR.rgb;
	if (tag > 0.5 && tag < 1.5) {
		col = INSTANCE_CUSTOM.rgb;
	} else if (tag > 3.5 && tag < 4.5) {
		col = tunic * 0.45;
	} else if (tag > 1.5 && tag < 3.5) {
		col = mix(tunic, INSTANCE_CUSTOM.rgb, 0.5);
	} else if (tag > 4.5 && tag < 5.5) {
		float k = h1(ph + 0.91);
		col = k < 0.35 ? vec3(0.05, 0.04, 0.035) : (k < 0.65 ? vec3(0.22, 0.12, 0.06) : (k < 0.8 ? vec3(0.42, 0.18, 0.08) : (k < 0.92 ? vec3(0.78, 0.62, 0.32) : vec3(0.6, 0.58, 0.55))));
	} else if (tag > 5.5 && tag < 6.5) {
		float k = h1(ph + 0.33);
		col = k < 0.5 ? vec3(0.82, 0.68, 0.36) : (k < 0.8 ? vec3(0.25, 0.45, 0.15) : vec3(0.55, 0.1, 0.08));
	} else if (tag > 6.5 && tag < 7.5) {
		col = vec3(0.2, 0.12, 0.06);
	} else if (tag > 7.5 && tag < 8.5) {
		col = vec3(0.04, 0.03, 0.03);
	} else if (tag > 8.5) {
		col = vec3(0.9, 0.86, 0.76);
	} else {
		col = tunic;
	}
	col *= shade;
}

void fragment() {
	ALBEDO = col;
	ROUGHNESS = 0.9;
}
