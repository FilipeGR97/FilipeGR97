shader_type spatial;
// Asfalto: UV = (posição lateral em metros, distância ao longo da pista em metros)
// COLOR.r = quantidade de borracha (traçado ideal), COLOR.g = 1 se for zona de box
render_mode blend_mix, cull_back, depth_draw_opaque;

uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float half_width = 7.0;
uniform float edge_lines = 1.0;
uniform float wetness : hint_range(0.0, 1.0) = 0.0;
uniform vec3 base_color : source_color = vec3(0.19, 0.195, 0.205);

varying vec2 m;
varying vec4 vc;

void vertex() {
	m = UV;
	vc = COLOR;
}

float band(float x, float a, float b, float aa) {
	return smoothstep(a - aa, a + aa, x) * (1.0 - smoothstep(b - aa, b + aa, x));
}

void fragment() {
	float n1 = texture(noise_tex, m * 0.35).r;
	float n2 = texture(noise_tex, m * 0.045 + vec2(0.31, 0.77)).r;
	float n3 = texture(noise_tex, m * 2.2).r;
	vec3 c = base_color * (0.78 + 0.32 * n1) * (0.86 + 0.28 * n2) * (0.92 + 0.16 * n3);
	// borracha no traçado
	float rub = vc.r * (0.75 + 0.25 * n2);
	c *= 1.0 - 0.38 * rub;
	// linhas brancas de limite de pista
	float d = half_width - abs(m.x);
	float aa = fwidth(m.x) * 1.2 + 0.005;
	float line = band(d, 0.06, 0.26, aa) * edge_lines;
	vec3 paint = vec3(0.86, 0.86, 0.84) * (0.9 + 0.1 * n3);
	c = mix(c, paint, line);
	// pista molhada: mais escura, reflexiva, com poças
	float puddle = smoothstep(0.55, 0.75, n2) * wetness;
	float w = clamp(wetness * 0.85 + puddle, 0.0, 1.0);
	c *= mix(1.0, 0.5, w);
	ALBEDO = c;
	ROUGHNESS = mix(mix(0.82 - 0.12 * n1, 0.55, line) - 0.12 * rub, 0.06 + 0.08 * n3, w);
	SPECULAR = mix(0.45, 0.7, w);
	NORMAL_MAP = texture(normal_tex, m * 0.35).rgb;
	NORMAL_MAP_DEPTH = mix(0.9, 0.12, w);
}
