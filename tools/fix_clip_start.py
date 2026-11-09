"""Shift every animation in a GLB so its first key is at t=0 (trimmed clips
exported from Blender keep their original start time)."""
import json, struct, sys
import numpy as np

path = sys.argv[1]
blob = bytearray(open(path, 'rb').read())
json_len = struct.unpack('<I', blob[12:16])[0]
gltf = json.loads(blob[20:20 + json_len])
bin_start = 20 + json_len + 8
fixed = []
done_accessors = set()
for anim in gltf['animations']:
    inputs = {s['input'] for s in anim['samplers']}
    starts = [gltf['accessors'][i]['min'][0] for i in inputs]
    offset = min(starts)
    if offset <= 1e-4:
        continue
    for i in inputs:
        if i in done_accessors:
            continue
        acc = gltf['accessors'][i]
        view = gltf['bufferViews'][acc['bufferView']]
        start = bin_start + view.get('byteOffset', 0) + acc.get('byteOffset', 0)
        data = np.frombuffer(bytes(blob[start:start + acc['count'] * 4]), np.float32) - offset
        blob[start:start + acc['count'] * 4] = data.astype(np.float32).tobytes()
        acc['min'] = [float(data.min())]
        acc['max'] = [float(data.max())]
        done_accessors.add(i)
    fixed.append((anim['name'], round(offset, 3)))
new_json = json.dumps(gltf, separators=(',', ':')).encode()
while len(new_json) % 4:
    new_json += b' '
binary = blob[20 + json_len:]
out = struct.pack('<4sII', b'glTF', 2, 12 + 8 + len(new_json) + len(binary)) + struct.pack('<II', len(new_json), 0x4E4F534A) + new_json + bytes(binary)
open(path, 'wb').write(out)
print(path.split('/')[-1], "shifted:", fixed)
