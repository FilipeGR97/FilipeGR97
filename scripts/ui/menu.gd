extends Node3D
## Menu principal com showroom 3D do carro.

var _ui: Control
var _panel: VBoxContainer
var _info: Label
var _car_holder: Node3D
var _car: CarModel
var _cam: Camera3D
var _team := 0
var _driver := 0
var _orbit := 0.0
var _screen := "main"


func _ready() -> void:
	get_tree().paused = false
	_team = int(Game.session["team"])
	_driver = int(Game.session["driver"])
	_build_stage()
	_ui = Control.new()
	_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui.theme = UIKit.theme()
	var layer := CanvasLayer.new()
	add_child(layer)
	layer.add_child(_ui)
	# faixa lateral
	var side := ColorRect.new()
	side.color = Color(0.03, 0.035, 0.05, 0.82)
	side.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	side.offset_right = 560
	_ui.add_child(side)
	var stripe := ColorRect.new()
	stripe.color = UIKit.ACCENT
	stripe.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	stripe.offset_left = 560
	stripe.offset_right = 565
	_ui.add_child(stripe)
	var title := UIKit.label("APEX GP", 64, Color.WHITE, true)
	title.position = Vector2(56, 48)
	_ui.add_child(title)
	var sub := UIKit.label("SIMULADOR DE MONOPOSTOS · TEMPORADA 2026", 17, UIKit.MUTED, true)
	sub.position = Vector2(60, 132)
	_ui.add_child(sub)
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(56, 200)
	scroll.size = Vector2(480, 820)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_ui.add_child(scroll)
	_panel = VBoxContainer.new()
	_panel.custom_minimum_size = Vector2(460, 0)
	_panel.add_theme_constant_override("separation", 10)
	scroll.add_child(_panel)
	_info = UIKit.label("", 18, Color.WHITE)
	_info.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_info.position = Vector2(-700, -230)
	_info.custom_minimum_size = Vector2(660, 200)
	_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_info.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_info.add_theme_constant_override("outline_size", 6)
	_info.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	_ui.add_child(_info)
	var ver := UIKit.label("v" + str(ProjectSettings.get_setting("application/config/version")), 14, UIKit.MUTED)
	ver.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	ver.position = Vector2(60, -40)
	_ui.add_child(ver)
	_show_main()


# ======================================================================= palco 3D
func _build_stage() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.035, 0.04, 0.05)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.35, 0.38, 0.45)
	env.ambient_light_energy = 0.5
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.1
	env.ssao_enabled = true
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.glow_hdr_threshold = 1.3
	# reflexos de estúdio: céu simples com faixas de luz
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.25, 0.27, 0.32)
	sky_mat.sky_horizon_color = Color(0.12, 0.13, 0.15)
	sky_mat.ground_bottom_color = Color(0.02, 0.02, 0.025)
	sky_mat.ground_horizon_color = Color(0.1, 0.1, 0.12)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.sky = sky
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	# piso refletivo
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(60, 60)
	floor_mi.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.05, 0.055, 0.065)
	fm.roughness = 0.18
	fm.metallic = 0.4
	floor_mi.material_override = fm
	add_child(floor_mi)
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 3.9
	tm.outer_radius = 4.0
	tm.rings = 96
	var rm := StandardMaterial3D.new()
	rm.emission_enabled = true
	rm.emission = UIKit.ACCENT
	rm.emission_energy_multiplier = 2.5
	rm.albedo_color = Color.BLACK
	tm.material = rm
	ring.mesh = tm
	ring.scale = Vector3(1, 0.02, 1)
	ring.position.y = 0.005
	add_child(ring)
	# luzes
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-55, 30, 0)
	key.light_energy = 1.2
	key.shadow_enabled = true
	add_child(key)
	for p in [[Vector3(4, 3, 3), Color(0.7, 0.85, 1.0), 6.0], [Vector3(-4, 2.5, -3), Color(1.0, 0.85, 0.7), 5.0], [Vector3(0, 5, 0), Color.WHITE, 4.0]]:
		var l := OmniLight3D.new()
		l.position = p[0]
		l.light_color = p[1]
		l.light_energy = p[2]
		l.omni_range = 14.0
		add_child(l)
	var spot := SpotLight3D.new()
	spot.position = Vector3(0, 6, 0)
	spot.rotation_degrees = Vector3(-90, 0, 0)
	spot.light_energy = 18.0
	spot.spot_range = 10.0
	spot.spot_angle = 35.0
	spot.shadow_enabled = true
	add_child(spot)
	_car_holder = Node3D.new()
	_car_holder.position = Vector3(0.6, 0, 0)
	add_child(_car_holder)
	_cam = Camera3D.new()
	_cam.fov = 38.0
	add_child(_cam)
	_set_car(_team)


