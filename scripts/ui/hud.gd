class_name HUD
extends CanvasLayer
## Interface da corrida: torre de posições, volta, cronometragem, painel do carro (velocidade, marcha, RPM,
## ERS, asa móvel, combustível, pneus), minimapa, mensagens, semáforo, MFD de estratégia, pausa e resultados.

var race
var player: Car
var root: Control
var _tower: VBoxContainer
var _tower_rows: Array = []
var _lap_lbl: Label
var _pos_lbl: Label
var _cur_lbl: Label
var _last_lbl: Label
var _best_lbl: Label
var _delta_lbl: Label
var _sector_bars: Array = []
var _speed_lbl: Label
var _gear_lbl: Label
var _leds: Array = []
var _ers_bar: ProgressBar
var _ers_lbl: Label
var _aero_lbl: Label
var _ot_lbl: Label
var _fuel_lbl: Label
var _bias_lbl: Label
var _tyre_w: Control
var _tyre_lbl: Label
var _msg_lbl: Label
var _msg_t := 0.0
var _lights_box: HBoxContainer
var _light_dots: Array = []
var _pit_lbl: Label
var _mfd: PanelContainer
var _mfd_lbl: Label
var _pause: Control
var _results: Control
var _cam_lbl: Label
var _minimap: Minimap
var _tower_timer := 0.0
var _visible_all := true


func setup(p_race, p_player: Car) -> void:
	race = p_race
	player = p_player
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UIKit.theme()
	add_child(root)
	_build_tower()
	_build_top()
	_build_timing()
	_build_dash()
	_build_map()
	_build_center()
	_build_mfd()
	_build_pause()


# ======================================================================= construção
const B := Control.GROW_DIRECTION_BEGIN
const E := Control.GROW_DIRECTION_END
const BOTH := Control.GROW_DIRECTION_BOTH
var _elements: Array = []


## Ancora um elemento num ponto da tela (ax, ay em 0..1) com deslocamento e direção de crescimento.
func _place(c: Control, ax: float, ay: float, ox: float, oy: float, gx: int, gy: int, toggles := true) -> void:
	root.add_child(c)
	c.anchor_left = ax
	c.anchor_right = ax
	c.anchor_top = ay
	c.anchor_bottom = ay
	c.offset_left = ox
	c.offset_right = ox
	c.offset_top = oy
	c.offset_bottom = oy
	c.grow_horizontal = gx
	c.grow_vertical = gy
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if toggles:
		_elements.append(c)


func _build_tower() -> void:
	var pnl := UIKit.panel(Color(0.04, 0.05, 0.07, 0.78), 6, 8)
	_tower = VBoxContainer.new()
	_tower.add_theme_constant_override("separation", 2)
	pnl.add_child(_tower)
	_place(pnl, 0, 0, 24, 24, E, E)
	var head := UIKit.label("CLASSIFICAÇÃO", 14, UIKit.MUTED, true)
	_tower.add_child(head)
	for i in 11:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var pos := UIKit.label("1", 18, Color.WHITE, true, HORIZONTAL_ALIGNMENT_CENTER)
		pos.custom_minimum_size = Vector2(34, 30)
		var posbg := UIKit.panel(Color(0.18, 0.2, 0.25), 3, 0)
		posbg.add_child(pos)
		var bar := UIKit.rect(Color.RED, Vector2(5, 26))
		var code := UIKit.label("XXX", 19, Color.WHITE, true)
		code.custom_minimum_size = Vector2(58, 30)
		var gap := UIKit.label("", 17, UIKit.MUTED, false, HORIZONTAL_ALIGNMENT_RIGHT)
		gap.custom_minimum_size = Vector2(96, 30)
		var tyre := UIKit.label("M", 15, Color.YELLOW, true, HORIZONTAL_ALIGNMENT_CENTER)
		tyre.custom_minimum_size = Vector2(22, 30)
		var pit := UIKit.label("", 13, UIKit.YELLOW, true)
		pit.custom_minimum_size = Vector2(28, 30)
		row.add_child(posbg)
		row.add_child(bar)
		row.add_child(code)
		row.add_child(gap)
		row.add_child(tyre)
		row.add_child(pit)
		_tower.add_child(row)
		_tower_rows.append({"row": row, "pos": pos, "posbg": posbg, "bar": bar, "code": code, "gap": gap, "tyre": tyre, "pit": pit})


