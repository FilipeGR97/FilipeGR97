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
var _launched := false
var _abort_t := 0.0          # desistiu de uma ultrapassagem (porta fechada): fica na cola um tempo
var _start_phase := false    # largada: mantém a coluna do grid até a 1ª frenagem
static var _trace_code := ""
var learn_rate := 0.15       # aprendizado durante a corrida (o grosso vem pré-calculado)
var _learn_i := -1
var _learn_mask := PackedByteArray()   # 0 não visto, 1 limpo, 2 passou do limite, 3 tráfego
var learn_stats := [0, 0, 0]   # eventos: escorregou, fora do traçado, no limite da pista


func _init(p_skill := 0.95) -> void:
	skill = p_skill
	for a in OS.get_cmdline_user_args():
		if a.begins_with("aitrace="):
			_trace_code = a.substr(8)
	_rng.randomize()
	_launch_delay = _rng.randf_range(0.18, 0.38)


func drive(car: Car, dt: float) -> void:
	if car.in_pit():
		drive_pit(car, dt)
		return
	var trk := car.track
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
	if not _launched:
		_launched = true
		if rt >= 0.0 and rt < 5.0:
			_offset = car.lateral - trk.line_off[car.t_idx]
			_offset_target = _offset
			_start_phase = true
	_abort_t = maxf(_abort_t - dt, 0.0)
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
		if fd > 0.0 and fd < 60.0 and _lat_gap(car, _follow_car) < 2.4:
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
			# carro parado/batido à frente e eu já mirando o lado livre: anda devagar enquanto contorna
			# (parado atrás dele não dá para sair de lado — era assim que se formavam engarrafamentos)
			var go_round := absf((trk.line_off[car.t_idx] + _offset_target) - _follow_car.lateral) > 2.4
			if _follow_car.speed < 3.0 and go_round and (fd > 6.2 or _lat_gap(car, _follow_car) > 1.6):
				fcap = maxf(fcap, 3.0)
				_follow_brake = 0.0
			cap = minf(cap, fcap)
	_offset = move_toward(_offset, _offset_target, dt * 2.0)
	# ------------------------------------------------ direção (pure pursuit)
	var look := 5.0 + spd * 0.30
	var ti := trk.idx(car.t_idx + int(look / trk.ds))
	var target := trk.line_point(ti, _offset)
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
	var kap := trk.line_kap_s[trk.idx(car.t_idx + int(spd * 0.12 / trk.ds))]
	var util := clampf(spd * spd * absf(kap) / maxf(trk.lat_cap(spd), 1.0), 0.0, 1.0)
	var alpha_ff := signf(kap) * util * Car.AY_PEAK * 0.35
	var yaw := car.angular_velocity.dot(b.y)
	var delta := ang + alpha_ff
	# não "torce" o volante além do que o pneu dianteiro aguenta (piloto sente a frente)
	var vv := maxf(spd, 1.0)
	var d_max := 3.4 * trk.lat_cap(vv) * 1.03 / (vv * vv) + Car.AY_PEAK * 0.9
	delta = clampf(delta, -d_max, d_max)
	var steer := (delta + beta) / car.max_steer
	steer += yaw * 0.035 * clampf(spd / 30.0, 0.0, 1.0)
	car.in_steer = clampf(steer, -1.0, 1.0)
	# ------------------------------------------------ velocidade
	# O ritmo vem do perfil da pista multiplicado pelo CONHECIMENTO que a IA tem de cada trecho
	# (trk.ai_k, aprendido: onde dá para ir além do perfil conservador da linha guia e onde não dá).
	# Por isso ela não "segue a cor da linha": freia depois e contorna mais rápido onde o carro aguenta.
	var wet_k := lerpf(1.0, 0.72, car.wetness) if Tyres.get_data(car.compound)["slick"] else lerpf(0.86, 0.80, car.wetness)
	var tyre_k := 1.0 - car.avg_wear() * 0.08
	# pneu frio (largada, saída do box) ou superaquecido: o piloto respeita a aderência menor
	var tdat := Tyres.get_data(car.compound)
	var tavg: float = (car.wheels[0].temp + car.wheels[1].temp + car.wheels[2].temp + car.wheels[3].temp) * 0.25
	var dtp: float = (tavg - float(tdat["t_opt"])) / float(tdat["t_win"])
	var temp_g := 1.0 - (0.18 * minf(dtp * dtp, 1.0) if dtp < 0.0 else 0.12 * minf(dtp * dtp, 1.3))
	var vs := skill * pace_mod * wet_k * tyre_k * sqrt(minf(temp_g / 0.97, 1.0)) * sqrt(car.grip_bonus) * cat_k
	var ahead := trk.idx(car.t_idx + int(maxf(spd * 0.18, 2.0) / trk.ds) + 1)
	var i_near := trk.idx(car.t_idx + 1)
	var v_target := trk.speed_prof[ahead] * trk.ai_k[ahead] * vs
	v_target = minf(v_target, trk.speed_prof[i_near] * trk.ai_k[i_near] * vs * 1.05)
	# ataque por dentro: freia um pouco mais tarde para completar a ultrapassagem
	if _attacking and v_target < spd:
		v_target *= 1.0 + 0.035 * aggression
	if absf(_offset) > 1.0:
		var kc := absf(trk.curv[ahead]) * absf(_offset)
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
			_offset_target = -signf(trk.line_off[car.t_idx]) * 2.5
	if _trace_code != "" and Engine.get_physics_frames() % 15 == 0 and (String(car.driver.get("code", "")) == _trace_code or _trace_code == "lento" and spd < 3.0 and rt > 5.0):
		# ferramenta de diagnóstico (arg aitrace=COD): o que a IA vê e por que acelera/freia
		var fc: Car = _follow_car if _follow_car and is_instance_valid(_follow_car) else null
		print("[ia] %s s=%.0f v=%.0f alvo=%.0f cap=%.0f lat=%.1f off=%.1f/%.1f segue=%s d=%.1f dlat=%.1f vseg=%.0f abort=%.1f freio_emerg=%.2f st=%.2f" % [car.driver.get("code", "?"), car.s, spd * 3.6, v_target * 3.6, minf(cap, 999.0) * 3.6, car.lateral, _offset, _offset_target, fc.driver["code"] if fc else "-", _gap(car, fc) if fc else 0.0, _lat_gap(car, fc) if fc else 0.0, fc.speed * 3.6 if fc else 0.0, _abort_t, _follow_brake, car.in_steer])
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
		if _learn_mask.size() != trk.n:
			_learn_mask.resize(trk.n)
			_learn_mask.fill(0)
		@warning_ignore("integer_division")
		if _learn_i >= 0 and car.t_idx < _learn_i - trk.n / 2:
			_end_learning_lap(trk)
		_learn_i = car.t_idx
		var clean_air := cap == INF and absf(_offset) < 0.6 and car.dmg_wing < 0.1 and car.puncture < 0
		if race and race.has_method("speed_cap") and race.speed_cap(car) < 900.0:
			clean_air = false
		if clean_air:
			var slide := absf(car.linear_velocity.dot(rgt)) / spd
			# frente saturada só é erro se o carro de fato abriu a trajetória (em grampo a
			# frente trabalha saturada em qualquer velocidade); traseira saturada = erro sempre
			var e_line := absf(car.lateral - (trk.line_off[car.t_idx] + _offset))
			var worst := maxf(front_util if e_line > 2.0 else 0.0, rear_util)
			var over := worst > 1.4 or slide > 0.14 or absf(car.lateral) > trk.half_width + 0.4
			if learn_rate < 0.5:
				# durante a corrida: só incidentes de verdade (rodada / saiu da pista)
				over = slide > 0.25 or absf(car.lateral) > trk.half_width + 1.0
			if over:
				# passou do limite: alivia a curva toda (entrada/ápice decidem a saída)
				trk.ai_learn(car.t_idx, -0.008 * learn_rate, 45)
				for q in range(-70, 15):
					_learn_mask[trk.idx(car.t_idx + q)] = 2
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
	if racing and (spd < 4.5 or absf(car.lateral) > trk.half_width + 1.2 or car.wrong_way):
		_stuck += dt
		var limit := 3.5 if spd < 4.5 else 6.0
		if _stuck > limit:
			_stuck = 0.0
			_offset = 0.0
			_offset_target = 0.0
			if OS.get_cmdline_user_args().has("impactlog"):
				print("[preso] %s s=%.0f v=%.0f km/h lat=%.1f — recolocado na pista" % [car.driver.get("code", "?"), car.s, spd * 3.6, car.lateral])
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
func _end_learning_lap(trk: Track) -> void:
	for i in trk.n:
		if _learn_mask[i] == 1:
			trk.ai_learn(i, 0.004 * learn_rate)
	_learn_mask.fill(0)


