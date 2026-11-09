"""Auto-rig + animate the hero (a T-pose, single-mesh GLB, facing +Z, ~1 unit tall).

Builds a humanoid skeleton fitted to the hero's proportions, skins every
vertex to its nearest bones (with left/right and region masks so legs don't
drag each other), and authors the clips the game looks for:
idle, walk, run, punch_1, punch_2, punch_3, punch_heavy, dodge, hit, knocked_out.

Usage: python rig_hero.py in.glb out.glb
Needs: numpy (and glbrender.py next to this file).
Conventions: model faces +Z, its LEFT is +X. Joints have identity rest
rotation, so animation rotations are in parent space (= model axes at rest).
"""
import json, struct, sys
import numpy as np

sys.path.insert(0, __file__.rsplit('/', 1)[0])
from glbrender import GLB

# --------------------------------------------------------------------- skeleton
# name: (parent, rest position in model space)
JOINTS = {
    "hips": (None, (0.0, 0.0, 0.0)),
    "spine": ("hips", (0.0, 0.07, -0.005)),
    "chest": ("spine", (0.0, 0.15, -0.01)),
    "neck": ("chest", (0.0, 0.30, -0.01)),
    "head": ("neck", (0.0, 0.36, -0.005)),
    "shoulder_L": ("chest", (0.05, 0.245, -0.02)),
    "upper_arm_L": ("shoulder_L", (0.12, 0.234, -0.03)),
    "lower_arm_L": ("upper_arm_L", (0.27, 0.234, -0.03)),
    "hand_L": ("lower_arm_L", (0.395, 0.234, -0.03)),
    "shoulder_R": ("chest", (-0.05, 0.245, -0.02)),
    "upper_arm_R": ("shoulder_R", (-0.12, 0.234, -0.03)),
    "lower_arm_R": ("upper_arm_R", (-0.27, 0.234, -0.03)),
    "hand_R": ("lower_arm_R", (-0.395, 0.234, -0.03)),
    "upper_leg_L": ("hips", (0.05, -0.01, 0.0)),
    "lower_leg_L": ("upper_leg_L", (0.05, -0.21, 0.0)),
    "foot_L": ("lower_leg_L", (0.05, -0.43, 0.0)),
    "upper_leg_R": ("hips", (-0.05, -0.01, 0.0)),
    "lower_leg_R": ("upper_leg_R", (-0.05, -0.21, 0.0)),
    "foot_R": ("lower_leg_R", (-0.05, -0.43, 0.0)),
}
# Bone tails (segment ends) used for skin weights.
TAILS = {
    "hips": (0.0, 0.07, 0.0), "spine": (0.0, 0.15, 0.0), "chest": (0.0, 0.30, 0.0),
    "neck": (0.0, 0.36, 0.0), "head": (0.0, 0.50, 0.0),
    "shoulder_L": (0.12, 0.234, 0.0), "upper_arm_L": (0.27, 0.234, 0.0),
    "lower_arm_L": (0.395, 0.234, 0.0), "hand_L": (0.49, 0.234, 0.0),
    "shoulder_R": (-0.12, 0.234, 0.0), "upper_arm_R": (-0.27, 0.234, 0.0),
    "lower_arm_R": (-0.395, 0.234, 0.0), "hand_R": (-0.49, 0.234, 0.0),
    "upper_leg_L": (0.05, -0.21, 0.0), "lower_leg_L": (0.05, -0.43, 0.0), "foot_L": (0.05, -0.5, 0.05),
    "upper_leg_R": (-0.05, -0.21, 0.0), "lower_leg_R": (-0.05, -0.43, 0.0), "foot_R": (-0.05, -0.5, 0.05),
}
NAMES = list(JOINTS)
IDX = {n: i for i, n in enumerate(NAMES)}


def allowed(name, P):
    """Region masks so each bone only grabs plausible vertices."""
    x, y = P[:, 0], P[:, 1]
    side = 1.0 if name.endswith("_L") else -1.0 if name.endswith("_R") else 0.0
    m = np.ones(len(P), bool)
    if "arm" in name or "hand" in name:
        m &= (x * side > 0.07) & (y > 0.12) & (y < 0.36)
    elif "shoulder" in name:
        m &= (x * side > 0.0) & (y > 0.12)
    elif "leg" in name or "foot" in name:
        m &= (x * side > -0.012) & (y < 0.06)
    elif name == "head":
        m &= y > 0.33
    elif name == "neck":
        m &= (y > 0.24) & (np.abs(x) < 0.2)
    elif name in ("chest", "spine"):
        m &= (y > -0.06) & (y < 0.4) & (np.abs(x) < 0.2)
    elif name == "hips":
        m &= (y > -0.12) & (y < 0.12) & (np.abs(x) < 0.15)
    return m


