class_name CarModel
extends Node3D
## Modelo visual do carro (PROVISÓRIO, procedural). Coordenadas: -Z = frente, Y = cima, X = lateral,
## chão em y = 0, eixo dianteiro em z = -1.7 e traseiro em z = +1.7.
##
## Se existir "res://assets/cars/<sigla_da_equipe>.glb" (ou "res://assets/cars/default.glb")
## ele é usado no lugar da carroceria procedural — pipeline para modelos feitos no Blender.
## Dentro do .glb, as rodas devem ficar de fora (o jogo cria as rodas).

const EYE := Vector3(0.0, 0.93, -0.06)          # olhos do piloto (câmera cockpit)
const TCAM := Vector3(0.0, 1.16, 0.18)
const HELMETCAM := Vector3(0.0, 1.13, 0.13)          # atrás e acima do capacete
const NOSECAM := Vector3(0.0, 0.62, -1.55)
const HIDE_LAYER := 1 << 19                      # capacete do jogador (oculto na câmera cockpit)
const W_F := 0.30
const W_R := 0.38

static var _cache: Dictionary = {}
static var _mats: Dictionary = {}

var wheel_root: Array = []
var wheel_steer: Array = []
var wheel_spin: Array = []
var body: MeshInstance3D
var _band_mat: StandardMaterial3D
var _brake_mat: StandardMaterial3D
var _rain_mat: StandardMaterial3D
var _flap_r: Node3D
var _flap_f: Array = []
var _steer_node: Node3D
var _gear_label: Label3D
var _led_mats: Array = []
var _aero_t := 0.0
var _rain_t := 0.0
var _rain_on := false


# ======================================================================= geometria utilitária
class Acc:
	var v := PackedVector3Array()
	var nrm := PackedVector3Array()
	var idx := PackedInt32Array()

	func add(verts: PackedVector3Array, tris: PackedInt32Array, smooth := true) -> void:
		var vol := 0.0
		for t in range(0, tris.size(), 3):
			vol += verts[tris[t]].dot(verts[tris[t + 1]].cross(verts[tris[t + 2]]))
		var flip := vol > 0.0
		var base := v.size()
		var ns := PackedVector3Array()
		ns.resize(verts.size())
		for t in range(0, tris.size(), 3):
			var a := tris[t]
			var b := tris[t + 1]
			var c := tris[t + 2]
			if flip:
				var tmp := b
				b = c
				c = tmp
			var fn := (verts[c] - verts[a]).cross(verts[b] - verts[a])
			ns[a] += fn
			ns[b] += fn
			ns[c] += fn
			idx.append(base + a)
			idx.append(base + b)
			idx.append(base + c)
		for i in verts.size():
			v.append(verts[i])
			nrm.append(ns[i].normalized() if ns[i].length_squared() > 0.0 else Vector3.UP)

	func to_arrays() -> Array:
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = v
		arr[Mesh.ARRAY_NORMAL] = nrm
		arr[Mesh.ARRAY_INDEX] = idx
		return arr


static func G(f: float, y: float, x: float) -> Vector3:
	# (frente, altura, lateral) -> coordenadas Godot
	return Vector3(x, y, -f)


static func _cr1(a: float, b: float, c: float, d: float, t: float) -> float:
	return 0.5 * ((2.0 * b) + (-a + c) * t + (2.0 * a - 5.0 * b + 4.0 * c - d) * t * t + (-a + 3.0 * b - 3.0 * c + d) * t * t * t)


## Casco por seções superelípticas: cada seção {f, y, x, w, ht, hb, n}
static func loft(acc: Acc, secs: Array, seg := 40, steps_per := 10) -> void:
	var L := secs.size()
	var keys := ["f", "y", "x", "w", "ht", "hb", "n"]
	var defs := {"x": 0.0, "n": 2.4}
	var verts := PackedVector3Array()
	var tris := PackedInt32Array()
	var rows := (L - 1) * steps_per + 1
	for r in rows:
		var fpos := float(r) / steps_per
		var k := mini(int(floor(fpos)), L - 2)
		var t := fpos - k
		var val := {}
		for key in keys:
			var a: float = secs[maxi(k - 1, 0)].get(key, defs.get(key, 0.0))
			var b: float = secs[k].get(key, defs.get(key, 0.0))
			var c: float = secs[k + 1].get(key, defs.get(key, 0.0))
			var d: float = secs[mini(k + 2, L - 1)].get(key, defs.get(key, 0.0))
			val[key] = _cr1(a, b, c, d, t) if key != "n" else lerpf(b, c, t)
		var w := maxf(val["w"], 0.003)
		var ht := maxf(val["ht"], 0.003)
		var hb := maxf(val["hb"], 0.003)
		var nn: float = val["n"]
		for j in seg:
			var an := float(j) / seg * TAU
			var cs := cos(an)
			var sn := sin(an)
			var ex := signf(cs) * pow(absf(cs), 2.0 / nn)
			var ey := signf(sn) * pow(absf(sn), 2.0 / nn)
			verts.append(G(val["f"], val["y"] + ey * (ht if sn >= 0.0 else hb), val["x"] + ex * w))
	for i in rows - 1:
		for j in seg:
			var p := i * seg + j
			var q := i * seg + (j + 1) % seg
			var r2 := (i + 1) * seg + j
			var u := (i + 1) * seg + (j + 1) % seg
			tris.append_array([p, r2, q, q, r2, u])
	_caps(verts, tris, 0, (rows - 1) * seg, seg)
	acc.add(verts, tris)


static func _caps(verts: PackedVector3Array, tris: PackedInt32Array, first: int, last: int, ring: int) -> void:
	for e in 2:
		var start := first if e == 0 else last
		var c := Vector3.ZERO
		var base := verts.size()
		for j in ring:
			c += verts[start + j]
			verts.append(verts[start + j])
		var ci := verts.size()
		verts.append(c / ring)
		for j in ring:
			var a := base + j
			var b := base + (j + 1) % ring
			if e == 0:
				tris.append_array([ci, a, b])
			else:
				tris.append_array([ci, b, a])