func _build_top() -> void:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	var p1 := UIKit.panel(Color(0.04, 0.05, 0.07, 0.82), 6, 14)
	_lap_lbl = UIKit.label("VOLTA 1/5", 28, Color.WHITE, true, HORIZONTAL_ALIGNMENT_CENTER)
	_lap_lbl.custom_minimum_size = Vector2(220, 0)
	p1.add_child(_lap_lbl)
	var p2 := UIKit.panel(UIKit.ACCENT, 6, 14)
	_pos_lbl = UIKit.label("P1", 28, Color.WHITE, true, HORIZONTAL_ALIGNMENT_CENTER)
	_pos_lbl.custom_minimum_size = Vector2(110, 0)
	p2.add_child(_pos_lbl)
	box.add_child(p1)
	box.add_child(p2)
	_place(box, 0.5, 0, 0, 22, BOTH, E)
	_lights_box = HBoxContainer.new()
	_lights_box.add_theme_constant_override("separation", 14)
	for i in 5:
		var pnl := UIKit.panel(Color(0.02, 0.02, 0.03, 0.92), 8, 10)
		var vb := VBoxContainer.new()
		vb.add_theme_constant_override("separation", 8)
		for k in 2:
			var dot := Panel.new()
			dot.custom_minimum_size = Vector2(44, 44)
			var st := StyleBoxFlat.new()
			st.bg_color = Color(0.2, 0.03, 0.03)
			st.set_corner_radius_all(22)
			dot.add_theme_stylebox_override("panel", st)
			vb.add_child(dot)
			_light_dots.append(st)
		pnl.add_child(vb)
		_lights_box.add_child(pnl)
	_place(_lights_box, 0.5, 0, 0, 110, BOTH, E, false)
	_lights_box.visible = false


func _build_timing() -> void:
	var pnl := UIKit.panel(Color(0.04, 0.05, 0.07, 0.82), 6, 14)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 2)
	pnl.add_child(vb)
	var r1 := HBoxContainer.new()
	r1.add_child(UIKit.label("ATUAL", 16, UIKit.MUTED, true))
	_cur_lbl = UIKit.label("0:00.000", 30, Color.WHITE, true, HORIZONTAL_ALIGNMENT_RIGHT)
	_cur_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r1.add_child(_cur_lbl)
	vb.add_child(r1)
	var bars := HBoxContainer.new()
	bars.add_theme_constant_override("separation", 4)
	for i in 3:
		var b := UIKit.rect(Color(0.3, 0.3, 0.33), Vector2(88, 6))
		bars.add_child(b)
		_sector_bars.append(b)
	vb.add_child(bars)
	_delta_lbl = UIKit.label("", 20, UIKit.GREEN, true, HORIZONTAL_ALIGNMENT_RIGHT)
	vb.add_child(_delta_lbl)
	var r2 := HBoxContainer.new()
	r2.add_child(UIKit.label("ÚLTIMA", 15, UIKit.MUTED, true))
	_last_lbl = UIKit.label("--:--.---", 19, Color.WHITE, false, HORIZONTAL_ALIGNMENT_RIGHT)
	_last_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r2.add_child(_last_lbl)
	vb.add_child(r2)
	var r3 := HBoxContainer.new()
	r3.add_child(UIKit.label("MELHOR", 15, UIKit.MUTED, true))
	_best_lbl = UIKit.label("--:--.---", 19, UIKit.PURPLE, false, HORIZONTAL_ALIGNMENT_RIGHT)
	_best_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r3.add_child(_best_lbl)
	vb.add_child(r3)
	pnl.custom_minimum_size = Vector2(300, 0)
	_place(pnl, 1, 0, -24, 24, B, E)
	_cam_lbl = UIKit.label("", 15, UIKit.MUTED, false, HORIZONTAL_ALIGNMENT_RIGHT)
	_cam_lbl.custom_minimum_size = Vector2(300, 0)
	_place(_cam_lbl, 1, 0, -24, 250, B, E)


