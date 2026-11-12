shader_type spatial;
// The voxel boxes of bodies, armour and weapons (one MultiMesh each, a box per voxel). The
// instance colour is the voxel's (sRGB, wounds and blood included). INSTANCE_CUSTOM.r carries
// what the voxel is made of, as kind / 16: 0 skin, 1 cloth, 2 leather and hair, 3 iron and
// steel, 4 gold and bronze, 5 wood, 6 bone and stone, 7 gems and ice, 8 fur and hide (the
// default, beasts), 9 flesh (wet, under the skin), 10 scales, 11 chitin (a shell), 12 a
// glowing eye, 13 forged iron (blackened and rough: a prosthetic's, which mirrored the blue sky as
// polished steel). A material can force one kind for all its boxes (armour plates).
//
// The look: each kind its own roughness and shine, a little grain voxel to voxel, and each box's
// edges a shade darker so the blocks read as blocks even in flat light. INSTANCE_CUSTOM.a over
// 1 carries the voxel's corner shading (VoxelPart.ao_bits): 4 bits a face (+x -x +y -y +z -z),
// a corner set when a neighbour shuts it in; the face darkens toward those corners, smoothly
// across it, so the creases of a body and the gaps between blocks lie in shadow.
//
// A weapon's sharp voxels (VoxelPart.taper_code, in r over the kind, in sixteens) are drawn
// tapered: an edge voxel pinched thin across the blade toward its open side, a wedge whose bevels
// meet in a bright honed line (half of a blade two thick, toward the face the halves share); a
// point voxel pinched to a tip. Where the edge turns a step of a blade cut round in steps, a
// corner of a voxel is pinched on its own, so the honed line runs on round it. Only the look: it
// hits as a cube.
//
// A gladiator's look (Physique) can bevel his body's outer edges: drawn with bevel_mode on, the
// code over the kind is the voxel's open faces (+x -x +y -y +z -z, bits 0..5), not a taper. Where two or three open
// faces meet, the box's corner there is drawn pulled in toward its middle, so the edges of the
// body read chamfered; nothing inside is uncovered, and it still hits as a cube.

