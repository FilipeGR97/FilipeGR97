class_name AIDriver
extends RefCounted
## Piloto controlado pelo computador: segue o traçado ideal com perfil de velocidade,
## desvia/ultrapassa carros à frente, usa asa móvel e ERS, e faz a estratégia de pit.
## Também é usado como "piloto automático" do jogador dentro do pit lane.

var skill := 0.95          # fração do limite usada (0.85 .. 1.0)
var aggression := 0.5
var cars: Array = []       # lista de todos os carros (para desvio)
var race                   # referência ao controlador da corrida (pode ser null)
var planned_stop_lap := -1
var planned_compound := "hard"

var _offset := 0.0
var _offset_target := 0.0
var _stuck := 0.0
var _rng := RandomNumberGenerator.new()
var _mistake := 0.0
var _launch_delay := 0.0
var _think := 0.0
var _cap := INF
var _gap_car: Car = null
var _strat_t := 0.0


func _init(p_skill := 0.95) -> void:
	skill = p_skill
	_rng.randomize()
	_launch_delay = _rng.randf_range(0.18, 0.38)


func drive(car: Car, dt: float) -> void:
	if car.in_pit():
		drive_pit(car, dt)
		return
	var tr := car.track
	var spd := car.speed
	# ------------------------------------------------ largada
	if car.launch_hold:
		car.in_throttle = 0.72
		car.in_brake = 0.0
		car.in_steer = 0.0
		return
	if _launch_delay > 0.0 and race and race.has_method("race_time") and race.race_time() < _launch_delay:
		car.in_throttle = 0.0
		car.in_brake = 1.0
		return
	# ------------------------------------------------ desvio de tráfego
	# decisões de tráfego a ~20 Hz (economiza CPU com 20 carros)
	_think -= dt
	if _think <= 0.0:
		_think = 0.05
		_cap = _update_traffic(car)
		_gap_car = _car_ahead(car, 25.0, 2.2)
	var cap := _cap
	_offset = move_toward(_offset, _offset_target, dt * 2.0)
	# ------------------------------------------------ direção (pure pursuit)
	var look := 7.0 + spd * 0.42
	var ti := tr.idx(car.t_idx + int(look / tr.ds))
	var target := tr.line_point(ti, _offset)
	var to := target - car.global_position
	var b := car.global_transform.basis
	var fwd := -b.z
	var rgt := b.x
	var xr := to.dot(rgt)
	var zf := maxf(to.dot(fwd), 1.0)
	var ld2 := xr * xr + zf * zf
	var ang := atan2(2.0 * 3.4 * xr, ld2)
	# amortecimento de guinada / contra-esterço
	var lat_v := car.linear_velocity.dot(rgt)
	var yaw := car.angular_velocity.dot(b.y)
	var steer := ang / car.max_steer
	steer += yaw * 0.035 * clampf(spd / 30.0, 0.0, 1.0)
	if spd > 8.0:
		var slide := lat_v / spd
		steer += slide * 0.9
	car.in_steer = clampf(steer, -1.0, 1.0)
	# ------------------------------------------------ velocidade
	var ahead := tr.idx(car.t_idx + int(maxf(spd * 0.18, 2.0) / tr.ds) + 1)
	var wet_k := lerpf(1.0, 0.72, car.wetness) if Tyres.get_data(car.compound)["slick"] else lerpf(0.86, 0.80, car.wetness)
	var tyre_k := 1.0 - car.avg_wear() * 0.08
	var v_target := tr.speed_prof[ahead] * skill * wet_k * tyre_k
	v_target = minf(v_target, tr.speed_prof[tr.idx(car.t_idx + 1)] * skill * wet_k * 1.05)
	if absf(_offset) > 1.0:
		var kc := absf(tr.curv[ahead]) * absf(_offset)
		v_target *= clampf(1.0 - kc * 1.2, 0.85, 0.99)
	v_target -= _mistake
	_mistake = maxf(_mistake - dt * 2.0, 0.0)
	# distância de segurança para o carro da frente
	v_target = minf(v_target, cap)
	var gap_car := _gap_car
	var err := v_target - spd
	if err > 0.0:
		car.in_throttle = clampf(0.35 + err * 0.35, 0.0, 1.0)
		car.in_brake = 0.0
	else:
		car.in_throttle = clampf(0.3 + err * 0.4, 0.0, 1.0)
		car.in_brake = clampf(-err * 0.3 - 0.05, 0.0, 1.0)
	# controle de tração "do piloto": alivia se a traseira escorrega de lado
	var rear_util := maxf(absf(car.wheels[2].sy), absf(car.wheels[3].sy)) / Car.AY_PEAK
	if rear_util > 0.75 and spd > 5.0:
		car.in_throttle *= clampf(1.0 - (rear_util - 0.75) * 1.6, 0.15, 1.0)
	# ------------------------------------------------ asa móvel e ERS
	car.want_aero = car.aero_available and absf(car.in_steer) < 0.3
	if car.overtake_ready and not car.overtake_active and gap_car == null:
		var near := _car_ahead(car, 60.0, 50.0)
		if near:
			car.overtake_active = true
			car.overtake_ready = false
			car.overtake_energy = 500000.0
	car.ers_mode = 1 if car.soc > 1.2e6 else 0
	if car.soc > 3.2e6:
		car.ers_mode = 2
	# erro ocasional (pilotos menos habilidosos erram mais)
	if _rng.randf() < dt * (1.0 - skill) * 0.08:
		_mistake = _rng.randf_range(1.0, 4.0)
	# ------------------------------------------------ carro preso / rodou
	if spd < 2.0 and race and race.has_method("is_racing") and race.is_racing():
		_stuck += dt
		if _stuck > 3.5:
			_stuck = 0.0
			car.reset_to_track()
	else:
		_stuck = 0.0
	# ------------------------------------------------ estratégia (1 Hz)
	_strat_t -= dt
	if _strat_t <= 0.0:
		_strat_t = 1.0
		_strategy(car)


