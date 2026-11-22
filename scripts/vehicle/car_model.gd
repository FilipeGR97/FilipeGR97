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
const CLASSICCAM := Vector3(0.0, 1.3, 0.32)          # estilo jogos de 2006: alta, vê o carro inteiro
const NOSECAM := Vector3(0.0, 0.62, -1.55)
const HIDE_LAYER := 1 << 19                      # capacete do jogador (oculto na câmera cockpit)
const W_F := 0.30
const W_R := 0.38

static var _cache: Dictionary = {}

## Modelos 3D externos com licença livre (CC-BY 4.0, créditos em assets/CREDITOS.md), por variante.
## pivot = ponto do modelo original que vira a origem (meio entre os eixos, no chão); flip = frente em +Z.
## hide = peças escondidas (rodas/pneus/volante originais: o jogo usa os próprios, que giram e esterçam).
## cockpit = deslocamento do piloto/volante/câmeras em relação ao carro procedural.
const EXT_MODELS := {
	"2026": {"path": "res://assets/cars_src/sf90/SF90.fbx", "scale": 1.16, "pivot": Vector3(0.0, 0.0917, -0.185), "flip": true,
		"hide": ["Rim ", "Tire ", "Decal", "Decail", "Steering Wheel", "Buttons", "Grip Button", "Ferrari Button", "Gears", "Its for something"],
		"wheel_z": 1.8, "cockpit": Vector3(0.0, -0.13, -0.365), "nosecam": Vector3(0.0, 0.74, -1.45), "mirror": Vector3(0.47, 0.7, -0.62),
		"paint": {"Main": ["res://assets/cars_src/sf90/textures/SF90_Main_", Color(0.808, 0.043, 0.055)]},
		# onde ficavam as marcas reais (peças de decalque do modelo) -> nossos patrocinadores fictícios
		"slots": {"Decal Shell Left": "title", "Decal Shell Right": "title", "Decal Ray Ban Left": "second", "Decal Ray Ban Right": "second",
			"Decal UPS Left": "third", "Decal UPS Right": "third", "Decal Hublot Left": "fourth", "Decal Hublot Right": "fourth",
			"Decal Rear Wing": "title", "Decal Shell V-Power Rear Left": "title", "Decal Shell V-Power Rear Right": "title",
			"Decal Rear Wing Left": "second", "Decal Rear Wing Right": "second", "Decal Kaspersky Front Left": "second",
			"Decal Kaspersky Front Right": "second", "Decal Shell V-Power Front Left": "third", "Decal Shell V-Power Front Right": "third",
			"Decal Number 5 Front": "number", "Decal Number 5 Left": "number", "Decal Number 5 Right": "number",
			"Decal Weichai": "fourth", "Decal Lenovo Left": "tyre", "Decal Lenovo Right": "tyre"}},
}
static var _mats: Dictionary = {}

var wheel_root: Array = []
var wheel_steer: Array = []
var wheel_spin: Array = []
var body: MeshInstance3D
var _nut_mat: StandardMaterial3D
var ext: Dictionary = {}          # configuração do modelo externo em uso (vazio = procedural)
var cam_off := Vector3.ZERO        # deslocamento das câmeras de cockpit (modelo externo)
var nose_cam := NOSECAM
var mirror_pos := Vector3(0.53, 0.735, -0.676)   # espelho direito (o esquerdo é o simétrico)
var _wheel_z := 1.7
var _tyres: Array = []          # MeshInstance3D dos pneus (cor do composto por instância)
var _compound_col := Color(1.0, 0.82, 0.05)
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
var _damage := 0.0
var variant := "2026"            # modelo da categoria: 2026, v10, lenda, eletrico
var _wrist_local: Array = []     # pulsos (no espaço do volante)
var _arms: Array = []            # [braço, antebraço, cotovelo] por lado


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
			c.uv1_scale = Vector3(18, 18, 18)
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
		"alu":
			var al := StandardMaterial3D.new()
			al.albedo_color = Color(0.7, 0.71, 0.74)
			al.metallic = 0.95
			al.roughness = 0.28
			m = al
		"rim_classic":
			var rc := StandardMaterial3D.new()
			rc.albedo_color = Color(0.8, 0.8, 0.82)
			rc.metallic = 0.55
			rc.roughness = 0.32
			m = rc
		"rim":
			var r := StandardMaterial3D.new()
			r.albedo_texture = _rim_tex()
			r.metallic = 0.6
			r.roughness = 0.35
			m = r
	_mats[key] = m
	return m


## Fibra de carbono em sarja 2x2: cada "fio" com brilho em gradiente e a trama alternando a direção.
static func _carbon_tex() -> ImageTexture:
	var n := 128
	var cell := 8
	var img := Image.create(n, n, true, Image.FORMAT_RGB8)
	for y in n:
		for x in n:
			var cx := x / cell
			var cy := y / cell
			var horiz := ((cx + cy) % 4) < 2
			var fx := float(x % cell) / cell
			var fy := float(y % cell) / cell
			# fio arredondado: claro no meio, escuro nas bordas da trama
			var t := fy if horiz else fx
			var along := fx if horiz else fy
			var hi := 1.0 - pow(absf(t - 0.5) * 2.0, 2.0)
			var v := (0.05 + 0.13 * hi) * (0.9 + 0.1 * sin(along * PI))
			if horiz:
				v *= 1.25
			img.set_pixel(x, y, Color(v, v * 1.03, v * 1.1))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## Face da roda no espaço do pneu (eixo X = eixo da roda; out_s = lado de fora).
