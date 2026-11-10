class_name Track
extends Node3D
## Circuito gerado proceduralmente a partir de uma spline.
## Gera: asfalto, zebras, áreas de escape (grama/brita/asfalto), muros, alambrado, pit lane com garagens,
## arquibancadas, pontes, árvores, placas de frenagem, pórtico de largada — e os dados usados pela IA
## (traçado ideal, perfil de velocidade, zonas de asa móvel).

enum Surface { ASPHALT, KERB, GRASS, GRAVEL, WALL }
const SURFACE_GRIP := [1.0, 0.94, 0.6, 0.58, 0.3]
const SURFACE_DRAG := [0.0, 0.004, 0.05, 0.16, 0.0]   # resistência extra (fração de Fz)

const DS := 2.0                 # espaçamento das amostras (m)
const APRON := 1.5              # faixa logo após a linha branca (zebra ou asfalto)
const WALL_H := 1.1
const PIT_TAPER := 160.0
const PIT_ZONE_W := 17.0

var def: Dictionary
var length := 0.0
var n := 0
var ds := DS
var half_width := 7.0
var wetness := 0.0

var pos := PackedVector3Array()
var tang := PackedVector3Array()
var right := PackedVector3Array()
var up := PackedVector3Array()
var curv := PackedFloat32Array()
var kerb := PackedByteArray()
var run_w := [PackedFloat32Array(), PackedFloat32Array()]   # [esquerda, direita]
var run_s := [PackedByteArray(), PackedByteArray()]         # tipo de superfície do escape
var line_off := PackedFloat32Array()
var speed_prof := PackedFloat32Array()
var aero_zone := PackedByteArray()
var aero_zones: Array = []           # [[s_ini, s_fim], ...]
var overtake_detect_s := 0.0

# pit
var pit_side := 1
var pit_entry_s := 0.0
var pit_len := 0.0
var pit_lane_off := 0.0
var pit_box_off := 0.0
var pit_speed := 22.2
var box_u: Array = []                # posição (u ao longo do pit) de cada equipe

var grid_slots: Array = []           # Transform3D
var tv_cams: Array = []              # Vector3
var minimap_pts := PackedVector2Array()
var bounds := Rect2()

var _light_mats: Array = []
var _quality := 2
var _noise_tex: NoiseTexture2D
var _normal_tex: NoiseTexture2D
var _road_mats: Array = []
var _terrain_mats: Array = []


# ======================================================================= construção
func build(track_def: Dictionary, wet: float, quality: int) -> void:
	def = track_def
	wetness = wet
	_quality = quality
	half_width = float(def.get("width", 14.0)) * 0.5
	pit_side = int(def.get("pit_side", 1))
	pit_speed = float(def.get("pit_speed_kmh", 80.0)) / 3.6
	_sample_spline()
	_analyse()
	_compute_racing_line()
	_compute_speed_profile(1.5)
	_compute_aero_zones()
	_setup_pit()
	_make_textures()
	_build_surfaces()
	_build_walls()
	_build_pit_buildings()
	_build_start_area()
	_build_scenery()
	_compute_grid()
	_compute_minimap()


# ---------------------------------------------------------------- spline
static func _cr(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: float) -> Vector3:
	# Catmull-Rom centrípeta (sem laços / sobreposição)
	var t0 := 0.0
	var t1 := t0 + pow(maxf(p0.distance_to(p1), 0.001), 0.5)
	var t2 := t1 + pow(maxf(p1.distance_to(p2), 0.001), 0.5)
	var t3 := t2 + pow(maxf(p2.distance_to(p3), 0.001), 0.5)
	var tt := lerpf(t1, t2, t)
	var a1 := p0 * (t1 - tt) / (t1 - t0) + p1 * (tt - t0) / (t1 - t0)
	var a2 := p1 * (t2 - tt) / (t2 - t1) + p2 * (tt - t1) / (t2 - t1)
	var a3 := p2 * (t3 - tt) / (t3 - t2) + p3 * (tt - t2) / (t3 - t2)
	var b1 := a1 * (t2 - tt) / (t2 - t0) + a2 * (tt - t0) / (t2 - t0)
	var b2 := a2 * (t3 - tt) / (t3 - t1) + a3 * (tt - t1) / (t3 - t1)
	return b1 * (t2 - tt) / (t2 - t1) + b2 * (tt - t1) / (t2 - t1)


func _sample_spline() -> void:
	var cp: Array = []
	for p in def["points"]:
		cp.append(Vector3(float(p[0]), float(p[2]) if p.size() > 2 else 0.0, float(p[1])))
	var m := cp.size()
	# amostragem densa
	var dense := PackedVector3Array()
	for i in m:
		for k in 30:
			dense.append(_cr(cp[(i - 1 + m) % m], cp[i], cp[(i + 1) % m], cp[(i + 2) % m], k / 30.0))
	dense.append(dense[0])
	var cum := PackedFloat32Array()
	cum.append(0.0)
	for i in range(1, dense.size()):
		cum.append(cum[i - 1] + Vector2(dense[i].x - dense[i - 1].x, dense[i].z - dense[i - 1].z).length())
	length = cum[cum.size() - 1]
	n = int(round(length / DS))
	ds = length / n
	pos.resize(n)
	var j := 0
	for i in n:
		var s := i * ds
		while j < cum.size() - 2 and cum[j + 1] < s:
			j += 1
		var f := (s - cum[j]) / maxf(cum[j + 1] - cum[j], 0.0001)
		pos[i] = dense[j].lerp(dense[j + 1], f)
	# suaviza a altimetria
	for it in 3:
		var ys := PackedFloat32Array()
		ys.resize(n)
		for i in n:
			var acc := 0.0
			for k in range(-10, 11):
				acc += pos[(i + k + n) % n].y
			ys[i] = acc / 21.0
		for i in n:
			pos[i].y = ys[i]


func _analyse() -> void:
	tang.resize(n); right.resize(n); up.resize(n); curv.resize(n); kerb.resize(n)
	for i in n:
		var t := (pos[(i + 1) % n] - pos[(i - 1 + n) % n]).normalized()
		tang[i] = t
		var r := t.cross(Vector3.UP).normalized()
		right[i] = r
		up[i] = r.cross(t).normalized()
	for i in n:
		var t1 := tang[(i - 2 + n) % n]
		var t2 := tang[(i + 2) % n]
		var a := atan2(t1.z * t2.x - t1.x * t2.z, t1.x * t2.x + t1.z * t2.z)
		curv[i] = a / (4.0 * ds)
	# suaviza curvatura
	var sm := PackedFloat32Array()
	sm.resize(n)
	for i in n:
		var acc := 0.0
		for k in range(-3, 4):
			acc += curv[(i + k + n) % n]
		sm[i] = acc / 7.0
	curv = sm
	# zebras onde o raio < 230 m (dilatado)
	var raw := PackedByteArray()
	raw.resize(n)
	for i in n:
		raw[i] = 1 if absf(curv[i]) > 1.0 / 230.0 else 0
	for i in n:
		var on := 0
		for k in range(-9, 10):
			if raw[(i + k + n) % n] == 1:
				on = 1
				break
		kerb[i] = on
	# áreas de escape
	for side in 2:
		var sd := -1.0 if side == 0 else 1.0
		var w := PackedFloat32Array()
		var st := PackedByteArray()
		w.resize(n); st.resize(n)
		for i in n:
			w[i] = 14.0
			st[i] = Surface.GRASS
		for i in n:
			var c := curv[i]
			var outside := (c > 0.0 and sd > 0.0) or (c < 0.0 and sd < 0.0)
			if outside and absf(c) > 1.0 / 190.0:
				var typ := Surface.GRAVEL
				var ww := 24.0
				if absf(c) > 1.0 / 45.0:
					typ = Surface.ASPHALT
					ww = 20.0
				for k in range(-6, 26):
					var q := (i + k + n) % n
					if st[q] != Surface.ASPHALT or typ == Surface.ASPHALT:
						st[q] = typ
					w[q] = maxf(w[q], ww)
		run_w[side] = w
		run_s[side] = st


