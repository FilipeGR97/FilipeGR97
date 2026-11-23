extends Node3D
## Controlador da sessão (corrida, treino livre, contra o relógio).

const MS_LEN := 50.0            # minissetor (m) para intervalos e delta

class Timing:
	var laps_done := -1
	var lap_start := 0.0
	var last_lap := -1.0
	var best_lap := -1.0
	var lap_valid := true
	var finished := false
	var finish_time := 0.0
	var penalty := 0.0
	var warnings := 0
	var limit_cool := 0.0
	var prev_s := 0.0
	var sector := 0
	var sector_start := 0.0
	var cur_sectors := [0.0, 0.0, 0.0]
	var best_sectors := [INF, INF, INF]
	var sector_colors := [Color(0.3, 0.3, 0.33), Color(0.3, 0.3, 0.33), Color(0.3, 0.3, 0.33)]
	var ms := PackedFloat64Array()       # tempo em cada minissetor da corrida
	var lap_ms := PackedFloat32Array()   # tempos parciais da volta atual
	var best_ms := PackedFloat32Array()  # tempos parciais da melhor volta
	var delta := 0.0
	var delta_valid := false
	var pit_count_lap := -1
	var detect_prev := 0.0


var mode := 0
var track: Track
var weather: Weather
var cars: Array = []
var player: Car
var camera: CameraRig
var hud: HUD
var timing := {}
var standings: Array = []
var session_time := 0.0
var race_start := 0.0
var state := "intro"           # intro, lights, racing, chequered, done
var _state_t := 0.0
var _lights_n := 0
var _lights_out_delay := 1.0
var _total_laps := 5
var _chequered := false
var _paused := false
var _results_shown := false
var _slip_t := 0.0
var _rng := RandomNumberGenerator.new()
var _fuel_per_lap := 1.3
var _sprays := {}
var _best_overall := INF
var _num_down := [false, false, false, false, false, false, false, false]
# bandeiras e Virtual Safety Car
var yellow := [false, false, false]
var vsc := false
var vsc_t := 0.0
var _vsc_count := 0
var _last_vsc_end := -999.0
var _vsc_ending := -1.0
var _vsc_over := 0.0
var _stop_t := {}
var _dmg_warned := {}


func _ready() -> void:
	_rng.randomize()
	var ses: Dictionary = Game.session
	mode = int(ses["mode"])
	var quality: int = Game.settings["graphics"]
	# ---------------- clima e pista
	weather = Weather.new()
	add_child(weather)
	weather.setup(int(ses["weather"]), quality)
	track = Track.new()
	add_child(track)
	var tdef := Tracks.get_data(String(ses["track"]))
	Car.category = String(ses.get("category", "f1_2026"))
	var cat := Categories.get_data(Car.category)
	track.build(tdef, weather.wetness, quality)
	if Car.category != "f1_2026":
		# perfil da linha guia / freio automático conforme a aderência do carro da categoria
		var pm := float(cat["mass"]) + 40.0
		track.compute_speed_profile(float(cat["profile_mu"]), -1.0, 1.2 * float(cat["cla_z"]) / (2.0 * pm), 1.2 * float(cat["cda_z"]) / (2.0 * pm))
	if bool(Game.settings["show_racing_line"]):
		_build_racing_line_guide()
	_total_laps = int(ses["laps"]) if mode == Game.Mode.QUICK_RACE else 0
	if _total_laps < 0:
		_total_laps = int(tdef.get("laps_full", ceili(305000.0 / track.length)))
	_fuel_per_lap = track.length / 1000.0 * 0.27 * float(ses["fuel_use"])
	# ---------------- carros
	_spawn_cars(ses, tdef)
	# ---------------- câmera, HUD
	camera = CameraRig.new()
	camera.track = track
	add_child(camera)
	camera.view = int(Game.settings["camera"]) as CameraRig.View
	camera.set_target(player)
	weather.follow = camera
	hud = HUD.new()
	add_child(hud)
	hud.setup(self, player)
	if bool(Game.settings.get("mirrors", true)) and int(Game.settings["graphics"]) >= 1:
		var mir := Mirrors.new()
		add_child(mir)
		mir.setup(player, camera)
	_compute_standings()
	if OS.get_cmdline_user_args().has("dyno"):
		player.freeze = true
		player.dyno_t = 0.0
	if mode == Game.Mode.QUICK_RACE:
		state = "intro"
		hud.message("%s — %d voltas" % [tdef["name"], _total_laps], Color.WHITE, 3.0)
		for c in cars:
			(c as Car).launch_hold = true
	else:
		state = "racing"
		race_start = 0.0
		hud.message("TREINO LIVRE" if mode == Game.Mode.PRACTICE else "CONTRA O RELÓGIO", Color.WHITE, 3.0)
	process_mode = Node.PROCESS_MODE_ALWAYS
	for ch in get_children():
		if ch != hud:
			ch.process_mode = Node.PROCESS_MODE_PAUSABLE