func _set_car(t: int) -> void:
	_team = t
	if _car:
		_car.queue_free()
	_car = CarModel.new()
	var team := Teams.team(t)
	_car.build(team, int(team["drivers"][clampi(_driver, 0, 1)]["num"]), false)
	_car.set_compound(Tyres.get_data(String(Game.session["start_compound"]))["color"])
	_car_holder.add_child(_car)


func _process(dt: float) -> void:
	_orbit += dt * 0.18
	_car_holder.rotation.y = _orbit
	var cpos := Vector3(-2.2, 1.55, 6.6)
	_cam.position = cpos
	_cam.look_at(Vector3(-0.6, 0.35, 0), Vector3.UP)


# ======================================================================= telas
func _clear() -> void:
	for c in _panel.get_children():
		c.queue_free()


func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(440, 54)
	b.pressed.connect(cb)
	_panel.add_child(b)
	return b


func _header(text: String) -> void:
	_panel.add_child(UIKit.label(text, 26, Color.WHITE, true))


func _show_main() -> void:
	_screen = "main"
	_clear()
	var first := _button("CORRIDA RÁPIDA", func(): _show_setup(Game.Mode.QUICK_RACE))
	_button("CONTRA O RELÓGIO", func(): _show_setup(Game.Mode.TIME_TRIAL))
	_button("TREINO LIVRE", func(): _show_setup(Game.Mode.PRACTICE))
	_button("EQUIPES E CARROS", _show_teams)
	_button("OPÇÕES", _show_options)
	_button("SAIR", func(): get_tree().quit())
	_panel.add_child(UIKit.rect(Color(0, 0, 0, 0), Vector2(0, 20)))
	_panel.add_child(UIKit.label("Em breve: fim de semana completo (TL1–3, Q1–Q3,\nSprint, Corrida), campeonato e carreira.", 15, UIKit.MUTED))
	first.call_deferred("grab_focus")
	_update_info()


func _update_info() -> void:
	var team := Teams.team(_team)
	var d: Dictionary = team["drivers"][_driver]
	var eng := Teams.engine(String(team["engine"]))
	_info.text = "%s\n%s  #%d\nMotor %s %s" % [String(team["name"]).to_upper(), d["name"], int(d["num"]), eng["name"], eng.get("type", "")]


func _team_picker() -> void:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	var prev := Button.new()
	prev.text = "◀"
	var name_l := UIKit.label(Teams.team(_team)["name"], 20, Color.WHITE, true, HORIZONTAL_ALIGNMENT_CENTER)
	name_l.custom_minimum_size = Vector2(300, 46)
	var nxt := Button.new()
	nxt.text = "▶"
	hb.add_child(prev)
	hb.add_child(name_l)
	hb.add_child(nxt)
	_panel.add_child(hb)
	var drv := HBoxContainer.new()
	drv.add_theme_constant_override("separation", 8)
	_panel.add_child(drv)
	var refresh := func():
		name_l.text = Teams.team(_team)["name"]
		for c in drv.get_children():
			c.queue_free()
		for di in 2:
			var d: Dictionary = Teams.team(_team)["drivers"][di]
			var b := Button.new()
			b.text = "%s #%d" % [d["name"], int(d["num"])]
			b.custom_minimum_size = Vector2(216, 44)
			b.toggle_mode = true
			b.button_pressed = di == _driver
			b.add_theme_font_size_override("font_size", 16)
			b.pressed.connect(func():
				_driver = di
				Game.session["driver"] = di
				for x in drv.get_children():
					(x as Button).button_pressed = x == b
				_update_info())
			drv.add_child(b)
		_update_info()
	prev.pressed.connect(func():
		_set_car((_team - 1 + Teams.count()) % Teams.count())
		Game.session["team"] = _team
		refresh.call())
	nxt.pressed.connect(func():
		_set_car((_team + 1) % Teams.count())
		Game.session["team"] = _team
		refresh.call())
	refresh.call()


