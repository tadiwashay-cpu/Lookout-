"""Rig an unrigged T-pose character mesh (e.g. AI-generated) by borrowing the
skeleton and skin weights of an already-rigged reference character:

    python rig_from_reference.py HERO.glb REFERENCE_RIGGED.glb OUT.glb [--faces +x]

The reference (mesh + bones) is warped so its feet, crotch, arm line, head top,
torso width and hand tips land on the new mesh's, then every new vertex takes
the weights of the nearest point on the reference surface.
"""
import bpy, math, os, sys
import numpy as np
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree
from mathutils.interpolate import poly_3d_calc

args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
hero_path, ref_path, out_path = args[0], args[1], args[2]
faces = args[args.index("--faces") + 1] if "--faces" in args else "+x"

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=ref_path)
arm = next(o for o in bpy.data.objects if o.type == 'ARMATURE')
ref_meshes = [o for o in bpy.data.objects if o.type == 'MESH' and o.parent == arm]
for o in [o for o in bpy.data.objects if o.type == 'MESH' and o.parent != arm]:
    bpy.data.objects.remove(o, do_unlink=True)     # importer's bone-shape helper
for a in list(bpy.data.actions):
    bpy.data.actions.remove(a)
arm.animation_data_clear()
arm.data.pose_position = 'REST'
bpy.context.view_layer.update()
# Bake object transforms so everything is in world metres.
for o in ref_meshes:
    mw = o.matrix_world.copy()
    o.parent = None
    o.data.transform(mw)
    o.matrix_world = Matrix.Identity(4)
bpy.ops.object.select_all(action='DESELECT')
arm.select_set(True)
bpy.context.view_layer.objects.active = arm
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
bpy.ops.object.select_all(action='DESELECT')
ref_existing = set(bpy.data.objects)

bpy.ops.import_scene.gltf(filepath=hero_path)
hero_parts = [o for o in bpy.data.objects if o not in ref_existing and o.type == 'MESH']
for o in hero_parts:
    o.select_set(True)
bpy.context.view_layer.objects.active = hero_parts[0]
if len(hero_parts) > 1:
    bpy.ops.object.join()
hero = bpy.context.view_layer.objects.active
hero.parent = None
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
turn = {"+x": -90, "-x": 90, "+y": 180, "-y": 0}[faces]     # make it face -Y like the reference
hero.data.transform(Matrix.Rotation(math.radians(turn), 4, 'Z'))

def verts(objs):
    return np.concatenate([np.array([v.co[:] for v in o.data.vertices]) for o in objs])

def landmarks(V):
    V = V.copy()
    z0 = V[:, 2].min()
    cx = (V[:, 0].min() + V[:, 0].max()) / 2
    cy = np.median(V[:, 1])
    V -= [cx, cy, z0]
    H = V[:, 2].max()
    span = np.abs(V[:, 0]).max()
    arm_z = V[np.abs(V[:, 0]) > 0.6 * span][:, 2].mean()
    # Walk down the torso's centre line until it opens up between the legs.
    crotch = 0.45 * H
    for z in np.arange(0.62 * H, 0.2 * H, -0.004 * H):
        sl = V[(np.abs(V[:, 2] - z) < 0.01 * H) & (np.abs(V[:, 0]) < 0.012 * H)]
        if len(sl) == 0:
            break
        crotch = z
    mid = (crotch + arm_z) / 2
    band = V[np.abs(V[:, 2] - mid) < 0.02 * H]
    torso_w = np.abs(band[:, 0]).max()
    torso_d = band[:, 1].max() - band[:, 1].min()
    return dict(off=np.array([cx, cy, z0]), H=H, span=span, arm_z=arm_z, crotch=crotch, torso_w=torso_w, torso_d=torso_d)

R = landmarks(verts(ref_meshes))
# Scale the hero to the reference's height first, then measure it.
hv = verts([hero])
s = R["H"] / (hv[:, 2].max() - hv[:, 2].min())
hero.data.transform(Matrix.Scale(s, 4))
Hm = landmarks(verts([hero]))
hero.data.transform(Matrix.Translation(Vector(-Hm["off"])))
Hm = landmarks(verts([hero]))
print("@ref ", {k: (round(float(v), 3) if k != "off" else None) for k, v in R.items()})
print("@hero", {k: (round(float(v), 3) if k != "off" else None) for k, v in Hm.items()})

