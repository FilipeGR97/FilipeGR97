extends SceneTree
## Skidpad: círculo de raio R; a velocidade sobe devagar até o carro não segurar mais o raio.
## godot --headless --fixed-fps 120 -s res://tests/skidpad.gd -- r=60
var track: Track
var car: Car
var t := 0.0
var R := 60.0
var vt := 10.0
var best := 0.0
var lost := 0.0


class Ctl:
	var lab
	func drive(c: Car, _dt: float) -> void:
		var trk := c.track
		var look := 6.0 + c.speed * 0.3
		var target := trk.point(trk.idx(c.t_idx + int(look / trk.ds)), 0.0)
		var b := c.global_transform.basis
		var to := target - c.global_position
		var xr := to.dot(b.x)
		var zf := maxf(to.dot(-b.z), 1.0)
		var ang := atan2(2.0 * 3.4 * xr, xr * xr + zf * zf)
		var st := ang / c.max_steer
		st += c.angular_velocity.dot(b.y) * 0.035
		if c.speed > 8.0:
			st += c.linear_velocity.dot(b.x) / c.speed * 0.9
		c.in_steer = clampf(st, -1, 1)
		var err: float = lab.vt - c.speed
		c.in_throttle = clampf(0.3 + err * 0.5, 0.0, 1.0)
		c.in_brake = clampf(-err * 0.3, 0.0, 1.0)


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("r="): R = float(a.substr(2))
	var pts: Array = []
	for k in 36:
		var an := -TAU * k / 36.0
		pts.append([R * cos(an), R * sin(an), 0.0])
	var d := {"name": "skid", "width": 14.0, "pit_side": 1, "pit_entry": 60.0, "pit_exit": 60.0, "points": pts, "bridges": [], "grandstands": []}
	track = Track.new()
	root.add_child(track)
	track.build(d, 0.0, 0)
	car = Car.new()
	root.add_child(car)
	car.setup(0, Teams.team(0)["drivers"][0], track, false)
	car.set_fuel(20.0)
	var c := Ctl.new()
	c.lab = self
	car.controller = c
	car.place(track.frame(10, 0.0, 0.0))


func _physics_process(dt: float) -> bool:
	t += dt
	if t > 3.0:
		vt += dt * 0.6
	if t > 6.0:
		var ok := absf(car.lateral) < 5.0 and car.speed > vt - 2.0
		if ok:
			best = maxf(best, car.speed)
			lost = 0.0
		else:
			if lost == 0.0:
				print("  perdeu: v=%.1f vt=%.1f lat=%.2f fy_util F=%.2f,%.2f R=%.2f,%.2f thr=%.2f st=%.2f fz=%.0f,%.0f,%.0f,%.0f T=%.0f" % [car.speed, vt, car.lateral, car.wheels[0].sy / Car.AY_PEAK, car.wheels[1].sy / Car.AY_PEAK, car.wheels[2].sy / Car.AY_PEAK, car.wheels[3].sy / Car.AY_PEAK, car.in_throttle, car.in_steer, car.wheels[0].fz, car.wheels[1].fz, car.wheels[2].fz, car.wheels[3].fz, car.wheels[0].temp])
			lost += dt
	if lost > 1.0 or t > 200.0:
		var ay := best * best / R
		var q := 1.2 * 4.0 / 1600.0
		print("R=%.0f  vmax %.1f km/h  ay %.2f g  mu_ef %.2f" % [R, best * 3.6, ay / 9.81, ay / (9.81 + q * best * best)])
		return true
	return false
