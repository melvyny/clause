// Goldmend :: the run map is painted on a blue-and-white porcelain plate.
// Cobalt brushwork (rim rings, a wave band, cloud scrolls in the well) under a
// glossy glaze, and the plate itself is cracked and mended with gold.
shader_type spatial;

uniform vec4 porcelain : source_color = vec4(0.86, 0.87, 0.84, 1.0);
uniform vec4 cobalt : source_color = vec4(0.04, 0.1, 0.42, 1.0);
uniform vec4 gold : source_color = vec4(1.0, 0.76, 0.33, 1.0);
uniform float radius = 14.0;

varying vec3 lp;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}
float fbm(vec2 p) {
	float s = 0.0; float a = 0.5;
	for (int i = 0; i < 4; i++) { s += a * noise(p); p *= 2.03; a *= 0.5; }
	return s;
}
vec2 hash2(vec2 p) { return fract(sin(vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)))) * 43758.5453); }
float seam(vec2 x) {
	vec2 n = floor(x); vec2 f = fract(x);
	float d1 = 8.0; float d2 = 8.0;
	for (int j = -1; j <= 1; j++) for (int i = -1; i <= 1; i++) {
		vec2 g = vec2(float(i), float(j));
		vec2 r = g + hash2(n + g) - f;
		float d = dot(r, r);
		if (d < d1) { d2 = d1; d1 = d; } else if (d < d2) { d2 = d; }
	}
	return sqrt(d2) - sqrt(d1);
}

void vertex() { lp = VERTEX; }

void fragment() {
	vec2 p = lp.xz / radius;          // -1..1 across the plate
	float r = length(p);
	float a = atan(p.y, p.x);
	float ink = 0.0;
	// rim rings
	ink += smoothstep(0.012, 0.0, abs(r - 0.965)) + smoothstep(0.006, 0.0, abs(r - 0.935));
	ink += smoothstep(0.006, 0.0, abs(r - 0.80)) + smoothstep(0.010, 0.0, abs(r - 0.775));
	// wave band ("sea water" pattern)
	float band = step(0.81, r) * step(r, 0.925);
	float waves = sin((r * 90.0) + sin(a * 26.0) * 2.2);
	ink += band * smoothstep(0.55, 0.9, waves) * 0.9;
	// cloud scrolls in the well: cobalt wash with darker outlines
	float c = fbm(p * 3.2 + vec2(1.7, 4.1));
	float iso = abs(fract(c * 5.0) - 0.5);
	float well = step(r, 0.76) * step(0.24, r);
	ink += well * smoothstep(0.1, 0.03, iso) * smoothstep(0.35, 0.6, c) * 0.95;
	ink += well * smoothstep(0.55, 0.7, c) * 0.28;
	// central lotus medallion
	float petals = 0.15 + 0.045 * cos(a * 8.0);
	ink += smoothstep(0.012, 0.0, abs(r - petals)) + smoothstep(0.008, 0.0, abs(r - 0.225)) + smoothstep(0.006, 0.0, abs(r - 0.24));
	ink += step(r, petals) * step(0.06, r) * (0.35 + 0.25 * cos(a * 16.0)) * 0.6;
	ink += smoothstep(0.05, 0.045, r) * 0.9;
	// brush variation
	float brush = 0.7 + 0.3 * noise(p * 60.0);
	ink = clamp(ink * brush, 0.0, 1.0);
	vec3 col = mix(porcelain.rgb, cobalt.rgb, ink);
	// kintsugi repairs across the plate
	float s = seam(p * 2.6 + vec2(0.3, 0.9));
	float g = 1.0 - smoothstep(0.0, 0.022, s);
	col = mix(col, gold.rgb, g);
	ALBEDO = col;
	METALLIC = g;
	ROUGHNESS = mix(0.28, 0.3, g);
	SPECULAR = 0.35;
	CLEARCOAT = (1.0 - g) * 0.6;
	CLEARCOAT_ROUGHNESS = 0.18;
	EMISSION = gold.rgb * g * 0.35;
}
