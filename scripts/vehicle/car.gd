class_name Car
extends RigidBody3D
## Monoposto com física própria:
## - suspensão por raycast (mola + amortecedor + barra estabilizadora + batente)
## - pneu com "magic formula" combinada, sensibilidade à carga, temperatura e desgaste por pneu
## - unidade de potência 2026: motor a combustão (~400 kW) + MGU-K (350 kW) com bateria/ERS
## - aerodinâmica ativa 2026 (modo reta X / modo curva Z), vácuo (slipstream) e ar sujo
## - câmbio de 8 marchas (seamless), diferencial autoblocante, freio com balanço ajustável
## - consumo de combustível, pit stop, limites de pista

enum Pit { NONE, REQUESTED, ENTRY, STOPPING, SERVICE, EXIT }

# ---------------------------------------------------------------- geometria
const COM_H := 0.30
const COM_Z := -0.17           # deslocamento do modelo (eixo dianteiro do modelo em z=-1.7)
const FRONT_Z := -1.87
const REAR_Z := 1.53
const HALF_TRACK_F := 0.80
const HALF_TRACK_R := 0.78
const R_F := 0.36
const R_R := 0.365
const DRY_MASS := 768.0

# ---------------------------------------------------------------- powertrain
const RATIOS := [-14.0, 0.0, 17.6, 14.6, 12.2, 10.15, 8.5, 7.15, 6.0, 5.05]   # índice = marcha + 1
const IDLE_RPM := 4000.0
const LIMIT_RPM := 12500.0
const ICE_KW := 400.0
const MGUK_KW := 350.0
const SOC_MAX := 4.0e6
const HARVEST_LAP_MAX := 8.5e6
const BRAKE_TORQUE_TOTAL := 17500.0
const SUB := 5
const LOW_V := 6.0
const MU0 := 1.8
const REAR_GRIP := 1.07
const KX_PEAK := 0.11
const AY_PEAK := 0.13
const MF_B := 2.2
const MF_C := 1.35

const CLA_Z := 4.0
const CDA_Z := 1.35
const CLA_X := 2.5
const CDA_X := 0.97
const AERO_BAL_F := 0.43


class Wheel:
	var mount := Vector3.ZERO
	var radius := 0.36
	var front := true
	var left := true
	var k := 180000.0
	var c := 6500.0
	var rest := 0.10
	var droop := 0.05
	var comp := 0.0
	var comp_prev := 0.0
	var grounded := false
	var hit_pos := Vector3.ZERO
	var hit_n := Vector3.UP
	var surface := 0
	var omega := 0.0
	var spin := 0.0
	var fz := 0.0
	var fx := 0.0
	var fy := 0.0
	var sx := 0.0
	var sy := 0.0
	var slip_power := 0.0
	var temp := 70.0
	var wear := 0.0
	var brake_mod := 1.0
	var drive_t := 0.0
	var query: PhysicsRayQueryParameters3D


# ---------------------------------------------------------------- identidade
var team_index := 0
var team: Dictionary = {}
var driver: Dictionary = {}
var is_player := false
var controller: Object = null     # PlayerInput ou AIDriver (método drive(car, dt))
var track: Track
var model: CarModel
var audio: Node

# ---------------------------------------------------------------- entradas (escritas pelo controlador)
var in_throttle := 0.0
var in_brake := 0.0
var in_steer := 0.0                # -1 esquerda .. 1 direita
var want_aero := false
var assists := {"abs": true, "tc": 1, "auto_gear": true}

# ---------------------------------------------------------------- estado
var wheels: Array = []
var gear := 1
var rpm := IDLE_RPM
var shift_timer := 0.0
var throttle_eff := 0.0
var tc_cut := 0.0
var steer_angle := 0.0
var max_steer := deg_to_rad(21.0)
var brake_bias := 0.585
var speed := 0.0
var wheel_rpm := 0.0
var v_long := 0.0
var launch_hold := false
var reverse_timer := 0.0
var brake_in := 0.0
var gear_rpm := 0.0
var stab_active := false
var wrong_way := false
var auto_braking := false
var power_mult := 1.0
var aero_mult := 1.0