# ======================================================================= carros
func _spawn_cars(ses: Dictionary, tdef: Dictionary) -> void:
	var entries: Array = []
	var p_team := int(ses["team"])
	var p_drv := int(ses["driver"])
	var diff := float(ses["difficulty"]) / 100.0
	for ti in Teams.count():
		var t := Teams.team(ti)
		for di in 2:
			var d: Dictionary = t["drivers"][di]
			var is_p := ti == p_team and di == p_drv
			var pace := float(t["power"]) * float(t["aero"]) * float(d["skill"])
			entries.append({"team": ti, "driver": d, "player": is_p, "pace": pace + _rng.randf_range(-0.012, 0.012)})
	var ai_count := int(ses["ai_count"])
	if mode == Game.Mode.TIME_TRIAL:
		ai_count = 0
	# mantém o jogador + os N adversários mais rápidos sorteados
	var player_e: Dictionary
	var others: Array = []
	for e in entries:
		if e["player"]:
			player_e = e
		else:
			others.append(e)
	others.shuffle()
	others = others.slice(0, ai_count)
	var field: Array = others + [player_e]
	field.sort_custom(func(a, b): return a["pace"] > b["pace"])
	var gp := int(ses["grid_position"])
	if gp >= 0:
		field.erase(player_e)
		field.insert(clampi(gp, 0, field.size()), player_e)
	var wet := weather.wetness
	var start_c := String(ses["start_compound"])
	var auto_c := Tyres.best_for(wet)
	if auto_c != "medium" and bool(Tyres.get_data(start_c)["slick"]):
		start_c = auto_c
	for k in field.size():
		var e: Dictionary = field[k]
		var car := Car.new()
		car.name = "Car_%s" % e["driver"]["code"]
		add_child(car)
		car.setup(int(e["team"]), e["driver"], track, bool(e["player"]))
		car.wetness = wet
		car.track_temp = float(tdef.get("track_c", 35.0)) - 10.0 * wet
		car.wear_mult = float(ses["tyre_wear"])
		car.fuel_mult = float(ses["fuel_use"])
		var fuel := (_total_laps + 1.2) * _fuel_per_lap + 1.0 if _total_laps > 0 else 30.0
		car.set_fuel(fuel)
		var aud := CarAudio.new()
		car.add_child(aud)
		aud.setup(car, not bool(e["player"]))
		car.audio = aud
		if bool(e["player"]):
			player = car
			var pi := PlayerInput.new()
			pi.autopilot.cars = cars
			pi.autopilot.race = self
			car.controller = pi
			if Game.dev_autodrive:
				var adv := AIDriver.new(0.95)
				adv.cars = cars
				adv.race = self
				car.controller = adv
			car.compounds_used.clear()
			car.set_compound(start_c, true)
			car.apply_setup(Game.session.get("setup", {}))
			car.next_compound = "hard" if start_c != "hard" else "medium"
			if not bool(Tyres.get_data(start_c)["slick"]):
				car.next_compound = start_c
		else:
			var drv_k := lerpf(0.985, 1.0, clampf((float(e["driver"]["skill"]) - 0.95) / 0.05, 0.0, 1.0))
			var aero_k := 1.0 - (1.0 - float(Teams.team(int(e["team"]))["aero"])) * 0.5
			var skill := lerpf(0.80, 1.0, diff) * drv_k * aero_k
			var ai := AIDriver.new(clampf(skill, 0.8, 1.0))
			ai.cat_k = float(Categories.get_data(Car.category)["ai_k"])
			# 90..100: além do limite de pilotagem, a equipe "otimiza o carro" (aderência/potência)
			var boost := clampf((diff - 0.9) / 0.1, 0.0, 1.0)
			car.grip_bonus = 1.0 + 0.05 * boost
			car.power_mult *= 1.0 + 0.03 * boost
			ai.aggression = clampf(0.35 + (float(e["driver"]["skill"]) - 0.95) * 6.0 + _rng.randf_range(-0.15, 0.25), 0.2, 0.95)
			ai.cars = cars
			ai.race = self
			car.controller = ai
			var c := auto_c
			if auto_c == "medium":
				c = ["medium", "medium", "hard", "soft"][_rng.randi() % 4]
			car.compounds_used.clear()
			car.set_compound(c, true)
			if _total_laps >= 6 and bool(Tyres.get_data(c)["slick"]):
				ai.planned_stop_lap = int(round(_total_laps * _rng.randf_range(0.38, 0.6)))
				ai.planned_compound = "hard" if c != "hard" else "medium"
		if wet > 0.0:
			var spray := Weather.make_spray()
			spray.position = Vector3(0, 0.3, 2.4)
			car.add_child(spray)
			_sprays[car] = spray
		cars.append(car)
		var tm := Timing.new()
		timing[car] = tm
		# posição inicial
		if mode == Game.Mode.QUICK_RACE:
			car.place(track.grid_slots[k])
		else:
			_place_in_box(car, k)
		tm.prev_s = car.s
		tm.laps_done = -1 if car.s > track.length * 0.5 else 0
		tm.detect_prev = car.s
	# no treino/contra o relógio o carro sai do box
	if mode != Game.Mode.QUICK_RACE:
		for c in cars:
			(c as Car).pit_state = Car.Pit.EXIT


