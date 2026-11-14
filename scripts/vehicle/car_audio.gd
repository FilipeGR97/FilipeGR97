class_name CarAudio
extends Node3D
## Som do carro.
## Motores com gravação (assets/audio/<motor>/, gerados por tools/build_engine_samples.py a partir de
## Sonsmotor/*.mp3): vários loops gravados em giros diferentes; o jogo mistura os dois mais próximos do
## rpm atual e ajusta a afinação, cruzando entre camada "acelerando" (on) e "aliviando" (off) pelo pedal.
## Trocas de marcha tocam um corte real gravado. Sem gravação, cai na síntese (harmônicos + distorção).

const RATE := 32000
const BASE_RPM := 6000.0
const LOOP_N := 16000            # 0,5 s -> todas as frequências múltiplas de 2 Hz fecham o loop
const XF := 480

static var _cache: Dictionary = {}

var car: Car
var spatial := false
var _on: Node
var _off: Node
var _whine: Node
var _tyre: Node
var _wind: Node
var _kerb: Node
var _shift_dip := 0.0
var _whine_amt := 0.3
var _pitch_k := 1.0
var _samples := false
var _arpm := 0.0
var _t_live := 0.0
var _live_k := 1.0
var _vol_jit := 0.0
var _phase := 0.0
const PITCH_MIN := 0.5
const PITCH_MAX := 1.4
var _on_layers: Array = []      # [{"p": player, "rpm": float, "streams": [...]}]
var _off_layers: Array = []
var _shift: Node
var _rng := RandomNumberGenerator.new()


func setup(p_car: Car, p_spatial: bool) -> void:
	car = p_car
	spatial = p_spatial
	var key := String(car.team["engine"])
	var prof: Dictionary = Teams.engine(key)["sound"]
	_rng.seed = hash(String(car.driver.get("name", "")))
	_phase = _rng.randf() * TAU
	if EngineSamples.DATA.has(key) and ResourceLoader.exists("res://assets/audio/%s/on_0.wav" % key):
		_samples = true
		_build_sample_layers(key)
	else:
		_on = _player(_engine_stream(key, prof, true), 0.0)
		_off = _player(_engine_stream(key, prof, false), -6.0)
	_whine_amt = float(prof.get("whine", 0.0))
	_whine = _player(_tone_stream("whine", [[1200.0, 1.0], [2400.0, 0.35], [3600.0, 0.12]]), -18.0)
	# cada equipe com afinação levemente diferente (escapamento/mapa), mesmo com o mesmo motor
	_pitch_k = 1.0 + float((hash(String(car.team["name"])) % 7) - 3) * 0.005
	if not spatial:
		_tyre = _player(_noise_stream("tyre", 0.12, 0.35), -40.0)
		_wind = _player(_noise_stream("wind", 0.02, 0.0), -40.0)
		_kerb = _player(_kerb_stream(), -40.0)


func _player(stream: AudioStream, vol: float) -> Node:
	var p: Node
	if spatial:
		var p3 := AudioStreamPlayer3D.new()
		p3.stream = stream
		p3.unit_size = 14.0
		p3.max_distance = 450.0
		p3.volume_db = vol - 3.0
		p3.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_PHYSICS_STEP
		p3.attenuation_filter_cutoff_hz = 4200.0      # adversários abafados (o seu motor fica nítido)
		p3.attenuation_filter_db = -18.0
		p3.max_polyphony = 1
		p = p3
	else:
		var p2 := AudioStreamPlayer.new()
		p2.stream = stream
		p2.volume_db = vol
		p = p2
	add_child(p)
	if stream:
		p.call_deferred("play")
	return p


func _build_sample_layers(key: String) -> void:
	var data: Dictionary = EngineSamples.DATA[key]
	for kind in ["on", "off"]:
		var list: Array = data[kind]
		var layers: Array = _on_layers if kind == "on" else _off_layers
		if spatial:
			# carros da IA: 2 vozes por camada — uma toca os loops de índice par, outra os ímpares.
			# Entre dois loops vizinhos sempre há um par e um ímpar; quando o giro passa para o próximo par
			# de loops, quem troca de gravação é a voz que já está com volume ~0 (sem estalo).
			var rpms := []
			var streams := []
			for e in list:
				rpms.append(float(e["rpm"]))
				streams.append(_sample("res://assets/audio/%s/%s" % [key, e["file"]]))
			var pe := _player(streams[0], -80.0)
			var po := _player(streams[mini(1, streams.size() - 1)], -80.0)
			layers.append({"pe": pe, "po": po, "rpms": rpms, "streams": streams, "ce": 0, "co": mini(1, streams.size() - 1)})
		else:
			for e in list:
				var p := _player(_sample("res://assets/audio/%s/%s" % [key, e["file"]]), -80.0)
				layers.append({"p": p, "rpm": float(e["rpm"])})
	if EngineSamples.SHIFT_COUNT > 0:
		_shift = _player(null, -80.0)


