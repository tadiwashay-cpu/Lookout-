"""(bpy) Ford Crown Victoria Police Interceptor -> game car GLB.
Decimates for mobile (~235k -> ~18k triangles), scales to real size,
faces Godot -Z, origin centred on the ground. Nodes: Body, Lights (roof
light bar lenses, flashed in game), Wheel_FL/FR/RL/RR (pivot at hub).
Usage: python convert_crown_vic.py CrownVic.fbx OUT.glb"""
import sys, math
import bpy, mathutils

src, out = sys.argv[1], sys.argv[2]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=src)
objs = {o.name: o for o in bpy.data.objects}
for o in list(bpy.data.objects):
    if o.type != 'MESH' or o.name.startswith("WGT"):
        bpy.data.objects.remove(o, do_unlink=True)
for o in bpy.data.objects:   # bake parent transforms
    m = o.matrix_world.copy(); o.parent = None; o.matrix_world = m
bpy.ops.object.select_all(action='SELECT')
bpy.context.view_layer.objects.active = bpy.data.objects[0]
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

def decimate(o, ratio):
    if ratio >= 1.0:
        return
    mod = o.modifiers.new("dec", 'DECIMATE'); mod.ratio = ratio
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.modifier_apply(modifier=mod.name)

def join(names, new_name):
    parts = [bpy.data.objects[n] for n in names if n in bpy.data.objects]
    bpy.ops.object.select_all(action='DESELECT')
    for p in parts: p.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    if len(parts) > 1: bpy.ops.object.join()
    obj = bpy.context.view_layer.objects.active; obj.name = new_name
    return obj

ratios = {"CrownVic.Body": 0.13, "Roof light bar": 0.07, "roof lights": 0.08, "windows glass": 0.35}
for o in bpy.data.objects:
    if o.name.startswith("CrownVic.Wheel."): decimate(o, 0.025)
    elif o.name in ratios: decimate(o, ratios[o.name])

# Wheel hub centres (before moving anything)
corners = {"Ft.L": "FL", "Ft.R": "FR", "Bk.L": "RL", "Bk.R": "RR"}
hubs = {}
for key, short in corners.items():
    w = bpy.data.objects["CrownVic.Wheel." + key]
    pts = [w.matrix_world @ v.co for v in w.data.vertices]
    hubs[short] = sum(pts, mathutils.Vector()) / len(pts)
centre = sum(hubs.values(), mathutils.Vector()) / 4
ground = min(min((w.matrix_world @ v.co).z for v in bpy.data.objects["CrownVic.Wheel." + k].data.vertices) for k in corners)
wheelbase = (hubs["FL"] - hubs["RL"]).length
scale = 2.91 / wheelbase          # real Crown Vic wheelbase
# Move to origin, scale, and turn so the front (Blender -Y) becomes +Y (= glTF/Godot -Z).
fix = (mathutils.Matrix.Rotation(math.pi, 4, 'Z') @ mathutils.Matrix.Scale(scale, 4)
       @ mathutils.Matrix.Translation(mathutils.Vector((-centre.x, -centre.y, -ground))))

body = join(["CrownVic.Body", "windows glass", "interior", "Roof light bar"], "Body")
lights = join(["roof lights"], "Lights")
for o in (body, lights):
    o.data.transform(fix); o.matrix_world = mathutils.Matrix.Identity(4)
for key, short in corners.items():
    wheel = join(["CrownVic.Wheel." + key, "CrownVic.WheelBrake." + key], "Wheel_" + short)
    hub = fix @ hubs[short]
    wheel.data.transform(mathutils.Matrix.Translation(-hub) @ fix)
    wheel.matrix_world = mathutils.Matrix.Translation(hub)
tris = sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in bpy.data.objects if o.type == 'MESH')
dims = body.dimensions
print("@ tris", tris, "scale", round(scale, 3), "body dims", [round(d, 2) for d in dims], "hubs", {k: [round(c, 2) for c in fix @ v] for k, v in hubs.items()})
bpy.ops.export_scene.gltf(filepath=out, export_format='GLB', export_yup=True, export_image_format='JPEG', export_jpeg_quality=85)
