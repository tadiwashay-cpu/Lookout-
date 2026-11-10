# Lookout — Game Design Doc

_Living document. Working title: **Lookout**._

## 1. Pitch
An open-world action game on Android about a chrome-armoured hero in a
harbour city who isn't automatically one of the good guys. Fight the gangs
terrorising the streets, but every punch thrown in public, every car
taken and every cop you hit is noticed. Save the city or become its
problem, and the police will treat you accordingly.

## 2. Pillars
1. **Anti-hero, not super-hero.** Your choices move two meters:
   *Reputation* (Protector ↔ Menace) and *Heat* (police wanted level).
   The police chase you whether or not you were "right".
2. **Fights that feel heavy.** Hit-stop, camera shake, haptics,
   readable enemy wind-ups, combo finishers. Fists first, guns later.
3. **One connected world.** City → forest → underwater base, no loading
   screens between districts (streamed cells).
4. **AAA *feel* on a tablet.** We don't brute-force fidelity. We win on
   lighting, animation, audio, camera and art direction (see §9).

## 2b. Characters
Players choose **X Bot** or **Y Bot** in the main menu; the choice is
shown to other players too. (The earlier chrome hero concept is retired.)
Animations: Mixamo rifle set (idle, walk, run, backwards, strafes, fire,
reload, jump, grenade toss, hit, turns). **Still needed from Mixamo:**
unarmed punches (Jab, Cross, Hook, Uppercut), Dodge/Roll, Knocked Out /
Death, Unarmed Idle, Driving pose. Name the files `punch_1`, `punch_2`,
`punch_3`, `punch_heavy`, `dodge`, `knocked_out`, `idle_unarmed` and run
`tools/convert_mixamo.py`; the game picks them up by name.

## 3. The hero (retired concept, kept for reference)
- Concept: `docs/concept/hero_concept_front.jpg`. Polished chrome armour
  over a dark undersuit, pointed shoulder plates, flared boots,
  "WS" chest emblem, "$" emblem on the shins.
- Name: _TBD_.
- Moveset (M0): 3-hit light combo (3rd hit = finisher), heavy punch
  (finisher), dodge with i-frames, jump, sprint.
- Later: grapple / throw, wall-run or armour boost (TBD), guns,
  vehicles.

## 4. Camera
- **Third person** (over-the-shoulder spring-arm) or **first person**,
  switched with the CAM button and remembered between sessions
  (`GameSettings.camera_mode`).
- In first person the body still casts a shadow (shadow-only mode).
- Later: first-person arms rig for punches and gun handling.

## 5. Heat and reputation
| Action | Heat | Notes |
|---|---|---|
| Brawling goons in public | +8 per hit, **capped at 1★** | Vigilante noise. Cops notice but don't escalate. |
| Hitting a civilian | +45 | |
| Discharging a gun | +60 | |
| Stealing a civilian car | +35 | First time you take that car |
| Stealing a police car | +120 | |
| Assaulting police | +90 | |

- 1★ patrol cars investigate → 2★ pursuit → 3★ roadblocks → 4★ SWAT
  → 5★ helicopter + armoured units.
- Heat decays 8 s after the last crime once you are out of police sight
  (`WantedSystem`).
- Reputation (M2) changes how civilians react (cheer, flee, call cops)
  and which missions open up.

## 6. World: Port Halden (built)
Everything is connected, and the map is about 1.7 × 2.1 km:
- **City**: Brooklyn-style grid. Brownstone rows with stoops (west),
  brick tenements and DUMBO-like warehouses (centre and waterfront),
  stepped towers downtown (north-east), plus a park, First Harbor Bank,
  the 84th Precinct, and **THE LOOKOUT** (the crew's HQ, where the story
  starts).
- **Harbour**: quay, container yard, gantry cranes, two piers and a
  docked cargo ship, directly east of the city.
- **Highway**: four lanes curving north from the city past the harbour
  into the forest, with guardrails and lights.
- **Forest**: hills, about 1,800 pines, a dirt road and a ranger lookout
  tower.
- **Suburb**: west of the forest, with houses, lawns, driveways and
  fences.

Multiplayer spawns: harbour, suburb, forest, highway.

### Original region notes
A grey, rust-belt harbour city on a cold northern coast.

