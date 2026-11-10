"""Procedural supercars (original designs) for the car store.

    python make_supercars.py OUT_DIR [--render PNG]

Each car is built the way the game expects (see DrivableCar):
  * root node named after the car, model facing -Z in glTF (+Y in Blender)
  * "Body" mesh: materials Body_* (paintable), Glass, Optics_Front,
    Optics_Rear (lamps; they glow at night), Trim
  * "Wheel_FL/FR/RL/RR" meshes with their origin on the hub
Body: cross-sections lofted along the car, one subdivision level, wheel
arches cut with booleans. ~10-14k triangles per car with wheels.
"""
import bpy, bmesh, math, os, sys
from mathutils import Vector, Matrix

# Silhouette keys: (t along the car 0=rear..1=nose, value). Linear in between.
DESIGNS = {
    # 1. razor wedge hypercar (green): angular facets, Y-shaped running lights
    "strix_v12": {
        "length": 4.9, "width": 2.06, "wheelbase": 2.78, "wheel_r": 0.37, "track": 1.76,
        "belt": [(0, 0.8), (0.3, 0.78), (0.7, 0.62), (1, 0.34)],
        "roof": [(0.3, 0.8), (0.4, 1.06), (0.52, 1.12), (0.64, 0.98), (0.74, 0.66)],
        "cab": (0.3, 0.72), "nose_drop": 0.1, "wing": None, "intake": True, "diffuser": True,
        "faceted": True, "lights": "y", "paint": (0.25, 0.75, 0.12), "price": 30000},
    # 2. front-engine GT (orange): long bonnet, big grille, fastback, haunches
    "aurora_gt": {
        "length": 4.6, "width": 1.98, "wheelbase": 2.72, "wheel_r": 0.36, "track": 1.7,
        "belt": [(0, 0.86), (0.3, 0.84), (0.7, 0.8), (1, 0.6)],
        "roof": [(0.1, 0.9), (0.22, 1.12), (0.4, 1.26), (0.52, 1.22), (0.6, 0.92)],
        "cab": (0.14, 0.6), "nose_drop": 0.1, "wing": None, "intake": False, "diffuser": True,
        "grille": "wide", "lights": "slim", "haunch": 0.06, "paint": (0.95, 0.38, 0.08), "price": 22000},
    # 3. mid-engine roadster (grey): open top, humps behind the seats
    "spyder_rs": {
        "length": 4.4, "width": 1.9, "wheelbase": 2.5, "wheel_r": 0.35, "track": 1.64,
        "belt": [(0, 0.86), (0.35, 0.86), (0.7, 0.78), (1, 0.56)],
        "roof": [(0.4, 0.9), (0.6, 0.9)],
        "cab": (0.42, 0.62), "nose_drop": 0.08, "wing": (0.02, 1.0, 0.28), "intake": True, "diffuser": True,
        "open_top": True, "lights": "slim", "paint": (0.42, 0.44, 0.47), "price": 18000},
    # 4. grand tourer (red): taller, long, upright grille, round twin lamps
    "regal_gt": {
        "length": 4.95, "width": 1.98, "wheelbase": 2.9, "wheel_r": 0.37, "track": 1.68,
        "belt": [(0, 0.92), (0.4, 0.92), (0.8, 0.88), (1, 0.72)],
        "roof": [(0.1, 0.98), (0.24, 1.3), (0.44, 1.38), (0.58, 1.3), (0.66, 0.98)],
        "cab": (0.14, 0.66), "nose_drop": 0.06, "wing": None, "intake": False, "diffuser": False,
        "grille": "tall", "lights": "round", "haunch": 0.05, "paint": (0.62, 0.05, 0.06), "price": 26000},
    # 5. mid-engine supercar (blue): teardrop canopy, big sculpted side intakes
    "vortex_rs": {
        "length": 4.6, "width": 2.02, "wheelbase": 2.68, "wheel_r": 0.36, "track": 1.72,
        "belt": [(0, 0.82), (0.3, 0.8), (0.72, 0.66), (1, 0.42)],
        "roof": [(0.22, 0.84), (0.34, 1.1), (0.5, 1.18), (0.64, 1.04), (0.76, 0.7)],
        "cab": (0.24, 0.76), "nose_drop": 0.1, "wing": None, "intake": True, "diffuser": True,
        "big_intake": True, "lights": "slim", "haunch": 0.04, "paint": (0.08, 0.45, 0.9), "price": 40000},
}

SILL = 0.24          # body bottom above ground
RINGS = 34
SIDE_PTS = 7         # points per half-section (bottom -> roof)