func _build_dash() -> void:
	var pnl := UIKit.panel(Color(0.04, 0.05, 0.07, 0.82), 8, 16)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	pnl.add_child(vb)
	var leds := HBoxContainer.new()
	leds.add_theme_constant_override("separation", 4)
	for k in 15:
		var c := Panel.new()
		c.custom_minimum_size = Vector2(20, 12)
		var st := StyleBoxFlat.new()
		st.bg_color = Color(0.15, 0.15, 0.17)
		st.set_corner_radius_all(6)
		c.add_theme_stylebox_override("panel", st)
		leds.add_child(c)
		_leds.append(st)
	vb.add_child(leds)
	var main := HBoxContainer.new()
	main.add_theme_constant_override("separation", 18)
	var sp := VBoxContainer.new()
	_speed_lbl = UIKit.label("0", 64, Color.WHITE, true, HORIZONTAL_ALIGNMENT_RIGHT)
	_speed_lbl.custom_minimum_size = Vector2(150, 0)
	sp.add_child(_speed_lbl)
	sp.add_child(UIKit.label("KM/H", 15, UIKit.MUTED, true, HORIZONTAL_ALIGNMENT_RIGHT))
	main.add_child(sp)
	var gp := UIKit.panel(Color(0.12, 0.13, 0.16), 6, 10)
	_gear_lbl = UIKit.label("N", 72, Color.WHITE, true, HORIZONTAL_ALIGNMENT_CENTER)
	_gear_lbl.custom_minimum_size = Vector2(80, 0)
	gp.add_child(_gear_lbl)
	main.add_child(gp)
	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 3)
	_aero_lbl = UIKit.label("ASA: CURVA", 16, UIKit.MUTED, true)
	_ot_lbl = UIKit.label("", 16, UIKit.YELLOW, true)
	_fuel_lbl = UIKit.label("COMB 0.0 kg", 16, Color.WHITE)
	_bias_lbl = UIKit.label("FREIO 58.5%", 16, Color.WHITE)
	info.add_child(_aero_lbl)
	info.add_child(_ot_lbl)
	info.add_child(_fuel_lbl)
	info.add_child(_bias_lbl)
	main.add_child(info)
	vb.add_child(main)
	var ers := HBoxContainer.new()
	ers.add_theme_constant_override("separation", 8)
	_ers_lbl = UIKit.label("ERS", 15, UIKit.MUTED, true)
	_ers_lbl.custom_minimum_size = Vector2(130, 0)
	_ers_bar = ProgressBar.new()
	_ers_bar.custom_minimum_size = Vector2(260, 14)
	_ers_bar.show_percentage = false
	_ers_bar.max_value = 1.0
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.15, 0.15, 0.17)
	bg.set_corner_radius_all(3)
	var fg := StyleBoxFlat.new()
	fg.bg_color = Color(0.2, 0.75, 1.0)
	fg.set_corner_radius_all(3)
	_ers_bar.add_theme_stylebox_override("background", bg)
	_ers_bar.add_theme_stylebox_override("fill", fg)
	_ers_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ers.add_child(_ers_lbl)
	ers.add_child(_ers_bar)
	vb.add_child(ers)
	var tyr := HBoxContainer.new()
	tyr.add_theme_constant_override("separation", 12)
	_tyre_w = Control.new()
	_tyre_w.custom_minimum_size = Vector2(96, 112)
	_tyre_w.draw.connect(_draw_tyres)
	tyr.add_child(_tyre_w)
	_tyre_lbl = UIKit.label("", 15, Color.WHITE)
	_tyre_lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
	tyr.add_child(_tyre_lbl)
	vb.add_child(tyr)
	pnl.custom_minimum_size = Vector2(446, 0)
	_place(pnl, 1, 1, -24, -24, B, B)


