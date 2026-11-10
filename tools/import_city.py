"""Convert the downloaded city FBX into a mobile-ready Godot city.

    python import_city.py CITY.fbx OUT_DIR [--scale 6] [--cell 90] [--keep 0.45]

Writes OUT_DIR/city.glb (geometry in grid chunks, one draw-call-friendly
mesh per chunk, duplicate colours merged) and OUT_DIR/city_data.json
(Godot coordinates, metres):
  colliders: boxes for buildings/props [cx, cy, cz, sx, sy, sz, yaw]
  roads:     lane-marking centrelines  [[x, z], [x, z]]
  ground_y:  street level, bounds, landmarks (tallest buildings)
"""
import bpy, bmesh, json, math, os, re, sys
from collections import defaultdict
from mathutils import Matrix, Vector

args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
src, out_dir = args[0], args[1]
SCALE = float(args[args.index("--scale") + 1]) if "--scale" in args else 7.0
CELL = float(args[args.index("--cell") + 1]) if "--cell" in args else 90.0
KEEP = float(args[args.index("--keep") + 1]) if "--keep" in args else 0.22
os.makedirs(out_dir, exist_ok=True)

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=src)
for o in list(bpy.data.objects):
    if o.type != 'MESH':
        bpy.data.objects.remove(o, do_unlink=True)

def wbounds(o):
    # From the vertices themselves: bound_box is cached and goes stale after
    # mesh.transform() in background mode.
    import numpy as np
    n = len(o.data.vertices)
    if n == 0:
        return Vector((0, 0, 0)), Vector((0, 0, 0))
    co = np.empty(n * 3, dtype=np.float32)
    o.data.vertices.foreach_get("co", co)
    co = co.reshape(-1, 3)
    mw = np.array(o.matrix_world, dtype=np.float32)
    w = co @ mw[:3, :3].T + mw[:3, 3]
    return Vector(w.min(axis=0).tolist()), Vector(w.max(axis=0).tolist())

# ---- drop clutter: 3D text signs and specks ---------------------------------
for o in list(bpy.data.objects):
    mn, mx = wbounds(o)
    if o.name.startswith("Text") or max(mx - mn) < 0.03:
        bpy.data.objects.remove(o, do_unlink=True)

# ---- materials: plain colours, duplicates merged, missing textures fixed ----
def base_color(m):
    if m is None or not m.use_nodes:
        return (0.6, 0.6, 0.6)
    bsdf = next((n for n in m.node_tree.nodes if n.type == 'BSDF_PRINCIPLED'), None)
    if bsdf is None:
        return (0.6, 0.6, 0.6)
    inp = bsdf.inputs["Base Color"]
    if inp.links:   # textured (files are missing): pick a sensible colour
        name = m.name.lower()
        if "allcolors" in name or "tree" in name or "leaf" in name:
            return (0.18, 0.36, 0.14)
        if "wood" in name or "chair" in name:
            return (0.35, 0.22, 0.12)
        return (0.55, 0.55, 0.55)
    return tuple(inp.default_value[:3])

palette = {}
def palette_mat(color):
    key = tuple(round(c * 20) / 20 for c in color)
    if key not in palette:
        m = bpy.data.materials.new("C_%02d%02d%02d" % tuple(int(k * 20) for k in key))
        m.use_nodes = True
        b = m.node_tree.nodes["Principled BSDF"]
        b.inputs["Base Color"].default_value = (*key, 1.0)
        b.inputs["Roughness"].default_value = 0.8
        palette[key] = m
    return palette[key]

# Trees: their gradient texture is missing. Objects made only of textured
# materials (not furniture) are trees -> brown trunk below, green above.
def is_textured(m):
    if m is None or not m.use_nodes:
        return False
    b0 = next((n for n in m.node_tree.nodes if n.type == 'BSDF_PRINCIPLED'), None)
    return bool(b0 and b0.inputs["Base Color"].links)

TREES = set()
for o in bpy.data.objects:
    mats = [sl.material for sl in o.material_slots if sl.material]
    if mats and all(is_textured(m) for m in mats) and not any(k in m.name.lower() for m in mats for k in ("chair", "wood")):
        TREES.add(o.name)
print("@trees", len(TREES))

for o in bpy.data.objects:
    for i, slot in enumerate(o.material_slots):
        slot.material = palette_mat(base_color(slot.material))
# Trees using the missing palette texture show as pink: anything named Tree gets foliage colours.
for o in bpy.data.objects:
    if o.name.lower().startswith("tree"):
        for slot in o.material_slots:
            slot.material = palette_mat((0.18, 0.36, 0.14))