| Zone | Description | Gameplay |
|---|---|---|
| **Old Market District** | Brick tenements, covered market, narrow alleys, tram lines | Clean Hands level, street fights, rooftop routes |
| **Downtown** | Mid-century concrete and glass office blocks, plazas | Police HQ, chases, heists |
| **Docks & Industrial** | Cranes, containers, warehouses, rail yard | Smuggling missions, access to the sub pen |
| **Greywood Forest** | Pine hills north of the city, logging roads, ranger towers, a dam | Off-road pursuit, hideouts, hunting gang camps |
| **The Trench** | A huge decommissioned submarine hull anchored on the seabed and converted into a hidden base | Interior level: tight corridors, flooding sections, final act |

Map target: roughly 2 × 2 km of drivable space at launch, split into
streamed 128 m cells.

## 6b. Vehicles
Ten civilian cars and two police vehicles, all drivable. Each has a
**hidden class (D → S)** that sets its engine, top speed, braking, grip
and durability, and how rare it is to find. **Classes are never shown in
the game.** Players learn them by driving.

| Vehicle | Class (hidden) | Drive | Where it's found |
|---|---|---|---|
| Compact | D | FWD | Everywhere |
| Minivan | D | FWD | Everywhere |
| Hatchback | C | FWD | Common |
| Sedan | C | RWD | Common |
| Wagon | C | RWD | Common |
| Pickup | C | AWD | Common (more in the docks and forest later) |
| SUV | B | AWD | Uncommon |
| Offroad | B | AWD | Uncommon (forest favourite) |
| Coupe | A | RWD | Rare |
| Sport | **S** | RWD | **One per district, hidden in a back alley** |
| Police Interceptor (sedan) | A | RWD | Parked at precincts. Taking one is +120 heat |
| Police Utility (SUV) | B | AWD | Parked at precincts. Taking one is +120 heat |

- Civilian cars spawn in a muted paint palette (in-game repaint shader).
  Police are navy (interceptor) and black (utility) with roof light
  bars that flash while driven.
- Enter/exit with **ENTER / EXIT** (E key, RB). Chase camera in third
  person, driver's-seat view in first person (follows the CAM setting).
- Driving controls: the joystick steers; **GAS / REV** pedals;
  **BRAKE** = handbrake.
- Running goons over hurts them, but it doesn't count for Clean Hands.
- Next: police AI that chases in these same two vehicles (M2), car
  damage, traffic.
- Tuning lives in `scripts/vehicles/vehicle_catalog.gd`.

## 6c. Police pursuit (NFS: Most Wanted style)
- Heat 1★ to 5★ means 1 to 6 Crown Vic interceptors. Black SUVs join at 4★ and up.
- Units are slightly faster than your car. They lead your path, ram your
  rear quarter, and box you in (left and right slots). If you outrun them
  out of sight, they're re-dispatched onto a road behind you.
- 3★ and up: roadblocks (two cruisers across the road about 150 m ahead).
- On foot: cars pull up and two officers get out. They tackle at 1★,
  carry pistols at 2★, and carry rifles at 3★ and up.
- **Busted**: crawling (under 2.5 m/s) with a cruiser within 9 m for 3 s.
  You get a fine (10% of your money, up to $500) and respawn at the
  precinct.
- **Evade**: break line of sight. Heat decays once no unit has seen you
  for a few seconds.
- Code: `scripts/ai/police_manager.gd`, `scripts/ai/car_pilot.gd`.

## 6d. NPCs and bots
- Pedestrians (Low Poly Man, random outfits): up to 12 around you in the
  city and suburb. They flee from crimes and gunfire. Hurting them raises
  heat.
- Goons: the Low Tide crew in red jackets, with punch, hit and death
  animations.
- Solo practice bots:
  - Battle Royale: 9 armed bots that follow the zone and fight everyone.
  - Street Race: 3 AI racers.
  - Robbers vs Police: officers on foot plus a pursuit.
  - Clean Hands: 5 brawler bots that punch and kick each other and you.

## 6d2. Movement and animation
- Unarmed is the default: walk, run, sprint, start and stop steps,
  falling, and a fighting stance when enemies are close.
- The gun comes out only when you shoot, aim or press SWAP. It goes
  away after 10 seconds without use. Pistols use pistol idle, walk and
  reload clips. Long guns use rifle and shotgun clips.
- Fist combos: three punches; HEAVY alternates front kick, roundhouse
  and heavy punch; flying kick while sprinting. A knock-out plays the
  KO fall.
- Pedestrians: walk, stop and idle, with start/stop steps, and run when
  they panic. Goons raise their guard when you're close.
- Cars leave skid marks when drifting or handbraking.