static func _wheel_face(rr: float, W: float, out_s: float, spokes: bool) -> ArrayMesh:
	var lip := Acc.new()
	var main := Acc.new()
	var back := Acc.new()
	var ax := W * 0.49 * out_s
	# borda do aro (anel usinado rente à lateral do pneu)
	lathe_x(lip, [[rr * 0.86, ax - out_s * 0.03], [rr * 1.04, ax - out_s * 0.03], [rr * 1.04, ax], [rr * 0.86, ax]], 48)
	if spokes:
		# aro clássico: raios do cubo até a borda, fundo escuro (o freio aparece entre os raios)
		var n_sp := 6
		for k in n_sp:
			var an := TAU * k / n_sp
			var dirv := Vector3(0, cos(an), sin(an))
			var p0 := Vector3(ax - out_s * 0.05, 0, 0) + dirv * rr * 0.2
			var p1 := Vector3(ax - out_s * 0.012, 0, 0) + dirv * rr * 0.9
			cyl(main, p0, p1, rr * 0.1, 8, 1.7)
		lathe_x(main, [[0.0, ax - out_s * 0.07], [rr * 0.24, ax - out_s * 0.07], [rr * 0.24, ax - out_s * 0.03], [0.0, ax - out_s * 0.03]], 24)
		lathe_x(back, [[0.0, ax - out_s * 0.16], [rr * 0.92, ax - out_s * 0.16], [rr * 0.92, ax - out_s * 0.15], [0.0, ax - out_s * 0.15]], 32)
	else:
		# calota de carbono quase plana (regulamento atual), levemente côncava
		lathe_x(main, [[0.0, ax - out_s * 0.05], [rr * 0.87, ax - out_s * 0.025], [rr * 0.87, ax - out_s * 0.018], [0.0, ax - out_s * 0.04]], 48)
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, lip.to_arrays())
	m.surface_set_material(0, mat("alu"))
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, main.to_arrays())
	m.surface_set_material(1, mat("rim_classic") if spokes else mat("carbon"))
	if not back.v.is_empty():
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, back.to_arrays())
		m.surface_set_material(2, mat("dark"))
	return m


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
func build(team: Dictionary, number: int, player: bool, driver: Dictionary = {}) -> void:
	var custom := _try_custom_model(team)
	var vk := String(Categories.get_data(Car.category)["model"])
	if custom:
		add_child(custom)
	elif EXT_MODELS.has(vk) and ResourceLoader.exists(EXT_MODELS[vk]["path"]) and not OS.get_cmdline_user_args().has("procedural"):
		variant = vk
		ext = EXT_MODELS[vk]
		add_child(_ext_model(ext, team, number, player))
		_wheel_z = float(ext["wheel_z"])
		cam_off = ext["cockpit"]
		nose_cam = ext.get("nosecam", NOSECAM)
		mirror_pos = ext.get("mirror", mirror_pos)
	else:
		variant = String(Categories.get_data(Car.category)["model"])
		if not _cache.has("body_" + variant):
			_cache["body_" + variant] = _build_body(variant)
		body = MeshInstance3D.new()
		body.mesh = _cache["body_" + variant]
		add_child(body)
		body.set_instance_shader_parameter("primary", team["primary"])
		body.set_instance_shader_parameter("secondary", team["secondary"])
		body.set_instance_shader_parameter("accent", team["accent"])
		_livery_style(body, team)
	if ext.is_empty():
		_build_moving_parts(team)
	# porca central das rodas: cor de destaque da equipe (como nos carros reais)
	_nut_mat = StandardMaterial3D.new()
	var nc: Color = team["accent"]
	if nc.get_luminance() < 0.1:
		nc = team["secondary"]
	_nut_mat.albedo_color = nc
	_nut_mat.metallic = 0.7
	_nut_mat.roughness = 0.3
	_build_wheels()
	var n0 := get_child_count()
	_build_cockpit(team, player, driver)
	if not ext.is_empty():
		# piloto, volante e braços vão juntos para o cockpit do modelo externo
		var drv := Node3D.new()
		drv.position = cam_off
		var moved := []
		for i in range(n0, get_child_count()):
			moved.append(get_child(i))
		add_child(drv)
		for nd in moved:
			remove_child(nd)
			drv.add_child(nd)
		return
	_build_lights()
	_build_number(number, team)


## Instancia o modelo externo: gira (frente em -Z), escala, apoia no chão e esconde as peças da lista.
func _ext_model(cfg: Dictionary, team: Dictionary = {}, number := 0, player := false) -> Node3D:
	var ps: PackedScene = load(cfg["path"])
	var inst := ps.instantiate() as Node3D
	var sc := float(cfg["scale"])
	var b := Basis(Vector3.UP, PI if cfg.get("flip", false) else 0.0).scaled(Vector3(sc, sc, sc))
	var holder := Node3D.new()
	holder.transform = Transform3D(b, -(b * (cfg["pivot"] as Vector3)))
	holder.add_child(inst)
	var paint: Dictionary = cfg.get("paint", {})
	for nd in _all_nodes(inst):
		if not (nd is MeshInstance3D):
			continue
		var mi := nd as MeshInstance3D
		var slot: String = cfg.get("slots", {}).get(String(mi.name), "")
		if slot != "" and not team.is_empty():
			_ext_sponsor(holder.transform * _chain_xf(mi, inst) * mi.get_aabb(), slot, team, number)
		for pre in cfg["hide"]:
			if String(mi.name).begins_with(pre):
				mi.visible = false
		if not mi.visible:
			continue
		# adversários trocam para versões mais simples da malha mais cedo (o modelo tem ~650 mil triângulos)
		mi.lod_bias = 1.0 if player else 0.45
		# material original -> nosso shader (texturas originais + pintura da nossa equipe)
		var to_car := holder.transform * _chain_xf(mi, inst)
		for si in mi.mesh.get_surface_count():
			var m0 := mi.mesh.surface_get_material(si)
			var mname := m0.resource_name if m0 else ""
			if not paint.has(mname):
				continue
			var key := "extmat_%s_%s_%d" % [cfg["path"], String(inst.get_path_to(mi)), si]
			if not _cache.has(key):
				var sm := ShaderMaterial.new()
				sm.shader = load("res://shaders/ext_paint.gdshader")
				var pre2: String = paint[mname][0]
				sm.set_shader_parameter("base_tex", load(pre2 + "BaseColor.png"))
				sm.set_shader_parameter("normal_tex", load(pre2 + "Normal.png"))
				sm.set_shader_parameter("rough_tex", load(pre2 + "Roughness.png"))
				sm.set_shader_parameter("metal_tex", load(pre2 + "Metallic.png"))
				sm.set_shader_parameter("paint_ref", paint[mname][1])
				sm.set_shader_parameter("to_car", Projection(to_car))
				_cache[key] = sm
			mi.set_surface_override_material(si, _cache[key])
		if not team.is_empty():
			mi.set_instance_shader_parameter("primary", team["primary"])
			mi.set_instance_shader_parameter("secondary", team["secondary"])
			mi.set_instance_shader_parameter("accent", team["accent"])
			_livery_style(mi, team)
	return holder


## Patrocinador fictício no lugar de uma marca real: texto plano encostado na superfície da peça de
## decalque original (caixa no espaço do carro: o eixo mais fino é a normal da superfície).
func _ext_sponsor(box: AABB, slot: String, team: Dictionary, number: int) -> void:
	var h := absi(hash(String(team["name"])))
	var names := {
		"title": String(team.get("title", SPONSORS[h % SPONSORS.size()])),
		"second": SPONSORS[(h / 7 + 3) % SPONSORS.size()],
		"third": SPONSORS[(h / 13 + 7) % SPONSORS.size()],
		"fourth": SPONSORS[(h / 17 + 11) % SPONSORS.size()],
		"tyre": "VELTRA",
		"number": str(number),
	}
	var text: String = names[slot]
	var sz := box.size
	var c := box.get_center()
	var axis := 0
	if sz.y <= sz.x and sz.y <= sz.z:
		axis = 1
	elif sz.z <= sz.x and sz.z <= sz.y:
		axis = 2
	var nrm := Vector3.ZERO
	var along := 0.0
	var tall := 0.0
	if axis == 0:
		nrm = Vector3(signf(c.x) if absf(c.x) > 0.01 else 1.0, 0, 0)
		along = sz.z
		tall = sz.y
	elif axis == 1:
		nrm = Vector3.UP
		along = maxf(sz.x, sz.z)
		tall = minf(sz.x, sz.z)
	else:
		nrm = Vector3(0, 0, signf(c.z) if absf(c.z) > 0.01 else 1.0)
		along = sz.x
		tall = sz.y
	var right: Vector3
	var up: Vector3
	if axis == 1:
		# superfície de cima: legível para quem olha de trás/de cima
		up = Vector3.FORWARD
		right = Vector3.RIGHT
	else:
		right = Vector3.UP.cross(nrm).normalized()
		up = nrm.cross(right).normalized()
	var l := Label3D.new()
	l.text = text
	l.font_size = 96
	l.outline_size = 10
	l.outline_modulate = Color(0, 0, 0, 0.45)
	l.modulate = Color(0.97, 0.97, 0.97)
	l.double_sided = false
	l.shaded = true
	l.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	l.visibility_range_end = 60.0
	# cabe na largura e na altura da área original
	var est_w := 0.6 * text.length() * 96.0
	l.pixel_size = clampf(minf(along * 0.85 / est_w, tall * 0.75 / 96.0), 0.0004, 0.004)
	l.transform = Transform3D(Basis(right, up, nrm), c + nrm * (sz[axis] * 0.5 + 0.006))
	add_child(l)