def lerp_keys(keys, t):
    if t <= keys[0][0]:
        return keys[0][1]
    for (t0, v0), (t1, v1) in zip(keys, keys[1:]):
        if t <= t1:
            k = (t - t0) / max(t1 - t0, 1e-5)
            k = k * k * (3 - 2 * k)
            return v0 + (v1 - v0) * k
    return keys[-1][1]


def material(name, color, metallic=0.0, rough=0.5, emission=None, alpha=1.0):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = rough
    if emission:
        bsdf.inputs["Emission Color"].default_value = (*emission, 1.0)
        bsdf.inputs["Emission Strength"].default_value = 0.6
    if alpha < 1.0:
        bsdf.inputs["Alpha"].default_value = alpha
        mat.surface_render_method = 'BLENDED'
    return mat


def section(d, t):
    """Half cross-section at t: list of (x, z) from bottom centre up to roof centre."""
    L, W = d["length"], d["width"]
    # Ends taper in plan and the nose drops.
    # Plan view: sharp wedge nose, short cut-off (Kamm) tail.
    if t > 0.8:
        taper = 1.0 - ((t - 0.8) / 0.2) ** 1.6 * 0.38
    elif t < 0.06:
        taper = 0.9 + 0.1 * (t / 0.06)
    else:
        taper = 1.0
    # Hips: the body bulges over the rear wheels (supercar stance).
    rear_axle = 0.5 - d["wheelbase"] / d["length"] * 0.5
    taper *= 1.0 + d.get("haunch", 0.035) * math.exp(-((t - rear_axle) / 0.08) ** 2)
    half = W * 0.5 * taper
    belt = lerp_keys(d["belt"], t)
    if t > 0.8:
        belt -= d["nose_drop"] * ((t - 0.8) / 0.2) ** 1.3 * 1.6
    cab0, cab1 = d["cab"]
    in_cab = cab0 <= t <= cab1 and not d.get("open_top")
    roof = lerp_keys(d["roof"], t) if in_cab else belt + 0.04
    if d.get("open_top"):
        lo = 0.5 - d["wheelbase"] / d["length"] * 0.5
        hump = math.exp(-((t - (cab0 - 0.06)) / 0.07) ** 2) * 0.16   # fairings behind the seats
        roof = belt + 0.04 + hump
    roof = max(roof, belt + 0.04)
    # Doubled points at the sill and the shoulder keep crisp character lines
    # after subdivision; the side is pulled in below the shoulder (sculpted flank).
    belt = max(belt, SILL + 0.22)
    h = belt - SILL   # side points as fractions of the flank: they can never cross over
    pts = [(0.0, SILL), (half * 0.84, SILL), (half * 0.9, SILL + h * 0.04), (half * 0.95, SILL + h * 0.3),
           (half * 0.985, SILL + h * 0.8), (half, SILL + h * 0.94), (half * 0.96, belt)]
    if in_cab and roof > belt + 0.1:
        pts += [(half * 0.72, belt + (roof - belt) * 0.55), (half * 0.42, roof)]
    else:
        pts += [(half * 0.7, belt + 0.03), (half * 0.35, belt + 0.04)]
    pts.append((0.0, roof if in_cab else belt + 0.045))
    return pts


