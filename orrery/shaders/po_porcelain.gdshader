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
uniform float mended = 0.0; // times this creature has been mended: permanent, brighter gold seams
uniform vec4 rim_color : source_color = vec4(0.7, 0.8, 1.0, 1.0);
uniform float rim_strength = 0.35;
uniform vec4 emission_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float emission_energy = 0.0;
uniform float gloss = 0.14;
// Surface decoration, modelled on real ceramic techniques:
// 0 plain dip | 1 Jun flambe | 2 Tang sancai drips | 3 Ru ice-crackle | 4 blue-and-white
// 5 Cizhou tiger stripes | 6 Jian "yohen" iridescent spots | 7 Chenghua doucai enamels | 8 hare's fur
uniform int pattern = 0;
uniform vec4 glaze2 : source_color = vec4(0.2, 0.45, 0.2, 1.0);
uniform vec4 glaze3 : source_color = vec4(0.85, 0.6, 0.2, 1.0);
uniform float pattern_scale = 4.0;

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

float vhash(vec3 p) { return fract(sin(dot(p, vec3(12.9898, 78.233, 37.719))) * 43758.5453); }
float vnoise(vec3 p) {
	vec3 i = floor(p); vec3 f = fract(p);
	vec3 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(vhash(i), vhash(i + vec3(1, 0, 0)), u.x), mix(vhash(i + vec3(0, 1, 0)), vhash(i + vec3(1, 1, 0)), u.x), u.y),
		mix(mix(vhash(i + vec3(0, 0, 1)), vhash(i + vec3(1, 0, 1)), u.x), mix(vhash(i + vec3(0, 1, 1)), vhash(i + vec3(1, 1, 1)), u.x), u.y), u.z);
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
	vec3 pattern_emit = vec3(0.0);
	if (pattern == 1) {
		float n = vnoise(vec3(ang * 2.5, lp.y * pattern_scale, 0.7));
		col = mix(col, glaze2.rgb, g * smoothstep(0.35, 0.75, n));
	} else if (pattern == 2) {
		float k = fract(ang / 6.2832 * 5.0 + vnoise(vec3(ang * 3.0, lp.y * 2.0, 1.0)) * 0.6);
		vec3 sc = k < 0.34 ? glaze.rgb : (k < 0.67 ? glaze2.rgb : glaze3.rgb);
		float run = vnoise(vec3(ang * 9.0, lp.y * pattern_scale * 0.5, 3.0));
		float cover = smoothstep(0.35, 0.6, run * 0.8 + (dip_level - lp.y) * 1.2 + 0.25);
		col = mix(porcelain.rgb, sc, cover);
	} else if (pattern == 3) {
		vec2 cv = voronoi(lp * pattern_scale + vec3(11.0, 5.0, 2.0));
		float cr = 1.0 - smoothstep(0.0, 0.035, cv.y - cv.x);
		col = mix(col, col * 0.5, cr * 0.75);
	} else if (pattern == 4) {
		float c = vnoise(lp * pattern_scale);
		float iso = abs(fract(c * 4.0) - 0.5);
		float ink = smoothstep(0.05, 0.015, iso) * 0.95 + smoothstep(0.72, 0.8, c) * 0.5;
		float bands = smoothstep(0.012, 0.0, abs(abs(fract(lp.y * pattern_scale * 0.3) - 0.5) - 0.47));
		col = mix(porcelain.rgb, glaze.rgb, clamp(ink + bands, 0.0, 1.0));
	} else if (pattern == 5) {
		float s1 = sin(ang * 9.0 + vnoise(lp * 3.0) * 3.0 + lp.y * 2.0 + lp.z * 3.0);
		col = mix(col, glaze2.rgb, smoothstep(0.55, 0.78, s1));
	} else if (pattern == 6) {
		vec2 sv = voronoi(lp * pattern_scale + vec3(2.0, 9.0, 4.0));
		float spot = smoothstep(0.3, 0.1, sv.x);
		vec3 iri = 0.5 + 0.5 * cos(6.2832 * (sv.y * 2.0 + ang * 0.15 + vec3(0.0, 0.33, 0.67)));
		col = mix(col, iri * 0.5 + glaze2.rgb * 0.5, spot * 0.85);
		pattern_emit = iri * spot * 1.4;
	} else if (pattern == 7) {
		float b = fract(lp.y * pattern_scale * 0.5);
		float band = step(0.3, b) * step(b, 0.75);
		float blob = vnoise(lp * pattern_scale * 2.0);
		vec3 enamel = blob > 0.55 ? glaze2.rgb : glaze3.rgb;
		col = mix(col, enamel, band * smoothstep(0.35, 0.45, blob) * 0.9);
	} else if (pattern == 8) {
		float f = vnoise(vec3(ang * 60.0, lp.y * 3.0, 0.0));
		col = mix(col, glaze2.rgb, smoothstep(0.55, 0.85, f) * g);
	}

	vec2 v = voronoi(lp * crack_scale + vec3(3.1, 7.7, 1.3));
	float w = crack_width * (1.0 + damage * 1.6 + mended * 0.9);
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
		+ gold.rgb * seam * (0.18 + mended * 0.55)
		+ core_color.rgb * seam * damage * damage * 5.0 * pulse
		+ emission_color.rgb * emission_energy
		+ pattern_emit;
}
