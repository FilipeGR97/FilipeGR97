class_name Weather
extends Node3D
## Iluminação, céu, neblina, pós-processamento e chuva. Também aplica o preset gráfico.

const PRESETS := [
	{"name": "Baixo", "msaa": Viewport.MSAA_DISABLED, "scale": 0.8, "shadow": 2048, "shadow_dist": 180.0, "ssao": false, "ssr": false, "glow": false, "rain": 1500},
	{"name": "Médio", "msaa": Viewport.MSAA_2X, "scale": 1.0, "shadow": 4096, "shadow_dist": 260.0, "ssao": true, "ssr": false, "glow": true, "rain": 3000},
	{"name": "Alto", "msaa": Viewport.MSAA_4X, "scale": 1.0, "shadow": 4096, "shadow_dist": 360.0, "ssao": true, "ssr": true, "glow": true, "rain": 5000},
	{"name": "Ultra", "msaa": Viewport.MSAA_8X, "scale": 1.0, "shadow": 8192, "shadow_dist": 480.0, "ssao": true, "ssr": true, "glow": true, "rain": 8000},
]

var kind := 0                  # 0 seco, 1 chuva leve, 2 chuva forte
var wetness := 0.0
var rain := 0.0
var env: Environment
var sun: DirectionalLight3D
var world_env: WorldEnvironment
var sky_mat: ShaderMaterial
var rain_fx: GPUParticles3D
var follow: Node3D


static func wetness_for(k: int) -> float:
	return [0.0, 0.45, 0.85][clampi(k, 0, 2)]


func setup(p_kind: int, quality: int) -> void:
	kind = p_kind
	wetness = wetness_for(kind)
	rain = [0.0, 0.45, 1.0][clampi(kind, 0, 2)]
	var q: Dictionary = PRESETS[clampi(quality, 0, 3)]
	# ---------------- céu
	sky_mat = ShaderMaterial.new()
	sky_mat.shader = load("res://shaders/sky.gdshader")
	sky_mat.set_shader_parameter("cloud_cover", [0.42, 0.88, 1.0][kind])
	sky_mat.set_shader_parameter("cloud_dark", [0.0, 0.45, 0.75][kind])
	sky_mat.set_shader_parameter("brightness", [1.0, 0.7, 0.5][kind])
	if kind > 0:
		sky_mat.set_shader_parameter("zenith", Color(0.32, 0.36, 0.42))
		sky_mat.set_shader_parameter("horizon", Color(0.55, 0.58, 0.62))
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	# ---------------- ambiente
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = [1.0, 1.1, 1.2][kind]
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = [1.0, 1.15, 1.3][kind]
	env.tonemap_white = 6.0
	env.ssao_enabled = q["ssao"]
	env.ssao_radius = 1.2
	env.ssao_intensity = 1.6
	env.ssr_enabled = q["ssr"]
	env.ssr_max_steps = 48
	env.glow_enabled = q["glow"]
	env.glow_intensity = 0.5
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.2
	env.fog_enabled = true
	env.fog_light_color = Color(0.68, 0.74, 0.82) if kind == 0 else Color(0.5, 0.53, 0.57)
	env.fog_density = [0.00035, 0.0016, 0.0035][kind]
	env.fog_aerial_perspective = 0.6
	env.fog_sky_affect = 0.15
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.06
	env.adjustment_saturation = [1.12, 0.92, 0.85][kind]
	world_env = WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)
	# ---------------- sol
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42.0, -35.0, 0.0)
	sun.light_energy = [1.35, 0.55, 0.3][kind]
	sun.light_color = Color(1.0, 0.96, 0.9)
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = q["shadow_dist"]
	sun.shadow_blur = 1.5 if kind == 0 else 3.0
	sun.shadow_bias = 0.03
	sun.light_angular_distance = 0.5
	add_child(sun)
	RenderingServer.directional_shadow_atlas_set_size(int(q["shadow"]), true)
	var vp := get_viewport()
	if vp:
		vp.msaa_3d = q["msaa"]
		vp.scaling_3d_scale = q["scale"]
	# ---------------- chuva
	if rain > 0.0:
		_make_rain(int(q["rain"]))


func _make_rain(amount: int) -> void:
	rain_fx = GPUParticles3D.new()
	rain_fx.amount = int(amount * rain)
	rain_fx.lifetime = 1.1
	rain_fx.local_coords = false
	rain_fx.visibility_aabb = AABB(Vector3(-40, -40, -40), Vector3(80, 80, 80))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(35, 2, 35)
	pm.direction = Vector3(0.05, -1, 0.02)
	pm.spread = 2.0
	pm.initial_velocity_min = 26.0
	pm.initial_velocity_max = 32.0
	pm.gravity = Vector3(0, -9.8, 0)
	pm.particle_flag_align_y = true
	rain_fx.process_material = pm
	var qm := QuadMesh.new()
	qm.size = Vector2(0.015, 0.55)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.8, 0.85, 0.95, 0.28)
	m.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	m.billboard_keep_scale = true
	qm.material = m
	rain_fx.draw_pass_1 = qm
	add_child(rain_fx)


func _process(_dt: float) -> void:
	if rain_fx and follow:
		rain_fx.global_position = follow.global_position + Vector3(0, 14, 0)


## Spray atrás de um carro na pista molhada.
static func make_spray() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 48
	p.lifetime = 0.9
	p.local_coords = false
	p.emitting = false
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(0.8, 0.1, 0.2)
	pm.direction = Vector3(0, 0.4, 1)
	pm.spread = 25.0
	pm.initial_velocity_min = 4.0
	pm.initial_velocity_max = 9.0
	pm.gravity = Vector3(0, -2.0, 0)
	pm.scale_min = 1.0
	pm.scale_max = 2.6
	pm.damping_min = 2.0
	pm.damping_max = 4.0
	var curve := CurveTexture.new()
	var c := Curve.new()
	c.add_point(Vector2(0, 0.3))
	c.add_point(Vector2(0.3, 1.0))
	c.add_point(Vector2(1, 1.6))
	curve.curve = c
	pm.scale_curve = curve
	var grad := Gradient.new()
	grad.set_color(0, Color(0.85, 0.87, 0.9, 0.35))
	grad.set_color(1, Color(0.85, 0.87, 0.9, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_ramp = gt
	p.process_material = pm
	var qm := QuadMesh.new()
	qm.size = Vector2(1.4, 1.0)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.albedo_texture = _soft_dot()
	qm.material = m
	p.draw_pass_1 = qm
	return p


static func _soft_dot() -> ImageTexture:
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		for x in 64:
			var d := Vector2(x - 31.5, y - 31.5).length() / 32.0
			var a := clampf(1.0 - d, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a * a))
	return ImageTexture.create_from_image(img)
