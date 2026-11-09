extends SceneTree
## Teste headless: constrói a pista, solta carros da IA e mede voltas.
## godot --headless -s res://tests/sim_test.gd

var track: Track
var cars: Array = []
var t := 0.0
var last_s := {}
var laps := {}
var lap_start := {}
var max_t := 200.0
var n_cars := 4

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	for a in args:
		if a.begins_with("cars="): n_cars = int(a.substr(5))
		if a.begins_with("time="): max_t = float(a.substr(5))
		if a == "trace": trace = true
		if a.begins_with("tr0="): tr0 = float(a.substr(4)); trace = true
		if a.begins_with("tr1="): tr1 = float(a.substr(4))
	var t0 := Time.get_ticks_msec()
	track = Track.new()
	root.add_child(track)
	track.build(Tracks.get_data("serra_azul"), 0.0, 0)
	print("pista: %.0f m, %d amostras, build %d ms, zonas aero %s" % [track.length, track.n, Time.get_ticks_msec() - t0, str(track.aero_zones)])
	var vmin := 999.0
	var tsum := 0.0
	for i in track.n:
		vmin = minf(vmin, track.speed_prof[i])
		tsum += track.ds / track.speed_prof[i]
	print("perfil: vmin %.1f km/h, tempo teórico %.2f s" % [vmin * 3.6, tsum])
	for k in n_cars:
		var c := Car.new()
		root.add_child(c)
		c.setup(k % Teams.count(), Teams.team(k % Teams.count())["drivers"][0], track, false)
		c.set_fuel(15.0)
		var ai := AIDriver.new(0.97)
		ai.race = self
		ai.cars = cars
		c.controller = ai
		c.place(track.grid_slots[k])
		if "nocol" in OS.get_cmdline_user_args(): c.collision_mask = 1
		cars.append(c)
		last_s[c] = c.s
		laps[c] = 0
		lap_start[c] = 0.0

func is_racing() -> bool:
	return true

func race_time() -> float:
	return t + 10.0

var trace := false
var tr0 := 400.0
var tr1 := 760.0
var pit_done := false
func _physics_process(dt: float) -> bool:
	t += dt
	if "pit" in OS.get_cmdline_user_args():
		var pc: Car = cars[0]
		if t > 3.0 and pc.pit_state == Car.Pit.NONE and not pit_done:
			pc.next_compound = "soft"
			pc.request_pit(true)
			pit_done = true
			print("pit solicitado")
		if int(t * 120.0) % 60 == 0 and pc.pit_state != Car.Pit.NONE:
			print("  pit t=%.1f state=%d u=%.0f lat=%.1f v=%.0f comp=%s" % [t, pc.pit_state, track.pit_u(pc.s), pc.lateral, pc.kmh(), pc.compound])
	for c in cars:
		var car: Car = c
		if car.s < 200.0 and last_s[car] > track.length - 200.0:
			if laps[car] > 0:
				print("%.1fs carro %d volta %d: %s  pneu %.0f%% %.0fC soc %.1fMJ comb %.1fkg" % [t, cars.find(car), laps[car], "%.3f" % (t - lap_start[car]), car.avg_wear()*100, car.wheels[0].temp, car.soc/1e6, car.fuel])
			laps[car] += 1
			lap_start[car] = t
		last_s[car] = car.s
	if int(t * 180.0) % (180 * 5) == 0 and n_cars > 1:
		var line := "t=%3.0f " % t
		for cc in cars:
			var q: Car = cc
			line += "[%4.0f %3.0f %s%s] " % [q.s, q.kmh(), "%+.0f" % q.lateral, "*" if q.surface_off else ""]
		print(line + " T0=%.0f,%.0f,%.0f,%.0f" % [cars[0].wheels[0].temp, cars[0].wheels[1].temp, cars[0].wheels[2].temp, cars[0].wheels[3].temp])
	if int(t * 180.0) % (180 * 10) == 0 and n_cars == 1:
		var c0: Car = cars[0]
		print("t=%.0f  s=%.0f lat=%.1f v=%.0f km/h gear=%d rpm=%.0f off=%s pos=%s" % [t, c0.s, c0.lateral, c0.kmh(), c0.gear, c0.rpm, c0.surface_off, str(c0.global_position)])
	var c1: Car = cars[0]
	if trace and int(t * 180.0) % 18 == 0 and (c1.s > tr0 and c1.s < tr1):
		print("  s=%.0f yaw=%.2f slip=%.2f v=%.0f prof=%.0f thr=%.2f brk=%.2f st=%.2f lat=%.1f g=%d sx=%.2f,%.2f sy=%.2f,%.2f fz=%.0f,%.0f" % [c1.s, c1.angular_velocity.y, c1.linear_velocity.dot(c1.global_transform.basis.x)/maxf(c1.speed,1.0), c1.kmh(), c1.track.speed_prof[c1.t_idx]*3.6, c1.in_throttle, c1.in_brake, c1.in_steer, c1.lateral, c1.gear, c1.wheels[0].sx, c1.wheels[2].sx, c1.wheels[0].sy, c1.wheels[2].sy, c1.wheels[0].fz, c1.wheels[2].fz])
	return t > max_t
