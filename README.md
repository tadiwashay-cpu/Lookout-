# Lookout

A 3D game built with **Godot 4**.

## Opening the project
1. Install Godot 4 (4.4 or newer) from https://godotengine.org
2. Project Manager → **Import** → select this folder's `project.godot`.

## Folder layout
| Folder | What goes there |
|---|---|
| `assets/models/` | 3D models — prefer **`.glb`** (glTF binary); `.blend` also works if Blender is installed |
| `assets/textures/` | Image textures (`.png`, `.jpg`, `.webp`) |
| `assets/materials/` | Godot material resources (`.tres`) |
| `assets/audio/music/`, `assets/audio/sfx/` | `.ogg` for music, `.wav` for short sound effects |
| `assets/fonts/` | `.ttf` / `.otf` fonts |
| `scenes/levels/`, `scenes/characters/`, `scenes/ui/` | Godot scenes (`.tscn`) |
| `scripts/` | GDScript (`.gd`), split by player / enemies / systems / ui |
| `addons/` | Godot plugins |
| `docs/` | Game design notes, concept art, references |

## Adding assets
- Keep each file under **100 MB** (GitHub's hard limit); web uploads are capped at 25 MB per file.
- Export models as `.glb` with textures embedded or placed in `assets/textures/`.
- Use lowercase names with underscores, e.g. `player_idle.glb`, `rock_large_01.png`.
