"""Split the Sketchfab car pack into one game-ready GLB per car.
Each output: metres, faces -Z (Godot forward), origin centred on the ground,
nodes: Body (body/glass/optics meshes) + Wheel_FL/FR/RL/RR (pivot at hub)."""
import sys, json, struct
import numpy as np
sys.path.insert(0, sys.argv[1])
from glbrender import GLB

src, info_path, canon_path, out_dir = sys.argv[2:6]
g = GLB(src); J = g.j
info = json.load(open(info_path)); canon = json.load(open(canon_path))
W = g.world_mats()

FRONT_PLUS_Z = {"Coupe Body", "Hatchback Body", "Pickup Body", "Sedan Body", "Wagon Body"}
IDS = {"Compact Body": "compact", "Coupe Body": "coupe", "Hatchback Body": "hatchback",
       "minivan body": "minivan", "Offroad Body": "offroad", "Pickup Body": "pickup",
       "Sedan Body": "sedan", "Sport body": "sport", "SUV Body": "suv", "Wagon Body": "wagon"}

def mesh_nodes(n):
    out = []
    def w(k):
        if 'mesh' in J['nodes'][k]: out.append(k)
        for c in J['nodes'][k].get('children', []): w(c)
    w(n); return out

def image_bytes(img_index):
    im = J['images'][img_index]; bv = J['bufferViews'][im['bufferView']]
    o = bv.get('byteOffset', 0); return g.bin[o:o + bv['byteLength']], im.get('mimeType', 'image/png')

class Writer:
    def __init__(self):
        self.j = {"asset": {"version": "2.0", "generator": "lookout split_cars.py"},
                  "scenes": [{"nodes": [0]}], "scene": 0, "nodes": [], "meshes": [], "materials": [],
                  "textures": [], "images": [], "samplers": [], "accessors": [], "bufferViews": [],
                  "buffers": [{"byteLength": 0}]}
        self.bin = bytearray(); self.mat_map = {}; self.tex_map = {}; self.img_map = {}; self.smp_map = {}

    def _view(self, data, target=None):
        while len(self.bin) % 4: self.bin += b'\0'
        bv = {"buffer": 0, "byteOffset": len(self.bin), "byteLength": len(data)}
        if target: bv["target"] = target
        self.bin += data; self.j["bufferViews"].append(bv); return len(self.j["bufferViews"]) - 1

    def accessor(self, arr, kind, target):
        if kind == "SCALAR":
            data = arr.astype(np.uint32).tobytes(); bv = self._view(data, target)
            acc = {"bufferView": bv, "componentType": 5125, "count": int(arr.size), "type": "SCALAR"}
        else:
            a = arr.astype(np.float32); bv = self._view(a.tobytes(), target)
            acc = {"bufferView": bv, "componentType": 5126, "count": int(len(a)), "type": kind}
            if kind == "VEC3": acc["min"] = a.min(0).tolist(); acc["max"] = a.max(0).tolist()
        self.j["accessors"].append(acc); return len(self.j["accessors"]) - 1

    def texture(self, ti):
        if ti in self.tex_map: return self.tex_map[ti]
        t = dict(J['textures'][ti]); new = {}
        if 'sampler' in t:
            si = t['sampler']
            if si not in self.smp_map:
                self.j["samplers"].append(J['samplers'][si]); self.smp_map[si] = len(self.j["samplers"]) - 1
            new['sampler'] = self.smp_map[si]
        ii = t['source']
        if ii not in self.img_map:
            data, mime = image_bytes(ii)
            self.j["images"].append({"bufferView": self._view(data), "mimeType": mime})
            self.img_map[ii] = len(self.j["images"]) - 1
        new['source'] = self.img_map[ii]
        self.j["textures"].append(new); self.tex_map[ti] = len(self.j["textures"]) - 1
        return self.tex_map[ti]

    def material(self, mi):
        if mi in self.mat_map: return self.mat_map[mi]
        m = json.loads(json.dumps(J['materials'][mi]))
        def fix(d):
            for k, v in list(d.items()):
                if isinstance(v, dict):
                    if k.endswith('Texture') and 'index' in v: v['index'] = self.texture(v['index']); v.pop('texCoord', None) if v.get('texCoord', 0) == 0 else None
                    else: fix(v)
        fix(m); m.pop('extensions', None)
        self.j["materials"].append(m); self.mat_map[mi] = len(self.j["materials"]) - 1
        return self.mat_map[mi]

    def mesh(self, node_ids, xform, name):
        prims = []
        for k in node_ids:
            M = xform @ W[k]; R = M[:3, :3]
            N_R = np.linalg.inv(R).T
            for pr in J['meshes'][J['nodes'][k]['mesh']]['primitives']:
                at = pr['attributes']
                P = g.acc(at['POSITION']); P = (np.c_[P, np.ones(len(P))] @ M.T)[:, :3]
                new = {"attributes": {"POSITION": self.accessor(P, "VEC3", 34962)}, "mode": 4}
                if 'NORMAL' in at:
                    Nn = g.acc(at['NORMAL']) @ N_R.T; Nn /= np.linalg.norm(Nn, axis=1, keepdims=True) + 1e-12
                    new["attributes"]["NORMAL"] = self.accessor(Nn, "VEC3", 34962)
                if 'TEXCOORD_0' in at:
                    new["attributes"]["TEXCOORD_0"] = self.accessor(g.acc(at['TEXCOORD_0']), "VEC2", 34962)
                idx = g.acc(pr['indices']).reshape(-1) if 'indices' in pr else np.arange(len(P))
                if np.linalg.det(R) < 0: idx = idx.reshape(-1, 3)[:, [0, 2, 1]].reshape(-1)
                new["indices"] = self.accessor(idx, "SCALAR", 34963)
                if 'material' in pr: new["material"] = self.material(pr['material'])
                prims.append(new)
        self.j["meshes"].append({"name": name, "primitives": prims}); return len(self.j["meshes"]) - 1

    def save(self, path):
        while len(self.bin) % 4: self.bin += b'\0'
        self.j["buffers"][0]["byteLength"] = len(self.bin)
        for k in ["samplers", "textures", "images"]:
            if not self.j[k]: del self.j[k]
        js = json.dumps(self.j, separators=(',', ':')).encode()
        while len(js) % 4: js += b' '
        out = struct.pack('<4sII', b'glTF', 2, 12 + 8 + len(js) + 8 + len(self.bin))
        out += struct.pack('<II', len(js), 0x4E4F534A) + js + struct.pack('<II', len(self.bin), 0x004E4942) + bytes(self.bin)
        open(path, 'wb').write(out)

