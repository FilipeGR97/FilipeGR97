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
		_thr = move_toward(_thr, thr, dt * (6.0 if thr > _thr else 10.0))
		_brk = move_toward(_brk, brk, dt * (7.0 if brk > _brk else 12.0))
		var rate := 2.6 if absf(raw) > absf(_steer) and signf(raw) == signf(_steer) else 5.0
		_steer = move_toward(_steer, raw, dt * rate)
	else:
		_thr = thr
		_brk = brk
		_steer = raw
	var steer := _steer
	if bool(st["steering_assist"]):
		# reduz o esterço máximo com a velocidade (o carro tem 21° de esterço nas rodas)
		var lim := clampf(1.0 - (car.speed - 15.0) / 85.0, 0.32, 1.0)
		steer *= lim
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