func _build_map() -> void:
	var pnl := UIKit.panel(Color(0.04, 0.05, 0.07, 0.65), 8, 6)
	_minimap = Minimap.new()
	_minimap.custom_minimum_size = Vector2(330, 250)
	pnl.add_child(_minimap)
	_place(pnl, 0, 1, 24, -24, E, B)


func _build_center() -> void:
	_msg_lbl = UIKit.label("", 34, Color.WHITE, true, HORIZONTAL_ALIGNMENT_CENTER)
	_msg_lbl.add_theme_constant_override("outline_size", 8)
	_msg_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_msg_lbl.custom_minimum_size = Vector2(1000, 60)
	_place(_msg_lbl, 0.5, 0.5, 0, -260, BOTH, BOTH, false)
	_pit_lbl = UIKit.label("", 22, UIKit.YELLOW, true, HORIZONTAL_ALIGNMENT_CENTER)
	_pit_lbl.add_theme_constant_override("outline_size", 6)
	_pit_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_pit_lbl.custom_minimum_size = Vector2(1000, 40)
	_place(_pit_lbl, 0.5, 0.5, 0, -200, BOTH, BOTH)


func _build_mfd() -> void:
	_mfd = UIKit.panel(Color(0.04, 0.05, 0.07, 0.9), 8, 18)
	_mfd_lbl = UIKit.label("", 19, Color.WHITE)
	_mfd.add_child(_mfd_lbl)
	_place(_mfd, 0, 0.5, 24, 60, E, BOTH, false)
	_mfd.visible = false


func _build_pause() -> void:
	_pause = Control.new()
	_pause.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pause.visible = false
	root.add_child(_pause)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pause.add_child(dim)
	var pnl := UIKit.panel(Color(0.06, 0.07, 0.09, 0.96), 8, 28)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	vb.custom_minimum_size = Vector2(360, 0)
	pnl.add_child(vb)
	vb.add_child(UIKit.label("PAUSA", 34, Color.WHITE, true))
	for item in [["Continuar", "resume"], ["Reiniciar sessão", "restart"], ["Trocar câmera", "camera"], ["Menu principal", "menu"]]:
		var b := Button.new()
		b.text = item[0]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(_on_pause_action.bind(item[1]))
		vb.add_child(b)
	vb.add_child(UIKit.label("Controles: W/S acelera/freia · A/D direção · E/Q marchas (manual)\nEspaço asa móvel · F ultrapassagem · R modo ERS · P box · Tab estratégia\n[ ] balanço de freio · C câmera · V olhar para trás · Backspace voltar à pista", 14, UIKit.MUTED))
	_pause.add_child(pnl)
	pnl.anchor_left = 0.5
	pnl.anchor_right = 0.5
	pnl.anchor_top = 0.5
	pnl.anchor_bottom = 0.5
	pnl.grow_horizontal = BOTH
	pnl.grow_vertical = BOTH


func _on_pause_action(what: String) -> void:
	match what:
		"resume":
			race.set_paused(false)
		"restart":
			race.restart()
		"camera":
			race.camera.next_view()
		"menu":
			race.to_menu()


func set_pause_visible(v: bool) -> void:
	_pause.visible = v
	if v:
		var first: Button = _pause.find_children("*", "Button", true, false)[0]
		first.grab_focus()


# ======================================================================= atualização
func message(text: String, color := Color.WHITE, time := 2.5) -> void:
	_msg_lbl.text = text
	_msg_lbl.add_theme_color_override("font_color", color)
	_msg_t = time


func set_lights(n_on: int, show: bool) -> void:
	_lights_box.visible = show
	for i in _light_dots.size():
		var st: StyleBoxFlat = _light_dots[i]
		st.bg_color = Color(1.0, 0.06, 0.04) if (i / 2) < n_on else Color(0.2, 0.03, 0.03)