static func _airfoil(np: int, th: float, cam: float) -> PackedVector2Array:
	var up := PackedVector2Array()
	var lo := PackedVector2Array()
	for i in np + 1:
		var t := (1.0 - cos(PI * i / np)) / 2.0
		var yt := 5.0 * th * (0.2969 * sqrt(t) - 0.126 * t - 0.3516 * t * t + 0.2843 * t * t * t - 0.1036 * t * t * t * t)
		var yc := cam * 4.0 * t * (1.0 - t)
		up.append(Vector2(0.5 - t, yc + yt))
		lo.append(Vector2(0.5 - t, yc - yt))
	var out := up.duplicate()
	for i in range(np - 1, 0, -1):
		out.append(lo[i])
	return out


## Elemento de asa: estações [f, y, x, corda, ângulo°] ao longo da envergadura.
static func wing(acc: Acc, st: Array, th := 0.1, cam := -0.05, origin := Vector3.ZERO) -> void:
	var prof := _airfoil(10, th, cam)
	var P := prof.size()
	var L := st.size()
	var per := 8
	var rows := (L - 1) * per + 1
	var verts := PackedVector3Array()
	var tris := PackedInt32Array()
	for r in rows:
		var fpos := float(r) / per
		var k := mini(int(floor(fpos)), L - 2)
		var t := fpos - k
		var a: Array = st[maxi(k - 1, 0)]
		var b: Array = st[k]
		var c: Array = st[k + 1]
		var d: Array = st[mini(k + 2, L - 1)]
		var f := _cr1(a[0], b[0], c[0], d[0], t)
		var y := _cr1(a[1], b[1], c[1], d[1], t)
		var x := lerpf(b[2], c[2], t)
		var ch := lerpf(b[3], c[3], t)
		var ang := deg_to_rad(lerpf(b[4], c[4], t))
		var ca := cos(ang)
		var sa := sin(ang)
		for j in P:
			var lx := prof[j].x * ch
			var ly := prof[j].y * ch
			verts.append(G(f + lx * ca + ly * sa, y - lx * sa + ly * ca, x) - origin)
	for i in rows - 1:
		for j in P:
			var p := i * P + j
			var q := i * P + (j + 1) % P
			var r2 := (i + 1) * P + j
			var u := (i + 1) * P + (j + 1) % P
			tris.append_array([p, r2, q, q, r2, u])
	_caps(verts, tris, 0, (rows - 1) * P, P)
	acc.add(verts, tris)


## Prisma: polígono 2D (a, b) mapeado por o + A*a + B*b, extrudado ao longo de C (espessura total th).
static func prism(acc: Acc, pts: Array, o: Vector3, A: Vector3, B: Vector3, C: Vector3, th: float) -> void:
	var poly := PackedVector2Array()
	for p in pts:
		poly.append(Vector2(p[0], p[1]))
	var area := 0.0
	for i in poly.size():
		var j := (i + 1) % poly.size()
		area += poly[i].x * poly[j].y - poly[j].x * poly[i].y
	if area < 0.0:
		poly.reverse()
	var tri := Geometry2D.triangulate_polygon(poly)
	if tri.is_empty():
		return
	var m := poly.size()
	var verts := PackedVector3Array()
	var tris := PackedInt32Array()
	var top := []
	var bot := []
	for p in poly:
		top.append(o + A * p.x + B * p.y + C * (th * 0.5))
		bot.append(o + A * p.x + B * p.y - C * (th * 0.5))
	# tampas (vértices próprios -> normais planas)
	for i in m:
		verts.append(top[i])
	for i in m:
		verts.append(bot[i])
	for t in range(0, tri.size(), 3):
		var a := tri[t]
		var b := tri[t + 1]
		var c := tri[t + 2]
		var cr := (poly[b] - poly[a]).cross(poly[c] - poly[a])
		if cr < 0.0:
			var tmp := b
			b = c
			c = tmp
		tris.append_array([a, b, c])
		tris.append_array([m + a, m + c, m + b])
	for i in m:
		var j := (i + 1) % m
		var base := verts.size()
		verts.append_array([top[i], top[j], bot[i], bot[j]])
		tris.append_array([base + 1, base + 0, base + 2, base + 1, base + 2, base + 3])
	acc.add(verts, tris)


static func box(acc: Acc, center: Vector3, size: Vector3, rot := Basis()) -> void:
	var hx := size.x * 0.5
	var hy := size.y * 0.5
	prism(acc, [[-hx, -hy], [hx, -hy], [hx, hy], [-hx, hy]], center, rot.x, rot.y, rot.z, size.z)


static func cyl(acc: Acc, a: Vector3, b: Vector3, r: float, seg := 10, flat := 1.0) -> void:
	var d := (b - a).normalized()
	var ref := Vector3.UP if absf(d.y) < 0.9 else Vector3.RIGHT
	var u := d.cross(ref).normalized()
	var w := d.cross(u).normalized()
	var verts := PackedVector3Array()
	var tris := PackedInt32Array()
	for e in 2:
		var p := a if e == 0 else b
		for j in seg:
			var an := float(j) / seg * TAU
			verts.append(p + u * cos(an) * r * flat + w * sin(an) * r / flat)
	for j in seg:
		var p := j
		var q := (j + 1) % seg
		tris.append_array([p, seg + j, q, q, seg + j, seg + q])
	_caps(verts, tris, 0, seg, seg)
	acc.add(verts, tris)


static func tube(acc: Acc, pts: Array, r: float, seg := 10, flat := Vector2.ONE) -> void:
	var verts := PackedVector3Array()
	var tris := PackedInt32Array()
	var L := pts.size()
	for i in L:
		var p: Vector3 = pts[i]
		var t: Vector3 = (pts[mini(i + 1, L - 1)] - pts[maxi(i - 1, 0)]).normalized()
		var ref := Vector3.UP if absf(t.y) < 0.9 else Vector3.RIGHT
		var u := t.cross(ref).normalized()
		var w := t.cross(u).normalized()
		for j in seg:
			var an := float(j) / seg * TAU
			verts.append(p + u * cos(an) * r * flat.x + w * sin(an) * r * flat.y)
	for i in L - 1:
		for j in seg:
			var p := i * seg + j
			var q := i * seg + (j + 1) % seg
			tris.append_array([p, (i + 1) * seg + j, q, q, (i + 1) * seg + j, (i + 1) * seg + (j + 1) % seg])
	_caps(verts, tris, 0, (L - 1) * seg, seg)
	acc.add(verts, tris)


