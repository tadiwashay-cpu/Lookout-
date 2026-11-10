"""Put Quaternius "Ultimate Modular" characters (CC0) on our Mixamo clip set.

Run with Blender's Python module (bpy):

    python retarget_quaternius.py SOURCE.glb GROUP_DIR OUT_DIR PREFIX BASE

  SOURCE.glb  a converted Mixamo character with every clip (x_bot.glb)
  GROUP_DIR   folder of Quaternius *humanoid rig* FBX files that share one
              skeleton (e.g. the men, or the women)
  OUT_DIR     assets/models/characters/civilians
  PREFIX      file prefix, e.g. "civ_m"
  BASE        the character that also carries the animations, e.g. "Casual"

What it does:
  1. renames the Quaternius bones to Mixamo names (mixamorig:RightHand...)
     so CharacterRig's hand/finger lookups and gun grip work unchanged
  2. retargets every clip from SOURCE onto that skeleton (both are T-pose:
     each bone copies the source bone's world-space rotation change; the
     hips also copy the movement, scaled by hip height)
  3. writes PREFIX_BASE.glb WITH the clips, and PREFIX_<name>.glb for
     every other character WITHOUT clips. All characters in a group share
     one skeleton, so the game loads the clips once (from BASE) and reuses
     them for the whole group: far less memory on a 4 GB phone.
"""
import bpy, glob, os, sys
from mathutils import Matrix, Quaternion, Vector

FPS = 30

# Mixamo short name -> Quaternius name, per finger layout.
BODY = {
    "Hips": "Hips", "Spine": "Abdomen", "Spine1": "Torso", "Spine2": "Chest",
    "Neck": "Neck", "Head": "Head",
}
for side, s in (("Left", "L"), ("Right", "R")):
    BODY.update({
        f"{side}Shoulder": f"Shoulder.{s}", f"{side}Arm": f"UpperArm.{s}",
        f"{side}ForeArm": f"LowerArm.{s}", f"{side}Hand": f"Hand.{s}",
        f"{side}UpLeg": f"UpperLeg.{s}", f"{side}Leg": f"LowerLeg.{s}",
        f"{side}Foot": f"Foot.{s}",
    })


def finger_map(bone_names):
    """Men number fingers 2-4 (thumb 2-3), women 1-3 (thumb 1-3)."""
    out = {}
    first = 1 if "Index1.L" in bone_names else 2
    for side, s in (("Left", "L"), ("Right", "R")):
        for finger in ("Index", "Middle", "Ring", "Pinky", "Thumb"):
            for i in (1, 2, 3):
                q = f"{finger}{i + first - 1}.{s}"
                if q in bone_names:
                    out[f"{side}Hand{finger}{i}"] = q
    return out


def clear():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.render.fps = FPS
    bpy.context.scene.render.fps_base = 1.0


def armature_of(objects):
    return next(o for o in objects if o.type == 'ARMATURE')


def load_target(path):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.fbx(filepath=path)
    new = [o for o in bpy.data.objects if o not in before]
    rig = armature_of(new)
    mapping = dict(BODY)
    mapping.update(finger_map({b.name for b in rig.data.bones}))
    # Rename to Mixamo names (vertex groups follow automatically).
    for mixamo, quat in mapping.items():
        rig.data.bones[quat].name = "mixamorig:" + mixamo
    rig.name = "Armature"
    rig.data.name = "Armature"
    make_opaque(new)
    return rig, new, sorted(mapping)


def make_opaque(objects):
    """Some packs (the women) import with alpha 0 (an FBX transparency quirk)."""
    for o in objects:
        if o.type != 'MESH':
            continue
        for mat in o.data.materials:
            if mat is None or not mat.use_nodes:
                continue
            for node in mat.node_tree.nodes:
                if node.type == 'BSDF_PRINCIPLED':
                    alpha = node.inputs.get("Alpha")
                    for link in list(alpha.links):
                        mat.node_tree.links.remove(link)
                    alpha.default_value = 1.0
            if hasattr(mat, "surface_render_method"):
                mat.surface_render_method = 'DITHERED'
            if hasattr(mat, "blend_method"):
                mat.blend_method = 'OPAQUE'


