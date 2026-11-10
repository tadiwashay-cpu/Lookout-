"""Swap a character's clips for the Explosive "RPG Animations" (unarmed) set.

    python apply_rpg_anims.py RPG_Unarmed.glb RPG_Unarmed_RM.glb CHARACTER.glb OUT.glb

Keeps only the shooter-pack gun clips already in CHARACTER.glb (pistol_*,
shotgun_*: ZenXChaos ThirdPersonShooter set) and replaces everything else
with the RPG pack, retargeted onto the Mixamo-named skeleton:
  * limbs aim at where the source limb points (works across rest poses)
  * spine, neck, head, hands, feet copy the source's world-space rotation
    change from its rest pose
  * hips copy the movement, scaled by hip height
Also writes OUT.json with clip length and ground speed (measured on the
root-motion version) so the game can match foot speed.
"""
import bpy, json, os, sys
from mathutils import Matrix, Quaternion, Vector

FPS = 30
KEEP = {"pistol_idle", "pistol_walk", "pistol_fire", "pistol_reload", "shotgun_idle", "shotgun_walk"}

# our clip name <- RPG action name (without the "Unarmed" prefix)
CLIPS = {
    "idle_unarmed": "Idle", "fight_idle": "IdleAlert1",
    "walk": "StrafeForward", "walk_back_unarmed": "StrafeBackward",
    "strafe_left_unarmed": "StrafeLeft", "strafe_right_unarmed": "StrafeRight",
    "run_unarmed": "RunForward", "run_back": "RunBackward",
    "strafe_left_run": "RunLeft", "strafe_right_run": "RunRight", "sprint": "Sprint",
    "jump": "Jump", "jump_unarmed": "Jump", "jump_big": "Jump", "falling": "Fall", "fall": "Fall", "land": "Land",
    "punch_1": "AttackL1", "punch_2": "AttackR1", "punch_3": "AttackL2", "punch_heavy": "AttackR3",
    "boxing": "AttackR2", "kick_front": "AttackKickR1", "kick_round": "AttackKickL1", "flying_kick": "AttackL3",
    "block": "Block", "block_hit": "BlockGetHit1", "hit_unarmed": "GetHitF1", "hit": "GetHitF1",
    "hit_back": "GetHitB1", "death": "Death1", "death_front": "Death1", "death_back": "KnockbackBack1",
    "ko_loser": "Knockdown1", "getup": "Getup1", "ko_winner": "Boost1", "stunned": "Stunned",
    "dodge_left": "DodgeLeft", "dodge_right": "DodgeRight", "dodge_back": "DodgeBackward",
    "roll": "RollForward", "turn_left": "TurnLeft90", "turn_right": "TurnRight90",
    "throw_grenade": "AttackR2", "pickup": "Pickup",
}

# Mixamo short name <- RPG bone
BONES = {"Hips": "B_Pelvis", "Spine": "B_Spine", "Spine1": "B_Spine1", "Spine2": "B_Spine2",
         "Neck": "B_Neck", "Head": "B_Head"}
for side, s in (("Left", "L"), ("Right", "R")):
    BONES.update({f"{side}Shoulder": f"B_{s}_Clavicle", f"{side}Arm": f"B_{s}_UpperArm",
                  f"{side}ForeArm": f"B_{s}_Forearm", f"{side}Hand": f"B_{s}_Hand",
                  f"{side}UpLeg": f"B_{s}_Thigh", f"{side}Leg": f"B_{s}_Calf",
                  f"{side}Foot": f"B_{s}_Foot", f"{side}ToeBase": f"B_{s}_Toe0"})
    for i, finger in enumerate(("Thumb", "Index", "Middle", "Ring", "Pinky")):
        for j, suffix in enumerate(("", "1", "2")):
            name = f"B_{s}_Finger{i}{suffix}"
            if s == "R" and i == 0 and suffix:
                name = f"B_R_Finger0.00{j}"   # the pack's right thumb is named oddly
            BONES[f"{side}Hand{finger}{j + 1}"] = name
# Limbs aim at their child (direction), the rest copy rotation deltas.
AIM = {"LeftArm": "LeftForeArm", "LeftForeArm": "LeftHand", "RightArm": "RightForeArm",
       "RightForeArm": "RightHand", "LeftUpLeg": "LeftLeg", "LeftLeg": "LeftFoot",
       "RightUpLeg": "RightLeg", "RightLeg": "RightFoot", "LeftShoulder": "LeftArm",
       "RightShoulder": "RightArm"}
