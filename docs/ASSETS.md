# Lookout — where the art comes from (and where to get more)

Phone budget we design for (4 GB RAM, Mobile renderer): props ≤ 5k triangles,
characters ≤ 30k, 1k textures (512 for small props), everything far away is a
MultiMesh or an impostor. Every asset below is free and usable in a
commercial game. Licences are noted; **CC0** needs no credit, **CC BY** needs
the credit line in `CREDITS.md` / the store page.

## What the game uses now

| What | Source | Licence | Notes |
|---|---|---|---|
| Car pack (17 cars) | "Generic passenger car pack" by Comrade1280 (Sketchfab) + the original supercars | CC BY 4.0 | Kept from the old project; credit required |
| Nash (main character) | Generated from your Mii design (Higgsfield / Tripo image-to-3D), auto-rigged with **UniRig** (Hugging Face Space) | yours | `tools/prepare_hero.py` only renames bones; the rig and weights are UniRig's |
| NPCs (14 city people) | Quaternius "Ultimate Modular Men/Women" | CC0 | Pre-rigged |
| Animations (88 clips: locomotion, punches, hook, knockback, death, get-up, roll, driving, sitting, working, dancing...) | Quaternius **Universal Animation Library 1 + 2** (OpenGameArt mirror) | CC0 | One shared library, retargeted to Godot's humanoid profile at import |
| Ground, asphalt, walls, roofs, interiors (21 PBR sets) | **Poly Haven** textures, 1k | CC0 | Diffuse + normal + AO/rough/metal |
| Street and interior props (26) | **Poly Haven** models, decimated with `tools/decimate_props.py` | CC0 | Hydrants, barriers, bins, tool chests, drill press, shelves, ceiling fans, lamps, diner furniture, a ship... |
| Forest | Poly Haven `fir_sapling_medium` (2.3 M triangles) rendered into billboard impostors by `tools/tree_impostor.py` | CC0 | 2 quads per tree on screen |
| Sounds | Synthesised in code (`scripts/core/sfx.gd`) | ours | Replace with recorded packs later (below) |

## Best free sources (ranked for this game)

### Realistic, phone-friendly
1. **Poly Haven** — polyhaven.com (API: api.polyhaven.com). CC0. The best free
   PBR textures and HDRIs anywhere, plus ~520 scanned models. Models are often
   very dense: always decimate (our script does it) and use 1k maps.
2. **ambientCG** — ambientcg.com. CC0. 2,000+ PBR materials (more facade,
   pavement and road variants than Poly Haven), 1k/2k JPG downloads, no login.
3. **Fab (Epic) free section** — fab.com, filter "Free". Includes the free
   Quixel Megascans set. Licence: Fab Standard licence (fine for games, *not*
   CC0, and some items are Unreal-only). Needs an Epic account; decimate for phones.
4. **Sketchfab** — filter "Downloadable" + licence CC0 / CC BY. Huge variety of
   buildings and cars; quality varies. Needs a login to download.

### Stylised but clean (fast, light)
5. **Quaternius** — quaternius.com / quaternius.itch.io. CC0. Characters,
   animations, cities, nature, vehicles; mobile-ready. New packs are free on
   itch.io (the free "Standard" tier).
6. **Kenney** — kenney.nl. CC0. City kits, roads, vehicles, UI, sounds.
7. **KayKit** — kaylousberg.itch.io. CC0. City builder / character packs.

### Characters and rigging
- **UniRig** (open source, Hugging Face Spaces) — automatic skeleton + skin
  weights for any mesh; what rigged Nash.
- **Mixamo** (Adobe, free account) — auto-rig a humanoid and download 2,000+
  mocap clips. Free to use in games; clips must ship inside the game, not resold.
- **AccuRIG** (Reallusion, free desktop app) — auto-rig + ActorCore free clips.
- **Meshy / Tripo / Hunyuan3D** — image-to-3D (and Meshy rigging) on credits.

### Animation packs
- Quaternius Universal Animation Library 1 & 2 (in the game), CC0.
- Mixamo: boxing, kickboxing, sitting, driving, crowd idles.
- CMU motion-capture database (free, 2,500 clips, BVH; needs cleaning).

### Sound
- **Sonniss GDC bundles** (gdc.sonniss.com) — tens of GB of pro SFX, royalty
  free (cars, impacts, crowds).
- **Kenney audio packs**, **freesound.org** (check each clip's licence),
  **ElevenLabs** sound effects (generated, needs credits).

## How a new asset goes into the game
1. Download glTF/GLB (or FBX → convert in Blender).
2. Props: `python tools/decimate_props.py SRC_DIR OUT_DIR` (set the budget).
3. Characters: rig (UniRig / Mixamo), then `tools/prepare_hero.py` if the
   bones aren't named; add a `.glb.import` with a bone map (see
   `assets/characters/npc/*.import`) so the shared animations play on it.
4. Textures: drop the 1k set in `assets/textures/<name>/` as diff/nor/arm.jpg
   and use `Mats.pbr("<name>")`.
5. Credit it in `CREDITS.md` if it isn't CC0.
