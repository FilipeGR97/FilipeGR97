shader_type spatial;
// Modelo 3D externo (Patch 7): usa as texturas originais (carbono, metal, detalhes, relevo, rugosidade) e,
// onde a textura original é a pintura da equipe (vermelho), aplica a pintura da NOSSA equipe (mesma lógica do
// carro procedural, livery_inc). Nenhuma marca real: os decalques originais ficam escondidos.
render_mode blend_mix, cull_disabled;

#include "res://shaders/livery_inc.gdshaderinc"

uniform sampler2D base_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rough_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D metal_tex : hint_default_black, filter_linear_mipmap_anisotropic, repeat_enable;
uniform mat4 to_car = mat4(1.0);       // malha -> espaço do carro (frente -Z, chão em y = 0)
uniform vec3 paint_ref : source_color = vec3(0.8, 0.05, 0.05);   // cor da pintura original

varying vec3 lp;
varying vec3 ln;

void vertex() {
	lp = (to_car * vec4(VERTEX, 1.0)).xyz;
	ln = normalize(mat3(to_car) * NORMAL);
}

void fragment() {
	vec3 base = texture(base_tex, UV).rgb;
	// máscara da pintura: quanto o texel original se parece com a cor da equipe original
	float sat = max(base.r, max(base.g, base.b)) - min(base.r, min(base.g, base.b));
	float hue_d = length(normalize(base + 1e-4) - normalize(paint_ref + 1e-4));
	float mask = smoothstep(0.35, 0.15, hue_d) * smoothstep(0.12, 0.3, sat);
	float floor_m;
	vec2 suv;
	vec3 liv = livery_paint(lp, ln, floor_m, suv);
	// sombreamento do original (oclusão pintada na textura) preservado sobre a nossa cor
	float shade = clamp(max(base.r, max(base.g, base.b)) / max(max(paint_ref.r, max(paint_ref.g, paint_ref.b)), 0.01), 0.55, 1.15);
	vec3 c = mix(base, liv * mix(shade, 1.0, floor_m), mask);
	float fin = finish;
	float matte = step(0.5, fin) * (1.0 - step(1.5, fin));
	float met = step(1.5, fin);
	float r0 = texture(rough_tex, UV).r;
	float m0 = texture(metal_tex, UV).r;
	float pm = mask * (1.0 - floor_m);
	ALBEDO = c;
	ROUGHNESS = mix(r0, mix(mix(0.3, 0.6, matte), 0.22, met), pm);
	METALLIC = mix(m0, mix(0.12, 0.8, met), pm);
	CLEARCOAT = pm * (1.0 - matte);
	CLEARCOAT_ROUGHNESS = 0.06;
	NORMAL_MAP = texture(normal_tex, UV).rgb;
}