func idx(i: int) -> int:
	return ((i % n) + n) % n


func idx_at_s(s: float) -> int:
	return idx(int(round(s / ds)))


func wrap_s(s: float) -> float:
	return fposmod(s, length)


func point(i: int, lateral: float, h := 0.0) -> Vector3:
	i = idx(i)
	return pos[i] + right[i] * lateral + up[i] * h


func point_s(s: float, lateral: float) -> Vector3:
	s = wrap_s(s)
	var f := s / ds
	var i0 := int(floor(f))
	var t := f - i0
	var a := point(i0, lateral)
	var b := point(i0 + 1, lateral)
	return a.lerp(b, t)


func frame(i: int, lateral: float, h := 0.0) -> Transform3D:
	i = idx(i)
	return Transform3D(Basis(right[i], up[i], -tang[i]), point(i, lateral, h))


## Índice da amostra mais próxima (busca local em torno de hint; hint<0 = busca total).
func locate(p: Vector3, hint := -1, window := 30) -> int:
	var best := -1
	var bd := INF
	if hint < 0:
		for i in range(0, n, 4):
			var d := Vector2(pos[i].x - p.x, pos[i].z - p.z).length_squared()
			if d < bd:
				bd = d
				best = i
		hint = best
		window = 6
	for k in range(-window, window + 1):
		var i := idx(hint + k)
		var d := Vector2(pos[i].x - p.x, pos[i].z - p.z).length_squared()
		if d < bd:
			bd = d
			best = i
	return best


func lateral_of(p: Vector3, i: int) -> float:
	return (p - pos[i]).dot(right[i])


func s_of(p: Vector3, i: int) -> float:
	return wrap_s(i * ds + (p - pos[i]).dot(tang[i]))


# ---------------------------------------------------------------- traçado ideal
func _compute_racing_line() -> void:
	var lim := half_width - 1.3
	var step := 4
	var m := n / step
	var o := PackedFloat32Array()
	o.resize(m)
	var cpos := PackedVector2Array()
	var crt := PackedVector2Array()
	cpos.resize(m); crt.resize(m)
	for k in m:
		cpos[k] = Vector2(pos[k * step].x, pos[k * step].z)
		crt[k] = Vector2(right[k * step].x, right[k * step].z)
	var q := PackedVector2Array()
	q.resize(m)
	for it in 600:
		for k in m:
			q[k] = cpos[k] + crt[k] * o[k]
		for k in m:
			var mid := (q[(k - 1 + m) % m] + q[(k + 1) % m]) * 0.5
			var target := (mid - cpos[k]).dot(crt[k])
			o[k] = clampf(lerpf(o[k], target, 0.6), -lim, lim)
	line_off.resize(n)
	for i in n:
		var f := float(i) / step
		var k0 := int(floor(f)) % m
		var k1 := (k0 + 1) % m
		line_off[i] = lerpf(o[k0], o[k1], f - floor(f))
	# refino na resolução total
	var qf := PackedVector2Array()
	qf.resize(n)
	for it in 60:
		for i in n:
			qf[i] = Vector2(pos[i].x, pos[i].z) + Vector2(right[i].x, right[i].z) * line_off[i]
		for i in n:
			var mid := (qf[(i - 1 + n) % n] + qf[(i + 1) % n]) * 0.5
			var target := (mid - Vector2(pos[i].x, pos[i].z)).dot(Vector2(right[i].x, right[i].z))
			line_off[i] = clampf(lerpf(line_off[i], target, 0.5), -lim, lim)


func line_point(i: int, extra := 0.0) -> Vector3:
	i = idx(i)
	return point(i, clampf(line_off[i] + extra, -half_width + 1.0, half_width - 1.0))


## Perfil de velocidade máxima (m/s) ao longo do traçado ideal.
func _compute_speed_profile(mu: float) -> void:
	var g := 9.81
	var m := 800.0
	var cla := 4.0
	var cda := 1.35
	var rho := 1.2
	var kq := rho * cla / (2.0 * m)
	var kd := rho * cda / (2.0 * m)
	var vtop := 95.0
	var p := PackedVector2Array()
	p.resize(n)
	for i in n:
		var lp := line_point(i)
		p[i] = Vector2(lp.x, lp.z)
	var kap := PackedFloat32Array()
	kap.resize(n)
	for i in n:
		var a := p[idx(i - 4)]
		var b := p[i]
		var c := p[idx(i + 4)]
		var ab := a.distance_to(b)
		var bc := b.distance_to(c)
		var ca := c.distance_to(a)
		var cross := absf((b - a).cross(c - a))
		kap[i] = 2.0 * cross / maxf(ab * bc * ca, 0.0001)
	speed_prof.resize(n)
	for i in n:
		var acc := 0.0
		for k in range(-3, 4):
			acc += kap[idx(i + k)]
		var kk := acc / 7.0
		var den := kk - mu * kq
		var v := vtop
		if den > 0.0:
			v = minf(vtop, sqrt(mu * g / den))
		speed_prof[i] = v
	var mub := mu * 0.92
	for _p in 2:
		for j in range(n - 1, -1, -1):
			var nx := speed_prof[idx(j + 1)]
			var ab := mub * (g + kq * nx * nx) + kd * nx * nx
			speed_prof[j] = minf(speed_prof[j], sqrt(nx * nx + 2.0 * ab * ds))
	for _p in 2:
		for j in n:
			var pv := speed_prof[idx(j - 1)]
			var aa := minf(mu * 0.55 * (g + kq * pv * pv), 700000.0 / (m * maxf(pv, 5.0))) - kd * pv * pv
			speed_prof[j] = minf(speed_prof[j], sqrt(maxf(pv * pv + 2.0 * maxf(aa, 0.0) * ds, 0.0)))


func _compute_aero_zones() -> void:
	aero_zone.resize(n)
	var straight := PackedByteArray()
	straight.resize(n)
	for i in n:
		straight[i] = 1 if absf(curv[i]) < 1.0 / 650.0 and speed_prof[i] > 55.0 else 0
	# encontra início de um trecho não-reto para varrer de forma circular
	var start := 0
	for i in n:
		if straight[i] == 0:
			start = i
			break
	var i := 0
	var best_len := 0.0
	aero_zones.clear()
	while i < n:
		var j := idx(start + i)
		if straight[j] == 1:
			var k := i
			while k < n and straight[idx(start + k)] == 1:
				k += 1
			var run_len := (k - i) * ds
			if run_len >= 280.0:
				var s0 := wrap_s((start + i) * ds + 40.0)
				var s1 := wrap_s((start + k) * ds - 120.0)
				aero_zones.append([s0, s1])
				for q in range(i + 20, k - 60):
					aero_zone[idx(start + q)] = 1
				if run_len > best_len:
					best_len = run_len
					overtake_detect_s = wrap_s(s0 - 120.0)
			i = k
		else:
			i += 1


