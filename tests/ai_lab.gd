extends SceneTree
## Laboratório da IA (headless): mede o ritmo e a limpeza da pilotagem da IA numa pista.
## godot --headless --fixed-fps 120 -s res://tests/ai_lab.gd -- track=serra_azul skill=1.0 laps=3 [mu=1.8] [wet=0.6] [cars=1]
## Imprime tempo de cada volta, tempo fora da pista, deriva máxima e rodadas.

var track: Track
var cars: Array = []
var t := 0.0
var max_laps := 3
var laps := {}
var lap_start := {}
var last_s := {}
var off_t := {}
var max_slip := {}
var spins := {}
var spin_t := {}
var lap_log := {}
var resets := {}
var skill := 1.0
var n_cars := 1
var trace := false
var wheeldbg := false
var _was_off := {}
var tr0 := 0.0
var tr1 := 99999.0
var learn := false
var start_k := -1.0
var best_lap := 999.0
var best_k := PackedFloat32Array()
var lap_k := PackedFloat32Array()
var lap_spins := 0


func _initialize() -> void:
	var key := "serra_azul"
	var mu := -1.0
	var wet := 0.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("track="): key = a.substr(6)
		if a.begins_with("skill="): skill = float(a.substr(6))
		if a.begins_with("laps="): max_laps = int(a.substr(5))
		if a.begins_with("mu="): mu = float(a.substr(3))
		if a.begins_with("wet="): wet = float(a.substr(4))
		if a.begins_with("cars="): n_cars = int(a.substr(5))
		if a == "trace": trace = true
		if a == "wheels": wheeldbg = true
		if a.begins_with("tr0="): tr0 = float(a.substr(4)); trace = true
		if a.begins_with("tr1="): tr1 = float(a.substr(4))
		if a == "learn": learn = true
		if a.begins_with("start="): start_k = float(a.substr(6))
	track = Track.new()
	root.add_child(track)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("margin="): track.line_margin = float(a.substr(7))
	var t0 := Time.get_ticks_msec()
	var catk := -1.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("cat="): Car.category = a.substr(4)
		if a.begins_with("catk="): catk = float(a.substr(5))
	track.build(Tracks.get_data(key), wet, 0)
	if Car.category != "f1_2026":
		var cc := Categories.get_data(Car.category)
		var pm := float(cc["mass"]) + 40.0
		track.compute_speed_profile(float(cc["profile_mu"]), -1.0, 1.2 * float(cc["cla_z"]) / (2.0 * pm), 1.2 * float(cc["cda_z"]) / (2.0 * pm))
	if mu > 0.0:
		track.compute_speed_profile(mu)
	if start_k > 0.0:
		track.ai_k.fill(start_k)
	var tsum := 0.0
	var vmin := 999.0
	for i in track.n:
		tsum += track.ds / track.speed_prof[i]
		vmin = minf(vmin, track.speed_prof[i])
	print("pista %s: %.0f m, build %d ms, perfil teórico %.2f s, vmin %.0f km/h" % [key, track.length, Time.get_ticks_msec() - t0, tsum, vmin * 3.6])
	for k in n_cars:
		var c := Car.new()
		root.add_child(c)
		var ti := k % Teams.count()
		c.setup(ti, Teams.team(ti)["drivers"][0], track, false)
		c.set_fuel(20.0)
		c.wetness = wet
		if wet > 0.0:
			c.track_temp = 25.0
			c.set_compound(Tyres.best_for(wet), true)
		var ai := AIDriver.new(skill)
		ai.cat_k = catk if catk > 0.0 else float(Categories.get_data(Car.category)["ai_k"])
		for a in OS.get_cmdline_user_args():
			if a.begins_with("boost="):
				c.grip_bonus = 1.0 + 0.05 * float(a.substr(6))
				c.power_mult *= 1.0 + 0.03 * float(a.substr(6))
		ai.learn_rate = 1.0 if learn else 0.0
		for a in OS.get_cmdline_user_args():
			pass
		ai.race = self
		ai.cars = cars
		c.controller = ai
		c.place(track.grid_slots[k])
		cars.append(c)
		laps[c] = 0
		lap_start[c] = 0.0
		last_s[c] = c.s
		off_t[c] = 0.0
		max_slip[c] = 0.0
		spins[c] = 0
		spin_t[c] = 0.0
		lap_log[c] = []
		resets[c] = 0


func is_racing() -> bool:
	return true


func race_time() -> float:
	return t + 10.0


