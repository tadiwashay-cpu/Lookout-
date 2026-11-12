# Lookout

Open-world action game for Android (Godot 4.4, Mobile renderer, built for
phones with 4 GB RAM and up).

Nash grew up without his father, Maxim, a horrid man, and stopped believing
in good or bad. A hustler who robs banks one week and helps the police the
next, he goes looking for a gig near his father's shady business, steals a
few vials marked **PROJECT AXIOM**, gets jumped while running, and lands on
one. It rewrites him: superhuman speed, strength, a power surge, and combat
instincts beyond decades of military training. He wants revenge on the men
who jumped him, and on his father. *(Story missions come after the career
and multiplayer.)*

## What's in it now
- **Open world, 2.4 km square**: downtown grid, harbour and sea, suburbs,
  forest hills, a mountain range with a pass road. Everything is joined by
  roads.
- **Enterable buildings** with staff at work: Auto Repair (repairs, respray,
  nitro), City Clinic, Harbor Diner, Iron Gym, First Harbor Bank.
- **Fighting** in the Def Jam style: combos, shoulder charge, block, dodge
  roll, power surge, a side-on fight camera, cinematic finishers, hit-stop
  and camera shake.
- **Driving**: the car pack, with planted arcade handling (Forza / NFS: Most
  Wanted feel), nitro, damage, smoke, fire and explosions, and an NFS: MW
  style HUD.
- **Multiplayer**: games on the same Wi-Fi find each other automatically; or
  join by IP.
  - **Clean Hands**: a bare-knuckle brawl in the harbour ring. The host sets
    the timer; the most KOs wins the biggest purse.
  - **Street Race**: up to 8 players over the grand loop. Grenades and power
    surges are allowed. A car that takes too much damage explodes, and its
    driver respawns where they died.
  - Both modes can be played solo against bots.

## Run it
Open `project.godot` in Godot 4.4+, then press Play. Export to Android with
the standard Android export template.

## Controls
| | Touch | Keyboard | Gamepad |
|---|---|---|---|
| Move / steer | left joystick | WASD | left stick |
| Look | drag right side | mouse | right stick |
| Punch (combo) | PUNCH | J | X |
| Heavy / finisher | HEAVY | K | Y |
| Block | BLOCK (hold) | L | LB |
| Dodge | DODGE | Ctrl | B |
| Power surge | SURGE | Q | R3 |
| Enter / exit / use | ENTER | E | RB |
| Gas / brake | GAS / BRAKE | W / S | RT / LT |
| Nitro | NITRO | Shift | — |
| Drift (handbrake) | DRIFT | Space | — |
| Grenade (race) | GRENADE | G | — |

## Layout
| Path | What |
|---|---|
| `scripts/core/` | `Game` (settings, money, input map), `Net` (LAN / IP multiplayer), `Sfx` |
| `scripts/world/` | terrain, roads, city, regions, services and interiors, the ring |
| `scripts/actors/` | humanoid animation, fighter combat, Nash, bots, other players, pedestrians, camera, effects |
| `scripts/vehicles/` | car physics, catalogue, race AI, grenades |
| `scripts/modes/` | free roam, Clean Hands, Street Race, network sync |
| `scripts/ui/` | main menu and lobby, HUD, touch controls |
| `tools/` | asset pipeline (rig prep, prop decimation, tree impostors, downloads) and `tools/capture/` dev test scenes |
| `docs/ASSETS.md` | where the art comes from and where to get more |