# ---------------------------------------------------------------- pit lane
func _setup_pit() -> void:
	var entry := float(def.get("pit_entry", 380.0))
	var ex := float(def.get("pit_exit", 420.0))
	pit_entry_s = wrap_s(-entry)
	pit_len = entry + ex
	pit_lane_off = half_width + APRON + 5.0
	pit_box_off = half_width + APRON + 10.5
	box_u.clear()
	var teams := Teams.count()
	var first := PIT_TAPER + 40.0
	var spacing := minf(16.0, (pit_len - 2.0 * PIT_TAPER - 80.0) / maxf(teams, 1))
	for t in teams:
		box_u.append(first + t * spacing)
	# escape do lado do box vira asfalto do pit
	var side := 0 if pit_side < 0 else 1
	var w: PackedFloat32Array = run_w[side]
	var st: PackedByteArray = run_s[side]
	for i in n:
		var u := pit_u(i * ds)
		if u >= -40.0 and u <= pit_len + 40.0:
			st[i] = Surface.ASPHALT
			var ramp := clampf(minf(u + 40.0, pit_len + 40.0 - u) / 40.0, 0.0, 1.0)
			w[i] = lerpf(maxf(w[i], 14.0), PIT_ZONE_W, ramp)
	run_w[side] = w
	run_s[side] = st


## Distância ao longo do pit a partir da entrada (pode ser negativa / > pit_len fora do pit).
func pit_u(s: float) -> float:
	var u := wrap_s(s - pit_entry_s)
	if u > length - 200.0:
		u -= length
	return u


func in_pit_range(s: float) -> bool:
	var u := pit_u(s)
	return u >= 0.0 and u <= pit_len


## Deslocamento lateral do caminho do pit para uma posição u.
func pit_path_lateral(u: float) -> float:
	var start_lat := (half_width - 2.5) * pit_side
	var lane := pit_lane_off * pit_side
	var e := smoothstep(0.0, PIT_TAPER, u)
	var x := smoothstep(0.0, PIT_TAPER, pit_len - u)
	return lerpf(start_lat, lane, minf(e, x))


func pit_limiter_zone(u: float) -> bool:
	return u > PIT_TAPER * 0.7 and u < pit_len - PIT_TAPER * 0.7


# ======================================================================= geração de malhas
func _make_textures() -> void:
	var fn := FastNoiseLite.new()
	fn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	fn.frequency = 0.02
	fn.fractal_octaves = 5
	_noise_tex = NoiseTexture2D.new()
	_noise_tex.width = 512
	_noise_tex.height = 512
	_noise_tex.seamless = true
	_noise_tex.noise = fn
	_noise_tex.generate_mipmaps = true
	var fn2 := FastNoiseLite.new()
	fn2.noise_type = FastNoiseLite.TYPE_CELLULAR
	fn2.frequency = 0.08
	_normal_tex = NoiseTexture2D.new()
	_normal_tex.width = 512
	_normal_tex.height = 512
	_normal_tex.seamless = true
	_normal_tex.as_normal_map = true
	_normal_tex.bump_strength = 4.0
	_normal_tex.noise = fn2


func _road_material(lines: bool) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/road.gdshader")
	m.set_shader_parameter("noise_tex", _noise_tex)
	m.set_shader_parameter("normal_tex", _normal_tex)
	m.set_shader_parameter("half_width", half_width)
	m.set_shader_parameter("edge_lines", 1.0 if lines else 0.0)
	m.set_shader_parameter("wetness", wetness)
	_road_mats.append(m)
	return m


