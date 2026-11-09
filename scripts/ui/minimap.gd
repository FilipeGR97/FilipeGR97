class_name Minimap
extends Control
## Mapa do circuito com a posição de todos os carros.

var track: Track
var cars: Array = []
var player: Car
var _pts := PackedVector2Array()
var _scale := 1.0
var _offset := Vector2.ZERO


func setup(p_track: Track, p_cars: Array, p_player: Car) -> void:
	track = p_track
	cars = p_cars
	player = p_player
	_rebuild()
	resized.connect(_rebuild)


func _rebuild() -> void:
	if track == null:
		return
	var r := track.bounds
	var pad := 14.0
	var avail := size - Vector2(pad, pad) * 2.0
	_scale = minf(avail.x / maxf(r.size.x, 1.0), avail.y / maxf(r.size.y, 1.0))
	_offset = Vector2(pad, pad) + (avail - r.size * _scale) * 0.5 - r.position * _scale
	_pts.clear()
	for p in track.minimap_pts:
		_pts.append(p * _scale + _offset)
	if not _pts.is_empty():
		_pts.append(_pts[0])


func _process(_dt: float) -> void:
	queue_redraw()


func _draw() -> void:
	if _pts.size() < 2:
		return
	draw_polyline(_pts, Color(0, 0, 0, 0.55), 9.0, true)
	draw_polyline(_pts, Color(0.92, 0.93, 0.95, 0.95), 4.0, true)
	# linha de chegada
	var s0 := _pts[0]
	draw_circle(s0, 4.0, Color(0.1, 0.1, 0.1))
	draw_circle(s0, 2.5, Color.WHITE)
	for c in cars:
		var car: Car = c
		if car == player:
			continue
		var p := Vector2(car.global_position.x, car.global_position.z) * _scale + _offset
		var col: Color = car.team["primary"]
		draw_circle(p, 5.0, Color(0, 0, 0, 0.7))
		draw_circle(p, 3.8, col)
	if player:
		var p := Vector2(player.global_position.x, player.global_position.z) * _scale + _offset
		draw_circle(p, 8.0, Color(0, 0, 0, 0.8))
		draw_circle(p, 6.0, UIKit.ACCENT)
		draw_circle(p, 2.5, Color.WHITE)
