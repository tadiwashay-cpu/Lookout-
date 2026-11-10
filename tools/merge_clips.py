"""Swap individual clips in a converted character without its source packs.

    python merge_clips.py CURRENT.glb OLD.glb MOCAP_WALK.fbx OUT.glb

Keeps every clip in CURRENT.glb except `idle_unarmed` (taken from OLD.glb,
same skeleton) and `walk` (one in-place gait cycle cut from a Mixamo mocap
take, see apply_rpg_anims.mocap_walk). Writes OUT.json with the walk speed.
"""
import bpy, json, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from apply_rpg_anims import import_glb, mocap_walk, FPS
from mathutils import Quaternion, Vector


def main(current, old, walk_fbx, out):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.render.fps = FPS
    tgt, objs, actions = import_glb(current)
    for track in list(tgt.animation_data.nla_tracks):
        tgt.animation_data.nla_tracks.remove(track)
    keep = []
    for a in actions:
        if a.name in ("idle_unarmed", "walk"):
            bpy.data.actions.remove(a)
        else:
            keep.append(a)
    old_rig, old_objs, old_actions = import_glb(old)
    idle = next(a for a in old_actions if a.name == "idle_unarmed")
    idle.use_fake_user = True
    keep.append(idle)
    for o in old_objs:
        bpy.data.objects.remove(o, do_unlink=True)
    for a in old_actions:
        if a is not idle:
            bpy.data.actions.remove(a)
    idle.name = "idle_unarmed"
    walk, length, speed = mocap_walk(walk_fbx, tgt, tgt.data.bones, tgt.matrix_world)
    keep.append(walk)
    for pb in tgt.pose.bones:
        pb.rotation_mode = 'QUATERNION'
        pb.rotation_quaternion = Quaternion()
        pb.location = Vector()
    for a in keep:
        track = tgt.animation_data.nla_tracks.new()
        track.name = a.name
        track.strips.new(a.name, 0, a)
        track.mute = True
    bpy.ops.export_scene.gltf(
        filepath=out, export_format='GLB', export_animations=True,
        export_animation_mode='NLA_TRACKS', export_force_sampling=False,
        export_yup=True, export_apply=False, export_skins=True,
        export_morph=False, export_def_bones=False)
    json.dump({"walk": {"length": length, "ground_speed": speed}}, open(os.path.splitext(out)[0] + ".json", "w"))
    print("@merged", out, len(keep), "clips")
    os._exit(0)


if __name__ == "__main__":
    main(*sys.argv[1:5])
