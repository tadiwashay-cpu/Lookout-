"""BVH takes from tools/gen_motion.py -> one GLB the game imports
(assets/animations/fight_gen.glb) plus timing data (fight_gen.json).

    python convert_motion.py BVH_DIR OUT.glb OUT.json

For each move it keeps the take with the most committed strike (furthest
reach of a hand or foot from the hips) and records when that happens, so
the game knows the frame a hit should land and can trim the wind-up.
"""
import bpy, glob, json, os, sys
from mathutils import Vector

src, out_glb, out_json = sys.argv[-3], sys.argv[-2], sys.argv[-1]
ENDS = ["LeftHand", "RightHand", "LeftFoot", "RightFoot"]
FPS = 20.0

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.context.scene.render.fps = int(FPS)
takes = {}
for path in sorted(glob.glob(os.path.join(src, "*.bvh"))):
    name, k = os.path.basename(path)[:-4].rsplit("_", 1)
    before = set(bpy.data.objects)
    bpy.ops.import_anim.bvh(filepath=path, axis_forward='-Z', axis_up='Y', rotate_mode='NATIVE', global_scale=1.0, frame_start=0, use_fps_scale=False, update_scene_fps=False, update_scene_duration=True)
    arm = [o for o in bpy.data.objects if o not in before][0]
    action = arm.animation_data.action
    f0, f1 = int(action.frame_range[0]), int(action.frame_range[1])
    # Reach of each limb end from the hips, per frame.
    best = (0.0, f0, "")
    rest = {}
    travel = 0.0
    start_hip = None
    for f in range(f0, f1 + 1):
        bpy.context.scene.frame_set(f)
        hips = arm.matrix_world @ arm.pose.bones["Hips"].head
        if start_hip is None:
            start_hip = hips.copy()
        travel = max(travel, (Vector((hips.x, hips.y, 0)) - Vector((start_hip.x, start_hip.y, 0))).length)
        for e in ENDS:
            p = arm.matrix_world @ arm.pose.bones[e].head
            d = Vector((p.x - hips.x, p.y - hips.y, 0)).length + max(p.z - hips.z, 0.0) * (0.6 if "Foot" in e else 0.2)
            if f == f0:
                rest[e] = d
            gain = d - rest[e]
            if gain > best[0]:
                best = (gain, f, e)
    takes.setdefault(name, []).append({"arm": arm, "action": action, "reach": best[0], "peak": best[1] / FPS, "limb": best[2],
                                         "length": (f1 - f0) / FPS, "travel": travel})

keep_arm = None
info = {}
for name, lst in takes.items():
    lst.sort(key=lambda t: -t["reach"])
    win = lst[0]
    win["action"].name = "Fx_" + name
    win["action"].use_fake_user = True
    info["Fx_" + name] = {"length": round(win["length"], 3), "peak": round(win["peak"], 3), "limb": win["limb"], "reach": round(win["reach"], 3), "travel": round(win["travel"], 3)}
    if keep_arm is None:
        keep_arm = win["arm"]
    for t in lst[1:]:
        bpy.data.actions.remove(t["action"])
for o in list(bpy.data.objects):
    if o is not keep_arm:
        bpy.data.objects.remove(o, do_unlink=True)
keep_arm.name = "Rig"
keep_arm.animation_data.action = None
keep_arm.data.pose_position = 'REST'
# A tiny skinned mesh so exporters write a proper skeleton.
mesh = bpy.data.meshes.new("Pin")
mesh.from_pydata([(0, 0, 0.9), (0.01, 0, 0.9), (0, 0.01, 0.9)], [], [(0, 1, 2)])
pin = bpy.data.objects.new("Pin", mesh)
bpy.context.scene.collection.objects.link(pin)
pin.parent = keep_arm
g = pin.vertex_groups.new(name="Hips")
g.add([0, 1, 2], 1.0, 'REPLACE')
pin.modifiers.new("Armature", 'ARMATURE').object = keep_arm
keep_arm.data.pose_position = 'POSE'
# Put every action on an NLA track so they all export.
for a in bpy.data.actions:
    if a.name.startswith("Fx_"):
        tr = keep_arm.animation_data.nla_tracks.new()
        tr.name = a.name
        tr.strips.new(a.name, 0, a)
bpy.ops.export_scene.gltf(filepath=out_glb, export_format='GLB', export_animations=True, export_animation_mode='NLA_TRACKS',
                          export_skins=True, export_force_sampling=True, export_frame_range=False)
json.dump(info, open(out_json, "w"), indent=1)
for k, v in info.items():
    print("@", k, v)
print("@saved", os.path.getsize(out_glb) // 1024, "KB")
os._exit(0)