func _option(label: String, items: Array, current: int, cb: Callable) -> OptionButton:
	var hb := HBoxContainer.new()
	var l := UIKit.label(label, 18, UIKit.MUTED, true)
	l.custom_minimum_size = Vector2(190, 40)
	var ob := OptionButton.new()
	for it in items:
		ob.add_item(str(it))
	ob.selected = clampi(current, 0, items.size() - 1)
	ob.custom_minimum_size = Vector2(250, 40)
	ob.item_selected.connect(cb)
	hb.add_child(l)
	hb.add_child(ob)
	_panel.add_child(hb)
	return ob


func _slider(label: String, mn: float, mx: float, step: float, val: float, cb: Callable, fmt := "%d") -> HSlider:
	var hb := HBoxContainer.new()
	var l := UIKit.label(label, 18, UIKit.MUTED, true)
	l.custom_minimum_size = Vector2(190, 40)
	var s := HSlider.new()
	s.min_value = mn
	s.max_value = mx
	s.step = step
	s.value = val
	s.custom_minimum_size = Vector2(190, 40)
	var v := UIKit.label(fmt % val, 18, Color.WHITE)
	v.custom_minimum_size = Vector2(60, 40)
	s.value_changed.connect(func(x):
		v.text = fmt % x
		cb.call(x))
	hb.add_child(l)
	hb.add_child(s)
	hb.add_child(v)
	_panel.add_child(hb)
	return s


func _check(label: String, val: bool, cb: Callable) -> CheckButton:
	var c := CheckButton.new()
	c.text = label
	c.button_pressed = val
	c.toggled.connect(cb)
	_panel.add_child(c)
	return c


func _show_setup(mode: int) -> void:
	_screen = "setup"
	_clear()
	Game.session["mode"] = mode
	var s: Dictionary = Game.session
	_header(["CORRIDA RÁPIDA", "CONTRA O RELÓGIO", "TREINO LIVRE"][mode])
	_team_picker()
	_option("Circuito", Tracks.keys().map(func(k): return Tracks.get_data(k)["name"]), Tracks.keys().find(s["track"]), func(i): s["track"] = Tracks.keys()[i])
	if mode == Game.Mode.QUICK_RACE:
		var laps := [3, 5, 8, 10, 15, 20, 30, 61]
		_option("Voltas", laps.map(func(x): return ("%d (100%%)" % x) if x == 61 else str(x)), laps.find(int(s["laps"])), func(i): s["laps"] = laps[i])
	if mode != Game.Mode.TIME_TRIAL:
		_slider("Adversários", 0, 19, 1, float(s["ai_count"]), func(x): s["ai_count"] = int(x))
		_slider("Dificuldade IA", 40, 100, 1, float(s["difficulty"]), func(x): s["difficulty"] = int(x))
	_option("Clima", ["Seco", "Chuva leve", "Chuva forte"], int(s["weather"]), func(i): s["weather"] = i)
	var comps := ["soft", "medium", "hard", "inter", "wet"]
	_option("Pneu inicial", comps.map(func(k): return Tyres.get_data(k)["name"]), comps.find(s["start_compound"]), func(i):
		s["start_compound"] = comps[i]
		_car.set_compound(Tyres.get_data(comps[i])["color"]))
	var wear := [0.0, 1.0, 2.0, 3.0]
	_option("Desgaste pneus", ["Desligado", "Realista", "2x", "3x"], wear.find(float(s["tyre_wear"])), func(i): s["tyre_wear"] = wear[i])
	if mode == Game.Mode.QUICK_RACE:
		var grid := [-1, 0, 9, 19]
		_option("Largada", ["Pelo ritmo", "Pole position", "Meio do grid", "Último"], grid.find(int(s["grid_position"])), func(i): s["grid_position"] = grid[i])
		_check("Regra dos 2 compostos (corridas de 10+ voltas)", bool(s["mandatory_compounds"]), func(v): s["mandatory_compounds"] = v)
	var go := _button("▶  IR PARA A PISTA", func(): get_tree().change_scene_to_file("res://scenes/race.tscn"))
	go.add_theme_color_override("font_color", Color.WHITE)
	_button("Voltar", _show_main)
	go.call_deferred("grab_focus")


