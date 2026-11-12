import json, urllib.request, ssl, sys, os
ctx=ssl.create_default_context(cafile='/root/.ccr/ca-bundle.crt')
H={"User-Agent":"LookoutAssetFetcher/1.0"}
def get(u): return urllib.request.urlopen(urllib.request.Request(u, headers=H),context=ctx,timeout=120).read()
out=sys.argv[1]; kind=sys.argv[2]
for i in sys.argv[3:]:
    f=json.loads(get(f"https://api.polyhaven.com/files/{i}"))
    if kind=="tex":
        os.makedirs(f"{out}/{i}", exist_ok=True)
        for m,key in [("Diffuse","diff"),("nor_gl","nor"),("arm","arm"),("Rough","rough"),("Displacement","disp")]:
            if m in f and "1k" in f[m]:
                e=f[m]["1k"].get("jpg") or f[m]["1k"].get("png")
                p=f"{out}/{i}/{key}.jpg"
                if e and key!="disp" and not os.path.exists(p): open(p,"wb").write(get(e["url"]))
        print("tex", i, os.listdir(f"{out}/{i}"))
    else:
        g=f["gltf"]["1k"]["gltf"]; d=f"{out}/{i}"; os.makedirs(d, exist_ok=True)
        open(f"{d}/{i}.gltf","wb").write(get(g["url"]))
        for rel,v in g.get("include",{}).items():
            p=f"{d}/{rel}"; os.makedirs(os.path.dirname(p), exist_ok=True)
            if not os.path.exists(p): open(p,"wb").write(get(v["url"]))
        print("model", i)