static func _sample(path: String) -> AudioStream:
	if _cache.has(path):
		return _cache[path]
	var st: AudioStream = load(path)
	var w := st as AudioStreamWAV
	if w and w.loop_mode == AudioStreamWAV.LOOP_DISABLED and not path.get_file().begins_with("shift"):
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = int(w.get_length() * w.mix_rate)
	_cache[path] = st
	return st


func on_shift() -> void:
	_shift_dip = 1.0
	if _shift and EngineSamples.SHIFT_COUNT > 0:
		var p: Node = _shift
		p.set("stream", _sample("res://assets/audio/shift_%d.wav" % _rng.randi_range(0, EngineSamples.SHIFT_COUNT - 1)))
		p.set("pitch_scale", _rng.randf_range(0.92, 1.08) * clampf(car.rpm / 11000.0, 0.7, 1.2))
		var ev: float = Game.settings["engine_volume"]
		p.set("volume_db", linear_to_db(maxf(ev, 0.001)) - (9.0 if spatial else 4.0))
		p.call("play")


## Pesos de mistura (potência constante) entre os loops vizinhos do rpm atual.
static func _weights(rpms: Array, rpm: float) -> PackedFloat32Array:
	var w := PackedFloat32Array()
	w.resize(rpms.size())
	if rpm <= float(rpms[0]):
		w[0] = 1.0
		return w
	for i in range(rpms.size() - 1):
		var a: float = rpms[i]
		var b: float = rpms[i + 1]
		if rpm <= b:
			var t := clampf((rpm - a) / maxf(b - a, 1.0), 0.0, 1.0)
			# só mistura na faixa central (40%) entre os dois loops: menos tempo com dois sons somados ("oco")
			t = clampf((t - 0.3) / 0.4, 0.0, 1.0)
			w[i] = cos(t * PI * 0.5)
			w[i + 1] = sin(t * PI * 0.5)
			return w
	w[rpms.size() - 1] = 1.0
	return w


func _update_samples(base: float, ld: float, dip: float, rpm: float) -> void:
	var rpm_k := clampf((rpm - 4000.0) / 8000.0, 0.0, 1.0)
	var own := 0.0 if not spatial else -5.0      # carro do jogador em destaque; adversários mais baixos
	var on_db := base + own + lerpf(-14.0, 0.0, ld) + dip + rpm_k * 2.5 + _vol_jit
	var off_db := base + own + lerpf(-3.0, -34.0, ld) + dip - (1.0 - rpm_k) * 3.0 + _vol_jit
	for kind in 2:
		var layers: Array = _on_layers if kind == 0 else _off_layers
		var db := on_db if kind == 0 else off_db
		if spatial:
			var L: Dictionary = layers[0]
			var rpms: Array = L["rpms"]
			var w := _weights(rpms, rpm)
			# índices ativos (no máximo 2 vizinhos)
			var ie := -1
			var io := -1
			for i in rpms.size():
				if w[i] > 0.0005:
					if i % 2 == 0:
						ie = i
					else:
						io = i
			for par in 2:
				var idx := ie if par == 0 else io
				var p: Node = L["pe"] if par == 0 else L["po"]
				var ck := "ce" if par == 0 else "co"
				if idx < 0:
					_apply(p, 1.0, -80.0)
					continue
				if idx != int(L[ck]):
					L[ck] = idx
					p.set("stream", L["streams"][idx])
					p.call("play")
				var lin := float(w[idx])
				_apply(p, clampf(rpm / float(rpms[idx]) * _pitch_k, PITCH_MIN, PITCH_MAX), db + linear_to_db(maxf(lin, 0.0001)))
		else:
			var rpms := []
			for L in layers:
				rpms.append(L["rpm"])
			var w := _weights(rpms, rpm)
			for i in layers.size():
				var L: Dictionary = layers[i]
				var lin := float(w[i])
				var vdb := db + (linear_to_db(lin) if lin > 0.001 else -80.0)
				_apply(L["p"], clampf(rpm / float(L["rpm"]) * _pitch_k, PITCH_MIN, PITCH_MAX), vdb)