static func lathe_x(acc: Acc, prof: Array, seg: int) -> void:
	# perfil fechado [(raio, axial)], revolucionado em torno do eixo X
	var verts := PackedVector3Array()
	var tris := PackedInt32Array()
	var P := prof.size()
	for j in seg:
		var an := float(j) / seg * TAU
		for p in prof:
			verts.append(Vector3(p[1], p[0] * cos(an), p[0] * sin(an)))
	for j in seg:
		var j2 := (j + 1) % seg
		for k in P:
			var k2 := (k + 1) % P
			tris.append_array([j * P + k, j2 * P + k, j * P + k2, j * P + k2, j2 * P + k, j2 * P + k2])
	acc.add(verts, tris)


# ======================================================================= materiais
static func mat(key: String) -> Material:
	if _mats.has(key):
		return _mats[key]
	var m: Material
	match key:
		"livery":
			var sm := ShaderMaterial.new()
			sm.shader = load("res://shaders/livery.gdshader")
			m = sm
		"carbon":
			var c := StandardMaterial3D.new()
			c.albedo_texture = _carbon_tex()
			c.uv1_triplanar = true
			c.uv1_scale = Vector3(36, 36, 36)
			c.roughness = 0.32
			c.metallic = 0.25
			c.clearcoat_enabled = true
			c.clearcoat = 0.8
			c.clearcoat_roughness = 0.15
			c.cull_mode = BaseMaterial3D.CULL_DISABLED
			m = c
		"dark":
			var d := StandardMaterial3D.new()
			d.albedo_color = Color(0.03, 0.03, 0.035)
			d.roughness = 0.8
			d.cull_mode = BaseMaterial3D.CULL_DISABLED
			m = d
		"metal":
			var me := StandardMaterial3D.new()
			me.albedo_color = Color(0.62, 0.64, 0.68)
			me.metallic = 0.95
			me.roughness = 0.25
			m = me
		"arm":
			var a := StandardMaterial3D.new()
			a.albedo_color = Color(0.07, 0.075, 0.085)
			a.metallic = 0.5
			a.roughness = 0.35
			m = a
		"glass":
			var g := StandardMaterial3D.new()
			g.albedo_color = Color(0.03, 0.04, 0.05)
			g.metallic = 0.9
			g.roughness = 0.05
			m = g
		"tyre":
			var t := StandardMaterial3D.new()
			t.albedo_color = Color(0.045, 0.045, 0.05)
			t.roughness = 0.88
			m = t
		"rim":
			var r := StandardMaterial3D.new()
			r.albedo_texture = _rim_tex()
			r.metallic = 0.6
			r.roughness = 0.35
			m = r
	_mats[key] = m
	return m


static func _carbon_tex() -> ImageTexture:
	var img := Image.create(64, 64, true, Image.FORMAT_RGB8)
	for y in 64:
		for x in 64:
			var cx := x / 8
			var cy := y / 8
			var on := ((cx + cy) % 4) < 2
			var fx := float(x % 8) / 8.0
			var fy := float(y % 8) / 8.0
			var g := (fx + fy) * 0.5
			var c := Color(0.2, 0.22, 0.25) if on else Color(0.07, 0.075, 0.085)
			img.set_pixel(x, y, c.darkened(g * 0.4))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


static func _rim_tex() -> ImageTexture:
	var S := 256
	var img := Image.create(S, S, true, Image.FORMAT_RGB8)
	var c := S * 0.5
	for y in S:
		for x in S:
			var dx := x - c
			var dy := y - c
			var r := sqrt(dx * dx + dy * dy) / c
			var a := atan2(dy, dx)
			var col := Color(0.04, 0.045, 0.05)
			var spoke := absf(fposmod(a * 5.0 / TAU, 1.0) - 0.5) < 0.12 * (1.2 - r)
			if r < 0.75 and r > 0.16 and spoke:
				col = Color(0.16, 0.17, 0.19).lerp(Color(0.08, 0.085, 0.095), r)
			if r > 0.78:
				col = Color(0.11, 0.115, 0.13)
			if r < 0.15:
				col = Color(0.6, 0.62, 0.66)
			img.set_pixel(x, y, col)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


# ======================================================================= construção
func build(team: Dictionary, number: int, player: bool) -> void:
	var custom := _try_custom_model(team)
	if custom:
		add_child(custom)
	else:
		if not _cache.has("body"):
			_cache["body"] = _build_body()
		body = MeshInstance3D.new()
		body.mesh = _cache["body"]
		add_child(body)
		body.set_instance_shader_parameter("primary", team["primary"])
		body.set_instance_shader_parameter("secondary", team["secondary"])
		body.set_instance_shader_parameter("accent", team["accent"])
		body.set_instance_shader_parameter("pattern", float(Teams.TEAMS.find(team) % 3))
	_build_moving_parts(team)
	_build_wheels()
	_build_cockpit(team, player)
	_build_lights()
	_build_number(number, team)


func _try_custom_model(team: Dictionary) -> Node3D:
	for p in ["res://assets/cars/%s.glb" % String(team["short"]).to_lower(), "res://assets/cars/default.glb"]:
		if ResourceLoader.exists(p):
			var ps: PackedScene = load(p)
			if ps:
				return ps.instantiate()
	return null