# ---- bake transforms, scale, centre, street level at 0 ---------------------
bpy.ops.object.select_all(action='SELECT')
bpy.context.view_layer.objects.active = bpy.data.objects[0]
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
ground = max(bpy.data.objects, key=lambda o: (wbounds(o)[1] - wbounds(o)[0]).x * (wbounds(o)[1] - wbounds(o)[0]).y)
gmn, gmx = wbounds(ground)
centre = (gmn + gmx) / 2
# Street level = the road surface (lane markings lie on it), not the lower grass.
marks = []
for o in bpy.data.objects:
    mn, mx = wbounds(o)
    sz = mx - mn
    if sz.z < 0.02 and min(sz.x, sz.y) < 0.1 and max(sz.x, sz.y) > 2.0:
        marks.append(mx.z)
marks.sort()
street = marks[len(marks) // 2] if marks else gmx.z
print("@street", round(street, 3), "ground top", round(gmx.z, 3))
M = Matrix.Scale(SCALE, 4) @ Matrix.Translation(Vector((-centre.x, -centre.y, -street)))
for o in bpy.data.objects:
    o.data.transform(M)
    o.data.update()
# Lift the grass slab to just under the roads: the game's flat ground
# (y = 0) then fits roads, pavements and grass alike.
gtop = max(v.co.z for v in ground.data.vertices)
ground.data.transform(Matrix.Translation(Vector((0, 0, -0.03 - gtop))))

def to_godot(v):   # Blender Z-up -> Godot Y-up (glTF): (x, y, z) -> (x, z, -y)
    return [round(v.x, 2), round(v.z, 2), round(-v.y, 2)]

def island_boxes(o):
    """Bounding boxes of the loose parts of a mesh, merged when they overlap."""
    me = o.data
    parent = list(range(len(me.vertices)))
    def find(a):
        while parent[a] != a:
            parent[a] = parent[parent[a]]
            a = parent[a]
        return a
    for e in me.edges:
        a, b = find(e.vertices[0]), find(e.vertices[1])
        if a != b:
            parent[a] = b
    boxes = {}
    for v in me.vertices:
        r = find(v.index)
        if r in boxes:
            mn, mx = boxes[r]
            boxes[r] = (Vector(map(min, mn, v.co)), Vector(map(max, mx, v.co)))
        else:
            boxes[r] = (v.co.copy(), v.co.copy())
    merged = []
    for mn, mx in sorted(boxes.values(), key=lambda b: -(b[1] - b[0]).length):
        for i, (a, b) in enumerate(merged):
            # a part inside / overlapping a bigger box joins it (windows, roofs...)
            if mn.x < b.x and mx.x > a.x and mn.y < b.y and mx.y > a.y:
                merged[i] = (Vector(map(min, a, mn)), Vector(map(max, b, mx)))
                break
        else:
            merged.append((mn, mx))
    return merged


# ---- data: colliders, road centrelines, landmarks ----------------------------
colliders, roads, towers = [], [], []
for o in bpy.data.objects:
    if o is ground:
        continue
    mn, mx = wbounds(o)
    size = mx - mn
    col = base_color(o.material_slots[0].material) if o.material_slots else (0.5, 0.5, 0.5)
    flat = size.z < 0.25
    if flat and min(size.x, size.y) < 0.6 and max(size.x, size.y) > 0.8 and min(col) > 0.9:
        # lane marking -> road centreline along its long axis
        if size.x >= size.y:
            a, b = Vector((mn.x, (mn.y + mx.y) / 2, 0)), Vector((mx.x, (mn.y + mx.y) / 2, 0))
        else:
            a, b = Vector(((mn.x + mx.x) / 2, mn.y, 0)), Vector(((mn.x + mx.x) / 2, mx.y, 0))
        roads.append([[to_godot(a)[0], to_godot(a)[2]], [to_godot(b)[0], to_godot(b)[2]]])
        continue
    if size.z > 0.9 and max(size.x, size.y) > 1.2:
        # One object can hold several buildings: box each separate piece so
        # the street between them stays open.
        for pmn, pmx in island_boxes(o):
            ps = pmx - pmn
            if ps.z < 0.9 or max(ps.x, ps.y) < 0.8:
                continue
            g = to_godot((pmn + pmx) / 2)
            colliders.append([g[0], round(pmx.z / 2, 2), g[2], round(ps.x, 2), round(pmx.z, 2), round(ps.y, 2), 0.0])
            if ps.x > 6 and ps.y > 6:
                towers.append({"pos": [g[0], 0.0, g[2]], "height": round(pmx.z, 1), "size": [round(ps.x, 1), round(ps.y, 1)]})
towers.sort(key=lambda t: -t["height"])
if "--data-only" in args:   # refresh the JSON without redoing the heavy mesh work
    path = os.path.join(out_dir, "city_data.json")
    data = json.load(open(path))
    data.update({"colliders": colliders, "roads": roads, "towers": towers[:12]})
    json.dump(data, open(path, "w"))
    print("@data-only colliders", len(colliders), "roads", len(roads))
    os._exit(0)

# ---- reduce heavy meshes --------------------------------------------------------
before = sum(len(p.vertices) - 2 for o in bpy.data.objects for p in o.data.polygons)
for o in bpy.data.objects:
    tris = sum(len(p.vertices) - 2 for p in o.data.polygons)
    if tris > 300:
        bpy.context.view_layer.objects.active = o
        mod = o.modifiers.new("planar", 'DECIMATE')
        mod.decimate_type = 'DISSOLVE'
        mod.angle_limit = math.radians(2.0)
        bpy.ops.object.modifier_apply(modifier=mod.name)
        tris = sum(len(p.vertices) - 2 for p in o.data.polygons)
        if tris > 500:
            mod = o.modifiers.new("collapse", 'DECIMATE')
            mod.ratio = max(KEEP, 500.0 / tris) if tris < 2500 else KEEP
            bpy.ops.object.modifier_apply(modifier=mod.name)
after = sum(len(p.vertices) - 2 for o in bpy.data.objects for p in o.data.polygons)

# ---- bake colours into vertex colours, one shared material ------------------
# (109 materials x 19 chunks would be ~1000 draw calls on a phone; this is 1 per chunk)
city_mat = bpy.data.materials.new("CityVC")
city_mat.use_nodes = True
nt = city_mat.node_tree
attr = nt.nodes.new("ShaderNodeVertexColor")
attr.layer_name = "Col"
nt.links.new(attr.outputs["Color"], nt.nodes["Principled BSDF"].inputs["Base Color"])
nt.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.85
for o in bpy.data.objects:
    me = o.data
    cols = [tuple(base_color(slot.material)) for slot in o.material_slots] or [(0.6, 0.6, 0.6)]
    for old in list(me.color_attributes):   # leftover colours from the source would win
        me.color_attributes.remove(old)
    layer = me.color_attributes.new("Col", 'BYTE_COLOR', 'CORNER')
    me.color_attributes.active_color = layer
    me.color_attributes.render_color_index = 0
    is_tree = o.name in TREES
    for poly in me.polygons:
        c = cols[min(poly.material_index, len(cols) - 1)]
        if is_tree:   # low faces = trunk, the rest = foliage (two greens for variety)
            c = (0.2, 0.13, 0.07) if poly.center.z < 0.9 else ((0.13, 0.3, 0.12) if (poly.index % 3) else (0.17, 0.36, 0.14))
        for li in poly.loop_indices:
            layer.data[li].color = (*c, 1.0)
    me.materials.clear()
    me.materials.append(city_mat)

# ---- chunk by grid cell (visibility culling + fewer draw calls) ---------------
cells = defaultdict(list)
for o in bpy.data.objects:
    if o is ground or o.type != 'MESH':
        continue
    mn, mx = wbounds(o)
    c = (mn + mx) / 2
    cells[(math.floor(c.x / CELL), math.floor(c.y / CELL))].append(o)
root = bpy.data.objects.new("City", None)
bpy.context.collection.objects.link(root)
col_obj = None
cells = {k: [o for o in v if o is not col_obj] for k, v in cells.items()}
for (ix, iy), objs in cells.items():
    if not objs:
        continue
    bpy.ops.object.select_all(action='DESELECT')
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    if len(objs) > 1:
        bpy.ops.object.join()
    chunk = bpy.context.view_layer.objects.active
    chunk.name = "Chunk_%d_%d" % (ix, iy)
    chunk.parent = root
print("@tris", before, "->", after, "chunks", len(cells), "materials", len(palette))

bpy.ops.export_scene.gltf(filepath=os.path.join(out_dir, "city.glb"), export_format='GLB',
                          export_yup=True, export_apply=True)
gmn, gmx = wbounds(ground)
data = {"scale": SCALE, "bounds": [to_godot(gmn)[0], to_godot(gmx)[2], to_godot(gmx)[0], to_godot(gmn)[2]],
        "colliders": colliders, "roads": roads, "towers": towers[:12]}
json.dump(data, open(os.path.join(out_dir, "city_data.json"), "w"))
# Top-down reference map (1 px = 0.5 m) for placing landmarks.
sc = bpy.context.scene
cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
sc.collection.objects.link(cam)
cam.data.type = 'ORTHO'
cam.data.ortho_scale = max(gmx.x - gmn.x, gmx.y - gmn.y)
cam.location = (0, 0, 400)
cam.data.clip_end = 1000
sc.camera = cam
sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", 'SUN'))
sc.collection.objects.link(sun)
sun.rotation_euler = (0.5, 0.2, 0.4)
sun.data.energy = 3
sc.render.engine = 'CYCLES'
sc.cycles.samples = 6
sc.cycles.device = 'CPU'
sc.render.resolution_x = 1400
sc.render.resolution_y = int(1400 * (gmx.y - gmn.y) / (gmx.x - gmn.x))
sc.render.filepath = os.path.join(out_dir, "city_map.png")
bpy.ops.render.render(write_still=True)
print("@data colliders", len(colliders), "roads", len(roads), "towers", len(towers),
      "bounds", data["bounds"], "glb KB", os.path.getsize(os.path.join(out_dir, "city.glb")) // 1024)
os._exit(0)
