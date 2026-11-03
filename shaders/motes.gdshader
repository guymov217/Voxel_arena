shader_type spatial;
// Little specks of light drawn by the shader alone (Arena._specks): embers rising off a brazier's
// coals and fading as they climb, or dust turning slowly in a shaft of sun and catching the light
// now and then. One MultiMesh of quads; each instance's origin is where its speck lives, and its
// custom data (r, g) two numbers of its own, so no two move alike. Nothing is simulated: no
// particle system is made (one draws on the game's own dice when it is made).
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, world_vertex_coords;

uniform vec4 color : source_color = vec4(1.0, 0.5, 0.15, 1.0);
uniform float rise = 0.0;    // metres a speck climbs over its life (embers); 0: it only drifts (dust)
uniform float life = 3.0;    // seconds a speck lives before it starts again
uniform float sway = 0.08;   // metres it wanders to the sides
uniform float size = 0.025;  // its width in metres

varying float v_alpha;

void vertex() {
	float ph = INSTANCE_CUSTOM.r;
	float h2 = INSTANCE_CUSTOM.g;
	float t = fract(TIME / life + ph);
	vec3 base = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec3 off = vec3(sin(TIME * (0.6 + h2) + ph * 20.0), 0.0, cos(TIME * (0.45 + 0.7 * h2) + ph * 13.0)) * sway;
	float s = size;
	if (rise > 0.0) {
		// An ember: up on the heat, spreading a little, smaller as it cools.
		off.y = rise * t;
		off.xz += vec2(sin(ph * 37.0), cos(ph * 41.0)) * 0.1 * t;
		s *= 1.0 - 0.6 * t;
		v_alpha = smoothstep(0.0, 0.08, t) * (1.0 - smoothstep(0.45, 1.0, t));
	} else {
		// Dust: turning slowly where it is, catching the light now and then.
		off.y = sin(TIME * (0.25 + 0.3 * h2) + ph * 9.0) * sway;
		v_alpha = 0.35 + 0.65 * pow(0.5 + 0.5 * sin(TIME * (0.7 + h2) + ph * 31.0), 3.0);
	}
	vec2 corner = (UV - 0.5) * 2.0;
	VERTEX = base + off + (INV_VIEW_MATRIX[0].xyz * corner.x + INV_VIEW_MATRIX[1].xyz * corner.y) * s * 0.5;
}

void fragment() {
	float d = length(UV - 0.5) * 2.0;
	ALBEDO = color.rgb;
	ALPHA = (1.0 - smoothstep(0.35, 1.0, d)) * v_alpha * color.a;
}