static func _build_body() -> ArrayMesh:
	var liv := Acc.new()
	var carb := Acc.new()
	var dark := Acc.new()
	var arm := Acc.new()
	var metal := Acc.new()
	var glass := Acc.new()
	# ---------------- monocoque + bico
	loft(liv, [
		{"f": 3.0, "y": 0.22, "w": 0.045, "ht": 0.04, "hb": 0.035},
		{"f": 2.75, "y": 0.25, "w": 0.08, "ht": 0.065, "hb": 0.055},
		{"f": 2.25, "y": 0.32, "w": 0.12, "ht": 0.095, "hb": 0.095},
		{"f": 1.75, "y": 0.40, "w": 0.155, "ht": 0.125, "hb": 0.16},
		{"f": 1.25, "y": 0.46, "w": 0.2, "ht": 0.155, "hb": 0.26},
		{"f": 0.75, "y": 0.50, "w": 0.25, "ht": 0.2, "hb": 0.32},
		{"f": 0.25, "y": 0.50, "w": 0.28, "ht": 0.22, "hb": 0.34},
		{"f": -0.25, "y": 0.50, "w": 0.29, "ht": 0.24, "hb": 0.34},
		{"f": -0.75, "y": 0.47, "w": 0.24, "ht": 0.22, "hb": 0.32},
		{"f": -1.25, "y": 0.43, "w": 0.17, "ht": 0.17, "hb": 0.28},
		{"f": -1.75, "y": 0.40, "w": 0.105, "ht": 0.12, "hb": 0.25},
		{"f": -2.2, "y": 0.38, "w": 0.055, "ht": 0.07, "hb": 0.18},
	], 48, 10)
	# ---------------- tampa do motor / airbox
	loft(liv, [
		{"f": -0.04, "y": 0.93, "w": 0.075, "ht": 0.07, "hb": 0.07, "n": 2.2},
		{"f": -0.25, "y": 0.92, "w": 0.125, "ht": 0.085, "hb": 0.14},
		{"f": -0.6, "y": 0.84, "w": 0.2, "ht": 0.09, "hb": 0.22},
		{"f": -1.0, "y": 0.74, "w": 0.19, "ht": 0.08, "hb": 0.22},
		{"f": -1.45, "y": 0.62, "w": 0.09, "ht": 0.05, "hb": 0.12},
		{"f": -1.95, "y": 0.52, "w": 0.035, "ht": 0.03, "hb": 0.06},
	], 32, 10)
	prism(dark, _ellipse(0.062, 0.062, 20), G(-0.03, 0.93, 0.0), Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1), 0.02)
	# barbatana
	prism(liv, [[-0.45, 1.0], [-1.0, 0.95], [-1.7, 0.86], [-1.85, 0.74], [-1.2, 0.76], [-0.5, 0.92]], Vector3.ZERO,
		Vector3(0, 0, -1), Vector3(0, 1, 0), Vector3(1, 0, 0), 0.012)
	# ---------------- ombro + sidepods
	loft(liv, [
		{"f": 0.6, "y": 0.52, "w": 0.34, "ht": 0.07, "hb": 0.1, "n": 3.2},
		{"f": 0.1, "y": 0.5, "w": 0.48, "ht": 0.1, "hb": 0.2, "n": 3.2},
		{"f": -0.5, "y": 0.45, "w": 0.45, "ht": 0.1, "hb": 0.22, "n": 3.0},
		{"f": -1.1, "y": 0.37, "w": 0.28, "ht": 0.07, "hb": 0.16},
		{"f": -1.65, "y": 0.31, "w": 0.11, "ht": 0.04, "hb": 0.12},
	], 40, 10)
	for s in [-1.0, 1.0]:
		loft(liv, [
			{"f": 0.82, "y": 0.52, "x": s * 0.38, "w": 0.15, "ht": 0.09, "hb": 0.07, "n": 3.4},
			{"f": 0.62, "y": 0.50, "x": s * 0.38, "w": 0.19, "ht": 0.12, "hb": 0.12, "n": 3.4},
			{"f": 0.25, "y": 0.46, "x": s * 0.35, "w": 0.25, "ht": 0.14, "hb": 0.24, "n": 3.2},
			{"f": -0.25, "y": 0.40, "x": s * 0.30, "w": 0.26, "ht": 0.13, "hb": 0.29, "n": 3.0},
			{"f": -0.75, "y": 0.34, "x": s * 0.24, "w": 0.21, "ht": 0.10, "hb": 0.24},
			{"f": -1.2, "y": 0.30, "x": s * 0.18, "w": 0.14, "ht": 0.07, "hb": 0.19},
			{"f": -1.6, "y": 0.27, "x": s * 0.12, "w": 0.075, "ht": 0.04, "hb": 0.15},
		], 40, 8)
		# entrada de ar
		prism(dark, _ellipse(0.13, 0.055, 24), G(0.835, 0.52, s * 0.38), Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1), 0.02)
		# retrovisor
		cyl(carb, G(0.74, 0.6, s * 0.3), G(0.72, 0.71, s * 0.47), 0.008, 8, 2.0)
		box(liv, G(0.72, 0.735, s * 0.53), Vector3(0.16, 0.06, 0.07))
		box(glass, G(0.683, 0.735, s * 0.53), Vector3(0.15, 0.05, 0.004))
		# aletas no sidepod
		for k in 4:
			box(dark, G(-0.15 - k * 0.08, 0.565 - k * 0.02, s * 0.36), Vector3(0.16, 0.004, 0.04), Basis(Vector3.RIGHT, 0.25))
	# ---------------- cockpit
	prism(dark, _ellipse(0.36, 0.17, 30), G(0.27, 0.723, 0.0), Vector3(0, 0, -1), Vector3(1, 0, 0), Vector3(0, 1, 0), 0.01)
	box(dark, G(-0.05, 0.75, 0.0), Vector3(0.26, 0.12, 0.08))
	# halo
	var hp := []
	for p in [[-0.12, 0.72, 0.28], [0.0, 0.88, 0.26], [0.22, 0.965, 0.19], [0.45, 0.985, 0.07], [0.53, 0.985, 0.0],
			[0.45, 0.985, -0.07], [0.22, 0.965, -0.19], [0.0, 0.88, -0.26], [-0.12, 0.72, -0.28]]:
		hp.append(G(p[0], p[1], p[2]))
	tube(arm, _smooth_path(hp, 6), 0.024, 12)
	cyl(arm, G(0.53, 0.985, 0.0), G(0.84, 0.66, 0.0), 0.026, 10, 1.6)
	# câmera T e antenas
	cyl(carb, G(-0.22, 0.99, 0.0), G(-0.22, 1.07, 0.0), 0.012, 8, 2.5)
	box(carb, G(-0.22, 1.08, 0.0), Vector3(0.26, 0.03, 0.06))
	for s in [-1.0, 1.0]:
		box(dark, G(-0.21, 1.08, s * 0.13), Vector3(0.035, 0.04, 0.08))
		cyl(carb, G(-0.55, 0.9, s * 0.06), G(-0.6, 1.0, s * 0.06), 0.004, 6)
		cyl(metal, G(1.5, 0.55, s * 0.05), G(1.5, 0.72, s * 0.05), 0.004, 6)
	cyl(metal, G(3.0, 0.22, 0.0), G(3.15, 0.22, 0.0), 0.005, 6)
	# ---------------- asa dianteira (elementos fixos)
	var full := []
	for z in [-0.9, -0.74, -0.55, -0.34, -0.14, 0.0, 0.14, 0.34, 0.55, 0.74, 0.9]:
		full.append(_fw_stack(z))
	var e0 := []
	var e1 := []
	for d in full:
		e0.append(d[0])
		e1.append(d[1])
	wing(carb, e0, 0.11)
	wing(liv, e1, 0.09)
	for s in [-1.0, 1.0]:
		# placa lateral
		prism(carb, [[3.05, 0.015], [3.05, 0.1], [2.88, 0.17], [2.62, 0.27], [2.38, 0.31], [2.25, 0.31], [2.25, 0.13], [2.4, 0.04], [2.62, 0.0], [2.9, 0.0]],
			G(0, 0, s * 0.915), Vector3(0, 0, -1), Vector3(0, 1, 0), Vector3(1, 0, 0), 0.014)
		prism(liv, [[3.05, 0.0], [3.05, 0.025], [2.4, 0.025], [2.4, 0.0]], G(0, 0, s * 0.92), Vector3(0, 0, -1), Vector3(0, 1, 0), Vector3(1, 0, 0), 0.05)
		cyl(carb, G(2.76, 0.16, s * 0.03), G(2.87, 0.085, s * 0.13), 0.016, 8, 2.5)
		prism(carb, [[3.02, 0.05], [3.02, 0.1], [2.65, 0.14], [2.65, 0.05]], G(0, 0, s * 0.22), Vector3(0, 0, -1), Vector3(0, 1, 0), Vector3(1, 0, 0), 0.008)
	# ---------------- assoalho
	var outline := [[1.35, 0.28], [1.2, 0.45], [0.95, 0.66], [0.6, 0.78], [-0.7, 0.8], [-1.1, 0.72], [-1.35, 0.52], [-2.2, 0.48]]
	var poly := []
	for p in outline:
		poly.append([p[0], p[1]])
	for i in range(outline.size() - 1, -1, -1):
		poly.append([outline[i][0], -outline[i][1]])
	prism(carb, poly, Vector3(0, 0.07, 0), Vector3(0, 0, -1), Vector3(1, 0, 0), Vector3(0, 1, 0), 0.02)
	for s in [-1.0, 1.0]:
		for i in range(2, 6):
			var a: Array = outline[i]
			var b: Array = outline[i + 1]
			var pa := G(a[0], 0.11, s * a[1] * 0.985)
			var pb := G(b[0], 0.11, s * b[1] * 0.985)
			var mid := (pa + pb) * 0.5
			var dir := (pb - pa)
			var basis := Basis(Vector3.UP, atan2(-dir.x, -dir.z))
			box(carb, mid, Vector3(0.012, 0.06, dir.length()), basis)
		for k in 4:
			var z := 0.18 + k * 0.09
			prism(carb, [[1.34, 0.09], [1.34, 0.17 - k * 0.01], [1.05, 0.22], [0.72, 0.18], [0.72, 0.09]], G(0, 0, s * z), Vector3(0, 0, -1), Vector3(0, 1, 0), Vector3(1, 0, 0), 0.008)
		prism(liv, [[1.22, 0.09], [1.16, 0.3], [0.96, 0.37], [0.8, 0.37], [0.8, 0.09]], G(0, 0, s * 0.70), Vector3(0, 0, -1), Vector3(0, 1, 0), Vector3(1, 0, 0), 0.012)
		for k in 3:
			box(carb, G(-1.75, 0.3 + k * 0.08, s * 0.53), Vector3(0.07, 0.01, 0.34), Basis(Vector3.RIGHT, 0.08 + k * 0.04))
	# difusor
	box(carb, G(-1.9, 0.17, 0.0), Vector3(0.95, 0.02, 0.85), Basis(Vector3.RIGHT, -0.22))
	for z in [-0.42, -0.28, -0.14, 0.0, 0.14, 0.28, 0.42]:
		box(carb, G(-1.88, 0.13, z), Vector3(0.008, 0.12, 0.8), Basis(Vector3.RIGHT, -0.22))
	# ---------------- traseira
	loft(carb, [{"f": -1.95, "y": 0.38, "w": 0.1, "ht": 0.08, "hb": 0.08}, {"f": -2.2, "y": 0.36, "w": 0.07, "ht": 0.06, "hb": 0.06}, {"f": -2.42, "y": 0.35, "w": 0.05, "ht": 0.045, "hb": 0.045}], 20, 8)
	cyl(metal, G(-2.0, 0.52, 0.0), G(-2.18, 0.52, 0.0), 0.038, 16)
	prism(dark, _ellipse(0.032, 0.032, 14), G(-2.185, 0.52, 0.0), Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1), 0.004)
	# asa traseira: plano principal + beam wing
	var rw_z := [-0.49, -0.3, -0.12, 0.0, 0.12, 0.3, 0.49]
	var main := []
	var beam1 := []
	var beam2 := []
	for z in rw_z:
		main.append([-2.24, 0.93 - 0.02 * (1.0 - absf(z) / 0.49), z, 0.36, 9.0])
		beam1.append([-2.18, 0.47, z * 0.86, 0.15, 10.0])
		beam2.append([-2.32, 0.53, z * 0.86, 0.12, 24.0])
	wing(liv, main, 0.12)
	wing(carb, beam1, 0.1)
	wing(carb, beam2, 0.1)
	for s in [-1.0, 1.0]:
		prism(carb, [[-2.0, 0.6], [-2.0, 1.0], [-2.08, 1.12], [-2.22, 1.17], [-2.6, 1.17], [-2.6, 0.7], [-2.45, 0.6]], G(0, 0, s * 0.5), Vector3(0, 0, -1), Vector3(0, 1, 0), Vector3(1, 0, 0), 0.016)
		prism(liv, [[-2.06, 1.1], [-2.08, 1.12], [-2.22, 1.17], [-2.6, 1.17], [-2.6, 1.07], [-2.22, 1.07]], G(0, 0, s * 0.5), Vector3(0, 0, -1), Vector3(0, 1, 0), Vector3(1, 0, 0), 0.024)
	# pilar "pescoço de cisne"
	var sp := []
	for p in [[-1.98, 0.5], [-2.05, 0.8], [-2.12, 1.02], [-2.22, 1.05], [-2.26, 0.98]]:
		sp.append(G(p[0], p[1], 0.0))
	tube(carb, _smooth_path(sp, 6), 0.022, 8, Vector2(1.0, 0.5))
	# ---------------- suspensão
	for front in [true, false]:
		var x := 1.7 if front else -1.7
		var R := 0.36
		for s in [-1.0, 1.0]:
			var inner: float = s * (0.8 - (W_F if front else W_R) * 0.5 - 0.06)
			if front:
				cyl(arm, G(x, R + 0.15, inner), G(x + 0.28, 0.5, s * 0.13), 0.012, 8, 2.4)
				cyl(arm, G(x, R + 0.15, inner), G(x - 0.3, 0.52, s * 0.15), 0.012, 8, 2.4)
				cyl(arm, G(x, R - 0.16, inner), G(x + 0.32, 0.25, s * 0.11), 0.013, 8, 2.4)
				cyl(arm, G(x, R - 0.16, inner), G(x - 0.38, 0.24, s * 0.14), 0.013, 8, 2.4)
				cyl(metal, G(x + 0.02, R - 0.14, inner), G(x - 0.12, 0.52, s * 0.12), 0.011, 8)
				cyl(arm, G(x - 0.12, R, inner), G(x - 0.14, 0.38, s * 0.12), 0.009, 8, 2.0)
			else:
				cyl(arm, G(x, R + 0.14, inner), G(x + 0.32, 0.5, s * 0.18), 0.012, 8, 2.4)
				cyl(arm, G(x, R + 0.14, inner), G(x - 0.2, 0.5, s * 0.14), 0.012, 8, 2.4)
				cyl(arm, G(x, R - 0.16, inner), G(x + 0.4, 0.22, s * 0.2), 0.013, 8, 2.4)
				cyl(arm, G(x, R - 0.16, inner), G(x - 0.15, 0.22, s * 0.14), 0.013, 8, 2.4)
				cyl(metal, G(x, R, inner), G(x + 0.05, R, s * 0.12), 0.022, 10)
	var mesh := ArrayMesh.new()
	var parts := [[liv, "livery"], [carb, "carbon"], [dark, "dark"], [arm, "arm"], [metal, "metal"], [glass, "glass"]]
	for p in parts:
		var a: Acc = p[0]
		if a.v.is_empty():
			continue
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a.to_arrays())
		mesh.surface_set_material(mesh.get_surface_count() - 1, mat(p[1]))
	return mesh


