# Asset tools (Python 3 + numpy + Pillow)

| Script | What it does |
|---|---|
| `split_cars.py` | Splits a multi-car pack GLB into one game-ready GLB per car (metres, faces -Z, origin on the ground, `Body` + `Wheel_FL/FR/RL/RR` with hub pivots). Car-specific grouping lives at the top of the file. |
| `glbrender.py` | Tiny GLB loader + preview renderer used to check orientation without a 3D app. |

These run outside Godot and aren't part of the game build.
