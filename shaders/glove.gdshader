shader_type spatial;
// Luva de corrida (modelo CC-BY de layne.harris, logo removido): o vermelho da foto original vira a cor da luva
// da equipe, mantendo costuras, dobras e a palma de borracha.
render_mode blend_mix, cull_disabled;

uniform sampler2D tex : source_color, filter_linear_mipmap_anisotropic;
uniform vec3 glove_col : source_color = vec3(0.92);

void fragment() {
	vec3 t = texture(tex, UV).rgb;
	float red = smoothstep(0.12, 0.3, t.r - max(t.g, t.b));
	float lum = clamp(t.r / 0.85, 0.0, 1.2);
	vec3 c = mix(t, glove_col * lum, red);
	ALBEDO = c;
	ROUGHNESS = mix(0.75, 0.6, red);
	SPECULAR = 0.3;
}
