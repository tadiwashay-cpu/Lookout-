# Art Direction: Port Halden

The goal: a city that looks **lived-in and specific**, not the generic
neon-cyberpunk "AI city". If a choice makes the city look like every other
procedurally generated sci-fi street, don't make it.

## Do
- **Materials with history**: soot-stained brick, water-streaked
  concrete, flaking painted render, rusted steel, wet asphalt with
  patched repairs. Grime collects at the bottom of walls and under
  sills.
- **Real light sources**: low overcast or late-afternoon sun; warm
  **sodium-orange** streetlights at night; fluorescent tube light
  spilling from shop interiors. Colour comes from *practical* sources.
- **Restrained palette**: desaturated greys, browns, brick reds, harbour
  blue-greys. Saturated colour is rare and meaningful: the Low Tide's
  red bandanas, police blue-and-red lights, the hero's chrome
  reflecting the sky.
- **Human scale at street level**: shop signs with invented local
  businesses, awnings, fire escapes, AC units, gutters, bins, bollards,
  parked cars, tram wires. Most of the detail budget goes in the first
  6 m of every building.
- **Architectural eras that clash**: 1900s brick tenements next to 1960s
  concrete, with a few newer glass towers downtown.
- **Weather**: rain and wet-road reflections are a big part of the mood
  (reflection probes plus a wet-material shader pass).

## Don't
- No neon-everything, holograms, purple/teal grading, floating ads,
  glowing cyber trim on every surface.
- No clean, untextured "plastic" buildings, and no uniform window grids
  without variation.
- No random sci-fi kitbash. Tech exists, but it's grimy and
  utilitarian. The Trench is industrial and submarine-like, not a
  glowing lab.

## The hero against the city
The hero's mirror-chrome armour is the brightest thing on screen. It
reflects the grey city around him, so the world's palette lands on him.
Keep the environment matte enough that he pops.

## Production rules (mobile)
- Buildings: modular kits + **trim sheets** + decals (grime, posters,
  graffiti tags), not unique textures per building.
- Texel density: ~5.12 px/cm for street-level props, half that above the
  2nd floor.
- Textures: 2048² maximum for the hero, 1024² for props, ASTC
  compressed.
- Every repeated object (lamp posts, windows, trees, road markings) is
  drawn through a MultiMesh or with GPU instancing.