LOOP = {"idle_unarmed", "fight_idle", "walk", "walk_back_unarmed", "strafe_left_unarmed", "strafe_right_unarmed",
        "run_unarmed", "run_back", "strafe_left_run", "strafe_right_run", "sprint", "falling", "block", "stunned"}


def import_glb(path):
    before = set(bpy.data.objects)
    actions_before = set(bpy.data.actions)
    bpy.ops.import_scene.gltf(filepath=path)
    new = [o for o in bpy.data.objects if o not in before]
    rig = next(o for o in new if o.type == 'ARMATURE')
    return rig, new, [a for a in bpy.data.actions if a not in actions_before]


def use_action(rig, action):
    rig.animation_data_create()
    rig.animation_data.action = action
    if hasattr(rig.animation_data, "action_slot") and action.slots:
        rig.animation_data.action_slot = action.slots[0]


def sample(rig, action, bones):
    use_action(rig, action)
    start, end = action.frame_range
    n = int(round(end - start)) + 1
    mw = rig.matrix_world
    out = {b: [] for b in bones if b in rig.pose.bones}
    for f in range(n):
        bpy.context.scene.frame_set(int(start) + f)
        for b in out:
            out[b].append(mw @ rig.pose.bones[b].matrix)
    return n, out


def ground_speeds(rm_path):
    """Hips travel per second on the root-motion version of each clip."""
    rig, objs, actions = import_glb(rm_path)
    speeds = {}
    for action in actions:
        name = action.name.replace("Unarmed", "", 1)
        n, frames = sample(rig, action, ["B_Pelvis"])
        p = frames["B_Pelvis"]
        travel = (Vector((p[-1].translation.x, p[-1].translation.y, 0)) - Vector((p[0].translation.x, p[0].translation.y, 0))).length
        speeds[name] = (round(max(n - 1, 1) / FPS, 3), round(travel / max((n - 1) / FPS, 0.01), 3))
    rig.animation_data.action = None
    for o in objs:
        bpy.data.objects.remove(o, do_unlink=True)
    for a in actions:
        bpy.data.actions.remove(a)
    return speeds


