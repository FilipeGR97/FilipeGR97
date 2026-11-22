extends SceneTree
## Ferramenta: lista as peças de um modelo 3D importado (malhas, materiais, caixas, triângulos).
## godot --headless -s res://tests/inspect_model.gd -- res://assets/cars_src/sf90/SF90.fbx

func _initialize() -> void:
	var path: String = OS.get_cmdline_user_args()[0]
	var ps: PackedScene = load(path)
	var root := ps.instantiate()
	var total := 0
	var gbox := AABB()
	var first := true
	var rows: Array = []
	for n in _all(root):
		if n is MeshInstance3D:
			var mi := n as MeshInstance3D
			var box: AABB = _xf(mi, root) * mi.get_aabb()
			if first:
				gbox = box
				first = false
			else:
				gbox = gbox.merge(box)
			var tris := 0
			var mats := []
			for s in mi.mesh.get_surface_count():
				var arr := mi.mesh.surface_get_arrays(s)
				var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
				tris += (idx.size() if idx.size() > 0 else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
				var m := mi.get_active_material(s)
				mats.append(m.resource_name if m else "-")
			total += tris
			rows.append([tris, String(root.get_path_to(mi)), box, mats])
	rows.sort_custom(func(a, b): return a[0] > b[0])
	print("MALHAS: %d  TRIANGULOS: %d" % [rows.size(), total])
	print("CAIXA TOTAL: pos %s tam %s" % [gbox.position, gbox.size])
	for r in rows:
		var b: AABB = r[2]
		print("%7d %-50s c=%s tam=%s %s" % [r[0], String(r[1]).right(50), b.get_center().snapped(Vector3.ONE * 0.01), b.size.snapped(Vector3.ONE * 0.01), str(r[3])])
	quit()


func _xf(n: Node, root: Node) -> Transform3D:
	var t := Transform3D()
	var c := n
	while c != null and c != root.get_parent():
		if c is Node3D:
			t = (c as Node3D).transform * t
		c = c.get_parent()
	return t


func _all(n: Node) -> Array:
	var out := [n]
	for c in n.get_children():
		out.append_array(_all(c))
	return out