def skin_weights(P):
    n = len(P)
    W = np.zeros((n, len(NAMES)))
    for name in NAMES:
        a = np.array(JOINTS[name][1]); b = np.array(TAILS[name])
        ab = b - a; t = np.clip(((P - a) @ ab) / (ab @ ab + 1e-12), 0, 1)
        d = np.linalg.norm(P - (a + t[:, None] * ab), axis=1)
        w = 1.0 / (d + 0.008) ** 6
        W[:, IDX[name]] = np.where(allowed(name, P), w, 0.0)
    empty = W.sum(1) == 0
    if empty.any():   # fall back to plain nearest bones
        for name in NAMES:
            a = np.array(JOINTS[name][1]); b = np.array(TAILS[name]); ab = b - a
            t = np.clip(((P[empty] - a) @ ab) / (ab @ ab), 0, 1)
            W[empty, IDX[name]] = 1.0 / (np.linalg.norm(P[empty] - (a + t[:, None] * ab), axis=1) + 0.008) ** 6
    top = np.argsort(-W, axis=1)[:, :4]
    tw = np.take_along_axis(W, top, 1); tw /= tw.sum(1, keepdims=True)
    tw[tw < 0.02] = 0; tw /= tw.sum(1, keepdims=True)
    return top.astype(np.uint16), tw.astype(np.float32)


# ------------------------------------------------------------------ quaternions
def q(axis, deg):
    axis = {"x": (1, 0, 0), "y": (0, 1, 0), "z": (0, 0, 1)}[axis]
    h = np.radians(deg) / 2
    return np.array([axis[0] * np.sin(h), axis[1] * np.sin(h), axis[2] * np.sin(h), np.cos(h)])


def mul(a, b):   # a then... returns a*b (apply b first, then a) — xyzw
    ax, ay, az, aw = a; bx, by, bz, bw = b
    return np.array([aw * bx + ax * bw + ay * bz - az * by, aw * by - ax * bz + ay * bw + az * bx,
                     aw * bz + ax * by - ay * bx + az * bw, aw * bw - ax * bx - ay * by - az * bz])


def chain(*rots):   # chain(R1, R2, ...) applies R1 first, then R2 ... (all in parent space)
    out = np.array([0, 0, 0, 1.0])
    for r in rots: out = mul(r, out)
    return out


def qmat(r):
    x, y, z, w = r
    return np.array([[1-2*(y*y+z*z), 2*(x*y-z*w), 2*(x*z+y*w)], [2*(x*y+z*w), 1-2*(x*x+z*z), 2*(y*z-x*w)], [2*(x*z-y*w), 2*(y*z+x*w), 1-2*(x*x+y*y)]])


# ----------------------------------------------------------------------- poses
# Model faces +Z, its left is +X.  Handy facts (identity rest):
#   arm L hangs:  Rz(-a)   arm R hangs: Rz(+a)
#   swing limb forward: Rx(-a) ; lean torso forward: Rx(+a)
#   left arm straight forward: Ry(-90) ; right arm forward: Ry(+90)
#   bend elbow forward: L Ry(-a), R Ry(+a) ; knee back: Rx(+a)
#   twist chest so RIGHT shoulder comes forward: Ry(+a)
S = np.sin

def arms_down(p, swing_l=0.0, swing_r=0.0, elbow=12.0, drop=74.0):
    p["upper_arm_L"] = chain(q("z", -drop), q("x", -swing_l))
    p["upper_arm_R"] = chain(q("z", drop), q("x", -swing_r))
    p["lower_arm_L"] = q("y", -elbow); p["lower_arm_R"] = q("y", elbow)


def guard(p):
    """Fists up — the brawler stance punches start and end in."""
    p["upper_arm_L"] = chain(q("z", -70), q("x", -38), q("y", -12))
    p["upper_arm_R"] = chain(q("z", 70), q("x", -38), q("y", 12))
    p["lower_arm_L"] = q("y", -115); p["lower_arm_R"] = q("y", 115)
    p["spine"] = q("y", 8)
    p["upper_leg_L"] = q("x", -8); p["upper_leg_R"] = q("x", 6)
    p["lower_leg_L"] = q("x", 12); p["lower_leg_R"] = q("x", 10)


