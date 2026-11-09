shader_type spatial;
// Pintura do carro: padrão definido pela posição no espaço do modelo (x frente, y cima, z lateral -> Godot: -z frente).
// Cores por instância para que todos os carros compartilhem a mesma malha.
render_mode blend_mix, cull_disabled;

instance uniform vec3 primary : source_color = vec3(0.85, 0.05, 0.08);
instance uniform vec3 secondary : source_color = vec3(0.95, 0.95, 0.95);
instance uniform vec3 accent : source_color = vec3(0.08, 0.08, 0.1);
instance uniform float pattern = 0.0;
uniform float clay = 0.0;

varying vec3 lp;

void vertex() {
	lp = VERTEX;
}

void fragment() {
	float fx = -lp.z;          // eixo para frente
	float y = lp.y;
	float z = abs(lp.x);
	vec3 c = primary;
	// faixa diagonal na lateral (secundária)
	float s = fx * 0.42 + y * 1.25;
	if (pattern < 0.5) {
		if (s > 0.95 && s < 1.16 && fx < 1.3) c = secondary;
		if (s >= 1.16 && s < 1.22 && fx < 1.3) c = accent;
	} else if (pattern < 1.5) {
		if (fx < 0.0 && y > 0.55) c = secondary;
		if (abs(fx - 0.0) < 0.05 && y > 0.5) c = accent;
	} else {
		if (y < 0.48 + 0.04 * fx) c = secondary;
	}
	// parte de baixo e assoalho em fibra
	if (y < 0.32 + 0.04 * fx && fx < 1.35) c = vec3(0.025);
	// bico com ponta na cor de destaque
	if (fx > 2.55) c = accent;
	// faixa central na tampa do motor
	if (z < 0.018 && y > 0.6 && fx < 0.0) c = accent;
	c = mix(c, vec3(0.72), clay);
	ALBEDO = c;
	ROUGHNESS = 0.32;
	METALLIC = 0.15;
	CLEARCOAT = 1.0;
	CLEARCOAT_ROUGHNESS = 0.06;
}
