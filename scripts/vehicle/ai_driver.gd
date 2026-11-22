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
var _follow_car: Car = null
var _follow_brake := 0.0
var _strat_t := 0.0
var cat_k := 1.0             # ajuste de ritmo da categoria (conhecimento treinado no F1 2026)
var pace_mod := 1.0          # variação de ritmo volta a volta (consistência do piloto)
var _lap_seen := -1
var _pit_stuck := 0.0
var _braking := false
var _attacking := false
var _defending := false
var _def_corner := -1
var _def_roll := 1.0
var _can_defend := not OS.get_cmdline_user_args().has("nodefend")
var learn_rate := 0.15       # aprendizado durante a corrida (o grosso vem pré-calculado)
var _learn_i := -1
var _learn_mask := PackedByteArray()   # 0 não visto, 1 limpo, 2 passou do limite, 3 tráfego
var learn_stats := [0, 0, 0]   # eventos: escorregou, fora do traçado, no limite da pista


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
	var rt: float = race.race_time() if race and race.has_method("race_time") else 99.0
	if car.launch_hold and rt < 0.0:
		# semáforo aceso: motor cheio, carro seguro
		car.in_throttle = 0.72
		car.in_brake = 0.0
		car.in_steer = 0.0
		return
	if _launch_delay > 0.0 and rt >= 0.0 and rt < _launch_delay:
		# tempo de reação: segura o carro com o motor cheio (não deixa o giro cair)
		car.launch_hold = true
		car.in_throttle = 0.72
		car.in_brake = 0.0
		return
	car.launch_hold = false
	# ------------------------------------------------ desvio de tráfego
	# decisões de tráfego a ~20 Hz (economiza CPU com 20 carros)
	_think -= dt
	if _think <= 0.0:
		_think = 0.05
		_cap = _update_traffic(car)
		_gap_car = _car_ahead(car, 25.0, 2.2)
	var cap := _cap
	_follow_brake = 0.0
	# carro da frente na mesma linha: distância de segurança recalculada A CADA PASSO
	# (a 5 g de frenagem o líder perde 2,5 m/s entre duas decisões de tráfego)
	if _follow_car and is_instance_valid(_follow_car) and not _follow_car.in_pit():
		var fd := _gap(car, _follow_car)
		if fd > 0.0 and fd < 60.0 and absf(_follow_car.lateral - car.lateral) < 2.4:
			# na chuva freia-se menos: distância maior e reação mais cedo
			# carro que freia menos (chuva, pouca asa: lenda/elétrico) precisa de mais distância
			var brk_k := sqrt(clampf(car.cla_z / 4.0, 0.3, 1.3)) * car.mu0 / 1.8
			var wetf := (1.0 + 0.7 * car.wetness) / clampf(brk_k, 0.5, 1.1)
			# primeira volta (pelotão embolado, pneu frio): mais cautela
			if race and race.has_method("race_time") and race.race_time() < 35.0:
				wetf *= 1.45
			var safe := (5.0 + spd * 0.11) * wetf
			var fcap := _follow_car.speed + (fd - safe) * 0.7
			# o da frente está freando: antecipa (como o piloto que vê a luz de freio)
			fcap -= _follow_car.in_brake * 4.0
			# aproximação rápida: freia o necessário para não encostar
			var closing := spd - _follow_car.speed
			if closing > 0.0:
				var a_req := closing * closing / (2.0 * maxf(fd - 2.5, 0.3))
				if a_req * wetf > 6.0:
					fcap = minf(fcap, _follow_car.speed - 1.0)
				if a_req * wetf > 10.0:
					_follow_brake = clampf(a_req * wetf / 35.0, 0.3, 1.0)
			cap = minf(cap, fcap)
	_offset = move_toward(_offset, _offset_target, dt * 2.0)
	# ------------------------------------------------ direção (pure pursuit)
	var look := 5.0 + spd * 0.30
	var ti := tr.idx(car.t_idx + int(look / tr.ds))
	var target := tr.line_point(ti, _offset)
	var to := target - car.global_position
	var b := car.global_transform.basis
	var fwd := -b.z
	var rgt := b.x
	var lat_v := car.linear_velocity.dot(rgt)
	var lon_v := car.linear_velocity.dot(fwd)
	# perseguição pura no referencial da VELOCIDADE (para onde o carro vai de fato)
	var beta := atan2(lat_v, maxf(lon_v, 3.0)) if spd > 5.0 else 0.0
	var vf := fwd.rotated(b.y, -beta)
	var vr := rgt.rotated(b.y, -beta)
	var xr := to.dot(vr)
	var zf := maxf(to.dot(vf), 1.0)
	var ld2 := xr * xr + zf * zf
	var ang := atan2(2.0 * 3.4 * xr, ld2)
	# volta ao referencial do chassi + ângulo de deriva que o pneu dianteiro precisa para
	# gerar a força lateral da curva (sem isso o carro "abre" no limite)
	var kap := tr.line_kap_s[tr.idx(car.t_idx + int(spd * 0.12 / tr.ds))]
	var util := clampf(spd * spd * absf(kap) / maxf(tr.lat_cap(spd), 1.0), 0.0, 1.0)
	var alpha_ff := signf(kap) * util * Car.AY_PEAK * 0.35
	var yaw := car.angular_velocity.dot(b.y)
	var delta := ang + alpha_ff
	# não "torce" o volante além do que o pneu dianteiro aguenta (piloto sente a frente)
	var vv := maxf(spd, 1.0)
	var d_max := 3.4 * tr.lat_cap(vv) * 1.03 / (vv * vv) + Car.AY_PEAK * 0.9
	delta = clampf(delta, -d_max, d_max)
	var steer := (delta + beta) / car.max_steer
	steer += yaw * 0.035 * clampf(spd / 30.0, 0.0, 1.0)
	car.in_steer = clampf(steer, -1.0, 1.0)
	# ------------------------------------------------ velocidade
	# O ritmo vem do perfil da pista multiplicado pelo CONHECIMENTO que a IA tem de cada trecho
	# (tr.ai_k, aprendido: onde dá para ir além do perfil conservador da linha guia e onde não dá).
	# Por isso ela não "segue a cor da linha": freia depois e contorna mais rápido onde o carro aguenta.
	var wet_k := lerpf(1.0, 0.72, car.wetness) if Tyres.get_data(car.compound)["slick"] else lerpf(0.86, 0.80, car.wetness)
	var tyre_k := 1.0 - car.avg_wear() * 0.08
	# pneu frio (largada, saída do box) ou superaquecido: o piloto respeita a aderência menor
	var tdat := Tyres.get_data(car.compound)
	var tavg: float = (car.wheels[0].temp + car.wheels[1].temp + car.wheels[2].temp + car.wheels[3].temp) * 0.25
	var dtp: float = (tavg - float(tdat["t_opt"])) / float(tdat["t_win"])
	var temp_g := 1.0 - (0.18 * minf(dtp * dtp, 1.0) if dtp < 0.0 else 0.12 * minf(dtp * dtp, 1.3))
	var vs := skill * pace_mod * wet_k * tyre_k * sqrt(minf(temp_g / 0.97, 1.0)) * sqrt(car.grip_bonus) * cat_k
	var ahead := tr.idx(car.t_idx + int(maxf(spd * 0.18, 2.0) / tr.ds) + 1)
	var i_near := tr.idx(car.t_idx + 1)
	var v_target := tr.speed_prof[ahead] * tr.ai_k[ahead] * vs
	v_target = minf(v_target, tr.speed_prof[i_near] * tr.ai_k[i_near] * vs * 1.05)
	# ataque por dentro: freia um pouco mais tarde para completar a ultrapassagem
	if _attacking and v_target < spd:
		v_target *= 1.0 + 0.035 * aggression
	if absf(_offset) > 1.0:
		var kc := absf(tr.curv[ahead]) * absf(_offset)
		v_target *= clampf(1.0 - kc * 1.2, 0.85, 0.99)
	v_target -= _mistake
	_mistake = maxf(_mistake - dt * 2.0, 0.0)
	# distância de segurança para o carro da frente
	v_target = minf(v_target, cap)
	# dano: pneu furado = devagar até o box; asa quebrada = alivia conforme o dano
	if car.puncture >= 0:
		v_target *= 0.55
	v_target *= 1.0 - 0.15 * car.dmg_wing
	# bandeiras: VSC (limite de ritmo), amarela (cautela), azul (deixa o líder passar)
	if race and race.has_method("speed_cap"):
		v_target = minf(v_target, race.speed_cap(car))
		if race.yellow_at(car.s):
			v_target *= 0.93
		if car.blue_flag:
			v_target *= 0.95
			_offset_target = -signf(tr.line_off[car.t_idx]) * 2.5
	var gap_car := _gap_car
	var err := v_target - spd
	if err > 0.0:
		car.in_throttle = clampf(0.35 + err * 0.35, 0.0, 1.0)
		car.in_brake = 0.0
	else:
		car.in_throttle = clampf(0.3 + err * 0.4, 0.0, 1.0)
		car.in_brake = clampf(-err * 0.3 - 0.05, 0.0, 1.0)
	# frenagem de emergência para não encostar no carro da frente
	if _follow_brake > 0.0:
		car.in_throttle = 0.0
		car.in_brake = maxf(car.in_brake, _follow_brake)
	_braking = car.in_brake > 0.1
	# controle de tração "do piloto": alivia se a traseira escorrega de lado
	var rear_util := maxf(absf(car.wheels[2].sy), absf(car.wheels[3].sy)) / Car.AY_PEAK
	var front_util := maxf(absf(car.wheels[0].sy), absf(car.wheels[1].sy)) / Car.AY_PEAK
	if rear_util > 0.75 and spd > 5.0:
		car.in_throttle *= clampf(1.0 - (rear_util - 0.75) * 1.6, 0.15, 1.0)
	# saindo de frente com acelerador: alivia para a frente voltar a morder
	if front_util > 1.1 and spd > 10.0 and not _braking:
		car.in_throttle *= clampf(1.0 - (front_util - 1.1) * 1.2, 0.35, 1.0)
	# ------------------------------------------------ aprendizado da pista
	# a cada amostra percorrida: escorregou/saiu do traçado = alivia a entrada desta curva;
	# passou limpo = tenta um pouco mais rápido na próxima volta (todos os pilotos compartilham)
	if learn_rate > 0.0 and car.t_idx != _learn_i and car.wetness < 0.1 and spd > 12.0:
		if _learn_mask.size() != tr.n:
			_learn_mask.resize(tr.n)
			_learn_mask.fill(0)
		if _learn_i >= 0 and car.t_idx < _learn_i - tr.n / 2:
			_end_learning_lap(tr)
		_learn_i = car.t_idx
		var clean_air := cap == INF and absf(_offset) < 0.6 and car.dmg_wing < 0.1 and car.puncture < 0
		if race and race.has_method("speed_cap") and race.speed_cap(car) < 900.0:
			clean_air = false
		if clean_air:
			var slide := absf(car.linear_velocity.dot(rgt)) / spd
			# frente saturada só é erro se o carro de fato abriu a trajetória (em grampo a
			# frente trabalha saturada em qualquer velocidade); traseira saturada = erro sempre
			var e_line := absf(car.lateral - (tr.line_off[car.t_idx] + _offset))
			var worst := maxf(front_util if e_line > 2.0 else 0.0, rear_util)
			var over := worst > 1.4 or slide > 0.14 or absf(car.lateral) > tr.half_width + 0.4
			if learn_rate < 0.5:
				# durante a corrida: só incidentes de verdade (rodada / saiu da pista)
				over = slide > 0.25 or absf(car.lateral) > tr.half_width + 1.0
			if over:
				# passou do limite: alivia a curva toda (entrada/ápice decidem a saída)
				tr.ai_learn(car.t_idx, -0.008 * learn_rate, 45)
				for q in range(-70, 15):
					_learn_mask[tr.idx(car.t_idx + q)] = 2
				learn_stats[0 if worst > 1.4 or slide > 0.14 else 2] += 1
			elif _learn_mask[car.t_idx] == 0:
				_learn_mask[car.t_idx] = 1
		elif _learn_mask[car.t_idx] == 0:
			_learn_mask[car.t_idx] = 3
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
	# ------------------------------------------------ carro preso / rodou / perdido fora da pista
	var racing: bool = race != null and race.has_method("is_racing") and race.is_racing()
	if racing and (spd < 4.5 or absf(car.lateral) > tr.half_width + 1.2 or car.wrong_way):
		_stuck += dt
		var limit := 3.5 if spd < 4.5 else 6.0
		if _stuck > limit:
			_stuck = 0.0
			_offset = 0.0
			_offset_target = 0.0
			car.reset_to_track()
	else:
		_stuck = maxf(_stuck - dt * 2.0, 0.0)
	# ------------------------------------------------ estratégia (1 Hz)
	_strat_t -= dt
	if _strat_t <= 0.0:
		_strat_t = 1.0
		if car.tyre_laps != _lap_seen:
			_lap_seen = car.tyre_laps
			pace_mod = 1.0 + _rng.randf_range(-0.005, 0.004)
		_strategy(car)