def idle(t):
    p, root = {}, np.zeros(3)
    b = S(t * 2 * np.pi / 2.4)
    arms_down(p, elbow=14 + 3 * b, drop=72 + 1.5 * b)
    p["chest"] = q("x", 1.5 * b); p["head"] = q("x", -1.0 * b)
    root[1] = -0.002 + 0.002 * b
    return p, root


def locomotion(t, period, leg, knee, arm, elbow, lean, bob):
    p, root = {}, np.zeros(3)
    ph = t / period * 2 * np.pi
    s = S(ph)
    p["upper_leg_L"] = q("x", -leg * s); p["upper_leg_R"] = q("x", leg * s)
    p["lower_leg_L"] = q("x", knee * max(0, -np.cos(ph)) + 6); p["lower_leg_R"] = q("x", knee * max(0, np.cos(ph)) + 6)
    p["foot_L"] = q("x", -8 * s); p["foot_R"] = q("x", 8 * s)
    arms_down(p, swing_l=-arm * s, swing_r=arm * s, elbow=elbow)
    p["spine"] = chain(q("x", lean), q("y", 4 * s))
    root[1] = -bob * 0.5 + bob * abs(np.cos(ph))
    return p, root


def walk(t): return locomotion(t, 1.0, 26, 40, 18, 18, 3, 0.012)
def run(t): return locomotion(t, 0.66, 42, 85, 38, 80, 12, 0.02)


def blend_pose(a, b, w):
    out = {}
    for k in set(a) | set(b):
        qa = a.get(k, np.array([0, 0, 0, 1.0])); qb = b.get(k, np.array([0, 0, 0, 1.0]))
        if qa @ qb < 0: qb = -qb
        r = qa * (1 - w) + qb * w; out[k] = r / np.linalg.norm(r)
    return out


def ease(x): return x * x * (3 - 2 * x)


def keyed(keys):
    """keys: list of (time, pose_fn) -> f(t) blending poses with smoothstep."""
    def f(t):
        for (t0, a), (t1, b) in zip(keys, keys[1:]):
            if t <= t1:
                w = ease(np.clip((t - t0) / max(t1 - t0, 1e-6), 0, 1))
                pa, ra = a(); pb, rb = b()
                return blend_pose(pa, pb, w), ra * (1 - w) + rb * w
        return keys[-1][1]()
    return f


def pose(builder, root=(0, 0, 0)):
    def f():
        p = {}; builder(p); return p, np.array(root, float)
    return f


def g_guard(p): guard(p)


def g_jab_r(p):
    guard(p); p["upper_arm_R"] = chain(q("y", 88), q("x", -4)); p["lower_arm_R"] = q("y", 6); p["spine"] = q("y", 22)


def g_cross_l(p):
    guard(p); p["upper_arm_L"] = chain(q("y", -88), q("x", -4)); p["lower_arm_L"] = q("y", -6); p["spine"] = q("y", -24)
    p["upper_leg_R"] = q("x", 14)


def g_hook_wind(p):
    guard(p); p["spine"] = q("y", -16)


def g_hook_r(p):
    guard(p); p["upper_arm_R"] = chain(q("y", 70), q("x", -6)); p["lower_arm_R"] = q("y", 95); p["spine"] = q("y", 38)


def g_crouch(p):
    guard(p); p["upper_leg_L"] = q("x", -30); p["upper_leg_R"] = q("x", -22)
    p["lower_leg_L"] = q("x", 55); p["lower_leg_R"] = q("x", 48); p["spine"] = chain(q("x", 14), q("y", -10))


def g_uppercut(p):
    guard(p); p["upper_arm_R"] = chain(q("z", 72), q("x", -150)); p["lower_arm_R"] = q("y", 40)
    p["spine"] = chain(q("x", -8), q("y", 20)); p["head"] = q("x", -10)


def g_dodge(p):
    arms_down(p, elbow=60, drop=55); p["spine"] = q("x", 28)
    p["upper_leg_L"] = q("x", -55); p["upper_leg_R"] = q("x", -35)
    p["lower_leg_L"] = q("x", 95); p["lower_leg_R"] = q("x", 70)


def g_hit(p):
    arms_down(p, swing_l=20, swing_r=25, elbow=40, drop=60); p["spine"] = q("x", -16); p["head"] = q("x", -18)