func _terrain_material(a: Color, b: Color, scale: float, stripes: float, rough: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/terrain.gdshader")
	m.set_shader_parameter("noise_tex", _noise_tex)
	m.set_shader_parameter("color_a", a)
	m.set_shader_parameter("color_b", b)
	m.set_shader_parameter("scale", scale)
	m.set_shader_parameter("stripes", stripes)
	m.set_shader_parameter("roughness_base", rough)
	m.set_shader_parameter("wetness", wetness)
	_terrain_mats.append(m)
	return m


func set_wetness(w: float) -> void:
	wetness = w
	for m in _road_mats:
		m.set_shader_parameter("wetness", w)
	for m in _terrain_mats:
		m.set_shader_parameter("wetness", w)


class Builder:
	var st := SurfaceTool.new()
	var faces := PackedVector3Array()
	var count := 0

	func _init() -> void:
		st.begin(Mesh.PRIMITIVE_TRIANGLES)

	func vert(p: Vector3, nrm: Vector3, uv: Vector2, col: Color) -> void:
		st.set_normal(nrm)
		st.set_uv(uv)
		st.set_color(col)
		st.add_vertex(p)

	## Quadrilátero: a = lado esquerdo, b = lado direito, 0 = atual, 1 = próximo (face para cima).
	func quad(a0: Vector3, b0: Vector3, a1: Vector3, b1: Vector3, n0: Vector3, n1: Vector3,
			ua0: Vector2, ub0: Vector2, ua1: Vector2, ub1: Vector2, ca0 := Color.WHITE, cb0 := Color.WHITE, ca1 := Color.WHITE, cb1 := Color.WHITE, collide := true) -> void:
		vert(a0, n0, ua0, ca0); vert(a1, n1, ua1, ca1); vert(b0, n0, ub0, cb0)
		vert(b0, n0, ub0, cb0); vert(a1, n1, ua1, ca1); vert(b1, n1, ub1, cb1)
		if collide:
			faces.append_array([a0, a1, b0, b0, a1, b1])
		count += 1

	func commit(tangents: bool) -> ArrayMesh:
		if count == 0:
			return null
		if tangents:
			st.generate_tangents()
		return st.commit()


func _add_mesh(mesh: ArrayMesh, mat: Material, shadows := true) -> MeshInstance3D:
	if mesh == null:
		return null
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


func _add_collider(faces: PackedVector3Array, surface: int) -> void:
	if faces.is_empty():
		return
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("surface", surface)
	var pm := PhysicsMaterial.new()
	pm.friction = 0.6 if surface != Surface.WALL else 0.25
	pm.bounce = 0.0 if surface != Surface.WALL else 0.15
	body.physics_material_override = pm
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(faces)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	add_child(body)


var kerb_lr := [PackedByteArray(), PackedByteArray()]


func _compute_kerb_sides() -> void:
	var pside := 0 if pit_side < 0 else 1
	for side in 2:
		var arr := PackedByteArray()
		arr.resize(n)
		for i in n:
			var s0 := i * ds
			var excl := side == pside and in_pit_range(s0) and pit_u(s0) > 20.0 and pit_u(s0) < pit_len - 20.0
			arr[i] = 1 if kerb[i] == 1 and not excl else 0
		kerb_lr[side] = arr


# ---------------------------------------------------------------- consulta de solo (substitui raycast)
var g_y := 0.0
var g_surface := 0
var g_normal := Vector3.UP

## Altura e tipo de superfície do chão sob o ponto p (usa a mesma seção transversal da malha).
func ground(p: Vector3, hint: int) -> void:
	var i := hint
	var d := (p - pos[i]).dot(tang[i])
	var steps := int(floor(d / ds))
	if steps != 0:
		i = idx(i + steps)
		d = (p - pos[i]).dot(tang[i])
	var j := (i + 1) % n
	var f := clampf(d / ds, 0.0, 1.0)
	var l := (p - pos[i]).dot(right[i])
	var al := absf(l)
	var side := 0 if l < 0.0 else 1
	var y := lerpf(pos[i].y, pos[j].y, f)
	g_normal = up[i]
	if al <= half_width:
		g_y = y
		g_surface = Surface.ASPHALT
		return
	var e1 := half_width + APRON
	if al <= e1:
		if kerb_lr[side][i] == 1:
			var mid := half_width + APRON * 0.55
			var h := 0.0
			if al < mid:
				h = 0.045 * (al - half_width) / (mid - half_width)
			else:
				h = lerpf(0.045, 0.02, (al - mid) / (e1 - mid))
			g_y = y + h
			g_surface = Surface.KERB
		else:
			g_y = y
			g_surface = Surface.ASPHALT
		return
	var w: float = run_w[side][i]
	var typ: int = run_s[side][i]
	var h_in := 0.02 if (kerb[i] == 1 and typ != Surface.ASPHALT) else 0.0
	var t := clampf((al - e1) / maxf(w, 1.0), 0.0, 1.2)
	g_y = y + lerpf(h_in, -0.05, t)
	g_surface = typ


func _build_surfaces() -> void:
	_compute_kerb_sides()
	var road := Builder.new()
	var apron := Builder.new()
	var kerbs := Builder.new()
	var grass := Builder.new()
	var gravel := Builder.new()
	var tarmac := Builder.new()
	var sub := 10
	for i in n:
		var j := (i + 1) % n
		var s0 := i * ds
		var s1 := (i + 1) * ds
		var n0 := up[i]
		var n1 := up[j]
		# ---- asfalto principal
		for k in sub:
			var la := -half_width + 2.0 * half_width * k / sub
			var lb := -half_width + 2.0 * half_width * (k + 1) / sub
			var r_a0 := _rubber(i, la)
			var r_b0 := _rubber(i, lb)
			var r_a1 := _rubber(j, la)
			var r_b1 := _rubber(j, lb)
			road.quad(point(i, la), point(i, lb), point(j, la), point(j, lb), n0, n1,
				Vector2(la, s0), Vector2(lb, s0), Vector2(la, s1), Vector2(lb, s1),
				Color(r_a0, 0, 0), Color(r_b0, 0, 0), Color(r_a1, 0, 0), Color(r_b1, 0, 0))
		# ---- laterais
		for side in 2:
			var sd := -1.0 if side == 0 else 1.0
			var in0 := half_width * sd
			var out0 := (half_width + APRON) * sd
			var is_kerb: bool = kerb_lr[side][i] == 1
			if is_kerb:
				var stripe := int(floor(s0 / 2.5)) % 2 == 0
				var col := Color(0.86, 0.08, 0.06) if stripe else Color(0.93, 0.93, 0.93)
				var mid := (half_width + APRON * 0.55) * sd
				var hm := 0.045
				var he := 0.02
				var pts := [[in0, 0.0], [mid, hm], [out0, he]]
				for q in 2:
					var la: float = pts[q][0]
					var lb: float = pts[q + 1][0]
					var ha: float = pts[q][1]
					var hb: float = pts[q + 1][1]
					if sd < 0.0:
						kerbs.quad(point(i, lb, hb), point(i, la, ha), point(j, lb, hb), point(j, la, ha), n0, n1,
							Vector2(lb, s0), Vector2(la, s0), Vector2(lb, s1), Vector2(la, s1), col, col, col, col)
					else:
						kerbs.quad(point(i, la, ha), point(i, lb, hb), point(j, la, ha), point(j, lb, hb), n0, n1,
							Vector2(la, s0), Vector2(lb, s0), Vector2(la, s1), Vector2(lb, s1), col, col, col, col)
			else:
				var a := minf(in0, out0)
				var b := maxf(in0, out0)
				apron.quad(point(i, a), point(i, b), point(j, a), point(j, b), n0, n1,
					Vector2(a, s0), Vector2(b, s0), Vector2(a, s1), Vector2(b, s1))
			# ---- escape
			var w0: float = run_w[side][i]
			var w1: float = run_w[side][j]
			var typ: int = run_s[side][i]
			var bl := grass
			if typ == Surface.GRAVEL:
				bl = gravel
			elif typ == Surface.ASPHALT:
				bl = tarmac
			var e0 := (half_width + APRON) * sd
			var f0 := (half_width + APRON + w0) * sd
			var f1 := (half_width + APRON + w1) * sd
			var h_in := 0.02 if (kerb[i] == 1 and typ != Surface.ASPHALT) else 0.0
			if sd < 0.0:
				bl.quad(point(i, f0, -0.05), point(i, e0, h_in), point(j, f1, -0.05), point(j, e0, h_in), n0, n1,
					Vector2(f0, s0), Vector2(e0, s0), Vector2(f1, s1), Vector2(e0, s1))
			else:
				bl.quad(point(i, e0, h_in), point(i, f0, -0.05), point(j, e0, h_in), point(j, f1, -0.05), n0, n1,
					Vector2(e0, s0), Vector2(f0, s0), Vector2(e0, s1), Vector2(f1, s1))
	var road_mat := _road_material(true)
	var plain_mat := _road_material(false)
	var kerb_mat := StandardMaterial3D.new()
	kerb_mat.vertex_color_use_as_albedo = true
	kerb_mat.roughness = 0.55
	var grass_mat := _terrain_material(Color(0.13, 0.30, 0.07), Color(0.26, 0.44, 0.12), 0.06, 1.0, 0.95)
	var gravel_mat := _terrain_material(Color(0.55, 0.49, 0.38), Color(0.72, 0.66, 0.53), 0.5, 0.0, 1.0)
	_add_mesh(road.commit(true), road_mat, false)
	_add_mesh(apron.commit(true), plain_mat, false)
	_add_mesh(kerbs.commit(false), kerb_mat, false)
	_add_mesh(grass.commit(false), grass_mat, false)
	_add_mesh(gravel.commit(false), gravel_mat, false)
	_add_mesh(tarmac.commit(true), plain_mat, false)
	_add_collider(road.faces + apron.faces + tarmac.faces, Surface.ASPHALT)
	_add_collider(kerbs.faces, Surface.KERB)
	_add_collider(grass.faces, Surface.GRASS)
	_add_collider(gravel.faces, Surface.GRAVEL)
	# chão infinito
	var ground := StaticBody3D.new()
	ground.set_meta("surface", Surface.GRASS)
	var wb := CollisionShape3D.new()
	var wbs := WorldBoundaryShape3D.new()
	wbs.plane = Plane(Vector3.UP, -0.6)
	wb.shape = wbs
	ground.add_child(wb)
	add_child(ground)
	var gm := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(9000, 9000)
	gm.mesh = pm
	gm.position = Vector3(400, -0.6, 400)
	gm.material_override = _terrain_material(Color(0.14, 0.27, 0.08), Color(0.24, 0.36, 0.12), 0.02, 0.0, 1.0)
	gm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(gm)


func _rubber(i: int, lat: float) -> float:
	var d := (lat - line_off[i]) / 1.6
	return exp(-d * d) * 0.9


func _wall_lateral(i: int, side: int) -> float:
	var sd := -1.0 if side == 0 else 1.0
	return (half_width + APRON + float(run_w[side][i])) * sd


func _build_walls() -> void:
	var walls := Builder.new()
	var fence := Builder.new()
	var skirt := Builder.new()
	var pside := 0 if pit_side < 0 else 1
	var pitwall := Builder.new()
	for i in n:
		var j := (i + 1) % n
		var s0 := i * ds
		var s1 := (i + 1) * ds
		for side in 2:
			var sd := -1.0 if side == 0 else 1.0
			var l0 := _wall_lateral(i, side)
			var l1 := _wall_lateral(j, side)
			var b0 := point(i, l0, -0.1)
			var b1 := point(j, l1, -0.1)
			var t0 := point(i, l0, WALL_H)
			var t1 := point(j, l1, WALL_H)
			var nn := -right[i] * sd
			var u0 := Vector2(s0, 0.0)
			var u1 := Vector2(s1, 0.0)
			var stripe := int(floor(s0 / 4.0)) % 2 == 0
			var c := Color(0.82, 0.82, 0.8)
			var ct := Color(0.75, 0.08, 0.06) if stripe else Color(0.92, 0.92, 0.92)
			var pit_gar := side == pside and in_pit_range(s0) and pit_u(s0) > PIT_TAPER - 30.0 and pit_u(s0) < pit_len - PIT_TAPER + 30.0
			if sd > 0.0:
				walls.quad(t0, b0, t1, b1, nn, nn, u0, u0, u1, u1, ct, c, ct, c)
			else:
				walls.quad(b0, t0, b1, t1, nn, nn, u0, u0, u1, u1, c, ct, c, ct)
			# topo do muro
			var o0 := point(i, l0 + 0.5 * sd, WALL_H)
			var o1 := point(j, l1 + 0.5 * sd, WALL_H)
			if sd > 0.0:
				walls.quad(t0, o0, t1, o1, up[i], up[j], u0, u0, u1, u1, c, c, c, c, false)
			else:
				walls.quad(o0, t0, o1, t1, up[i], up[j], u0, u0, u1, u1, c, c, c, c, false)
			# alambrado
			if not pit_gar:
				var f0 := point(i, l0 + 0.25 * sd, WALL_H + 3.2)
				var f1 := point(j, l1 + 0.25 * sd, WALL_H + 3.2)
				var g0 := point(i, l0 + 0.25 * sd, WALL_H)
				var g1 := point(j, l1 + 0.25 * sd, WALL_H)
				fence.quad(g0, f0, g1, f1, nn, nn, Vector2(s0, 0), Vector2(s0, 3.2), Vector2(s1, 0), Vector2(s1, 3.2), Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE, false)
			# talude externo até o chão
			var k0 := point(i, l0 + 0.5 * sd, -0.1)
			var k1 := point(j, l1 + 0.5 * sd, -0.1)
			var e0 := point(i, l0 + 60.0 * sd, 0.0)
			var e1 := point(j, l1 + 60.0 * sd, 0.0)
			e0.y = -0.65
			e1.y = -0.65
			if sd > 0.0:
				skirt.quad(k0, e0, k1, e1, up[i], up[j], Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE, false)
			else:
				skirt.quad(e0, k0, e1, k1, up[i], up[j], Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE, false)
		# muro do pit (separa pista e pit lane)
		var u := pit_u(s0)
		if u > PIT_TAPER - 10.0 and u < pit_len - PIT_TAPER + 10.0:
			var lw := (half_width + APRON + 1.2) * pit_side
			var lw2 := lw + 0.6 * pit_side
			var a0 := point(i, minf(lw, lw2), 0.0)
			var a1 := point(j, minf(lw, lw2), 0.0)
			var c0 := point(i, maxf(lw, lw2), 0.0)
			var c1 := point(j, maxf(lw, lw2), 0.0)
			var hh := up[i] * 1.0
			var hj := up[j] * 1.0
			var cw := Color(0.9, 0.9, 0.9)
			pitwall.quad(a0 + hh, c0 + hh, a1 + hj, c1 + hj, up[i], up[j], Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, cw, cw, cw, cw)
			pitwall.quad(a0, a0 + hh, a1, a1 + hj, -right[i], -right[j], Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, cw, cw, cw, cw)
			pitwall.quad(c0 + hh, c0, c1 + hj, c1, right[i], right[j], Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, cw, cw, cw, cw)
	var wall_mat := StandardMaterial3D.new()
	wall_mat.vertex_color_use_as_albedo = true
	wall_mat.roughness = 0.8
	wall_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_add_mesh(walls.commit(false), wall_mat)
	_add_collider(walls.faces, Surface.WALL)
	_add_mesh(pitwall.commit(false), wall_mat)
	_add_collider(pitwall.faces, Surface.WALL)
	var fm := StandardMaterial3D.new()
	fm.albedo_texture = _fence_texture()
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	fm.alpha_scissor_threshold = 0.5
	fm.alpha_antialiasing_mode = BaseMaterial3D.ALPHA_ANTIALIASING_ALPHA_TO_COVERAGE
	fm.cull_mode = BaseMaterial3D.CULL_DISABLED
	fm.metallic = 0.6
	fm.roughness = 0.5
	fm.uv1_scale = Vector3(1.0 / 2.0, 1.0 / 3.2, 1.0)
	fm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_add_mesh(fence.commit(false), fm, false)
	_add_mesh(skirt.commit(false), _terrain_material(Color(0.14, 0.28, 0.08), Color(0.25, 0.38, 0.12), 0.03, 0.0, 1.0), false)


func _fence_texture() -> ImageTexture:
	var img := Image.create(128, 128, true, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in 128:
		for x in 128:
			var d1 := (x + y) % 16
			var d2 := (x - y + 256) % 16
			var post := x < 6
			var rail := y < 5 or y > 122
			if d1 < 1 or d2 < 1 or post or rail:
				img.set_pixel(x, y, Color(0.62, 0.64, 0.66, 1.0))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


# ---------------------------------------------------------------- pit / garagens
func _build_pit_buildings() -> void:
	var marks := Builder.new()
	var sd := float(pit_side)
	# linhas do pit: separação faixa rápida / faixa de trabalho, e linha de entrada
	for i in n:
		var s0 := i * ds
		var u := pit_u(s0)
		if u < 0.0 or u > pit_len:
			continue
		var j := (i + 1) % n
		var s1 := s0 + ds
		var lat := (pit_lane_off + 2.8) * sd
		if u > PIT_TAPER and u < pit_len - PIT_TAPER and int(s0 / 2.0) % 3 != 0:
			_mark(marks, i, j, lat, 0.12, s0, s1, Color(0.95, 0.95, 0.95))
		# linha de entrada/saída (sólida) seguindo a borda da faixa
		if u < PIT_TAPER or u > pit_len - PIT_TAPER:
			var a := pit_path_lateral(u) - 2.4 * sd
			if absf(a) > half_width + 0.3:
				_mark(marks, i, j, a, 0.15, s0, s1, Color(0.95, 0.95, 0.95))
		# zona de limite de velocidade
		if absf(u - PIT_TAPER * 0.7) < 1.0 or absf(u - (pit_len - PIT_TAPER * 0.7)) < 1.0:
			for q in 8:
				var la := (half_width + APRON + 1.8 + q * 1.8) * sd
				_mark(marks, i, j, la, 0.9, s0, s1, Color(0.95, 0.95, 0.95))
	# caixas dos boxes
	for t in Teams.count():
		var s_box := wrap_s(pit_entry_s + float(box_u[t]))
		var c: Color = Teams.team(t)["primary"]
		var i0 := idx_at_s(s_box - 3.0)
		for k in 3:
			var i := idx(i0 + k)
			_mark(marks, i, idx(i + 1), pit_box_off * sd, 3.0, i * ds, (i + 1) * ds, c.lerp(Color.WHITE, 0.2))
	var mm := StandardMaterial3D.new()
	mm.vertex_color_use_as_albedo = true
	mm.roughness = 0.6
	_add_mesh(marks.commit(false), mm, false)
	# prédio dos boxes
	var mid_u := pit_len * 0.5
	var s_mid := wrap_s(pit_entry_s + mid_u)
	var i_mid := idx_at_s(s_mid)
	var b_len := pit_len - 2.0 * PIT_TAPER + 60.0
	var lat_b := (half_width + APRON + PIT_ZONE_W + 7.0) * sd
	var f := frame(i_mid, lat_b, 0.0)
	var concrete := StandardMaterial3D.new()
	concrete.albedo_color = Color(0.86, 0.87, 0.88)
	concrete.roughness = 0.7
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.1, 0.16, 0.22)
	glass.metallic = 0.8
	glass.roughness = 0.08
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.07, 0.07, 0.08)
	dark.roughness = 0.9
	_box_at(f, Vector3(14.0, 7.0, b_len), Vector3(0, 3.5, 0), concrete, true)
	_box_at(f, Vector3(12.0, 4.0, b_len), Vector3(sd * 1.5, 10.0, 0), glass, false)
	_box_at(f, Vector3(16.0, 0.4, b_len + 2.0), Vector3(0, 12.2, 0), concrete, false)
	# portas das garagens com cor da equipe
	for t in Teams.count():
		var s_box := wrap_s(pit_entry_s + float(box_u[t]))
		var ib := idx_at_s(s_box)
		var gf := frame(ib, (half_width + APRON + PIT_ZONE_W + 0.02) * sd, 0.0)
		var tm := StandardMaterial3D.new()
		tm.albedo_color = Teams.team(t)["primary"]
		tm.roughness = 0.4
		_box_at(gf, Vector3(0.1, 4.2, 12.0), Vector3(0, 2.1, 0), dark, false)
		_box_at(gf, Vector3(0.12, 1.2, 13.5), Vector3(0, 5.2, 0), tm, false)
		var lbl := Label3D.new()
		lbl.text = String(Teams.team(t)["name"]).to_upper()
		lbl.font_size = 96
		lbl.pixel_size = 0.006
		lbl.outline_size = 0
		lbl.modulate = Color.WHITE
		lbl.transform = gf * Transform3D(Basis(Vector3.UP, -PI * 0.5 * sd), Vector3(-0.1 * sd, 5.2, 0))
		add_child(lbl)
	# placa de velocidade do pit
	for u in [PIT_TAPER * 0.7 - 5.0]:
		var ii := idx_at_s(pit_entry_s + u)
		var pf := frame(ii, (half_width + APRON + PIT_ZONE_W - 1.0) * sd, 0.0)
		var wm := StandardMaterial3D.new()
		wm.albedo_color = Color.WHITE
		_box_at(pf, Vector3(1.6, 1.6, 0.1), Vector3(0, 2.2, 0), wm, false)
		var l := Label3D.new()
		l.text = "%d" % int(round(pit_speed * 3.6))
		l.font_size = 120
		l.pixel_size = 0.008
		l.modulate = Color(0.85, 0.05, 0.05)
		l.outline_size = 0
		l.transform = pf * Transform3D(Basis(), Vector3(0, 2.2, 0.06))
		add_child(l)


