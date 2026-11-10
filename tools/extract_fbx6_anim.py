"""Extract animation from old (FBX 6.x) files that Blender can't open, using
ufbx (pip install ufbx). Samples every bone's world transform at 30 fps and
writes JSON for tools/convert_mixamo.py --retarget.
Usage: python extract_fbx6_anim.py OUT.json name=path.fbx [name=path.fbx ...]"""
import json, os, sys
import ufbx

BONES = ["Pelvis", "Spine1", "Spine2", "Spine3", "Neck_Base", "Head",
         "L_Clavicle", "L_Arm", "L_Forearm", "L_Hand", "L_Middle1",
         "R_Clavicle", "R_Arm", "R_Forearm", "R_Hand", "R_Middle1",
         "L_Thigh", "L_Shin", "L_Ankle", "L_Toes", "R_Thigh", "R_Shin", "R_Ankle", "R_Toes"]
FPS = 30.0


def matrix(m):
    return [m.c0.x, m.c0.y, m.c0.z, m.c1.x, m.c1.y, m.c1.z, m.c2.x, m.c2.y, m.c2.z, m.c3.x, m.c3.y, m.c3.z]


out_path = sys.argv[1]
result = {}
keep = []   # ufbx objects must outlive the matrices read from them


def read_bones(scene_obj):
    out = {}
    for b in BONES:
        node = scene_obj.find_node(b)
        if node is None:
            continue
        keep.append(node)
        m = node.node_to_world
        keep.append(m)
        out[b] = matrix(m)
    return out


for arg in sys.argv[2:]:
    name, path = arg.split("=", 1)
    scene = ufbx.load_file(path)
    keep.append(scene)
    stack = scene.anim_stacks[0]
    keep.append(stack)
    anim = stack.anim
    keep.append(anim)
    rest = read_bones(scene)
    frames = []
    begin, end = stack.time_begin, stack.time_end
    count = max(int(round((end - begin) * FPS)), 1)
    for i in range(count + 1):
        ev = ufbx.evaluate_scene(scene, anim, begin + i / FPS)
        keep.append(ev)
        frames.append(read_bones(ev))
    result[name] = {"fps": FPS, "rest": rest, "frames": frames}
    print(name, len(frames), "frames", flush=True)
with open(out_path, "w") as f:
    json.dump(result, f)
sys.stdout.flush()
os._exit(0)   # ufbx bindings can crash while tearing down scenes
