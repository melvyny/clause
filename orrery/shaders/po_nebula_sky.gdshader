// Porcelain Orrery :: deep-space nebula with star field, a ringed planet and
// soft aurora ribbons. Colours lean indigo / magenta / teal so the white
// porcelain and gold figures pop.
shader_type sky;

uniform vec3 deep : source_color = vec3(0.02, 0.02, 0.07);
uniform vec3 mid : source_color = vec3(0.09, 0.06, 0.22);
uniform vec3 neb_a : source_color = vec3(0.85, 0.25, 0.62);
uniform vec3 neb_b : source_color = vec3(0.1, 0.75, 0.8);
uniform vec3 planet_col : source_color = vec3(0.96, 0.9, 0.82);
uniform vec3 planet_dir = vec3(-0.55, 0.32, -0.77);
uniform float planet_size = 0.16;

float hash(vec3 p) { return fract(sin(dot(p, vec3(12.9898, 78.233, 37.719))) * 43758.5453); }
float noise(vec3 p) {
	vec3 i = floor(p); vec3 f = fract(p);
	vec3 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1, 0, 0)), u.x), mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), u.x), u.y),
		mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), u.x), mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), u.x), u.y), u.z);
}
float fbm(vec3 p) {
	float a = 0.5; float s = 0.0;
	for (int i = 0; i < 5; i++) { s += a * noise(p); p *= 2.07; a *= 0.5; }
	return s;
}

void sky() {
	vec3 d = normalize(EYEDIR);
	vec3 col = mix(mid, deep, smoothstep(-0.2, 0.9, d.y));
	// nebula clouds
	float n1 = fbm(d * 2.6 + vec3(0.0, 0.0, TIME * 0.004));
	float n2 = fbm(d * 4.3 + vec3(5.2, 1.3, 0.0));
	float band = exp(-pow((d.y - 0.12 + 0.25 * d.x) * 2.4, 2.0));
	col += neb_a * smoothstep(0.45, 0.85, n1) * band * 0.9;
	col += neb_b * smoothstep(0.5, 0.9, n2) * band * 0.6;
	col += mix(neb_a, neb_b, n2) * pow(n1, 3.0) * 0.25;
	// stars
	vec3 sp = d * 220.0;
	float st = hash(floor(sp));
	float tw = 0.6 + 0.4 * sin(TIME * 2.0 + st * 40.0);
	col += vec3(1.0, 0.95, 0.9) * step(0.9965, st) * tw * 1.4;
	vec3 sp2 = d * 90.0;
	col += vec3(0.8, 0.9, 1.0) * step(0.9985, hash(floor(sp2))) * 2.5;
	// ringed porcelain planet
	vec3 pd = normalize(planet_dir);
	float ang = acos(clamp(dot(d, pd), -1.0, 1.0));
	float body = smoothstep(planet_size + 0.003, planet_size, ang);
	vec3 tangent = normalize(cross(pd, vec3(0.0, 1.0, 0.0)));
	float shade = 0.35 + 0.65 * smoothstep(-0.2, 0.15, dot(d - pd, tangent + vec3(0.0, 0.6, 0.0)));
	float bands = 0.9 + 0.1 * sin(dot(d, vec3(0.0, 1.0, 0.2)) * 160.0);
	vec3 pcol = planet_col * shade * bands;
	// ring: ellipse around planet
	vec3 rel = d - pd;
	vec2 rp = vec2(dot(rel, tangent), dot(rel, normalize(cross(tangent, pd))));
	float r = length(vec2(rp.x, rp.y * 3.2 + rp.x * 0.6));
	float ring = smoothstep(0.012, 0.0, abs(r - planet_size * 1.75)) + 0.6 * smoothstep(0.008, 0.0, abs(r - planet_size * 1.95));
	float front = step(0.0, rp.y * 3.2 + rp.x * 0.6);
	col = mix(col, pcol, body);
	col += vec3(1.0, 0.78, 0.4) * ring * (1.0 - body * (1.0 - front)) * 0.9;
	col += planet_col * 0.08 * exp(-ang * 6.0);
	COLOR = col;
}
