import os, sys, shutil
from gradio_client import Client, handle_file
space, src, out = sys.argv[1], sys.argv[2], sys.argv[3]
c = Client(space, ssl_verify=os.environ["SSL_CERT_FILE"], verbose=False)
res = c.predict(input_glb=handle_file(src), api_name="/rig_model")
print("STATUS", res[1])
p = res[0]["path"] if isinstance(res[0], dict) else res[0]
if p and os.path.exists(p):
    shutil.copy(p, out); print("SAVED", out, os.path.getsize(out))