def g_ko(p):
    arms_down(p, swing_l=-10, swing_r=-15, elbow=20, drop=30); p["hips"] = q("x", -88); p["head"] = q("x", 10)


CLIPS = {
    "idle": (idle, 2.4),
    "walk": (walk, 1.0),
    "run": (run, 0.66),
    "punch_1": (keyed([(0, pose(g_guard)), (0.12, pose(g_jab_r)), (0.34, pose(g_guard))]), 0.34),
    "punch_2": (keyed([(0, pose(g_guard)), (0.12, pose(g_cross_l)), (0.34, pose(g_guard))]), 0.34),
    "punch_3": (keyed([(0, pose(g_guard)), (0.1, pose(g_hook_wind)), (0.2, pose(g_hook_r)), (0.5, pose(g_guard))]), 0.5),
    "punch_heavy": (keyed([(0, pose(g_guard)), (0.2, pose(g_crouch, (0, -0.04, 0))), (0.3, pose(g_uppercut, (0, 0.01, 0))), (0.62, pose(g_guard))]), 0.62),
    "dodge": (keyed([(0, pose(g_guard)), (0.08, pose(g_dodge, (0, -0.07, 0))), (0.28, pose(g_guard))]), 0.28),
    "hit": (keyed([(0, pose(g_guard)), (0.08, pose(g_hit)), (0.3, pose(g_guard))]), 0.3),
    "knocked_out": (keyed([(0, pose(g_hit)), (0.45, pose(g_ko, (0, -0.43, -0.05))), (0.6, pose(g_ko, (0, -0.43, -0.05)))]), 0.6),
}
FPS = 30


def sample(clip):
    fn, length = CLIPS[clip]
    times = np.round(np.arange(0, length + 1e-6, 1 / FPS), 5)
    if times[-1] < length - 1e-6: times = np.append(times, length)
    frames = [fn(t) for t in times]
    return times, frames


# ------------------------------------------------------------------- skinning
def joint_globals(pose_dict, root_offset):
    G = {}
    for name in NAMES:
        parent, pos = JOINTS[name]
        local_t = np.array(pos) - (np.array(JOINTS[parent][1]) if parent else 0)
        if name == "hips": local_t = local_t + root_offset
        M = np.eye(4); M[:3, :3] = qmat(pose_dict.get(name, np.array([0, 0, 0, 1.0]))); M[:3, 3] = local_t
        G[name] = (G[parent] @ M) if parent else M
    return G


def deform(P, J, Wt, pose_dict, root_offset):
    G = joint_globals(pose_dict, root_offset)
    mats = np.stack([G[n] @ np.block([[np.eye(3), -np.array(JOINTS[n][1])[:, None]], [np.zeros((1, 3)), np.ones((1, 1))]]) for n in NAMES])
    Ph = np.c_[P, np.ones(len(P))]
    out = np.zeros_like(P)
    for k in range(4):
        out += Wt[:, k:k + 1] * np.einsum('nij,nj->ni', mats[J[:, k]], Ph)[:, :3]
    return out


