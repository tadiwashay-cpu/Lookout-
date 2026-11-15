# Credits

## Vehicles (credit required)
**"Generic passenger car pack"** by **Comrade1280**
https://sketchfab.com/3d-models/generic-passenger-car-pack-20f9af9b8a404d5cb022ac6fe87f21f5
Licensed under **CC BY 4.0** (https://creativecommons.org/licenses/by/4.0/).
Changes: split into one file per vehicle, re-oriented and re-centred, wheels
separated for physics; paint recoloured in-game.
Files: `assets/vehicles/*.glb`

## Characters and animation (CC0)
- **Universal Animation Library** and **Universal Animation Library 2** by
  **Quaternius** — CC0. `assets/animations/`
- **Ultimate Modular Men / Women** by **Quaternius** — CC0.
  `assets/characters/npc/`
- **Nash** — generated from the author's own design; auto-rigged with
  **UniRig** (VAST-AI-Research, MIT licence) via a Hugging Face Space.

## Generated fight animations
20 moves in `assets/animations/fight_gen.glb` (uppercut, haymaker, kicks,
knee, elbow, stomp, taunt, flex...) were generated from our own text
descriptions (`tools/moves.txt`) with **MoMask** (Guo et al., CVPR 2024; MIT
licensed code) through its public Hugging Face demo.
> Note before a commercial release: MoMask's model was trained on the
> HumanML3D / AMASS research motion datasets, whose licences are for
> non-commercial research. Generated motions are new, but the status of
> selling a game that uses them is unsettled. Replace them with licensed
> clips (e.g. Mixamo or a paid pack) before charging money.

## Textures and props (CC0)
**Poly Haven** (polyhaven.com) — CC0. Textures in `assets/textures/`, props in
`assets/props/` (decimated), tree impostors in `assets/trees/` rendered from
`fir_sapling_medium`.

## Sound (CC0)
Recorded effects in `assets/sounds/`, all CC0 from OpenGameArt.org:
- punches, heavy hits, blocks: **"37 hits/punches"** by Independent.nu (submitted by qubodup)
- crashes, scrapes, bell, door, click, landing: **"100 CC0 SFX"** by rubberduck
- explosions: **"25 CC0 bang / firework SFX"** by rubberduck
- engine loop: **"Racing car engine sound loops"** by domasx2

Whooshes, the surge, beeps, the horn, tyres and the crowd are synthesised in
`scripts/core/sfx.gd`.

## Key art
Loading screen and menu background (`assets/ui/`) generated with ForgeGUI
from the author's own Nash design.

## Engine
Made with **Godot Engine** (MIT licence).
