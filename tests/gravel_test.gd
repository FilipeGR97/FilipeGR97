extends Node
## Carro do jogador parado na brita da curva 1: tenta sair acelerando, depois de ré, e volta para a pista.
## godot --headless --path . --fixed-fps 120 res://tests/gravel_test.tscn

var track: Track
var car: Car
var t := 0.0
var log_t := 0.0
var back_on := -1.0
var spins := 0

func _ready() -> void:
	track = Track.new()
	add_child(track)
	track.build(Tracks.get_data("serra_azul"), 0.0, 0)
	car = Car.new()
	add_child(car)
	car.setup(0, Teams.team(0)["drivers"][0], track, true)
	car.set_fuel(20.0)
	car.controller = PlayerInput.new()
	# procura um trecho de brita do lado de fora da curva 1
	var gi := -1
	var side := 1
	for i in range(int(500 / track.ds), int(900 / track.ds)):
		for sd in 2:
			if track.run_s[sd][i] == Track.Surface.GRAVEL:
				gi = i; side = sd; break
		if gi >= 0: break
	var lat := (track.half_width + Track.APRON + 9.0) * (-1.0 if side == 0 else 1.0)
	var f := track.frame(gi, lat, 0.0)
	# atravessado, apontando para a pista
	f.basis = f.basis.rotated(Vector3.UP, (PI * 0.5 if side == 1 else -PI * 0.5) * 0.6)
	car.place(f)
	print("brita em s=%.0f lado=%d" % [gi * track.ds, side])

func _press(a: String, on: bool) -> void:
	if on: Input.action_press(a)
	else: Input.action_release(a)

func _physics_process(dt: float) -> void:
	t += dt
	var spd := car.kmh()
	var target := track.line_point(track.idx(car.t_idx + int((8.0 + car.speed * 0.4) / track.ds)))
	var xr := (target - car.global_position).dot(car.global_transform.basis.x)
	if t < 4.0:
		_press("throttle", true); _press("brake", false)
	elif t < 7.0:
		# tenta a ré
		_press("throttle", false); _press("brake", true)
	else:
		_press("brake", false)
		var prof := track.speed_prof[track.idx(car.t_idx + int(maxf(car.speed * 0.9, 25.0) / track.ds))] * 3.6 * 0.97
		var brake := spd > prof + 8.0
		_press("brake", brake); _press("throttle", not brake)
		_press("steer_left", xr < -0.6); _press("steer_right", xr > 0.6)
	if back_on < 0.0 and not car.surface_off and absf(car.lateral) < track.half_width:
		back_on = t
		print(">>> de volta à pista em %.1f s" % t)
	if back_on > 0.0 and car.speed > 10.0:
		var slip := absf(rad_to_deg(atan2(car.linear_velocity.dot(car.global_transform.basis.x), car.v_long)))
		if slip > 25.0: spins += 1
	log_t -= dt
	if log_t <= 0.0:
		log_t = 1.0
		var w2: Car.Wheel = car.wheels[2]
		print("t=%4.1f v=%5.1f g=%d thr=%.2f sup=%d lat=%+.1f pneuT=%.0f,%.0f desg=%.0f%% sx=%.2f" % [t, spd, car.gear, car.throttle_eff, w2.surface, car.lateral, car.wheels[0].temp, w2.temp, car.max_wear() * 100.0, w2.sx])
	if t > 45.0:
		print("RESUMO: voltou=%s  ticks rodando depois=%d" % [back_on > 0.0, spins])
		get_tree().quit()