var soc := SOC_MAX
var ers_mode := 1                  # 0 recarga, 1 normal, 2 ataque
var harvest_lap := 0.0
var ers_deploy_kw := 0.0
var overtake_ready := false
var overtake_active := false
var overtake_energy := 0.0

var aero_open := false
var aero_available := false
var drag_mult := 1.0               # vácuo (setado pela corrida)
var down_mult := 1.0               # ar sujo

var fuel := 10.0
var compound := "medium"
var tyre_laps := 0
var next_compound := "medium"
var compounds_used: Array = []
var wetness := 0.0
var track_temp := 38.0
var wear_mult := 1.0
var fuel_mult := 1.0

# progresso na pista
var t_idx := 0
var s := 0.0
var lateral := 0.0
var surface_off := false

# pit
var pit_state := Pit.NONE
var pit_timer := 0.0
var pit_stops := 0
var in_limiter := false
var pit_service_time := 0.0

var _fuel_acc := 0.0
var _auto_cool := 0.0
var _ctl_tick := 0
var _t_grip := 1.0
var _t_opt := 95.0
var _t_win := 28.0
var _t_heat := 1.0
var _t_wear := 0.01
var _t_slick := true
var _rng := RandomNumberGenerator.new()
var _accel_local := Vector3.ZERO
var _prev_vel := Vector3.ZERO
var g_force := Vector3.ZERO


func setup(p_team_index: int, p_driver: Dictionary, p_track: Track, player: bool) -> void:
	team_index = p_team_index
	team = Teams.team(p_team_index)
	driver = p_driver
	track = p_track
	is_player = player
	var eng := Teams.engine(String(team["engine"]))
	power_mult = float(team.get("power", 1.0)) * float(eng.get("power", 1.0))
	aero_mult = float(team.get("aero", 1.0))
	_rng.seed = hash(String(p_driver.get("name", "x")))
	mass = DRY_MASS + fuel
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3.ZERO
	inertia = Vector3(1150.0, 1050.0, 260.0)
	continuous_cd = true
	can_sleep = false
	collision_layer = 2
	collision_mask = 1 | 2
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = 0.0
	angular_damp = 0.02
	var pm := PhysicsMaterial.new()
	pm.friction = 0.35
	pm.bounce = 0.05
	physics_material_override = pm
	_build_collision()
	_build_wheels()
	model = CarModel.new()
	model.build(team, int(p_driver.get("num", 0)), player)
	model.position = Vector3(0.0, -COM_H, COM_Z)
	add_child(model)
	set_compound(compound, true)


func _build_collision() -> void:
	# caixas em coordenadas do corpo (origem = centro de massa, 0.30 m acima do solo)
	var boxes := [
		[Vector3(0.95, 0.66, 4.5), Vector3(0.0, 0.43, -0.05)],    # chassi
		[Vector3(1.45, 0.48, 1.9), Vector3(0.0, 0.40, 0.45)],     # sidepods
		[Vector3(1.80, 0.24, 0.62), Vector3(0.0, 0.23, -2.62)],   # asa dianteira
		[Vector3(1.0, 0.35, 0.6), Vector3(0.0, 0.95, 2.25)],      # asa traseira
	]
	for wz in [-1.7, 1.7]:
		for wx in [-0.8, 0.8]:
			boxes.append([Vector3(0.34, 0.52, 0.72), Vector3(wx, 0.44, wz)])
	for b in boxes:
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = b[0]
		cs.shape = sh
		var p: Vector3 = b[1]
		cs.position = Vector3(p.x, p.y - COM_H, p.z + COM_Z)
		add_child(cs)


func _build_wheels() -> void:
	wheels.clear()
	for i in 4:
		var w := Wheel.new()
		w.front = i < 2
		w.left = i % 2 == 0
		w.radius = R_F if w.front else R_R
		var ht := HALF_TRACK_F if w.front else HALF_TRACK_R
		w.mount = Vector3(-ht if w.left else ht, w.radius - COM_H, FRONT_Z if w.front else REAR_Z)
		w.k = 175000.0 if w.front else 165000.0
		w.c = 6200.0 if w.front else 6000.0
		w.query = PhysicsRayQueryParameters3D.new()
		w.query.collision_mask = 1
		w.query.hit_back_faces = false
		wheels.append(w)


