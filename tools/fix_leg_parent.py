"""Re-parent the thighs to the hips (Quaternius women's rig has them on Root,
so legs ignored pelvis rotation and looked warped in big moves).

    python fix_leg_parent.py IN.glb OUT.glb
"""
import bpy, os, sys

src, out = sys.argv[-2], sys.argv[-1]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
arm = next(o for o in bpy.data.objects if o.type == 'ARMATURE')
before = {b.name: (b.parent.name if b.parent else None) for b in arm.data.bones}
bpy.context.view_layer.objects.active = arm
bpy.ops.object.mode_set(mode='EDIT')
eb = arm.data.edit_bones
hips = eb.get("mixamorig:Hips")
changed = []
for side in ("Left", "Right"):
    leg = eb.get("mixamorig:%sUpLeg" % side)
    if leg and hips and leg.parent != hips:
        leg.use_connect = False
        leg.parent = hips
        changed.append(leg.name)
bpy.ops.object.mode_set(mode='OBJECT')
print("@parents", {k: before[k] for k in ("mixamorig:LeftUpLeg", "mixamorig:RightUpLeg") if k in before}, "changed", changed)
has_anim = bool(bpy.data.actions)
bpy.ops.export_scene.gltf(filepath=out, export_format='GLB', export_animations=False,
                          export_yup=True, export_apply=False, export_skins=True, export_morph=False)
print("@saved", out)
os._exit(0)