## Transformação de um nó até um ancestral (sem precisar estar na árvore).
static func _chain_xf(n: Node, top: Node) -> Transform3D:
	var t := Transform3D()
	var c := n
	while c != null and c != top.get_parent():
		if c is Node3D:
			t = (c as Node3D).transform * t
		c = c.get_parent()
	return t


static func _all_nodes(n: Node) -> Array:
	var out := [n]
	for c in n.get_children():
		out.append_array(_all_nodes(c))
	return out


func _try_custom_model(team: Dictionary) -> Node3D:
	for p in ["res://assets/cars/%s.glb" % String(team["short"]).to_lower(), "res://assets/cars/default.glb"]:
		if ResourceLoader.exists(p):
			var ps: PackedScene = load(p)
			if ps:
				return ps.instantiate()
	return null


static func _build_body(vk := "2026") -> ArrayMesh:
	var liv := Acc.new()
	var carb := Acc.new()
	var dark := Acc.new()
	var arm := Acc.new()
	var metal := Acc.new()
	var glass := Acc.new()
	# ---------------- monocoque + bico (V10: bico alto; lenda: baixo e fino; elétrico: largo)
	var mono := [
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
	]
	for sec in mono:
		var f: float = sec["f"]
		if vk == "v10" and f > 1.0:
			sec["y"] = float(sec["y"]) + 0.2 * clampf((f - 1.0) / 1.0, 0.0, 1.0)
			sec["hb"] = float(sec["hb"]) * lerpf(1.0, 0.6, clampf((f - 1.0) / 1.5, 0.0, 1.0))
		elif vk == "lenda" and f > 0.5:
			sec["y"] = float(sec["y"]) - 0.05 * clampf((f - 0.5) / 1.5, 0.0, 1.0)
			sec["w"] = float(sec["w"]) * 0.85
		elif vk == "eletrico" and f > 1.0:
			sec["w"] = float(sec["w"]) * 1.35
			sec["y"] = float(sec["y"]) - 0.03
	loft(liv, mono, 48, 10)
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
	# barbatana (só nos carros modernos)
	if vk == "2026":
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
	if vk == "2026" or vk == "eletrico":
		tube(arm, _smooth_path(hp, 6), 0.024, 12)
		cyl(arm, G(0.53, 0.985, 0.0), G(0.84, 0.66, 0.0), 0.026, 10, 1.6)
	else:
		# era clássica: santantônio atrás da cabeça
		cyl(arm, G(-0.12, 0.8, 0.0), G(-0.16, 1.0, 0.0), 0.03, 10)
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
	if vk != "lenda":
		wing(liv, e1, 0.09)
	if vk == "v10":
		# bico alto: pilones ligando o bico à asa dianteira
		for s in [-1.0, 1.0]:
			prism(carb, [[2.95, 0.06], [2.95, 0.36], [2.55, 0.44], [2.45, 0.44], [2.45, 0.06]], G(0, 0, s * 0.07), Vector3(0, 0, -1), Vector3(0, 1, 0), Vector3(1, 0, 0), 0.012)
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
	var rdy: float = {"2026": 0.0, "v10": 0.07, "lenda": 0.2, "eletrico": -0.17}[vk]
	var rchord: float = {"2026": 0.36, "v10": 0.32, "lenda": 0.48, "eletrico": 0.24}[vk]
	var main := []
	var upper := []
	var beam1 := []
	var beam2 := []
	for z in rw_z:
		main.append([-2.24, 0.93 + rdy - 0.02 * (1.0 - absf(z) / 0.49), z, rchord, 9.0])
		upper.append([-2.4, 1.07 + rdy, z, 0.16, 28.0])
		beam1.append([-2.18, 0.47, z * 0.86, 0.15, 10.0])
		beam2.append([-2.32, 0.53, z * 0.86, 0.12, 24.0])
	wing(liv, main, 0.12)
	if vk == "v10" or vk == "lenda":
		wing(carb, upper, 0.1)
	if vk == "2026" or vk == "v10":
		wing(carb, beam1, 0.1)
		wing(carb, beam2, 0.1)
	for s in [-1.0, 1.0]:
		var ep := [[-2.0, 0.6], [-2.0, 1.0], [-2.08, 1.12], [-2.22, 1.17], [-2.6, 1.17], [-2.6, 0.7], [-2.45, 0.6]]
		var ept := [[-2.06, 1.1], [-2.08, 1.12], [-2.22, 1.17], [-2.6, 1.17], [-2.6, 1.07], [-2.22, 1.07]]
		for q in ep:
			if q[1] > 0.95:
				q[1] += rdy
		for q in ept:
			q[1] += rdy
		prism(carb, ep, G(0, 0, s * 0.5), Vector3(0, 0, -1), Vector3(0, 1, 0), Vector3(1, 0, 0), 0.016)
		prism(liv, ept, G(0, 0, s * 0.5), Vector3(0, 0, -1), Vector3(0, 1, 0), Vector3(1, 0, 0), 0.024)
	# elétrico: para-lamas sobre as rodas (estilo Fórmula E)
	if vk == "eletrico":
		for front in [true, false]:
			var cx := 1.7 if front else -1.7
			for s in [-1.0, 1.0]:
				var a0 := 15.0 if front else -30.0
				var a1 := 165.0 if front else 110.0
				var prev := Vector3.ZERO
				for k in 15:
					var an := deg_to_rad(lerpf(a0, a1, float(k) / 14.0))
					var pnt := G(cx + cos(an) * 0.43 * (1.0 if front else -1.0), 0.36 + sin(an) * 0.43, s * 0.8)
					if k > 0:
						var mid := (pnt + prev) * 0.5
						var dir := pnt - prev
						box(liv, mid, Vector3(0.36, 0.012, dir.length() + 0.01), Basis(Vector3.RIGHT, atan2(dir.y, -dir.z)))
					prev = pnt
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
	var rdy: float = {"2026": 0.0, "v10": 0.07, "lenda": 0.2, "eletrico": -0.17}.get(variant, 0.0)
	_flap_r.position = G(-2.31, 1.04 + rdy, 0.0)
	add_child(_flap_r)
	var fm := MeshInstance3D.new()
	fm.mesh = _cache["flap_r"]
	_flap_r.add_child(fm)
	_apply_livery(fm, team)
	# flaps superiores da asa dianteira (também abrem no modo reta, regra 2026); lenda: asa de 1 elemento
	for s in ([] if variant == "lenda" else [-1.0, 1.0]):
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