def remap(v, src, dst):
    return float(np.interp(v, src, dst))

def warp(p):
    x, y, z = p[0] - R["off"][0], p[1] - R["off"][1], p[2] - R["off"][2]
    nz = remap(z, [0, R["crotch"], R["arm_z"], R["H"]], [0, Hm["crotch"], Hm["arm_z"], Hm["H"]])
    nx = math.copysign(remap(abs(x), [0, R["torso_w"], R["span"]], [0, Hm["torso_w"], Hm["span"]]), x)
    ny = y * Hm["torso_d"] / R["torso_d"]
    return Vector((nx, ny, nz))

for o in ref_meshes:
    for v in o.data.vertices:
        v.co = warp(v.co)
bpy.context.view_layer.objects.active = arm
bpy.ops.object.mode_set(mode='EDIT')
for eb in arm.data.edit_bones:
    eb.use_connect = False
for eb in arm.data.edit_bones:
    h, t = warp(eb.head), warp(eb.tail)
    eb.head, eb.tail = h, t
bpy.ops.object.mode_set(mode='OBJECT')

# --- weights: nearest point on the warped reference surface ---------------------
tri_v, tris, tri_w = [], [], []
for o in ref_meshes:
    o.data.calc_loop_triangles()
    names = [g.name for g in o.vertex_groups]
    base = len(tri_v)
    for v in o.data.vertices:
        tri_v.append(v.co.copy())
        tri_w.append({names[g.group]: g.weight for g in v.groups if g.weight > 1e-4})
    for lt in o.data.loop_triangles:
        tris.append(tuple(base + i for i in lt.vertices))
tree = BVHTree.FromPolygons(tri_v, tris)
bone_names = [b.name for b in arm.data.bones]
groups = {n: hero.vertex_groups.new(name=n) for n in bone_names}
side_x = 0.02 * Hm["H"]
for v in hero.data.vertices:
    loc, _n, idx, _d = tree.find_nearest(v.co)
    ids = tris[idx]
    bw = poly_3d_calc([tri_v[i] for i in ids], loc)
    w = {}
    for i, b in zip(ids, bw):
        for n, val in tri_w[i].items():
            w[n] = w.get(n, 0.0) + val * b
    # A limb never follows the other side's bones (baggy trouser legs touch).
    for n in list(w):
        if ("Left" in n and v.co.x < -side_x) or ("Right" in n and v.co.x > side_x):
            del w[n]
    top = sorted(w.items(), key=lambda kv: -kv[1])[:4]
    total = sum(val for _, val in top) or 1.0
    if not top:
        top, total = [("mixamorig:Hips" if "mixamorig:Hips" in groups else bone_names[0], 1.0)], 1.0
    for n, val in top:
        if n in groups:
            groups[n].add([v.index], val / total, 'REPLACE')

for o in ref_meshes:
    bpy.data.objects.remove(o, do_unlink=True)
hero.name = "Hero"
hero.parent = arm
mod = hero.modifiers.new("Armature", 'ARMATURE')
mod.object = arm
arm.data.pose_position = 'POSE'
for m in hero.data.materials:
    if m and m.use_nodes:
        bsdf = next((n for n in m.node_tree.nodes if n.type == 'BSDF_PRINCIPLED'), None)
        if bsdf:
            bsdf.inputs["Metallic"].default_value = 0.0
            bsdf.inputs["Roughness"].default_value = 0.85
for img in bpy.data.images:
    if img.size[0] > 1024:
        img.scale(1024, 1024)
for poly in hero.data.polygons:
    poly.use_smooth = True
bpy.ops.export_scene.gltf(filepath=out_path, export_format='GLB', export_animations=False, export_yup=True,
                          export_skins=True, export_morph=False, export_image_format='JPEG', export_jpeg_quality=88)
print("@saved", out_path, os.path.getsize(out_path) // 1024, "KB")
os._exit(0)
