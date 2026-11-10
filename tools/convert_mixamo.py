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
from mathutils import Matrix, Vector, Quaternion

# --- Retargeting (tools/extract_fbx6_anim.py JSON, Y-up source facing +Z) ---
RETARGET_MAP = {
    "Pelvis": "Hips", "Spine1": "Spine", "Spine2": "Spine1", "Spine3": "Spine2", "Neck_Base": "Neck", "Head": "Head",
    "L_Clavicle": "LeftShoulder", "L_Arm": "LeftArm", "L_Forearm": "LeftForeArm", "L_Hand": "LeftHand",
    "R_Clavicle": "RightShoulder", "R_Arm": "RightArm", "R_Forearm": "RightForeArm", "R_Hand": "RightHand",
    "L_Thigh": "LeftUpLeg", "L_Shin": "LeftLeg", "L_Ankle": "LeftFoot",
    "R_Thigh": "RightUpLeg", "R_Shin": "RightLeg", "R_Ankle": "RightFoot",
}
# Limbs are retargeted by aiming each bone along the source bone direction
# (works across different rest poses: A-pose source, T-pose Mixamo target).
AIM_CHILD = {
    "L_Clavicle": "L_Arm", "L_Arm": "L_Forearm", "L_Forearm": "L_Hand", "L_Hand": "L_Middle1",
    "R_Clavicle": "R_Arm", "R_Arm": "R_Forearm", "R_Forearm": "R_Hand", "R_Hand": "R_Middle1",
    "L_Thigh": "L_Shin", "L_Shin": "L_Ankle", "L_Ankle": "L_Toes",
    "R_Thigh": "R_Shin", "R_Shin": "R_Ankle", "R_Ankle": "R_Toes",
}
# Source (x, y, z) Y-up facing +Z  ->  Blender Z-up facing -Y.
C = Matrix(((1, 0, 0), (0, 0, -1), (0, 1, 0)))
LOOP_RETARGET = {"idle_unarmed", "walk", "run_unarmed", "sprint", "falling", "pistol_idle", "pistol_walk", "shotgun_idle", "shotgun_walk"}


def _m(values):
    """12 floats (columns c0..c3) -> (3x3 rotation normalised, position)."""
    rot = Matrix(((values[0], values[3], values[6]), (values[1], values[4], values[7]), (values[2], values[5], values[8]))).normalized()
    return rot, Vector((values[9], values[10], values[11]))


def retarget_clips(rig, prefix, json_path):
    data = json.load(open(json_path))
    arm_mw = rig.matrix_world.copy()
    arm_rot = arm_mw.to_3x3().normalized()
    arm_inv = arm_mw.inverted()
    bones = rig.data.bones
    order = [b for b in bones if b.name.split(":", 1)[-1] in RETARGET_MAP.values()]   # parents before children
    tgt_of = {v: k for k, v in RETARGET_MAP.items()}
    hips_rest_world = arm_mw @ bones[prefix + "Hips"].head_local
    clips = []
    for clip, payload in data.items():
        rest = {k: _m(v) for k, v in payload["rest"].items()}
        frames = payload["frames"]
        n = len(frames)
        scale = hips_rest_world.z / max(rest["Pelvis"][1].y, 0.001)
        first = C @ _m(frames[0]["Pelvis"])[1]
        last = C @ _m(frames[-1]["Pelvis"])[1]
        action = bpy.data.actions.new(clip)
        action.use_fake_user = True
        rig.animation_data_create()
        rig.animation_data.action = action
        for pb in rig.pose.bones:
            pb.rotation_mode = 'QUATERNION'
        prev_q = {}
        for fi, frame in enumerate(frames):
            pose = {}
            for bone in order:
                short = bone.name.split(":", 1)[-1]
                src = tgt_of[short]
                rest_local = bone.matrix_local
                parent = bone.parent
                if parent is not None and parent.name in pose:
                    base = pose[parent.name] @ parent.matrix_local.inverted() @ rest_local
                else:
                    base = rest_local.copy()
                rot_now, pos_now = _m(frame[src])
                if src in AIM_CHILD and AIM_CHILD[src] in frame:
                    child_pos = _m(frame[AIM_CHILD[src]])[1]
                    direction = arm_rot.transposed() @ (C @ (child_pos - pos_now))
                    current = base.to_3x3() @ Vector((0, 1, 0))
                    swing = current.rotation_difference(direction.normalized()).to_matrix()
                    rot = swing @ base.to_3x3()
                else:
                    delta = rot_now @ rest[src][0].transposed()
                    delta_arm = arm_rot.transposed() @ C @ delta @ C.transposed() @ arm_rot
                    rot = delta_arm @ rest_local.to_3x3()
                translation = base.translation
                if short == "Hips":
                    p = C @ pos_now
                    t = fi / max(n - 1, 1)
                    drift = first.lerp(last, t) if clip in LOOP_RETARGET or n > 1 else first
                    world = Vector((hips_rest_world.x + (p.x - drift.x) * scale,
                                    hips_rest_world.y + (p.y - drift.y) * scale,
                                    p.z * scale))
                    translation = arm_inv @ world
                matrix = Matrix.Translation(translation) @ rot.to_4x4()
                pose[bone.name] = matrix
                basis = base.inverted() @ matrix
                pb = rig.pose.bones[bone.name]
                q = basis.to_quaternion()
                if bone.name in prev_q:
                    q.make_compatible(prev_q[bone.name])
                prev_q[bone.name] = q
                pb.rotation_quaternion = q
                pb.keyframe_insert("rotation_quaternion", frame=fi + 1)
                if short == "Hips":
                    pb.location = basis.translation
                    pb.keyframe_insert("location", frame=fi + 1)
        rig.animation_data.action = None
        for pb in rig.pose.bones:
            pb.rotation_quaternion = Quaternion()
            pb.location = Vector()
        clips.append((clip, action, (1, n)))
        print("@retargeted", clip, n, "frames")
    return clips

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
    # Combat pack (24 fps performances; frame ranges are in 30 fps scene frames)
    "FightingIdle_mixamo": [("fight_idle", (31, 91))],
    "Boxing_mixamo": [("boxing", (16, 106))],
    "BigFrontKick_mixamo": [("kick_front", (82, 148))],
    "RoundHouseKick_mixamo": [("kick_round", (199, 268))],
    "KnockOut_Loser_mixamo": [("ko_loser", (316, 406))],
    "KnockOut_Winner_mixamo": [("ko_winner", (481, 601))],
}
IN_PLACE = {"walk", "walk_back", "run", "run_back", "strafe_left", "strafe_right",
            "strafe_left_run", "strafe_right_run", "turn_left", "turn_right", "throw_grenade", "hit",
            "walk_back_unarmed", "strafe_left_unarmed", "strafe_right_unarmed", "walk_start", "walk_stop",
            "idle_unarmed", "sprint_start", "punch_1", "punch_2", "punch_3", "punch_heavy", "flying_kick",
            "block", "hit_unarmed", "jump_big", "fall", "jump_unarmed",
            "fight_idle", "boxing", "kick_front", "kick_round", "ko_loser", "ko_winner"}
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