## Estilo de pintura (grafismo) e acabamento (0 brilhante, 1 fosco, 2 metálico) da equipe.
static func _livery_style(mi: GeometryInstance3D, team: Dictionary) -> void:
	var sty := float(team.get("style", 3 if team.get("legend", false) else 0))
	mi.set_instance_shader_parameter("pattern", sty)
	mi.set_instance_shader_parameter("finish", float(team.get("finish", 0)))
	mi.set_instance_shader_parameter("metal", 0.0)


func _apply_livery(mi: GeometryInstance3D, team: Dictionary) -> void:
	mi.set_instance_shader_parameter("primary", team["primary"])
	mi.set_instance_shader_parameter("secondary", team["secondary"])
	mi.set_instance_shader_parameter("accent", team["accent"])
	_livery_style(mi, team)


func _build_wheels() -> void:
	# rodas por categoria: 2026/elétrico 18" (perfil baixo); clássicos 13" (perfil alto)
	var rim_k: float = {"2026": 0.7, "v10": 0.52, "lenda": 0.5, "eletrico": 0.68}.get(variant, 0.7)
	var wk_f: float = {"2026": 1.0, "v10": 1.05, "lenda": 0.95, "eletrico": 0.9}.get(variant, 1.0)
	var wk_r: float = {"2026": 1.0, "v10": 1.0, "lenda": 1.18, "eletrico": 0.8}.get(variant, 1.0)
	for i in 4:
		var front := i < 2
		var left := i % 2 == 0
		var R := 0.36 if front else 0.365
		var W := (W_F * wk_f) if front else (W_R * wk_r)
		var key := "tyre_%s_%s" % ["f" if front else "r", variant]
		if not _cache.has(key):
			var acc := Acc.new()
			var prof := []
			var r0 := rim_k
			var r1 := rim_k + 0.04
			for p in [[r0, -0.47], [r1, -0.5], [0.93, -0.5], [0.985, -0.45], [1.0, -0.33], [1.0, 0.33], [0.985, 0.45], [0.93, 0.5], [r1, 0.5], [r0, 0.47]]:
				prof.append([p[0] * R, p[1] * W])
			lathe_x(acc, prof, 48)
			var m := ArrayMesh.new()
			m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, acc.to_arrays())
			var tm := ShaderMaterial.new()
			tm.shader = load("res://shaders/tyre.gdshader")
			tm.set_shader_parameter("letters", load("res://assets/textures/tyre_letters.png"))
			tm.set_shader_parameter("r_out", R)
			tm.set_shader_parameter("r_side0", r1 * R)
			tm.set_shader_parameter("r_side1", 0.93 * R)
			tm.set_shader_parameter("half_w", 0.5 * W)
			m.surface_set_material(0, tm)
			_cache[key] = m
		var root := Node3D.new()
		var sx := -0.8 if left else 0.8
		if not front:
			sx = -0.78 if left else 0.78
		root.position = Vector3(sx, R, -_wheel_z if front else _wheel_z)
		add_child(root)
		var steer := Node3D.new()
		root.add_child(steer)
		var spin := Node3D.new()
		steer.add_child(spin)
		var tyre := MeshInstance3D.new()
		tyre.mesh = _cache[key]
		tyre.set_instance_shader_parameter("band", _compound_col)
		spin.add_child(tyre)
		_tyres.append(tyre)
		# aro
		var barrel := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = R * rim_k
		cm.bottom_radius = R * rim_k
		cm.height = W * 0.9
		cm.radial_segments = 32
		cm.material = mat("dark")
		barrel.mesh = cm
		barrel.rotation.z = PI * 0.5
		spin.add_child(barrel)
		# face da roda (gira com o pneu): borda do aro usinada, calota de carbono (2026/elétrico) ou
		# raios prateados (clássicos) e porca central na cor de destaque da equipe
		var out_s := -1.0 if left else 1.0
		var fkey := "wface_%s_%s_%d" % [variant, "f" if front else "r", int(out_s)]
		if not _cache.has(fkey):
			_cache[fkey] = _wheel_face(R * rim_k, W, out_s, variant == "v10" or variant == "lenda")
		var face := MeshInstance3D.new()
		face.mesh = _cache[fkey]
		spin.add_child(face)
		var nut := MeshInstance3D.new()
		var nm := CylinderMesh.new()
		nm.top_radius = 0.034
		nm.bottom_radius = 0.05
		nm.height = 0.05
		nm.radial_segments = 6
		nm.material = _nut_mat
		nut.mesh = nm
		nut.rotation.z = -PI * 0.5 * out_s
		nut.position.x = out_s * (W * 0.46)
		spin.add_child(nut)
		# sulcos dos pneus da era V10 (4 sulcos) / desenho do pneu do elétrico
		if variant == "v10" or variant == "eletrico":
			var grooves := [-0.3, -0.1, 0.1, 0.3] if variant == "v10" else [-0.22, 0.0, 0.22]
			for gx in grooves:
				var gr := MeshInstance3D.new()
				var gtm := TorusMesh.new()
				gtm.inner_radius = R - 0.006
				gtm.outer_radius = R + 0.0015
				gtm.rings = 48
				gtm.ring_segments = 4
				gtm.material = mat("dark")
				gr.mesh = gtm
				gr.rotation.z = PI * 0.5
				gr.scale = Vector3(1.0, 0.12, 1.0)
				gr.position.x = gx * W
				spin.add_child(gr)
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


