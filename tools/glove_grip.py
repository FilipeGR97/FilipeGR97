"""Gera a luva "segurando o volante" a partir da luva de corrida CC-BY (layne.harris, Sketchfab) — Patch 7.1.

A luva original é uma mão aberta e reta, sem esqueleto. Aqui os dedos são dobrados em volta de um cilindro
(a manopla do volante): cada ponto depois da linha dos nós vira um arco de raio R em volta do eixo da manopla,
e o polegar gira por cima dela. Saída: .glb em metros, eixos já no espaço do volante do jogo:
  +Y = eixo da manopla (para cima), -Z = para a frente, +X = lado de fora (dorso da mão), origem = centro da manopla.
Mão direita; a esquerda é o espelho em X (feito no jogo).

Uso: PYTHONPATH=<numpy> python tools/glove_grip.py <kmz.dae> <saida.glb> <textura_relativa>
"""
import json, re, struct, sys
import numpy as np

src, dst, tex_rel = sys.argv[1], sys.argv[2], sys.argv[3]
S = 0.0083                      # metros por unidade do modelo (mão + punho ~ 24 cm)
GRIP_R = 0.0245 / S             # raio da manopla em unidades do modelo
Y_K = -3.0                      # linha dos nós dos dedos
X0 = 0.0                        # linha neutra dos dedos (meio da espessura)
R_B = GRIP_R + 1.25             # raio de dobra (manopla + meia espessura do dedo)
Z_MID = -4.0                    # meio da linha dos nós (fica na altura do centro da manopla)

d = open(src, encoding="utf-8", errors="ignore").read()
arrs = {m[0]: np.array(m[2].split(), dtype=float) for m in re.findall(r'<float_array[^>]*id="([^"]*)"[^>]*count="(\d+)"[^>]*>([^<]*)</float_array>', d)}
pos = arrs["objMesh1-positions-array"].reshape(-1, 3)
uvs = arrs["objMesh1-texcoords-array"].reshape(-1, 2)
tri = re.search(r'<triangles[^>]*>(.*?)</triangles>', d, re.S).group(1)
inputs = re.findall(r'<input[^>]*semantic="(\w+)"[^>]*offset="(\d+)"', tri)
stride = max(int(o) for _, o in inputs) + 1
p = np.array(re.search(r"<p>(.*?)</p>", tri, re.S).group(1).split(), dtype=np.int64).reshape(-1, stride)
vo = [int(o) for s_, o in inputs if s_ == "VERTEX"][0]
to = [int(o) for s_, o in inputs if s_ == "TEXCOORD"][0]
vi, ti = p[:, vo], p[:, to]

P = pos.copy()
# ---- punho mais curto: o cano original (~16 cm) parecia um pano solto de dentro do cockpit
cuff = P[:, 1] < -12.0
P[cuff, 1] = -12.0 + (P[cuff, 1] + 12.0) * 0.4
# ---- dedos: dobra em arco em volta da manopla (do lado da palma, -X)
fingers = (P[:, 2] < 2.2) & (P[:, 1] > Y_K)
s = P[fingers, 1] - Y_K
th = np.minimum(s / R_B, 2.6)
r = R_B + (P[fingers, 0] - X0)          # ponto do lado de fora (+X) fica mais longe do eixo
ax_x = X0 - R_B
P[fingers, 1] = Y_K + r * np.sin(th) + np.maximum(s - th * R_B, 0) * np.cos(th)
P[fingers, 0] = ax_x + r * np.cos(th)
# ---- polegar: gira em volta da base, deitando sobre a manopla (para o lado da palma)
thumb = (P[:, 2] >= 2.2) & (P[:, 1] > -11.0)
base = np.array([0.0, -9.0, 2.6])
a = -0.75
c, sn = np.cos(a), np.sin(a)
q = P[thumb] - base
P[thumb] = base + np.c_[q[:, 0] * c - q[:, 2] * sn, q[:, 1], q[:, 0] * sn + q[:, 2] * c]

# ---- para o espaço do volante: Z_luva (linha dos nós) -> +Y; Y_luva (dedos) -> -Z; X_luva -> +X
G = np.c_[(P[:, 0] - ax_x), (P[:, 2] - Z_MID), -(P[:, 1] - Y_K)] * S
# triângulos sem índice compartilhado de UV: um vértice por canto, depois junta iguais
corner_p = G[vi]
corner_t = uvs[ti].copy()
corner_t[:, 1] = 1.0 - corner_t[:, 1]
a3, b3, c3 = corner_p[0::3], corner_p[1::3], corner_p[2::3]
fn = np.cross(b3 - a3, c3 - a3)
# normais suaves: acumula por vértice de posição
acc = np.zeros_like(G)
for k in range(3):
    np.add.at(acc, vi[k::3], fn)
nv = acc / (np.linalg.norm(acc, axis=1, keepdims=True) + 1e-12)
corner_n = nv[vi]
key = np.round(np.c_[corner_p * 1e5, corner_t * 1e5]).astype(np.int64)
uk, inv = np.unique(key, axis=0, return_inverse=True)
inv = inv.reshape(-1)
first = np.zeros(len(uk), dtype=np.int64)
first[inv[::-1]] = np.arange(len(inv))[::-1]
V, N, T, I = corner_p[first].astype(np.float32), corner_n[first].astype(np.float32), corner_t[first].astype(np.float32), inv.astype(np.uint32)

parts, views, accs, off = [], [], [], 0
def add(arr, target, comp, typ, mm=False):
    global off
    b = arr.tobytes(); pad = (-len(b)) % 4
    views.append({"buffer": 0, "byteOffset": off, "byteLength": len(b), "target": target})
    parts.append(b + b"\0" * pad); off += len(b) + pad
    a_ = {"bufferView": len(views) - 1, "componentType": comp, "count": int(arr.shape[0]), "type": typ}
    if mm:
        a_["min"] = arr.min(0).tolist(); a_["max"] = arr.max(0).tolist()
    accs.append(a_); return len(accs) - 1
ap, an, at, ai = add(V, 34962, 5126, "VEC3", True), add(N, 34962, 5126, "VEC3"), add(T, 34962, 5126, "VEC2"), add(I, 34963, 5125, "SCALAR")
gl = {"asset": {"version": "2.0", "generator": "Apex GP glove_grip.py"}, "scene": 0, "scenes": [{"nodes": [0]}],
      "nodes": [{"name": "glove", "mesh": 0}],
      "meshes": [{"name": "glove", "primitives": [{"attributes": {"POSITION": ap, "NORMAL": an, "TEXCOORD_0": at}, "indices": ai, "material": 0}]}],
      "materials": [{"name": "glove", "pbrMetallicRoughness": {"baseColorTexture": {"index": 0}, "metallicFactor": 0.0, "roughnessFactor": 0.7}, "doubleSided": True}],
      "images": [{"uri": tex_rel}], "textures": [{"source": 0}],
      "buffers": [{"byteLength": off}], "bufferViews": views, "accessors": accs}
js = json.dumps(gl).encode(); js += b" " * ((-len(js)) % 4)
bb = b"".join(parts)
with open(dst, "wb") as fh:
    fh.write(struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(bb)))
    fh.write(struct.pack("<II", len(js), 0x4E4F534A) + js)
    fh.write(struct.pack("<II", len(bb), 0x004E4942) + bb)
print("ok", dst, len(V), "vértices", len(I) // 3, "triângulos", "caixa", V.min(0), V.max(0))