## Fim de volta: trechos percorridos limpos (sem escorregar perto) ficam um pouco mais rápidos.
func _end_learning_lap(tr: Track) -> void:
	for i in tr.n:
		if _learn_mask[i] == 1:
			tr.ai_learn(i, 0.004 * learn_rate)
	_learn_mask.fill(0)


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
	# próxima curva de verdade à frente: lado de dentro (+1 direita, -1 esquerda)
	var corner_side := 0.0
	var corner_d := 9999.0
	var corner_i := -1
	for k in range(int(30.0 / tr.ds), int(260.0 / tr.ds), 4):
		var ci := tr.idx(car.t_idx + k)
		var kk := tr.line_kap_s[ci]
		if absf(kk) > 1.0 / 160.0:
			corner_side = signf(kk)
			corner_d = k * tr.ds
			corner_i = ci
			break
	_attacking = false
	var ahead := _car_ahead(car, 70.0, 2.4)
	_follow_car = ahead
	if ahead:
		var d := _gap(car, ahead)
		var safe := (5.0 + car.speed * 0.11) * (1.0 + 0.7 * car.wetness) / clampf(sqrt(clampf(car.cla_z / 4.0, 0.3, 1.3)) * car.mu0 / 1.8, 0.5, 1.1)
		if race and race.has_method("race_time") and race.race_time() < 35.0:
			safe *= 1.45
		if d < safe + 20.0:
			cap = ahead.speed + (d - safe) * 0.7
		var closing := car.speed - ahead.speed
		if straight and (closing > 0.3 or d < safe + 6.0):
			var o_lat := ahead.lateral
			var room_left := o_lat - (-tr.half_width + 1.2)
			var room_right := (tr.half_width - 1.2) - o_lat
			var side := 1.0 if room_right > room_left else -1.0
			# ataque inteligente: prefere o lado de DENTRO da próxima curva, se houver espaço
			if corner_side != 0.0 and corner_d < 200.0:
				var room_in := room_right if corner_side > 0.0 else room_left
				if room_in > 3.2:
					side = corner_side
			if absf(car.lateral - o_lat) > 1.2:
				side = signf(car.lateral - o_lat)
			_offset_target = clampf(o_lat + side * 3.0 - line, -tr.half_width * 0.9 - line, tr.half_width * 0.9 - line)
	elif not straight:
		_offset_target = move_toward(_offset_target, 0.0, 0.02)
	else:
		_offset_target = move_toward(_offset_target, 0.0, 0.01)
	# já está por dentro e emparelhado com quem vai à frente: freia mais tarde para completar
	var beside := _car_ahead(car, 14.0, 4.0)
	if beside and corner_side != 0.0 and corner_d < 160.0 and (car.lateral - beside.lateral) * corner_side > 1.3:
		_attacking = true
	# defesa: alguém colado atrás antes de uma frenagem -> fecha a porta por dentro (um movimento só)
	if corner_i != _def_corner:
		_def_corner = corner_i
		_def_roll = _rng.randf()
		_defending = false
	if _can_defend and ahead == null and not car.blue_flag and corner_side != 0.0 and corner_d < 230.0 and straight:
		var behind := _car_behind(car, 30.0, 4.5)
		if behind and not behind.blue_flag:
			var gapb := -_gap(car, behind)
			var closing_b := behind.speed - car.speed
			# regra de pilotagem: só fecha a porta com o rival logo atrás e ainda na mesma linha;
			# se ele já mudou de lado ou está perto demais, mudar de trajetória seria "fechar" (batida)
			var in_line := absf(behind.lateral - car.lateral) < 1.4
			var safe_gap := gapb > 6.0 + maxf(closing_b, 0.0) * 0.8
			var start_ok := in_line and safe_gap and (closing_b > 0.8 or gapb < 14.0) and _def_roll < aggression
			if _defending and not in_line and absf(car.lateral - (corner_side * (tr.half_width - 2.2))) > 1.0:
				_defending = false      # ele já foi para o outro lado: mantém a linha (não fecha de novo)
			if _defending or start_ok:
				_defending = true
				var inside := corner_side * (tr.half_width - 2.2)
				_offset_target = clampf(inside - line, -tr.half_width * 0.9 - line, tr.half_width * 0.9 - line)
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