func _build_cockpit(team: Dictionary, player: bool, driver: Dictionary = {}) -> void:
	var hc: Array = driver.get("helmet", [(team["secondary"] as Color).lerp(Color.WHITE, 0.3), team["primary"], team["accent"]])
	_build_helmet(hc, player, driver)
	# volante: placa de carbono com manoplas de camurça, botões coloridos com aro cromado,
	# seletores rotativos, tela, LEDs e borboletas. Coordenadas locais: x direita, y cima, z para o piloto.
	_steer_node = Node3D.new()
	_steer_node.position = G(0.43, 0.755, 0.0)
	_steer_node.rotation.x = -0.38
	add_child(_steer_node)
	var classic := variant == "v10" or variant == "lenda"
	var wb := Acc.new()        # corpo (carbono)
	var wr := Acc.new()        # camurça das manoplas
	var wal := Acc.new()       # alumínio (seletores, aros dos botões)
	# corpo: superelipse (no clássico, mais "borboleta": topo reto e alças mais altas)
	var outline := []
	var wide := 0.112 if not classic else 0.104
	for j in 48:
		var an := float(j) / 48.0 * TAU
		var cx := cos(an)
		var sy := sin(an)
		var ex := signf(cx) * pow(absf(cx), 2.0 / 4.8)
		var ey := signf(sy) * pow(absf(sy), 2.0 / 4.8)
		var hy := (0.058 if sy > 0.0 else 0.068) if not classic else (0.05 if sy > 0.0 else 0.06)
		outline.append([ex * wide, ey * hy])
	prism(wb, outline, Vector3(0, 0, 0), Vector3.RIGHT, Vector3.UP, Vector3.BACK, 0.03)
	# moldura (aba de trás um pouco maior, dá espessura de peça usinada)
	var back := []
	for p in outline:
		back.append([p[0] * 1.04, p[1] * 1.05])
	prism(wb, back, Vector3(0, 0, -0.012), Vector3.RIGHT, Vector3.UP, Vector3.BACK, 0.008)
	# manoplas: grossas, levemente curvas, com apoio do polegar em cima
	for s in [-1.0, 1.0]:
		var gp := []
		for k in 9:
			var t := float(k) / 8.0
			gp.append(Vector3(s * (wide + 0.016 + 0.01 * sin(t * PI)), 0.058 - t * 0.135, 0.004))
		tube(wr, gp, 0.0245, 18)
		tube(wr, [Vector3(s * (wide - 0.004), 0.05, 0.012), Vector3(s * (wide + 0.012), 0.062, 0.01)], 0.013, 12)
		# borboletas de câmbio (atrás, alumínio)
		box(wal, Vector3(s * 0.08, 0.008, -0.034), Vector3(0.075, 0.05, 0.005))
	# botões redondos coloridos com aro de alumínio (duas colunas, como no vídeo)
	var btn_cols := [Color(0.1, 0.75, 0.25), Color(1.0, 0.78, 0.05), Color(0.9, 0.08, 0.08), Color(0.12, 0.45, 1.0), Color(0.95, 0.95, 0.95), Color(1.0, 0.45, 0.0)]
	var spots := [[-0.072, 0.032, 0], [-0.072, 0.004, 1], [-0.072, -0.024, 3], [0.072, 0.032, 2], [0.072, 0.004, 1], [0.072, -0.024, 0],
		[-0.042, -0.048, 4], [0.042, -0.048, 5]]
	if variant == "lenda":
		spots = [[-0.06, 0.0, 2], [0.06, 0.0, 0]]
	var btn_acc := []
	for c in btn_cols:
		btn_acc.append(Acc.new())
	for b in spots:
		cyl(wal, Vector3(b[0], b[1], 0.014), Vector3(b[0], b[1], 0.018), 0.0078, 16)
		cyl(btn_acc[int(b[2])], Vector3(b[0], b[1], 0.017), Vector3(b[0], b[1], 0.0215), 0.0058, 16)
	# seletores rotativos (alumínio recartilhado) no centro de baixo
	if variant != "lenda":
		for s in [-1.0, 1.0]:
			cyl(wal, Vector3(s * 0.018, -0.03, 0.014), Vector3(s * 0.018, -0.03, 0.028), 0.0105, 18)
			box(btn_acc[4], Vector3(s * 0.018, -0.022, 0.0285), Vector3(0.0018, 0.008, 0.001))
	# coluna de direção até o painel
	cyl(wb, Vector3(0, 0, -0.016), Vector3(0, -0.02, -0.25), 0.018, 12)
	var wmesh := ArrayMesh.new()
	var surfs := [[wb, mat("carbon")], [wr, _tex_mat("suede", Color(0.13, 0.13, 0.14), 0.95, 60.0, 0.6)], [wal, mat("alu")]]
	for k in btn_cols.size():
		var bm := StandardMaterial3D.new()
		bm.albedo_color = btn_cols[k]
		bm.roughness = 0.3
		bm.clearcoat_enabled = true
		bm.emission_enabled = true
		bm.emission = (btn_cols[k] as Color) * 0.15
		surfs.append([btn_acc[k], bm])
	for sf in surfs:
		var acc: Acc = sf[0]
		if acc.v.is_empty():
			continue
		wmesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, acc.to_arrays())
		wmesh.surface_set_material(wmesh.get_surface_count() - 1, sf[1])
	var wmi := MeshInstance3D.new()
	wmi.mesh = wmesh
	_steer_node.add_child(wmi)
	# tela: colorida no 2026/elétrico; LCD verde estreito no clássico; nenhuma no Lenda
	var screen := MeshInstance3D.new()
	var scm := QuadMesh.new()
	scm.size = Vector2(0.085, 0.048) if not classic else Vector2(0.06, 0.02)
	var scmat := StandardMaterial3D.new()
	scmat.albedo_color = Color(0.01, 0.02, 0.03)
	scmat.emission_enabled = true
	scmat.emission = Color(0.02, 0.07, 0.12) if not classic else Color(0.05, 0.18, 0.06)
	scmat.roughness = 0.1
	scm.material = scmat
	screen.mesh = scm
	screen.position = Vector3(0, 0.012, 0.0165) if not classic else Vector3(0, 0.03, 0.0165)
	screen.visible = variant != "lenda"
	_steer_node.add_child(screen)
	_gear_label = Label3D.new()
	_gear_label.text = "N"
	_gear_label.font_size = 64 if not classic else 40
	_gear_label.pixel_size = 0.00042
	_gear_label.outline_size = 0
	_gear_label.modulate = Color(1, 1, 1) if not classic else Color(0.5, 1.0, 0.55)
	_gear_label.position = screen.position + Vector3(0, 0, 0.001)
	_gear_label.visible = variant != "lenda"
	_steer_node.add_child(_gear_label)
	# luzes de troca (15 LEDs) no topo, viradas para o piloto
	for k in 15:
		var led := MeshInstance3D.new()
		var lm := BoxMesh.new()
		lm.size = Vector3(0.0075, 0.0075, 0.004)
		var lmat := StandardMaterial3D.new()
		lmat.emission_enabled = true
		lmat.albedo_color = Color(0.05, 0.05, 0.05)
		lmat.emission = Color(0.1, 1.0, 0.2) if k < 5 else (Color(1.0, 0.1, 0.1) if k < 10 else Color(0.3, 0.3, 1.0))
		lmat.emission_energy_multiplier = 0.0
		lm.material = lmat
		led.mesh = lm
		led.position = Vector3(-0.0665 + k * 0.0095, 0.046 if not classic else 0.044, 0.0165)
		_steer_node.add_child(led)
		_led_mats.append(lmat)
	if player:
		_build_hands(team)