func _place_in_box(car: Car, k: int) -> void:
	var u: float = track.box_u[car.team_index] + (k % 2) * 7.0
	var s := track.wrap_s(track.pit_entry_s + u)
	var i := track.idx_at_s(s)
	car.place(track.frame(i, track.pit_box_off * track.pit_side, 0.0))


func _build_racing_line_guide() -> void:
	# linha ideal colorida: verde acelerar, amarelo aliviar, vermelho frear
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in track.n:
		var j := track.idx(i + 1)
		var v0 := track.speed_prof[i]
		var v1 := track.speed_prof[track.idx(i + 6)]
		var col := Color(0.1, 0.9, 0.2, 0.32)
		if v1 < v0 - 0.4:
			col = Color(1.0, 0.1, 0.05, 0.5)
		elif v1 < v0 + 0.05 and v0 < 85.0:
			col = Color(1.0, 0.8, 0.1, 0.4)
		if i % 4 == 3:
			continue
		var a0 := track.line_point(i, -0.22) + track.up[i] * 0.015
		var b0 := track.line_point(i, 0.22) + track.up[i] * 0.015
		var a1 := track.line_point(j, -0.22) + track.up[j] * 0.015
		var b1 := track.line_point(j, 0.22) + track.up[j] * 0.015
		for p in [a0, a1, b0, b0, a1, b1]:
			st.set_color(col)
			st.set_normal(Vector3.UP)
			st.add_vertex(p)
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


# ======================================================================= API usada por IA / HUD
func race_time() -> float:
	return session_time - race_start if state != "intro" and state != "lights" else -1.0


func is_racing() -> bool:
	return state == "racing" or state == "chequered"


func is_race() -> bool:
	return mode == Game.Mode.QUICK_RACE


func laps_total() -> int:
	return _total_laps


func mandatory_compounds() -> bool:
	return is_race() and bool(Game.session["mandatory_compounds"]) and weather.wetness < 0.2 and _total_laps >= 10


func fuel_per_lap() -> float:
	return _fuel_per_lap


func car_lap(car: Car) -> int:
	var t: Timing = timing[car]
	if is_race():
		return clampi(t.laps_done + 1, 1, maxi(_total_laps, 1))
	return maxi(t.laps_done + 1, 1)


func laps_remaining(car: Car) -> float:
	var t: Timing = timing[car]
	return maxf(_total_laps - t.laps_done - car.s / track.length, 0.0)


func car_progress_in_lap(car: Car) -> float:
	return car.s / track.length


func lap_running(car: Car) -> bool:
	var t: Timing = timing[car]
	if is_race():
		return state != "intro" and state != "lights" and not t.finished
	return t.laps_done >= 0


func position_of(car: Car) -> int:
	return standings.find(car) + 1


func progress(car: Car) -> float:
	var t: Timing = timing[car]
	return t.laps_done * track.length + car.s


func gap_seconds(behind: Car, ahead: Car) -> float:
	var tb: Timing = timing[behind]
	var ta: Timing = timing[ahead]
	var k := tb.ms.size() - 1
	if k < 0 or k >= ta.ms.size():
		return -1.0
	return tb.ms[k] - ta.ms[k]


func gap_text(car: Car, ahead: Car) -> String:
	var t: Timing = timing[car]
	if t.finished and timing[standings[0]].finished:
		var tl: Timing = timing[standings[0]]
		if t.laps_done < tl.laps_done:
			return "+%d V" % (tl.laps_done - t.laps_done)
		return "+%.3f" % (t.finish_time - tl.finish_time)
	var dl := (progress(ahead) - progress(car)) / track.length
	if dl >= 1.0:
		return "+%d V" % int(dl)
	var g := gap_seconds(car, ahead)
	if g < 0.02:
		g = (progress(ahead) - progress(car)) / maxf(car.speed, 8.0)
	return "+%.1f" % g if g >= 10.0 else "+%.3f" % g


# ======================================================================= loop
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		if state == "done":
			return
		set_paused(not _paused)
	elif _paused:
		return
	elif event.is_action_pressed("reset_car") and player and state != "intro" and state != "lights":
		player.reset_to_track()
		timing[player].lap_valid = false
		hud.message("Carro reposicionado — volta invalidada", Color(1, 0.6, 0.2))


func _process(_dt: float) -> void:
	if camera == null or _paused:
		return
	camera.look_back = Input.is_action_pressed("look_back")
	var changed := false
	if Input.is_action_just_pressed("camera_next"):
		camera.next_view()
		changed = true
	for k in CameraRig.View.size():
		if Input.is_key_pressed(KEY_1 + k) and not _num_down[k]:
			camera.view = k as CameraRig.View
			changed = true
		_num_down[k] = Input.is_key_pressed(KEY_1 + k)
	if changed:
		Game.settings["camera"] = camera.view
		hud.message("Câmera: %s" % CameraRig.NAMES[camera.view], Color.WHITE, 1.2)


