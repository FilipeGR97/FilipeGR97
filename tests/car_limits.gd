extends SceneTree
## Mede a capacidade real do carro: desaceleração máxima de frenagem por faixa de velocidade.
## godot --headless --fixed-fps 120 -s res://tests/car_limits.gd

var track: Track
var car: Car
var t := 0.0
var bins := {}
var started := false


class Hold:
	var brake := 1.0
	func drive(c: Car, _dt: float) -> void:
		c.in_throttle = 0.0
		c.in_brake = brake
		c.in_steer = 0.0


func _initialize() -> void:
	track = Track.new()
	root.add_child(track)
	track.build(Tracks.get_data("serra_azul"), 0.0, 0)
	car = Car.new()
	root.add_child(car)
	car.setup(0, Teams.team(0)["drivers"][0], track, false)
	car.set_fuel(20.0)
	car.controller = Hold.new()
	var i := track.idx_at_s(track.wrap_s(-280.0))
	car.place(track.frame(i, 0.0, 0.0))


func _physics_process(dt: float) -> bool:
	t += dt
	if not started:
		if t > 0.5:
			started = true
			var v := 88.0
			car.linear_velocity = -car.global_transform.basis.z * v
			for w in car.wheels:
				w.omega = v / w.radius
			car.gear = 8
		else:
			(car.controller as Hold).brake = 1.0
			return false
	var vel := car.linear_velocity
	var a := -(vel - _pv).dot(-car.global_transform.basis.z) / dt
	_pv = vel
	if t > 0.6 and car.speed > 8.0:
		var b := int(car.speed / 10.0)
		if not bins.has(b):
			bins[b] = [0.0, 0]
		bins[b][0] += a
		bins[b][1] += 1
	if car.speed < 6.0 and t > 1.0:
		var keys := bins.keys()
		keys.sort()
		for k in keys:
			print("v %3d-%3d km/h: desacel %.2f g" % [k * 36, (k + 1) * 36, bins[k][0] / bins[k][1] / 9.81])
		return true
	return t > 30.0


var _pv := Vector3.ZERO
