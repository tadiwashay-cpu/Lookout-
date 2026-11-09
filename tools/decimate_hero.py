"""Decimate a single-mesh character GLB for mobile, keeping UVs and textures.
Usage: python decimate_hero.py in.glb out.glb TARGET_TRIS
Needs: numpy, pillow, fast-simplification (pip install fast-simplification)."""
import io, json, struct, sys
import numpy as np
import fast_simplification
from PIL import Image

sys.path.insert(0, __file__.rsplit('/', 1)[0])
from glbrender import GLB

src, dst, target = sys.argv[1], sys.argv[2], int(sys.argv[3])
g = GLB(src); J = g.j
prim = J['meshes'][0]['primitives'][0]
P = g.acc(prim['attributes']['POSITION']).astype(np.float32)
UV = g.acc(prim['attributes']['TEXCOORD_0']).astype(np.float32)
N = g.acc(prim['attributes']['NORMAL']).astype(np.float32)
F = g.acc(prim['indices']).reshape(-1, 3).astype(np.int64)
print("in: verts", len(P), "tris", len(F))

reduction = 1.0 - target / len(F)
_, _, collapses = fast_simplification.simplify(P, F, target_reduction=reduction, return_collapses=True)
P2, F2, mapping = fast_simplification.replay_simplification(P, F, collapses)
mapping = np.asarray(mapping)
UV2 = np.zeros((len(P2), 2), np.float32); UV2[mapping] = UV
N2 = np.zeros((len(P2), 3), np.float32); np.add.at(N2, mapping, N)
N2 /= np.linalg.norm(N2, axis=1, keepdims=True) + 1e-12
F2 = np.asarray(F2).reshape(-1, 3)
F2 = F2[(F2[:, 0] != F2[:, 1]) & (F2[:, 1] != F2[:, 2]) & (F2[:, 0] != F2[:, 2])]
print("out: verts", len(P2), "tris", len(F2))

def image(i, max_size):
    im = J['images'][i]; bv = J['bufferViews'][im['bufferView']]
    data = g.bin[bv.get('byteOffset', 0): bv.get('byteOffset', 0) + bv['byteLength']]
    img = Image.open(io.BytesIO(data))
    if max(img.size) > max_size:
        img = img.resize((max_size, max_size), Image.LANCZOS)
    out = io.BytesIO(); img.save(out, 'WEBP', quality=90); return out.getvalue()

binbuf = bytearray(); views = []; accs = []
def view(b, target=None):
    while len(binbuf) % 4: binbuf.append(0)
    v = {"buffer": 0, "byteOffset": len(binbuf), "byteLength": len(b)}
    if target: v["target"] = target
    binbuf.extend(b); views.append(v); return len(views) - 1
def acc(a, kind, ctype, target):
    accs.append({"bufferView": view(a.tobytes(), target), "componentType": ctype, "count": len(a), "type": kind})
    if kind == "VEC3": accs[-1]["min"] = a.min(0).tolist(); accs[-1]["max"] = a.max(0).tolist()
    return len(accs) - 1

pos = acc(P2.astype(np.float32), "VEC3", 5126, 34962)
nor = acc(N2.astype(np.float32), "VEC3", 5126, 34962)
tex = acc(UV2.astype(np.float32), "VEC2", 5126, 34962)
idx = acc(F2.reshape(-1).astype(np.uint32), "SCALAR", 5125, 34963)
base_img = view(image(0, 2048)); orm_img = view(image(1, 1024))
mat = json.loads(json.dumps(J['materials'][0])); mat["name"] = "Hero"
out = {
    "asset": {"version": "2.0", "generator": "lookout decimate_hero.py"},
    "extensionsUsed": ["EXT_texture_webp"], "extensionsRequired": ["EXT_texture_webp"],
    "scene": 0, "scenes": [{"nodes": [0]}],
    "nodes": [{"name": "Hero", "mesh": 0}],
    "meshes": [{"name": "Hero", "primitives": [{"attributes": {"POSITION": pos, "NORMAL": nor, "TEXCOORD_0": tex}, "indices": idx, "material": 0}]}],
    "materials": [mat],
    "textures": [{"extensions": {"EXT_texture_webp": {"source": 0}}}, {"extensions": {"EXT_texture_webp": {"source": 1}}}],
    "images": [{"bufferView": base_img, "mimeType": "image/webp"}, {"bufferView": orm_img, "mimeType": "image/webp"}],
    "accessors": accs, "bufferViews": views, "buffers": [{"byteLength": 0}],
}
while len(binbuf) % 4: binbuf.append(0)
out["buffers"][0]["byteLength"] = len(binbuf)
js = json.dumps(out, separators=(',', ':')).encode()
while len(js) % 4: js += b' '
blob = struct.pack('<4sII', b'glTF', 2, 28 + len(js) + len(binbuf)) + struct.pack('<II', len(js), 0x4E4F534A) + js + struct.pack('<II', len(binbuf), 0x004E4942) + bytes(binbuf)
open(dst, 'wb').write(blob)
print("wrote", dst, len(blob) // 1024, "KB")
