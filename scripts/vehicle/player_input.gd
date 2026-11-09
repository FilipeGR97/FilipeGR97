class_name PlayerInput
extends RefCounted
## Entrada do jogador (teclado / controle / volante) + assistências de pilotagem.

var autopilot := AIDriver.new(1.0)
var _steer := 0.0
var _thr := 0.0
var _brk := 0.0
var enabled := true


func drive(car: Car, dt: float) -> void:
	var st: Dictionary = Game.settings
	car.assists["abs"] = bool(st["abs"])
	car.assists["tc"] = int(st["traction_control"])
	car.assists["auto_gear"] = bool(st["auto_gearbox"])
	car.assists["stab"] = bool(st.get("stability", true))
	if not enabled:
		car.in_throttle = 0.0
		car.in_brake = 1.0
		car.in_steer = 0.0
		return
	# dentro do pit o carro anda sozinho (como nos jogos de F1)
	if car.in_pit():
		autopilot.drive_pit(car, dt)
		return
	var thr := Input.get_action_strength("throttle")
	var brk := Input.get_action_strength("brake")
	var raw := Input.get_axis("steer_left", "steer_right")
	var dz: float = st["steer_deadzone"]
	var lin: float = st["steer_linearity"]
	var mag := maxf(absf(raw) - dz, 0.0) / (1.0 - dz)
	raw = signf(raw) * pow(mag, lin)
	var digital := _is_digital()
	if digital:
		# teclado: rampas suaves
		# teclado: acelerador progressivo (0 -> 100% em ~0,5 s), freio rápido
		_thr = move_toward(_thr, thr, dt * (2.2 if thr > _thr else 10.0))
		_brk = move_toward(_brk, brk, dt * (6.0 if brk > _brk else 12.0))
		var rate := 2.2 if absf(raw) > absf(_steer) and signf(raw) == signf(_steer) else 5.0
		_steer = move_toward(_steer, raw, dt * rate)
	else:
		_thr = thr
		_brk = brk
		_steer = raw
	var steer := _steer
	var b := car.global_transform.basis
	if bool(st["steering_assist"]):
		# esterço ideal: no máximo o ângulo que os pneus dianteiros aguentam nesta velocidade
		var v := maxf(car.speed, 1.0)
		var a_lat := 1.55 * (9.81 + 0.003 * v * v)
		var ideal := 3.4 * a_lat / (v * v) + 0.09
		var lim := clampf(ideal / car.max_steer, 0.12, 1.0)
		steer *= lim
	if bool(st.get("stability", true)) and car.speed > 8.0 and car.v_long > 0.0:
		# contra-esterço automático quando a traseira escapa
		var slide := car.linear_velocity.dot(b.x) / car.speed
		if absf(slide) > 0.03:
			steer += (slide - signf(slide) * 0.03) * 1.6
	# freio automático (segue o perfil da linha ideal) — assistência opcional
	car.auto_braking = false
	if bool(st.get("auto_brake", false)) and car.v_long > 5.0:
		var tr := car.track
		var ahead := tr.idx(car.t_idx + int(maxf(car.speed * 0.2, 2.0) / tr.ds) + 1)
		var wet_k := lerpf(1.0, 0.75, car.wetness) if Tyres.get_data(car.compound)["slick"] else 0.85
		var target := tr.speed_prof[ahead] * 0.96 * wet_k
		if car.speed > target + 0.5:
			var ab := clampf((car.speed - target) * 0.3, 0.0, 1.0)
			if ab > _brk:
				_brk = ab
				_thr = minf(_thr, 0.0)
				car.auto_braking = true
	car.in_throttle = _thr
	car.in_brake = _brk
	car.in_steer = steer
	if car.launch_hold:
		return
	# marchas manuais
	if not bool(st["auto_gearbox"]):
		if Input.is_action_just_pressed("gear_up"):
			car.shift_up()
		if Input.is_action_just_pressed("gear_down"):
			car.shift_down()
	# asa móvel (modo reta)
	if bool(st["auto_aero"]):
		car.want_aero = car.aero_available and absf(steer) < 0.3
	else:
		if Input.is_action_just_pressed("aero_mode"):
			car.want_aero = not car.aero_open
		if not car.aero_available:
			car.want_aero = false
	if Input.is_action_just_pressed("overtake") and car.overtake_ready:
		car.overtake_active = true
		car.overtake_ready = false
		car.overtake_energy = 500000.0
	if Input.is_action_just_pressed("ers_mode"):
		car.ers_mode = (car.ers_mode + 1) % 3
	if Input.is_action_just_pressed("bias_fwd"):
		car.brake_bias = minf(car.brake_bias + 0.01, 0.65)
	if Input.is_action_just_pressed("bias_rear"):
		car.brake_bias = maxf(car.brake_bias - 0.01, 0.5)
	if Input.is_action_just_pressed("pit_request"):
		car.request_pit(car.pit_state == Car.Pit.NONE)


func _is_digital() -> bool:
	return Input.get_connected_joypads().is_empty()