summary = {}
for b, (name, size, center, ws) in info.items():
    c = canon[name]; car = IDS[name]
    yaw = c['yaw'] + (np.pi if name in FRONT_PLUS_Z else 0.0)   # length axis -> -Z means front at -Z
    # Rotate so the car's front points to -Z: first align length to +Z, front was +Z => flip.
    T = np.eye(4); T[0, 3] = -c['cx']; T[2, 3] = -c['cz']
    cy, sy = np.cos(-c['yaw']), np.sin(-c['yaw'])
    Ry = np.eye(4); Ry[:3, :3] = [[cy, 0, sy], [0, 1, 0], [-sy, 0, cy]]
    flip = np.eye(4)
    if name in FRONT_PLUS_Z: flip[:3, :3] = np.diag([-1, 1, -1])   # 180 deg about Y
    X = flip @ Ry @ T
    # ground: lowest wheel point -> y = 0
    wheel_ids = [w[0] for w in ws]
    lows = []
    centres = {}
    for wn in wheel_ids:
        pts = []
        for k in mesh_nodes(wn):
            for pr in J['meshes'][J['nodes'][k]['mesh']]['primitives']:
                P = g.acc(pr['attributes']['POSITION']); pts.append((np.c_[P, np.ones(len(P))] @ (X @ W[k]).T)[:, :3])
        pts = np.concatenate(pts); lows.append(pts[:, 1].min()); centres[wn] = ((pts.min(0) + pts.max(0)) / 2, pts.max(0) - pts.min(0))
    ground = min(lows)
    G = np.eye(4); G[1, 3] = -ground; X = G @ X

    wr = Writer()
    wr.j["nodes"].append({"name": car, "children": []})
    body_mesh = wr.mesh(mesh_nodes(int(b)), X, "Body")
    wr.j["nodes"].append({"name": "Body", "mesh": body_mesh}); wr.j["nodes"][0]["children"].append(1)
    wheel_out = {}
    for wn in wheel_ids:
        cen, ext = centres[wn]; cen = cen.copy(); cen[1] -= ground
        side = "L" if cen[0] < 0 else "R"; end = "F" if cen[2] < 0 else "R"
        wname = f"Wheel_{end}{side}"
        Cm = np.eye(4); Cm[:3, 3] = -cen
        mi = wr.mesh(mesh_nodes(wn), Cm @ X, wname)
        wr.j["nodes"].append({"name": wname, "mesh": mi, "translation": cen.round(5).tolist()})
        wr.j["nodes"][0]["children"].append(len(wr.j["nodes"]) - 1)
        wheel_out[wname] = {"pos": cen.round(3).tolist(), "radius": round(float(max(ext[1], ext[2]) / 2), 3), "width": round(float(ext[0]), 3)}
    path = f"{out_dir}/{car}.glb"; wr.save(path)
    summary[car] = {"length": round(c['length'], 2), "width": round(c['width'], 2), "height": round(c['height'] - 0, 2), "wheels": wheel_out,
                    "bytes": len(open(path, 'rb').read())}
    assert sorted(wheel_out) == ["Wheel_FL", "Wheel_FR", "Wheel_RL", "Wheel_RR"], (car, sorted(wheel_out))
json.dump(summary, open(f"{out_dir}/_summary.json", "w"), indent=1)
for k, v in summary.items(): print(k, v['bytes'] // 1024, "KB", "L", v['length'], {w: (d['pos'], d['radius']) for w, d in v['wheels'].items()})
