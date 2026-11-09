"""Convert a Mixamo-rigged character + Mixamo animation FBXs into one GLB.

Run with Blender's Python module (pip install bpy, Python 3.11):
    python convert_mixamo.py CHARACTER.fbx OUT.glb ANIM_DIR [ANIM_DIR ...] [--npc]

- Renames animation bones (mixamorig9:* ...) to the character's prefix so
  every clip drives the same skeleton (works for rigs with or without fingers).
- Strips horizontal root motion from clips the game moves itself.
- Names clips the way the game expects (CLIP_NAMES); a clip can be trimmed
  to a frame range (e.g. a calm idle cut from the end of Stop Walking).
- --npc: removes loose duplicate meshes and bone-parents loose hair meshes
  to the Head bone (for the Rigged Low Poly Man).
Writes OUT.json with each clip's length and ground speed.
"""
import json, os, re, sys
import bpy

# file stem -> list of (clip name, optional (first, last) frame range)
CLIP_NAMES = {
    # first pack (rifle set)
    "rifle_aiming_idle": [("idle", None)],
    "walking": [("walk", None)],
    "walking_backwards": [("walk_back", None)],
    "rifle_run": [("run", None)],
    "run_backwards": [("run_back", None)],
    "strafe_left": [("strafe_left", None)],
    "strafe_right": [("strafe_right", None)],
    "strafe_2": [("strafe_left_run", None)],      # measured: moves left
    "strafe": [("strafe_right_run", None)],       # measured: moves right
    "firing_rifle": [("fire", None)],
    "reloading": [("reload", None)],
    "toss_grenade": [("throw_grenade", None)],
    "hit_reaction": [("hit", None)],
    "turn_left": [("turn_left", None)],
    "turning_right_45_degrees": [("turn_right", None)],
    # second pack (unarmed + jumps)
    "Rifle_Jump": [("jump", None)],
    "Jump": [("jump_unarmed", None)],
    "Big_Jump": [("jump_big", None)],
    "Jumping_Down": [("fall", None)],
    "Walking_Backwards": [("walk_back_unarmed", None)],
    "Left_Strafe_Walking": [("strafe_left_unarmed", None)],
    "Right_Strafe_Walking": [("strafe_right_unarmed", None)],
    "Start_Walking": [("walk_start", None)],
    "Stop_Walking": [("walk_stop", None), ("idle_unarmed", (72, 91))],
    "Idle_To_Sprint": [("sprint_start", None)],
    "Punching": [("punch_1", None)],
    "Headbutt": [("punch_2", None)],
    "Hook_Punch": [("punch_3", None)],
    "Kicking": [("punch_heavy", None)],
    "Flying_Kick": [("flying_kick", None)],
    "Body_Block": [("block", None)],
    "Reaction": [("hit_unarmed", None)],
    "Dying": [("death", None)],
}
IN_PLACE = {"walk", "walk_back", "run", "run_back", "strafe_left", "strafe_right",
            "strafe_left_run", "strafe_right_run", "turn_left", "turn_right", "throw_grenade", "hit",
            "walk_back_unarmed", "strafe_left_unarmed", "strafe_right_unarmed", "walk_start", "walk_stop",
            "idle_unarmed", "sprint_start", "punch_1", "punch_2", "punch_3", "punch_heavy", "flying_kick",
            "block", "hit_unarmed", "jump_big", "fall", "jump_unarmed"}
FPS = 30.0


def fcurves(action):
    try:
        if action.fcurves:
            return list(action.fcurves)
    except Exception:
        pass
    out = []
    for layer in action.layers:
        for strip in layer.strips:
            for bag in strip.channelbags:
                out += list(bag.fcurves)
    return out


def stem(path):
    return re.sub(r"^[0-9a-f]{8}-", "", os.path.splitext(os.path.basename(path))[0])


def clean_npc(rig):
    """Keep only meshes deformed by the rig; hang loose hair on the head bone."""
    head = next((b.name for b in rig.data.bones if b.name.endswith("Head")), None)
    for obj in list(bpy.data.objects):
        if obj.type != 'MESH':
            continue
        skinned = any(m.type == 'ARMATURE' and m.object == rig for m in obj.modifiers)
        if skinned:
            continue
        if "hair" in obj.name.lower() and head:
            matrix = obj.matrix_world.copy()
            obj.parent = rig
            obj.parent_type = 'BONE'
            obj.parent_bone = head
            obj.matrix_world = matrix
        else:
            bpy.data.objects.remove(obj, do_unlink=True)


def main(char_path, out_path, anim_dirs, npc):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.render.fps = int(FPS)
    bpy.ops.import_scene.fbx(filepath=char_path)
    rig = next(o for o in bpy.data.objects if o.type == 'ARMATURE')
    prefix = rig.data.bones[0].name.split(":")[0] + ":"
    if npc:
        clean_npc(rig)
    for action in list(bpy.data.actions):
        bpy.data.actions.remove(action)

    clips = []   # (name, action, frame range)
    speeds = {}
    files = []
    for directory in anim_dirs:
        files += [os.path.join(directory, f) for f in sorted(os.listdir(directory)) if f.lower().endswith(".fbx")]
    for path in files:
        key = stem(path)
        if key not in CLIP_NAMES:
            continue
        for clip, frame_range in CLIP_NAMES[key]:
            before = set(bpy.data.objects)
            bpy.ops.import_scene.fbx(filepath=path)
            new_objects = [o for o in bpy.data.objects if o not in before]
            anim_rig = next(o for o in new_objects if o.type == 'ARMATURE')
            action = anim_rig.animation_data.action
            for bone in anim_rig.data.bones:
                bone.name = prefix + bone.name.split(":", 1)[-1]
            action.name = clip
            action.use_fake_user = True
            start, end = frame_range if frame_range else action.frame_range
            hips_path = f'pose.bones["{prefix}Hips"].location'
            travel = 0.0
            for fc in fcurves(action):
                if fc.data_path != hips_path or fc.array_index not in (0, 2):
                    continue
                keys = fc.keyframe_points
                travel = max(travel, abs(keys[-1].co[1] - keys[0].co[1]))
                if clip in IN_PLACE:
                    first = fc.evaluate(start)
                    for k in keys:
                        k.co[1] = first
                        k.handle_left[1] = first
                        k.handle_right[1] = first
            duration = max(end - start, 1.0) / FPS
            speeds[clip] = {"length": round(duration, 3), "ground_speed": round(travel * 0.01 / max((action.frame_range[1] - action.frame_range[0]) / FPS, 0.01), 3)}
            clips.append((clip, action, (start, end)))
            anim_rig.animation_data.action = None
            for o in new_objects:
                bpy.data.objects.remove(o, do_unlink=True)

    rig.animation_data_create()
    for clip, action, (start, end) in clips:
        track = rig.animation_data.nla_tracks.new()
        track.name = clip
        strip = track.strips.new(clip, int(start), action)
        strip.action_frame_start = start
        strip.action_frame_end = end
        track.mute = True
    rig.animation_data.action = None

    bpy.ops.export_scene.gltf(
        filepath=out_path, export_format='GLB', export_animations=True,
        export_animation_mode='NLA_TRACKS', export_force_sampling=True,
        export_frame_step=1, export_yup=True, export_apply=False,
        export_skins=True, export_morph=False, export_def_bones=False,
    )
    with open(os.path.splitext(out_path)[0] + ".json", "w") as f:
        json.dump(speeds, f, indent=1)
    print("@converted", out_path, len(clips), "clips:", sorted(speeds))


if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    main(args[0], args[1], args[2:], "--npc" in sys.argv)
