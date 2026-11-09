"""(bpy) 1) M4A1 OBJ -> rifle GLB: grip at origin, barrel toward Godot -Z,
'Muzzle' marker node, PBR-ish materials.  2) Character-select portraits.
Usage: python make_rifle_and_portraits.py M4A1.obj OUT_DIR X_BOT.fbx Y_BOT.fbx IDLE.fbx"""
import math, sys
import bpy, mathutils

obj_path, out_dir, x_bot, y_bot, idle_fbx = sys.argv[1:6]

# ----------------------------------------------------------------- rifle
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.wm.obj_import(filepath=obj_path)
parts = [o for o in bpy.data.objects if o.type == 'MESH']
for o in parts:
    o.select_set(True)
bpy.context.view_layer.objects.active = parts[0]
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
bpy.ops.object.join()
rifle = bpy.context.view_layer.objects.active
rifle.name = "M4A1"
# Grip (Blender space): x ~ -0.58, z ~ -0.06. Move it to the origin.
grip = mathutils.Vector((-0.58, 0.0, -0.06))
rifle.data.transform(mathutils.Matrix.Translation(-grip))
# Barrel currently +X; glTF -Z == Blender +Y, so rotate +90 deg about Z.
rifle.data.transform(mathutils.Matrix.Rotation(math.radians(90), 4, 'Z'))
looks = {
    "Black_Metal": ((0.035, 0.035, 0.038), 0.85, 0.38),
    "Grey_Metal": ((0.22, 0.22, 0.23), 0.9, 0.32),
    "Black_Plastic": ((0.03, 0.03, 0.03), 0.0, 0.7),
    "Grey_Plastic": ((0.09, 0.09, 0.09), 0.0, 0.65),
}
for mat in rifle.data.materials:
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    color, metal, rough = looks.get(mat.name, ((0.05, 0.05, 0.05), 0.5, 0.5))
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Metallic"].default_value = metal
    bsdf.inputs["Roughness"].default_value = rough
muzzle = bpy.data.objects.new("Muzzle", None)
muzzle.location = mathutils.Vector((0.0, 0.58, 0.06))   # muzzle tip after the moves above
bpy.context.scene.collection.objects.link(muzzle)
muzzle.parent = rifle
bpy.ops.export_scene.gltf(filepath=f"{out_dir}/m4a1.glb", export_format='GLB', export_yup=True)
print("@rifle", [round(d, 3) for d in rifle.dimensions], "tris", sum(len(p.vertices) - 2 for p in rifle.data.polygons))

# ------------------------------------------------------------- portraits
def portrait(fbx, out_png, tint):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    bpy.ops.import_scene.fbx(filepath=fbx)
    rig = next(o for o in bpy.data.objects if o.type == 'ARMATURE')
    prefix = rig.data.bones[0].name.split(":")[0] + ":"
    before = set(bpy.data.objects)
    bpy.ops.import_scene.fbx(filepath=idle_fbx)
    anim_rig = next(o for o in bpy.data.objects if o not in before and o.type == 'ARMATURE')
    for b in anim_rig.data.bones:
        b.name = prefix + b.name.split(":", 1)[-1]
    action = anim_rig.animation_data.action
    for o in [o for o in bpy.data.objects if o not in before]:
        bpy.data.objects.remove(o, do_unlink=True)
    rig.animation_data_create()
    rig.animation_data.action = action
    try:
        rig.animation_data.action_slot = action.slots[0]
    except Exception:
        pass
    scene.frame_set(20)
    cam_data = bpy.data.cameras.new("cam"); cam_data.lens = 50
    cam = bpy.data.objects.new("cam", cam_data); scene.collection.objects.link(cam)
    cam.location = (0.7, -3.9, 1.25)
    direction = mathutils.Vector((0.15, 0.0, 0.95)) - cam.location
    cam.rotation_euler = direction.to_track_quat('-Z', 'Y').to_euler()
    scene.camera = cam
    for name, loc, energy, color in [("key", (2.5, -2.5, 3.5), 900, (1.0, 0.93, 0.85)),
                                     ("rim", (-2.0, 2.0, 2.5), 700, tint), ("fill", (-3, -2, 1.2), 180, (0.8, 0.85, 1.0))]:
        ld = bpy.data.lights.new(name, 'AREA'); ld.energy = energy; ld.color = color; ld.size = 2.0
        lo = bpy.data.objects.new(name, ld); lo.location = loc; scene.collection.objects.link(lo)
        lo.rotation_euler = (mathutils.Vector((0, 0, 1.0)) - lo.location).to_track_quat('-Z', 'Y').to_euler()
    world = bpy.data.worlds.new("w"); scene.world = world; world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = (0.02, 0.022, 0.025, 1)
    scene.render.engine = 'CYCLES'; scene.cycles.device = 'CPU'; scene.cycles.samples = 48
    scene.render.resolution_x = 512; scene.render.resolution_y = 640
    scene.render.film_transparent = False
    scene.view_settings.view_transform = 'AgX'
    scene.render.filepath = out_png
    bpy.ops.render.render(write_still=True)
    print("@portrait", out_png)

portrait(x_bot, f"{out_dir}/x_bot_portrait.png", (1.0, 0.45, 0.3))
portrait(y_bot, f"{out_dir}/y_bot_portrait.png", (0.35, 0.65, 1.0))
