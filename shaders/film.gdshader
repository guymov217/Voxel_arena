shader_type canvas_item;
render_mode blend_premul_alpha, unshaded;
// A film's look laid over the 3D picture, under the HUD (Arena._build_visuals): the corners darkened
// a little, as a lens does, and a fine grain that changes with every frame of film (24 a second),
// most of it in the shadows. It draws over what is there without reading it back: the picture is
// darkened through the alpha (premultiplied blending) and the grain added to it, one pass, cheap.

uniform float vignette : hint_range(0.0, 1.0) = 0.3;     // how dark the far corners go
uniform float vignette_start : hint_range(0.0, 1.0) = 0.42;   // from this far out (half-diagonals)
uniform float grain : hint_range(0.0, 0.2) = 0.03;
uniform float grain_fps = 24.0;

float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void fragment() {
	vec2 d = SCREEN_UV - 0.5;
	// Rounder than the frame: the corners darken, the middle and the edges' middles hardly.
	float r = length(d * vec2(1.0, 0.82)) / 0.64;
	float v = vignette * smoothstep(vignette_start, 1.0, r);
	// Film grain: two hashes summed (a soft bell, not flat noise), one grain a pixel.
	vec2 px = floor(FRAGCOORD.xy);
	float f = floor(TIME * grain_fps);
	float n = hash(px + vec2(f * 17.0, f * 31.0)) + hash(px * 1.31 + vec2(f * 7.0, 11.0)) - 1.0;
	float g = n * grain;
	// Darker grains darken (through the alpha), brighter ones add a little light.
	COLOR = vec4(vec3(max(g, 0.0) * 0.6), clamp(v + max(-g, 0.0), 0.0, 1.0));
}
