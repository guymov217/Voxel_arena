shader_type spatial;
render_mode cull_disabled, depth_draw_opaque, specular_disabled;
// A net's ropes (NetSim): one fine mesh, made once, each of whose vertices is put in its place here.
//   UV2: the square of the net it lies in (its place in the grid of knots); UV: where in the net,
//   in ropes between two knots (the square's place and where in it). The places of the knots are in
//   `grid` (a texel to a knot, RGBA floats, at the knot's place in the grid); the vertex is worked
//   out off the square's four knots and then put out of every box of the bodies about it (`boxes`,
//   four texels a box: its world-to-its-own columns with the origin in their w, then its half
//   extents), by the way of least depth as the net's own knots are: the net is a surface, drawn
//   smooth over a man, and nowhere in him (a square between four knots does not cut a corner).
// The ropes are cut out of it with the alpha scissor (a rope's shadow falls on the sand too):
// `density` ropes are drawn to each between two knots, and the vertex colour's red is the rim,
// whose rope is stouter.

uniform sampler2D grid : filter_nearest, repeat_disable;
uniform sampler2D boxes : filter_nearest, repeat_disable;
uniform int box_count = 0;
uniform vec4 rope : source_color = vec4(0.42, 0.29, 0.15, 1.0);
uniform float density = 3.0;
uniform float strand = 0.15;

// (Where the vertex is in the net before the bodies put it out of them: the threads between the net's own ropes, which hold the net's squares full, are not drawn where a body is.)
varying vec3 free_at;

vec3 knot(ivec2 g) {
	return texelFetch(grid, g, 0).xyz;
}

void vertex() {
	ivec2 g = ivec2(UV2 + vec2(0.5));
	vec2 ab = UV - UV2;
	vec3 p = mix(mix(knot(g), knot(g + ivec2(1, 0)), ab.x), mix(knot(g + ivec2(0, 1)), knot(g + ivec2(1, 1)), ab.x), ab.y);
	free_at = p;
	for (int b = 0; b < box_count; b++) {
		vec4 t0 = texelFetch(boxes, ivec2(0, b), 0);
		vec4 t1 = texelFetch(boxes, ivec2(1, b), 0);
		vec4 t2 = texelFetch(boxes, ivec2(2, b), 0);
		vec3 he = texelFetch(boxes, ivec2(3, b), 0).xyz;
		mat3 bm = mat3(t0.xyz, t1.xyz, t2.xyz);
		vec3 o = vec3(t0.w, t1.w, t2.w);
		vec3 l = bm * p + o;
		vec3 e = he - abs(l);
		if (e.x > 0.0 && e.y > 0.0 && e.z > 0.0) {
			if (e.x <= e.y && e.x <= e.z) {
				l.x = (l.x >= 0.0 ? 1.0 : -1.0) * he.x;
			} else if (e.y <= e.z) {
				l.y = (l.y >= 0.0 ? 1.0 : -1.0) * he.y;
			} else {
				l.z = (l.z >= 0.0 ? 1.0 : -1.0) * he.z;
			}
			p = transpose(bm) * (l - o);
		}
	}
	// (The node stands at the origin, turned no way: the model space is the world.)
	VERTEX = p;
}

void fragment() {
	vec2 u = UV * density;
	// The ropes the net is knitted of are drawn wherever they are (they are put out of the bodies); the threads between them only where no body is: a limb through a square of the net has
	// the net about it, not a thread through it.
	vec2 nu = floor(u + 0.5) / density;
	vec2 on_rope = abs(nu - floor(nu + 0.5));
	bool knitted = (abs(fract(u.x + 0.5) - 0.5) <= abs(fract(u.y + 0.5) - 0.5)) ? on_rope.x < 0.001 : on_rope.y < 0.001;
	if (!knitted) {
		for (int b = 0; b < box_count; b++) {
			vec4 t0 = texelFetch(boxes, ivec2(0, b), 0);
			vec4 t1 = texelFetch(boxes, ivec2(1, b), 0);
			vec4 t2 = texelFetch(boxes, ivec2(2, b), 0);
			vec3 he = texelFetch(boxes, ivec2(3, b), 0).xyz;
			vec3 l = mat3(t0.xyz, t1.xyz, t2.xyz) * free_at + vec3(t0.w, t1.w, t2.w);
			if (abs(l.x) < he.x && abs(l.y) < he.y && abs(l.z) < he.z) {
				discard;
			}
		}
	}
	vec2 fr = fract(u);
	vec2 dd = min(fr, 1.0 - fr);
	float line = min(dd.x, dd.y);
	float w = strand * (1.0 + 1.5 * COLOR.r);
	float aa = max(fwidth(line), 0.002);
	ALPHA = 1.0 - smoothstep(w - aa, w + aa, line);
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	// (twisted fibre: a faint banding along each rope; the rim a shade darker, tarred)
	float tw = 0.9 + 0.1 * sin((u.x + u.y) * 38.0);
	ALBEDO = rope.rgb * tw * (1.0 - 0.28 * COLOR.r);
	ROUGHNESS = 1.0;
	vec3 nn = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));
	NORMAL = dot(nn, VIEW) < 0.0 ? -nn : nn;
}