uniform int force_kind = -1;
// For a lone box (not a MultiMesh): its colour, and its half size when it is not a cube.
uniform vec4 tint : source_color = vec4(1.0);
uniform vec3 box_half = vec3(0.0);
uniform float edge_dark : hint_range(0.0, 0.5) = 0.09;
uniform float edge_width : hint_range(0.01, 0.5) = 0.16;
uniform float rim_amount : hint_range(0.0, 1.0) = 0.2;
uniform float ao_strength : hint_range(0.0, 1.0) = 0.55;   // 0: corner shading off (Options)
uniform float edge_thin : hint_range(0.0, 1.0) = 0.1;    // a sharp edge's thickness, of the voxel's
uniform float point_thin : hint_range(0.0, 1.0) = 0.08;
uniform float body_bevel : hint_range(0.0, 1.0) = 0.85;   // how far a bevelled corner is pulled in
uniform float oil : hint_range(0.0, 1.0) = 0.0;          // skin oiled for the arena: glossier
uniform bool bevel_mode = false;
// The fine look's smooth light (FineSmooth): how far a face is lit by the way the body faces there
// (the instance colour's alpha, 2 and up: an octahedron's 32 by 32) and not by its own. The cube
// is where it was; only its light changes. 0: every cube lit as a cube. Its shadow is cast from
// smooth_inset of a voxel further in (a cube's faces turned from the sun lay in the cube's own
// shadow, and a skin lit as one surface showed them as dark streaks).
uniform float smooth_shade : hint_range(0.0, 1.0) = 0.0;
uniform float smooth_inset : hint_range(0.0, 3.0) = 1.0;
// The smooth skin (FineSmooth.skin): each cube's corners drawn moved onto the body's shape, by
// smooth_tex (eight texels a cube, a row of 256 cubes: the move in cubes, and the way the body
// faces at the corner). A corner is moved the same for every cube it is a corner of.
uniform sampler2D smooth_tex : filter_nearest, repeat_disable;
uniform float smooth_geo : hint_range(0.0, 1.0) = 0.0;
uniform float grain_k : hint_range(0.0, 4.0) = 1.0;      // the grain voxel to voxel, of each kind's own (the smooth skin's tiles: more)
uniform float patina : hint_range(0.0, 1.0) = 1.0;      // bronze gone green in its corners and spots (0: polished, the new look's armour)
uniform float iron_metal : hint_range(0.0, 1.0) = 1.0;   // how much a mirror iron is (the new look's armour: less, so its bands read in the sun)
uniform float scratches : hint_range(0.0, 1.0) = 1.0;    // iron's scratches and dents (the new look's armour: fainter, on its small voxels)
instance uniform float held_item = 0.0;   // a weapon (Weapon._build_mesh): its leather grip is stitched
instance uniform float sweat = 0.0;       // the sheen of sweat on the skin, 0..1 (Physique.live)
instance uniform float pallor = 0.0;      // the skin gone pale from blood lost, 0..1 (Physique.pale)
// A knee or an elbow under the smooth skin (Fighter._bend_drawing): the two parts that meet there
// are drawn as one skin bent round the joint, not as two stiff pieces turned on one another. All
// that is drawn with the part within bend_at.w of the joint along its length is turned about the
// joint (bend_at.xyz, world) toward the other part's turn from this one's (bend_turn: its axis,
// world, and the angle): not at all at that distance on the part's own side, half of it at the
// joint, all of it at that distance past it. Both parts do the same from their two sides, so they
// meet at every angle. bend_at.w under 0: the joint is at the part's low end; 0: no bend.
instance uniform vec4 bend_at = vec4(0.0);
instance uniform vec4 bend_turn = vec4(0.0);
// A man's foot level on the sand (Fighter._foot_drawing): the foot is drawn with his shin, and a
// shin that leans drove its toes into the sand and lifted its heel. All that is drawn with the
// shin under his ankle (foot_at.xyz, world; within foot_at.w of it along the shin the turn is
// spread) is turned about the ankle by foot_turn.xyz (a turn's axis, world, as long as its angle)
// and moved foot_turn.w up. foot_at.w 0: as it is.
instance uniform vec4 foot_at = vec4(0.0);
instance uniform vec4 foot_turn = vec4(0.0);

const float ROUGH[14] = float[](0.58, 0.97, 0.72, 0.34, 0.38, 0.8, 0.62, 0.1, 0.92, 0.3, 0.42, 0.22, 0.2, 0.86);
const float METAL[14] = float[](0.0, 0.0, 0.0, 0.85, 0.7, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.12);
const float SPEC[14] = float[](0.38, 0.16, 0.3, 0.5, 0.5, 0.28, 0.4, 0.75, 0.2, 0.6, 0.55, 0.7, 0.5, 0.2);
const float GRAIN[14] = float[](0.035, 0.035, 0.06, 0.06, 0.04, 0.09, 0.05, 0.03, 0.08, 0.08, 0.06, 0.04, 0.0, 0.08);

varying vec3 box_pos;
varying flat float kind_f;
varying flat float seed;
varying flat vec2 status;   // INSTANCE_CUSTOM.g: burning, .b: poisoned (0..1)
varying flat float ao_code; // the corner bits (an integer held exactly in a float)
varying flat float taper_code;
varying flat float spike_code; // a point's place on a run of points (bits 0..3) and the run's length (4..7)