## Material com textura real (CC0) aplicada por projeção triplanar no espaço do objeto.
## key: glove / suede / suit  (assets/textures/<key>_detail.jpg e _normal.jpg)
static func _tex_mat(key: String, col: Color, rough: float, scale: float, nd: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.albedo_texture = load("res://assets/textures/%s_detail.jpg" % key)
	m.normal_enabled = true
	m.normal_texture = load("res://assets/textures/%s_normal.jpg" % key)
	m.normal_scale = nd
	m.uv1_triplanar = true
	m.uv1_triplanar_sharpness = 2.0
	m.uv1_scale = Vector3(scale, scale, scale)
	m.roughness = rough
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m


## Capacete: casco liso em seções (pintura gráfica por shader com contorno e verniz), viseira escura,
## borracha da viseira, spoiler, entrada de ar e HANS. helmet = [cor base, grafismo, contorno].
func _build_helmet(colors: Array, player: bool, driver: Dictionary = {}) -> void:
	var c1: Color = colors[0]
	var c2: Color = colors[1] if colors.size() > 1 else c1.darkened(0.3)
	var c3: Color = colors[2] if colors.size() > 2 else Color.WHITE
	var shell := Acc.new()
	var visor := Acc.new()
	var dark := Acc.new()
	loft(shell, [
		{"f": -0.05, "y": 0.818, "w": 0.05, "ht": 0.05, "hb": 0.05, "n": 2.2},
		{"f": -0.03, "y": 0.818, "w": 0.098, "ht": 0.104, "hb": 0.096, "n": 2.2},
		{"f": 0.02, "y": 0.818, "w": 0.122, "ht": 0.132, "hb": 0.118, "n": 2.2},
		{"f": 0.10, "y": 0.818, "w": 0.128, "ht": 0.14, "hb": 0.124, "n": 2.2},
		{"f": 0.17, "y": 0.812, "w": 0.121, "ht": 0.124, "hb": 0.124, "n": 2.3},
		{"f": 0.222, "y": 0.80, "w": 0.098, "ht": 0.094, "hb": 0.116, "n": 2.4},
		{"f": 0.248, "y": 0.79, "w": 0.055, "ht": 0.05, "hb": 0.07, "n": 2.4},
	], 56, 10)
	# viseira escura e a borracha em volta
	_helmet_ring(visor, 0.808, 0.858, 1.018, -68.0, 68.0)
	_helmet_ring(dark, 0.80, 0.866, 1.012, -74.0, 74.0)
	# spoiler traseiro (aerofólio) e entrada de ar no topo
	box(dark, G(-0.035, 0.935, 0.0), Vector3(0.16, 0.012, 0.05), Basis(Vector3.RIGHT, 0.25))
	box(dark, G(0.16, 0.95, 0.0), Vector3(0.05, 0.015, 0.03))
	# HANS (carbono, apoiado nos ombros atrás da cabeça)
	var hans := Acc.new()
	box(hans, G(-0.085, 0.705, 0.0), Vector3(0.2, 0.05, 0.07), Basis(Vector3.RIGHT, -0.4))
	for s in [-1.0, 1.0]:
		box(hans, G(-0.01, 0.68, s * 0.11), Vector3(0.06, 0.03, 0.16), Basis(Vector3.UP, s * 0.2))
	var paint := ShaderMaterial.new()
	paint.shader = load("res://shaders/helmet.gdshader")
	paint.set_shader_parameter("c1", c1)
	paint.set_shader_parameter("c2", c2)
	paint.set_shader_parameter("c3", c3)
	var design := 0
	var code := String(driver.get("code", ""))
	if driver.has("helmet") and code == "LEN":
		design = 1
	elif code != "":
		# setas (como no vídeo de referência) são as mais comuns; depois faixa central e diagonais
		design = [0, 0, 0, 2, 2, 3, 3][(code.unicode_at(0) * 7 + code.unicode_at(code.length() - 1)) % 7]
	paint.set_shader_parameter("design", float(design))
	var dark_m := StandardMaterial3D.new()
	dark_m.albedo_color = Color(0.03, 0.03, 0.035)
	dark_m.roughness = 0.55
	var visor_m := StandardMaterial3D.new()
	visor_m.albedo_color = Color(0.02, 0.025, 0.03)
	visor_m.metallic = 0.9
	visor_m.roughness = 0.04
	visor_m.cull_mode = BaseMaterial3D.CULL_DISABLED
	var m := ArrayMesh.new()
	for sf in [[shell, paint], [dark, dark_m], [visor, visor_m], [hans, mat("carbon")]]:
		var acc: Acc = sf[0]
		if acc.v.is_empty():
			continue
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, acc.to_arrays())
		m.surface_set_material(m.get_surface_count() - 1, sf[1])
	var helmet := MeshInstance3D.new()
	helmet.mesh = m
	add_child(helmet)
	if player:
		helmet.layers = HIDE_LAYER


## Faixa (anel parcial) colada ao casco entre as alturas y0..y1, de a0 a a1 graus (0 = frente).
func _helmet_ring(acc: Acc, y0: float, y1: float, grow: float, a0: float, a1: float) -> void:
	var verts := PackedVector3Array()
	var tris := PackedInt32Array()
	var seg := 36
	var rows := 3
	for r in rows:
		var y := lerpf(y0, y1, float(r) / (rows - 1))
		var dy := y - 0.818
		var k := sqrt(maxf(1.0 - pow(dy / (0.14 if dy > 0.0 else 0.124), 2.0), 0.05))
		for j in seg + 1:
			var an := deg_to_rad(lerpf(a0, a1, float(j) / seg))
			var front := cos(an) > 0.0
			var rf := (0.138 if front else 0.15) * k * grow
			var rx := 0.128 * k * grow
			verts.append(G(0.10 + cos(an) * rf, y, sin(an) * rx))
	for r in rows - 1:
		for j in seg:
			var p := r * (seg + 1) + j
			tris.append_array([p, p + seg + 1, p + 1, p + 1, p + seg + 1, p + seg + 2])
	acc.add(verts, tris, true)


