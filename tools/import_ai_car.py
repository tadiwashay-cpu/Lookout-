"""Turn a heavy single-mesh car (e.g. AI-generated, wheels fused into one
mesh of many loose pieces) into a game car:

    python import_ai_car.py IN.glb OUT.glb CAR_ID [--length 4.7] [--body-tris 25000]

  * scales to a real length, faces it forward (+Y in Blender = what the game
    expects), the rear wing/spoiler end is the back
  * finds the four tyre contact patches, gathers every loose piece inside
    each wheel's cylinder into Wheel_FL/FR/RL/RR (origin on the hub)
  * decimates body and wheels for mobile, shrinks textures to 1024 px JPEG
  * names the body material Body_* so the game's paint shader can recolour it
"""
import bpy, bmesh, math, os, sys
from mathutils import Matrix, Vector

args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
src, out, car_id = args[0], args[1], args[2]
length = float(args[args.index("--length") + 1]) if "--length" in args else 4.7
body_tris = int(args[args.index("--body-tris") + 1]) if "--body-tris" in args else 25000
wheel_r = float(args[args.index("--wheel-r") + 1]) if "--wheel-r" in args else 0.0

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
meshes = [o for o in bpy.data.objects if o.type == 'MESH']
bpy.ops.object.select_all(action='DESELECT')
for o in meshes:
    o.select_set(True)
bpy.context.view_layer.objects.active = meshes[0]
if len(meshes) > 1:
    bpy.ops.object.join()
car = bpy.context.view_layer.objects.active
car.parent = None
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

def bounds(obj):
    vs = [v.co for v in obj.data.vertices]
    mn = Vector((min(v.x for v in vs), min(v.y for v in vs), min(v.z for v in vs)))
    mx = Vector((max(v.x for v in vs), max(v.y for v in vs), max(v.z for v in vs)))
    return mn, mx