static func _ellipse(rx: float, ry: float, seg: int) -> Array:
	var out := []
	for i in seg:
		var a := float(i) / seg * TAU
		out.append([cos(a) * rx, sin(a) * ry])
	return out


static func _smooth_path(pts: Array, per: int) -> Array:
	var out := []
	var L := pts.size()
	for i in L - 1:
		for k in per:
			var t := float(k) / per
			var a: Vector3 = pts[maxi(i - 1, 0)]
			var b: Vector3 = pts[i]
			var c: Vector3 = pts[i + 1]
			var d: Vector3 = pts[mini(i + 2, L - 1)]
			out.append(Vector3(_cr1(a.x, b.x, c.x, d.x, t), _cr1(a.y, b.y, c.y, d.y, t), _cr1(a.z, b.z, c.z, d.z, t)))
	out.append(pts[L - 1])
	return out


static func _fw_stack(z: float) -> Array:
	var a := absf(z)
	var rise := pow(maxf(0.0, (a - 0.18) / 0.72), 1.4)
	var C := []
	for c in [0.38, 0.19, 0.15, 0.12]:
		C.append(c * (1.0 - 0.15 * a))
	var A := [2.0 + 5.0 * rise, 8.0 + 16.0 * rise, 16.0 + 24.0 * rise, 24.0 + 28.0 * rise]
	var out := []
	var cx := 2.86 - 0.1 * a
	var cy := 0.06 + 0.025 * a
	for i in 4:
		var r := deg_to_rad(A[i])
		if i > 0:
			var pr := deg_to_rad(A[i - 1])
			var pc: float = C[i - 1]
			var tex: float = out[i - 1][0] - pc / 2.0 * cos(pr)
			var tey: float = out[i - 1][1] + pc / 2.0 * sin(pr)
			var lex := tex + 0.03
			var ley := tey + 0.01 + 0.025 * rise
			cx = lex - float(C[i]) / 2.0 * cos(r)
			cy = ley + float(C[i]) / 2.0 * sin(r)
		out.append([cx, cy, z, C[i], A[i]])
	return out