func set_paused(p: bool) -> void:
	_paused = p
	get_tree().paused = p
	hud.set_pause_visible(p)


func restart() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()


func to_menu() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/menu.tscn")


func _physics_process(dt: float) -> void:
	if _paused:
		return
	session_time += dt
	_state_t += dt
	match state:
		"intro":
			if _state_t > 2.5:
				state = "lights"
				_state_t = 0.0
				_lights_n = 0
				_lights_out_delay = _rng.randf_range(0.4, 2.8)
				camera.set_target(player)
		"lights":
			var n := mini(int(_state_t) + 1, 5)
			if _state_t >= 5.0 + _lights_out_delay:
				_lights_go()
			elif n != _lights_n:
				_lights_n = n
				track.set_start_lights(n)
				hud.set_lights(n, true)
	if state == "intro" or state == "lights":
		return
	if OS.get_cmdline_user_args().has("gearlog") and player.gear >= 6 and int(session_time * 120) % 6 == 0:
		print("[marcha] t=%.2f g=%d rpm=%5.0f v=%3.0f thr_in=%.2f thr=%.2f tc=%.2f stab=%s aero=%s ers=%.0fkW soc=%.2f lim=%s" % [session_time - race_start, player.gear, player.rpm, player.kmh(), player.in_throttle, player.throttle_eff, player.tc_cut, player.stab_active, player.aero_open, player.ers_deploy_kw, player.soc / 1e6, player.in_limiter])
	if OS.get_cmdline_user_args().has("launchlog") and session_time - race_start < 6.0 and int(session_time * 120) % 12 == 0:
		print("[largada] t=%.2f rpm=%5.0f marcha=%d thr_in=%.2f thr=%.2f tc=%.2f v=%.0f sx=%.2f shift=%.3f hold=%s" % [session_time - race_start, player.rpm, player.gear, player.in_throttle, player.throttle_eff, player.tc_cut, player.kmh(), player.wheels[2].sx, player.shift_timer, player.launch_hold])
	for c in cars:
		_update_timing(c, dt)
	_slip_t -= dt
	if _slip_t <= 0.0:
		_slip_t = 0.1
		_update_slipstream()
		_update_flags(0.1)
		if OS.get_cmdline_user_args().has("pitqueue"):
			_dev_pit_queue()
		if OS.get_cmdline_user_args().has("startlog") and is_racing() and race_time() < 16.0:
			# ferramenta de teste: quantos carros andam lado a lado na largada (fila indiana = 1 coluna)
			if int(race_time() * 10.0) % 20 == 0:
				var cols := {}
				var lats := []
				for c in cars:
					cols[int(roundf((c as Car).lateral / 2.5))] = true
					lats.append(snappedf((c as Car).lateral, 0.1))
				print("[largada] t=%.0f s colunas=%d lateral=%s" % [race_time(), cols.size(), str(lats)])
		if OS.get_cmdline_user_args().has("pitall"):
			# ferramenta de teste: todos os carros param no box na 1ª volta (testa entrada/saída do pit lane)
			for c in cars:
				var pc: Car = c
				if race_time() > 20.0 and pc.pit_stops == 0 and pc.pit_state == Car.Pit.NONE:
					pc.request_pit(true)
		if OS.get_cmdline_user_args().has("vsctest"):
			_dev_vsc_test()
		_compute_standings()
		_update_sprays()
	if is_race() and state == "chequered" and not _results_shown:
		var t: Timing = timing[player]
		if t.finished and session_time - t.finish_time > 3.0:
			_show_results()


func _lights_go() -> void:
	print("[corrida] largada")
	state = "racing"
	race_start = session_time
	track.set_start_lights(0)
	hud.set_lights(0, false)
	hud.message("LARGADA!", Color(0.2, 1.0, 0.4), 1.5)
	for c in cars:
		var car: Car = c
		car.launch_hold = false
		var t: Timing = timing[car]
		t.lap_start = race_start
		t.sector_start = race_start