func _process(dt: float) -> void:
	if car == null:
		return
	var ev: float = Game.settings["engine_volume"]
	_t_live += dt
	_live_k = 1.0 + 0.0035 * sin(_t_live * 0.83 + _phase) + 0.0022 * sin(_t_live * 2.31 + _phase * 1.7) + 0.0012 * sin(_t_live * 5.7)
	_vol_jit = 0.6 * sin(_t_live * 1.37 + _phase) + 0.35 * sin(_t_live * 3.9 + _phase * 0.5)
	_arpm = move_toward(_arpm if _arpm > 0.0 else car.rpm, car.rpm, dt * 70000.0)
	var rpm := _arpm * _live_k
	var pitch := clampf(rpm / BASE_RPM * _pitch_k, 0.55, 2.3)
	var thr := car.throttle_eff
	_shift_dip = maxf(_shift_dip - dt * 12.0, 0.0)
	var ld := clampf(thr * 1.15, 0.0, 1.0)
	var base := linear_to_db(maxf(ev, 0.001))
	# troca de marcha: corte curto da ignição (~70 ms), como nas gravações
	var dip := -14.0 * _shift_dip * _shift_dip
	var rpm_k := clampf((rpm - 4000.0) / 8500.0, 0.0, 1.0)
	if _samples:
		_update_samples(base, ld, dip, rpm)
	else:
		_apply(_on, pitch, base + lerpf(-11.0, 0.0, ld) + dip + rpm_k * 3.0)
		_apply(_off, pitch, base + lerpf(-2.0 + rpm_k * 2.0, -24.0, ld) + dip)
	# turbo + MGU-K (assobio elétrico)
	var whine_pitch := clampf(0.4 + rpm / 12500.0 * 0.9 + car.ers_deploy_kw / 350.0 * 0.15, 0.3, 1.6)
	# MGU-K (elétrico) existe em todos; turbo só nos motores turbo
	var turbo := linear_to_db(maxf(_whine_amt / 0.35, 0.05)) * 0.5
	# com gravação real o turbo/MGU-K já está no som; o assobio sintético só criava batimento ("na na na")
	var whine_db := base - 26.0 + car.ers_deploy_kw / 350.0 * 8.0 + ld * 4.0 * _whine_amt / 0.35 + turbo
	if _samples:
		whine_db = -80.0
	_apply(_whine, whine_pitch, whine_db)
	if not spatial:
		var slip := 0.0
		var kerb := 0.0
		for w in car.wheels:
			var wh: Car.Wheel = w
			if wh.grounded:
				# só canta quando passa do pico de aderência (escorregamento combinado > 1)
				var comb := sqrt(pow(wh.sy / Car.AY_PEAK, 2) + pow(wh.sx / Car.KX_PEAK, 2))
				slip = maxf(slip, clampf((comb - 1.05) * 1.2, 0.0, 1.0))
				if wh.surface == Track.Surface.KERB or wh.surface == Track.Surface.GRAVEL:
					kerb = 1.0
		slip *= clampf(car.speed / 8.0, 0.0, 1.0)
		if car.wetness > 0.3:
			slip *= 0.3
		_apply(_tyre, 0.9 + slip * 0.2, base - 44.0 + slip * 26.0)
		_apply(_wind, 0.6 + car.speed / 90.0 * 0.8, base - 48.0 + clampf(car.speed / 90.0, 0.0, 1.0) * 22.0)
		_apply(_kerb, 0.7 + car.speed / 100.0, base - 50.0 + kerb * clampf(car.speed / 25.0, 0.0, 1.0) * 30.0)


func _apply(p: Node, pitch: float, db: float) -> void:
	if p == null:
		return
	p.set("pitch_scale", pitch)
	p.set("volume_db", clampf(db, -80.0, 12.0))


