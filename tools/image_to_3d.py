"""image -> textured GLB via the Image-to-3D Space (token injected by the proxy)."""
import os, shutil, sys, json
from gradio_client import Client, handle_file
name, image, out = sys.argv[1], sys.argv[2], sys.argv[3]
c = Client("https://prithivmlmods-image-to-3d-video-asset-generator.hf.space", ssl_verify=os.environ.get("SSL_CERT_FILE", True), verbose=False)
try: c.predict(api_name="/start_session")
except Exception as e: print("start_session:", e)
path2 = image
try:
    pre = c.predict(input=handle_file(image), api_name="/preprocess_image")
    path2 = pre["path"] if isinstance(pre, dict) else pre
    print("PRE", path2); shutil.copy(path2, os.path.join(out, name + "_pre.png"))
except Exception as e:
    print("preprocess failed:", e)
res = c.predict(image=handle_file(path2), seed=7, resolution="1024", decimation_target=120000, texture_size=2048,
                ss_guidance_strength=7.5, ss_guidance_rescale=0.7, ss_sampling_steps=12, ss_rescale_t=5,
                shape_guidance=7.5, shape_rescale=0.5, shape_steps=12, shape_rescale_t=3,
                tex_guidance=1, tex_rescale=0, tex_steps=12, tex_rescale_t=3, api_name="/generate_3d")
print("RES", json.dumps(res, default=str)[:600])
for r in (res if isinstance(res, (list, tuple)) else [res]):
    p = r.get("path") if isinstance(r, dict) else r
    if isinstance(p, str) and os.path.exists(p):
        ext = os.path.splitext(p)[1] or ".bin"
        shutil.copy(p, os.path.join(out, name + ext)); print("SAVED", name + ext, os.path.getsize(p))
