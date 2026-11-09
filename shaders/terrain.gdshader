shader_type spatial;
// Grama / brita / terra com coordenadas de mundo (sem UV).
render_mode blend_mix, cull_back;

uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 color_a : source_color = vec3(0.17, 0.33, 0.09);
uniform vec3 color_b : source_color = vec3(0.30, 0.45, 0.14);
uniform float scale = 0.08;
uniform float stripes = 1.0;      // faixas de corte da grama
uniform float roughness_base = 0.92;
uniform float wetness : hint_range(0.0, 1.0) = 0.0;

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
	c *= 0.85 + 0.3 * n3;
	float st = step(0.5, fract((p.x + p.y * 0.35) * 0.045));
	c *= 1.0 + (st - 0.5) * 0.14 * stripes;
	c *= mix(1.0, 0.72, wetness);
	ALBEDO = c;
	ROUGHNESS = mix(roughness_base, 0.45, wetness);
}
