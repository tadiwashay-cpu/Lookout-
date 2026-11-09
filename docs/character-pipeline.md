# Hero Character Pipeline: concept → playable model

Concept: `docs/concept/hero_concept_front.jpg` (front T-pose).

## Status
`assets/models/hero/hero.glb` is **rigged and animated**, and the player uses it.
- **Mesh:** reduced from 282k to about 40k triangles for mobile with
  `tools/decimate_hero.py`. Textures are 2048² base colour and 1024²
  metal/rough.
- **Rig:** 19-bone humanoid made by `tools/rig_hero.py`, fitted to his
  proportions, with automatic skin weights. Left/right and body regions
  are masked so the legs don't pull on each other.
- **Clips:** idle, walk, run, punch_1, punch_2, punch_3, punch_heavy,
  dodge, hit, knocked_out. These are hand-authored procedural motion,
  good enough to play with.

To redo it (for example after editing the mesh): run
`python tools/decimate_hero.py source.glb hero_40k.glb 40000`, then
`python tools/rig_hero.py hero_40k.glb assets/models/hero/hero.glb`.
Pose and timing tweaks go in `rig_hero.py` (`CLIPS`).

Later upgrade: a professional rig with motion-captured animation
(Mixamo or similar) will look better. The game picks it up the same way
as long as the clip names match.

## 1. Turn the concept into a 3D model
Choose one:
- **Image-to-3D tool** (fastest; Tripo, Meshy, Rodin, etc.). Feed it the
  front T-pose; add a side and back view if you can draw or generate
  them, since quality improves a lot. Expect messy topology. It still
  needs cleanup (step 2).
- **Hire or commission a modeller** with the concept sheet. Best quality.
- **Sculpt it yourself** on the tablet with Nomad Sculpt, then retopo in
  Blender on a PC.

Ask for: T-pose or A-pose, real-world scale (≈1.85 m tall), facing +Z or
-Z, ≤ 40k triangles, one PBR texture set (base colour, metallic/roughness,
normal) at 2048².

## 2. Clean up, rig and animate
1. Clean up and decimate in Blender (on a PC). Separate the head mesh if
   you want face expressions later.
2. Auto-rig: upload the model to **Mixamo** (free) in a desktop browser.
   It rigs humanoids automatically.
3. Download these Mixamo animations **without skin**, then rename them
   to the names the game looks for:

| Clip name in Godot | Suggested Mixamo animation |
|---|---|
| `idle` | Fighting Idle |
| `walk` | Walking |
| `run` | Running |
| `punch_1` | Jab / Lead Jab |
| `punch_2` | Cross Punch |
| `punch_3` | Hook Punch (finisher) |
| `punch_heavy` | Uppercut |
| `dodge` | Dodging / Quick Roll |
| `hit` | Hit Reaction |
| `knocked_out` | Knocked Out / Dying |

4. Export one **.glb** with the mesh, skeleton and all clips.

## 3. Bring it into Lookout
1. Put the file at `assets/models/hero/hero.glb`. If it's over 25 MB,
   tell me and I'll set up Git LFS.
2. In Godot, open `scenes/characters/player.tscn`, select the **Player**
   node, and drag `hero.glb` into **Model Scene** in the Inspector.
3. If he faces backwards, change **Model Yaw Offset Deg** (180 ↔ 0).
4. Run the game. The controller finds the AnimationPlayer and plays the
   clips above automatically, and the placeholder body disappears.

## Materials
The chrome look needs: metallic = 1, roughness ≈ 0.12–0.2, a normal map
for panel lines, and something to reflect. Reflection probes in each
district do that job on mobile.