# ======================================================================= cronometragem
func _update_timing(car: Car, dt: float) -> void:
	var t: Timing = timing[car]
	var L := track.length
	var s := car.s
	var crossed := t.prev_s > L - 80.0 and s < 80.0
	var back := t.prev_s < 80.0 and s > L - 80.0
	if back:
		t.laps_done -= 1
	# setores
	var sec := clampi(int(s / (L / 3.0)), 0, 2)
	if t.laps_done >= 0 and not t.finished and sec != t.sector and sec == (t.sector + 1) % 3 and not crossed:
		_close_sector(car, t, t.sector)
		t.sector = sec
	if crossed:
		t.laps_done += 1
		_on_line(car, t)
	# minissetores (intervalos)
	if t.laps_done >= -1 and is_racing():
		var k := int(floor((progress(car) + 400.0) / MS_LEN))
		while t.ms.size() <= k and k >= 0:
			t.ms.append(session_time)
		if t.laps_done >= 0 and lap_running(car):
			var kl := int(s / MS_LEN)
			while t.lap_ms.size() <= kl:
				t.lap_ms.append(session_time - t.lap_start)
			if t.best_ms.size() > kl and kl > 0:
				t.delta = (session_time - t.lap_start) - t.best_ms[kl]
				t.delta_valid = true
			else:
				t.delta_valid = false
	# detecção do modo ultrapassagem (a 1 s do carro da frente)
	var ds := track.overtake_detect_s
	if t.detect_prev < ds and s >= ds and s - t.detect_prev < 50.0 and t.laps_done >= 1 and is_race():
		var pos := standings.find(car)
		if pos > 0:
			var g := gap_seconds(car, standings[pos - 1])
			car.overtake_ready = g >= 0.0 and g < 1.0
			if car == player and car.overtake_ready:
				hud.message("MODO ULTRAPASSAGEM DISPONÍVEL [F]", UIKit.YELLOW, 2.0)
	t.detect_prev = s
	# limites de pista
	t.limit_cool = maxf(t.limit_cool - dt, 0.0)
	if car.surface_off and not car.in_pit() and car.speed > 12.0 and t.limit_cool <= 0.0 and not t.finished:
		var on_pit_road := track.in_pit_range(s) and signf(car.lateral) == float(track.pit_side)
		if not on_pit_road:
			t.limit_cool = 4.0
			t.lap_valid = false
			t.warnings += 1
			if car == player:
				if t.warnings >= 4 and is_race():
					t.penalty += 5.0
					hud.message("PENALIDADE +5 s — limites de pista", Color(1.0, 0.3, 0.2), 3.0)
				else:
					hud.message("LIMITES DE PISTA (%d) — volta invalidada" % t.warnings, Color(1.0, 0.6, 0.2), 2.5)
	t.prev_s = s


func _close_sector(_car: Car, t: Timing, idx: int) -> void:
	var st := session_time - t.sector_start
	t.sector_start = session_time
	t.cur_sectors[idx] = st
	var col := UIKit.YELLOW
	if st < t.best_sectors[idx] and t.lap_valid:
		t.best_sectors[idx] = st
		col = UIKit.GREEN
	t.sector_colors[idx] = col
	if idx == 0:
		t.sector_colors[1] = Color(0.3, 0.3, 0.33)
		t.sector_colors[2] = Color(0.3, 0.3, 0.33)


## Registra cada volta do jogador (e a melhor volta da IA até agora) em user://voltas.csv
## — serve para calibrar a dificuldade com os tempos reais de quem joga.
func _log_player_lap(lap: float, valid: bool) -> void:
	var ai_best := 0.0
	for c in cars:
		if c != player:
			var tc: Timing = timing[c]
			if tc.best_lap > 0.0 and (ai_best == 0.0 or tc.best_lap < ai_best):
				ai_best = tc.best_lap
	var path := "user://voltas.csv"
	var new_file := not FileAccess.file_exists(path)
	var f := FileAccess.open(path, FileAccess.READ_WRITE if not new_file else FileAccess.WRITE)
	if f == null:
		return
	f.seek_end()
	if new_file:
		f.store_line("data;pista;modo;volta_s;valida;melhor_ia_s;dificuldade;clima;abs;tc;freio_auto;direcao_assist;cambio_auto;equipe")
	var st: Dictionary = Game.settings
	var ses: Dictionary = Game.session
	f.store_line("%s;%s;%d;%.3f;%s;%.3f;%d;%d;%s;%d;%s;%s;%s;%s" % [Time.get_datetime_string_from_system(), track.key, mode, lap, valid, ai_best,
		int(ses["difficulty"]), int(ses["weather"]), st["abs"], int(st["traction_control"]), st["auto_brake"], st["steering_assist"], st["auto_gearbox"], player.team["name"]])
	f.close()


