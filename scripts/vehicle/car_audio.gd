class_name CarAudio
extends Node3D
## Som do carro. Cada fornecedor de motor tem um timbre próprio, sintetizado na inicialização
## (harmônicos de V6 turbo + distorção + ruído de admissão/escape), tocado em loops que mudam
## de afinação com o RPM e cruzam entre "acelerando" e "aliviando".
## Para usar gravações reais: coloque res://assets/audio/<motor>_on.ogg e <motor>_off.ogg
## (loops gravados a 6000 rpm) — eles substituem a síntese automaticamente.

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


func setup(p_car: Car, p_spatial: bool) -> void:
	car = p_car
	spatial = p_spatial
	var key := String(car.team["engine"])
	var prof: Dictionary = Teams.engine(key)["sound"]
	_on = _player(_engine_stream(key, prof, true), 0.0)
	_off = _player(_engine_stream(key, prof, false), -6.0)
	_whine = _player(_tone_stream("whine", [[1200.0, 1.0], [2400.0, 0.35], [3600.0, 0.12]]), -18.0)
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
		p3.attenuation_filter_cutoff_hz = 9000.0
		p3.max_polyphony = 1
		p = p3
	else:
		var p2 := AudioStreamPlayer.new()
		p2.stream = stream
		p2.volume_db = vol
		p = p2
	add_child(p)
	p.call_deferred("play")
	return p


func on_shift() -> void:
	_shift_dip = 1.0


func _process(dt: float) -> void:
	if car == null:
		return
	var ev: float = Game.settings["engine_volume"]
	var rpm := car.rpm
	var pitch := clampf(rpm / BASE_RPM, 0.55, 2.25)
	var thr := car.throttle_eff
	_shift_dip = maxf(_shift_dip - dt * 12.0, 0.0)
	var ld := clampf(thr * 1.15, 0.0, 1.0)
	var base := linear_to_db(maxf(ev, 0.001))
	var dip := -9.0 * _shift_dip
	var rpm_k := clampf((rpm - 4000.0) / 8500.0, 0.0, 1.0)
	_apply(_on, pitch, base + lerpf(-11.0, 0.0, ld) + dip + rpm_k * 3.0)
	_apply(_off, pitch, base + lerpf(-2.0 + rpm_k * 2.0, -24.0, ld) + dip)
	# turbo + MGU-K (assobio elétrico)
	var whine_pitch := clampf(0.4 + rpm / 12500.0 * 0.9 + car.ers_deploy_kw / 350.0 * 0.15, 0.3, 1.6)
	_apply(_whine, whine_pitch, base - 24.0 + car.ers_deploy_kw / 350.0 * 8.0 + ld * 4.0)
	if not spatial:
		var slip := 0.0
		var kerb := 0.0
		for w in car.wheels:
			var wh: Car.Wheel = w
			if wh.grounded:
				slip = maxf(slip, clampf((absf(wh.sy) / Car.AY_PEAK + absf(wh.sx) / Car.KX_PEAK - 0.85) * 0.8, 0.0, 1.0))
				if wh.surface == Track.Surface.KERB or wh.surface == Track.Surface.GRAVEL:
					kerb = 1.0
		slip *= clampf(car.speed / 8.0, 0.0, 1.0)
		if car.wetness > 0.3:
			slip *= 0.3
		_apply(_tyre, 0.9 + slip * 0.2, base - 40.0 + slip * 34.0)
		_apply(_wind, 0.6 + car.speed / 90.0 * 0.8, base - 45.0 + clampf(car.speed / 90.0, 0.0, 1.0) * 30.0)
		_apply(_kerb, 0.7 + car.speed / 100.0, base - 50.0 + kerb * clampf(car.speed / 25.0, 0.0, 1.0) * 42.0)


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
	var orders := [1.0, 2.0, 3.0, 6.0, 9.0, 12.0, 15.0, 18.0]   # múltiplos de rpm/120 (meia ordem)
	var f0 := BASE_RPM / 120.0
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
	var fire := f0 * 6.0
	for i in total:
		var t := float(i) / RATE
		var s := 0.0
		for k in orders.size():
			var a: float = harm[k]
			if not on and k >= 5:
				a *= 0.5
			s += a * sin(TAU * f0 * orders[k] * t + ph[k])
		# pulso de combustão modula o ruído (dá o "rasgado")
		var env := pow(0.5 + 0.5 * sin(TAU * fire * t), 6.0)
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
