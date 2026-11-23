"""Converte um modelo .usdz/.usdc (USD) em .glb para a Godot importar (Patch 7.1).

A Godot não lê USD; o Blender não é necessário: usa a biblioteca oficial da Pixar (pip install usd-core).
Cada malha vira um nó com o nome do objeto pai no USD (ex.: "front_wheels_7"), para o jogo poder esconder
peças pelo nome. Posições em metros (metersPerUnit do arquivo), já com as transformações aplicadas.
Materiais: nome original + textura de cor e de relevo (normal) quando existirem.

Uso:  PYTHONPATH=<pasta com usd-core e numpy> python tools/usd_to_glb.py <entrada.usdc> <saida.glb> <pasta_texturas_relativa>
      (as texturas ficam ao lado do .glb, na pasta indicada; o .glb aponta para elas)
"""
import json, os, struct, sys
import numpy as np
from pxr import Usd, UsdGeom, UsdShade, Sdf

src, dst, texdir = sys.argv[1], sys.argv[2], sys.argv[3]
stage = Usd.Stage.Open(src)
mpu = UsdGeom.GetStageMetersPerUnit(stage) or 1.0
cache = UsdGeom.XformCache()

def tex_of(material, inp_name):
    """Arquivo de textura ligado a uma entrada do UsdPreviewSurface (diffuseColor, normal...)."""
    if not material:
        return None
    for shader_out in [material.GetSurfaceOutput()]:
        src_info = shader_out.GetConnectedSource()
        if not src_info:
            continue
        surf = UsdShade.Shader(src_info[0])
        inp = surf.GetInput(inp_name)
        if not inp:
            return None
        c = inp.GetConnectedSource()
        if not c:
            return None
        tex = UsdShade.Shader(c[0])
        f = tex.GetInput("file")
        if f and f.Get():
            return f.Get().resolvedPath or f.Get().path
    return None