# ---------------------------------------------------------------- mãos e braços do piloto
## Luvas de couro claro acolchoadas, fechadas em volta das manoplas: dedos grossos encostados
## (punho fechado), dorso arredondado com costura, polegar por cima, palma de camurça e punho
## longo com tira de velcro na cor da equipe. Braços com tecido do macacão e cinemática inversa.
func _build_hands(team: Dictionary) -> void:
	var glove := _tex_mat("glove", Color(0.92, 0.92, 0.93).lerp(team["primary"], 0.08), 0.62, 34.0, 1.0)
	var palm := _tex_mat("suede", Color(0.36, 0.36, 0.37), 0.95, 40.0, 0.8)
	var strap := _tex_mat("suit", (team["accent"] as Color).lerp(team["primary"], 0.5), 0.7, 30.0, 0.6)
	var suit := _tex_mat("suit", (team["primary"] as Color).darkened(0.25), 0.9, 22.0, 0.8)
	var classic := variant == "v10" or variant == "lenda"
	var wide := 0.112 if not classic else 0.104
	_wrist_local.clear()
	for s in [-1.0, 1.0]:
		# centro da manopla (meio da altura dela)
		var C := Vector3(s * (wide + 0.022), -0.006, 0.004)
		var gl := Acc.new()
		var pa := Acc.new()
		var st := Acc.new()
		# dedos: quatro anéis grossos encostados envolvendo a manopla pela frente
		var R := 0.037
		for fi in 4:
			var fy: float = [0.033, 0.011, -0.011, -0.032][fi]
			var reach: float = [290.0, 298.0, 296.0, 282.0][fi]
			var fr: float = [0.0118, 0.0124, 0.0121, 0.0108][fi]
			var pts := []
			var steps := 12
			for k in steps + 1:
				var phi := deg_to_rad(lerpf(70.0, reach, float(k) / steps))
				var rr := R - (0.005 if k == steps else 0.0)
				pts.append(C + Vector3(s * sin(phi) * rr, fy, cos(phi) * rr))
			tube(gl, pts, fr, 12)
		# dorso da mão: volume arredondado do pulso até os nós dos dedos (por fora da manopla)
		var W := C + Vector3(s * 0.022, -0.018, 0.084)
		var K := C + Vector3(s * 0.034, 0.0, 0.022)
		tube(gl, [W, W.lerp(K, 0.35) + Vector3(s * 0.008, 0.002, 0.0), W.lerp(K, 0.75) + Vector3(s * 0.009, 0.001, 0.0), K], 0.043, 18, Vector2(0.52, 1.05))
		# costura/acolchoado sobre os nós dos dedos
		tube(st, [K + Vector3(s * 0.022, 0.034, -0.004), K + Vector3(s * 0.026, 0.0, -0.002), K + Vector3(s * 0.022, -0.034, -0.004)], 0.006, 8)
		# palma (lado de dentro, camurça)
		tube(pa, [W + Vector3(-s * 0.014, 0.0, -0.004), K + Vector3(-s * 0.03, 0.0, -0.012)], 0.032, 14, Vector2(0.32, 1.0))
		# polegar por cima da manopla, apontando para a frente
		tube(gl, [C + Vector3(s * 0.032, 0.03, 0.046), C + Vector3(s * 0.016, 0.06, 0.024), C + Vector3(-s * 0.008, 0.062, 0.0), C + Vector3(-s * 0.018, 0.054, -0.016)], 0.0128, 12)
		# punho longo da luva (gauntlet) e tira de velcro
		cyl(gl, W, W + Vector3(-s * 0.006, -0.014, 0.055), 0.036, 20)
		cyl(st, W + Vector3(-s * 0.002, -0.005, 0.02), W + Vector3(-s * 0.003, -0.007, 0.032), 0.0375, 20)
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, gl.to_arrays())
		m.surface_set_material(0, glove)
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, pa.to_arrays())
		m.surface_set_material(1, palm)
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, st.to_arrays())
		m.surface_set_material(2, strap)
		var hi := MeshInstance3D.new()
		hi.mesh = m
		_steer_node.add_child(hi)
		_wrist_local.append(W + Vector3(-s * 0.006, -0.014, 0.055))
	# braços (fora do volante, no espaço do modelo): macacão com textura de tecido
	_arms.clear()
	for s in [-1.0, 1.0]:
		var parts := []
		for spec in [[0.05, 0.044], [0.045, 0.037], [0.047, 0.047]]:
			var mi := MeshInstance3D.new()
			if spec[0] == spec[1]:
				var sp := SphereMesh.new()
				sp.radius = spec[0]
				sp.height = spec[0] * 2.0
				sp.radial_segments = 20
				sp.rings = 10
				sp.material = suit
				mi.mesh = sp
			else:
				var cm := CylinderMesh.new()
				cm.bottom_radius = spec[0]
				cm.top_radius = spec[1]
				cm.height = 1.0
				cm.radial_segments = 20
				cm.rings = 1
				cm.material = suit
				mi.mesh = cm
			add_child(mi)
			parts.append(mi)
		_arms.append(parts)
	_update_arms()


static func _orient_limb(mi: Node3D, p0: Vector3, p1: Vector3) -> void:
	var d := p1 - p0
	var L := maxf(d.length(), 0.001)
	var y := d / L
	var ref := Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
	var x := y.cross(ref).normalized()
	var z := x.cross(y).normalized()
	mi.transform = Transform3D(Basis(x, y * L, z), (p0 + p1) * 0.5)


## Cinemática inversa: ombro fixo, pulso preso ao volante, cotovelo resolvido (braço 0,30 / antebraço 0,29 m).
## Os cotovelos ficam baixos e por dentro do cockpit: de cima só aparecem as luvas e o começo do antebraço.
func _update_arms() -> void:
	if _arms.is_empty():
		return
	for k in 2:
		var s := -1.0 if k == 0 else 1.0
		var S := G(-0.08, 0.6, s * 0.16)
		var Wr: Vector3 = _steer_node.transform * (_wrist_local[k] as Vector3)
		var a := 0.30
		var b := 0.29
		var dv := Wr - S
		var d := clampf(dv.length(), 0.05, a + b - 0.002)
		var dir := dv.normalized()
		var ca := clampf((a * a + d * d - b * b) / (2.0 * a * d), -1.0, 1.0)
		var sa := sqrt(1.0 - ca * ca)
		var pole := Vector3(s * 0.25, -1.0, 0.1)
		var perp := (pole - dir * pole.dot(dir)).normalized()
		var E := S + dir * (a * ca) + perp * (a * sa)
		E.x = s * minf(absf(E.x), 0.135)
		E.y = minf(E.y, 0.6)
		var parts: Array = _arms[k]
		_orient_limb(parts[0], S, E)
		_orient_limb(parts[1], E, Wr)
		(parts[2] as Node3D).position = E


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
		# 2026: na barbatana; demais: na lateral da tampa do motor
		l.position = G(-0.75, 0.86, s * 0.012) if variant == "2026" else G(-0.72, 0.8, s * 0.2)
		l.rotation.y = PI * 0.5 * s
		add_child(l)
	var nose := Label3D.new()
	nose.text = str(number)
	nose.font_size = 96
	nose.pixel_size = 0.0016
	nose.outline_size = 10
	nose.outline_modulate = team["accent"]
	nose.position = G(2.0, 0.53 + {"v10": 0.18, "lenda": -0.04, "eletrico": -0.03}.get(variant, 0.0), 0.0)
	nose.rotation = Vector3(-PI * 0.5 + 0.12, 0.0, 0.0)
	add_child(nose)
	_build_sponsors(team)
	_build_decals()


## Patrocinadores fictícios: principal no sidepod e na asa traseira, secundários no bico,
## na tampa do motor e nas placas da asa dianteira. Escolhidos pelo nome da equipe (sempre iguais).
const SPONSORS := ["NEXA", "VOLTEX", "ORBITAL", "KAIROS", "PRISMA", "TERRA OIL", "MERIDIAN", "SOLARA", "QUANTA", "AXION", "LUMEN", "BRAVO TEL", "ZENTRA", "HALCYON", "RUBIX", "NORTHWIND", "TAURO", "PETRA", "CORVA", "AURUM", "VISTA", "ATLAS"]