void vertex() {
	box_pos = VERTEX;
	float way_code = COLOR.a;
	if (smooth_geo > 0.0 && COLOR.a > 1.5) {
		int ci = (VERTEX.x > 0.0 ? 1 : 0) + (VERTEX.y > 0.0 ? 2 : 0) + (VERTEX.z > 0.0 ? 4 : 0);
		vec4 cd = texelFetch(smooth_tex, ivec2((INSTANCE_ID % 256) * 8 + ci, INSTANCE_ID / 256), 0);
		VERTEX += cd.xyz * (abs(VERTEX.x) * 2.0 / 1.04) * smooth_geo;
		way_code = cd.a;
	}
	if (smooth_shade > 0.0 && way_code > 1.5) {
		float code = floor(way_code - 2.0 + 0.5);
		vec2 e = vec2(floor(code / 32.0), mod(code, 32.0)) / 31.0 * 2.0 - 1.0;
		vec3 way = vec3(e, 1.0 - abs(e.x) - abs(e.y));
		float under = clamp(-way.z, 0.0, 1.0);
		way.x += way.x >= 0.0 ? -under : under;
		way.y += way.y >= 0.0 ? -under : under;
		way = normalize(way);
		if (IN_SHADOW_PASS) {
			VERTEX -= way * abs(VERTEX.x) * 2.0 * smooth_inset * smooth_shade;
		}
		NORMAL = normalize(mix(NORMAL, way, smooth_shade));
	}
	float kc = INSTANCE_CUSTOM.a > 0.5 ? floor(INSTANCE_CUSTOM.r * 16.0 + 0.5) : 8.0;
	kind_f = force_kind >= 0 ? float(force_kind) : mod(kc, 16.0);
	taper_code = INSTANCE_CUSTOM.a > 0.5 ? floor(kc / 16.0) : 0.0;
	spike_code = INSTANCE_CUSTOM.a > 0.5 ? floor(fract(INSTANCE_CUSTOM.a) * 1024.0 + 0.5) : 0.0;
	if (bevel_mode) {
		int open = int(taper_code) & 63;
		// Which way the body is open along each axis (0: shut both ways, or a sliver open both).
		vec3 dir = vec3(0.0);
		for (int a = 0; a < 3; a++) {
			bool pos = ((open >> (2 * a)) & 1) == 1;
			bool neg = ((open >> (2 * a + 1)) & 1) == 1;
			dir[a] = pos == neg ? 0.0 : (pos ? 1.0 : -1.0);
		}
		vec3 at = vec3(0.0);
		float n = 0.0;
		for (int a = 0; a < 3; a++) {
			if (dir[a] != 0.0 && sign(VERTEX[a]) == dir[a]) {
				at[a] = 1.0;
				n += 1.0;
			}
		}
		float faces = abs(dir.x) + abs(dir.y) + abs(dir.z);
		if (n >= 2.0) {
			VERTEX *= vec3(1.0) - at * body_bevel;
		}
		int na = abs(NORMAL.x) > 0.5 ? 0 : (abs(NORMAL.y) > 0.5 ? 1 : 2);
		if (faces >= 2.0 && dir[na] != 0.0 && sign(NORMAL[na]) == dir[na]) {
			NORMAL = normalize(mix(NORMAL, normalize(dir), body_bevel));
		}
	} else if (taper_code > 0.5) {
		int t = int(taper_code);
		bool is_point = ((t >> 9) & 1) == 1;
		float thin = is_point ? point_thin : edge_thin;
		vec3 pinch = vec3(float((t >> 6) & 1), float((t >> 7) & 1), float((t >> 8) & 1));
		vec3 toward = vec3(0.0);   // the open sides it narrows to
		float sides = 0.0;
		bool open_side = false;
		for (int f = 0; f < 6; f++) {
			if (((t >> f) & 1) == 1) {
				vec3 d = vec3(0.0);
				d[f / 2] = (f % 2 == 0) ? 1.0 : -1.0;
				toward += d;
				sides += 1.0;
				open_side = open_side || dot(VERTEX, d) > 0.0;
			}
		}
		// Not a point: its corners across the blade thin on their own (bits 16..19, which on a
		// point hold its place on a spike), where the edge turns a step of a blade cut round in
		// steps; and narrowed both ways across the blade's width, all of it is thin, a flat plate.
		vec3 corner = vec3(0.0);
		if (!is_point) {
			int pa = pinch.x > 0.5 ? 0 : (pinch.y > 0.5 ? 1 : 2);
			int a1 = pa == 0 ? 1 : 0;
			int a2 = pa == 2 ? 1 : 2;
			int ci = (VERTEX[a1] > 0.0 ? 0 : 1) + (VERTEX[a2] > 0.0 ? 0 : 2);
			if (((int(spike_code) >> ci) & 1) == 1) {
				corner[a1] = sign(VERTEX[a1]);
				corner[a2] = sign(VERTEX[a2]);
				open_side = true;
			}
			if (((t >> (2 * a1)) & 3) == 3 || ((t >> (2 * a2)) & 3) == 3) {
				toward = vec3(0.0);
			}
		}
		// Half of a blade two thick narrows toward the face it shares with its other half.
		vec3 anchor = vec3(0.0);
		for (int a = 0; a < 3; a++) {
			anchor[a] = ((t >> (10 + 2 * a)) & 1) == 1 ? 1.0 : (((t >> (11 + 2 * a)) & 1) == 1 ? -1.0 : 0.0);
		}
		// A length of a spike (a run of points) narrows from its base's width to its tip's, so
		// the spike tapers unbroken from the first block to the last; a lone point from full
		// width to the tip.
		int si = is_point ? int(spike_code) & 15 : 0;
		int sn = is_point ? int(spike_code) >> 4 : 0;
		float s_base = sn > 1 ? mix(1.0, thin, float(si) / float(sn)) : 1.0;
		float s_tip = sn > 1 ? mix(1.0, thin, float(si + 1) / float(sn)) : thin;
		vec3 fixed_at = anchor * abs(VERTEX);
		VERTEX = mix(VERTEX, fixed_at + (VERTEX - fixed_at) * (open_side ? s_tip : s_base), pinch);
		// The faces across the pinch are bevels now: they lean toward the edge (at a corner,
		// pinched toward two sides, the face is mostly flat with a bevel at one end: less). The
		// shared face of a half stays flat; its outer face leans twice as steeply.
		int na = abs(NORMAL.x) > 0.5 ? 0 : (abs(NORMAL.y) > 0.5 ? 1 : 2);
		if (pinch[na] > 0.5) {
			float slope = anchor[na] == 0.0 ? 0.5 : (sign(NORMAL[na]) == anchor[na] ? 0.0 : 1.0);
			if (dot(toward, toward) > 0.5) {
				NORMAL = normalize(NORMAL + normalize(toward) * (s_base - s_tip) * slope / sides);
			}
			// A corner thin on its own: the face falls to it there.
			NORMAL = normalize(NORMAL + corner * (s_base - s_tip) * slope);
		}
	}
	seed = fract(sin(float(INSTANCE_ID) * 12.9898 + 4.1414) * 43758.5453);
	status = INSTANCE_CUSTOM.a > 0.5 ? INSTANCE_CUSTOM.gb : vec2(0.0);
	ao_code = INSTANCE_CUSTOM.a > 0.5 ? max(0.0, floor(INSTANCE_CUSTOM.a - 1.0 + 0.5)) : 0.0;
	if (bend_at.w != 0.0) {
		mat3 m3 = mat3(MODEL_MATRIX);
		vec3 rel = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz - bend_at.xyz;
		float t = clamp(dot(rel, normalize(m3[1])) / bend_at.w * 0.5 + 0.5, 0.0, 1.0);
		float w = t * t * (3.0 - 2.0 * t);
		if (w > 0.0) {
			float a = bend_turn.w * w;
			vec3 ax = bend_turn.xyz;
			float ca = cos(a);
			float sa = sin(a);
			vec3 d = rel * ca + cross(ax, rel) * sa + ax * dot(ax, rel) * (1.0 - ca) - rel;
			VERTEX += vec3(dot(m3[0], d) / dot(m3[0], m3[0]), dot(m3[1], d) / dot(m3[1], m3[1]), dot(m3[2], d) / dot(m3[2], m3[2]));
			vec3 nw = m3 * NORMAL;
			nw = nw * ca + cross(ax, nw) * sa + ax * dot(ax, nw) * (1.0 - ca);
			NORMAL = normalize(vec3(dot(m3[0], nw), dot(m3[1], nw), dot(m3[2], nw)));
		}
	}
	if (foot_at.w != 0.0) {
		mat3 m3 = mat3(MODEL_MATRIX);
		vec3 rel = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz - foot_at.xyz;
		float t = clamp(0.5 - dot(rel, normalize(m3[1])) / foot_at.w * 0.5, 0.0, 1.0);
		float w = t * t * (3.0 - 2.0 * t);
		if (w > 0.0) {
			vec3 d = vec3(0.0, foot_turn.w * w, 0.0);
			vec3 nw = m3 * NORMAL;
			float a = length(foot_turn.xyz);
			if (a > 0.00001) {
				vec3 ax = foot_turn.xyz / a;
				float ca = cos(a * w);
				float sa = sin(a * w);
				d += rel * ca + cross(ax, rel) * sa + ax * dot(ax, rel) * (1.0 - ca) - rel;
				nw = nw * ca + cross(ax, nw) * sa + ax * dot(ax, nw) * (1.0 - ca);
			}
			VERTEX += vec3(dot(m3[0], d) / dot(m3[0], m3[0]), dot(m3[1], d) / dot(m3[1], m3[1]), dot(m3[2], d) / dot(m3[2], m3[2]));
			NORMAL = normalize(vec3(dot(m3[0], nw), dot(m3[1], nw), dot(m3[2], nw)));
		}
	}
}

