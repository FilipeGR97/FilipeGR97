#!/bin/bash
# Lista TODOS os avisos do GDScript (os amarelos do painel "Erros" do editor) de uma vez — Patch 7.2.
# Copia scripts/cenas para uma pasta temporária, liga "aviso = erro" num override.cfg SÓ nessa cópia
# (o projeto e o editor aberto não são tocados) e carrega cada .gd com os autoloads ativos.
# Uso: bash tools/check_warnings.sh [pasta_temporaria]     (saída vazia + "0 avisos" = tudo limpo)
set -e
PROJ="$(cd "$(dirname "$0")/.." && pwd)"
G="$PROJ/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe"
W="${1:-${TMPDIR:-/tmp}/apexgp_warnings}"
rm -rf "$W"; mkdir -p "$W/.godot"
cp -r "$PROJ/scripts" "$PROJ/scenes" "$PROJ/shaders" "$PROJ/tests" "$PROJ/data" "$PROJ/project.godot" "$W/"
cp "$PROJ/.godot/global_script_class_cache.cfg" "$W/.godot/" 2>/dev/null || true
{
  echo "[debug]"
  for n in unassigned_variable unassigned_variable_op_assign unused_variable unused_local_constant \
    unused_private_class_variable unused_parameter unused_signal shadowed_variable shadowed_variable_base_class \
    shadowed_global_identifier unreachable_code unreachable_pattern standalone_expression standalone_ternary \
    incompatible_ternary static_called_on_instance redundant_static_unload redundant_await assert_always_true \
    assert_always_false integer_division narrowing_conversion int_as_enum_without_cast int_as_enum_without_match \
    enum_variable_without_default empty_file deprecated_keyword confusable_identifier confusable_local_declaration \
    confusable_local_usage confusable_capture_reassignment inference_on_variant native_method_override \
    get_node_default_without_onready onready_with_export; do
    echo "gdscript/warnings/$n=2"
  done
} > "$W/override.cfg"
cat > "$W/chk_node.gd" <<'EOF'
extends Node
func _ready() -> void:
	var stack := ["res://scripts", "res://tests"]
	while stack.size():
		var d: String = stack.pop_back()
		for f in DirAccess.get_files_at(d):
			if f.ends_with(".gd"):
				load(d + "/" + f)
		for sd in DirAccess.get_directories_at(d):
			stack.append(d + "/" + sd)
	get_tree().quit()
EOF
printf '[gd_scene format=3]\n\n[ext_resource type="Script" path="res://chk_node.gd" id="1"]\n\n[node name="C" type="Node"]\nscript = ExtResource("1")\n' > "$W/chk.tscn"
"$G" --headless --path "$W" res://chk.tscn > "$W/out.txt" 2>&1 || true
grep -E "^SCRIPT ERROR|at: GDScript::reload" "$W/out.txt" | paste - - \
  | sed -E 's/SCRIPT ERROR: (Parse|Compile) Error: //; s/ \(Warning treated as error\.\)//; s/\s+at: GDScript::reload \(res:\/\/(.*)\)/ @\1/' \
  | awk -F' @' '{print $2" | "$1}' | sort -u -V
echo "$(grep -c '^SCRIPT ERROR' "$W/out.txt") avisos"