# --- scale and orientation -------------------------------------------------
mn, mx = bounds(car)
size = mx - mn
long_axis = 0 if size.x >= size.y else 1
s = length / size[long_axis]
car.data.transform(Matrix.Scale(s, 4))
mn, mx = bounds(car)
# Rear = the end whose top vertices are highest (wing / spoiler).
vs = [v.co for v in car.data.vertices]
top = sorted(vs, key=lambda v: -v.z)[: max(50, len(vs) // 200)]
rear_sign = 1 if sum(v[long_axis] for v in top) / len(top) > (mn[long_axis] + mx[long_axis]) / 2 else -1
# Want the front on +Y: rotate so (long_axis, -rear_sign) maps to +Y.
front = Vector((0, 0, 0))
front[long_axis] = -rear_sign
angle = math.atan2(front.x, front.y)   # rotate front onto +Y
car.data.transform(Matrix.Rotation(angle, 4, 'Z'))
mn, mx = bounds(car)
centre = (mn + mx) / 2
car.data.transform(Matrix.Translation(Vector((-centre.x, -centre.y, -mn.z))))   # centred, wheels on z=0
mn, mx = bounds(car)
print("@car size", [round(v, 2) for v in (mx - mn)], "rear was", "+" if rear_sign > 0 else "-", "axis", "xy"[long_axis])

# --- wheels: contact patches -> centres -> loose pieces in the cylinder ------
vs = [v.co.copy() for v in car.data.vertices]
patch = {}
for v in vs:
    if v.z < 0.03:
        key = (v.x > 0, v.y > 0)
        patch.setdefault(key, []).append(v)
wheels = {}
for (px, py), pts in patch.items():
    c = sum(pts, Vector()) / len(pts)
    # Radius: look straight up through the hub. The tyre's top is the last
    # point before the air gap under the wheel arch.
    if wheel_r > 0.0:
        r = wheel_r
    else:
        zs = sorted(v.z for v in vs if abs(v.x - c.x) < 0.2 and abs(v.y - c.y) < 0.05)
        r = 0.36
        for k in range(1, len(zs)):
            if zs[k - 1] > 0.45 and zs[k] - zs[k - 1] > 0.025:
                r = zs[k - 1] / 2.0
                break
        r = max(0.28, min(0.46, r))
    name = "Wheel_%s%s" % ("F" if py else "R", "L" if not px else "R")
    # +Y is the front; in the game the car's left is +X... keep the pack
    # convention: Wheel_*L on -X (driver's left when facing +Y in Blender).
    wheels[name] = (Vector((c.x, c.y, r)), r)
print("@wheels", {k: ([round(x, 2) for x in v[0]], round(v[1], 2)) for k, v in wheels.items()})

bm = bmesh.new()
bm.from_mesh(car.data)
bm.verts.ensure_lookup_table()
parent = list(range(len(bm.verts)))
def find(a):
    while parent[a] != a:
        parent[a] = parent[parent[a]]
        a = parent[a]
    return a
for e in bm.edges:
    a, b = find(e.verts[0].index), find(e.verts[1].index)
    if a != b:
        parent[a] = b
islands = {}
for v in bm.verts:
    islands.setdefault(find(v.index), []).append(v)
assign = {}
for root, verts in islands.items():
    cen = sum((v.co for v in verts), Vector()) / len(verts)
    for name, (wc, r) in wheels.items():
        inside = all(math.hypot(v.co.y - wc.y, v.co.z - wc.z) < r * 1.06 and abs(v.co.x - wc.x) < 0.2 for v in verts)
        if inside:
            assign[root] = name
            break
for name in wheels:
    faces = [f for f in bm.faces if assign.get(find(f.verts[0].index)) == name]
    print("@", name, len(faces), "faces")
# Split each wheel into its own object.
objs = {}
for name, (wc, r) in wheels.items():
    wbm = bmesh.new()
    vmap = {}
    for f in bm.faces:
        if assign.get(find(f.verts[0].index)) != name:
            continue
        nv = []
        for v in f.verts:
            if v not in vmap:
                vmap[v] = wbm.verts.new(v.co - wc)
            nv.append(vmap[v])
        try:
            nf = wbm.faces.new(nv)
            nf.material_index = f.material_index
            nf.smooth = f.smooth
        except ValueError:
            pass
    me = bpy.data.meshes.new(name)
    wbm.to_mesh(me)
    wbm.free()
    for m in car.data.materials:
        me.materials.append(m)
    ob = bpy.data.objects.new(name, me)
    ob.location = wc
    bpy.context.collection.objects.link(ob)
    objs[name] = ob
dead = [f for f in bm.faces if find(f.verts[0].index) in assign]
bmesh.ops.delete(bm, geom=dead, context='FACES')
bm.to_mesh(car.data)
bm.free()
car.name = "Body"

# --- decimate -------------------------------------------------------------
def decimate(ob, target):
    tris = sum(len(p.vertices) - 2 for p in ob.data.polygons)
    if tris > target:
        mod = ob.modifiers.new("dec", 'DECIMATE')
        mod.ratio = target / tris
        bpy.context.view_layer.objects.active = ob
        bpy.ops.object.modifier_apply(modifier=mod.name)
    return sum(len(p.vertices) - 2 for p in ob.data.polygons)
print("@tris body", decimate(car, body_tris), "wheels", [decimate(o, 1800) for o in objs.values()])

# --- materials / textures ---------------------------------------------------
for m in car.data.materials:
    if m and not m.name.startswith("Body"):
        m.name = "Body_" + m.name
for img in bpy.data.images:
    if img.size[0] > 1024:
        img.scale(1024, int(1024 * img.size[1] / img.size[0]))

root = bpy.data.objects.new(car_id, None)
bpy.context.collection.objects.link(root)
car.parent = root
for ob in objs.values():
    ob.parent = root
bpy.ops.export_scene.gltf(filepath=out, export_format='GLB', export_yup=True, export_apply=True,
                          export_image_format='JPEG', export_jpeg_quality=85)
print("@exported", out, os.path.getsize(out) // 1024, "KB")
os._exit(0)