# ---------------------------------------------------------------- partes móveis
func _build_moving_parts(team: Dictionary) -> void:
	# flap da asa traseira (gira em torno do bordo de ataque no modo reta)
	if not _cache.has("flap_r"):
		var acc := Acc.new()
		var st := []
		for z in [-0.49, -0.3, -0.12, 0.0, 0.12, 0.3, 0.49]:
			st.append([-2.42, 1.04, z, 0.22, 30.0])
		wing(acc, st, 0.1, -0.05, G(-2.31, 1.04, 0.0))
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, acc.to_arrays())
		m.surface_set_material(0, mat("livery"))
		_cache["flap_r"] = m
	_flap_r = Node3D.new()
	_flap_r.position = G(-2.31, 1.04, 0.0)
	add_child(_flap_r)
	var fm := MeshInstance3D.new()
	fm.mesh = _cache["flap_r"]
	_flap_r.add_child(fm)
	_apply_livery(fm, team)
	# flaps superiores da asa dianteira (também abrem no modo reta, regra 2026)
	for s in [-1.0, 1.0]:
		var key := "flap_f%d" % int(s)
		var piv_d: Array = _fw_stack(s * 0.5)[2]
		var pivot := G(piv_d[0] + piv_d[3] * 0.5, piv_d[1], 0.0)
		if not _cache.has(key):
			var acc := Acc.new()
			var e2 := []
			var e3 := []
			for z in [0.1, 0.25, 0.42, 0.6, 0.76, 0.9]:
				var d := _fw_stack(s * z)
				e2.append(d[2])
				e3.append(d[3])
			wing(acc, e2, 0.09, -0.05, pivot)
			wing(acc, e3, 0.09, -0.05, pivot)
			var m := ArrayMesh.new()
			m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, acc.to_arrays())
			m.surface_set_material(0, mat("livery"))
			_cache[key] = m
		var node := Node3D.new()
		node.position = pivot
		add_child(node)
		var mi := MeshInstance3D.new()
		mi.mesh = _cache[key]
		node.add_child(mi)
		_apply_livery(mi, team)
		_flap_f.append(node)