func _on_line(car: Car, t: Timing) -> void:
	var now := session_time
	if t.laps_done <= 0:
		# primeira passagem: na corrida a volta 1 conta desde a largada; no treino começa a volta lançada
		t.sector = 0
		if not is_race():
			t.lap_start = now
			t.sector_start = now
			t.lap_valid = true
			t.lap_ms = PackedFloat32Array()
			car.on_new_lap()
		return
	if true:
		_close_sector(car, t, 2)
		var lap := now - t.lap_start
		t.last_lap = lap
		if car == player:
			_log_player_lap(lap, t.lap_valid)
		if t.lap_valid and (t.best_lap < 0.0 or lap < t.best_lap):
			t.best_lap = lap
			t.best_ms = t.lap_ms.duplicate()
			if car == player:
				hud.message("MELHOR VOLTA PESSOAL  %s" % Game.fmt_time(lap), UIKit.GREEN, 2.5)
			if lap < _best_overall:
				_best_overall = lap
				if car == player:
					hud.message("VOLTA MAIS RÁPIDA  %s" % Game.fmt_time(lap), UIKit.PURPLE, 3.0)
		elif car == player and not t.lap_valid:
			hud.message("Volta %s (inválida)" % Game.fmt_time(lap), Color(1, 0.6, 0.3), 2.0)
		car.on_new_lap()
		if car == standings[0] and OS.get_cmdline_user_args().has("racelog"):
			var line := "[volta %d] " % t.laps_done
			for c in standings:
				var tc: Timing = timing[c]
				line += "%s %s | " % [c.driver["code"], Game.fmt_time(tc.last_lap)]
			print(line)
			var gl := "   intervalo p/ líder: "
			for c in standings:
				gl += "%s %.1f  " % [c.driver["code"], maxf(gap_seconds(c, standings[0]), 0.0)]
			print(gl)
	t.lap_start = now
	t.sector_start = now
	t.sector = 0
	t.lap_valid = true
	t.lap_ms = PackedFloat32Array()
	# fim de corrida
	if is_race() and not t.finished:
		if t.laps_done >= _total_laps or (_chequered and t.laps_done >= 1):
			t.finished = true
			t.finish_time = now - race_start + t.penalty
			if not _chequered:
				_chequered = true
				state = "chequered"
				if car == player:
					hud.message("VITÓRIA!  🏁", UIKit.YELLOW, 5.0)
				else:
					hud.message("BANDEIRA QUADRICULADA — %s venceu" % car.driver["name"], Color.WHITE, 3.5)
			if car == player:
				var pos := standings.find(car) + 1
				if pos > 1:
					hud.message("FIM DE CORRIDA — P%d" % pos, Color.WHITE, 5.0)
				# volta de desaceleração com piloto automático
				var ai := AIDriver.new(0.8)
				ai.cars = cars
				car.controller = ai
		elif t.laps_done == _total_laps - 1 and car == player:
			hud.message("ÚLTIMA VOLTA", Color.WHITE, 2.5)
		if car == player and mandatory_compounds() and car.compounds_used.size() < 2 and _total_laps - t.laps_done <= 3 and _total_laps - t.laps_done >= 1:
			hud.message("⚠ Falta trocar de composto — peça BOX [P] ou será desclassificado", UIKit.YELLOW, 4.0)


func _compute_standings() -> void:
	standings = cars.duplicate()
	if is_race():
		standings.sort_custom(func(a, b):
			var ta: Timing = timing[a]
			var tb: Timing = timing[b]
			if ta.finished and tb.finished:
				if ta.laps_done != tb.laps_done:
					return ta.laps_done > tb.laps_done
				return ta.finish_time < tb.finish_time
			if ta.finished != tb.finished:
				if ta.finished and ta.laps_done >= tb.laps_done:
					return true
				if tb.finished and tb.laps_done >= ta.laps_done:
					return false
			return progress(a) > progress(b))
	else:
		standings.sort_custom(func(a, b):
			var ba: float = timing[a].best_lap
			var bb: float = timing[b].best_lap
			if ba < 0.0:
				ba = INF
			if bb < 0.0:
				bb = INF
			return ba < bb)


# ======================================================================= bandeiras / VSC
func speed_cap(car: Car) -> float:
	if vsc:
		return maxf(track.speed_prof[car.t_idx] * 0.6, 22.0)
	return INF


## Vaga do box ocupada pelo companheiro de equipe (atendimento ou parando à frente)?
func box_busy(car: Car) -> bool:
	var u := track.pit_u(car.s)
	for c in cars:
		var o: Car = c
		if o == car or o.team_index != car.team_index:
			continue
		if o.pit_state == Car.Pit.SERVICE:
			return true
		if o.pit_state == Car.Pit.STOPPING and track.pit_u(o.s) > u and not o.pit_wait:
			return true
	return false


func yellow_at(s: float) -> bool:
	return yellow[clampi(int(s / (track.length / 3.0)), 0, 2)]


