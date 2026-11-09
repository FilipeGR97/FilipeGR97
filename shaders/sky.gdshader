shader_type sky;
// Céu procedural com nuvens (fbm). cloud_cover controla o clima.

uniform vec3 zenith : source_color = vec3(0.16, 0.36, 0.72);
uniform vec3 horizon : source_color = vec3(0.62, 0.74, 0.88);
uniform vec3 ground : source_color = vec3(0.30, 0.31, 0.30);
uniform float cloud_cover : hint_range(0.0, 1.0) = 0.45;
uniform float cloud_dark : hint_range(0.0, 1.0) = 0.0;
uniform float sun_size = 0.9997;
uniform float brightness = 1.0;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}
float fbm(vec2 p) {
	float v = 0.0, a = 0.5;
	for (int i = 0; i < 6; i++) { v += a * noise(p); p = p * 2.03 + vec2(1.7, 9.2); a *= 0.5; }
	return v;
}

void sky() {
	vec3 d = EYEDIR;
	float h = d.y;
	vec3 col = mix(horizon, zenith, pow(clamp(h, 0.0, 1.0), 0.55));
	col = mix(col, ground, smoothstep(0.0, -0.06, h));
	// sol
	float sd = dot(d, LIGHT0_DIRECTION);
	vec3 sunc = LIGHT0_COLOR * LIGHT0_ENERGY;
	col += sunc * pow(max(sd, 0.0), 350.0) * 0.6 * (1.0 - cloud_dark);
	col += sunc * smoothstep(sun_size, sun_size + 0.0002, sd) * 6.0 * (1.0 - cloud_cover * 0.8);
	col += vec3(1.0, 0.85, 0.6) * pow(max(sd, 0.0), 8.0) * 0.12;
	// nuvens projetadas num plano
	if (h > 0.0) {
		vec2 uv = d.xz / (h + 0.08) * 1.4;
		float c = fbm(uv * 1.2 + vec2(3.0, 1.0));
		float cov = smoothstep(1.0 - cloud_cover, 1.0 - cloud_cover + 0.35, c);
		float shade = fbm(uv * 1.2 + vec2(3.05, 1.03) + LIGHT0_DIRECTION.xz * 0.04);
		vec3 cc = mix(vec3(1.0), vec3(0.62, 0.65, 0.7), clamp((shade - c) * 4.0 + 0.4, 0.0, 1.0));
		cc = mix(cc, vec3(0.38, 0.4, 0.44), cloud_dark);
		col = mix(col, cc * (0.75 + 0.35 * pow(max(sd, 0.0), 4.0)), cov * smoothstep(0.0, 0.12, h));
	}
	COLOR = col * brightness;
}