def main(src_path, rm_path, char_path, out_path):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.render.fps = FPS
    speeds = ground_speeds(rm_path)
    tgt, tgt_objs, tgt_actions = import_glb(char_path)
    # Drop every clip except the shooter-pack gun set.
    kept = []
    tgt.animation_data_create()
    for track in list(tgt.animation_data.nla_tracks):
        tgt.animation_data.nla_tracks.remove(track)
    for a in tgt_actions:
        if a.name in KEEP:
            kept.append(a)
        else:
            bpy.data.actions.remove(a)
    src, src_objs, src_actions = import_glb(src_path)
    by_name = {a.name.replace("Unarmed", "", 1): a for a in src_actions}

    mw, mw_inv = tgt.matrix_world, tgt.matrix_world.inverted()
    tbones = tgt.data.bones
    pre = "mixamorig:"
    mapped = {pre + m: s for m, s in BONES.items() if pre + m in tbones and s in src.data.bones}
    # The RPG character faces +Y in Blender, Mixamo rigs face -Y: turn the
    # source round 180 degrees so both look the same way before comparing.
    flip = Matrix.Rotation(3.141592653589793, 4, 'Z')
    src_rest = {b.name: flip @ src.matrix_world @ b.matrix_local for b in src.data.bones}
    tgt_rest = {b.name: mw @ b.matrix_local for b in tbones}
    scale = tgt_rest[pre + "Hips"].translation.z / max(src_rest["B_Pelvis"].translation.z, 1e-4)
    # Each aimed bone's direction to its child, in the bone's own rest frame.
    local_dir = {}
    for short, child in AIM.items():
        if pre + short in tbones and pre + child in tbones:
            b0 = tbones[pre + short]
            d = (tbones[pre + child].head_local - b0.head_local).normalized()
            local_dir[pre + short] = b0.matrix_local.to_3x3().inverted() @ d
    for pb in tgt.pose.bones:
        pb.rotation_mode = 'QUATERNION'
    json_out = {}
    made = []
    cache = {}
    for clip, rpg in CLIPS.items():
        action_src = by_name.get(rpg)
        if action_src is None:
            print("@missing", rpg)
            continue
        if rpg not in cache:
            n0, raw = sample(src, action_src, list(set(mapped.values())) + ["Motion"])
            # The pack turns its "Motion" root during clips; measure every
            # bone relative to it so the body faces forward like the rest pose.
            if "Motion" in raw:
                motion_rest = src_rest["Motion"]
                for b in raw:
                    if b == "Motion":
                        continue
                    raw[b] = [motion_rest @ (flip @ raw["Motion"][i]).inverted() @ flip @ m for i, m in enumerate(raw[b])]
            else:
                raw = {b: [flip @ m for m in v] for b, v in raw.items()}
            cache[rpg] = (n0, raw)
        n, frames = cache[rpg]
        action = bpy.data.actions.new(clip)
        action.use_fake_user = True
        use_action(tgt, action)
        prev = {}
        for fi in range(n):
            pose = {}
            for bone in tbones:   # parents before children
                name, parent = bone.name, bone.parent
                base = (pose[parent.name] @ parent.matrix_local.inverted() @ bone.matrix_local) if parent else bone.matrix_local.copy()
                sname = mapped.get(name)
                if sname is None:
                    pose[name] = base
                    continue
                short = name[len(pre):]
                s_now = frames[sname][fi]
                child = AIM.get(short)
                if child and pre + child in mapped and name in local_dir:
                    want = frames[mapped[pre + child]][fi].translation - s_now.translation
                    want_arm = (mw_inv.to_3x3() @ want).normalized()
                    current = base.to_3x3() @ Vector((0, 1, 0))
                    # keep the source's twist about the limb as well
                    delta = s_now.to_3x3().normalized() @ src_rest[sname].to_3x3().normalized().inverted()
                    rot0 = mw_inv.to_3x3().normalized() @ delta @ tgt_rest[name].to_3x3().normalized()
                    aim_now = rot0 @ local_dir[name]
                    rot = aim_now.rotation_difference(want_arm).to_matrix() @ rot0
                else:
                    delta = s_now.to_3x3().normalized() @ src_rest[sname].to_3x3().normalized().inverted()
                    rot = mw_inv.to_3x3().normalized() @ delta @ tgt_rest[name].to_3x3().normalized()
                translation = base.translation
                if short == "Hips":
                    offset = (s_now.translation - src_rest[sname].translation) * scale
                    translation = mw_inv @ (tgt_rest[name].translation + offset)
                matrix = Matrix.Translation(translation) @ rot.to_4x4()
                pose[name] = matrix
                q = (base.inverted() @ matrix).to_quaternion()
                if name in prev:
                    q.make_compatible(prev[name])
                prev[name] = q
                pb = tgt.pose.bones[name]
                pb.rotation_quaternion = q
                pb.keyframe_insert("rotation_quaternion", frame=fi)
                if short == "Hips":
                    pb.location = (base.inverted() @ matrix).translation
                    pb.keyframe_insert("location", frame=fi)
        tgt.animation_data.action = None
        made.append(action)
        length, speed = speeds.get(rpg, (round((n - 1) / FPS, 3), 0.0))
        json_out[clip] = {"length": length, "ground_speed": speed, "loop": clip in LOOP}
        print("@clip", clip, "<-", rpg, n)
    for pb in tgt.pose.bones:
        pb.rotation_quaternion = Quaternion()
        pb.location = Vector()
    for o in src_objs:
        bpy.data.objects.remove(o, do_unlink=True)
    for action in made + kept:
        track = tgt.animation_data.nla_tracks.new()
        track.name = action.name
        track.strips.new(action.name, 0, action)
        track.mute = True
    bpy.ops.export_scene.gltf(
        filepath=out_path, export_format='GLB', export_animations=True,
        export_animation_mode='NLA_TRACKS', export_force_sampling=False,
        export_yup=True, export_apply=False, export_skins=True,
        export_morph=False, export_def_bones=False,
    )
    with open(os.path.splitext(out_path)[0] + ".json", "w") as f:
        json.dump(json_out, f, indent=1)
    print("@done", out_path, len(made), "rpg +", len(kept), "gun clips")
    os._exit(0)


if __name__ == "__main__":
    main(*sys.argv[1:5])
