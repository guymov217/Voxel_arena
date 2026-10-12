shader_type sky;
// The arena's sky: a deep blue overhead fading to a warm dusty horizon, the sun with its glare,
// and clouds that drift across on the wind, lit gold on the side toward the sun. At night the
// stars are a real photograph of the night sky (CC0, Poly Haven "moonless golf"), only the part
// above the horizon, with the clouds dark against them.

uniform vec3 top_color : source_color = vec3(0.22, 0.42, 0.78);
uniform vec3 horizon_color : source_color = vec3(0.86, 0.78, 0.64);
uniform vec3 ground_color : source_color = vec3(0.42, 0.34, 0.25);
uniform vec3 cloud_light : source_color = vec3(1.0, 0.96, 0.9);
uniform vec3 cloud_shade : source_color = vec3(0.62, 0.64, 0.72);
uniform float cover : hint_range(0.0, 1.0) = 0.48;
uniform float wind = 0.012;
uniform float night = 0.0;
uniform float star_gain = 6.0;
uniform sampler2D clouds_noise : filter_linear_mipmap, repeat_enable;
uniform sampler2D stars : source_color, filter_linear_mipmap;

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.55;
	for (int i = 0; i < 4; i++) {
		v += a * texture(clouds_noise, p).r;
		p = p * 2.03 + vec2(0.17, 0.31);
		a *= 0.5;
	}
	return v;
}

void sky() {
	vec3 d = EYEDIR;
	float up = d.y;
	// Sky gradient, a little brighter and warmer near the horizon.
	float hz = pow(1.0 - clamp(up, 0.0, 1.0), 3.5);
	vec3 col = mix(top_color, horizon_color, hz);
	if (up < 0.0) {
		col = mix(horizon_color, ground_color, clamp(-up * 3.0, 0.0, 1.0));
	}
	vec3 sdir = LIGHT0_DIRECTION;
	float sun_dot = max(dot(d, sdir), 0.0);
	// Night: the photographed stars above the horizon (the photo's own horizon, trees and
	// town lights, never shows).
	if (night > 0.0 && up > 0.0) {
		vec2 uv = vec2(atan(d.x, -d.z) / (2.0 * PI) + 0.5, acos(clamp(up, -1.0, 1.0)) / PI);
		// Only the stars themselves: the photo's own sky glow is taken off, so the night
		// stays dark, and the trees on its horizon are well below where it starts.
		vec3 st = texture(stars, uv).rgb;
		st = max(st - vec3(0.22), vec3(0.0)) * 1.3;
		st *= st;
		float above = smoothstep(0.38, 0.6, up);
		col += st * star_gain * above * night;
	}
	if (!AT_CUBEMAP_PASS && up > 0.0) {
		// Clouds on a flat layer high up: the further toward the horizon, the thinner and
		// the more squashed, fading into the haze.
		vec2 p = d.xz / (up + 0.08) * 0.11 + vec2(TIME * wind, TIME * wind * 0.37);
		float n = fbm(p);
		float c = smoothstep(1.0 - cover, 1.0 - cover + 0.28, n);
		float thick = smoothstep(1.0 - cover, 1.0, n);
		// Light through them: bright on the edges toward the sun, darker in the middle.
		float lit = 0.55 + 0.45 * pow(sun_dot, 3.0) + 0.25 * (1.0 - thick);
		vec3 cc = mix(cloud_shade, cloud_light, clamp(lit, 0.0, 1.0));
		cc = mix(cc, horizon_color, hz * 0.6);
		cc *= mix(1.0, 0.12, night);
		col = mix(col, cc, c * smoothstep(0.0, 0.18, up) * 0.92);
	}
	// The sun and its glare (none at night).
	if (LIGHT0_ENABLED) {
		float disc = smoothstep(0.9993, 0.9997, sun_dot);
		vec3 sc = LIGHT0_COLOR * LIGHT0_ENERGY;
		col += sc * (disc * 14.0 + pow(sun_dot, 64.0) * 0.6 + pow(sun_dot, 6.0) * 0.12) * (1.0 - night);
	}
	COLOR = col;
}