func _process(dt: float) -> void:
	if race == null or player == null:
		return
	if Input.is_action_just_pressed("toggle_hud"):
		_visible_all = not _visible_all
		for c in _elements:
			(c as CanvasItem).visible = _visible_all
	_msg_t -= dt
	_msg_lbl.modulate.a = clampf(_msg_t, 0.0, 1.0)
	if _minimap.track == null:
		_minimap.setup(race.track, race.cars, player)
	_update_dash()
	_update_timing()
	_tower_timer -= dt
	if _tower_timer <= 0.0:
		_tower_timer = 0.25
		_update_tower()
	_update_pit_and_mfd()
	_cam_lbl.text = "Câmera: %s (C)" % CameraRig.NAMES[race.camera.view]


func _update_dash() -> void:
	var car := player
	_speed_lbl.text = "%d" % int(round(car.kmh()))
	_gear_lbl.text = "R" if car.gear < 0 else ("N" if car.gear == 0 else str(car.gear))
	var frac := (car.rpm - 9500.0) / (Car.LIMIT_RPM - 9500.0)
	for k in 15:
		var st: StyleBoxFlat = _leds[k]
		var on := frac > float(k) / 15.0
		var col := Color(0.1, 0.95, 0.3) if k < 5 else (Color(1.0, 0.1, 0.1) if k < 10 else Color(0.35, 0.4, 1.0))
		if frac > 0.98 and int(Time.get_ticks_msec() / 70) % 2 == 0:
			col = Color(0.35, 0.4, 1.0)
		st.bg_color = col if on else Color(0.15, 0.15, 0.17)
	car.model.set_dash(car.gear, clampf(car.rpm / Car.LIMIT_RPM, 0.0, 1.0))
	_ers_bar.value = car.soc / Car.SOC_MAX
	_ers_lbl.text = "ERS %s" % ["RECARGA", "NORMAL", "ATAQUE"][car.ers_mode]
	if car.aero_open:
		_aero_lbl.text = "ASA: MODO RETA ●"
		_aero_lbl.add_theme_color_override("font_color", UIKit.GREEN)
	elif car.aero_available:
		_aero_lbl.text = "ASA: DISPONÍVEL [Espaço]" if not bool(Game.settings["auto_aero"]) else "ASA: AUTOMÁTICA"
		_aero_lbl.add_theme_color_override("font_color", Color.WHITE)
	else:
		_aero_lbl.text = "ASA: MODO CURVA"
		_aero_lbl.add_theme_color_override("font_color", UIKit.MUTED)
	if car.overtake_active:
		_ot_lbl.text = "ULTRAPASSAGEM ATIVA"
	elif car.overtake_ready:
		_ot_lbl.text = "ULTRAPASSAGEM [F]"
	else:
		_ot_lbl.text = ""
	var per_lap: float = race.fuel_per_lap()
	_fuel_lbl.text = "COMB %.1f kg (%+.1f v)" % [car.fuel, car.fuel / maxf(per_lap, 0.01) - race.laps_remaining(car)] if race.is_race() else "COMB %.1f kg" % car.fuel
	_bias_lbl.text = "FREIO %.1f%% DIANT." % (car.brake_bias * 100.0)
	var td := Tyres.get_data(car.compound)
	_tyre_lbl.text = "%s (%s)\n%d voltas\ndesgaste %d%%\n%.0f°C méd." % [td["name"], td["label"], car.tyre_laps, int(round(car.avg_wear() * 100.0)), (car.wheels[0].temp + car.wheels[1].temp + car.wheels[2].temp + car.wheels[3].temp) / 4.0]
	_tyre_lbl.add_theme_color_override("font_color", td["color"])
	_tyre_w.queue_redraw()