func _apply_livery(mi: GeometryInstance3D, team: Dictionary) -> void:
	mi.set_instance_shader_parameter("primary", team["primary"])
	mi.set_instance_shader_parameter("secondary", team["secondary"])
	mi.set_instance_shader_parameter("accent", team["accent"])


func _build_wheels() -> void:
	_band_mat = StandardMaterial3D.new()
	_band_mat.albedo_color = Color(1.0, 0.82, 0.05)
	_band_mat.roughness = 0.6
	for i in 4:
		var front := i < 2
		var left := i % 2 == 0
		var R := 0.36 if front else 0.365
		var W := W_F if front else W_R
		var key := "tyre_%s" % ("f" if front else "r")
		if not _cache.has(key):
			var acc := Acc.new()
			var prof := []
			for p in [[0.70, -0.47], [0.74, -0.5], [0.93, -0.5], [0.985, -0.45], [1.0, -0.33], [1.0, 0.33], [0.985, 0.45], [0.93, 0.5], [0.74, 0.5], [0.70, 0.47]]:
				prof.append([p[0] * R, p[1] * W])
			lathe_x(acc, prof, 48)
			var m := ArrayMesh.new()
			m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, acc.to_arrays())
			m.surface_set_material(0, mat("tyre"))
			_cache[key] = m
		var root := Node3D.new()
		var sx := -0.8 if left else 0.8
		if not front:
			sx = -0.78 if left else 0.78
		root.position = Vector3(sx, R, -1.7 if front else 1.7)
		add_child(root)
		var steer := Node3D.new()
		root.add_child(steer)
		var spin := Node3D.new()
		steer.add_child(spin)
		var tyre := MeshInstance3D.new()
		tyre.mesh = _cache[key]
		spin.add_child(tyre)
		# aro
		var barrel := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = R * 0.7
		cm.bottom_radius = R * 0.7
		cm.height = W * 0.9
		cm.radial_segments = 32
		cm.material = mat("dark")
		barrel.mesh = cm
		barrel.rotation.z = PI * 0.5
		spin.add_child(barrel)
		var face := MeshInstance3D.new()
		var fcm := CylinderMesh.new()
		fcm.top_radius = R * 0.7
		fcm.bottom_radius = R * 0.7
		fcm.height = 0.01
		fcm.radial_segments = 32
		fcm.material = mat("rim")
		face.mesh = fcm
		face.rotation.z = PI * 0.5
		face.position.x = (W * 0.3) * (-1.0 if left else 1.0)
		spin.add_child(face)
		# faixa colorida do composto (dos dois lados)
		for sd in [-1.0, 1.0]:
			var band := MeshInstance3D.new()
			var tm := TorusMesh.new()
			tm.inner_radius = R * 0.83
			tm.outer_radius = R * 0.88
			tm.rings = 48
			tm.ring_segments = 6
			tm.material = _band_mat
			band.mesh = tm
			band.rotation.z = PI * 0.5
			band.scale = Vector3(1.0, 0.25, 1.0)
			band.position.x = sd * W * 0.5
			spin.add_child(band)
		# carenagem do freio (não gira)
		var drum := MeshInstance3D.new()
		var dm := CylinderMesh.new()
		dm.top_radius = R * 0.55
		dm.bottom_radius = R * 0.6
		dm.height = 0.12
		dm.material = mat("carbon")
		drum.mesh = dm
		drum.rotation.z = PI * 0.5
		drum.position.x = (W * 0.5 + 0.04) * (1.0 if left else -1.0)
		steer.add_child(drum)
		wheel_root.append(root)
		wheel_steer.append(steer)
		wheel_spin.append(spin)


