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
import bpy, json, math, os, sys
from mathutils import Matrix, Quaternion, Vector

FPS = 30
KEEP = {"pistol_idle", "pistol_walk", "pistol_fire", "pistol_reload", "shotgun_idle", "shotgun_walk",
        "idle_unarmed"}   # calm standing idle (the pack's own idle is a fighting stance)

# our clip name <- RPG action name (without the "Unarmed" prefix)
CLIPS = {
    "fight_idle": "IdleAlert1",
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


KNEE_FORWARD = 0.8    # 0 = the pack's knock-kneed stance, 1 = knees straight ahead
HIP_KEEP = 0.5        # keep half of the pack's deep crouch (hips drop); feet stay planted


def adjust_hip_offset(offset):
    return Vector((offset.x, offset.y, offset.z * HIP_KEEP if offset.z < 0 else offset.z))


def solve_legs(frames, fi, mapped, tbones, mw, rig):
    """Two-bone leg solve on the target's bone lengths: the foot lands where
    the clip puts it (relative to the hips), but the knee is steered toward
    the front so the stylised inward-knee stance doesn't look twisted."""
    pre = "mixamorig:"
    out = {}
    forward = Vector((0, -1, 0))   # Mixamo rigs face -Y in Blender
    for side in ("Left", "Right"):
        up, low, foot = pre + side + "UpLeg", pre + side + "Leg", pre + side + "Foot"
        if not all(b in mapped and b in tbones for b in (up, low, foot)):
            continue
        H = frames[mapped[up]][fi].translation
        K = frames[mapped[low]][fi].translation
        F = frames[mapped[foot]][fi].translation
        P = frames[mapped[pre + "Hips"]][fi].translation
        scale = mw.to_3x3().to_scale()
        lt = ((tbones[low].head_local - tbones[up].head_local) * scale.x).length
        lc = ((tbones[foot].head_local - tbones[low].head_local) * scale.x).length
        # Hips raised (less crouch), thigh joint follows them, foot stays planted.
        hips_t = rig["tgt_hips"] + adjust_hip_offset(P - rig["src_hips"]) * rig["scale"]
        thigh_t = hips_t + (H - P) * rig["scale"]
        foot_t = rig["tgt_hips"] + (F - rig["src_hips"]) * rig["scale"]
        d = foot_t - thigh_t
        dist = min(d.length, (lt + lc) * 0.999)
        if dist < 1e-4:
            continue
        axis = d.normalized()
        d = axis * dist
        bend = (K - H) - axis * (K - H).dot(axis)
        fwd = forward - axis * forward.dot(axis)
        if bend.length < 1e-4:
            bend = fwd
        pole = bend.normalized().lerp(fwd.normalized(), KNEE_FORWARD).normalized()
        a = (lt * lt - lc * lc + dist * dist) / (2.0 * dist)
        h = max(lt * lt - a * a, 0.0) ** 0.5
        knee = axis * a + pole * h
        out[up] = knee
        out[low] = d - knee
    return out


def mocap_walk(path, tgt, tbones, mw, pre="mixamorig:"):
    """One clean gait cycle from a long Mixamo mocap take, in place, as 'walk'."""
    before = set(bpy.data.objects)
    acts_before = set(bpy.data.actions)
    bpy.ops.import_scene.fbx(filepath=path)
    new = [o for o in bpy.data.objects if o not in before]
    src = next(o for o in new if o.type == 'ARMATURE')
    action = next(a for a in bpy.data.actions if a not in acts_before)
    names = [b.name for b in src.data.bones if b.name in tbones]
    # Some Mixamo exports make the Hips the armature object itself: then the
    # hip motion is the object's own animation, so read its matrix every frame.
    hips_is_object = pre + "Hips" not in src.data.bones
    src.animation_data_create()
    src.animation_data.action = None
    bpy.context.view_layer.update()
    rest_mw = src.matrix_world.copy()
    rest = {b.name: rest_mw @ b.matrix_local for b in src.data.bones}
    if hips_is_object:
        rest[pre + "Hips"] = rest_mw.copy()
    use_action(src, action)
    start_f, end_f = action.frame_range
    n = int(round(end_f - start_f)) + 1
    frames = {b: [] for b in names}
    if hips_is_object:
        frames[pre + "Hips"] = []
    for f in range(n):
        bpy.context.scene.frame_set(int(start_f) + f)
        mwf = src.matrix_world.copy()
        for b in names:
            frames[b].append(mwf @ src.pose.bones[b].matrix)
        if hips_is_object:
            frames[pre + "Hips"].append(mwf)
    # Find the cycle: the frame after `start` whose leg pose best matches it.
    legs = [pre + b for b in ("LeftUpLeg", "LeftLeg", "RightUpLeg", "RightLeg")]
    def pose_key(i):
        hip_inv = frames[pre + "Hips"][i].to_3x3().inverted()
        return [hip_inv @ frames[b][i].to_3x3() for b in legs if b in frames]
    start = min(60, n // 4)
    ref = pose_key(start)
    best, period = 1e9, 30
    for p in range(22, min(70, n - start - 1)):
        k = pose_key(start + p)
        err = sum((a.to_quaternion().rotation_difference(b.to_quaternion()).angle) for a, b in zip(ref, k))
        if err < best:
            best, period = err, p
    clip_frames = {b: v[start:start + period + 1] for b, v in frames.items()}
    # The take may walk along any axis: turn the cycle so the hips face the
    # same way as in the rest pose (Mixamo rigs face -Y in Blender).
    hips_rest = rest[pre + "Hips"].to_3x3().normalized()
    heading = Vector()
    for m in clip_frames[pre + "Hips"]:
        f = (m.to_3x3().normalized() @ hips_rest.inverted()) @ Vector((0, -1, 0))
        heading += Vector((f.x, f.y, 0))
    yaw = math.atan2(heading.x, -heading.y) + math.pi
    turn = Matrix.Rotation(yaw, 4, 'Z')
    pivot = clip_frames[pre + "Hips"][0].translation.copy()
    pivot.z = 0.0
    shift = Matrix.Translation(pivot) @ turn @ Matrix.Translation(-pivot)
    clip_frames = {b: [shift @ m for m in v] for b, v in clip_frames.items()}
    print("@walk heading fix", round(math.degrees(yaw), 1), "deg")
    hips = clip_frames[pre + "Hips"]
    travel = (hips[-1].translation - hips[0].translation)
    travel.z = 0.0
    tgt_rest = {b.name: mw @ b.matrix_local for b in tbones}
    scale = tgt_rest[pre + "Hips"].translation.z / max(rest[pre + "Hips"].translation.z, 1e-4)
    mw_inv = mw.inverted()
    act = bpy.data.actions.new("walk")
    act.use_fake_user = True
    use_action(tgt, act)
    prev = {}
    for fi in range(period + 1):
        pose = {}
        drift = travel * (fi / period)
        for bone in tbones:
            name, parent = bone.name, bone.parent
            base = (pose[parent.name] @ parent.matrix_local.inverted() @ bone.matrix_local) if parent else bone.matrix_local.copy()
            if name not in clip_frames:
                pose[name] = base
                continue
            s_now = clip_frames[name][fi]
            delta = s_now.to_3x3().normalized() @ rest[name].to_3x3().normalized().inverted()
            rot = mw_inv.to_3x3().normalized() @ delta @ tgt_rest[name].to_3x3().normalized()
            translation = base.translation
            if name == pre + "Hips":
                offset = (s_now.translation - drift - hips[0].translation) * scale
                offset.z = (s_now.translation.z - rest[name].translation.z) * scale
                translation = mw_inv @ (tgt_rest[name].translation + Vector((offset.x * 0.3, offset.y * 0.3, offset.z)))
            matrix = Matrix.Translation(translation) @ rot.to_4x4()
            pose[name] = matrix
            q = (base.inverted() @ matrix).to_quaternion()
            if name in prev:
                q.make_compatible(prev[name])
            prev[name] = q
            pb = tgt.pose.bones[name]
            pb.rotation_quaternion = q
            pb.keyframe_insert("rotation_quaternion", frame=fi)
            if name == pre + "Hips":
                pb.location = (base.inverted() @ matrix).translation
                pb.keyframe_insert("location", frame=fi)
    tgt.animation_data.action = None
    for o in new:
        bpy.data.objects.remove(o, do_unlink=True)
    speed = travel.length * scale / (period / FPS)
    print("@walk cycle", period, "frames, match", round(best, 3), "speed", round(speed, 2))
    return act, round(period / FPS, 3), round(speed, 3)


def main(src_path, rm_path, char_path, out_path, walk_path=None):
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
    rig_info = {"src_hips": src_rest["B_Pelvis"].translation, "tgt_hips": tgt_rest[pre + "Hips"].translation, "scale": scale}
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
            leg_wants = solve_legs(frames, fi, mapped, tbones, mw, rig_info)
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
                    want = leg_wants.get(name) or (frames[mapped[pre + child]][fi].translation - s_now.translation)
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
                    offset = adjust_hip_offset(s_now.translation - src_rest[sname].translation) * scale
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
    if walk_path:
        for a in [a for a in made if a.name == "walk"]:
            made.remove(a)
            bpy.data.actions.remove(a)
        walk, length, speed = mocap_walk(walk_path, tgt, tbones, mw)
        made.append(walk)
        json_out["walk"] = {"length": length, "ground_speed": speed, "loop": True}
        for pb in tgt.pose.bones:
            pb.rotation_quaternion = Quaternion()
            pb.location = Vector()
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
    main(*sys.argv[1:6])