# ======================================================================= API
func set_compound(key: String, fresh: bool) -> void:
	compound = key
	var d := Tyres.get_data(key)
	_t_grip = d["grip"]
	_t_opt = d["t_opt"]
	_t_win = d["t_win"]
	_t_heat = d["heat"]
	_t_wear = d["wear_km"]
	_t_slick = d["slick"]
	if fresh:
		for w in wheels:
			w.temp = float(d["start_t"])
			w.wear = 0.0
		tyre_laps = 0
	if not compounds_used.has(key):
		compounds_used.append(key)
	if model:
		model.set_compound(d["color"])


func set_fuel(kg: float) -> void:
	fuel = kg
	mass = DRY_MASS + fuel


func place(xf: Transform3D) -> void:
	var t := Transform3D(xf.basis.orthonormalized(), xf.origin + xf.basis.y * (COM_H + 0.015))
	if is_inside_tree():
		global_transform = t
		reset_physics_interpolation()
	else:
		transform = t
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	for w in wheels:
		w.omega = 0.0
		w.comp = 0.0
		w.comp_prev = 0.0
	t_idx = track.locate(t.origin, -1)
	s = track.s_of(t.origin, t_idx)


func reset_to_track() -> void:
	var i := track.locate(global_position, t_idx)
	# fica do lado oposto ao traçado ideal (fora do caminho de quem vem)
	var line := track.line_off[i]
	var lat := -signf(line if absf(line) > 0.5 else lateral) * (track.half_width - 2.0)
	place(track.frame(i, lat, 0.0))
	gear = 1
	for w in wheels:
		var wh: Wheel = w
		wh.temp = maxf(wh.temp, _t_opt - 25.0)


func kmh() -> float:
	return speed * 3.6


func request_pit(on: bool) -> void:
	if on and pit_state == Pit.NONE:
		pit_state = Pit.REQUESTED
	elif not on and pit_state == Pit.REQUESTED:
		pit_state = Pit.NONE


func in_pit() -> bool:
	return pit_state >= Pit.ENTRY


func avg_wear() -> float:
	var a := 0.0
	for w in wheels:
		a += w.wear
	return a / 4.0


func max_wear() -> float:
	var a := 0.0
	for w in wheels:
		a = maxf(a, w.wear)
	return a


func on_new_lap() -> void:
	harvest_lap = 0.0
	tyre_laps += 1
	overtake_active = false
	overtake_energy = 0.0


func shift_up() -> void:
	if gear < 8 and shift_timer <= 0.0:
		gear = maxi(gear + 1, 1) if gear >= 0 else 0
		shift_timer = 0.035
		if audio and audio.has_method("on_shift"):
			audio.on_shift()


func shift_down() -> void:
	if shift_timer > 0.0:
		return
	if gear > 1:
		var r_now: float = RATIOS[gear + 1]
		var r_low: float = RATIOS[gear]
		if wheel_rpm * r_low / r_now < LIMIT_RPM - 300.0:
			gear -= 1
			shift_timer = 0.035
			if audio and audio.has_method("on_shift"):
				audio.on_shift()
	elif gear == 1 and speed < 2.0:
		gear = 0
	elif gear == 0 and speed < 2.0:
		gear = -1