func _draw_tyres() -> void:
	var car := player
	var td := Tyres.get_data(car.compound)
	var opt: float = td["t_opt"]
	var win: float = td["t_win"]
	var pos := [Vector2(4, 4), Vector2(56, 4), Vector2(4, 60), Vector2(56, 60)]
	for i in 4:
		var w: Car.Wheel = car.wheels[i]
		var x := (w.temp - opt) / win
		var col := Color(0.2, 0.55, 1.0).lerp(Color(0.15, 0.85, 0.35), clampf(x + 1.0, 0.0, 1.0))
		if x > 0.0:
			col = Color(0.15, 0.85, 0.35).lerp(Color(1.0, 0.15, 0.1), clampf(x, 0.0, 1.0))
		var r := Rect2(pos[i], Vector2(36, 48))
		_tyre_w.draw_rect(r, col.darkened(0.55))
		var h := 48.0 * (1.0 - w.wear)
		_tyre_w.draw_rect(Rect2(pos[i] + Vector2(0, 48.0 - h), Vector2(36, h)), col)
		_tyre_w.draw_rect(r, Color(0, 0, 0, 0.8), false, 2.0)
	_tyre_w.draw_rect(Rect2(Vector2(44, 20), Vector2(8, 70)), Color(0.4, 0.42, 0.45))


func _update_timing() -> void:
	var t = race.timing[player]
	var now: float = race.session_time
	var cur := now - float(t.lap_start) if race.lap_running(player) else 0.0
	_cur_lbl.text = Game.fmt_time(cur)
	_cur_lbl.add_theme_color_override("font_color", Color.WHITE if t.lap_valid else Color(1.0, 0.35, 0.3))
	_last_lbl.text = Game.fmt_time(t.last_lap) if t.last_lap > 0.0 else "--:--.---"
	_best_lbl.text = Game.fmt_time(t.best_lap) if t.best_lap > 0.0 else "--:--.---"
	var lap_n: int = race.car_lap(player)
	if race.is_race():
		_lap_lbl.text = "VOLTA %d/%d" % [lap_n, race.laps_total()]
	else:
		_lap_lbl.text = "VOLTA %d" % lap_n
	var pos: int = race.position_of(player)
	_pos_lbl.text = "P%d" % pos
	_pos_lbl.get_parent().visible = race.is_race()
	for i in 3:
		var b: ColorRect = _sector_bars[i]
		b.color = t.sector_colors[i]
	if t.delta_valid and race.lap_running(player):
		var d: float = t.delta
		_delta_lbl.text = "%+.3f" % d
		_delta_lbl.add_theme_color_override("font_color", UIKit.GREEN if d <= 0.0 else Color(1.0, 0.3, 0.25))
	else:
		_delta_lbl.text = ""


func _update_tower() -> void:
	var st: Array = race.standings
	var n := st.size()
	var my := st.find(player)
	var rows := _tower_rows.size()
	var start := clampi(my - 5, 0, maxi(n - rows, 0))
	if n <= rows:
		start = 0
	for r in rows:
		var d: Dictionary = _tower_rows[r]
		var idx := start + r
		if r == 0:
			idx = 0
		elif start > 0:
			idx = start + r
		var row: HBoxContainer = d["row"]
		if idx >= n:
			row.visible = false
			continue
		row.visible = true
		var car: Car = st[idx]
		(d["pos"] as Label).text = str(idx + 1)
		(d["bar"] as ColorRect).color = car.team["primary"]
		(d["code"] as Label).text = String(car.driver["code"])
		(d["code"] as Label).add_theme_color_override("font_color", UIKit.YELLOW if car == player else Color.WHITE)
		var gap := ""
		if race.is_race():
			if idx == 0:
				gap = "Líder" if not race.timing[car].finished else "🏁"
			else:
				gap = race.gap_text(car, st[idx - 1])
		else:
			var bl: float = race.timing[car].best_lap
			gap = Game.fmt_time(bl) if bl > 0.0 else "--"
		(d["gap"] as Label).text = gap
		var td := Tyres.get_data(car.compound)
		(d["tyre"] as Label).text = td["code"]
		(d["tyre"] as Label).add_theme_color_override("font_color", td["color"])
		(d["pit"] as Label).text = "BOX" if car.in_pit() else ""
		var bg: PanelContainer = d["posbg"]
		bg.add_theme_stylebox_override("panel", UIKit.panel_style(UIKit.ACCENT if car == player else Color(0.18, 0.2, 0.25), 3, 0))


