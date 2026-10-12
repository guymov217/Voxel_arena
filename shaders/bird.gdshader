shader_type spatial;
render_mode cull_disabled, unshaded;
// A far-off bird: the wings beat for a while, then it glides. UV.x is how far out along the wing.
instance uniform float phase = 0.0;

void vertex() {
	float cycle = mod(TIME * 0.4 + phase, 3.0);
	float beat = cycle < 1.6 ? sin(TIME * 9.0 + phase * 4.0) : 0.15;
	VERTEX.y += beat * 0.22 * UV.x * UV.x;
}

void fragment() {
	ALBEDO = vec3(0.12, 0.11, 0.1);
}
