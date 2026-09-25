// Porcelain Orrery :: glazed porcelain with kintsugi gold seams.
// - White porcelain body, element-coloured glaze "dipped" up to `dip_level`
//   with drips, glossy clearcoat.
// - Gold kintsugi seams from a 3D Voronoi pattern. `damage` (0..1) widens the
//   seams and makes them glow in `core_color` -- a creature literally cracks
//   open with light as it loses HP.
shader_type spatial;

uniform vec4 porcelain : source_color = vec4(0.95, 0.94, 0.9, 1.0);
uniform vec4 glaze : source_color = vec4(0.12, 0.32, 0.85, 1.0);
uniform float dip_level = 0.0;
uniform float drip = 0.12;
uniform float glaze_all = 0.0;
uniform vec4 gold : source_color = vec4(1.0, 0.74, 0.32, 1.0);
uniform vec4 core_color : source_color = vec4(1.0, 0.5, 0.2, 1.0);
uniform float crack_scale = 3.2;
uniform float crack_width = 0.035;
uniform float damage = 0.0;
uniform vec4 rim_color : source_color = vec4(0.7, 0.8, 1.0, 1.0);
uniform float rim_strength = 0.35;
uniform vec4 emission_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float emission_energy = 0.0;
uniform float gloss = 0.14;

varying vec3 lp;

vec3 hash3(vec3 p) {
	p = vec3(dot(p, vec3(127.1, 311.7, 74.7)), dot(p, vec3(269.5, 183.3, 246.1)), dot(p, vec3(113.5, 271.9, 124.6)));
	return fract(sin(p) * 43758.5453);
}

vec2 voronoi(vec3 x) {
	vec3 p = floor(x);
	vec3 f = fract(x);
	float d1 = 8.0;
	float d2 = 8.0;
	for (int k = -1; k <= 1; k++)
	for (int j = -1; j <= 1; j++)
	for (int i = -1; i <= 1; i++) {
		vec3 b = vec3(float(i), float(j), float(k));
		vec3 r = b + hash3(p + b) - f;
		float d = dot(r, r);
		if (d < d1) { d2 = d1; d1 = d; } else if (d < d2) { d2 = d; }
	}
	return vec2(sqrt(d1), sqrt(d2));
}

void vertex() {
	lp = VERTEX;
}

void fragment() {
	float ang = atan(lp.x, lp.z);
	float drips = pow(0.5 + 0.5 * sin(ang * 7.0 + lp.y * 3.0), 6.0) * drip * 2.5;
	float wave = sin(ang * 3.0) * drip * 0.4;
	float g = max(glaze_all, smoothstep(0.015, -0.015, lp.y - dip_level - wave - drips));
	// glaze pools darker toward the bottom, lighter at the rim of the dip
	vec3 glaze_col = mix(glaze.rgb * 0.7, glaze.rgb * 1.15, smoothstep(dip_level - 0.6, dip_level, lp.y));
	vec3 col = mix(porcelain.rgb, glaze_col, g);

	vec2 v = voronoi(lp * crack_scale + vec3(3.1, 7.7, 1.3));
	float w = crack_width * (1.0 + damage * 1.6);
	float seam = 1.0 - smoothstep(0.0, w, v.y - v.x);

	ALBEDO = mix(col, gold.rgb, seam);
	METALLIC = seam;
	ROUGHNESS = mix(gloss, 0.32, seam);
	SPECULAR = 0.6;
	CLEARCOAT = 1.0 - seam;
	CLEARCOAT_ROUGHNESS = 0.08;

	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	float pulse = 0.75 + 0.25 * sin(TIME * 6.0);
	EMISSION = rim_color.rgb * fres * rim_strength
		+ gold.rgb * seam * 0.18
		+ core_color.rgb * seam * damage * damage * 5.0 * pulse
		+ emission_color.rgb * emission_energy;
}