func _update_traffic(car: Car) -> float:
	var tr := car.track
	var cap := INF
	var line := tr.line_off[car.t_idx]
	# trecho à frente é reta? (só tenta ultrapassar em reta / zona de frenagem)
	var straight := true
	for k in range(0, int(140.0 / tr.ds), 5):
		if absf(tr.curv[tr.idx(car.t_idx + k)]) > 1.0 / 350.0:
			straight = false
			break
	var ahead := _car_ahead(car, 70.0, 2.4)
	if ahead:
		var d := _gap(car, ahead)
		var safe := 5.0 + car.speed * 0.11
		if d < safe + 20.0:
			cap = ahead.speed + (d - safe) * 0.7
		var closing := car.speed - ahead.speed
		if straight and (closing > 0.3 or d < safe + 6.0):
			var o_lat := ahead.lateral
			var room_left := o_lat - (-tr.half_width + 1.2)
			var room_right := (tr.half_width - 1.2) - o_lat
			var side := 1.0 if room_right > room_left else -1.0
			if absf(car.lateral - o_lat) > 1.2:
				side = signf(car.lateral - o_lat)
			_offset_target = clampf(o_lat + side * 3.0 - line, -tr.half_width * 0.9 - line, tr.half_width * 0.9 - line)
	elif not straight:
		_offset_target = move_toward(_offset_target, 0.0, 0.02)
	else:
		_offset_target = move_toward(_offset_target, 0.0, 0.01)
	# carro lado a lado: mantém espaço
	for o in cars:
		var oc: Car = o
		if oc == car or oc.in_pit():
			continue
		var d2 := _gap(car, oc)
		var dl := absf(oc.lateral - car.lateral)
		if absf(d2) < 5.0 and dl < 2.9 and dl > 0.9:
			var push := signf(car.lateral - oc.lateral)
			_offset_target = clampf(oc.lateral + push * 3.1 - line, -tr.half_width * 0.92 - line, tr.half_width * 0.92 - line)
		if d2 > 0.0 and d2 < 6.5 and dl <= 2.2:
			cap = minf(cap, oc.speed - 1.0)
	return cap


func _gap(car: Car, other: Car) -> float:
	var d := other.s - car.s
	var L := car.track.length
	if d < -L * 0.5:
		d += L
	elif d > L * 0.5:
		d -= L
	return d