meshes = []
for prim in stage.Traverse():
    if not prim.IsA(UsdGeom.Mesh):
        continue
    m = UsdGeom.Mesh(prim)
    pts = np.array(m.GetPointsAttr().Get(), dtype=np.float64)
    counts = np.array(m.GetFaceVertexCountsAttr().Get())
    idx = np.array(m.GetFaceVertexIndicesAttr().Get())
    xf = np.array(cache.GetLocalToWorldTransform(prim), dtype=np.float64)   # linha-vetor (USD)
    P = (np.c_[pts, np.ones(len(pts))] @ xf)[:, :3] * mpu
    # normais e UV (vertex ou faceVarying)
    nrm = m.GetNormalsAttr().Get()
    ninterp = m.GetNormalsInterpolation()
    pv = UsdGeom.PrimvarsAPI(prim)
    st = pv.GetPrimvar("st") or pv.GetPrimvar("st0") or pv.GetPrimvar("UVMap")
    uv = None
    uvi = None
    uinterp = None
    if st:
        uv = np.array(st.Get(), dtype=np.float64)
        uinterp = st.GetInterpolation()
        if st.IsIndexed():
            uvi = np.array(st.GetIndices())
    # triangula em leque, por "face-vértice"
    starts = np.concatenate([[0], np.cumsum(counts)[:-1]])
    fv = []
    for s0, c in zip(starts, counts):
        for k in range(1, c - 1):
            fv.extend([s0, s0 + k, s0 + k + 1])
    fv = np.array(fv)
    pos = P[idx[fv]]
    rot = xf[:3, :3]
    if nrm is not None and len(nrm):
        N = np.array(nrm, dtype=np.float64)
        N = N[fv] if ninterp == "faceVarying" else N[idx[fv]]
        N = N @ rot
        N /= np.linalg.norm(N, axis=1, keepdims=True) + 1e-12
    else:
        a, b, c = pos[0::3], pos[1::3], pos[2::3]
        fn = np.cross(b - a, c - a)
        fn /= np.linalg.norm(fn, axis=1, keepdims=True) + 1e-12
        N = np.repeat(fn, 3, axis=0)
    if uv is not None:
        ui = fv if uinterp == "faceVarying" else idx[fv]
        if uvi is not None:
            ui = uvi[ui]
        T = uv[ui].copy()
        T[:, 1] = 1.0 - T[:, 1]
    else:
        T = np.zeros((len(pos), 2))
    # junta vértices iguais (arquivo menor)
    key = np.round(np.c_[pos * 1e4, N * 1e3, T * 1e5]).astype(np.int64)
    uk, inv = np.unique(key, axis=0, return_inverse=True)
    inv = inv.reshape(-1)
    first = np.zeros(len(uk), dtype=np.int64)
    first[inv[::-1]] = np.arange(len(inv))[::-1]
    mat = UsdShade.MaterialBindingAPI(prim).ComputeBoundMaterial()[0]
    name = prim.GetParent().GetName() + "_" + prim.GetName()
    for anc in prim.GetPath().GetPrefixes()[::-1]:
        nm = anc.name
        if not nm.startswith("Object_") and nm not in ("root", "GLTF_SceneRootNode", "Sketchfab_model", "Meshes", "scene"):
            name = nm + "_" + prim.GetName()
            break
    meshes.append({
        "name": name,
        "pos": pos[first].astype(np.float32), "nrm": N[first].astype(np.float32), "uv": T[first].astype(np.float32),
        "idx": inv.astype(np.uint32),
        "mat": mat.GetPath().name if mat else "default",
        "base": tex_of(mat, "diffuseColor"), "normal": tex_of(mat, "normal"),
    })
    print("%-40s %7d tris  %s" % (name, len(fv) // 3, meshes[-1]["mat"]))

# ---- escreve o glTF binário
bin_parts = []
offset = 0
bviews, accs = [], []
def add(arr, target, comp, typ, minmax=False):
    global offset
    data = arr.tobytes()
    pad = (-len(data)) % 4
    bviews.append({"buffer": 0, "byteOffset": offset, "byteLength": len(data), "target": target})
    bin_parts.append(data + b"\0" * pad)
    offset += len(data) + pad
    a = {"bufferView": len(bviews) - 1, "componentType": comp, "count": int(arr.shape[0]), "type": typ}
    if minmax:
        a["min"] = arr.min(axis=0).tolist()
        a["max"] = arr.max(axis=0).tolist()
    accs.append(a)
    return len(accs) - 1

images, textures, materials, matindex = [], [], [], {}
def tex_index(path):
    if not path:
        return None
    fn = os.path.basename(path)
    for i, im in enumerate(images):
        if im["uri"].endswith(fn):
            return i
    images.append({"uri": texdir.rstrip("/") + "/" + fn})
    textures.append({"source": len(images) - 1})
    return len(textures) - 1

gl_meshes, nodes = [], []
for m in meshes:
    if m["mat"] not in matindex:
        mat = {"name": m["mat"], "pbrMetallicRoughness": {"metallicFactor": 0.0, "roughnessFactor": 0.6}}
        ti = tex_index(m["base"])
        if ti is not None:
            mat["pbrMetallicRoughness"]["baseColorTexture"] = {"index": ti}
        ni = tex_index(m["normal"])
        if ni is not None:
            mat["normalTexture"] = {"index": ni}
        materials.append(mat)
        matindex[m["mat"]] = len(materials) - 1
    ap = add(m["pos"], 34962, 5126, "VEC3", True)
    an = add(m["nrm"], 34962, 5126, "VEC3")
    at = add(m["uv"], 34962, 5126, "VEC2")
    ai = add(m["idx"], 34963, 5125, "SCALAR")
    gl_meshes.append({"name": m["name"], "primitives": [{"attributes": {"POSITION": ap, "NORMAL": an, "TEXCOORD_0": at}, "indices": ai, "material": matindex[m["mat"]]}]})
    nodes.append({"name": m["name"], "mesh": len(gl_meshes) - 1})

gltf = {"asset": {"version": "2.0", "generator": "Apex GP usd_to_glb.py"},
        "scene": 0, "scenes": [{"nodes": list(range(len(nodes)))}], "nodes": nodes, "meshes": gl_meshes,
        "materials": materials, "images": images, "textures": textures,
        "buffers": [{"byteLength": offset}], "bufferViews": bviews, "accessors": accs}
js = json.dumps(gltf).encode()
js += b" " * ((-len(js)) % 4)
binb = b"".join(bin_parts)
with open(dst, "wb") as fh:
    fh.write(struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(binb)))
    fh.write(struct.pack("<II", len(js), 0x4E4F534A) + js)
    fh.write(struct.pack("<II", len(binb), 0x004E4942) + binb)
print("ok:", dst, "%.1f MB" % (os.path.getsize(dst) / 1e6), "malhas", len(nodes), "materiais", [m["name"] for m in materials])
