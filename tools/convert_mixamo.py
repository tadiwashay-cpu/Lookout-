"""Convert Mixamo FBX characters + animation FBXs into one game-ready GLB each.

Run with Blender's Python module (pip install bpy, Python 3.11):
    python convert_mixamo.py CHARACTER.fbx OUT.glb ANIM_DIR

- Renames animation bones (mixamorig9:*, mixamorig2:* ...) to the
  character's prefix so every clip drives the same skeleton.
- Strips horizontal root motion from locomotion clips (the game moves the
  character; the animation only moves the legs).
- Names clips the way the game expects (see CLIP_NAMES) and writes
  OUT.json next to the GLB with each clip's ground speed for playback sync.
"""
import json, os, re, sys
import bpy

CLIP_NAMES = {
    # file stem (without upload hash)  -> clip name used by the game
    "rifle_aiming_idle": "idle",
    "walking": "walk",
    "walking_backwards": "walk_back",
    "rifle_run": "run",
    "run_backwards": "run_back",
    "strafe_left": "strafe_left",
    "strafe_right": "strafe_right",
    "strafe_2": "strafe_left_run",     # measured: moves to the character's left
    "strafe": "strafe_right_run",      # measured: moves to the character's right
    "firing_rifle": "fire",
    "reloading": "reload",
    "rifle_jump": "jump",
    "toss_grenade": "throw_grenade",
    "hit_reaction": "hit",
    "turn_left": "turn_left",
    "turning_right_45_degrees": "turn_right",
}
IN_PLACE = {"walk", "walk_back", "run", "run_back", "strafe_left", "strafe_right",
            "strafe_left_run", "strafe_right_run", "turn_left", "turn_right", "throw_grenade", "hit"}
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
    name = os.path.splitext(os.path.basename(path))[0]
    return re.sub(r"^[0-9a-f]{8}-", "", name)


def main(char_path, out_path, anim_dir):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.render.fps = int(FPS)
    bpy.ops.import_scene.fbx(filepath=char_path)
    rig = next(o for o in bpy.data.objects if o.type == 'ARMATURE')
    prefix = rig.data.bones[0].name.split(":")[0] + ":"
    for action in list(bpy.data.actions):          # T-pose "animation" from the character file
        bpy.data.actions.remove(action)

    speeds = {}
    for file in sorted(os.listdir(anim_dir)):
        if not file.lower().endswith(".fbx") or stem(file) not in CLIP_NAMES:
            continue
        clip = CLIP_NAMES[stem(file)]
        before = set(bpy.data.objects)
        bpy.ops.import_scene.fbx(filepath=os.path.join(anim_dir, file))
        new_objects = [o for o in bpy.data.objects if o not in before]
        anim_rig = next(o for o in new_objects if o.type == 'ARMATURE')
        action = anim_rig.animation_data.action
        for bone in anim_rig.data.bones:            # mixamorig9:Hips -> mixamorig:Hips (updates fcurves)
            bone.name = prefix + bone.name.split(":", 1)[-1]
        action.name = clip
        action.use_fake_user = True
        start, end = action.frame_range
        hips_path = f'pose.bones["{prefix}Hips"].location'
        travel = 0.0
        for fc in fcurves(action):
            if fc.data_path != hips_path or fc.array_index not in (0, 2):
                continue
            keys = fc.keyframe_points
            travel = max(travel, abs(keys[-1].co[1] - keys[0].co[1]))
            if clip in IN_PLACE:
                first = keys[0].co[1]
                for k in keys:
                    k.co[1] = first; k.handle_left[1] = first; k.handle_right[1] = first
        duration = max(end - start, 1.0) / FPS
        speeds[clip] = {"length": round(duration, 3), "ground_speed": round(travel * 0.01 / duration, 3)}
        anim_rig.animation_data.action = None
        for o in new_objects:
            bpy.data.objects.remove(o, do_unlink=True)

    # Push every clip onto the character as an NLA strip so the exporter keeps them all.
    rig.animation_data_create()
    for action in bpy.data.actions:
        track = rig.animation_data.nla_tracks.new()
        track.name = action.name
        strip = track.strips.new(action.name, int(action.frame_range[0]), action)
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
    print("@converted", out_path, "clips:", sorted(speeds))


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2], sys.argv[3])