def build_body(name, d, mats):
    L = d["length"]
    bm = bmesh.new()
    rings = []
    for i in range(RINGS):
        t = i / (RINGS - 1)
        y = (t - 0.5) * L
        half = section(d, t)
        ring = [bm.verts.new((x, y, z)) for x, z in half]                       # right side (+x)
        ring += [bm.verts.new((-x, y, z)) for x, z in reversed(half[1:-1])]  # left side, back down
        rings.append(ring)
    n = len(rings[0])
    for a, b in zip(rings, rings[1:]):
        for k in range(n):
            k2 = (k + 1) % n
            try:
                bm.faces.new((a[k], a[k2], b[k2], b[k]))
            except ValueError:
                pass
    # End caps as fans round a centre point (an n-gon pinches when subdivided).
    for ring, flip in ((rings[0], True), (rings[-1], False)):
        centre = sum((v.co for v in ring), Vector()) / len(ring)
        hub = bm.verts.new(centre + Vector((0, (-0.04 if flip else 0.04), 0)))
        for k in range(len(ring)):
            a, b = ring[k], ring[(k + 1) % len(ring)]
            try:
                bm.faces.new((b, a, hub) if flip else (a, b, hub))
            except ValueError:
                pass
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-4)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new("Body", mesh)
    bpy.context.collection.objects.link(obj)
    for m in mats.values():
        mesh.materials.append(m)
    # Greenhouse faces -> glass (above the beltline, inside the cabin span)
    cab0, cab1 = d["cab"]
    for poly in mesh.polygons:
        c = poly.center
        t = c.y / L + 0.5
        belt = lerp_keys(d["belt"], t)
        if cab0 + 0.02 < t < cab1 - 0.02 and c.z > belt + 0.06 and abs(poly.normal.z) < 0.93:
            poly.material_index = list(mats).index("glass")
    if not d.get("faceted"):   # faceted hypercar keeps its hard planes
        mod = obj.modifiers.new("sub", 'SUBSURF')
        mod.levels = 1
        mod.render_levels = 1
    for m in obj.modifiers:
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.modifier_apply(modifier=m.name)
    # Wheel arches
    wb, track, r = d["wheelbase"], d["track"], d["wheel_r"]
    for sy, sx in ((-1, -1), (-1, 1), (1, -1), (1, 1)):   # one cutter per wheel, sides only
        cutter = bpy.data.objects.new("cut", bpy.data.meshes.new("cut"))
        bpy.context.collection.objects.link(cutter)
        cbm = bmesh.new()
        bmesh.ops.create_cone(cbm, cap_ends=True, segments=24, radius1=r * 1.16, radius2=r * 1.16, depth=0.6)
        bmesh.ops.rotate(cbm, verts=cbm.verts, cent=(0, 0, 0), matrix=Matrix.Rotation(math.pi / 2, 3, 'Y'))
        bmesh.ops.translate(cbm, verts=cbm.verts, vec=(sx * (d["width"] * 0.5), sy * wb / 2, r))
        cbm.to_mesh(cutter.data)
        cbm.free()
        boolean = obj.modifiers.new("arch", 'BOOLEAN')
        boolean.operation = 'DIFFERENCE'
        boolean.object = cutter
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.modifier_apply(modifier=boolean.name)
        bpy.data.objects.remove(cutter, do_unlink=True)
    return obj


def add_box(body, size, loc, mat_index, rot=None):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=size, verts=bm.verts)
    if rot:
        bmesh.ops.rotate(bm, verts=bm.verts, cent=(0, 0, 0), matrix=rot)
    bmesh.ops.translate(bm, verts=bm.verts, vec=loc)
    for f in bm.faces:
        f.material_index = mat_index
    tmp = bpy.data.meshes.new("tmp")
    bm.to_mesh(tmp)
    bm.free()
    for m in body.data.materials:   # same slots as the body so indices survive the join
        tmp.materials.append(m)
    part = bpy.data.objects.new("part", tmp)
    bpy.context.collection.objects.link(part)
    return part