## 6e. Guns and the shop
13 guns with distinct stats (`scripts/weapons/weapon_catalog.gd`): the
M4A1 (starter), plus AK-47, M16A4, G36, SCAR-H, MP5K, Uzi, P90, Glock,
Deagle, SPAS-12 (8 pellets), AWP and M249. Buy and equip them in
**Main menu → SHOP** with money from missions and multiplayer.

## 6f. Atmosphere
- Day and night cycle (Settings: minutes per day). At night: moon, lit
  windows, glowing street lamps, orange dusk.
- Cloud layer over the map, and billowing clouds plus valley mist over
  the forest.
- About 330 rocks: cover clusters in the forest, highway shoulders,
  suburb, park and harbour.

## 7. Factions
- **Low Tide crew**: street gang terrorising the market. Red bandanas.
  Melee early, firearms later.
- **Halden Police Department (HPD)**: escalating response tied to Heat.
- **Meridian Salvage**: "salvage" corporation running The Trench. The
  late-game antagonist.

## 8. Levels and missions
### Clean Hands (implemented as a greybox)
The Low Tide crew is terrorising the old market. **No weapons**: guns are
disabled for this mission.
- Put down 12 goons.
- Land 5 combo finishers (third hit of a combo).
- Keep Heat at 2★ or below. Brawling alone can't push you past 1★, so
  going over means you hurt a civilian or a cop.
- Later additions: protect the shopkeepers, chase down the crew boss,
  optional "no damage taken" medal.

### Planned
- Market boss fight, a rooftop chase, the first police pursuit, the
  forest gang camp, docks infiltration, and The Trench (multi-stage
  finale).

## 9. AAA feel on Android: how we get there
- **Lighting**: one dynamic sun with shadows, plus *baked* lighting
  (LightmapGI) for static city geometry, reflection probes per district,
  and a strong time-of-day grade. Baked GI is the biggest visual win per
  millisecond on mobile.
- **Animation**: proper locomotion blend space, root-motion punches,
  hit reactions, finisher cameras. Placeholder tweens are used until the
  rig lands.
- **Combat feedback**: hit-stop, shake, haptics, impact VFX, and layered
  punch audio (whoosh + flesh + armour clank).
- **Audio**: city ambience beds per district, a police scanner when
  wanted, dynamic music that rises with Heat.
- **Detail where the camera looks**: high-quality hero and street-level
  props; buildings use trim sheets and decals, not unique textures.
- **Performance discipline**: see §10.

## 10. Performance budget (mid-range Android tablet)
| Item | Budget |
|---|---|
| Frame rate | 30 fps locked by default; 60 fps "performance" option |
| Renderer | Godot **Mobile** renderer (Vulkan) |
| Draw calls on screen | < 300 (MultiMesh for repeats: lamps, windows, markings, trees) |
| Hero | ≤ 40k triangles, one 2048² texture set (ASTC) |
| Enemies | ≤ 15k triangles each, shared atlas |
| Buildings | ≤ 2k tris each with LODs + `visibility_range` culling |
| Active AI | ≤ 12 fighting, the rest simplified |
| Shadows | Sun only, 2 splits, 80 m max |
| Textures | ASTC / ETC2 compression (enabled in project settings) |

## 11. Controls (Android)
- Left thumb: floating joystick (push to the edge to sprint).
- Right thumb: drag to look.
- Buttons: PUNCH, HEAVY, DODGE, JUMP, CAM.
- Gamepad and keyboard are supported for testing.

## 12. Multiplayer
_To be designed later._ Keep game state serialisable and AI
server-authoritative-friendly so co-op or PvP can be added.

## 13. Roadmap
| Milestone | Content | Status |
|---|---|---|
| **M0** | Project setup, mobile renderer, touch controls, TPS/FPS camera, fist combat, goon AI, Heat system, Clean Hands greybox | ✅ in this branch |
| **M1** | Hero 3D model imported ✅ (static); rig + animations, impact VFX/SFX | Needs rigging (see `docs/character-pipeline.md`) |
| **M1.5** | Drivable cars (10 civilian + 2 police), hidden D–S classes, repaint | ✅ |
| **M2** | Police AI and pursuit, civilians, reputation | |
| **M3** | Guns, aiming (TPS/FPS), cover; goons with firearms | |
| **M4** | World streaming, full market district art pass, baked lighting | |
| **M5** | Greywood Forest | |
| **M6** | The Trench (underwater base) | |
| **M7** | Multiplayer | |
