shader_type sky;
// Céu de foto 360° (metade de cima de um panorama equirretangular CC0 da Poly Haven).
// O panorama é girado para o sol da foto coincidir com a luz direcional do jogo.

uniform sampler2D pano : source_color, filter_linear, repeat_enable;
uniform float sun_u = 0.6;            // coluna (0..1) do sol na foto
uniform float brightness = 1.0;
uniform vec3 tint : source_color = vec3(1.0);
uniform vec3 ground : source_color = vec3(0.30, 0.31, 0.30);
uniform float sun_glow = 1.0;         // brilho extra perto do sol (a foto vem com o sol "estourado")


void sky() {
	vec3 d = EYEDIR;
	vec3 L = LIGHT0_DIRECTION;
	float az = atan(d.x, -d.z);
	float az_l = atan(L.x, -L.z);
	float u = fract(sun_u + (az - az_l) / (2.0 * PI));
	float v = acos(clamp(d.y, 0.0, 1.0)) / (0.5 * PI);   // 0 no zênite, 1 no horizonte
	vec3 col = textureLod(pano, vec2(u, min(v, 0.998)), 0.0).rgb * tint;
	// abaixo do horizonte: emenda com a cor do chão
	col = mix(col, ground, smoothstep(0.0, -0.08, d.y));
	// halo do sol (a foto é LDR, o sol de verdade é muito mais forte)
	float sd = max(dot(d, L), 0.0);
	col += LIGHT0_COLOR * LIGHT0_ENERGY * (pow(sd, 900.0) * 1.5 + pow(sd, 60.0) * 0.08) * sun_glow;
	COLOR = col * brightness;
}