def details(body, d, mats):
    idx = {k: i for i, k in enumerate(mats)}
    L, W = d["length"], d["width"]
    parts = []
    nose_y, tail_y = L * 0.5, -L * 0.5
    belt_f = lerp_keys(d["belt"], 0.96) - d["nose_drop"] * 0.73
    belt_r = lerp_keys(d["belt"], 0.02)
    style = d.get("lights", "slim")
    if style == "y":   # Y-shaped running lights: two angled strips per side
        for sx in (-1, 1):
            parts.append(add_box(body, (0.38, 0.05, 0.035), (sx * W * 0.3, nose_y - 0.36, belt_f + 0.02), idx["front"], Matrix.Rotation(sx * 0.5, 3, 'Z')))
            parts.append(add_box(body, (0.05, 0.05, 0.16), (sx * W * 0.38, nose_y - 0.42, belt_f - 0.06), idx["front"]))
            parts.append(add_box(body, (0.5, 0.04, 0.05), (sx * W * 0.28, tail_y + 0.02, belt_r - 0.08), idx["rear"], Matrix.Rotation(sx * 0.2, 3, 'Y')))
    elif style == "round":   # twin round lamps per side
        for sx in (-1, 1):
            for k, off in enumerate((0.18, 0.4)):
                lamp = bmesh.new()
                bmesh.ops.create_cone(lamp, cap_ends=True, segments=14, radius1=0.08 if k else 0.1, radius2=0.08 if k else 0.1, depth=0.06)
                bmesh.ops.rotate(lamp, verts=lamp.verts, cent=(0, 0, 0), matrix=Matrix.Rotation(math.pi / 2, 3, 'X'))
                bmesh.ops.translate(lamp, verts=lamp.verts, vec=(sx * (W * 0.5 - off), nose_y - 0.2 - off * 0.25, belt_f - 0.02))
                for f in lamp.faces:
                    f.material_index = idx["front"]
                tmp = bpy.data.meshes.new("lamp")
                lamp.to_mesh(tmp)
                lamp.free()
                for m in body.data.materials:
                    tmp.materials.append(m)
                part = bpy.data.objects.new("lamp", tmp)
                bpy.context.collection.objects.link(part)
                parts.append(part)
            parts.append(add_box(body, (0.32, 0.05, 0.1), (sx * W * 0.32, tail_y + 0.03, belt_r - 0.1), idx["rear"]))
    elif d.get("light_bar"):
        parts.append(add_box(body, (W * 0.78, 0.05, 0.04), (0, nose_y - 0.16, belt_f - 0.05), idx["front"]))
        parts.append(add_box(body, (W * 0.84, 0.05, 0.05), (0, tail_y + 0.06, belt_r - 0.1), idx["rear"]))
    else:   # slim swept lamps
        for sx in (-1, 1):
            parts.append(add_box(body, (0.44, 0.22, 0.045), (sx * W * 0.27, nose_y - 0.34, belt_f + 0.0), idx["front"],
                                 Matrix.Rotation(sx * 0.32, 3, 'Z') @ Matrix.Rotation(0.18, 3, 'X')))
        parts.append(add_box(body, (W * 0.74, 0.04, 0.045), (0, tail_y + 0.015, belt_r - 0.1), idx["rear"]))   # full-width tail strip
    parts.append(add_box(body, (W * 0.72, 0.3, 0.06), (0, nose_y - 0.12, SILL + 0.03), idx["trim"]))          # splitter
    if d.get("grille") == "wide":
        parts.append(add_box(body, (W * 0.5, 0.06, 0.22), (0, nose_y - 0.03, SILL + 0.2), idx["trim"]))
    elif d.get("grille") == "tall":
        parts.append(add_box(body, (W * 0.36, 0.06, 0.34), (0, nose_y - 0.02, SILL + 0.3), idx["trim"]))
    if d.get("big_intake"):
        for sx in (-1, 1):
            parts.append(add_box(body, (0.08, 0.9, 0.34), (sx * W * 0.49, -L * 0.04, SILL + 0.36), idx["trim"], Matrix.Rotation(sx * 0.12, 3, 'Z')))
    if d.get("diffuser"):
        for k in range(5):
            parts.append(add_box(body, (0.03, 0.4, 0.16), (-0.5 + k * 0.25, tail_y + 0.25, SILL + 0.05), idx["trim"]))
        parts.append(add_box(body, (W * 0.72, 0.5, 0.03), (0, tail_y + 0.28, SILL - 0.02), idx["trim"]))
    if d.get("intake"):
        for sx in (-1, 1):
            parts.append(add_box(body, (0.06, 0.55, 0.22), (sx * W * 0.5, -L * 0.1, SILL + 0.38), idx["trim"]))
    if d.get("wing"):
        t, h, chord = d["wing"]
        y = (t - 0.5) * L + 0.25
        parts.append(add_box(body, (W * 0.9, chord, 0.04), (0, y, h), idx["paint"], Matrix.Rotation(-0.12, 3, 'X')))
        for sx in (-1, 1):
            parts.append(add_box(body, (0.04, 0.22, h - belt_r + 0.04), (sx * W * 0.3, y, (h + belt_r) * 0.5), idx["trim"]))
            parts.append(add_box(body, (0.03, chord * 1.05, 0.2), (sx * W * 0.45, y, h + 0.02), idx["paint"]))
    if d.get("fins"):
        for sx in (-1, 1):
            parts.append(add_box(body, (0.03, 0.9, 0.22), (sx * W * 0.2, -L * 0.3, belt_r + 0.1), idx["paint"]))
    if d.get("open_top"):   # roadster: cockpit tub, raked windscreen, two seats
        c0, c1 = d["cab"]
        y0, y1 = (c0 - 0.5) * L, (c1 - 0.5) * L
        belt_c = lerp_keys(d["belt"], (c0 + c1) * 0.5)
        parts.append(add_box(body, (W * 0.74, y1 - y0, 0.06), (0, (y0 + y1) * 0.5, belt_c + 0.01), idx["trim"]))
        parts.append(add_box(body, (W * 0.8, 0.04, 0.32), (0, y1 + 0.02, belt_c + 0.15), idx["glass"], Matrix.Rotation(-0.75, 3, 'X')))
        for sx in (-1, 1):
            parts.append(add_box(body, (0.42, 0.12, 0.42), (sx * W * 0.2, y0 + 0.12, belt_c + 0.2), idx["trim"], Matrix.Rotation(0.2, 3, 'X')))
    for sx in (-1, 1):   # mirrors
        parts.append(add_box(body, (0.18, 0.08, 0.1), (sx * (W * 0.5 + 0.02), (d["cab"][1] - 0.5) * L - 0.15, lerp_keys(d["belt"], d["cab"][1]) + 0.12), idx["paint"]))
    bpy.ops.object.select_all(action='DESELECT')
    for p in parts:
        p.select_set(True)
    body.select_set(True)
    bpy.context.view_layer.objects.active = body
    bpy.ops.object.join()


