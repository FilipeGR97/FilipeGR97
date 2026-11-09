extends Node
## Bateria de cenários de estresse para caçar bugs de física/controle.
## godot --headless --path . --fixed-fps 120 res://tests/scenarios.tscn  [-- only=nome]
##
## Cada cenário coloca o carro do jogador numa situação extrema e um "piloto de teclado" tenta se recuperar
## (inclusive usando a ré). Invariantes checados o tempo todo:
##  - nada vira NaN; velocidade < 400 km/h; pneu <= 140 °C
##  - roda não dispara (velocidade da roda muito acima da do carro por muito tempo)
##  - depois de recuperar: anda para frente na pista sem rodar

var track: Track
var car: Car
var other: Car
var results: Array = []
var queue: Array = []
var cur: Dictionary = {}
var t := 0.0
var stuck_t := 0.0
var rev_t := 0.0
var recovered_at := -1.0
var spins := 0
var runaway_t := 0.0
var max_temp := 0.0
var fails: Array = []
var prev_s := 0.0
var progress := 0.0
var saved_settings := {}

const SCENARIOS := [
	{"name": "muro_frontal_200", "s": 300.0, "lat": 5.5, "yaw": -40.0, "v": 200.0},
	{"name": "muro_raspao_250", "s": 250.0, "lat": 5.0, "yaw": -12.0, "v": 250.0},
	{"name": "brita_150", "s": 560.0, "lat": 3.0, "yaw": 0.0, "v": 170.0, "no_brake": 2.5},
	{"name": "grama_200", "s": 1300.0, "lat": 4.0, "yaw": 15.0, "v": 200.0},
	{"name": "de_costas_parado", "s": 200.0, "lat": 0.0, "yaw": 180.0, "v": 0.0},
	{"name": "de_lado_parado", "s": 200.0, "lat": 2.0, "yaw": 90.0, "v": 0.0},
	{"name": "queda_3m", "s": 400.0, "lat": 0.0, "yaw": 0.0, "v": 80.0, "h": 3.0},
	{"name": "capotado", "s": 400.0, "lat": 0.0, "yaw": 0.0, "v": 0.0, "roll": 180.0},
	{"name": "zebras_alta_vel", "s": 640.0, "lat": 0.0, "yaw": 0.0, "v": 150.0, "kerb": true},
	{"name": "chuva_com_slick", "s": 0.0, "lat": 0.0, "yaw": 0.0, "v": 100.0, "wet": 0.85, "time": 45.0},
	{"name": "sem_assistencias", "s": 0.0, "lat": 0.0, "yaw": 0.0, "v": 100.0, "noassist": true, "time": 45.0},
	{"name": "cambio_manual_re", "s": 200.0, "lat": 0.0, "yaw": 0.0, "v": 0.0, "manual": true, "time": 25.0},
	{"name": "batida_traseira_ia", "s": 200.0, "lat": 0.0, "yaw": 0.0, "v": 120.0, "rear_hit": true},
	{"name": "box_do_jogador", "s": 4350.0, "lat": 0.0, "yaw": 0.0, "v": 200.0, "pit": true, "time": 50.0},
]


func _ready() -> void:
	saved_settings = Game.settings.duplicate()
	track = Track.new()
	add_child(track)
	track.build(Tracks.get_data("serra_azul"), 0.0, 0)
	var only := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("only="):
			only = a.substr(5)
	for sc in SCENARIOS:
		if only == "" or String(sc["name"]).contains(only):
			queue.append(sc)
	_next()


func _next() -> void:
	for a in ["throttle", "brake", "steer_left", "steer_right", "gear_up", "gear_down", "reset_car", "pit_request"]:
		Input.action_release(a)
	if car:
		car.queue_free()
		car = null
	if other:
		other.queue_free()
		other = null
	if queue.is_empty():
		_report()
		return
	cur = queue.pop_front()
	Game.settings = saved_settings.duplicate()
	if cur.get("noassist", false):
		Game.settings["abs"] = false
		Game.settings["traction_control"] = 0
		Game.settings["stability"] = false
		Game.settings["steering_assist"] = false
	if cur.get("manual", false):
		Game.settings["auto_gearbox"] = false
	t = 0.0
	stuck_t = 0.0
	rev_t = 0.0
	recovered_at = -1.0
	spins = 0
	runaway_t = 0.0
	max_temp = 0.0
	fails = []
	car = Car.new()
	add_child(car)
	car.setup(0, Teams.team(0)["drivers"][0], track, true)
	car.set_fuel(20.0)
	car.wetness = float(cur.get("wet", 0.0))
	car.controller = PlayerInput.new()
	var i := track.idx_at_s(float(cur["s"]))
	var f := track.frame(i, float(cur["lat"]), float(cur.get("h", 0.0)))
	f.basis = f.basis.rotated(f.basis.y, deg_to_rad(-float(cur["yaw"])))
	if cur.has("roll"):
		f.basis = f.basis.rotated(f.basis.z, deg_to_rad(float(cur["roll"])))
		f.origin += Vector3.UP * 1.0
	car.place(f)
	car.global_position += Vector3.UP * float(cur.get("h", 0.0))
	car.linear_velocity = -f.basis.z * float(cur["v"]) / 3.6
	for w in car.wheels:
		(w as Car.Wheel).omega = float(cur["v"]) / 3.6 / 0.36
	car.gear = clampi(int(float(cur["v"]) / 40.0) + 1, 1, 8)
	if cur.get("rear_hit", false):
		other = Car.new()
		add_child(other)
		other.setup(1, Teams.team(1)["drivers"][0], track, false)
		var ai := AIDriver.new(1.0)
		ai.cars = [car, other]
		other.controller = ai
		var fo := track.frame(track.idx(i - 25), 0.3, 0.0)
		other.place(fo)
		other.linear_velocity = -fo.basis.z * 230.0 / 3.6
		for w in other.wheels:
			(w as Car.Wheel).omega = 230.0 / 3.6 / 0.36
		other.gear = 7
		other.set_meta("ramming", true)
	prev_s = car.s
	progress = 0.0