func _mark(b: Builder, i: int, j: int, lat: float, w: float, s0: float, s1: float, c: Color) -> void:
	var a := lat - w * 0.5
	var bb := lat + w * 0.5
	b.quad(point(i, a, 0.012), point(i, bb, 0.012), point(j, a, 0.012), point(j, bb, 0.012), up[i], up[j],
		Vector2(a, s0), Vector2(bb, s0), Vector2(a, s1), Vector2(bb, s1), c, c, c, c, false)


func _box_at(f: Transform3D, size: Vector3, local: Vector3, mat: Material, collide: bool) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.transform = f * Transform3D(Basis(), local)
	add_child(mi)
	if collide:
		var body := StaticBody3D.new()
		body.set_meta("surface", Surface.WALL)
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = size
		cs.shape = sh
		body.add_child(cs)
		body.transform = mi.transform
		add_child(body)
	return mi


# ---------------------------------------------------------------- largada
func _build_start_area() -> void:
	var marks := Builder.new()
	# linha de largada/chegada (quadriculada)
	var cells := 28
	for c in cells:
		for r in 2:
			var la := -half_width + 2.0 * half_width * c / cells
			var lb := -half_width + 2.0 * half_width * (c + 1) / cells
			var col := Color(0.95, 0.95, 0.95) if (c + r) % 2 == 0 else Color(0.05, 0.05, 0.05)
			var p0 := point(0, la, 0.013) + tang[0] * (r * 0.5 - 0.5)
			var p1 := point(0, lb, 0.013) + tang[0] * (r * 0.5 - 0.5)
			marks.quad(p0, p1, p0 + tang[0] * 0.5, p1 + tang[0] * 0.5, up[0], up[0], Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, col, col, col, col, false)
	# caixas do grid
	for k in 20:
		var s := wrap_s(-12.0 - k * 8.0)
		var lat := (-3.2 if k % 2 == 0 else 3.2) * float(-pit_side)
		var i := idx_at_s(s)
		var j := idx(i + 1)
		var w := Color(0.95, 0.95, 0.95)
		_mark(marks, i, j, lat, 2.4, i * ds, j * ds, w)
		var i2 := idx(i - 1)
		_mark(marks, i2, i, lat - 1.2, 0.15, i2 * ds, i * ds, w)
		_mark(marks, i2, i, lat + 1.2, 0.15, i2 * ds, i * ds, w)
	var mm := StandardMaterial3D.new()
	mm.vertex_color_use_as_albedo = true
	mm.roughness = 0.6
	_add_mesh(marks.commit(false), mm, false)
	# pórtico com semáforo
	var lw := -(half_width + 4.0) * float(pit_side)
	var rw := (half_width + APRON + 1.5) * float(pit_side)
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.15, 0.16, 0.18)
	steel.metallic = 0.7
	steel.roughness = 0.35
	var f0 := frame(0, 0.0, 0.0)
	f0.origin -= tang[0] * 2.0
	var mid := (lw + rw) * 0.5
	var span := absf(rw - lw)
	_box_at(f0, Vector3(0.6, 7.5, 0.6), Vector3(lw, 3.75, 0), steel, true)
	_box_at(f0, Vector3(0.6, 7.5, 0.6), Vector3(rw, 3.75, 0), steel, false)
	_box_at(f0, Vector3(span, 0.9, 0.7), Vector3(mid, 7.2, 0), steel, false)
	var lbl := Label3D.new()
	lbl.text = String(def.get("name", "")).to_upper()
	lbl.font_size = 110
	lbl.pixel_size = 0.01
	lbl.outline_size = 0
	lbl.transform = f0 * Transform3D(Basis(), Vector3(mid, 7.2, 0.37))
	add_child(lbl)
	# 5 colunas de luzes (2 por coluna)
	_light_mats.clear()
	for c in 5:
		var lm := StandardMaterial3D.new()
		lm.albedo_color = Color(0.15, 0.02, 0.02)
		lm.emission_enabled = true
		lm.emission = Color(1.0, 0.05, 0.03)
		lm.emission_energy_multiplier = 0.0
		_light_mats.append(lm)
		var x := (c - 2) * 0.9
		_box_at(f0, Vector3(0.75, 1.9, 0.5), Vector3(x, 5.6, 0.2), steel, false)
		for r in 2:
			var sph := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = 0.24
			sm.height = 0.48
			sph.mesh = sm
			sph.material_override = lm
			sph.transform = f0 * Transform3D(Basis(), Vector3(x, 5.15 + r * 0.8, 0.5))
			add_child(sph)