def sample_source(src, actions):
    """{clip: (frames, {bone: [world 4x4 per frame]})} and rest world matrices."""
    mw = src.matrix_world
    rest = {b.name: mw @ b.matrix_local for b in src.data.bones}
    clips = {}
    src.animation_data_create()
    scene = bpy.context.scene
    for action in actions:
        src.animation_data.action = action
        if hasattr(src.animation_data, "action_slot") and action.slots:
            src.animation_data.action_slot = action.slots[0]
        start, end = action.frame_range
        n = int(round(end - start)) + 1
        per_bone = {pb.name: [] for pb in src.pose.bones}
        for f in range(n):
            scene.frame_set(int(start) + f)
            for pb in src.pose.bones:
                per_bone[pb.name].append(mw @ pb.matrix)
        clips[action.name] = (n, per_bone)
        print("@sampled", action.name, n)
    src.animation_data.action = None
    return rest, clips


def retarget(rig, mapped, src_rest, clips):
    mw = rig.matrix_world
    mw_inv = mw.inverted()
    bones = rig.data.bones
    tgt_rest_w = {b.name: mw @ b.matrix_local for b in bones}
    hips = "mixamorig:Hips"
    scale = tgt_rest_w[hips].translation.z / max(src_rest[hips].translation.z, 1e-4)
    mapped_full = {"mixamorig:" + m for m in mapped}
    order = list(bones)   # Blender lists parents before children
    for pb in rig.pose.bones:
        pb.rotation_mode = 'QUATERNION'
    rig.animation_data_create()
    made = []
    for clip, (n, frames) in clips.items():
        action = bpy.data.actions.new(clip)
        action.use_fake_user = True
        rig.animation_data.action = action
        prev = {}
        for fi in range(n):
            pose = {}
            for bone in order:
                name = bone.name
                parent = bone.parent
                rest_local = bone.matrix_local
                base = (pose[parent.name] @ parent.matrix_local.inverted() @ rest_local) if parent else rest_local.copy()
                if name not in mapped_full or name not in frames:
                    pose[name] = base
                    continue
                s_now = frames[name][fi]
                delta = s_now.to_3x3().normalized() @ src_rest[name].to_3x3().normalized().inverted()
                world_rot = delta @ tgt_rest_w[name].to_3x3().normalized()
                rot = mw_inv.to_3x3().normalized() @ world_rot
                translation = base.translation
                if name == hips:
                    offset = (s_now.translation - src_rest[name].translation) * scale
                    translation = mw_inv @ (tgt_rest_w[name].translation + offset)
                matrix = Matrix.Translation(translation) @ rot.to_4x4()
                pose[name] = matrix
                basis = base.inverted() @ matrix
                pb = rig.pose.bones[name]
                q = basis.to_quaternion()
                if name in prev:
                    q.make_compatible(prev[name])
                prev[name] = q
                pb.rotation_quaternion = q
                pb.keyframe_insert("rotation_quaternion", frame=fi)
                if name == hips:
                    pb.location = basis.translation
                    pb.keyframe_insert("location", frame=fi)
        rig.animation_data.action = None
        for pb in rig.pose.bones:
            pb.rotation_quaternion = Quaternion()
            pb.location = Vector()
        made.append((clip, action, n))
        print("@retargeted", clip, n)
    for clip, action, n in made:
        track = rig.animation_data.nla_tracks.new()
        track.name = clip
        strip = track.strips.new(clip, 0, action)
        track.mute = True
    return len(made)


def export(path, with_anims):
    bpy.context.scene.render.fps = FPS
    bpy.ops.export_scene.gltf(
        filepath=path, export_format='GLB', export_animations=with_anims,
        export_animation_mode='NLA_TRACKS', export_force_sampling=False,
        export_yup=True, export_apply=False, export_skins=True,
        export_morph=False, export_def_bones=False,
    )
    print("@exported", path, os.path.getsize(path) // 1024, "KB")


def main(source, group_dir, out_dir, prefix, base_name):
    os.makedirs(out_dir, exist_ok=True)
    files = sorted(glob.glob(os.path.join(group_dir, "*.fbx")))
    # 1. Sample the source clips once.
    clear()
    bpy.ops.import_scene.gltf(filepath=source)
    src = armature_of(bpy.data.objects)
    actions = [a for a in bpy.data.actions]
    src_rest, clips = sample_source(src, actions)
    # 2. Characters: the base one gets the clips, the rest are mesh + skeleton.
    for path in files:
        name = os.path.splitext(os.path.basename(path))[0]
        clear()
        rig, objects, mapped = load_target(path)
        if name == base_name:
            print("@clips", retarget(rig, mapped, src_rest, clips))
        export(os.path.join(out_dir, f"{prefix}_{name.lower()}.glb"), name == base_name)
    os._exit(0)   # skip Blender's slow teardown


if __name__ == "__main__":
    main(*sys.argv[1:6])