// How shut in this point of the face is (0 open, 1 in a corner), from the face's 4 corner bits.
float corner_shade(vec3 a, vec3 p, float m) {
	if (ao_code < 0.5 || ao_strength <= 0.0) {
		return 0.0;
	}
	int bits = int(ao_code);
	int face;
	vec2 uv;
	if (a.x >= a.y && a.x >= a.z) {
		face = p.x > 0.0 ? 0 : 1;
		uv = p.yz;
	} else if (a.y >= a.z) {
		face = p.y > 0.0 ? 2 : 3;
		uv = p.xz;
	} else {
		face = p.z > 0.0 ? 4 : 5;
		uv = p.xy;
	}
	int f4 = (bits >> (face * 4)) & 15;
	if (f4 == 0) {
		return 0.0;
	}
	vec2 t = clamp(uv / max(m, 1e-5) * 0.5 + 0.5, 0.0, 1.0);
	// Toward a shut corner the shade gathers, falling away across the face.
	t = t * t * (3.0 - 2.0 * t);
	float c00 = float(f4 & 1);
	float c10 = float((f4 >> 1) & 1);
	float c01 = float((f4 >> 2) & 1);
	float c11 = float((f4 >> 3) & 1);
	return mix(mix(c00, c10, t.x), mix(c01, c11, t.x), t.y);
}