func _update_traffic(car: Car) -> float:
	var trk := car.track
	var cap := INF
	var creep := false          # contornando carro parado: anda devagar em vez de parar atrás dele
	var line := trk.line_off[car.t_idx]
	# trecho à frente é reta? (só tenta ultrapassar em reta / zona de frenagem)
	var straight := true
	for k in range(0, int(140.0 / trk.ds), 5):
		if absf(trk.curv[trk.idx(car.t_idx + k)]) > 1.0 / 350.0:
			straight = false
			break
	# próxima curva de verdade à frente: lado de dentro (+1 direita, -1 esquerda)
	var corner_side := 0.0
	var corner_d := 9999.0
	var corner_i := -1
	for k in range(int(30.0 / trk.ds), int(260.0 / trk.ds), 4):
		var ci := trk.idx(car.t_idx + k)
		var kk := trk.line_kap_s[ci]
		if absf(kk) > 1.0 / 160.0:
			corner_side = signf(kk)
			corner_d = k * trk.ds
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
			# onde o carro da frente VAI estar (quem defende pode estar fechando a porta)
			var o_lat := clampf(ahead.lateral + _lat_rate(ahead) * 0.4, -trk.half_width, trk.half_width)
			var room_left := o_lat - (-trk.half_width + 1.2)
			var room_right := (trk.half_width - 1.2) - o_lat
			const ROOM := 3.0          # largura de um carro + folga: menos que isso não há espaço
			var side := 1.0 if room_right > room_left else -1.0
			# ataque inteligente: prefere o lado de DENTRO da próxima curva, se houver espaço
			if corner_side != 0.0 and corner_d < 200.0:
				var room_in := room_right if corner_side > 0.0 else room_left
				if room_in > 3.2:
					side = corner_side
			if absf(car.lateral - o_lat) > 1.2:
				side = signf(car.lateral - o_lat)
			var room := room_right if side > 0.0 else room_left
			var other_room := room_left if side > 0.0 else room_right
			if room < ROOM and other_room >= ROOM + 0.6 and d > 6.0:
				# fechou um lado mas ainda dá tempo (não emparelhou): tenta pelo outro
				side = -side
				room = other_room
			if ahead.speed > 15.0 and (room < ROOM or _abort_t > 0.0 and room < ROOM + 1.0):
				# porta fechada: não força. Volta para trás dele e fica no vácuo esperando outra chance
				if _abort_t <= 0.0:
					_abort_t = 1.2
				_offset_target = clampf(ahead.lateral - line, -trk.half_width * 0.9 - line, trk.half_width * 0.9 - line)
			else:
				_offset_target = clampf(o_lat + side * 3.0 - line, -trk.half_width * 0.9 - line, trk.half_width * 0.9 - line)
	if ahead and ahead.speed < 4.0 and _gap(car, ahead) < 45.0:
		# carro parado/rodado à frente (também em curva): contorna pelo lado com mais espaço
		var so := ahead.lateral
		var rl := so - (-trk.half_width + 1.2)
		var rr := (trk.half_width - 1.2) - so
		var sd := 1.0 if rr > rl else -1.0
		_offset_target = clampf(so + sd * 3.0 - line, -trk.half_width * 0.92 - line, trk.half_width * 0.92 - line)
		_abort_t = 0.0
		creep = _gap(car, ahead) > 6.2 or _lat_gap(car, ahead) > 1.6
	elif ahead:
		pass
	elif not straight:
		_start_phase = false
		_offset_target = move_toward(_offset_target, 0.0, 0.02)
	elif _start_phase and corner_d > 260.0:
		pass                       # largada: segue na sua coluna, brigando lado a lado até a 1ª frenagem
	else:
		_offset_target = move_toward(_offset_target, 0.0, 0.01 if not _start_phase else 0.025)
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
			if _defending and not in_line and absf(car.lateral - (corner_side * (trk.half_width - 2.2))) > 1.0:
				_defending = false      # ele já foi para o outro lado: mantém a linha (não fecha de novo)
			if _defending or start_ok:
				_defending = true
				var inside := corner_side * (trk.half_width - 2.2)
				_offset_target = clampf(inside - line, -trk.half_width * 0.9 - line, trk.half_width * 0.9 - line)
	# carro lado a lado: mantém espaço
	for o in cars:
		var oc: Car = o
		if oc == car or oc.in_pit():
			continue
		var d2 := _gap(car, oc)
		var dl := absf(oc.lateral - car.lateral)
		if absf(d2) < 5.0 and dl < 2.9 and dl > 0.9:
			var push := signf(car.lateral - oc.lateral)
			var want := oc.lateral + push * 3.1
			_offset_target = clampf(want - line, -trk.half_width * 0.92 - line, trk.half_width * 0.92 - line)
			# sem espaço do lado de fora (muro/limite) e ele está à frente ou emparelhado: cede a posição
			if absf(want) > trk.half_width * 0.92 and d2 > 1.0 and oc.speed > 12.0:
				cap = minf(cap, oc.speed - 2.0)
				_abort_t = maxf(_abort_t, 1.2)
		if d2 > 0.0 and d2 < 6.5 and dl <= 2.2:
			cap = minf(cap, oc.speed - 1.0)
	if creep:
		cap = maxf(cap, 3.0)
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
		if d > 0.0 and d < bd and _lat_gap(car, oc) < max_lat:
			bd = d
			best = oc
	return best


