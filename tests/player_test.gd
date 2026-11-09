extends Node
## Teste do carro do JOGADOR com "teclado virtual" (Input.action_press), como um humano faria.
## godot --headless --path . --fixed-fps 120 res://tests/player_test.tscn
## Fases: largada a fundo -> curva 1 com freio/esterço digital -> frenagem forte -> ré.

var track: Track
var car: Car
var t := 0.0
var max_yaw := 0.0
var max_slip := 0.0
var spins := 0
var log_t := 0.0
var phase := ""
var v_brake0 := 0.0
var t_brake0 := 0.0
var re_t := 1000.0

func _ready() -> void:
	track = Track.new()
	add_child(track)
	track.build(Tracks.get_data("serra_azul"), 0.0, 0)
	car = Car.new()
	add_child(car)
	car.setup(0, Teams.team(0)["drivers"][0], track, true)
	car.set_fuel(20.0)
	car.controller = PlayerInput.new()
	car.place(track.grid_slots[0])
	if "autobrake" in OS.get_cmdline_user_args():
		Game.settings["auto_brake"] = true

func _press(a: String, on: bool) -> void:
	if on: Input.action_press(a)
	else: Input.action_release(a)

func _physics_process(dt: float) -> void:
	if car == null:
		get_tree().quit(1)
		return
	t += dt
	var spd := car.kmh()
	# controlador "humano digital": segue a linha ideal com teclas (liga/desliga)
	var ahead := track.idx(car.t_idx + int(maxf(car.speed * 0.9, 25.0) / track.ds))
	var target := track.line_point(track.idx(car.t_idx + int((8.0 + car.speed * 0.4) / track.ds)))
	var xr := (target - car.global_position).dot(car.global_transform.basis.x)
	var prof := track.speed_prof[ahead] * 3.6 * 0.97
	if t < 10.0:
		phase = "reta"
		_press("throttle", true); _press("brake", false)
		_press("steer_left", xr < -0.6); _press("steer_right", xr > 0.6)
	elif t_brake0 >= 0.0 and t < 20.0:
		phase = "freio"
		_press("throttle", false); _press("brake", true)
		_press("steer_left", false); _press("steer_right", false)
		if v_brake0 == 0.0:
			v_brake0 = spd; t_brake0 = t
		if spd < 5.0:
			print("FREIO: %.0f km/h -> 5 km/h em %.2f s (%.2f g média)" % [v_brake0, t - t_brake0, (v_brake0 - 5.0) / 3.6 / (t - t_brake0) / 9.81])
			t_brake0 = -1.0
			re_t = t
	elif t < re_t + 3.0:
		phase = "re"
		_press("brake", true); _press("throttle", false)
	elif t < re_t + 4.0:
		phase = "re"
		if t < re_t + 3.0 + dt * 1.5:
			print("ré: marcha=%d v_long=%.1f km/h" % [car.gear, car.v_long * 3.6])
		_press("brake", false); _press("throttle", false)
	elif t < re_t + 44.0:
		phase = "volta"
		_press("steer_left", xr < -0.6)
		_press("steer_right", xr > 0.6)
		var brake := spd > prof + 8.0 and not ("autobrake" in OS.get_cmdline_user_args())
		_press("brake", brake)
		_press("throttle", not brake)
	else:
		print("RESUMO VOLTA: deriva máx %.1f°, ticks rodando %d" % [max_slip, spins])
		get_tree().quit()
		return
	var yaw := absf(car.angular_velocity.y)
	var slip := 0.0
	if car.speed > 10.0:
		slip = absf(rad_to_deg(atan2(car.linear_velocity.dot(car.global_transform.basis.x), car.v_long)))
	if phase == "volta":
		max_slip = maxf(max_slip, slip)
		if slip > 25.0 and car.speed > 10.0:
			spins += 1
	if phase == "freio" and t_brake0 > 0.0:
		if int(t * 120) % 12 == 0:
			print("   freio v=%3.0f rpm=%5.0f g=%d sx=%.2f,%.2f abs=%.2f,%.2f" % [spd, car.rpm, car.gear, car.wheels[0].sx, car.wheels[2].sx, car.wheels[0].brake_mod, car.wheels[2].brake_mod])
	log_t -= dt
	if log_t <= 0.0:
		log_t = 1.0
		print("t=%4.1f %s s=%5.0f v=%3.0f g=%d rpm=%5.0f thr=%.2f brk=%.2f deriva=%4.1f° lat=%+.1f off=%s" % [t, phase, car.s, spd, car.gear, car.rpm, car.throttle_eff, car.in_brake, slip, car.lateral, car.surface_off])
