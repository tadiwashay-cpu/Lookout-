# Lookout

Open-world anti-hero action game for **Android**, built with **Godot 4 (Mobile renderer)**.

- Design: [`docs/game-design.md`](docs/game-design.md)
- Art direction: [`docs/art-direction.md`](docs/art-direction.md)
- Hero model pipeline: [`docs/character-pipeline.md`](docs/character-pipeline.md)
- Multiplayer: [`docs/multiplayer.md`](docs/multiplayer.md)
- Third-party asset credits: [`CREDITS.md`](CREDITS.md)

## Run it
1. Install Godot **4.4 or newer**. The Android editor app works.
2. Project Manager → **Import** → choose `project.godot`.
3. Press **Play**. You start at the **main menu**: pick **X** or **Y Bot**,
   then **Story** (you spawn in the crew's HQ), **Multiplayer** or
   **Settings**.

## Controls
| | Touch (Android) | Keyboard / mouse | Gamepad |
|---|---|---|---|
| Move | Left-thumb joystick (push to edge = sprint) | WASD | Left stick |
| Look | Drag on the right half | Mouse (click to capture) | Right stick |
| Punch (combo) | PUNCH | J | X |
| Heavy punch | HEAVY | K | Y |
| Dodge | DODGE | L | B |
| Jump | JUMP | Space | A |
| Sprint | joystick to edge | Shift | L3 |
| First/third person | CAM | V | Back/Select |
| Enter / exit car | ENTER / EXIT (appears near a car) | E | RB |
| Drive | Joystick steers, GAS / REV, BRAKE = handbrake | W/S, A/D, Space | Stick, RB to exit |

## Project layout
| Path | Contents |
|---|---|
| `scripts/autoloads/` | `InputSetup` (input map), `GameSettings` (saved prefs), `WantedSystem` (police heat) |
| `scripts/player/` | Hero controller: camera, movement, combat |
| `scripts/enemies/` | Goon AI |
| `scripts/missions/` | Mission / challenge logic (Clean Hands) |
| `scripts/levels/` | Level builders (greybox city) |
| `scripts/ui/` | HUD, wanted stars, touch controls |
| `scripts/components/` | Reusable components (health) |
| `scenes/` | `.tscn` scenes |
| `assets/` | Models (`.glb`), textures, audio, fonts |
| `docs/` | Design docs and concept art |

## Adding assets
- Models as **`.glb`**, ≤ 40k triangles for the hero.
- Keep files under 100 MB (GitHub's limit); browser uploads are capped at 25 MB.
- Lowercase names with underscores, e.g. `goon_thug_a.glb`.