# ---------------------------------------------------------------------- write
def write(src, dst):
    g = GLB(src); J0 = g.j
    prim = J0['meshes'][0]['primitives'][0]
    P = g.acc(prim['attributes']['POSITION']).astype(np.float32)
    joints, weights = skin_weights(P)

    binbuf = bytearray(); views = []; accs = []
    def view(b, target=None):
        while len(binbuf) % 4: binbuf.append(0)
        v = {"buffer": 0, "byteOffset": len(binbuf), "byteLength": len(b)}
        if target: v["target"] = target
        binbuf.extend(b); views.append(v); return len(views) - 1
    def acc(a, kind, ctype, target=None, minmax=False):
        a = np.ascontiguousarray(a)
        d = {"bufferView": view(a.tobytes(), target), "componentType": ctype, "count": int(a.shape[0]), "type": kind}
        if minmax:
            flat = a.reshape(a.shape[0], -1)
            d["min"] = flat.min(0).tolist(); d["max"] = flat.max(0).tolist()
        accs.append(d); return len(accs) - 1

    def src_acc(i):
        return g.acc(i)
    at = prim['attributes']
    attrs = {
        "POSITION": acc(P, "VEC3", 5126, 34962, True),
        "NORMAL": acc(src_acc(at['NORMAL']).astype(np.float32), "VEC3", 5126, 34962),
        "TEXCOORD_0": acc(src_acc(at['TEXCOORD_0']).astype(np.float32), "VEC2", 5126, 34962),
        "JOINTS_0": acc(joints, "VEC4", 5123, 34962),
        "WEIGHTS_0": acc(weights, "VEC4", 5126, 34962),
    }
    indices = acc(src_acc(prim['indices']).reshape(-1).astype(np.uint32), "SCALAR", 5125, 34963)

    # images / textures carried over byte-for-byte
    images = []
    for im in J0['images']:
        bv = J0['bufferViews'][im['bufferView']]
        data = g.bin[bv.get('byteOffset', 0): bv.get('byteOffset', 0) + bv['byteLength']]
        images.append({"bufferView": view(data), "mimeType": im['mimeType']})

    nodes = [{"name": "Hero", "children": [1, 2]}, {"name": "HeroMesh", "mesh": 0, "skin": 0}]
    joint_node = {}
    for name in NAMES:
        joint_node[name] = len(nodes) + 0
        nodes.append(None)
    # node 2 must be the root joint
    order = NAMES
    base = 2
    for i, name in enumerate(order):
        parent, pos = JOINTS[name]
        local_t = (np.array(pos) - (np.array(JOINTS[parent][1]) if parent else 0)).round(6).tolist()
        kids = [base + j for j, n in enumerate(order) if JOINTS[n][0] == name]
        node = {"name": name, "translation": local_t}
        if kids: node["children"] = kids
        nodes[base + i] = node
    inv = np.stack([np.eye(4) for _ in order])
    for i, name in enumerate(order):
        inv[i][:3, 3] = -np.array(JOINTS[name][1])
    ibm = acc(np.stack([m.T.reshape(-1) for m in inv]).astype(np.float32), "MAT4", 5126)
    skin = {"joints": [base + i for i in range(len(order))], "inverseBindMatrices": ibm, "skeleton": base}

    animations = []
    for clip in CLIPS:
        times, frames = sample(clip)
        t_acc = acc(times.astype(np.float32), "SCALAR", 5126, minmax=True)
        channels, samplers = [], []
        for name in order:
            rots = np.array([f[0].get(name, np.array([0, 0, 0, 1.0])) for f in frames], np.float32)
            if np.allclose(rots, [0, 0, 0, 1], atol=1e-5) and clip not in ("idle",):
                continue
            samplers.append({"input": t_acc, "output": acc(rots, "VEC4", 5126), "interpolation": "LINEAR"})
            channels.append({"sampler": len(samplers) - 1, "target": {"node": base + IDX[name], "path": "rotation"}})
        root_t = np.array([np.array(JOINTS["hips"][1]) + f[1] for f in frames], np.float32)
        samplers.append({"input": t_acc, "output": acc(root_t, "VEC3", 5126), "interpolation": "LINEAR"})
        channels.append({"sampler": len(samplers) - 1, "target": {"node": base + IDX["hips"], "path": "translation"}})
        animations.append({"name": clip, "channels": channels, "samplers": samplers})

    mat = json.loads(json.dumps(J0['materials'][0]))
    out = {
        "asset": {"version": "2.0", "generator": "lookout rig_hero.py"},
        "extensionsUsed": J0.get("extensionsUsed", []), "extensionsRequired": J0.get("extensionsRequired", []),
        "scene": 0, "scenes": [{"nodes": [0]}], "nodes": nodes,
        "meshes": [{"name": "Hero", "primitives": [{"attributes": attrs, "indices": indices, "material": 0}]}],
        "skins": [skin], "animations": animations, "materials": [mat],
        "textures": J0['textures'], "images": images,
        "accessors": accs, "bufferViews": views, "buffers": [{"byteLength": 0}],
    }
    if not out["extensionsUsed"]: del out["extensionsUsed"]
    if not out["extensionsRequired"]: del out["extensionsRequired"]
    while len(binbuf) % 4: binbuf.append(0)
    out["buffers"][0]["byteLength"] = len(binbuf)
    js = json.dumps(out, separators=(',', ':')).encode()
    while len(js) % 4: js += b' '
    blob = struct.pack('<4sII', b'glTF', 2, 28 + len(js) + len(binbuf)) + struct.pack('<II', len(js), 0x4E4F534A) + js + struct.pack('<II', len(binbuf), 0x004E4942) + bytes(binbuf)
    open(dst, 'wb').write(blob)
    print("wrote", dst, len(blob) // 1024, "KB;", len(order), "joints;", len(animations), "clips")
    return P, joints, weights


if __name__ == "__main__":
    write(sys.argv[1], sys.argv[2])
