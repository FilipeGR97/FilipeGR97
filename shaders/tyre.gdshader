shader_type spatial;
// Pneu: banda de rodagem com borracha "raspada", lateral com letreiro (marca fictícia) e
// faixa pintada na cor do composto (cor por instância).
// Malha em torno do eixo X: VERTEX = (axial, r*cos(a), r*sin(a)).
render_mode blend_mix, cull_back;

uniform sampler2D letters : hint_default_black, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float r_out = 0.36;        // raio externo
uniform float r_side0 = 0.27;      // início da lateral (perto do aro)
uniform float r_side1 = 0.335;     // fim da lateral (antes do ombro)
uniform float half_w = 0.17;
instance uniform vec3 band : source_color = vec3(1.0, 0.82, 0.05);
instance uniform float wear = 0.0;

varying vec3 lp;
varying vec3 ln;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

void vertex() {
	lp = VERTEX;
	ln = NORMAL;
}

void fragment() {
	float r = length(lp.yz);
	float a = atan(lp.z, lp.y) / (2.0 * PI) + 0.5;
	float side = smoothstep(0.55, 0.85, abs(ln.x));
	// ---- banda de rodagem: borracha fosca com riscos de uso na direção da rotação
	float g = hash(vec2(floor(a * 900.0), floor(lp.x * 140.0)));
	vec3 tread = vec3(0.055) * (0.85 + 0.3 * g) + vec3(0.035) * wear;
	float tr_rough = 0.78 + 0.12 * g;
	// ---- lateral
	float t = clamp((r - r_side0) / (r_side1 - r_side0), 0.0, 1.0);   // 0 aro .. 1 ombro
	vec3 sw = vec3(0.04);
	// faixa do composto: um anel perto do ombro
	float ring = smoothstep(0.80, 0.82, t) * (1.0 - smoothstep(0.88, 0.90, t));
	// letreiro entre o aro e a faixa
	float u = lp.x > 0.0 ? 1.0 - a : a;
	float tv = (0.76 - t) / 0.5;
	float txt = texture(letters, vec2(u, clamp(tv, 0.0, 1.0))).r * step(0.0, tv) * step(tv, 1.0);
	sw = mix(sw, vec3(0.78), txt * 0.92);
	sw = mix(sw, band, ring);
	vec3 c = mix(tread, sw, side);
	ALBEDO = c;
	ROUGHNESS = mix(tr_rough, 0.7 - 0.25 * txt, side);
	SPECULAR = 0.35;
}