def wheel(name, r, width, loc, mats):
    bm = bmesh.new()
    tire = bmesh.ops.create_cone(bm, cap_ends=True, segments=28, radius1=r, radius2=r, depth=width)
    for f in bm.faces:
        f.material_index = 0
    rim = bmesh.ops.create_cone(bm, cap_ends=True, segments=20, radius1=r * 0.68, radius2=r * 0.68, depth=width * 1.04)
    for v in rim["verts"]:
        for f in v.link_faces:
            f.material_index = 1
    for k in range(5):   # spokes
        a = k / 5 * math.tau
        res = bmesh.ops.create_cube(bm, size=1.0)
        bmesh.ops.scale(bm, vec=(r * 1.25, 0.06, width * 1.08), verts=res["verts"])
        bmesh.ops.rotate(bm, verts=res["verts"], cent=(0, 0, 0), matrix=Matrix.Rotation(a, 3, 'Z'))
        for v in res["verts"]:
            for f in v.link_faces:
                f.material_index = 1
    bmesh.ops.rotate(bm, verts=bm.verts, cent=(0, 0, 0), matrix=Matrix.Rotation(math.pi / 2, 3, 'Y'))
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    mesh.materials.append(mats["tire"])
    mesh.materials.append(mats["rim"])
    obj = bpy.data.objects.new(name, mesh)
    obj.location = loc
    bpy.context.collection.objects.link(obj)
    for p in mesh.polygons:
        p.use_smooth = True
    return obj


def build_car(car_id, d, out_dir):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    mats = {
        "paint": material("Body_Paint", d["paint"], 0.6, 0.25),
        "glass": material("Glass", (0.05, 0.07, 0.09), 0.2, 0.05),
        "front": material("Optics_Front", (1.0, 0.97, 0.9), 0.0, 0.1, emission=(1.0, 0.97, 0.9)),
        "rear": material("Optics_Rear", (0.9, 0.05, 0.04), 0.0, 0.2, emission=(0.9, 0.05, 0.04)),
        "trim": material("Trim", (0.03, 0.03, 0.035), 0.3, 0.6),
    }
    root = bpy.data.objects.new(car_id, None)
    bpy.context.collection.objects.link(root)
    body = build_body(car_id + "_body", d, mats)
    details(body, d, mats)
    for p in body.data.polygons:
        p.use_smooth = True
    body.data.shade_auto_smooth(angle=math.radians(40)) if hasattr(body.data, "shade_auto_smooth") else None
    body.parent = root
    wm = {"tire": material("Wheel_Tire", (0.02, 0.02, 0.02), 0.0, 0.85), "rim": material("Wheel_Rim", (0.6, 0.6, 0.62), 0.9, 0.25)}
    r, wb, tr = d["wheel_r"], d["wheelbase"], d["track"]
    for nm, sx, sy in (("Wheel_FL", -1, 1), ("Wheel_FR", 1, 1), ("Wheel_RL", -1, -1), ("Wheel_RR", 1, -1)):
        w = wheel(nm, r, 0.28, (sx * tr / 2, sy * wb / 2, r), wm)
        w.parent = root
    tris = sum(len(p.vertices) - 2 for o in bpy.data.objects if o.type == 'MESH' for p in o.data.polygons)
    path = os.path.join(out_dir, car_id + ".glb")
    bpy.ops.export_scene.gltf(filepath=path, export_format='GLB', export_yup=True, export_apply=True)
    print("@car", car_id, tris, "tris", os.path.getsize(path) // 1024, "KB")


if __name__ == "__main__":
    out = sys.argv[1]
    os.makedirs(out, exist_ok=True)
    for car_id, d in DESIGNS.items():
        build_car(car_id, d, out)
    os._exit(0)