func _build_cockpit(team: Dictionary, player: bool) -> void:
	# capacete
	var helmet := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.125
	sm.height = 0.25
	var hm := StandardMaterial3D.new()
	hm.albedo_color = (team["secondary"] as Color).lerp(Color.WHITE, 0.3)
	hm.roughness = 0.2
	hm.clearcoat_enabled = true
	sm.material = hm
	helmet.mesh = sm
	helmet.position = G(0.1, 0.81, 0.0)
	helmet.scale = Vector3(0.94, 1.0, 1.08)
	add_child(helmet)
	var visor := MeshInstance3D.new()
	var vm := SphereMesh.new()
	vm.radius = 0.128
	vm.height = 0.12
	vm.is_hemisphere = false
	vm.material = mat("glass")
	visor.mesh = vm
	visor.position = G(0.15, 0.83, 0.0)
	visor.scale = Vector3(0.85, 0.5, 0.6)
	add_child(visor)
	if player:
		helmet.layers = HIDE_LAYER
		visor.layers = HIDE_LAYER
	# volante
	_steer_node = Node3D.new()
	_steer_node.position = G(0.40, 0.70, 0.0)
	_steer_node.rotation.x = -0.45
	add_child(_steer_node)
	var wheel := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.27, 0.13, 0.03)
	bm.material = mat("carbon")
	wheel.mesh = bm
	_steer_node.add_child(wheel)
	for s in [-1.0, 1.0]:
		var grip := MeshInstance3D.new()
		var gm := CapsuleMesh.new()
		gm.radius = 0.022
		gm.height = 0.13
		gm.material = mat("dark")
		grip.mesh = gm
		grip.position = Vector3(s * 0.14, -0.01, 0.0)
		_steer_node.add_child(grip)
	var screen := MeshInstance3D.new()
	var scm := BoxMesh.new()
	scm.size = Vector3(0.1, 0.055, 0.004)
	var scmat := StandardMaterial3D.new()
	scmat.albedo_color = Color(0.02, 0.05, 0.08)
	scmat.emission_enabled = true
	scmat.emission = Color(0.05, 0.25, 0.4)
	scm.material = scmat
	screen.mesh = scm
	screen.position = Vector3(0, 0.01, -0.018)
	_steer_node.add_child(screen)
	_gear_label = Label3D.new()
	_gear_label.text = "N"
	_gear_label.font_size = 64
	_gear_label.pixel_size = 0.0006
	_gear_label.outline_size = 0
	_gear_label.modulate = Color(1, 1, 1)
	_gear_label.position = Vector3(0, 0.012, -0.022)
	_gear_label.rotation.y = PI
	_steer_node.add_child(_gear_label)
	# luzes de troca (15 LEDs)
	for k in 15:
		var led := MeshInstance3D.new()
		var lm := BoxMesh.new()
		lm.size = Vector3(0.008, 0.008, 0.004)
		var lmat := StandardMaterial3D.new()
		lmat.emission_enabled = true
		lmat.albedo_color = Color(0.05, 0.05, 0.05)
		lmat.emission = Color(0.1, 1.0, 0.2) if k < 5 else (Color(1.0, 0.1, 0.1) if k < 10 else Color(0.3, 0.3, 1.0))
		lmat.emission_energy_multiplier = 0.0
		lm.material = lmat
		led.mesh = lm
		led.position = Vector3(-0.07 + k * 0.01, 0.055, -0.018)
		_steer_node.add_child(led)
		_led_mats.append(lmat)


func _build_lights() -> void:
	_rain_mat = StandardMaterial3D.new()
	_rain_mat.albedo_color = Color(0.2, 0.0, 0.0)
	_rain_mat.emission_enabled = true
	_rain_mat.emission = Color(1.0, 0.05, 0.03)
	_rain_mat.emission_energy_multiplier = 0.0
	var l := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.06, 0.035, 0.012)
	bm.material = _rain_mat
	l.mesh = bm
	l.position = G(-2.43, 0.35, 0.0)
	add_child(l)
	_brake_mat = _rain_mat
	for s in [-1.0, 1.0]:
		var e := MeshInstance3D.new()
		var em := BoxMesh.new()
		em.size = Vector3(0.012, 0.3, 0.012)
		em.material = _rain_mat
		e.mesh = em
		e.position = G(-2.605, 0.88, s * 0.5)
		add_child(e)


func _build_number(number: int, team: Dictionary) -> void:
	for s in [-1.0, 1.0]:
		var l := Label3D.new()
		l.text = str(number)
		l.font_size = 96
		l.pixel_size = 0.0018
		l.outline_size = 12
		l.outline_modulate = team["accent"]
		l.modulate = Color.WHITE
		l.position = G(-0.75, 0.86, s * 0.012)
		l.rotation.y = PI * 0.5 * s
		add_child(l)
	var nose := Label3D.new()
	nose.text = str(number)
	nose.font_size = 96
	nose.pixel_size = 0.0016
	nose.outline_size = 10
	nose.outline_modulate = team["accent"]
	nose.position = G(2.0, 0.53, 0.0)
	nose.rotation = Vector3(-PI * 0.5 + 0.12, 0.0, 0.0)
	add_child(nose)


# ======================================================================= atualização
func set_wheel(i: int, comp: float, spin: float, steer: float) -> void:
	var root: Node3D = wheel_root[i]
	var R := 0.36 if i < 2 else 0.365
	root.position.y = R + comp
	(wheel_steer[i] as Node3D).rotation.y = -steer
	(wheel_spin[i] as Node3D).rotation.x = spin


func set_steering(v: float) -> void:
	if _steer_node:
		_steer_node.rotation.z = v * 1.4


func set_aero(open: bool) -> void:
	var target := 1.0 if open else 0.0
	if _aero_t == target:
		return
	_aero_t = move_toward(_aero_t, target, 0.08)
	if _flap_r:
		_flap_r.rotation.x = -_aero_t * 0.45
	for f in _flap_f:
		(f as Node3D).rotation.x = -_aero_t * 0.3


func set_compound(c: Color) -> void:
	if _band_mat:
		_band_mat.albedo_color = c


func set_brake_light(_on: bool) -> void:
	pass


func set_rain_light(on: bool) -> void:
	_rain_on = on
	if _rain_mat:
		var blink := on and (Time.get_ticks_msec() / 250) % 2 == 0
		_rain_mat.emission_energy_multiplier = 8.0 if blink else 0.0


func set_dash(gear: int, rpm_frac: float) -> void:
	if _gear_label:
		_gear_label.text = "R" if gear < 0 else ("N" if gear == 0 else str(gear))
	for k in _led_mats.size():
		var lm: StandardMaterial3D = _led_mats[k]
		var on := rpm_frac > 0.72 + k * 0.018
		lm.emission_energy_multiplier = 3.0 if on else 0.0