func _update_pit_and_mfd() -> void:
	var car := player
	var txt := ""
	match car.pit_state:
		Car.Pit.REQUESTED:
			txt = "BOX SOLICITADO — entrada no fim da volta (pneu: %s)" % Tyres.get_data(car.next_compound)["name"]
		Car.Pit.ENTRY, Car.Pit.STOPPING:
			txt = "PIT LANE — limitador %d km/h" % int(round(car.track.pit_speed * 3.6))
		Car.Pit.SERVICE:
			txt = "PIT STOP  %.1f s" % maxf(car.pit_service_time - car.pit_timer, 0.0)
		Car.Pit.EXIT:
			txt = ("SAINDO DO BOX — parada de %.1f s" % car.pit_service_time) if car.pit_service_time > 0.0 else "SAINDO DO BOX"
	_pit_lbl.text = txt
	if Input.is_action_just_pressed("mfd"):
		_mfd.visible = not _mfd.visible
	if _mfd.visible:
		if Input.is_action_just_pressed("mfd_next"):
			var i := Tyres.ORDER.find(car.next_compound)
			car.next_compound = Tyres.ORDER[(i + 1) % Tyres.ORDER.size()]
		var lines := "ESTRATÉGIA  (Tab fecha)\n\n"
		lines += "Próximo pneu:  %s   [PgDn troca]\n" % Tyres.get_data(car.next_compound)["name"].to_upper()
		lines += "Box:  %s   [P]\n" % ("SOLICITADO" if car.pit_state == Car.Pit.REQUESTED else ("NO PIT" if car.in_pit() else "não"))
		lines += "Modo ERS:  %s   [R]\n" % ["RECARGA", "NORMAL", "ATAQUE"][car.ers_mode]
		lines += "Balanço de freio:  %.1f%%   [ ]\n" % (car.brake_bias * 100.0)
		lines += "Compostos usados:  %s\n" % ", ".join(car.compounds_used.map(func(k): return Tyres.get_data(k)["code"]))
		if race.mandatory_compounds() and car.compounds_used.size() < 2 and bool(Tyres.get_data(car.compound)["slick"]):
			lines += "\n⚠ Regra: use 2 compostos secos diferentes na corrida"
		_mfd_lbl.text = lines


func show_results(rows: Array, title: String) -> void:
	if _results:
		_results.queue_free()
	_results = Control.new()
	_results.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(_results)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_results.add_child(dim)
	var pnl := UIKit.panel(Color(0.06, 0.07, 0.09, 0.97), 8, 26)
	pnl.anchor_left = 0.5
	pnl.anchor_right = 0.5
	pnl.anchor_top = 0.5
	pnl.anchor_bottom = 0.5
	pnl.grow_horizontal = BOTH
	pnl.grow_vertical = BOTH
	pnl.custom_minimum_size = Vector2(1040, 0)
	_results.add_child(pnl)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 3)
	pnl.add_child(vb)
	vb.add_child(UIKit.label(title, 32, Color.WHITE, true))
	var head := _result_row(["POS", "PILOTO", "EQUIPE", "TEMPO / DIF.", "MELHOR VOLTA", "PITS", "PEN."], true)
	vb.add_child(head)
	for r in rows:
		vb.add_child(_result_row(r["cols"], false, r["player"]))
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	var b1 := Button.new()
	b1.text = "Reiniciar"
	b1.pressed.connect(func(): race.restart())
	var b2 := Button.new()
	b2.text = "Menu principal"
	b2.pressed.connect(func(): race.to_menu())
	hb.add_child(b1)
	hb.add_child(b2)
	vb.add_child(UIKit.rect(Color(0, 0, 0, 0), Vector2(0, 10)))
	vb.add_child(hb)
	b2.grab_focus()


func _result_row(cols: Array, header: bool, is_player := false) -> Control:
	var hb := HBoxContainer.new()
	var widths := [60, 250, 230, 170, 160, 60, 60]
	for i in cols.size():
		var l := UIKit.label(str(cols[i]), 15 if header else 18, UIKit.MUTED if header else (UIKit.YELLOW if is_player else Color.WHITE), header or i == 1)
		l.custom_minimum_size = Vector2(widths[i], 26)
		hb.add_child(l)
	return hb
