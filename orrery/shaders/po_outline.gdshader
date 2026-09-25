// Porcelain Orrery :: thin inverted-hull outline so figurines read clearly
// against the busy nebula background.
shader_type spatial;
render_mode unshaded, cull_front, depth_draw_opaque, shadows_disabled;

uniform vec4 ink : source_color = vec4(0.05, 0.04, 0.12, 1.0);
uniform float thickness = 0.014;

void vertex() {
	VERTEX += NORMAL * thickness;
}

void fragment() {
	ALBEDO = ink.rgb;
}
