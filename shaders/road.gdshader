shader_type spatial;
// Asfalto: UV = (posição lateral em metros, distância ao longo da pista em metros)
// COLOR.r = quantidade de borracha (traçado ideal)
// Textura de detalhe/normal/rugosidade: "asphalt_track" da Poly Haven (CC0).
render_mode blend_mix, cull_back, depth_draw_opaque;

uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D detail_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rough_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float half_width = 7.0;
uniform float edge_lines = 1.0;
uniform float wetness : hint_range(0.0, 1.0) = 0.0;
uniform vec3 base_color : source_color = vec3(0.2, 0.205, 0.215);
uniform float tile = 0.42;          // repetições da textura por metro

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
	vec2 uv = m * tile;
	// textura real (média 0,12) normalizada para ~1 e suavizada para não "granular" demais
	float det = texture(detail_tex, uv).r / 0.121;
	det = mix(1.0, det, 0.55);
	float n2 = texture(noise_tex, m * 0.045 + vec2(0.31, 0.77)).r;
	float n1 = texture(noise_tex, m * 0.21).r;
	vec3 c = base_color * det * (0.88 + 0.22 * n2) * (0.94 + 0.12 * n1);
	// borracha no traçado (faixa escura) + marcas de pneu ao longo da pista
	float rub = vc.r * (0.7 + 0.3 * n2);
	float streak = texture(noise_tex, vec2(m.x * 1.7, m.y * 0.011)).r;
	float marks = smoothstep(0.58, 0.72, streak) * smoothstep(0.15, 0.6, vc.r);
	c *= 1.0 - 0.42 * rub - 0.22 * marks;
	// linhas brancas de limite de pista (tinta com um pouco do grão do asfalto)
	float d = half_width - abs(m.x);
	float aa = fwidth(m.x) * 1.2 + 0.005;
	float line = band(d, 0.06, 0.26, aa) * edge_lines;
	vec3 paint = vec3(0.82, 0.82, 0.8) * mix(1.0, det, 0.25);
	c = mix(c, paint, line);
	// pista molhada: mais escura, reflexiva, com poças
	float puddle = smoothstep(0.55, 0.75, n2) * wetness;
	float w = clamp(wetness * 0.85 + puddle, 0.0, 1.0);
	c *= mix(1.0, 0.5, w);
	ALBEDO = c;
	float r = texture(rough_tex, uv).r;
	ROUGHNESS = mix(mix(0.62 + 0.3 * r, 0.55, line) - 0.14 * rub, 0.06 + 0.06 * r, w);
	SPECULAR = mix(0.45, 0.7, w);
	NORMAL_MAP = texture(normal_tex, uv).rgb;
	NORMAL_MAP_DEPTH = mix(1.0, 0.15, w) * (1.0 - 0.6 * line);
}
