"""(bpy) Export selected guns from a weapons-pack FBX as individual GLBs.
Each gun: barrel toward Godot -Z, origin at the pistol grip (where the right
hand goes), plus 'Muzzle' and 'Support' (left-hand) marker nodes.
Usage: python export_weapons.py Weapons.fbx OUT_DIR"""
import json, sys
import bpy, bmesh, mathutils

GUNS = {  # pack object name -> (game id, class)
    "AK47": ("ak47", "rifle"), "M16A4": ("m16a4", "rifle"), "ScarH": ("scar_h", "rifle"), "G36": ("g36", "rifle"),
    "Mp5K": ("mp5k", "smg"), "Uzi": ("uzi", "smg"), "P90": ("p90", "smg"),
    "Glock17": ("glock17", "pistol"), "Deagle": ("deagle", "pistol"),
    "Spas_12": ("spas12", "shotgun"), "L115_Awp": ("awp", "sniper"), "M249": ("m249", "lmg"),
}

src, out_dir = sys.argv[1], sys.argv[2]
report = {}
for pack_name, (gun_id, kind) in GUNS.items():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.fbx(filepath=src)
    root = bpy.data.objects[pack_name]
    keep = [root] + [c for c in root.children_recursive if c.type == 'MESH']
    world = {obj.name: obj.matrix_world.copy() for obj in keep}   # before parents go away
    for obj in list(bpy.data.objects):
        if obj not in keep:
            bpy.data.objects.remove(obj, do_unlink=True)
    for obj in keep:
        obj.parent = None
        obj.matrix_world = world[obj.name]
    # Bake transforms and join into one mesh
    for obj in keep:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = root
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    mag_verts = []
    for obj in keep:
        if "agazine" in obj.name:
            mag_verts += [v.co.copy() for v in obj.data.vertices]
    bpy.ops.object.join()
    gun = bpy.context.view_layer.objects.active
    gun.name = gun_id
    verts = [v.co.copy() for v in gun.data.vertices]
    xs = [v.x for v in verts]; ys = [v.y for v in verts]; zs = [v.z for v in verts]
    y0, y1 = min(ys), max(ys)
    length = y1 - y0
    def band(lo, hi):
        return [v for v in verts if lo <= v.y <= hi]
    end_a = band(y0, y0 + length * 0.12)
    end_b = band(y1 - length * 0.12, y1)
    height = lambda vs: (max(v.z for v in vs) - min(v.z for v in vs)) if vs else 9
    muzzle_at_min = height(end_a) < height(end_b)
    sign = -1.0 if muzzle_at_min else 1.0          # +1: muzzle at max Y
    muzzle_y = y0 if muzzle_at_min else y1
    # Distance from the muzzle along the barrel, 0..1
    t = lambda v: (v.y - muzzle_y) * sign * -1.0 / length
    mag_set = {(round(v.x, 4), round(v.y, 4), round(v.z, 4)) for v in mag_verts}
    body = [v for v in verts if (round(v.x, 4), round(v.y, 4), round(v.z, 4)) not in mag_set]
    center_z = sorted(v.z for v in body)[len(body) // 2]
    # Pistol grip: lowest part of the body in the rear section (pistols: anywhere)
    lo_t, hi_t = (0.25, 1.0) if kind == "pistol" else (0.4, 0.85)
    slices = {}
    for v in body:
        tv = t(v)
        if lo_t <= tv <= hi_t:
            key = round(tv * 40)
            slices[key] = min(slices.get(key, 9), v.z)
    grip_key = min(slices, key=slices.get)
    grip_t = grip_key / 40.0
    grip_bottom = slices[grip_key]
    grip_y = muzzle_y - sign * grip_t * length
    grip = mathutils.Vector((sum(xs) / len(xs), grip_y, grip_bottom + (center_z - grip_bottom) * 0.62))
    support_t = 0.3 if kind in ("rifle", "lmg", "sniper", "shotgun") else (0.45 if kind == "smg" else grip_t)
    support_y = muzzle_y - sign * support_t * length
    support = mathutils.Vector((grip.x, support_y, center_z - 0.02))
    muzzle = mathutils.Vector((grip.x, muzzle_y, center_z))
    # muzzle height: centre of the front slice
    front = end_a if muzzle_at_min else end_b
    muzzle.z = (max(v.z for v in front) + min(v.z for v in front)) / 2
    # Move grip to origin; point the muzzle along +Y (Blender) == -Z (glTF/Godot)
    xform = mathutils.Matrix.Translation(-grip)
    if sign < 0:
        xform = mathutils.Matrix.Rotation(3.14159265, 4, 'Z') @ xform
    gun.data.transform(xform)
    for name, p in (("Muzzle", muzzle), ("Support", support)):
        marker = bpy.data.objects.new(name, None)
        marker.location = xform @ p
        bpy.context.scene.collection.objects.link(marker)
        marker.parent = gun
    bpy.ops.export_scene.gltf(filepath=f"{out_dir}/{gun_id}.glb", export_format='GLB', export_yup=True)
    report[gun_id] = {"class": kind, "length": round(length, 3), "tris": sum(len(p.vertices) - 2 for p in gun.data.polygons),
                      "muzzle": [round(c, 3) for c in (xform @ muzzle)], "support": [round(c, 3) for c in (xform @ support)]}
    print("@", gun_id, report[gun_id])
json.dump(report, open(f"{out_dir}/weapons.json", "w"), indent=1)
