# Asset tools (Python 3 + numpy + Pillow)

| Script | What it does |
|---|---|
| `split_cars.py` | Splits a multi-car pack GLB into one game-ready GLB per car (metres, faces -Z, origin on the ground, `Body` + `Wheel_FL/FR/RL/RR` with hub pivots). Car-specific grouping lives at the top of the file. |
| `glbrender.py` | Tiny GLB loader + preview renderer used to check orientation without a 3D app. |

These run outside Godot and aren't part of the game build.

## retarget_quaternius.py (Blender bpy)
Puts Quaternius "Ultimate Modular" characters (humanoid rig FBX) on our
Mixamo clip set. One file per group carries the clips; the others are
mesh-only and share them at runtime (see `CharacterRig._civilian_clips`).

    python retarget_quaternius.py assets/models/characters/x_bot.glb MEN_FBX_DIR \
        assets/models/characters/civilians civ_m Casual

## add_addon.sh
Installs a GDScript add-on from GitHub. See `docs/addons.md`.