# ======================================================================= física
func _physics_process(dt: float) -> void:
	if track == null:
		return
	var xf := global_transform
	var b := xf.basis
	var upv := b.y
	var fwd := -b.z
	var rgt := b.x
	var vel := linear_velocity
	speed = vel.length()
	v_long = vel.dot(fwd)
	var acc := (vel - _prev_vel) / dt
	_prev_vel = vel
	_accel_local = _accel_local.lerp(Vector3(acc.dot(rgt), acc.dot(upv), acc.dot(fwd)), 0.08)
	g_force = _accel_local / 9.81

	# progresso na pista
	t_idx = track.locate(global_position, t_idx, 3)
	s = track.s_of(global_position, t_idx)
	lateral = track.lateral_of(global_position, t_idx)
	surface_off = absf(lateral) - 0.95 > track.half_width
	wrong_way = (-b.z).dot(track.tang[t_idx]) < -0.3 and not in_pit()

	_ctl_tick += 1
	if controller and (is_player or _ctl_tick % 2 == 0 or in_pit()):
		controller.drive(self, dt * (1.0 if is_player or in_pit() else 2.0))
	_update_pit(dt)

	# --- direção
	var target_steer := clampf(in_steer, -1.0, 1.0) * max_steer
	steer_angle = move_toward(steer_angle, target_steer, dt * 3.2)

	# --- câmbio
	shift_timer = maxf(shift_timer - dt, 0.0)
	_auto_gearbox(dt)

	# --- aerodinâmica ativa
	# modo reta só em zona de reta, pista seca (direção de prova desativa no molhado) e carro andando reto
	aero_available = track.aero_zone[t_idx] == 1 and pit_state < Pit.ENTRY and wetness < 0.4
	var cornering := absf(g_force.x) > 1.0 or absf(steer_angle) > deg_to_rad(1.6) or absf(angular_velocity.dot(upv)) > 0.12
	if aero_open:
		if not aero_available or brake_in > 0.05 or cornering:
			aero_open = false
	elif want_aero and aero_available and brake_in < 0.05 and not cornering:
		aero_open = true
	# --- unidade de potência
	var r_gear: float = RATIOS[gear + 1]
	var w_rear: float = (wheels[2].omega + wheels[3].omega) * 0.5
	# rpm real das rodas (o motor está ligado a elas: patinando, o motor sobe de giro e bate no limitador)
	var true_rpm := absf(w_rear * r_gear) * 60.0 / TAU
	var road_rpm := absf(v_long / R_R * r_gear) * 60.0 / TAU
	wheel_rpm = true_rpm
	# rpm usado pelo câmbio automático: segue a velocidade real (não troca marcha com roda patinando)
	gear_rpm = road_rpm
	if brake_in > 0.05 or true_rpm < road_rpm * 0.9:
		# rodas segurando na frenagem: embreagem abre, motor acompanha a velocidade
		wheel_rpm = maxf(true_rpm, road_rpm)
	var engaged := gear != 0 and not launch_hold and shift_timer <= 0.0
	var thr := in_throttle
	brake_in = in_brake
	if gear == -1 and bool(assists["auto_gear"]):
		thr = in_brake
		brake_in = in_throttle
	if gear == -1 and speed > 7.0:
		thr = 0.0
	if in_limiter and speed > track.pit_speed - 0.3:
		thr = minf(thr, clampf((track.pit_speed - speed) * 0.5, 0.0, 1.0))
	# controle de tração
	var tc_level := clampi(int(assists["tc"]), 0, 2)
	var tc_target: float = TC_TARGETS[tc_level]
	var rear_slip := maxf(wheels[2].sx, wheels[3].sx)
	if gear < 0:
		rear_slip = -minf(wheels[2].sx, wheels[3].sx)
	var low_grip: bool = wheels[2].surface >= Track.Surface.GRASS or wheels[3].surface >= Track.Surface.GRASS
	var max_cut := 0.95
	# controle de tração proporcional e suave (antes era liga/desliga e "picotava" o motor)
	var tc_want := clampf((rear_slip - tc_target) / maxf(tc_target, 0.05) * 0.85, 0.0, max_cut)
	tc_cut = move_toward(tc_cut, tc_want, dt * (6.0 if tc_want > tc_cut else 3.0))
	# controle de estabilidade: corta potência se a traseira começa a escorregar de lado (sobreesterço)
	var stab_cut := 0.0
	if bool(assists.get("stab", false)) and speed > 6.0 and gear > 0:
		var util := 0.0
		for wi in [2, 3]:
			var rw: Wheel = wheels[wi]
			var ux := rw.sx / KX_PEAK
			var uy := rw.sy / AY_PEAK
			util = maxf(util, sqrt(ux * ux + uy * uy))
		var body_slip := absf(linear_velocity.dot(rgt)) / maxf(speed, 1.0)
		stab_cut = clampf((util - 0.8) * 1.8, 0.0, 0.9)
		stab_cut = maxf(stab_cut, clampf((body_slip - 0.05) * 9.0, 0.0, 0.9))
	stab_active = stab_cut > 0.05
	throttle_eff = thr * (1.0 - tc_cut) * (1.0 - stab_cut)
	var clutch_rpm := IDLE_RPM + thr * 4800.0
	var free_rpm := IDLE_RPM + thr * (LIMIT_RPM - IDLE_RPM)
	if not engaged:
		rpm = lerpf(rpm, free_rpm if gear == 0 or launch_hold else rpm, minf(dt * 6.0, 1.0))
	else:
		rpm = maxf(wheel_rpm, clutch_rpm if wheel_rpm < clutch_rpm else wheel_rpm)
		rpm = maxf(rpm, IDLE_RPM)
	var limiter_cut := rpm >= LIMIT_RPM
	rpm = minf(rpm, LIMIT_RPM + 50.0)
	var omega_e := rpm * TAU / 60.0
	var p_ice := ICE_KW * 1000.0 * _ice_curve(rpm) * power_mult * throttle_eff
	var p_ers := _ers(dt)
	var t_crank := 0.0
	if engaged:
		if limiter_cut:
			t_crank = 0.0
		elif throttle_eff > 0.02:
			t_crank = (p_ice + p_ers) / maxf(omega_e, 300.0)
		else:
			t_crank = -(8.0 + rpm * 0.0016)
			if speed < 3.0:
				t_crank = 0.0
	var t_axle := t_crank * r_gear * 0.93
	var w_l: Wheel = wheels[2]
	var w_r: Wheel = wheels[3]
	var lsd := 55.0 + absf(t_axle) * 0.05
	w_l.drive_t = t_axle * 0.5 - lsd * (w_l.omega - w_r.omega)
	w_r.drive_t = t_axle * 0.5 + lsd * (w_l.omega - w_r.omega)
	wheels[0].drive_t = 0.0
	wheels[1].drive_t = 0.0
	var i_drive := 1.3 + (0.035 * r_gear * r_gear * 0.5 if engaged else 0.0)

	# --- combustível
	var burn := 0.0194 * throttle_eff * clampf(rpm / 11000.0, 0.3, 1.1) * fuel_mult * dt
	fuel = maxf(fuel - burn, 0.0)
	if fuel <= 0.0:
		throttle_eff = 0.0
	_fuel_acc += dt
	if _fuel_acc > 0.5:
		_fuel_acc = 0.0
		mass = DRY_MASS + fuel

	# --- aerodinâmica
	var vv := v_long * v_long
	var cla := (CLA_X if aero_open else CLA_Z) * aero_mult * down_mult
	var cda := (CDA_X if aero_open else CDA_Z) * drag_mult
	var down := 0.6 * cla * vv
	var drag := 0.6 * cda * speed * speed
	if speed > 0.5:
		apply_central_force(-vel.normalized() * drag)
	var any_ground := false
	for w in wheels:
		if w.grounded:
			any_ground = true
	if any_ground:
		apply_force(-upv * down * AERO_BAL_F, b * Vector3(0, -0.1, FRONT_Z))
		apply_force(-upv * down * (1.0 - AERO_BAL_F), b * Vector3(0, -0.1, REAR_Z))

	# --- rodas: contato com o solo (consulta analítica da pista — mesma geometria da malha)
	for w in wheels:
		var wf: Wheel = w
		var origin := xf * (wf.mount + Vector3(0, wf.rest, 0))
		wf.comp_prev = wf.comp
		track.ground(origin, t_idx)
		var dist := (origin.y - track.g_y) / maxf(upv.y, 0.2)
		if dist > wf.rest + wf.radius + wf.droop or dist < -0.5:
			wf.grounded = false
			wf.comp = -wf.droop
			wf.fz = 0.0
			continue
		wf.grounded = true
		wf.hit_pos = origin - upv * dist
		wf.hit_n = track.g_normal
		wf.surface = track.g_surface
		wf.comp = wf.rest + wf.radius - dist
	# forças de suspensão (com barra estabilizadora)
	for wi in 4:
		var wf: Wheel = wheels[wi]
		if not wf.grounded:
			continue
		var other: Wheel = wheels[wi ^ 1]
		var arb := 70000.0 if wi < 2 else 52000.0
		var cv := (wf.comp - wf.comp_prev) / dt
		var f := wf.k * wf.comp + wf.c * cv
		if wf.comp > 0.055:
			f += 1500000.0 * (wf.comp - 0.055)
		f += (maxf(wf.comp, 0.0) - maxf(other.comp, 0.0)) * arb
		wf.fz = clampf(f, 0.0, 40000.0)
		if wf.comp <= 0.0:
			wf.fz = 0.0

	# --- pneus
	var wetf := Tyres.wet_factor(compound, wetness)
	var sub_n := 2 if is_player else 1
	var amb := lerpf(track_temp, 18.0, wetness)
	var dry_pen := 1.0
	if not _t_slick and wetness < 0.25:
		dry_pen = 3.5 if compound == "wet" else 2.6
	var brake_total := brake_in * BRAKE_TORQUE_TOTAL
	if launch_hold:
		brake_total = BRAKE_TORQUE_TOTAL
	var abs_on: bool = assists["abs"]
	for wi in 4:
		var w: Wheel = wheels[wi]
		var tb := brake_total * (brake_bias if w.front else 1.0 - brake_bias) * 0.5
		if not w.grounded:
			# roda no ar: só torque de motor/freio
			var ia := i_drive if not w.front else 1.3
			w.omega += w.drive_t / ia * dt
			w.omega = move_toward(w.omega, 0.0, tb / ia * dt)
			w.fx = 0.0
			w.fy = 0.0
			w.slip_power = 0.0
			continue
		var r := w.hit_pos - xf.origin
		var vp := vel + angular_velocity.cross(r)
		var n := w.hit_n
		var heading := fwd
		if w.front:
			heading = fwd.rotated(upv, -steer_angle)
		var wfw := (heading - n * heading.dot(n)).normalized()
		var wsd := wfw.cross(n)
		var vx := vp.dot(wfw)
		var vy := vp.dot(wsd)
		# coeficiente de atrito efetivo
		var mu := MU0 * (1.0 if w.front else REAR_GRIP) * _t_grip * wetf * float(Track.SURFACE_GRIP[w.surface])
		var dtp := (w.temp - _t_opt) / _t_win
		mu *= 1.0 - (0.18 * minf(dtp * dtp, 1.0) if dtp < 0.0 else 0.12 * minf(dtp * dtp, 1.3))
		mu *= 1.0 - 0.07 * w.wear - maxf(w.wear - 0.72, 0.0) * 1.15
		mu *= clampf(1.0 - 0.1 * (w.fz / 3000.0 - 1.0), 0.75, 1.08)
		var mfz := mu * w.fz
		# ABS
		if abs_on and tb > 0.0:
			# ABS mira o pico de aderência do pneu (escorregamento ~ KX_PEAK)
			var lim_sx := -KX_PEAK * (1.05 if w.front else 0.95)
			if w.sx < lim_sx:
				w.brake_mod = maxf(w.brake_mod - dt * 10.0 * (w.sx / lim_sx), 0.08)
			else:
				w.brake_mod = minf(w.brake_mod + dt * 9.0, 1.0)
		else:
			w.brake_mod = 1.0
		var tbw := tb * w.brake_mod
		var inertia_w := i_drive if not w.front else 1.3
		var h := dt / sub_n
		var denom := maxf(absf(vx), LOW_V)
		var sy := -vy / denom
		var ny := sy / AY_PEAK
		var ny2 := ny * ny
		var rr2 := w.radius * w.radius
		var fx_acc := 0.0
		var fy_acc := 0.0
		for k in sub_n:
			var sx := (w.omega * w.radius - vx) / denom
			var nx := sx / KX_PEAK
			var sl := sqrt(nx * nx + ny2)
			var fx := 0.0
			var fy := 0.0
			var kx := mfz * MF_B * MF_C / KX_PEAK
			if sl > 0.00001:
				var f := mfz * sin(MF_C * atan(MF_B * sl))
				fx = f * nx / sl
				fy = f * ny / sl
				# rigidez local dFx/dsx (secante) para a integração implícita
				var nx2 := nx + 0.05
				var sl2 := sqrt(nx2 * nx2 + ny2)
				var fx2 := mfz * sin(MF_C * atan(MF_B * sl2)) * nx2 / sl2
				kx = maxf((fx2 - fx) / (0.05 * KX_PEAK), 0.0)
			# Euler implícito linearizado: estável mesmo com poucos subpassos
			var om := w.omega + h * (w.drive_t - fx * w.radius) / inertia_w / (1.0 + h * kx * rr2 / (inertia_w * denom))
			if om > 0.0:
				om = maxf(om - tbw / inertia_w * h, 0.0)
			else:
				om = minf(om + tbw / inertia_w * h, 0.0)
			if engaged and not w.front:
				var om_max := (LIMIT_RPM + 200.0) * TAU / 60.0 / absf(r_gear)
				om = clampf(om, -om_max, om_max)
			w.omega = om
			fx_acc += fx
			fy_acc += fy
			w.sx = sx
		w.sy = sy
		var fxw := fx_acc / sub_n
		var fyw := fy_acc / sub_n
		# resistência ao rolamento / superfície
		var rr := (0.012 + float(Track.SURFACE_DRAG[w.surface])) * w.fz
		fxw -= rr * clampf(vx / 0.6, -1.0, 1.0)
		# parado sem acelerar: segura o carro (evita deslizar)
		if speed < 0.4 and throttle_eff < 0.05:
			fyw = -vy * 900.0
		w.fx = fxw
		w.fy = fyw
		apply_force(upv * w.fz + wfw * fxw + wsd * fyw, w.hit_pos - xf.origin)
		# temperatura e desgaste
		w.slip_power = absf(fxw * (w.omega * w.radius - vx)) + absf(fyw * vy)
		var paved := w.surface <= Track.Surface.KERB
		var slip_heat := minf(w.slip_power, 30000.0) * (1.0 if paved else 0.08)
		var heat := 0.00012 * slip_heat * _t_heat + 0.000008 * absf(vx) * w.fz
		var cool := (w.temp - amb) * (0.012 + 0.0009 * absf(vx)) * (1.0 + 2.5 * wetness)
		w.temp = clampf(w.temp + (heat - cool) * dt, amb - 5.0, 140.0)
		var overheat := 1.0 + maxf(w.temp - _t_opt - _t_win, 0.0) / 20.0
		w.wear = minf(w.wear + dt * absf(vx) / 1000.0 * _t_wear * wear_mult * dry_pen * overheat * (0.35 + 0.65 * clampf(w.slip_power / 9000.0, 0.0, 4.0)) * (1.0 if paved else 0.15), 1.0)

	for wi in 4:
		var w: Wheel = wheels[wi]
		w.spin -= w.omega * dt