func _press(a: String, on: bool) -> void:
	if on:
		Input.action_press(a)
	else:
		Input.action_release(a)


func _fail(msg: String) -> void:
	var key := msg.split(" (")[0]
	for f in fails:
		if String(f).begins_with(key):
			return
	fails.append(msg)


func _physics_process(dt: float) -> void:
	if car == null or cur.is_empty():
		return
	t += dt
	var dur := float(cur.get("time", 30.0))
	# ---------------- invariantes
	var p := car.global_position
	if is_nan(p.x) or is_nan(p.y) or is_nan(car.linear_velocity.x) or is_inf(p.x):
		_fail("NaN na posição/velocidade")
		_finish()
		return
	if car.speed > 111.0:
		_fail("velocidade absurda %.0f km/h" % car.kmh())
	if p.y < -20.0:
		_fail("caiu do mundo (y=%.1f)" % p.y)
		_finish()
		return
	for w in car.wheels:
		var wh: Car.Wheel = w
		max_temp = maxf(max_temp, wh.temp)
	var wheel_v := 0.0
	for k in [2, 3]:
		wheel_v = maxf(wheel_v, absf((car.wheels[k] as Car.Wheel).omega) * 0.365)
	if wheel_v > car.speed * 1.6 + 25.0 and car.wheels[2].grounded:
		runaway_t += dt
		if runaway_t > 3.0:
			_fail("roda disparada (roda %.0f km/h, carro %.0f km/h)" % [wheel_v * 3.6, car.kmh()])
	else:
		runaway_t = maxf(runaway_t - dt, 0.0)
	# progresso para frente ao longo da pista
	var ds := car.s - prev_s
	if ds < -track.length * 0.5:
		ds += track.length
	elif ds > track.length * 0.5:
		ds -= track.length
	prev_s = car.s
	if recovered_at >= 0.0:
		progress += ds
	# ---------------- piloto de teclado com rotina de recuperação
	_drive(dt)
	if "trace" in OS.get_cmdline_user_args() and int(t * 120) % 30 == 0:
		var w2: Car.Wheel = car.wheels[2]
		print("  t=%.1f v=%.0f vl=%.1f g=%d thr_in=%.2f brk_in=%.2f thr=%.2f tc=%.2f stab=%s om=%.1f sx=%.2f sy=%.2f fz=%.0f sup=%d lat=%.1f yaw=%.2f" % [t, car.kmh(), car.v_long, car.gear, car.in_throttle, car.in_brake, car.throttle_eff, car.tc_cut, car.stab_active, w2.omega, w2.sx, w2.sy, w2.fz, w2.surface, car.lateral, car.angular_velocity.y])
	var on_track := absf(car.lateral) < track.half_width + 0.5
	var fwd_ok := (-car.global_transform.basis.z).dot(track.tang[car.t_idx]) > 0.7
	if recovered_at < 0.0 and on_track and fwd_ok and car.v_long > 15.0 and car.global_transform.basis.y.y > 0.8:
		recovered_at = t
	if recovered_at >= 0.0 and car.speed > 12.0:
		var slip := absf(rad_to_deg(atan2(car.linear_velocity.dot(car.global_transform.basis.x), car.v_long)))
		if slip > 30.0:
			spins += 1
	if t >= dur:
		_finish()


