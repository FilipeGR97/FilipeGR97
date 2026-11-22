shader_type spatial;
// Grama / brita / terra com coordenadas de mundo (sem UV).
// Grama: faixas de corte largas + textura de detalhe (CC0). Brita: textura de cascalho (CC0).
render_mode blend_mix, cull_back;

uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D detail_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D albedo_tex : source_color, hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 color_a : source_color = vec3(0.17, 0.33, 0.09);
uniform vec3 color_b : source_color = vec3(0.30, 0.45, 0.14);
uniform float scale = 0.08;
uniform float stripes = 1.0;      // faixas de corte da grama
uniform float roughness_base = 0.92;
uniform float wetness : hint_range(0.0, 1.0) = 0.0;
uniform float detail_mean = 0.244;   // média da textura de detalhe (para normalizar)
uniform float detail_mix = 0.0;      // 0 = sem textura de detalhe
uniform float tex_scale = 0.5;       // repetições por metro das texturas reais
uniform float albedo_mix = 0.0;      // 1 = cor vem da textura (brita)
uniform float normal_depth = 0.0;

varying vec3 wp;

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = wp.xz;
	float n1 = texture(noise_tex, p * scale).r;
	float n2 = texture(noise_tex, p * scale * 0.13 + vec2(0.4, 0.1)).r;
	float n3 = texture(noise_tex, p * scale * 6.0).r;
	vec3 c = mix(color_a, color_b, clamp(n1 * 0.65 + n2 * 0.55 - 0.1, 0.0, 1.0));
	c *= 0.9 + 0.2 * n3;
	// detalhe real de perto (some com a distância pelos mipmaps)
	vec2 tp = p * tex_scale;
	float det = texture(detail_tex, tp).r / detail_mean;
	c *= mix(1.0, det, detail_mix);
	// faixas de corte: largas, com borda suave, como num gramado de autódromo
	float ph = fract((p.x + p.y * 0.35) / 14.0);
	float st = smoothstep(0.46, 0.54, ph) * (1.0 - smoothstep(0.96, 1.0, ph));
	c *= 1.0 + (st - 0.5) * 0.3 * stripes;
	vec3 tc = texture(albedo_tex, tp).rgb;
	c = mix(c, tc * (0.85 + 0.3 * n2), albedo_mix);
	c *= mix(1.0, 0.72, wetness);
	ALBEDO = c;
	ROUGHNESS = mix(roughness_base, 0.45, wetness);
	if (normal_depth > 0.0) {
		NORMAL_MAP = texture(normal_tex, tp).rgb;
		NORMAL_MAP_DEPTH = normal_depth;
	}
}