func _process(_dt: float) -> void:
	# visual (uma vez por quadro; carros distantes da câmera não atualizam rodas)
	if model == null:
		return
	model.set_aero(aero_open)
	model.set_rain_light(wetness > 0.3)
	var cam := get_viewport().get_camera_3d()
	if cam and not is_player and cam.global_position.distance_squared_to(global_position) > 160.0 * 160.0:
		return
	for wi in 4:
		var w: Wheel = wheels[wi]
		model.set_wheel(wi, w.comp, w.spin, steer_angle if w.front else 0.0)
	if is_player:
		model.set_steering(in_steer)


const ICE_X := [0.0, 4000.0, 7000.0, 9500.0, 11000.0, 12000.0, 12600.0]
const ICE_Y := [0.0, 0.33, 0.64, 0.88, 1.0, 0.97, 0.9]
const TC_TARGETS := [10.0, 0.16, 0.09]


func _ice_curve(r: float) -> float:
	# fração da potência máxima em função do rpm
	for i in 6:
		if r <= ICE_X[i + 1]:
			return lerpf(ICE_Y[i], ICE_Y[i + 1], (r - ICE_X[i]) / (ICE_X[i + 1] - ICE_X[i]))
	return 0.9


func _ers(dt: float) -> float:
	var vk := speed * 3.6
	var deploy := 0.0
	if throttle_eff > 0.2 and gear >= 1 and soc > 0.0 and not launch_hold:
		var mode_f := 0.2
		if ers_mode == 1:
			mode_f = clampf(soc / 1.6e6, 0.3, 1.0)
		elif ers_mode == 2:
			mode_f = clampf(soc / 0.8e6, 0.2, 1.0)
		var c0 := 290.0 + (15.0 if ers_mode == 2 else 0.0)
		var c1 := 345.0
		var taper := clampf((c1 - vk) / (c1 - c0), 0.0, 1.0)
		if overtake_active and overtake_energy > 0.0:
			taper = 1.0 if vk < 337.0 else 0.0
		deploy = MGUK_KW * 1000.0 * mode_f * taper * throttle_eff * power_mult
		var used := deploy * dt
		if overtake_active and overtake_energy > 0.0:
			overtake_energy = maxf(overtake_energy - used, 0.0)
			if overtake_energy <= 0.0:
				overtake_active = false
		else:
			soc -= used
	var harvest := 0.0
	if speed > 12.0:
		if brake_in > 0.05:
			harvest = MGUK_KW * 1000.0 * minf(brake_in * 1.4, 1.0)
		elif throttle_eff < 0.05:
			harvest = 120000.0
		elif ers_mode == 0 and vk > 200.0:
			harvest = 150000.0          # "super clipping": parte da potência do motor recarrega a bateria
		elif soc < 1.0e6 and vk > 280.0:
			harvest = 100000.0
	if harvest_lap < HARVEST_LAP_MAX:
		var h := harvest * dt
		harvest_lap += h
		soc = minf(soc + h, SOC_MAX)
	soc = clampf(soc, 0.0, SOC_MAX)
	ers_deploy_kw = deploy / 1000.0
	return deploy


