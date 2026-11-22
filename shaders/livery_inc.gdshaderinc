// Lógica da pintura (Patch 7): usada pelo carro procedural (livery.gdshader) e pelos modelos 3D
// externos (ext_paint.gdshader). lp = posição no espaço do carro (frente -Z), ln = normal no mesmo espaço.
// Devolve a cor; floor_m = 1 no assoalho/fundo (fibra escura).

instance uniform vec3 primary : source_color = vec3(0.85, 0.05, 0.08);
instance uniform vec3 secondary : source_color = vec3(0.95, 0.95, 0.95);
instance uniform vec3 accent : source_color = vec3(0.08, 0.08, 0.1);
instance uniform float pattern = 0.0;
instance uniform float finish = 0.0;
instance uniform float metal = 0.0;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}

// bordas suaves (sem serrilhado)
float lt(float x, float a) {
	float w = fwidth(x) * 0.8 + 1e-5;
	return 1.0 - smoothstep(a - w, a + w, x);
}
float gt(float x, float a) { return 1.0 - lt(x, a); }
float inr(float x, float a, float b) { return gt(x, a) * lt(x, b); }

// pontos em grade (meio-tom): raio cresce com t (0..1). uv em metros.
float halftone(vec2 uv, float cell, float t) {
	vec2 g = fract(uv / cell) - 0.5;
	float r = clamp(t, 0.0, 1.0) * 0.62;
	float d = length(g);
	float w = fwidth(d) + 1e-4;
	return 1.0 - smoothstep(r - w, r + w, d);
}

// estrela de 3 pontas (tipo emblema) em grade, tamanho com t
float stars(vec2 uv, float cell, float t) {
	vec2 g = fract(uv / cell) - 0.5;
	float a = atan(g.y, g.x);
	float r = length(g);
	float arm = 0.18 + 0.32 * pow(abs(cos(1.5 * a)), 12.0);
	float s = arm * clamp(t, 0.0, 1.0) * 1.2;
	float w = fwidth(r) + 1e-4;
	return 1.0 - smoothstep(s - w, s + w, r);
}

vec3 livery_paint(vec3 lp, vec3 ln, out float floor_m, out vec2 suv) {
	float fx = -lp.z;
	float y = lp.y;
	float z = abs(lp.x);
	vec3 n = normalize(ln);
	// coordenadas de superfície: lateral usa (fx, y); topo usa (fx, z)
	suv = abs(n.x) > 0.6 ? vec2(fx, y) : vec2(fx, z);
	vec3 c = primary;
	float sty = pattern;
	if (sty < 0.5) {
		// FAIXA DIAGONAL com filete
		float s = fx * 0.42 + y * 1.25;
		float front = lt(fx, 1.3);
		c = mix(c, secondary, inr(s, 0.95, 1.16) * front);
		c = mix(c, accent, inr(s, 1.16, 1.22) * front);
	} else if (sty < 1.5) {
		// LÂMINAS: base escura, bloco angular no sidepod/tampa na cor de destaque com borda secundária,
		// bico com ponta secundária
		float q = fx * 0.9 - y * 1.6 + z * 0.4;
		float blade = inr(q, -1.45, -0.55) * inr(fx, -1.6, 0.9) * gt(y, 0.36);
		float edge = (inr(q, -1.55, -1.45) + inr(q, -0.55, -0.45)) * inr(fx, -1.6, 0.9) * gt(y, 0.36);
		c = mix(c, accent, blade);
		c = mix(c, secondary, edge);
		c = mix(c, secondary, gt(fx, 2.35) * lt(fx, 2.55));
		// faixa fina secundária ao longo do topo do sidepod
		c = mix(c, secondary, inr(y, 0.585, 0.6) * inr(fx, -0.9, 0.6) * gt(z, 0.3));
	} else if (sty < 2.5) {
		// ESTRELAS: preto com campo de estrelas prateadas que some de trás para a frente,
		// e "lâmina" de destaque ao longo do sidepod
		float t = clamp((-fx + 0.4) / 2.2, 0.0, 1.0);
		float st = stars(suv * vec2(1.0, 1.0), 0.07, t * 1.1);
		c = mix(c, secondary, st * gt(y, 0.33));
		float sw = inr(fx * 0.25 + y * 1.7, 1.02, 1.07) * inr(fx, -0.8, 1.9) * gt(z, 0.12);
		c = mix(c, accent, sw);
		c = mix(c, secondary, gt(fx, 2.45));
	} else if (sty < 3.5) {
		// HOMENAGEM ANOS 80: branco em cima, cor em baixo com a "seta" no sidepod
		c = secondary;
		c = mix(c, primary, lt(y - 0.03 * fx, 0.47));
		float arrow = gt(z, 0.22) * inr(fx, -0.9, 0.7) * lt(y + abs(fx + 0.1) * 0.22, 0.62);
		c = mix(c, primary, arrow);
	} else if (sty < 4.5) {
		// DUAS CORES: em cima primária, embaixo secundária, filete de destaque na divisa
		float cut = 0.5 + 0.035 * fx;
		c = mix(secondary, primary, gt(y, cut));
		c = mix(c, accent, inr(y, cut - 0.012, cut + 0.012) * lt(fx, 2.6));
	} else if (sty < 5.5) {
		// PRETO E DOURADO: base escura com filetes dourados acompanhando a carroceria
		c = primary;
		float p1 = inr(y, 0.56, 0.572) * inr(fx, -1.9, 2.4);
		float p2 = inr(y, 0.36, 0.37) * inr(fx, -1.2, 1.0) * gt(z, 0.3);
		float p3 = inr(fx, 2.2, 2.27);
		c = mix(c, secondary, clamp(p1 + p2 + p3, 0.0, 1.0));
	} else if (sty < 6.5) {
		// DEGRADÊ DE PONTOS: primária na frente vira secundária atrás por meio-tom
		float t = clamp((0.8 - fx) / 2.6, 0.0, 1.0);
		float ht = halftone(suv, 0.045, t);
		c = mix(primary, secondary, max(ht, step(0.98, t)));
		c = mix(c, accent, inr(fx * 0.3 + y, 0.82, 0.85) * lt(fx, 2.0));
	} else {
		// FAIXAS DE CANTO: branco, faixas de destaque (fluorescente) no sidepod e bico, parte de baixo preta
		c = primary;
		c = mix(c, accent, inr(fx * 0.55 + y * 1.0, 0.68, 0.8) * inr(fx, -1.5, 1.2) * gt(z, 0.15));
		c = mix(c, accent, inr(fx, 1.9, 2.3) * gt(y, 0.45));
		c = mix(c, secondary, lt(y, 0.42 + 0.03 * fx));
	}
	// parte de baixo e assoalho em fibra
	floor_m = lt(y, 0.32 + 0.04 * fx) * lt(fx, 1.35);
	c = mix(c, vec3(0.025), floor_m);
	// faixa central na tampa do motor (exceto estilos com tampa própria)
	if (sty < 0.5 || (sty > 3.5 && sty < 4.5)) {
		c = mix(c, accent, lt(z, 0.018) * gt(y, 0.6) * lt(fx, 0.0));
	}
	return c;
}