## n_on = número de colunas acesas (0..5); -1 apaga (largada)
func set_start_lights(n_on: int) -> void:
	for c in _light_mats.size():
		var m: StandardMaterial3D = _light_mats[c]
		m.emission_energy_multiplier = 6.0 if c < n_on else 0.0
		m.albedo_color = Color(0.9, 0.05, 0.03) if c < n_on else Color(0.15, 0.02, 0.02)


func _compute_grid() -> void:
	grid_slots.clear()
	for k in 20:
		var s := wrap_s(-12.0 - k * 8.0 - 1.6)
		var lat := (-3.2 if k % 2 == 0 else 3.2) * float(-pit_side)
		var i := idx_at_s(s)
		var f := frame(i, lat, 0.0)
		grid_slots.append(f)


# ---------------------------------------------------------------- cenário
func _build_scenery() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026
	# arquibancadas
	for g in def.get("grandstands", []):
		_grandstand(float(g[0]), int(g[1]), float(g[2]), rng)
	# pontes publicitárias
	for b in def.get("bridges", []):
		_bridge(float(b) * length, rng)
	# placas de frenagem 300/200/100
	_brake_boards()
	# placas publicitárias nos muros
	_ad_boards(rng)
	# árvores
	_trees(rng)
	# câmeras de TV
	tv_cams.clear()
	var step := int(220.0 / ds)
	for i in range(0, n, step):
		var side := 1 if (i / step) % 2 == 0 else 0
		var lat := _wall_lateral(i, side) + (6.0 if side == 1 else -6.0)
		tv_cams.append(point(i, lat, 5.0 + (i % 3) * 2.0))


