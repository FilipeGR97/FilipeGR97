extends Node
## Autoload "Game": configuração da sessão, opções persistentes e mapa de controles.

const SETTINGS_PATH := "user://settings.cfg"

enum Mode { QUICK_RACE, TIME_TRIAL, PRACTICE }

# --- Configuração da próxima sessão (preenchida pelo menu) ---
var session := {
	"mode": Mode.QUICK_RACE,
	"track": "serra_azul",
	"team": 0,
	"driver": 0,
	"laps": 5,
	"ai_count": 19,
	"difficulty": 80,          # 0..100
	"weather": 0,              # 0 seco, 1 chuva leve, 2 chuva forte
	"start_compound": "medium",
	"tyre_wear": 1.0,          # multiplicador de desgaste
	"fuel_use": 1.0,
	"mandatory_compounds": true,
	"grid_position": -1,       # -1 = aleatória pelo ritmo
}

# --- Opções persistentes ---
var settings := {
	"graphics": 2,             # 0 baixo, 1 médio, 2 alto, 3 ultra
	"fov": 70.0,
	"master_volume": 0.8,
	"engine_volume": 1.0,
	"show_racing_line": true,
	"abs": true,
	"traction_control": 1,     # 0 off, 1 médio, 2 total
	"auto_gearbox": true,
	"steering_assist": true,   # limita o esterço ao que os pneus aguentam
	"stability": true,         # controle de estabilidade + contra-esterço
	"auto_brake": false,       # freio automático seguindo a linha ideal
	"pit_limiter_auto": true,
	"auto_aero": false,        # abre a asa móvel automaticamente
	"camera": 0,
	"steer_deadzone": 0.06,
	"steer_linearity": 1.3,
}

var last_results: Array = []


var _shots: Array = []      # ferramenta de desenvolvimento: "shots=120@a.png,300@b.png"
var _frame := 0
var dev_autodrive := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_input()
	load_settings()
	apply_audio()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("shots="):
			for part in a.substr(6).split(","):
				var kv := part.split("@")
				_shots.append([int(kv[0]), kv[1]])
		elif a.begins_with("cam="):
			settings["camera"] = int(a.substr(4))
		elif a.begins_with("weather="):
			session["weather"] = int(a.substr(8))
		elif a.begins_with("gfx="):
			settings["graphics"] = int(a.substr(4))
		elif a.begins_with("mode="):
			session["mode"] = int(a.substr(5))
		elif a.begins_with("laps="):
			session["laps"] = int(a.substr(5))
		elif a.begins_with("ai="):
			session["ai_count"] = int(a.substr(3))
		elif a == "autodrive":
			dev_autodrive = true


func _process(_dt: float) -> void:
	if _shots.is_empty():
		return
	_frame += 1
	var s: Array = _shots[0]
	if _frame >= int(s[0]):
		_shots.pop_front()
		print("shot frame %d fps %d" % [_frame, Engine.get_frames_per_second()])
		var rc := get_tree().current_scene
		if rc and rc.get("player"):
			var pc: Car = rc.player
			var cam: Camera3D = get_viewport().get_camera_3d()
			print("  car fwd=%s vel=%s v=%.0f look_back=%s pit=%d cam_fwd=%s cam_pos=%s car_pos=%s up=%s" % [-pc.global_transform.basis.z, pc.linear_velocity.normalized(), pc.kmh(), rc.camera.look_back, pc.pit_state, -cam.global_transform.basis.z, cam.global_position, pc.global_position, pc.global_transform.basis.y])
		var img := get_viewport().get_texture().get_image()
		img.save_png(String(s[1]))
		if _shots.is_empty():
			get_tree().quit()


# ---------------------------------------------------------------- opções
func load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(SETTINGS_PATH) != OK:
		return
	for k in settings.keys():
		settings[k] = cf.get_value("settings", k, settings[k])


func save_settings() -> void:
	var cf := ConfigFile.new()
	for k in settings.keys():
		cf.set_value("settings", k, settings[k])
	cf.save(SETTINGS_PATH)


func apply_audio() -> void:
	var v: float = settings["master_volume"]
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(v, 0.0001)))


# ---------------------------------------------------------------- controles
func _add_action(action: String, events: Array, deadzone := 0.2) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, deadzone)
	for e in events:
		InputMap.action_add_event(action, e)


func _key(code: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = code
	return e


func _joy_btn(b: JoyButton) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.button_index = b
	return e


func _joy_axis(a: JoyAxis, v: float) -> InputEventJoypadMotion:
	var e := InputEventJoypadMotion.new()
	e.axis = a
	e.axis_value = v
	return e


func _setup_input() -> void:
	_add_action("throttle", [_key(KEY_W), _key(KEY_UP), _joy_axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)], 0.05)
	_add_action("brake", [_key(KEY_S), _key(KEY_DOWN), _joy_axis(JOY_AXIS_TRIGGER_LEFT, 1.0)], 0.05)
	_add_action("steer_left", [_key(KEY_A), _key(KEY_LEFT), _joy_axis(JOY_AXIS_LEFT_X, -1.0)], 0.05)
	_add_action("steer_right", [_key(KEY_D), _key(KEY_RIGHT), _joy_axis(JOY_AXIS_LEFT_X, 1.0)], 0.05)
	_add_action("gear_up", [_key(KEY_E), _joy_btn(JOY_BUTTON_A), _joy_btn(JOY_BUTTON_RIGHT_SHOULDER)])
	_add_action("gear_down", [_key(KEY_Q), _joy_btn(JOY_BUTTON_X), _joy_btn(JOY_BUTTON_LEFT_SHOULDER)])
	_add_action("camera_next", [_key(KEY_C), _joy_btn(JOY_BUTTON_Y)])
	_add_action("look_back", [_key(KEY_V), _joy_btn(JOY_BUTTON_RIGHT_STICK)])
	_add_action("pit_request", [_key(KEY_P), _joy_btn(JOY_BUTTON_DPAD_UP)])
	_add_action("aero_mode", [_key(KEY_SPACE), _joy_btn(JOY_BUTTON_B)])
	_add_action("overtake", [_key(KEY_F), _joy_btn(JOY_BUTTON_LEFT_STICK)])
	_add_action("ers_mode", [_key(KEY_R), _joy_btn(JOY_BUTTON_DPAD_RIGHT)])
	_add_action("bias_fwd", [_key(KEY_BRACKETRIGHT)])
	_add_action("bias_rear", [_key(KEY_BRACKETLEFT)])
	_add_action("mfd", [_key(KEY_TAB), _joy_btn(JOY_BUTTON_BACK)])
	_add_action("mfd_next", [_key(KEY_PAGEDOWN), _joy_btn(JOY_BUTTON_DPAD_DOWN)])
	_add_action("reset_car", [_key(KEY_BACKSPACE)])
	_add_action("toggle_hud", [_key(KEY_H)])
	_add_action("pause", [_key(KEY_ESCAPE), _joy_btn(JOY_BUTTON_START)])


# ---------------------------------------------------------------- utilidades
static func fmt_time(t: float, plus := false) -> String:
	if t < 0.0 or is_inf(t) or is_nan(t):
		return "--:--.---"
	var m := int(t / 60.0)
	var s := t - m * 60.0
	var txt := ""
	if m > 0:
		txt = "%d:%06.3f" % [m, s]
	else:
		txt = "%.3f" % s
	return ("+" + txt) if plus else txt