func _drive(dt: float) -> void:
	var b := car.global_transform.basis
	var spd := car.kmh()
	# capotado: usa o botão de voltar à pista
	if b.y.y < 0.3 and car.speed < 3.0:
		stuck_t += dt
		if stuck_t > 1.5:
			Input.action_press("reset_car")
			car.reset_to_track()
			stuck_t = 0.0
		return
	Input.action_release("reset_car")
	if cur.get("no_brake", 0.0) > t:
		_press("throttle", true)
		_press("brake", false)
		return
	if cur.get("manual", false):
		_drive_manual(dt)
		return
	if cur.get("pit", false) and t > 0.5 and t < 0.6:
		Input.action_press("pit_request")
	elif cur.get("pit", false):
		Input.action_release("pit_request")
	var look := track.idx(car.t_idx + int((8.0 + car.speed * 0.4) / track.ds))
	var lat_target := track.line_off[look]
	if cur.get("kerb", false):
		lat_target = (track.half_width + 0.6) * (1.0 if track.curv[look] < 0.0 else -1.0)
	var target := track.point(look, lat_target)
	var to := target - car.global_position
	var xr := to.dot(b.x)
	var zf := to.dot(-b.z)
	# ré: preso ou de costas para o alvo
	if rev_t > 0.0:
		rev_t -= dt
		_press("throttle", false)
		_press("brake", true)
		# esterça ao contrário na ré para virar o nariz
		_press("steer_left", xr > 0.0)
		_press("steer_right", xr < 0.0)
		return
	if car.speed < 1.5 and t > 1.0:
		stuck_t += dt
	else:
		stuck_t = maxf(stuck_t - dt * 0.5, 0.0)
	if stuck_t > 1.5 or (zf < -2.0 and car.speed < 3.0 and t > 0.5):
		rev_t = 2.2
		stuck_t = 0.0
		return
	var prof := track.speed_prof[track.idx(car.t_idx + int(maxf(car.speed * 0.9, 25.0) / track.ds))] * 3.6 * 0.95
	if car.wetness > 0.3:
		prof *= 0.6
	var brake := spd > prof + 8.0
	_press("brake", brake)
	_press("throttle", not brake)
	_press("steer_left", xr < -0.5)
	_press("steer_right", xr > 0.5)


func _drive_manual(_dt: float) -> void:
	# sequência: 1ª -> sobe até 4ª -> freia -> desce até 1ª -> N -> R -> ré
	var phase := int(t)
	Input.action_release("gear_up")
	Input.action_release("gear_down")
	if t < 8.0:
		_press("throttle", true)
		_press("brake", false)
		if fmod(t, 1.5) < 0.02 and car.gear < 4:
			Input.action_press("gear_up")
	elif t < 14.0:
		_press("throttle", false)
		_press("brake", true)
		if fmod(t, 0.7) < 0.02:
			Input.action_press("gear_down")
	elif t < 20.0:
		_press("brake", false)
		_press("throttle", true)
		if t < 14.05:
			print("   manual: marcha após reduções = %d (esperado -1 = ré), v=%.1f" % [car.gear, car.kmh()])
	else:
		_press("throttle", false)
		if t < 20.02:
			print("   manual: ré v_long=%.1f km/h (negativo = para trás)" % (car.v_long * 3.6))
			if car.v_long > -2.0:
				_fail("ré no câmbio manual não andou para trás")
	if phase == 0:
		recovered_at = 0.0


func _finish() -> void:
	var name: String = cur["name"]
	var dur := float(cur.get("time", 30.0))
	if not cur.get("manual", false):
		if recovered_at < 0.0:
			_fail("não conseguiu voltar a andar na pista em %.0f s" % dur)
		elif progress < 150.0 and not cur.get("pit", false):
			_fail("voltou mas andou só %.0f m" % progress)
		if spins > 20 and not cur.get("noassist", false):
			_fail("rodando depois de recuperar (%d ticks com deriva > 30°)" % spins)
	if max_temp > 139.0:
		_fail("pneu superaquecido (%.0f °C)" % max_temp)
	if cur.get("pit", false) and car.pit_stops < 1:
		_fail("pit stop do jogador não aconteceu (estado %d)" % car.pit_state)
	var ok := fails.is_empty()
	if cur.get("noassist", false) and spins > 20:
		print("   (sem assistências o carro roda %d ticks no teclado — esperado, como num F1 real)" % spins)
	var line := "%-20s %s  recuperou=%s  avançou=%4.0fm  rodadas=%d  pneu_máx=%3.0f°C  pits=%d" % [name, "OK  " if ok else "FALHA", ("%.1fs" % recovered_at) if recovered_at >= 0.0 else "não", progress, spins, max_temp, car.pit_stops]
	if not ok:
		line += "\n      -> " + "; ".join(fails)
	print(line)
	results.append(ok)
	cur = {}
	call_deferred("_next")


func _report() -> void:
	var n_ok := results.count(true)
	print("\n=== %d/%d cenários OK ===" % [n_ok, results.size()])
	get_tree().quit(0 if n_ok == results.size() else 1)
