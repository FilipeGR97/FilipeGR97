shader_type spatial;
// Zebra pintada: cor por vértice + grão do asfalto por baixo da tinta, desgaste e sujeira de borracha.
render_mode blend_mix, cull_back;

uniform sampler2D detail_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float wetness : hint_range(0.0, 1.0) = 0.0;

varying vec2 m;
varying vec3 vcol;

void vertex() {
	m = UV;
	vcol = COLOR.rgb;
}

void fragment() {
	vec2 uv = m * 0.42;
	float det = texture(detail_tex, uv).r / 0.121;
	float wear = texture(noise_tex, m * vec2(0.9, 0.25)).r;
	vec3 c = vcol * mix(1.0, det, 0.18);
	// borracha das rodas sujando a tinta (mais no lado de dentro)
	c *= 1.0 - 0.22 * smoothstep(0.55, 0.85, wear);
	c *= mix(1.0, 0.6, wetness);
	ALBEDO = c;
	ROUGHNESS = mix(0.5 + 0.2 * wear, 0.08, wetness);
	SPECULAR = 0.5;
	NORMAL_MAP = texture(normal_tex, uv).rgb;
	NORMAL_MAP_DEPTH = 0.35;
}