func _sponsor_label(text: String, size: int, col: Color, pos: Vector3, rot: Vector3, outline := Color(0, 0, 0, 0)) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = 0.001
	l.outline_size = 6 if outline.a > 0.0 else 0
	l.outline_modulate = outline
	l.modulate = col
	l.shaded = true
	l.double_sided = false
	l.alpha_cut = Label3D.ALPHA_CUT_OPAQUE_PREPASS
	l.position = pos
	l.rotation = rot
	add_child(l)


func _build_sponsors(team: Dictionary) -> void:
	var h := absi(hash(String(team["name"])))
	var title: String = team.get("title", SPONSORS[h % SPONSORS.size()])
	var second: String = SPONSORS[(h / 7 + 3) % SPONSORS.size()]
	var third: String = SPONSORS[(h / 13 + 7) % SPONSORS.size()]
	if second == title:
		second = SPONSORS[(h + 1) % SPONSORS.size()]
	var prim: Color = team["primary"]
	var on_prim := Color.WHITE if prim.get_luminance() < 0.55 else Color(0.05, 0.05, 0.07)
	var acc: Color = team["accent"]
	var rdy: float = {"2026": 0.0, "v10": 0.07, "lenda": 0.2, "eletrico": -0.17}.get(variant, 0.0)
	for s in [-1.0, 1.0]:
		# sidepod (patrocinador principal)
		_sponsor_label(title, 125, on_prim, G(-0.05, 0.47, s * 0.605), Vector3(0, PI * 0.5 * s, -0.02 * s), acc)
		# placa da asa traseira (face externa)
		_sponsor_label(title, 110, Color.WHITE, G(-2.33, 0.86 + rdy, s * 0.512), Vector3(0, PI * 0.5 * s, 0))
		# tampa do motor
		_sponsor_label(second, 70, on_prim, G(-1.2, 0.66, s * 0.185), Vector3(0, PI * 0.5 * s, 0.12 * s))
		# placa da asa dianteira
		_sponsor_label(third, 70, Color.WHITE, G(2.7, 0.15, s * 0.93), Vector3(0, PI * 0.5 * s, 0))
	# plano principal da asa traseira (visto de trás/cima)
	_sponsor_label(title, 170, on_prim, G(-2.2, 0.965 + rdy, 0.0), Vector3(-PI * 0.5 + 0.35, 0, 0))
	_sponsor_label(title, 170, on_prim, G(-2.42, 0.93 + rdy, 0.0), Vector3(0.2, PI, 0))
	# bico (atrás do número)
	_sponsor_label(second, 90, on_prim, G(1.55, 0.6 + {"v10": 0.12, "lenda": -0.03}.get(variant, 0.0), 0.0), Vector3(-PI * 0.5 + 0.18, 0, 0))


## Adesivos e detalhes projetados na carroceria (decalques): placa de inspeção, seta de resgate,
## aviso de alta tensão, tira técnica, quadriculado na tampa do motor, fornecedor de pneus no bico e
## parafusos nas placas das asas. Somem com a distância (custo baixo com 20 carros).
static var _decal_tex := {}


func _decal(tex: String, pos: Vector3, size: Vector3, basis: Basis) -> void:
	if not _decal_tex.has(tex):
		_decal_tex[tex] = load("res://assets/decals/%s.png" % tex)
	var d := Decal.new()
	d.texture_albedo = _decal_tex[tex]
	d.size = size
	d.transform = Transform3D(basis, pos)
	d.normal_fade = 0.4
	d.upper_fade = 0.05
	d.lower_fade = 0.05
	d.distance_fade_enabled = true
	d.distance_fade_begin = 30.0
	d.distance_fade_length = 15.0
	add_child(d)


func _build_decals() -> void:
	if OS.get_cmdline_user_args().has("nodecals"):
		return
	var rdy: float = {"2026": 0.0, "v10": 0.07, "lenda": 0.2, "eletrico": -0.17}.get(variant, 0.0)
	var nose_dy: float = {"v10": 0.12, "lenda": -0.03}.get(variant, 0.0)
	for s in [-1.0, 1.0]:
		# projeção lateral: X da textura ao longo do carro (legível de fora), Y para fora, Z para baixo
		var side := Basis(Vector3(0, 0, -s), Vector3(s, 0, 0), Vector3(0, -1, 0))
		_decal("plate", G(0.38, 0.47, s * 0.62), Vector3(0.15, 0.45, 0.075), side)
		_decal("rescue", G(0.02, 0.66, s * 0.3), Vector3(0.1, 0.3, 0.1), side)
		_decal("warning", G(-0.8, 0.58, s * 0.3), Vector3(0.08, 0.35, 0.08), side)
		_decal("techstrip", G(-0.55, 0.37, s * 0.62), Vector3(0.4, 0.4, 0.05), side)
		_decal("veltra", G(1.95, 0.5 + nose_dy, s * 0.15), Vector3(0.16, 0.25, 0.04), side)
		_decal("bolts", G(2.78, 0.12, s * 0.95), Vector3(0.14, 0.12, 0.035), side)
		_decal("bolts", G(-2.3, 0.62 + rdy, s * 0.52), Vector3(0.14, 0.12, 0.035), side)
	# tira quadriculada ao longo do topo da tampa do motor (projeção de cima)
	var top := Basis(Vector3(0, 0, -1), Vector3(0, 1, 0), Vector3(1, 0, 0))
	_decal("checker", G(-1.55, 0.75, 0.0), Vector3(0.5, 0.5, 0.05), top)


# ======================================================================= atualização
func set_wheel(i: int, comp: float, spin: float, steer: float) -> void:
	var root: Node3D = wheel_root[i]
	var R := 0.36 if i < 2 else 0.365
	root.position.y = R + comp
	(wheel_steer[i] as Node3D).rotation.y = -steer
	(wheel_spin[i] as Node3D).rotation.x = spin


func set_steering(v: float) -> void:
	if _steer_node:
		_steer_node.rotation.z = -v * 1.4
		_update_arms()


func set_aero(open: bool) -> void:
	var target := 1.0 if open else 0.0
	if _aero_t == target:
		return
	_aero_t = move_toward(_aero_t, target, 0.08)
	if _flap_r:
		_flap_r.rotation.x = -_aero_t * 0.45
	for f in _flap_f:
		(f as Node3D).rotation.x = -_aero_t * 0.3


## Dano na asa dianteira: flaps entortam (>0,25) e se soltam (>0,6).
func set_damage(d: float) -> void:
	_damage = d
	for i in _flap_f.size():
		var f: Node3D = _flap_f[i]
		if not f.has_meta("base"):
			f.set_meta("base", f.position)
		var base: Vector3 = f.get_meta("base")
		f.visible = d < 0.6 or (i == 0 and d < 0.85)
		if d > 0.25:
			f.rotation.z = (0.35 if i == 0 else -0.35) * clampf(d, 0.0, 1.0)
			f.position = base + Vector3(0, -0.04 * d, 0)
		else:
			f.rotation.z = 0.0
			f.position = base


func set_compound(c: Color) -> void:
	_compound_col = c
	for t in _tyres:
		(t as GeometryInstance3D).set_instance_shader_parameter("band", c)


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
