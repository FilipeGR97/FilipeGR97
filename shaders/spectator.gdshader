shader_type spatial;
// Público: cor da camiseta vem de cada instância (INSTANCE_CUSTOM); pele/calça vêm da cor do vértice.
render_mode cull_back;

varying vec3 shirt;

void vertex() {
	shirt = INSTANCE_CUSTOM.rgb;
}

void fragment() {
	ALBEDO = mix(shirt, COLOR.rgb, COLOR.a);
	ROUGHNESS = 0.9;
}
