class_name CameraRig
extends Camera3D
## Câmeras: cockpit (olhos do piloto, com halo), T-cam, bico, perseguição perto/longe e TV (beira da pista).

enum View { HELMET, COCKPIT, TCAM, NOSE, CHASE, CHASE_FAR, TV }
const NAMES := ["Atrás do piloto", "Olhos do piloto", "T-Cam", "Bico", "Perseguição", "Perseguição (longe)", "TV"]

var target: Car
var track: Track
var view := View.HELMET
var look_back := false
var _chase_pos := Vector3.ZERO
var _chase_dir := Vector3.FORWARD
var _head := Vector3.ZERO
var _shake_t := 0.0
var _tv_idx := -1
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	doppler_tracking = Camera3D.DOPPLER_TRACKING_IDLE_STEP
	# a câmera é posicionada a cada frame a partir do transform já interpolado do carro
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	near = 0.04
	far = 6000.0
	current = true


func set_target(car: Car, snap := true) -> void:
	target = car
	if snap and car:
		_chase_pos = car.global_position + car.global_transform.basis.z * 7.0 + Vector3.UP * 2.0
		_chase_dir = -car.global_transform.basis.z


func next_view() -> void:
	view = ((view + 1) % View.size()) as View
	Game.settings["camera"] = view


func _process(dt: float) -> void:
	if target == null or not is_instance_valid(target):
		return
	var xf := target.get_global_transform_interpolated()
	var b := xf.basis
	var mxf := xf * target.model.transform
	var spd := target.speed
	# câmera do cockpit esconde o próprio capacete
	cull_mask = 0xFFFFF & ~CarModel.HIDE_LAYER if (view == View.COCKPIT and target.is_player) else 0xFFFFF
	var fov_set: float = Game.settings["fov"]
	match view:
		View.HELMET, View.COCKPIT, View.TCAM, View.NOSE:
			var local := CarModel.EYE
			if view == View.HELMET:
				local = CarModel.HELMETCAM
			if view == View.TCAM:
				local = CarModel.TCAM
			elif view == View.NOSE:
				local = CarModel.NOSECAM
			# cabeça balança com as forças G
			var g := target.g_force
			var head_target := Vector3(clampf(-g.x * 0.012, -0.05, 0.05), clampf(-g.y * 0.004, -0.02, 0.02), clampf(g.z * 0.01, -0.04, 0.04)) if view <= View.COCKPIT else Vector3.ZERO
			_head = _head.lerp(head_target, minf(dt * 6.0, 1.0))
			var pos := mxf * (local + _head)
			var basis := mxf.basis.orthonormalized()
			if look_back:
				basis = basis.rotated(basis.y, PI)
			# vibração
			_shake_t += dt
			var kerb := 0.0
			for w in target.wheels:
				var wh: Car.Wheel = w
				if wh.grounded and wh.surface != Track.Surface.ASPHALT:
					kerb = 1.0
			var amp := (0.0006 * clampf(spd / 90.0, 0.0, 1.0) + 0.004 * kerb * clampf(spd / 30.0, 0.0, 1.0)) * (1.0 if view <= View.COCKPIT else 0.5)
			pos += basis.y * sin(_shake_t * 61.0) * amp + basis.x * sin(_shake_t * 47.0) * amp * 0.6
			global_transform = Transform3D(basis, pos)
			if view == View.COCKPIT:
				rotate_object_local(Vector3.RIGHT, -0.035)
			elif view == View.HELMET:
				rotate_object_local(Vector3.RIGHT, -0.15)
			fov = fov_set + (0.0 if view <= View.COCKPIT else 6.0)
		View.CHASE, View.CHASE_FAR:
			var dist := 6.2 if view == View.CHASE else 10.0
			var hgt := 1.75 if view == View.CHASE else 3.0
			var fwd := -b.z
			if look_back:
				fwd = -fwd
			_chase_dir = _chase_dir.slerp(fwd, minf(dt * 5.0, 1.0)).normalized()
			var flat := Vector3(_chase_dir.x, 0.0, _chase_dir.z).normalized()
			var want := xf.origin - flat * dist + Vector3.UP * hgt
			_chase_pos = _chase_pos.lerp(want, minf(dt * 12.0, 1.0))
			global_position = _chase_pos
			look_at(xf.origin + flat * 3.0 + Vector3.UP * 0.7, Vector3.UP)
			fov = 62.0 + clampf(spd / 90.0, 0.0, 1.0) * 8.0
		View.TV:
			if track == null:
				return
			var best := -1
			var bd := INF
			for i in track.tv_cams.size():
				var p: Vector3 = track.tv_cams[i]
				var d := p.distance_squared_to(xf.origin)
				if d < bd:
					bd = d
					best = i
			if best != _tv_idx:
				_tv_idx = best
			var cp: Vector3 = track.tv_cams[_tv_idx]
			global_position = cp
			look_at(xf.origin + Vector3.UP * 0.6, Vector3.UP)
			var dd := sqrt(bd)
			fov = clampf(rad_to_deg(2.0 * atan(9.0 / maxf(dd, 1.0))), 4.0, 55.0)
