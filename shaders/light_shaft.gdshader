shader_type spatial;
// A shaft of sunlight through a gap in the velarium (Arena._build_light_shafts): a strip along
// the sun's way that turns about its own length to face the eye, so it reads as a beam from
// anywhere. Faint (light added to what is behind it), soft at its sides, coming in at the top
// and gone before it reaches the stands or the sand, and gone too when the eye is right in it.
// The quad is built along +y from 0 to 1 (UV.y), its width across (UV.x); the node's basis
// carries the beam's length (y) and width (x).
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, world_vertex_coords;

uniform vec3 color : source_color = vec3(1.0, 0.9, 0.7);
uniform float strength = 0.06;

varying float v_along;
varying float v_across;
varying float v_near;

void vertex() {
	vec3 axis = (MODEL_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz;
	float half_w = length((MODEL_MATRIX * vec4(1.0, 0.0, 0.0, 0.0)).xyz) * 0.5;
	vec3 base = (MODEL_MATRIX * vec4(0.0, UV.y, 0.0, 1.0)).xyz;
	vec3 to_eye = CAMERA_POSITION_WORLD - base;
	vec3 side = cross(normalize(axis), normalize(to_eye));
	side = length(side) > 1e-4 ? normalize(side) : vec3(1.0, 0.0, 0.0);
	VERTEX = base + side * (UV.x * 2.0 - 1.0) * half_w;
	v_along = UV.y;
	v_across = UV.x;
	v_near = length(to_eye);
}

void fragment() {
	float edge = smoothstep(0.0, 0.45, v_across) * smoothstep(1.0, 0.55, v_across);
	float along = smoothstep(0.0, 0.1, v_along) * (1.0 - smoothstep(0.4, 1.0, v_along));
	// The dust in it, catching the light unevenly.
	float dust = 0.8 + 0.2 * sin(TIME * 0.5 + v_along * 23.0 + v_across * 4.0) * sin(TIME * 0.31 + v_along * 9.0);
	float near = smoothstep(3.0, 9.0, v_near);
	ALBEDO = color;
	ALPHA = strength * edge * along * dust * near;
}
