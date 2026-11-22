shader_type spatial;
// Pintura do carro: padrão definido pela posição no espaço do modelo (x frente, y cima, z lateral -> Godot: -z frente).
// Cores por instância para que todos os carros compartilhem a mesma malha.
// As bordas entre cores são suavizadas (sem serrilhado) com fwidth.
render_mode blend_mix, cull_disabled;

instance uniform vec3 primary : source_color = vec3(0.85, 0.05, 0.08);
instance uniform vec3 secondary : source_color = vec3(0.95, 0.95, 0.95);
instance uniform vec3 accent : source_color = vec3(0.08, 0.08, 0.1);
instance uniform float pattern = 0.0;
instance uniform float metal = 0.0;     // pintura metálica (prata)
uniform float clay = 0.0;

varying vec3 lp;

void vertex() {
	lp = VERTEX;
}

// 1 quando x < a (borda suave)
float lt(float x, float a) {
	float w = fwidth(x) * 0.8 + 1e-5;
	return 1.0 - smoothstep(a - w, a + w, x);
}
float gt(float x, float a) {
	return 1.0 - lt(x, a);
}
float inr(float x, float a, float b) {
	return gt(x, a) * lt(x, b);
}

void fragment() {
	float fx = -lp.z;          // eixo para frente
	float y = lp.y;
	float z = abs(lp.x);
	vec3 c = primary;
	float s = fx * 0.42 + y * 1.25;
	if (pattern < 0.5) {
		// faixa diagonal na lateral (secundária) com filete na cor de destaque
		float front = lt(fx, 1.3);
		c = mix(c, secondary, inr(s, 0.95, 1.16) * front);
		c = mix(c, accent, inr(s, 1.16, 1.22) * front);
	} else if (pattern < 1.5) {
		c = mix(c, secondary, lt(fx, 0.0) * gt(y, 0.55));
		c = mix(c, accent, lt(abs(fx), 0.05) * gt(y, 0.5));
	} else if (pattern < 2.5) {
		c = mix(c, secondary, lt(y, 0.48 + 0.04 * fx));
	} else {
		// homenagem anos 80: branco em cima, vermelho em baixo com a "seta" no sidepod
		c = secondary;
		c = mix(c, primary, lt(y - 0.03 * fx, 0.47));
		float arrow = gt(z, 0.22) * inr(fx, -0.9, 0.7) * lt(y + abs(fx + 0.1) * 0.22, 0.62);
		c = mix(c, primary, arrow);
	}
	// filete fino na cor de destaque acompanhando a borda do cockpit/tampa do motor
	float pin = inr(y, 0.705, 0.715) * inr(fx, -1.2, 1.6) * gt(z, 0.1);
	c = mix(c, accent, pin * (1.0 - step(2.5, pattern)));
	// parte de baixo e assoalho em fibra
	float floor_m = lt(y, 0.32 + 0.04 * fx) * lt(fx, 1.35);
	c = mix(c, vec3(0.025), floor_m);
	// bico com ponta na cor de destaque
	c = mix(c, accent, gt(fx, 2.55));
	// faixa central na tampa do motor
	c = mix(c, accent, lt(z, 0.018) * gt(y, 0.6) * lt(fx, 0.0));
	c = mix(c, vec3(0.72), clay);
	ALBEDO = c;
	ROUGHNESS = mix(mix(0.32, 0.22, metal), 0.5, floor_m);
	METALLIC = mix(mix(0.15, 0.85, metal), 0.1, floor_m);
	CLEARCOAT = 1.0 - floor_m * 0.7;
	CLEARCOAT_ROUGHNESS = 0.06;
}
