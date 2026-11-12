"""Poly Haven prop -> phone GLB: join, decimate to a triangle budget, 512px textures."""
import bpy, sys, os, glob
src_dir, out_dir = sys.argv[-2], sys.argv[-1]
BUDGET = {"fire_hydrant": 1800, "concrete_road_barrier": 1200, "boulder_01": 1500, "rock_moss_set_01": 3000,
          "dutch_ship_medium": 14000, "drill_press_01": 3000, "metal_trash_can": 2000, "exterior_aircon_unit": 2500,
          "CoffeeCart_01": 4000, "cardboard_box_01": 600, "ceiling_fan": 2500, "bar_chair_round_01": 2500,
          "industrial_storage_cart": 3000, "hanging_industrial_lamp": 2000, "metal_tool_chest": 3000, "stick_grenade": 1200}
for d in sorted(glob.glob(os.path.join(src_dir, "*"))):
    name = os.path.basename(d)
    if name == "fir_sapling_medium":
        continue
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=os.path.join(d, name + ".gltf"))
    meshes = [o for o in bpy.data.objects if o.type == 'MESH']
    budget = BUDGET.get(name, 5000)
    total = 0
    for o in meshes:
        tris = sum(len(p.vertices) - 2 for p in o.data.polygons)
        total += tris
    for o in meshes:
        tris = sum(len(p.vertices) - 2 for p in o.data.polygons)
        if total > budget and tris > 50:
            m = o.modifiers.new("dec", 'DECIMATE'); m.ratio = max(budget / total, 0.005)
            bpy.context.view_layer.objects.active = o
            bpy.ops.object.modifier_apply(modifier=m.name)
    after = sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in meshes)
    for img in bpy.data.images:
        if img.size[0] > 512:
            img.scale(512, max(1, int(512 * img.size[1] / img.size[0])))
    out = os.path.join(out_dir, name.lower() + ".glb")
    bpy.ops.export_scene.gltf(filepath=out, export_format='GLB', export_image_format='JPEG', export_jpeg_quality=85)
    print("@", name, total, "->", after, os.path.getsize(out) // 1024, "KB")
os._exit(0)
