shader_type spatial;
// Pintura do carro procedural. A lógica dos estilos está em livery_inc.gdshaderinc (compartilhada com os
// modelos externos). Estilos: 0 faixa diagonal | 1 lâminas | 2 estrelas | 3 anos 80 | 4 duas cores |
// 5 preto e dourado | 6 degradê de pontos | 7 faixas de canto. Acabamento: 0 brilhante | 1 fosco | 2 metálico
render_mode blend_mix, cull_disabled;

#include "res://shaders/livery_inc.gdshaderinc"
uniform float clay = 0.0;

varying vec3 lp;
varying vec3 ln;

void vertex() {
	lp = VERTEX;
	ln = NORMAL;
}

void fragment() {
	float floor_m;
	vec2 suv;
	vec3 c = livery_paint(lp, ln, floor_m, suv);
	c = mix(c, vec3(0.72), clay);
	// acabamento
	float fin = finish;
	if (metal > 0.5) fin = 2.0;
	float matte = step(0.5, fin) * (1.0 - step(1.5, fin));
	float met = step(1.5, fin);
	// fosco: leve textura manchada (como a pintura fosca de verdade)
	float mot = vnoise(suv * 9.0) * 0.6 + vnoise(suv * 31.0) * 0.4;
	c *= 1.0 + matte * (mot - 0.5) * 0.12;
	ALBEDO = c;
	ROUGHNESS = mix(mix(mix(0.3, 0.58 + 0.08 * mot, matte), 0.22, met), 0.5, floor_m);
	METALLIC = mix(mix(0.12, 0.8, met), 0.1, floor_m);
	SPECULAR = mix(0.5, 0.35, matte);
	CLEARCOAT = (1.0 - matte) * (1.0 - floor_m * 0.7);
	CLEARCOAT_ROUGHNESS = 0.06;
}
