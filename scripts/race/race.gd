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
	track.build(tdef, weather.wetness, quality)
	if bool(Game.settings["show_racing_line"]):
		_build_racing_line_guide()
	_total_laps = int(ses["laps"]) if mode == Game.Mode.QUICK_RACE else 0
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
	_compute_standings()
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
			car.set_compound(start_c, true)
			car.next_compound = "hard" if start_c != "hard" else "medium"
			if not bool(Tyres.get_data(start_c)["slick"]):
				car.next_compound = start_c
		else:
			var skill := lerpf(0.86, 1.0, diff) * lerpf(0.97, 1.0, (float(e["driver"]["skill"]) - 0.95) / 0.05)
			var ai := AIDriver.new(clampf(skill, 0.8, 1.0))
			ai.cars = cars
			ai.race = self
			car.controller = ai
			var c := auto_c
			if auto_c == "medium":
				c = ["medium", "medium", "hard", "soft"][_rng.randi() % 4]
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
	return is_race() and bool(Game.session["mandatory_compounds"]) and weather.wetness < 0.2 and _total_laps >= 5


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
	elif event.is_action_pressed("camera_next"):
		camera.next_view()
	elif event.is_action_pressed("reset_car") and player and state != "intro" and state != "lights":
		player.reset_to_track()
		timing[player].lap_valid = false
		hud.message("Carro reposicionado — volta invalidada", Color(1, 0.6, 0.2))


func _process(_dt: float) -> void:
	if camera:
		camera.look_back = Input.is_action_pressed("look_back")


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
	for c in cars:
		_update_timing(c, dt)
	_slip_t -= dt
	if _slip_t <= 0.0:
		_slip_t = 0.1
		_update_slipstream()
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


func _close_sector(car: Car, t: Timing, idx: int) -> void:
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
		if i == 0:
			tm = Game.fmt_time(t.finish_time)
		elif t.finished and t.laps_done < leader.laps_done:
			tm = "+%d volta(s)" % (leader.laps_done - t.laps_done)
		elif t.finished:
			tm = "+%.3f" % (t.finish_time - leader.finish_time)
		else:
			tm = "em pista"
		rows.append({"player": car == player, "cols": [i + 1, car.driver["name"], car.team["name"], tm, Game.fmt_time(t.best_lap) if t.best_lap > 0 else "--", car.pit_stops, ("+%ds" % int(t.penalty)) if t.penalty > 0.0 else ""]})
	var warn := ""
	if mandatory_compounds() and player.compounds_used.size() < 2:
		warn = "  ⚠ DESCLASSIFICADO: não usou 2 compostos"
	hud.show_results(rows, "RESULTADO FINAL" + warn)
	print("[corrida] resultado final: %d carros, vencedor %s, jogador P%d" % [rows.size(), final[0].driver["name"], final.find(player) + 1])
	var pits := 0
	var two := 0
	for c in final:
		pits += (c as Car).pit_stops
		if (c as Car).compounds_used.size() >= 2:
			two += 1
	print("[corrida] pit stops totais: %d, carros com 2+ compostos: %d/%d" % [pits, two, final.size()])
	Game.last_results = rows