func _show_teams() -> void:
	_screen = "teams"
	_clear()
	_header("EQUIPES E CARROS")
	_team_picker()
	var lbl := UIKit.label("", 17, Color.WHITE)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.custom_minimum_size = Vector2(440, 0)
	_panel.add_child(lbl)
	var upd := func():
		var t := Teams.team(_team)
		var e := Teams.engine(String(t["engine"]))
		lbl.text = "Unidade de potência: %s (%s)\nPotência relativa: %.1f%%\nAerodinâmica relativa: %.1f%%\n\nOs nomes e pinturas são fictícios. Você pode editar\nscripts/data/teams.gd para criar suas próprias equipes." % [e["name"], e.get("type", ""), float(t["power"]) * float(e["power"]) * 100.0, float(t["aero"]) * 100.0]
	upd.call()
	for c in _panel.get_children():
		if c is HBoxContainer:
			for b in c.get_children():
				if b is Button:
					(b as Button).pressed.connect(upd)
			break
	_button("Voltar", _show_main)


func _show_options() -> void:
	_screen = "options"
	_clear()
	var st: Dictionary = Game.settings
	_header("OPÇÕES")
	_panel.add_child(UIKit.label("GRÁFICOS", 16, UIKit.ACCENT, true))
	_option("Qualidade", Weather.PRESETS.map(func(p): return p["name"]), int(st["graphics"]), func(i): st["graphics"] = i)
	_slider("Campo de visão", 50, 100, 1, float(st["fov"]), func(x): st["fov"] = x)
	_panel.add_child(UIKit.label("ÁUDIO", 16, UIKit.ACCENT, true))
	_slider("Volume geral", 0, 100, 1, float(st["master_volume"]) * 100.0, func(x):
		st["master_volume"] = x / 100.0
		Game.apply_audio())
	_slider("Volume do motor", 0, 150, 1, float(st["engine_volume"]) * 100.0, func(x): st["engine_volume"] = x / 100.0)
	_panel.add_child(UIKit.label("ASSISTÊNCIAS", 16, UIKit.ACCENT, true))
	_panel.add_child(UIKit.label("No teclado, desligar tudo deixa o carro como um F1 real: muito difícil.", 14, UIKit.MUTED))
	_check("ABS (freio antitravamento)", bool(st["abs"]), func(v): st["abs"] = v)
	_option("Controle de tração", ["Desligado", "Médio", "Total"], int(st["traction_control"]), func(i): st["traction_control"] = i)
	_check("Câmbio automático", bool(st["auto_gearbox"]), func(v): st["auto_gearbox"] = v)
	_check("Direção assistida", bool(st["steering_assist"]), func(v): st["steering_assist"] = v)
	_check("Controle de estabilidade", bool(st.get("stability", true)), func(v): st["stability"] = v)
	_check("Freio automático (segue a linha)", bool(st.get("auto_brake", false)), func(v): st["auto_brake"] = v)
	_check("Linha ideal na pista", bool(st["show_racing_line"]), func(v): st["show_racing_line"] = v)
	_check("Asa móvel automática", bool(st["auto_aero"]), func(v): st["auto_aero"] = v)
	_panel.add_child(UIKit.label("CONTROLES", 16, UIKit.ACCENT, true))
	_slider("Zona morta direção", 0, 30, 1, float(st["steer_deadzone"]) * 100.0, func(x): st["steer_deadzone"] = x / 100.0)
	_slider("Linearidade direção", 10, 25, 1, float(st["steer_linearity"]) * 10.0, func(x): st["steer_linearity"] = x / 10.0, "%d")
	_panel.add_child(UIKit.label("Teclado: W/S/A/D · E/Q marchas · Espaço asa · F ultrapassagem\nR modo ERS · P box · Tab estratégia · C câmera · V retrovisor\nControle (Xbox): gatilhos, analógico esquerdo, A/X marchas", 14, UIKit.MUTED))
	_button("Salvar e voltar", func():
		Game.save_settings()
		_show_main())


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") and _screen != "main":
		Game.save_settings()
		_show_main()
