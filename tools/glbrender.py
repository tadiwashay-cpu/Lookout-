"""Minimal GLB loader + painter's-algorithm renderer (numpy + PIL) for previews."""
import json, struct, io, sys
import numpy as np
from PIL import Image, ImageDraw

CT = {5120: np.int8, 5121: np.uint8, 5122: np.int16, 5123: np.uint16, 5125: np.uint32, 5126: np.float32}
NC = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4, 'MAT4': 16}

class GLB:
    def __init__(self, path):
        b = open(path, 'rb').read()
        clen = struct.unpack('<I', b[12:16])[0]
        self.j = json.loads(b[20:20 + clen])
        off = 20 + clen
        blen = struct.unpack('<I', b[off:off + 4])[0]
        self.bin = b[off + 8: off + 8 + blen]
        self._img = {}

    def acc(self, i):
        a = self.j['accessors'][i]; bv = self.j['bufferViews'][a['bufferView']]
        dt = CT[a['componentType']]; n = NC[a['type']]
        start = bv.get('byteOffset', 0) + a.get('byteOffset', 0)
        stride = bv.get('byteStride', 0); isz = np.dtype(dt).itemsize * n
        if stride and stride != isz:
            raw = np.frombuffer(self.bin, np.uint8, a['count'] * stride, start).reshape(a['count'], stride)[:, :isz]
            arr = np.frombuffer(raw.tobytes(), dt).reshape(a['count'], n)
        else:
            arr = np.frombuffer(self.bin, dt, a['count'] * n, start).reshape(a['count'], n)
        return arr.astype(np.float64) if dt == np.float32 else arr

    def image(self, tex_index):
        if tex_index in self._img: return self._img[tex_index]
        tex = self.j['textures'][tex_index]; src = tex.get('source', tex.get('extensions', {}).get('EXT_texture_webp', {}).get('source')); im = self.j['images'][src]
        bv = self.j['bufferViews'][im['bufferView']]
        data = self.bin[bv.get('byteOffset', 0): bv.get('byteOffset', 0) + bv['byteLength']]
        img = np.asarray(Image.open(io.BytesIO(data)).convert('RGB')).astype(np.float64) / 255
        self._img[tex_index] = img
        return img

    def node_matrix(self, n):
        nd = self.j['nodes'][n]
        if 'matrix' in nd: return np.array(nd['matrix']).reshape(4, 4).T
        m = np.eye(4)
        if 'scale' in nd: m = np.diag(list(nd['scale']) + [1]) @ m
        if 'rotation' in nd:
            x, y, z, w = nd['rotation']
            r = np.array([[1-2*(y*y+z*z), 2*(x*y-z*w), 2*(x*z+y*w)], [2*(x*y+z*w), 1-2*(x*x+z*z), 2*(y*z-x*w)], [2*(x*z-y*w), 2*(y*z+x*w), 1-2*(x*x+y*y)]])
            R = np.eye(4); R[:3, :3] = r; m = R @ m
        if 'translation' in nd:
            T = np.eye(4); T[:3, 3] = nd['translation']; m = T @ m
        return m

    def world_mats(self):
        out = {}
        def walk(n, parent):
            w = parent @ self.node_matrix(n); out[n] = w
            for c in self.j['nodes'][n].get('children', []): walk(c, w)
        for s in self.j['scenes']:
            for n in s['nodes']: walk(n, np.eye(4))
        return out

    def triangles(self, node_ids=None):
        """Returns world-space tris (N,3,3) and per-tri RGB colors (N,3)."""
        W = self.world_mats(); tris = []; cols = []
        for n, m in W.items():
            nd = self.j['nodes'][n]
            if 'mesh' not in nd or (node_ids is not None and n not in node_ids): continue
            for pr in self.j['meshes'][nd['mesh']]['primitives']:
                P = self.acc(pr['attributes']['POSITION'])
                P = (np.c_[P, np.ones(len(P))] @ m.T)[:, :3]
                idx = self.acc(pr['indices']).reshape(-1).astype(np.int64) if 'indices' in pr else np.arange(len(P))
                idx = idx.reshape(-1, 3); t = P[idx]
                mat = self.j['materials'][pr['material']] if 'material' in pr else {}
                pbr = mat.get('pbrMetallicRoughness', {})
                base = np.array(pbr.get('baseColorFactor', [0.8, 0.8, 0.8, 1])[:3])
                c = np.tile(base, (len(t), 1))
                if 'baseColorTexture' in pbr and 'TEXCOORD_0' in pr['attributes']:
                    img = self.image(pbr['baseColorTexture']['index'])
                    uv = self.acc(pr['attributes']['TEXCOORD_0'])[idx].mean(axis=1)
                    h, w, _ = img.shape
                    px = (np.mod(uv[:, 0], 1) * (w - 1)).astype(int); py = (np.mod(uv[:, 1], 1) * (h - 1)).astype(int)
                    c = c * img[py, px]
                tris.append(t); cols.append(c)
        return np.concatenate(tris), np.concatenate(cols)

def render(tris, cols, out, yaw_deg=35, pitch_deg=20, size=900, max_tris=120000, bg=(28, 30, 34)):
    if len(tris) > max_tris:
        sel = np.random.default_rng(0).choice(len(tris), max_tris, replace=False); tris, cols = tris[sel], cols[sel]
    c = (tris.reshape(-1, 3).min(0) + tris.reshape(-1, 3).max(0)) / 2
    t = tris - c
    ya, pa = np.radians(yaw_deg), np.radians(pitch_deg)
    Ry = np.array([[np.cos(ya), 0, np.sin(ya)], [0, 1, 0], [-np.sin(ya), 0, np.cos(ya)]])
    Rx = np.array([[1, 0, 0], [0, np.cos(pa), -np.sin(pa)], [0, np.sin(pa), np.cos(pa)]])
    t = t @ (Rx @ Ry).T
    n = np.cross(t[:, 1] - t[:, 0], t[:, 2] - t[:, 0]); n /= np.linalg.norm(n, axis=1, keepdims=True) + 1e-12
    light = np.array([0.4, 0.7, 0.6]); light /= np.linalg.norm(light)
    shade = 0.35 + 0.65 * np.abs(n @ light)
    rgb = np.clip(cols * shade[:, None], 0, 1)
    ext = np.abs(t[:, :, :2]).max() * 1.08
    xy = (t[:, :, :2] / ext * 0.5 + 0.5) * size; xy[:, :, 1] = size - xy[:, :, 1]
    order = np.argsort(t[:, :, 2].mean(1))  # far (negative z) first
    im = Image.new('RGB', (size, size), bg); d = ImageDraw.Draw(im)
    for i in order:
        col = tuple((rgb[i] * 255).astype(int)); d.polygon([tuple(p) for p in xy[i]], fill=col, outline=col)
    im.save(out)
