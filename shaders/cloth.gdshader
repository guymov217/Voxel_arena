shader_type spatial;
render_mode cull_disabled;
// Cloth in the wind over the arena: the velarium's sails over the stands and the long banners
// hung from the arcade (Arena._build_velarium). Each vertex is moved by a wave that runs along
// the cloth, the more the freer it hangs (UV.x for a sail: 0 at the rim it is lashed to, 1 at
// its free edge over the seats; UV.y for a banner: 0 at its pole, 1 at its foot). A sail's
// colour comes with it (COLOR); a banner draws its own border and a laurel wreath in gold.

uniform bool hanging = false;
uniform float wave = 0.25;
uniform vec4 field : source_color = vec4(0.6, 0.12, 0.1, 1.0);
uniform vec4 trim : source_color = vec4(0.9, 0.7, 0.3, 1.0);
uniform float cells = 0.0;      // drawn in voxels this many across (0: smooth)

void vertex() {
	float free = hanging ? UV.y : UV.x;
	// (Each banner its own phase from where it hangs; the sails, all one mesh, from where each
	// part of them is.)
	float ph = TIME * (hanging ? 2.1 : 1.3) + (hanging ? NODE_POSITION_WORLD.x * 0.37 + NODE_POSITION_WORLD.z * 0.29 : VERTEX.x * 0.21 + VERTEX.z * 0.17);
	float w = sin(ph + free * 5.0 + UV.y * 3.0) * 0.7 + sin(ph * 1.7 + free * 9.0) * 0.3;
	if (hanging) {
		VERTEX.z += w * wave * free;
		VERTEX.x += sin(ph * 0.8 + free * 4.0) * wave * 0.25 * free;
	} else {
		VERTEX.y += w * wave * pow(free, 1.5);
	}
}

void fragment() {
	vec2 uv = UV;
	float grain = 1.0;
	if (cells > 0.0) {
		vec2 cn = hanging ? vec2(cells, cells * 3.0) : vec2(cells * 1.6, cells);
		vec2 c = floor(UV * cn);
		uv = (c + 0.5) / cn;
		grain = 1.0 + 0.08 * (fract(sin(dot(c, vec2(12.9898, 78.233))) * 43758.5453) - 0.5);
	}
	vec3 col;
	if (hanging) {
		col = field.rgb;
		// A gold border, a fringe at the foot, and a laurel wreath (a ring open at the top).
		float edge = min(min(uv.x, 1.0 - uv.x) * 3.0, min(uv.y * 12.0, (1.0 - uv.y) * 6.0));
		if (edge < 0.18) {
			col = trim.rgb;
		}
		vec2 q = (uv - vec2(0.5, 0.42)) * vec2(1.0, 3.0);
		float r = length(q);
		if (r > 0.24 && r < 0.33 && q.y > -0.18) {
			col = trim.rgb;
		}
		if (r < 0.08) {
			col = trim.rgb;
		}
	} else {
		col = COLOR.rgb;
		// A darker hem along both sides of each sail and at its free edge.
		float hem = min(min(uv.y, 1.0 - uv.y) * 14.0, (1.0 - uv.x) * 22.0);
		if (hem < 1.0) {
			col *= 0.78;
		}
	}
	ALBEDO = col * grain;
	ROUGHNESS = 0.95;
	SPECULAR = 0.2;
	// Sunlight through the cloth, warm, seen from under it.
	BACKLIGHT = col * 0.3;
}