func _update_flags(dt: float) -> void:
	var L := track.length
	var y := [false, false, false]
	var trigger := ""
	for c in cars:
		var car: Car = c
		var t: Timing = timing[car]
		if car.in_pit() or t.finished or not is_racing() or (is_race() and race_time() < 8.0):
			continue
		var k := clampi(int(car.s / (L / 3.0)), 0, 2)
		var stopped := car.speed < 8.0
		var off := absf(car.lateral) > track.half_width + 1.0
		if stopped or (off and car.speed < 25.0):
			y[k] = true
			_stop_t[car] = float(_stop_t.get(car, 0.0)) + dt
			if stopped and not off and _stop_t[car] > 6.0:
				trigger = "carro parado na pista (%s)" % car.driver["code"]
		else:
			_stop_t[car] = 0.0
		if car.last_impact > 0.0:
			y[k] = true
			if car.last_impact > 1.1:
				trigger = "acidente forte (%s)" % car.driver["code"]
			car.last_impact = 0.0
		# avisos de dano para o jogador
		if car == player:
			if car.dmg_wing > 0.2 and not _dmg_warned.has("wing"):
				_dmg_warned["wing"] = true
				hud.message("ASA DIANTEIRA DANIFICADA (%d%%) — BOX recomendado [P]" % int(car.dmg_wing * 100), Color(1.0, 0.5, 0.2), 4.0)
			if car.puncture >= 0 and not _dmg_warned.has("pun"):
				_dmg_warned["pun"] = true
				hud.message("PNEU FURADO — vá para o BOX [P]", Color(1.0, 0.3, 0.2), 4.0)
			if car.dmg_wing < 0.05 and car.puncture < 0:
				_dmg_warned.clear()
	yellow = y
	# bandeira azul: carro com uma volta a mais chegando por trás (até ~1,5 s)
	for c in cars:
		(c as Car).blue_flag = false
	if is_race() and is_racing():
		for c in cars:
			var car: Car = c
			for o in cars:
				if o == car:
					continue
				var oc: Car = o
				var d := car.s - oc.s
				if d < 0.0:
					d += L
				if d > 0.0 and d < 90.0 and progress(oc) - progress(car) > L * 0.5:
					car.blue_flag = true
					if car == player and int(session_time * 10) % 30 == 0:
						hud.message("BANDEIRA AZUL — deixe o líder passar", Color(0.3, 0.6, 1.0), 2.0)
					break
	# Virtual Safety Car
	if is_race() and state == "racing" and trigger != "" and not vsc and race_time() > 8.0 and session_time - _last_vsc_end > 60.0:
		vsc = true
		_vsc_count += 1
		vsc_t = 0.0
		_vsc_ending = -1.0
		hud.message("VIRTUAL SAFETY CAR — " + trigger, UIKit.YELLOW, 4.0)
		if OS.get_cmdline_user_args().has("racelog"):
			print("[vsc] acionado t=%.0f: %s" % [race_time(), trigger])
	if vsc:
		vsc_t += dt
		var still := false
		for c in cars:
			if float(_stop_t.get(c, 0.0)) > 0.0 and absf((c as Car).lateral) < track.half_width + 1.0:
				still = true
		if _vsc_ending < 0.0 and vsc_t > 20.0 and not still:
			_vsc_ending = 3.0
			hud.message("VSC TERMINANDO — prepare-se", UIKit.GREEN, 3.0)
		if _vsc_ending >= 0.0:
			_vsc_ending -= dt
			if _vsc_ending <= 0.0:
				vsc = false
				_last_vsc_end = session_time
				hud.message("BANDEIRA VERDE", UIKit.GREEN, 2.0)
		# o jogador precisa respeitar o tempo-alvo
		var cap := speed_cap(player)
		if not player.in_pit() and player.speed > cap * 1.08:
			_vsc_over += dt
			if _vsc_over > 3.0:
				_vsc_over = 0.0
				timing[player].penalty += 5.0
				hud.message("PENALIDADE +5 s — acima do tempo do VSC", Color(1.0, 0.3, 0.2), 3.0)
		else:
			_vsc_over = maxf(_vsc_over - dt * 0.5, 0.0)
	for c in cars:
		(c as Car).aero_allowed = not vsc


var _dev_mate: Car = null
func _dev_pit_queue() -> void:
	# ferramenta de teste: jogador com pneu furado e companheiro de equipe pedem box na mesma volta
	var rt := race_time()
	if _dev_mate == null:
		for c in cars:
			if c != player and (c as Car).team_index == player.team_index:
				_dev_mate = c
	if _dev_mate == null:
		return
	var together := OS.get_cmdline_user_args().has("juntos")
	if rt > 3.0 and player.pit_stops == 0 and player.pit_state == Car.Pit.NONE and player.puncture < 0 and (not together or (track.pit_u(player.s) > track.length - 700.0 and track.pit_u(player.s) < track.length - 400.0)):
		if together:
			# coloca o companheiro colado atrás do jogador
			var i := track.idx(player.t_idx - 8)
			_dev_mate.place(track.frame(i, player.lateral, 0.0))
			_dev_mate.linear_velocity = player.linear_velocity
		else:
			player.puncture = 2
		player.request_pit(true)
		_dev_mate.request_pit(true)
		print("[box] pedidos feitos: jogador (furo) e %s" % _dev_mate.driver["code"])
	for c in [player, _dev_mate]:
		var car: Car = c
		if car == player and int(session_time * 10) % 20 == 0 and not car.in_pit():
			print("[box] JOGADOR fora do box: estado=%d s=%.0f u=%.0f v=%.0f lat=%.1f furo=%d" % [car.pit_state, car.s, track.pit_u(car.s), car.kmh(), car.lateral, car.puncture])
		if car.in_pit() and int(session_time * 10) % 5 == 0:
			print("[box] %s estado=%d u=%.0f box=%.0f v=%.0f v_long=%.1f marcha=%d espera=%s pits=%d" % [car.driver["code"], car.pit_state, track.pit_u(car.s), float(track.box_u[car.team_index]), car.kmh(), car.v_long * 3.6, car.gear, car.pit_wait, car.pit_stops])


