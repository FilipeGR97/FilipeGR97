class_name Mirrors
extends Node
## Retrovisores do carro do jogador: duas câmeras traseiras de baixa resolução renderizando em texturas
## aplicadas nos espelhos. Só atualizam nas câmeras em 1ª pessoa, em quadros alternados (custo baixo).

const SIZE := Vector2i(300, 110)

var car: Car
var rig: CameraRig
var _vps: Array = []
var _cams: Array = []
var _sides := [-1.0, 1.0]
var _frame := 0


func setup(p_car: Car, p_rig: CameraRig) -> void:
	car = p_car
	rig = p_rig
	for sd in _sides:
		var vp := SubViewport.new()
		vp.size = SIZE
		vp.msaa_3d = Viewport.MSAA_DISABLED
		vp.positional_shadow_atlas_size = 0
		vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		add_child(vp)
		var cam := Camera3D.new()
		cam.fov = 26.0
		cam.near = 0.1
		cam.far = 600.0
		cam.cull_mask = 0xFFFFF & ~CarModel.HIDE_LAYER
		vp.add_child(cam)
		_vps.append(vp)
		_cams.append(cam)
		# tela do espelho (virada para o piloto), imagem espelhada na horizontal
		var quad := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(0.145, 0.05)
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_texture = vp.get_texture()
		m.uv1_scale = Vector3(-1, 1, 1)
		m.uv1_offset = Vector3(1, 0, 0)
		qm.material = m
		quad.mesh = qm
		quad.position = CarModel.G(0.676, 0.735, sd * 0.53)
		quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		car.model.add_child(quad)


func _process(_dt: float) -> void:
	if car == null or rig == null:
		return
	var first_person: bool = rig.view == CameraRig.View.HELMET or rig.view == CameraRig.View.COCKPIT or rig.view == CameraRig.View.TCAM
	_frame += 1
	var xf := car.get_global_transform_interpolated() * car.model.transform
	for i in _vps.size():
		var vp: SubViewport = _vps[i]
		if not first_person:
			vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
			continue
		# alterna os dois espelhos a cada quadro (cada um atualiza a ~30 fps a 60 fps de jogo)
		vp.render_target_update_mode = SubViewport.UPDATE_ONCE if (_frame + i) % 2 == 0 else SubViewport.UPDATE_DISABLED
		var sd: float = _sides[i]
		var pos := xf * CarModel.G(0.70, 0.75, sd * 0.56)
		var basis := xf.basis.orthonormalized().rotated(xf.basis.y.normalized(), PI + sd * 0.10)
		(_cams[i] as Camera3D).global_transform = Transform3D(basis, pos)