func _car_ahead(car: Car, max_d: float, max_lat: float) -> Car:
	var best: Car = null
	var bd := max_d
	for o in cars:
		var oc: Car = o
		if oc == car or oc.in_pit():
			continue
		var d := _gap(car, oc)
		if d > 0.0 and d < bd and absf(oc.lateral - car.lateral) < max_lat:
			bd = d
			best = oc
	return best


func _strategy(car: Car) -> void:
	if race == null or not race.has_method("laps_total"):
		return
	if car.pit_state != Car.Pit.NONE:
		return
	var lap: int = race.car_lap(car)
	var total: int = race.laps_total()
	if total <= 0:
		return
	var laps_left := total - lap
	var best_tyre := Tyres.best_for(car.wetness)
	var tyre_ok := bool(Tyres.get_data(car.compound)["slick"]) == (best_tyre == "medium") or best_tyre == car.compound
	var must := false
	if not tyre_ok and laps_left >= 1:
		must = true
		car.next_compound = best_tyre if best_tyre != "medium" else "medium"
	elif car.max_wear() > 0.78 and laps_left >= 2:
		must = true
		car.next_compound = "hard" if laps_left > 18 else ("medium" if laps_left > 8 else "soft")
	elif planned_stop_lap > 0 and lap >= planned_stop_lap and laps_left >= 1:
		must = true
		car.next_compound = planned_compound
	elif race.mandatory_compounds() and car.compounds_used.size() < 2 and bool(Tyres.get_data(car.compound)["slick"]) and laps_left == 1:
		must = true
		car.next_compound = "soft" if car.compound != "soft" else "medium"
	if must and race.car_progress_in_lap(car) > 0.5:
		car.request_pit(true)
		planned_stop_lap = -1


# ======================================================================= pit lane (piloto automático)
func drive_pit(car: Car, dt: float) -> void:
	var tr := car.track
	var u := tr.pit_u(car.s)
	var box_u: float = tr.box_u[car.team_index]
	var look := 6.0 + car.speed * 0.35
	var ut := u + look
	var lat := tr.pit_path_lateral(ut)
	var target_speed := tr.pit_speed - 0.6
	if car.pit_state == Car.Pit.STOPPING or car.pit_state == Car.Pit.SERVICE:
		var k := clampf(1.0 - (box_u - ut) / 26.0, 0.0, 1.0)
		lat = lerpf(lat, tr.pit_box_off * tr.pit_side, smoothstep(0.0, 1.0, k))
		var rem := box_u - u
		target_speed = clampf(sqrt(maxf(rem, 0.0) * 2.0 * 6.0), 0.0, tr.pit_speed - 0.6)
		if rem < 0.6:
			target_speed = 0.0
	elif car.pit_state == Car.Pit.EXIT:
		var back := clampf(1.0 - (ut - box_u) / 24.0, 0.0, 1.0)
		lat = lerpf(lat, tr.pit_box_off * tr.pit_side, smoothstep(0.0, 1.0, back))
		if u > tr.pit_len - Track.PIT_TAPER * 0.7:
			target_speed = 60.0
	elif u < Track.PIT_TAPER * 0.7:
		target_speed = maxf(tr.pit_speed, 45.0 - u * 0.15)
	var target := tr.point_s(car.s + look, lat)
	var b := car.global_transform.basis
	var to := target - car.global_position
	var xr := to.dot(b.x)
	var zf := maxf(to.dot(-b.z), 1.0)
	var ang := atan2(2.0 * 3.4 * xr, xr * xr + zf * zf)
	car.in_steer = clampf(ang / car.max_steer, -1.0, 1.0)
	var err := target_speed - car.speed
	if car.pit_state == Car.Pit.SERVICE:
		car.in_throttle = 0.0
		car.in_brake = 1.0
		car.in_steer = 0.0
		return
	if err > 0.0:
		car.in_throttle = clampf(0.25 + err * 0.3, 0.0, 1.0)
		car.in_brake = 0.0
	else:
		car.in_throttle = 0.0
		car.in_brake = clampf(-err * 0.25, 0.0, 1.0)
	if target_speed <= 0.0:
		car.in_brake = 1.0
	car.want_aero = false