func _physics_process(dt: float) -> bool:
	t += dt
	var done := true
	for cc in cars:
		var c: Car = cc
		if absf(c.lateral) > track.half_width + 0.6:
			if off_t[c] == 0.0 or not _was_off.get(c, false):
				print("  fora da pista: carro %d s=%.0f lat=%.1f v=%.0f" % [cars.find(c), c.s, c.lateral, c.kmh()])
			off_t[c] += dt
			_was_off[c] = true
		else:
			_was_off[c] = false
		if c.speed > 15.0:
			var slip := rad_to_deg(absf(atan2(c.linear_velocity.dot(c.global_transform.basis.x), maxf(c.linear_velocity.dot(-c.global_transform.basis.z), 0.1))))
			max_slip[c] = maxf(max_slip[c], slip)
			if slip > 25.0:
				spin_t[c] += dt
				if spin_t[c] > 0.3 and spin_t[c] - dt <= 0.3:
					spins[c] += 1
					print("  rodada: carro %d s=%.0f v=%.0f" % [cars.find(c), c.s, c.kmh()])
			else:
				spin_t[c] = 0.0
		if c.s < 200.0 and last_s[c] > track.length - 200.0:
			if laps[c] > 0:
				var lt: float = t - lap_start[c]
				lap_log[c].append(lt)
				if learn and cars.find(c) == 0 and laps[c] >= 2 and spins[c] == lap_spins and off_t[c] < 1.0 and lt < best_lap:
					best_lap = lt
					best_k = lap_k.duplicate()
				lap_spins = spins[c]
				print("carro %d volta %d: %s  fora=%.1fs deriva_max=%.1f° rodadas=%d | T pneus %.0f/%.0f soc %.1fMJ colheita %.1fMJ desg %.0f%% comb %.1f" % [cars.find(c), laps[c], _ft(lt), off_t[c], max_slip[c], spins[c], c.wheels[0].temp, c.wheels[2].temp, c.soc / 1e6, c.harvest_lap / 1e6, c.avg_wear() * 100.0, c.fuel])
				off_t[c] = 0.0
				max_slip[c] = 0.0
				if learn:
					var sm := 0.0
					for x in track.ai_k:
						sm += x
					print("    k médio %.3f  eventos %s" % [sm / track.n, str(c.controller.learn_stats)])
					c.controller.learn_stats = [0, 0, 0]
			if learn:
				lap_k = track.ai_k.duplicate()
				c.repair()
				c.set_compound(c.compound, true)
				c.set_fuel(20.0)
				c.soc = Car.SOC_MAX
			laps[c] += 1
			lap_start[c] = t
			c.on_new_lap()
		if trace and cars.find(c) == 0 and laps[c] >= 1 and laps[c] <= 2 and int(c.s / 10.0) != int(last_s[c] / 10.0) and (c.s > tr0 and c.s < tr1):
			var ip := track.idx_at_s(c.s)
			print("  s=%4.0f v=%3.0f prof=%3.0f thr=%.2f brk=%.2f g=%d rpm=%5.0f lat=%+.1f line=%+.1f slipR=%.2f slipF=%.2f sx=%.2f k=%+.4f st=%+.2f cv=%+.4f" % [c.s, c.kmh(), track.speed_prof[ip] * 3.6, c.in_throttle, c.in_brake, c.gear, c.rpm, c.lateral, track.line_off[ip], maxf(absf(c.wheels[2].sy), absf(c.wheels[3].sy)) / Car.AY_PEAK, maxf(absf(c.wheels[0].sy), absf(c.wheels[1].sy)) / Car.AY_PEAK, c.wheels[2].sx, track.line_kap_s[ip], c.in_steer, track.curv[ip]])
		if wheeldbg and cars.find(c) == 0 and c.s > tr0 and c.s < tr1 and int(c.s / 5.0) != int(last_s[c] / 5.0):
			var ws := ""
			for w in c.wheels:
				ws += "[%s su=%d fz=%.0f sy=%.2f] " % ["g" if w.grounded else "-", w.surface, w.fz, w.sy]
			print("  W s=%.0f y=%.2f trk_y=%.2f pitch=%.3f roll=%.3f yaw_err=%.3f %s" % [c.s, c.global_position.y, track.point(c.t_idx, c.lateral).y, c.rotation.x, c.rotation.z, (-c.global_transform.basis.z).signed_angle_to(track.tang[c.t_idx], Vector3.UP), ws])
		last_s[c] = c.s
		if laps[c] <= max_laps:
			done = false
	if t > 130.0 * max_laps + 120.0:
		print("TEMPO ESGOTADO")
		done = true
	if done:
		if learn:
			if best_k.size() == track.n:
				track.ai_k = best_k
				print("usando o conhecimento da melhor volta limpa: %s" % _ft(best_lap))
			var path := "res://data/ai/%s.json" % track.key
			track.save_ai_knowledge(path)
			var mn := 9.0
			var mx := 0.0
			for x in track.ai_k:
				mn = minf(mn, x)
				mx = maxf(mx, x)
			print("conhecimento salvo em %s (fator %.3f .. %.3f)" % [path, mn, mx])
		for cc in cars:
			var c: Car = cc
			var arr: Array = lap_log[c]
			var best := 999.0
			for x in arr.slice(1):
				best = minf(best, x)
			print("RESUMO carro %d: melhor (voltas lançadas) %s, rodadas %d" % [cars.find(c), _ft(best), spins[c]])
	return done


func _ft(x: float) -> String:
	return "%d:%06.3f" % [int(x / 60.0), fmod(x, 60.0)]
