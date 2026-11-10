# Credits

## Third-party assets

### Vehicles
**"Generic passenger car pack"** by **Comrade1280**
https://sketchfab.com/3d-models/generic-passenger-car-pack-20f9af9b8a404d5cb022ac6fe87f21f5
Licensed under **CC BY 4.0** (https://creativecommons.org/licenses/by/4.0/).
Changes: split into one file per vehicle, re-oriented and re-centred,
wheels separated for physics (`tools/split_cars.py`); paint recoloured in-game.
Files: `assets/models/vehicles/*.glb`

> CC BY 4.0 requires this credit to ship with the game (e.g. in the in-game
> credits screen and the store listing).

### Characters and animations
**X Bot**, **Y Bot** and the animation clips come from **Adobe Mixamo**
(mixamo.com). They're free to use in games, royalty-free, under the Mixamo
terms. Converted with `tools/convert_mixamo.py`: one GLB per character
with every clip, root motion removed.
Files: `assets/models/characters/*.glb`, portraits in `assets/ui/portraits/`.

**Combat pack** (`Combat.zip`, Mixamo clips): fighting idle, boxing,
front kick, roundhouse kick, KO fall and KO win. Trimmed to the moves
and converted at 30 fps.

**Third Person Shooter Animation Sets** by ZenXChaos
(github.com/ZenXChaos/ThirdPersonShooter-AnimationSets, made for Unity).
Clips used: unarmed idle, walk, run and sprint, start and stop steps,
falling, death, and the pistol and shotgun sets. They were read from
the FBX 6 files with `tools/extract_fbx6_anim.py` (ufbx) and retargeted
onto the Mixamo skeleton with `tools/convert_mixamo.py --retarget`.
⚠️ Check the repo's licence terms before release.

### City people (pedestrians, bots, SWAT)
**Ultimate Modular Men** and **Ultimate Modular Women** by **Quaternius**
(quaternius.com), **CC0 1.0** (public domain). 14 city outfits plus the
SWAT and soldier models. They were converted with
`tools/retarget_quaternius.py`: bones renamed to Mixamo names and our 53
clips retargeted onto them.
Files: `assets/models/characters/civilians/` (licence file included).

### Add-ons
See `addons/ADDONS.md`: Debug Menu, Phantom Camera, GPUTrail, Road
Generator and netfox, all MIT.

### NPCs
**Rigged Low Poly Man** (Mixamo skeleton). Used for goons, pedestrians,
cops and bots, tinted per role. ⚠️ Source and licence to be filled in.
File: `assets/models/characters/npc_man.glb` (with the Mixamo clip set).

### Police car
**Ford Crown Victoria Police Interceptor**. ⚠️ Source and licence to be
filled in. Converted with `tools/convert_crown_vic.py`: decimated from
235k to about 21k triangles, scaled to the real 2.91 m wheelbase, wheels
split for physics.
File: `assets/models/vehicles/crown_vic.glb`

### Weapons pack
**Weapons.fbx** (low-poly guns: AK47, M16A4, SCAR-H, G36, MP5K, Uzi,
P90, Glock 17, Desert Eagle, SPAS-12, AWP, M249). ⚠️ Source and licence
to be filled in. Exported per gun with `tools/export_weapons.py`.
Files: `assets/models/weapons/*.glb`

### Weapons
**"Low Poly Colt M4A1"**. ⚠️ Source and licence to be filled in by the
project owner (check the store page the zip came from, and add the
author and licence here). Converted with `tools/make_rifle_and_portraits.py`.
File: `assets/models/weapons/m4a1.glb`