vec3 to_linear(vec3 c) {
	return mix(pow((c + vec3(0.055)) * (1.0 / 1.055), vec3(2.4)), c * (1.0 / 12.92), lessThan(c, vec3(0.04045)));
}

void fragment() {
	int k = int(clamp(kind_f, 0.0, 13.0));
	vec3 c = to_linear(COLOR.rgb) * tint.rgb;
	c *= 1.0 + GRAIN[k] * grain_k * (seed - 0.5) * 2.0;
	// Distance to the nearest edge of this face of the box, 0 at the edge, 1 in the middle.
	vec3 a = abs(box_pos);
	float m = max(a.x, max(a.y, a.z));
	vec3 q = box_half.x > 0.0 ? clamp(a / box_half, vec3(0.0), vec3(1.0)) : a / max(m, 1e-5);
	float second = q.x + q.y + q.z - 1.0 - min(q.x, min(q.y, q.z));
	float edge = 1.0 - smoothstep(1.0 - edge_width, 1.0, second);
	c *= mix(1.0 - edge_dark, 1.0, edge);
	// What is worked into a voxel's faces (only its look): -1..1 across the face it is on.
	vec2 fuv = (a.x >= a.y && a.x >= a.z) ? box_pos.yz : ((a.y >= a.z) ? box_pos.xz : box_pos.xy);
	fuv /= max(m, 1e-5);
	float seed2 = fract(seed * 7.31 + 0.17);
	float fpx = length(fwidth(fuv)) * 1.5;   // a pixel, across the face: thin lines fade, not flicker
	if (k == 0) {
		// Skin: each voxel a touch warmer or cooler, as skin is.
		c *= vec3(1.0 + 0.05 * (seed2 - 0.5), 1.0, 1.0 - 0.05 * (seed2 - 0.5));
		// Pale from blood lost: the warmth drained out of the skin toward a waxen grey (only what
		// is the colour of skin: the blood on it stays red).
		if (pallor > 0.0) {
			float lum = dot(c, vec3(0.2126, 0.7152, 0.0722));
			float skinness = clamp((c.g / max(c.r, 1e-4) - 0.22) * 5.0, 0.0, 1.0);
			c = mix(c, vec3(lum) * vec3(1.0, 1.03, 1.08) * 1.12, pallor * 0.62 * skinness);
		}
	} else if (k == 1) {
		// Cloth: the weave.
		c *= 0.965 + 0.07 * (0.5 + 0.5 * sin(fuv.x * 28.0) * sin(fuv.y * 28.0));
	} else if (k == 3) {
		// Steel: a scratch catching the light on some voxels, each its own way across, and a dent
		// now and then.
		if (seed2 < 0.42) {
			vec2 dir = vec2(cos(seed * 6.2832), sin(seed * 6.2832));
			float across = abs(dot(fuv, vec2(-dir.y, dir.x)) - (seed2 - 0.21) * 3.0);
			float along = abs(dot(fuv, dir) - 0.3 * sin(seed * 17.0));
			float line = 1.0 - smoothstep(0.035, 0.035 + fpx, across);
			c *= 1.0 + 0.3 * scratches * line * (1.0 - smoothstep(0.4, 0.85, along));
		}
		if (seed2 > 0.9) {
			c *= 1.0 - 0.16 * scratches * (1.0 - smoothstep(0.15, 0.6, length(fuv - vec2(0.25, -0.15))));
		}
	} else if (k == 8) {
		// Fur: tufts a little lighter and darker.
		c *= 1.0 + 0.07 * (seed2 - 0.5);
	}
	// A weapon's grip wrapped in dark leather: the stitches along it (not a pale goose's feathers).
	if (k == 2 && held_item > 0.5 && dot(c, vec3(0.2126, 0.7152, 0.0722)) < 0.12) {
		float stitch = step(abs(fuv.x), 0.14) * step(0.5, fract(fuv.y * 2.0 + 0.25));
		c = mix(c, c * 1.7 + vec3(0.04), stitch * 0.65);
	}
	// Armour: a rivet at the corners of some of its plates.
	if (force_kind >= 0 && (k == 3 || k == 4) && seed2 > 0.72) {
		float rv = 1.0 - smoothstep(0.12, 0.2, length(abs(fuv) - vec2(0.62)));
		c = mix(c, c * 1.4 + vec3(0.03), rv);
	}
	float cs = box_half.x <= 0.0 ? corner_shade(a, box_pos, m) : 0.0;
	c *= 1.0 - ao_strength * cs;
	// Bronze (not gold: it is brighter) going green where it is shut in, and in spots.
	if (k == 4 && patina > 0.0 && dot(c, vec3(0.2126, 0.7152, 0.0722)) < 0.3) {
		c = mix(c, vec3(0.1, 0.24, 0.18), clamp(cs * 0.7 + (seed2 > 0.82 ? 0.3 : 0.0), 0.0, 0.7) * patina);
	}
	// A sharp voxel: the honed line where its bevels meet, bright, smoother on metal and gems.
	float hone = 0.0;
	// (A length of a spike short of its tip has no honed end: the spike runs on.)
	bool sharp_point = ((int(taper_code) >> 9) & 1) == 1;
	bool mid_spike = sharp_point && (int(spike_code) >> 4) > 1 && (int(spike_code) & 15) + 1 < (int(spike_code) >> 4);
	if (taper_code > 0.5 && !bevel_mode && !mid_spike) {
		int t = int(taper_code);
		for (int f = 0; f < 6; f++) {
			if (((t >> f) & 1) == 1) {
				float s = (f % 2 == 0) ? 1.0 : -1.0;
				hone = max(hone, smoothstep(0.72, 0.98, box_pos[f / 2] * s / max(m, 1e-5)));
			}
		}
		// A corner thin on its own (see vertex()): honed there, where the edges either side meet.
		if (!sharp_point) {
			int pa = ((t >> 6) & 1) == 1 ? 0 : (((t >> 7) & 1) == 1 ? 1 : 2);
			int a1 = pa == 0 ? 1 : 0;
			int a2 = pa == 2 ? 1 : 2;
			for (int ci = 0; ci < 4; ci++) {
				if (((int(spike_code) >> ci) & 1) == 1) {
					float s1 = (ci & 1) == 0 ? 1.0 : -1.0;
					float s2 = (ci & 2) == 0 ? 1.0 : -1.0;
					hone = max(hone, min(smoothstep(0.72, 0.98, box_pos[a1] * s1 / max(m, 1e-5)), smoothstep(0.72, 0.98, box_pos[a2] * s2 / max(m, 1e-5))));
				}
			}
		}
		hone *= (k == 3 || k == 4 || k == 7) ? 1.0 : 0.35;
		c = mix(c, c * 1.22 + vec3(0.025), hone * 0.6);
	}
	ALBEDO = c;
	ROUGHNESS = clamp(ROUGH[k] + 0.08 * (seed - 0.5) - 0.1 * hone, 0.02, 1.0);
	METALLIC = METAL[k] * (k == 3 ? iron_metal : 1.0);
	SPECULAR = SPEC[k];
	if (k == 10) {
		// Scales: a sheen of green and blue at a glancing look.
		float fr = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
		ALBEDO += vec3(0.0, 0.05, 0.04) * fr;
	}
	if (k == 12) {
		EMISSION += c * (2.2 + 0.4 * sin(TIME * 2.0 + seed * 6.0));
	}
	if (k == 0) {
		// Skin: light through the thin edges, warm.
		BACKLIGHT = c * vec3(0.16, 0.07, 0.05);
		// Oiled: a wet sheen on the muscles that catches the sun.
		ROUGHNESS = mix(ROUGHNESS, 0.26 + 0.08 * seed, oil);
		SPECULAR = mix(SPECULAR, 0.72, oil);
		// Out of breath: a sheen of sweat (softer than oil: a glow on the skin, not a mirror).
		ROUGHNESS = mix(ROUGHNESS, 0.42, sweat);
		SPECULAR = mix(SPECULAR, 0.55, sweat);
	}
	if (status.x < 0.0) {
		// Wet blood on it (Weapon.bloody: green below nought): glossy while it is fresh.
		float wet = clamp(-status.x, 0.0, 1.0);
		ROUGHNESS = mix(ROUGHNESS, 0.24, wet);
		SPECULAR = mix(SPECULAR, 0.5, wet);
		METALLIC = mix(METALLIC, 0.0, wet * 0.85);
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
