class_name Mirrors
extends Node
## Retrovisores do carro do jogador: UMA câmera traseira grande-angular renderizada TODO quadro numa
## textura; cada espelho mostra a sua metade (esquerda/direita), espelhada. Assim a imagem é fluida
## (sem "atraso") e custa uma única renderização extra por quadro.

const SIZE := Vector2i(640, 120)
const OWN_LAYER := 1 << 18          # malhas do próprio carro (o espelho não as enxerga)
## câmeras em que os espelhos aparecem na tela
const VIEWS := [CameraRig.View.HELMET, CameraRig.View.COCKPIT, CameraRig.View.TCAM, CameraRig.View.CLASSIC]

var car: Car
var rig: CameraRig
var _vp: SubViewport
var _cam: Camera3D


func setup(p_car: Car, p_rig: CameraRig) -> void:
	car = p_car
	rig = p_rig
	_vp = SubViewport.new()
	_vp.size = SIZE
	_vp.msaa_3d = Viewport.MSAA_DISABLED
	_vp.positional_shadow_atlas_size = 0
	_vp.mesh_lod_threshold = 8.0        # imagem pequena: malhas bem simplificadas
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_vp)
	_cam = Camera3D.new()
	_cam.keep_aspect = Camera3D.KEEP_WIDTH
	_cam.fov = 62.0                     # horizontal: cobre os dois lados de trás
	_cam.near = 0.1
	_cam.far = 700.0
	_cam.cull_mask = 0xFFFFF & ~CarModel.HIDE_LAYER & ~OWN_LAYER
	# o próprio carro não precisa de interpolação aqui: a posição é copiada a cada quadro
	_cam.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_vp.add_child(_cam)
	for sd in [-1.0, 1.0]:
		# tela do espelho (virada para o piloto). A câmera olha para trás, então o lado esquerdo do
		# carro aparece na metade direita da imagem; cada espelho pega a sua metade, invertida.
		var quad := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(0.145, 0.05)
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_texture = _vp.get_texture()
		m.uv1_scale = Vector3(-0.5, 1, 1)
		m.uv1_offset = Vector3(1.0 if sd < 0.0 else 0.5, 0, 0)
		qm.material = m
		quad.mesh = qm
		var mp: Vector3 = car.model.mirror_pos
		quad.position = Vector3(sd * mp.x, mp.y, mp.z)
		quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		car.model.add_child(quad)
	_own_layer(car.model)


func _process(_dt: float) -> void:
	if car == null or rig == null or _vp == null:
		return
	var on: bool = rig.view in VIEWS and not rig.look_back
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED
	if not on:
		return
	# mesma transformação interpolada que a câmera principal usa (sem defasagem entre as duas)
	var xf := car.get_global_transform_interpolated() * car.model.transform
	var pos := xf * (CarModel.G(0.6, 0.86, 0.0) + car.model.cam_off)
	var basis := xf.basis.orthonormalized().rotated(xf.basis.y.normalized(), PI)
	_cam.global_transform = Transform3D(basis, pos)
	# um pouco para baixo, como um espelho de verdade enxerga a pista atrás
	_cam.rotate_object_local(Vector3.RIGHT, -0.05)


## O espelho fica no centro do carro: sem isso a tomada de ar e a asa tampariam a imagem.
func _own_layer(n: Node) -> void:
	if n is VisualInstance3D:
		var vi := n as VisualInstance3D
		if vi.layers != CarModel.HIDE_LAYER:
			vi.layers = OWN_LAYER
	for ch in n.get_children():
		_own_layer(ch)
