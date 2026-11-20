shader_type canvas_item;
render_mode blend_add;
// The gleam that runs across the logo in the opening (scripts/ui/intro.gd): a slanted band of warm light, drawn only
// where the logo's own pixels are (the picture this is on is the logo alone, clear elsewhere) and added to the logo
// already on screen, so the letters flare as it passes. `sweep` is where the band is along the logo's box:
// 0 at its left edge, 1 at its right, below 0 or above 1 off the logo.
uniform vec4 box = vec4(0.25, 0.44, 0.75, 0.87);   // the logo's rectangle in the picture, in UV: left, top, right, bottom
uniform float sweep = -1.0;
uniform float width = 0.17;
uniform float strength = 1.0;
uniform vec4 tint : source_color = vec4(1.0, 0.93, 0.78, 1.0);

void fragment() {
	vec4 logo = texture(TEXTURE, UV);
	vec2 p = (UV - box.xy) / (box.zw - box.xy);
	float along = p.x + (p.y - 0.5) * 0.35;
	float d = abs(along - sweep) / width;
	float band = pow(max(1.0 - d, 0.0), 2.0);
	COLOR = vec4(tint.rgb * band * strength, logo.a);
}
