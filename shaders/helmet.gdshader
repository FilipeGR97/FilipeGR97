shader_type spatial;
// Pintura do capacete: desenho gráfico procedural com contorno, verniz brilhante e flocos metálicos.
// Coordenadas: posição do vértice relativa ao centro do casco, normalizada pelos raios do casco.
render_mode blend_mix, cull_back;

uniform vec3 c1 : source_color = vec3(0.95);    // cor base
uniform vec3 c2 : source_color = vec3(0.85, 0.1, 0.1);  // grafismo principal
uniform vec3 c3 : source_color = vec3(0.05);    // contorno / detalhe
uniform float design = 0.0;
uniform vec3 center = vec3(0.0, 0.818, -0.10);
uniform vec3 radii = vec3(0.128, 0.14, 0.155);

varying vec3 hp;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

// faixa com contorno: devolve (preenchimento, contorno)
vec2 stripe(float x, float c, float w, float o) {
	float d = abs(x - c);
	float aa = fwidth(x) * 1.2;
	float fill = 1.0 - smoothstep(w - aa, w + aa, d);
	float line = (1.0 - smoothstep(w + o - aa, w + o + aa, d)) - fill;
	return vec2(fill, max(line, 0.0));
}

void vertex() {
	hp = (VERTEX - center) / radii;
}

void fragment() {
	vec3 n = normalize(hp);
	float lat = n.x;          // lateral
	float up = n.y;           // altura
	float fwd = -n.z;         // frente
	float w = abs(lat);
	vec3 col = c1;
	float outline = 0.0;
	if (design < 0.5) {
		// SETAS: "V" apontando para a frente no topo, como nos capacetes dos anos 2000
		float q = fwd + 1.35 * w;
		vec2 a = stripe(q, 0.42, 0.16, 0.035);
		vec2 b = stripe(q, -0.12, 0.1, 0.035);
		vec2 cc = stripe(q, -0.55, 0.06, 0.03);
		float top = smoothstep(-0.25, -0.1, up);
		col = mix(col, c2, a.x * top);
		col = mix(col, c2, b.x * top);
		col = mix(col, c3, cc.x * top);
		outline = (a.y + b.y) * top;
		// queixo na cor principal
		vec2 jaw = stripe(up, -0.85, 0.42, 0.03);
		col = mix(col, c2, jaw.x);
		outline += jaw.y;
	} else if (design < 1.5) {
		// LENDA: base lisa com duas faixas em volta da cabeça logo acima da viseira
		vec2 g = stripe(up, 0.36, 0.11, 0.0);
		vec2 bl = stripe(up, 0.2, 0.045, 0.0);
		col = mix(col, c2, g.x);
		col = mix(col, c3, bl.x);
		// faixas descem um pouco na nuca
		float back = smoothstep(0.2, 0.7, -fwd);
		vec2 g2 = stripe(up + back * 0.18, 0.36, 0.11, 0.0);
		col = mix(col, c2, g2.x * back);
	} else if (design < 2.5) {
		// FAIXA CENTRAL larga com filetes, metade de baixo na segunda cor
		vec2 a = stripe(lat, 0.0, 0.2, 0.04);
		col = mix(col, c2, a.x * step(-0.2, up));
		outline = a.y * step(-0.2, up);
		vec2 lo = stripe(up, -0.8, 0.45, 0.04);
		col = mix(col, c2, lo.x);
		outline += lo.y;
	} else {
		// DIAGONAIS nas laterais
		float q = up * 1.1 + fwd * 0.8;
		vec2 a = stripe(q, 0.1, 0.12, 0.035);
		vec2 b = stripe(q, -0.3, 0.07, 0.03);
		float side = smoothstep(0.15, 0.35, w);
		col = mix(col, c2, a.x * side);
		col = mix(col, c3, b.x * side);
		outline = a.y * side;
	}
	col = mix(col, c3, clamp(outline, 0.0, 1.0));
	// flocos metálicos finos sob o verniz
	float fl = hash(floor(hp.xy * 900.0) + floor(hp.z * 900.0));
	ALBEDO = col * (0.97 + 0.06 * fl);
	ROUGHNESS = 0.22;
	METALLIC = 0.12 + 0.1 * step(0.93, fl);
	CLEARCOAT = 1.0;
	CLEARCOAT_ROUGHNESS = 0.03;
}
