"""UniRig output -> game-ready character: humanoid bone names (Godot
SkeletonProfileHumanoid), facing -Y in Blender (+Z in Godot), 1.8 m tall.

    python prepare_hero.py IN_unirig.glb OUT.glb
"""
import bpy, sys, os, math
from mathutils import Matrix, Vector
src, out = sys.argv[-2], sys.argv[-1]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
for o in list(bpy.data.objects):
    if o.type == 'MESH' and o.parent is None:
        bpy.data.objects.remove(o, do_unlink=True)    # importer's bone-shape helper
arm = next(o for o in bpy.data.objects if o.type == 'ARMATURE')
mesh = next(o for o in bpy.data.objects if o.type == 'MESH')
B = arm.data.bones
def head(n): return arm.matrix_world @ B[n].head_local
# Which arm/leg chain is the character's left? Facing +X (UniRig/Tripo), left is +Y.
left_arm, right_arm = ("bone_6", "bone_25") if head("bone_6").y > head("bone_25").y else ("bone_25", "bone_6")
left_leg, right_leg = ("bone_44", "bone_48") if head("bone_44").y > head("bone_48").y else ("bone_48", "bone_44")
def chain(start, n):
    names, b = [start], B[start]
    for _ in range(n - 1):
        kids = [c for c in b.children]
        b = kids[0] if len(kids) == 1 else None
        if b is None: break
        names.append(b.name)
    return names
names = {"bone_0": "Hips", "bone_1": "Spine", "bone_2": "Chest", "bone_3": "UpperChest", "bone_4": "Neck", "bone_5": "Head"}
for side, root in (("Left", left_arm), ("Right", right_arm)):
    sh = B[root]; up = sh.children[0]; lo = up.children[0]; hand = lo.children[0]
    names[sh.name] = side + "Shoulder"; names[up.name] = side + "UpperArm"; names[lo.name] = side + "LowerArm"; names[hand.name] = side + "Hand"
    # Fingers: order around the hand from thumb (nearest the front) to little finger.
    fingers = sorted(hand.children, key=lambda f: -(arm.matrix_world @ f.head_local).x)
    labels = ["Thumb", "Index", "Middle", "Ring", "Little"]
    for label, f in zip(labels, fingers):
        parts = ["Metacarpal", "Proximal", "Distal"] if label == "Thumb" else ["Proximal", "Intermediate", "Distal"]
        b = f
        for p in parts:
            names[b.name] = side + label + p
            if not b.children: break
            b = b.children[0]
for side, root in (("Left", left_leg), ("Right", right_leg)):
    seq = chain(root, 4)
    for n, label in zip(seq, ["UpperLeg", "LowerLeg", "Foot", "Toes"]):
        names[n] = side + label
for b in arm.data.bones:
    if b.name in names:
        b.name = names[b.name]
for g in mesh.vertex_groups:
    pass   # Blender renames vertex groups with the bones
print("@named", len(names), "of", len(arm.data.bones))
# Face -Y, stand on z=0, 1.8 m.
bpy.context.view_layer.objects.active = arm
arm.select_set(True); mesh.select_set(True)
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
import numpy as np
v = np.array([(mesh.matrix_world @ x.co)[:] for x in mesh.data.vertices])
h = v[:, 2].max() - v[:, 2].min()
s = 1.8 / h
arm.matrix_world = Matrix.Rotation(-math.pi / 2, 4, 'Z') @ Matrix.Scale(s, 4) @ Matrix.Translation(Vector((0, 0, -v[:, 2].min())))
bpy.context.view_layer.update()
bpy.ops.object.select_all(action='DESELECT')
arm.select_set(True); mesh.select_set(True); bpy.context.view_layer.objects.active = arm
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
arm.name = "Nash"; mesh.name = "NashBody"
for m in mesh.data.materials:
    if m and m.use_nodes:
        bsdf = next((n for n in m.node_tree.nodes if n.type == 'BSDF_PRINCIPLED'), None)
        if bsdf:
            bsdf.inputs["Metallic"].default_value = 0.0
            bsdf.inputs["Roughness"].default_value = 0.8
for img in bpy.data.images:
    if img.size[0] > 1024: img.scale(1024, 1024)
for p in mesh.data.polygons: p.use_smooth = True
v = np.array([(mesh.matrix_world @ x.co)[:] for x in mesh.data.vertices])
print("@bounds", v.min(0).round(2), v.max(0).round(2))
print("@hand", [(b.name, [round(c, 2) for c in arm.matrix_world @ b.head_local]) for b in arm.data.bones if b.name in ("LeftHand", "RightHand", "LeftFoot", "Head")])
bpy.ops.export_scene.gltf(filepath=out, export_format='GLB', export_animations=False, export_skins=True,
                          export_image_format='JPEG', export_jpeg_quality=88)
print("@saved", out, os.path.getsize(out) // 1024, "KB")
os._exit(0)
