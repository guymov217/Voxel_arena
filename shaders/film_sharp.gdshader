shader_type canvas_item;
render_mode unshaded;
// The film's look over the 3D picture (shaders/film.gdshader), at the higher settings with the
// picture sharpened first: a contrast-adaptive sharpen (each pixel against its four neighbours,
// strongest where the picture is flat and gentle on an edge already hard, so nothing rings),
// which gives back to the voxels' edges what the anti-aliasing softened. Then the corners
// darkened a little and the fine moving grain, as film.gdshader does. One pass over the screen.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float sharpness : hint_range(0.0, 1.0) = 0.35;
uniform float vignette : hint_range(0.0, 1.0) = 0.3;
uniform float vignette_start : hint_range(0.0, 1.0) = 0.42;
uniform float grain : hint_range(0.0, 0.2) = 0.03;
uniform float grain_fps = 24.0;

float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void fragment() {
	vec2 px = SCREEN_PIXEL_SIZE;
	vec3 e = textureLod(screen_tex, SCREEN_UV, 0.0).rgb;
	vec3 b = textureLod(screen_tex, SCREEN_UV + vec2(0.0, -px.y), 0.0).rgb;
	vec3 d = textureLod(screen_tex, SCREEN_UV + vec2(-px.x, 0.0), 0.0).rgb;
	vec3 f = textureLod(screen_tex, SCREEN_UV + vec2(px.x, 0.0), 0.0).rgb;
	vec3 h = textureLod(screen_tex, SCREEN_UV + vec2(0.0, px.y), 0.0).rgb;
	// How much room there is to sharpen without clipping: less on a hard edge.
	vec3 mn = min(min(min(b, d), min(f, h)), e);
	vec3 mx = max(max(max(b, d), max(f, h)), e);
	vec3 amp = sqrt(clamp(min(mn, 1.0 - mx) / max(mx, vec3(1e-4)), 0.0, 1.0));
	vec3 w = -amp / mix(8.0, 5.0, sharpness);
	vec3 col = clamp((e + (b + d + f + h) * w) / (1.0 + 4.0 * w), 0.0, 1.0);
	// The lens's corners and the film's grain (film.gdshader).
	vec2 dd = SCREEN_UV - 0.5;
	float r = length(dd * vec2(1.0, 0.82)) / 0.64;
	float v = vignette * smoothstep(vignette_start, 1.0, r);
	vec2 fp = floor(FRAGCOORD.xy);
	float fr = floor(TIME * grain_fps);
	float n = hash(fp + vec2(fr * 17.0, fr * 31.0)) + hash(fp * 1.31 + vec2(fr * 7.0, 11.0)) - 1.0;
	float g = n * grain;
	col = col * (1.0 - clamp(v + max(-g, 0.0), 0.0, 1.0)) + vec3(max(g, 0.0) * 0.6);
	COLOR = vec4(col, 1.0);
}