var _dev_victim: Car = null
func _dev_vsc_test() -> void:
	# ferramenta de teste: para um carro no meio da pista aos 14 s e solta aos 40 s
	var rt := race_time()
	if rt > 14.0 and _dev_victim == null and standings.size() > 6:
		_dev_victim = standings[6]
		_dev_victim.freeze = true
		print("[vsc] carro %s parado na pista em s=%.0f" % [_dev_victim.driver["code"], _dev_victim.s])
	if rt > 40.0 and _dev_victim and _dev_victim.freeze:
		_dev_victim.freeze = false
		_dev_victim.reset_to_track()
		print("[vsc] carro liberado")
	if int(rt * 10) % 20 == 0:
		var slow := 0
		for c in cars:
			if (c as Car).speed < speed_cap(c) * 1.1 or not vsc:
				slow += 1
		print("[vsc] t=%.0f vsc=%s amarelas=%s vel_jogador=%.0f limite=%.0f carros_ok=%d/%d" % [rt, vsc, str(yellow), player.kmh(), speed_cap(player) * 3.6 if vsc else -1.0, slow, cars.size()])


func _update_slipstream() -> void:
	for c in cars:
		var car: Car = c
		var best := 1.0
		var dirty := 1.0
		for o in cars:
			if o == car:
				continue
			var oc: Car = o
			var d := oc.s - car.s
			if d < -track.length * 0.5:
				d += track.length
			if d <= 0.0 or d > 60.0:
				continue
			var lat := absf(oc.lateral - car.lateral)
			if lat > 3.5:
				continue
			var k := (1.0 - d / 60.0) * (1.0 - lat / 3.5)
			best = minf(best, 1.0 - 0.26 * k)
			dirty = minf(dirty, 1.0 - 0.12 * k)
		car.drag_mult = best
		car.down_mult = dirty


func _update_sprays() -> void:
	for car in _sprays.keys():
		var sp: GPUParticles3D = _sprays[car]
		sp.emitting = (car as Car).speed > 18.0
		sp.amount_ratio = clampf((car as Car).speed / 80.0, 0.2, 1.0)


func _dsq(car: Car) -> bool:
	if not mandatory_compounds():
		return false
	var dry := 0
	for k in car.compounds_used:
		if bool(Tyres.get_data(k)["slick"]):
			dry += 1
	return dry < 2 and timing[car].finished


func _show_results() -> void:
	_results_shown = true
	_compute_standings()
	var rows: Array = []
	var leader: Timing = timing[standings[0]]
	var final := standings.duplicate()
	# aplica penalidades de tempo entre carros na mesma volta
	final.sort_custom(func(a, b):
		var ta: Timing = timing[a]
		var tb: Timing = timing[b]
		var da := _dsq(a)
		var db := _dsq(b)
		if da != db:
			return db
		if ta.finished != tb.finished:
			return ta.finished
		if ta.finished:
			if ta.laps_done != tb.laps_done:
				return ta.laps_done > tb.laps_done
			return ta.finish_time < tb.finish_time
		return progress(a) > progress(b))
	leader = timing[final[0]]
	for i in final.size():
		var car: Car = final[i]
		var t: Timing = timing[car]
		var tm := ""
		if _dsq(car):
			tm = "DESCLASSIFICADO"
		elif i == 0:
			tm = Game.fmt_time(t.finish_time)
		elif t.finished and t.laps_done < leader.laps_done:
			tm = "+%d volta(s)" % (leader.laps_done - t.laps_done)
		elif t.finished:
			tm = "+%.3f" % (t.finish_time - leader.finish_time)
		else:
			tm = "em pista"
		rows.append({"player": car == player, "cols": ["DSQ" if _dsq(car) else str(i + 1), car.driver["name"], car.team["name"], tm, Game.fmt_time(t.best_lap) if t.best_lap > 0 else "--", car.pit_stops, ("+%ds" % int(t.penalty)) if t.penalty > 0.0 else ""]})
	var warn := ""
	if _dsq(player):
		warn = "  — você foi desclassificado (não usou 2 compostos secos)"
	hud.show_results(rows, "RESULTADO FINAL" + warn)
	print("[corrida] resultado final: %d carros, vencedor %s, jogador P%d" % [rows.size(), final[0].driver["name"], final.find(player) + 1])
	var pits := 0
	var two := 0
	for c in final:
		pits += (c as Car).pit_stops
		if (c as Car).compounds_used.size() >= 2:
			two += 1
	print("[corrida] pit stops totais: %d, carros com 2+ compostos: %d/%d" % [pits, two, final.size()])
	var laps_txt := ""
	for c in final:
		laps_txt += "%s:%d " % [c.driver["code"], timing[c].laps_done]
	print("[corrida] voltas completadas: " + laps_txt)
	var dm := ""
	for c in final:
		var cc: Car = c
		if cc.dmg_wing > 0.05 or cc.puncture >= 0 or cc.pit_stops > 0:
			dm += "%s(asa %d%% furo %s pits %d) " % [cc.driver["code"], int(cc.dmg_wing * 100), str(cc.puncture >= 0), cc.pit_stops]
	print("[corrida] danos/pits: " + (dm if dm != "" else "nenhum") + " | VSC acionado: %s" % str(_vsc_count))
	Game.last_results = rows