func _grandstand(frac: float, side: int, glen: float, rng: RandomNumberGenerator) -> void:
	var sd := float(side)
	var i := idx_at_s(frac * length)
	var si := 0 if sd < 0.0 else 1
	var maxw := 0.0
	for k in range(-int(glen / ds / 2.0), int(glen / ds / 2.0) + 1):
		maxw = maxf(maxw, float(run_w[si][idx(i + k)]))
	var lat := (half_width + APRON + maxw + 4.0) * sd
	var f := frame(i, lat, 0.0)
	var b := Builder.new()
	var rows := 12
	var cell := 0.9
	var cols := int(glen / cell)
	for r in rows:
		var y0 := 0.8 + r * 0.55
		var d0 := r * 0.85
		for c in cols:
			var x0 := -glen * 0.5 + c * cell
			var crowd := rng.randf() < 0.86
			var col := Color.from_hsv(rng.randf(), rng.randf_range(0.2, 0.8), rng.randf_range(0.35, 0.95)) if crowd else Color(0.25, 0.3, 0.38)
			# degrau (topo), em coordenadas locais: x lateral -> ao longo de -Z do frame
			var p0 := Vector3(d0 * sd, y0, -x0)
			var p1 := Vector3(d0 * sd, y0, -(x0 + cell))
			var p2 := Vector3((d0 + 0.85) * sd, y0, -x0)
			var p3 := Vector3((d0 + 0.85) * sd, y0, -(x0 + cell))
			var h := Vector3(0, 0.55, 0)
			if sd > 0.0:
				b.quad(f * p0, f * p2, f * p1, f * p3, f.basis.y, f.basis.y, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, col, col, col, col, false)
				b.quad(f * (p0 + h * 0.0), f * (p0 - h), f * p1, f * (p1 - h), -f.basis.x, -f.basis.x, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, col.darkened(0.3), col.darkened(0.3), col.darkened(0.3), col.darkened(0.3), false)
			else:
				b.quad(f * p2, f * p0, f * p3, f * p1, f.basis.y, f.basis.y, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, col, col, col, col, false)
				b.quad(f * (p0 - h), f * p0, f * (p1 - h), f * p1, f.basis.x, f.basis.x, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, col.darkened(0.3), col.darkened(0.3), col.darkened(0.3), col.darkened(0.3), false)
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.9
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_add_mesh(b.commit(false), m)
	var conc := StandardMaterial3D.new()
	conc.albedo_color = Color(0.7, 0.71, 0.72)
	var depth := rows * 0.85
	_box_at(f, Vector3(depth + 1.0, 0.8, glen), Vector3(sd * depth * 0.5, 0.4, 0), conc, false)
	_box_at(f, Vector3(0.6, rows * 0.55 + 0.8, glen), Vector3(sd * (depth + 0.3), (rows * 0.55 + 0.8) * 0.5, 0), conc, false)
	var roof := StandardMaterial3D.new()
	roof.albedo_color = Color(0.92, 0.93, 0.95)
	roof.metallic = 0.4
	roof.roughness = 0.4
	_box_at(f, Vector3(depth + 3.0, 0.3, glen + 2.0), Vector3(sd * depth * 0.5, rows * 0.55 + 4.5, 0), roof, false)
	for k in range(int(glen / 25.0) + 1):
		_box_at(f, Vector3(0.4, rows * 0.55 + 4.5, 0.4), Vector3(sd * (depth + 0.2), (rows * 0.55 + 4.5) * 0.5, -glen * 0.5 + k * 25.0), conc, false)


const SPONSORS := ["NEXA", "VOLTEX", "ORBITAL", "KAIROS", "PRISMA", "TERRA OIL", "MERIDIAN", "APEX GP", "SOLARA", "QUANTA"]
const SPONSOR_COLORS := [Color(0.05, 0.25, 0.7), Color(0.85, 0.1, 0.1), Color(0.05, 0.05, 0.08), Color(1.0, 0.75, 0.0), Color(0.0, 0.55, 0.45), Color(0.95, 0.95, 0.95)]


