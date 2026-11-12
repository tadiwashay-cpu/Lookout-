import bpy, sys, os, math
import numpy as np
from mathutils import Vector
src, out = sys.argv[-2], sys.argv[-1]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
ms=[o for o in bpy.data.objects if o.type=='MESH']
print("@objs", [(o.name, len(o.data.polygons)) for o in ms][:20])
# Use one tree only: the sapling file is a row of trees; take the largest object.
big = max(ms, key=lambda o: (o.matrix_world @ Vector(o.bound_box[6])).z - (o.matrix_world @ Vector(o.bound_box[0])).z)
for o in ms:
    if o is not big: o.hide_render = True
bb=[big.matrix_world @ Vector(c) for c in big.bound_box]
mn=Vector((min(v.x for v in bb),min(v.y for v in bb),min(v.z for v in bb))); mx=Vector((max(v.x for v in bb),max(v.y for v in bb),max(v.z for v in bb)))
c=(mn+mx)/2; size=mx-mn
print("@tree", big.name, [round(x,2) for x in size])
sc=bpy.context.scene; sc.render.engine='CYCLES'; sc.cycles.samples=48; sc.cycles.device='CPU'
sc.render.film_transparent=True; sc.render.resolution_x=512; sc.render.resolution_y=1024
sc.render.image_settings.file_format='PNG'; sc.render.image_settings.color_mode='RGBA'
w=bpy.data.worlds.new("w"); sc.world=w; w.use_nodes=True; w.node_tree.nodes["Background"].inputs[1].default_value=1.6
sun=bpy.data.objects.new("sun", bpy.data.lights.new("sun",'SUN')); sun.data.energy=5.0; sun.rotation_euler=(0.7,0.2,0.6); sc.collection.objects.link(sun)
cam=bpy.data.objects.new("c", bpy.data.cameras.new("c")); sc.collection.objects.link(cam); sc.camera=cam
cam.data.type='ORTHO'; h=max(size.z, max(size.x,size.y)*2)*1.02; cam.data.ortho_scale=h
for name, ang in [("a",0.0),("b",math.pi/2)]:
    d=Vector((math.cos(ang), math.sin(ang), 0)); cam.location=Vector((c.x,c.y,mn.z+h/2))+d*50
    cam.rotation_euler=(-d).to_track_quat('-Z','Y').to_euler()
    sc.render.filepath=os.path.join(out, "fir_%s.png"%name); bpy.ops.render.render(write_still=True)
print("@height", size.z)
os._exit(0)