func _car_behind(car: Car, max_d: float, max_lat: float) -> Car:
	var best: Car = null
	var bd := max_d
	for o in cars:
		var oc: Car = o
		if oc == car or oc.in_pit():
			continue
		var d := -_gap(car, oc)
		if d > 0.0 and d < bd and absf(oc.lateral - car.lateral) < max_lat:
			bd = d
			best = oc
	return best


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
	if (car.dmg_wing > 0.45 or car.puncture >= 0) and laps_left >= 1:
		must = true
		if car.next_compound == "":
			car.next_compound = car.compound
	elif not tyre_ok and laps_left >= 1:
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
	if must and (race.car_progress_in_lap(car) > 0.5 or car.dmg_wing > 0.45 or car.puncture >= 0):
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
	# fila no box: se o companheiro está na vaga, para atrás dele e espera
	car.pit_wait = false
	if car.pit_state == Car.Pit.STOPPING and race and race.has_method("box_busy") and race.box_busy(car):
		car.pit_wait = true
		box_u -= 9.0
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
		if u > tr.pit_len - tr.pit_taper * 0.7:
			target_speed = 60.0
	elif u < tr.pit_taper * 0.7:
		target_speed = maxf(tr.pit_speed, 45.0 - u * 0.15)
	# carro parado/atravessado à frente na mesma faixa do box: espera atrás (sem bater)
	for o in cars:
		var oc: Car = o
		if oc == car or oc.speed > 3.0:
			continue
		var d := tr.pit_u(oc.s) - u
		if d > 0.0 and d < 16.0 and absf(oc.lateral - car.lateral) < 2.4 and oc.pit_state != Car.Pit.SERVICE:
			target_speed = minf(target_speed, maxf(d - 8.0, 0.0) * 0.8)
	# preso dentro do box (rodou/bateu, atravessado): recoloca alinhado na faixa
	if car.speed < 1.0 and car.pit_state != Car.Pit.SERVICE and not car.pit_wait and target_speed > 1.0:
		_pit_stuck += dt
		if _pit_stuck > 3.0:
			_pit_stuck = 0.0
			var i := tr.idx_at_s(car.s)
			car.place(tr.frame(i, tr.pit_path_lateral(u) if car.pit_state != Car.Pit.STOPPING else tr.pit_box_off * tr.pit_side, 0.0))
			car.gear = 1
	else:
		_pit_stuck = 0.0
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