# ======================================================================= síntese
static func _to_wav(buf: PackedFloat32Array) -> AudioStreamWAV:
	var peak := 0.0001
	for x in buf:
		peak = maxf(peak, absf(x))
	var data := PackedByteArray()
	data.resize(LOOP_N * 2)
	for i in LOOP_N:
		data.encode_s16(i * 2, int(clampf(buf[i] / peak * 0.85, -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_begin = 0
	w.loop_end = LOOP_N
	return w


static func _crossfade(buf: PackedFloat32Array) -> PackedFloat32Array:
	# buf tem LOOP_N + XF amostras; mistura a cauda no início para o loop não estalar
	for j in XF:
		var t := float(j) / XF
		buf[j] = lerpf(buf[LOOP_N + j], buf[j], t)
	return buf


static func _engine_stream(key: String, prof: Dictionary, on: bool) -> AudioStream:
	var ck := "%s_%s" % [key, "on" if on else "off"]
	if _cache.has(ck):
		return _cache[ck]
	var rec := "res://assets/audio/%s.ogg" % ck
	if ResourceLoader.exists(rec):
		var s: AudioStream = load(rec)
		_cache[ck] = s
		return s
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(ck)
	var harm: Array = prof["harm"]
	var orders: Array = prof["orders"]     # múltiplos de rpm/120 (meia ordem)
	var f0 := BASE_RPM / 120.0
	var cyl := float(prof.get("cyl", 6))
	var uneven := float(prof.get("uneven", 0.0))
	var ph := []
	for k in orders.size():
		ph.append(rng.randf() * TAU)
	var drive: float = prof["drive"] * (1.0 if on else 0.6)
	var noise_amt: float = prof["noise"] * (1.0 if on else 1.6)
	var rasp: float = prof["rasp"]
	var total := LOOP_N + XF
	var buf := PackedFloat32Array()
	buf.resize(total)
	var lp := 0.0
	var lp2 := 0.0
	var fire := f0 * cyl
	for i in total:
		var t := float(i) / RATE
		var s := 0.0
		for k in orders.size():
			var a: float = harm[k]
			if not on and float(orders[k]) > cyl:
				a *= 0.5
			s += a * sin(TAU * f0 * float(orders[k]) * t + ph[k])
		# pulso de combustão modula o ruído (dá o "rasgado"); V8 tem queima irregular (ronco)
		var env := pow(0.5 + 0.5 * sin(TAU * fire * t), 6.0)
		if uneven > 0.0:
			env *= 1.0 - uneven + uneven * (0.5 + 0.5 * sin(TAU * f0 * t + 1.3)) * 2.0
		var wn := rng.randf_range(-1.0, 1.0)
		lp += (wn - lp) * 0.35
		lp2 += (lp - lp2) * 0.5
		s += (lp2 * 1.5 + wn * rasp * 0.5) * noise_amt * (0.3 + env * 1.7)
		if not on and rng.randf() < 0.0009:
			s += rng.randf_range(-3.0, 3.0)    # estalos de escape no alívio
		buf[i] = tanh(s * drive * 0.45)
	var st := _to_wav(_crossfade(buf))
	_cache[ck] = st
	return st


static func _tone_stream(ck: String, partials: Array) -> AudioStream:
	if _cache.has(ck):
		return _cache[ck]
	var buf := PackedFloat32Array()
	buf.resize(LOOP_N + XF)
	for i in LOOP_N + XF:
		var t := float(i) / RATE
		var s := 0.0
		for p in partials:
			s += float(p[1]) * sin(TAU * float(p[0]) * t)
		buf[i] = s
	var st := _to_wav(buf)
	_cache[ck] = st
	return st


static func _noise_stream(ck: String, cut: float, band: float) -> AudioStream:
	if _cache.has(ck):
		return _cache[ck]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(ck)
	var buf := PackedFloat32Array()
	buf.resize(LOOP_N + XF)
	var a := 0.0
	var b := 0.0
	for i in LOOP_N + XF:
		var wn := rng.randf_range(-1.0, 1.0)
		a += (wn - a) * cut
		b += (a - b) * cut
		var s := b
		if band > 0.0:
			s = (a - b) * 3.0 + sin(TAU * 1800.0 * float(i) / RATE) * band * (0.5 + 0.5 * a)
		buf[i] = s
	var st := _to_wav(_crossfade(buf))
	_cache[ck] = st
	return st


static func _kerb_stream() -> AudioStream:
	if _cache.has("kerb"):
		return _cache["kerb"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var buf := PackedFloat32Array()
	buf.resize(LOOP_N + XF)
	var lp := 0.0
	for i in LOOP_N + XF:
		var t := float(i) / RATE
		var env := pow(0.5 + 0.5 * sin(TAU * 40.0 * t), 3.0)
		lp += (rng.randf_range(-1.0, 1.0) - lp) * 0.08
		buf[i] = lp * env * 4.0 + sin(TAU * 80.0 * t) * env * 0.4
	var st := _to_wav(_crossfade(buf))
	_cache["kerb"] = st
	return st