def main(char_path, out_path, anim_dirs, npc, retarget_json=None):
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
    if retarget_json:
        clips += retarget_clips(rig, prefix, retarget_json)
    have = {c[0] for c in clips}
    files = []
    for directory in anim_dirs:
        files += [os.path.join(directory, f) for f in sorted(os.listdir(directory)) if f.lower().endswith(".fbx")]
    for path in files:
        key = stem(path)
        if key not in CLIP_NAMES:
            continue
        for clip, frame_range in CLIP_NAMES[key]:
            if clip in have:
                continue   # a retargeted clip of the same name wins
            before = set(bpy.data.objects)
            bpy.ops.import_scene.fbx(filepath=path)
            new_objects = [o for o in bpy.data.objects if o not in before]
            anim_rig = next(o for o in new_objects if o.type == 'ARMATURE')
            action = anim_rig.animation_data.action
            # The importer switches the scene to the file's frame rate (24 fps for
            # some packs). Rescale keys to 30 fps so every clip times correctly.
            scene = bpy.context.scene
            file_fps = scene.render.fps / scene.render.fps_base
            if abs(file_fps - FPS) > 0.01:
                k = FPS / file_fps
                for fc in fcurves(action):
                    for key in fc.keyframe_points:
                        key.co[0] = 1.0 + (key.co[0] - 1.0) * k
                        key.handle_left[0] = 1.0 + (key.handle_left[0] - 1.0) * k
                        key.handle_right[0] = 1.0 + (key.handle_right[0] - 1.0) * k
                    fc.update()
            scene.render.fps = int(FPS)
            scene.render.fps_base = 1.0
            for bone in anim_rig.data.bones:
                bone.name = prefix + bone.name.split(":", 1)[-1]
            # Hip translation is stored in the source rig's units; scale it to
            # this rig (the low-poly NPC's armature uses different units).
            src_hips = anim_rig.data.bones.get(prefix + "Hips")
            dst_hips = rig.data.bones.get(prefix + "Hips")
            unit = 1.0
            if src_hips and dst_hips and src_hips.head_local.length > 1e-4:
                unit = dst_hips.head_local.length / src_hips.head_local.length
            if abs(unit - 1.0) > 0.02:
                for fc in fcurves(action):
                    if fc.data_path.endswith('"].location'):
                        for key in fc.keyframe_points:
                            key.co[1] *= unit
                            key.handle_left[1] *= unit
                            key.handle_right[1] *= unit
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
    bpy.context.scene.render.fps = int(FPS)
    bpy.context.scene.render.fps_base = 1.0

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
    retarget = next((a.split("=", 1)[1] for a in sys.argv if a.startswith("--retarget=")), None)
    main(args[0], args[1], args[2:], "--npc" in sys.argv, retarget)