## Velocidade lateral (m/s) do carro em relação à pista (+ = para a direita).
static func _lat_rate(c: Car) -> float:
	return c.linear_velocity.dot(c.track.right[c.t_idx])


## Distância lateral entre os dois carros: a menor entre a de agora e a prevista em 0,4 s
## (assim a IA reage quando o carro da frente começa a fechar a porta, não só depois que fechou).
static func _lat_gap(car: Car, oc: Car) -> float:
	var now := absf(oc.lateral - car.lateral)
	var fut := absf((oc.lateral + _lat_rate(oc) * 0.4) - (car.lateral + _lat_rate(car) * 0.4))
	return minf(now, fut)


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
	var trk := car.track
	var u := trk.pit_u(car.s)
	var box_u: float = trk.box_u[car.team_index]
	var look := 6.0 + car.speed * 0.35
	var ut := u + look
	var lat := trk.pit_path_lateral(ut)
	var target_speed := trk.pit_speed - 0.6
	# fila no box: se o companheiro está na vaga, para atrás dele e espera
	car.pit_wait = false
	if car.pit_state == Car.Pit.STOPPING and race and race.has_method("box_busy") and race.box_busy(car):
		car.pit_wait = true
		box_u -= 9.0
	if car.pit_state == Car.Pit.STOPPING or car.pit_state == Car.Pit.SERVICE:
		var k := clampf(1.0 - (box_u - ut) / 26.0, 0.0, 1.0)
		lat = lerpf(lat, trk.pit_box_off * trk.pit_side, smoothstep(0.0, 1.0, k))
		var rem := box_u - u
		target_speed = clampf(sqrt(maxf(rem, 0.0) * 2.0 * 6.0), 0.0, trk.pit_speed - 0.6)
		if rem < 0.6:
			target_speed = 0.0
	elif car.pit_state == Car.Pit.EXIT:
		var back := clampf(1.0 - (ut - box_u) / 24.0, 0.0, 1.0)
		lat = lerpf(lat, trk.pit_box_off * trk.pit_side, smoothstep(0.0, 1.0, back))
		if u > trk.pit_len - trk.pit_taper * 0.7:
			target_speed = 60.0
	elif u < trk.pit_taper * 0.7:
		target_speed = maxf(trk.pit_speed, 45.0 - u * 0.15)
	# carro parado/atravessado à frente na mesma faixa do box: espera atrás (sem bater)
	for o in cars:
		var oc: Car = o
		if oc == car or oc.speed > 3.0:
			continue
		var d := trk.pit_u(oc.s) - u
		if d > 0.0 and d < 16.0 and absf(oc.lateral - car.lateral) < 2.4 and oc.pit_state != Car.Pit.SERVICE:
			target_speed = minf(target_speed, maxf(d - 8.0, 0.0) * 0.8)
	# preso dentro do box (rodou/bateu, atravessado): recoloca alinhado na faixa
	if car.speed < 1.0 and car.pit_state != Car.Pit.SERVICE and not car.pit_wait and target_speed > 1.0:
		_pit_stuck += dt
		if _pit_stuck > 3.0:
			_pit_stuck = 0.0
			var i := trk.idx_at_s(car.s)
			car.place(trk.frame(i, trk.pit_path_lateral(u) if car.pit_state != Car.Pit.STOPPING else trk.pit_box_off * trk.pit_side, 0.0))
			car.gear = 1
	else:
		_pit_stuck = 0.0
	var target := trk.point_s(car.s + look, lat)
	var b := car.global_transform.basis
	var to := target - car.global_position
	var xr := to.dot(b.x)
	var zf := maxf(to.dot(-b.z), 1.0)
	var ang := atan2(2.0 * 3.4 * xr, xr * xr + zf * zf)
	# Patch 7.2: mesma correção da pilotagem normal — contra-esterço pela deriva e amortecimento da guinada.
	# Sem isso, saindo do box de pneu frio e acelerador cheio, o carro "rabeava" e rodava contra o muro
	# (na categoria Lenda, 100% dos pit stops terminavam em batida logo depois da saída).
	var spd := car.speed
	var lat_v := car.linear_velocity.dot(b.x)
	var lon_v := car.linear_velocity.dot(-b.z)
	var beta := atan2(lat_v, maxf(lon_v, 3.0)) if spd > 5.0 else 0.0
	var yaw := car.angular_velocity.dot(b.y)
	car.in_steer = clampf((ang + beta) / car.max_steer + yaw * 0.035 * clampf(spd / 30.0, 0.0, 1.0), -1.0, 1.0)
	var err := target_speed - spd
	if car.pit_state == Car.Pit.SERVICE:
		car.in_throttle = 0.0
		car.in_brake = 1.0
		car.in_steer = 0.0
		return
	if err > 0.0:
		car.in_throttle = clampf(0.25 + err * 0.3, 0.0, 1.0)
		car.in_brake = 0.0
		# controle de tração "do piloto": pneu frio patinando ou traseira escorregando = alivia o pé
		var rsx := maxf(car.wheels[2].sx, car.wheels[3].sx)
		if rsx > Car.KX_PEAK:
			car.in_throttle *= clampf(1.0 - (rsx - Car.KX_PEAK) / Car.KX_PEAK * 1.5, 0.25, 1.0)
		var rear_util := maxf(absf(car.wheels[2].sy), absf(car.wheels[3].sy)) / Car.AY_PEAK
		if rear_util > 0.6 and spd > 5.0:
			car.in_throttle *= clampf(1.0 - (rear_util - 0.6) * 2.0, 0.1, 1.0)
	else:
		car.in_throttle = 0.0
		car.in_brake = clampf(-err * 0.25, 0.0, 1.0)
	if target_speed <= 0.0:
		car.in_brake = 1.0
	car.want_aero = false