func _bridge(s: float, rng: RandomNumberGenerator) -> void:
	var i := idx_at_s(s)
	var l0 := _wall_lateral(i, 0) - 3.0
	var l1 := _wall_lateral(i, 1) + 3.0
	var f := frame(i, 0.0, 0.0)
	var conc := StandardMaterial3D.new()
	conc.albedo_color = Color(0.25, 0.26, 0.28)
	conc.roughness = 0.6
	var span := l1 - l0
	_box_at(f, Vector3(1.2, 9.0, 3.0), Vector3(l0, 4.5, 0), conc, false)
	_box_at(f, Vector3(1.2, 9.0, 3.0), Vector3(l1, 4.5, 0), conc, false)
	_box_at(f, Vector3(span + 2.0, 2.4, 4.0), Vector3((l0 + l1) * 0.5, 9.8, 0), conc, false)
	var brand: String = SPONSORS[rng.randi() % SPONSORS.size()]
	var bg := StandardMaterial3D.new()
	bg.albedo_color = SPONSOR_COLORS[rng.randi() % SPONSOR_COLORS.size()]
	_box_at(f, Vector3(minf(span, 60.0), 2.0, 4.05), Vector3((l0 + l1) * 0.5, 9.8, 0), bg, false)
	for dir in [1.0, -1.0]:
		var lbl := Label3D.new()
		lbl.text = brand
		lbl.font_size = 200
		lbl.pixel_size = 0.012
		lbl.outline_size = 0
		lbl.modulate = Color.WHITE if bg.albedo_color.get_luminance() < 0.6 else Color(0.05, 0.05, 0.08)
		var rot := Basis() if dir > 0.0 else Basis(Vector3.UP, PI)
		lbl.transform = f * Transform3D(rot, Vector3((l0 + l1) * 0.5, 9.8, 2.04 * dir))
		add_child(lbl)


func _brake_boards() -> void:
	var white := StandardMaterial3D.new()
	white.albedo_color = Color(0.95, 0.95, 0.95)
	var pole := StandardMaterial3D.new()
	pole.albedo_color = Color(0.3, 0.3, 0.32)
	var i := 0
	var placed := 0
	while i < n and placed < 40:
		# procura pontos de mínimo de velocidade após grande queda
		var v := speed_prof[i]
		if v < speed_prof[idx(i - 1)] and v <= speed_prof[idx(i + 1)]:
			var vmax := 0.0
			for k in range(1, 200):
				vmax = maxf(vmax, speed_prof[idx(i - k)])
			if vmax - v > 22.0:
				# ponto de início de frenagem
				var b := i
				while speed_prof[idx(b - 1)] > speed_prof[idx(b)] + 0.01 and i - b < 250:
					b -= 1
				var side := 0 if curv[i] > 0.0 else 1   # lado de fora da curva
				var sd := -1.0 if side == 0 else 1.0
				for dist in [100.0, 200.0, 300.0]:
					var bi := idx(b - int(round((dist - 100.0) / ds)))
					var lat := (half_width + APRON + 2.0) * sd
					var fr := frame(bi, lat, 0.0)
					_box_at(fr, Vector3(0.12, 1.4, 0.12), Vector3(0, 0.7, 0), pole, false)
					_box_at(fr, Vector3(1.3, 0.9, 0.1), Vector3(0, 1.75, 0), white, false)
					var l := Label3D.new()
					l.text = "%d" % int(dist)
					l.font_size = 96
					l.pixel_size = 0.009
					l.outline_size = 0
					l.modulate = Color(0.05, 0.05, 0.05)
					l.transform = fr * Transform3D(Basis(), Vector3(0, 1.75, 0.06))
					add_child(l)
				placed += 1
				i += 60
		i += 1


func _ad_boards(rng: RandomNumberGenerator) -> void:
	var mats := {}
	var every := int(130.0 / ds)
	for i in range(0, n, every):
		for side in 2:
			if rng.randf() < 0.35:
				continue
			var s0 := i * ds
			if side == (0 if pit_side < 0 else 1) and in_pit_range(s0):
				continue
			var sd := -1.0 if side == 0 else 1.0
			var lat := _wall_lateral(i, side) - 0.05 * sd
			var brand: String = SPONSORS[rng.randi() % SPONSORS.size()]
			var ci := rng.randi() % SPONSOR_COLORS.size()
			if not mats.has(ci):
				var m := StandardMaterial3D.new()
				m.albedo_color = SPONSOR_COLORS[ci]
				m.roughness = 0.5
				mats[ci] = m
			var fr := frame(i, lat, 0.0)
			_box_at(fr, Vector3(0.06, 0.9, 7.5), Vector3(0, 0.55, 0), mats[ci], false)
			var l := Label3D.new()
			l.text = brand
			l.font_size = 72
			l.pixel_size = 0.01
			l.outline_size = 0
			var bgc: Color = SPONSOR_COLORS[ci]
			l.modulate = Color.WHITE if bgc.get_luminance() < 0.6 else Color(0.05, 0.05, 0.08)
			l.transform = fr * Transform3D(Basis(Vector3.UP, -PI * 0.5 * sd), Vector3(-0.04 * sd, 0.55, 0))
			add_child(l)


func _trees(rng: RandomNumberGenerator) -> void:
	var count: int = [250, 600, 1100, 1600][clampi(_quality, 0, 3)]
	var bb := AABB(pos[0], Vector3.ZERO)
	for p in pos:
		bb = bb.expand(p)
	bb = bb.grow(260.0)
	var probe := PackedVector2Array()
	var probe_r := PackedFloat32Array()
	for i in range(0, n, 3):
		probe.append(Vector2(pos[i].x, pos[i].z))
		probe_r.append(half_width + APRON + maxf(float(run_w[0][i]), float(run_w[1][i])) + 70.0)
	var xforms: Array = []
	var tries := 0
	while xforms.size() < count and tries < count * 12:
		tries += 1
		var p := Vector2(rng.randf_range(bb.position.x, bb.end.x), rng.randf_range(bb.position.z, bb.end.z))
		var ok := true
		for k in probe.size():
			if p.distance_squared_to(probe[k]) < probe_r[k] * probe_r[k]:
				ok = false
				break
		if not ok:
			continue
		var sc := rng.randf_range(0.7, 1.5)
		var t := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(sc, sc * rng.randf_range(0.85, 1.3), sc)), Vector3(p.x, -0.6, p.y))
		xforms.append(t)
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.25
	trunk.bottom_radius = 0.35
	trunk.height = 4.0
	trunk.radial_segments = 6
	var crown := SphereMesh.new()
	crown.radius = 3.2
	crown.height = 7.0
	crown.radial_segments = 10
	crown.rings = 6
	var tm := StandardMaterial3D.new()
	tm.albedo_color = Color(0.3, 0.22, 0.15)
	var cm := StandardMaterial3D.new()
	cm.albedo_color = Color(0.13, 0.27, 0.09)
	cm.roughness = 0.95
	trunk.material = tm
	crown.material = cm
	for part in 2:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = part == 1
		mm.mesh = trunk if part == 0 else crown
		mm.instance_count = xforms.size()
		for k in xforms.size():
			var t: Transform3D = xforms[k]
			if part == 0:
				mm.set_instance_transform(k, t * Transform3D(Basis(), Vector3(0, 2.0, 0)))
			else:
				mm.set_instance_transform(k, t * Transform3D(Basis(), Vector3(0, 6.0, 0)))
				mm.set_instance_color(k, Color.from_hsv(rng.randf_range(0.22, 0.32), rng.randf_range(0.5, 0.75), rng.randf_range(0.6, 1.0)))
		if part == 1:
			cm.vertex_color_use_as_albedo = true
			cm.albedo_color = Color(0.25, 0.42, 0.17)
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		add_child(mmi)


func _compute_minimap() -> void:
	minimap_pts.clear()
	var mn := Vector2(INF, INF)
	var mx := Vector2(-INF, -INF)
	for i in range(0, n, 2):
		var p := Vector2(pos[i].x, pos[i].z)
		minimap_pts.append(p)
		mn = mn.min(p)
		mx = mx.max(p)
	bounds = Rect2(mn, mx - mn)