func _auto_gearbox(dt: float) -> void:
	if launch_hold:
		if gear < 1:
			gear = 1
		return
	if not bool(assists["auto_gear"]):
		return
	# ré automática: parado e segurando o freio
	if gear >= 1 and speed < 1.0 and in_brake > 0.5 and in_throttle < 0.05:
		reverse_timer += dt
		if reverse_timer > 0.35:
			gear = -1
			reverse_timer = 0.0
		return
	reverse_timer = 0.0
	if gear <= 0:
		if in_throttle > 0.1 and (gear == 0 or v_long > -1.0):
			gear = 1
		return
	_auto_cool = maxf(_auto_cool - dt, 0.0)
	if shift_timer > 0.0 or _auto_cool > 0.0:
		return
	if (gear_rpm > 11850.0 or (rpm > 12350.0 and gear_rpm > 10800.0)) and gear < 8:
		_auto_cool = 0.25
		shift_up()
	elif gear > 1:
		var r_now: float = RATIOS[gear + 1]
		var r_low: float = RATIOS[gear]
		var after := gear_rpm * r_low / r_now
		var thresh := 9300.0 if in_brake > 0.2 else 7000.0
		if gear_rpm < thresh and after < 11400.0:
			shift_down()
			_auto_cool = 0.2


# ======================================================================= pit stop
func _update_pit(dt: float) -> void:
	var u := track.pit_u(s)
	in_limiter = pit_state >= Pit.ENTRY and track.pit_limiter_zone(u)
	match pit_state:
		Pit.REQUESTED:
			if u >= 0.0 and u < 40.0:
				pit_state = Pit.ENTRY
		Pit.ENTRY:
			if u >= float(track.box_u[team_index]) - 30.0 and u < track.pit_len:
				pit_state = Pit.STOPPING
		Pit.STOPPING:
			if speed < 0.6 and absf(u - float(track.box_u[team_index])) < 2.5:
				pit_state = Pit.SERVICE
				pit_service_time = 2.1 + _rng.randf() * 0.9 + (0.0 if _rng.randf() > 0.06 else _rng.randf_range(1.5, 4.0))
				pit_timer = pit_service_time
		Pit.SERVICE:
			pit_timer -= dt
			if pit_timer <= 0.0:
				set_compound(next_compound, true)
				pit_stops += 1
				pit_state = Pit.EXIT
		Pit.EXIT:
			if u > track.pit_len - 5.0 or u < -10.0:
				pit_state = Pit.NONE
