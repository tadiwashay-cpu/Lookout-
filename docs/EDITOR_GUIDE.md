# Fixing and editing Lookout yourself (Godot on the tablet)

You don't need to code much. Most fixes are finding a line and changing a
number. This guide shows where everything is and what to touch.

---

## 0. First, understand this one thing

**Lookout is built by scripts, not by hand-placed scenes.** When you open
`main.tscn` or `world.tscn` you'll see only one node and an empty grid. That's
normal. The city, roads, cars and people are created by code when you press
**Play**. So:

- To *see* the game, press **▶ Play** (top right).
- To *change* the game, you edit **scripts** (`.gd` files) or **assets**
  (pictures, sounds, models).

The main menu is a 2D screen. If the 3D grid shows an empty scene, tap **2D**
at the top to see it.

---

## 1. Running the game

| Button (top right) | What it does |
|---|---|
| ▶ | Plays the whole game from the main menu |
| ⏸ / ■ | Pause / stop the game |
| 🎬 with a ▶ | Plays only the scene you have open |

To get back to the editor while it's playing, tap **■ Stop** (or use the
Android back gesture and stop it).

---

## 2. When something breaks: find the error

1. Tap **Debugger** at the bottom, then the **Errors** tab.
2. Each error shows a **file and line number**, like
   `res://scripts/actors/fighter.gd:242`.
3. Tap the error. Godot opens that script at that line.
4. Red lines in the script editor are mistakes. The message at the bottom of
   the script editor says what's wrong.

**Output** (bottom tab) shows everything printed while the game runs,
warnings included. Yellow = warning (usually OK), red = error (fix it).

### Common errors and what to do

| Message | Meaning | Fix |
|---|---|---|
| `Parse Error: ...` | A typo in a script | Go to the line. Check brackets `( )`, quotes `" "`, colons `:` at the end of `func`/`if`/`for` lines |
| `Mixed use of tabs and spaces` | Indentation is broken | Lines inside a block must start with **tabs**. Delete the spaces at the start and press Tab |
| `Identifier "x" not declared` | A name is spelled wrong | Check the spelling. Names are case-sensitive (`Player` ≠ `player`) |
| `Invalid get index 'x' (on base: 'Nil')` | Something wasn't there yet | Tell me the file and line, this one usually needs me |
| `Cannot open file` / `Missing dependencies` | A file was moved or renamed | Put it back where it was, with the same name |
| `Failed loading resource` (a model or picture) | It didn't import | Select the file, open the **Import** tab, press **Reimport** |
| Everything looks broken after updating | Old cached imports | Close Godot, delete the hidden `.godot` folder in the project, open again (it reimports everything; takes a few minutes) |

**Golden rule:** if you change something and it breaks, press **Undo**
(the curved arrow on the right toolbar) until it works again.

---

## 3. Editing a script safely

1. In **FileSystem** (bottom left) open `scripts/`, then tap a `.gd` file.
   The **Script** tab opens it.
2. Change only the **numbers or text** described below. Don't change words
   like `func`, `var`, `const`, `if`.
3. Save: the 💾 button on the right toolbar.
4. Press ▶ to test.

To search inside a script: the Search 🔍 in the script editor (Find).
To search **all** scripts: Script tab menu → **Search in Files**.

---

## 4. "I want to change..." (the cheat sheet)

| You want to change | File | What to edit |
|---|---|---|
| **Punch damage, speed, reach** | `scripts/actors/fighter.gd` | The `ATTACKS` list at the top: `"damage": 7.0`, `"range": 1.7`, `"speed": 1.35`. The `GENERATED` list: `[clip, damage, push, heavy]` |
| **Combo order / heavy moves** | `scripts/actors/fighter.gd` | `COMBO := [...]` and `HEAVIES := [...]`. Use names that already exist in `GENERATED` or `ATTACKS` |
| **Nash's health, speed** | `scripts/actors/player.gd` (`max_health = 160.0`) and `fighter.gd` (`run_speed`, `sprint_speed`, `jump_velocity`) | |
| **Bot difficulty** | `scripts/actors/bot_fighter.gd` | `run_speed`, `sprint_speed` in `_ready()` |
| **Car speed, grip, acceleration** | `scripts/vehicles/car_catalog.gd` | Each car: `"top"` (metres/second, 70 ≈ 250 km/h), `"accel"`, `"grip"`, `"steer"`, `"health"` |
| **Car handling feel** | `scripts/vehicles/car.gd` | In `_assist`: `hold` (sideways grip), `max_yaw` (how fast it turns) |
| **Camera distance, height, field of view** | `scripts/actors/camera_rig.gd` | `distance := 4.8`, `base_fov := 70.0`; car camera: `var back := 6.0 + ...` |
| **Screen shake strength** | `scripts/actors/player.gd` | Numbers in `CameraRig.shake_all(...)` and `kick_all(...)` |
| **Hit-stop (freeze on hit)** | `scripts/actors/player.gd` | `Game.hitstop(0.075 if heavy else 0.03)` |
| **Graphics presets / FPS** | `scripts/core/game.gd` | `PRESETS`: `"lines"` = 3D resolution (800 on HIGH; lower = faster), `"shadow"`, `"glow"`, `"view"` (draw distance) |
| **Touch button positions and sizes** | `scripts/ui/touch_controls.gd` | In `_build`: `"p": br + Vector2(-175, 20)` = position, `"r": 64.0` = size |
| **Traffic amount** | `scripts/vehicles/traffic.gd` | `max_cars = [4, 6, 8, 10]` (per graphics level), `cruise` speed |
| **Race prizes, Clean Hands money** | `scripts/modes/race.gd` (`PRIZES`), `scripts/modes/clean_hands.gd` (`PURSE`, `PER_KO`) | |
| **Where things are on the map** | `scripts/world/layout.gd` | `RING_CENTER`, `PLAYER_START`, road points in `ROADS` |
| **Shop names and colours** | `scripts/world/services.gd` | `KINDS` at the top |
| **Loading screen tips** | `scripts/core/game.gd` | `TIPS := [...]` |
| **Version number** | Project → Project Settings → Application → Config → **Version** | Also update `CHANGELOG.md` |

---

## 5. Replacing art and sounds (no code needed)

Keep the **same file name** and the game picks it up automatically.

| Thing | File to replace |
|---|---|
| Loading screen picture | `assets/ui/loading.jpg` (wide, 16:9) |
| Menu background | `assets/ui/menu_bg.jpg` |
| Punch sounds | `assets/sounds/punch_1.wav` … `punch_5.wav` (more takes = `punch_6.wav`, up to 7) |
| Heavy hits, blocks, crashes, explosions | `heavy_N.wav`, `block_N.wav`, `crash_N.wav`, `explosion_N.wav` |
| Bell, door, click, landing | `bell.wav`, `door.wav`, `click.wav`, `land.wav` |
| Engine | `engine_loop.wav` (a short sound that loops cleanly) |

Sounds must be **.wav**. ForgeGUI gives MP3: convert it first (any
"MP3 to WAV" app), or tell me and I'll convert it.

### How to get a file into the project on Android
1. Find your project folder with your **Files** app (the folder that has
   `project.godot` in it).
2. Copy the new file into the right folder (for example `assets/sounds/`),
   replacing the old one.
3. Switch back to Godot. It notices the new file and imports it (a short
   progress bar). If it doesn't, tap the file in FileSystem → **Import** tab
   → **Reimport**.

---

## 6. Importing a new character (for example from ForgeGUI)

The game can only animate a character whose skeleton is mapped to Godot's
standard humanoid skeleton. Here's how:

1. Copy the `.glb` into `assets/characters/` (or `assets/characters/npc/` for
   people on the street).
2. In FileSystem, **double-tap** the `.glb`. The **Advanced Import Settings**
   window opens.
3. In the tree on the left, tap **Skeleton3D** (or `Skeleton`).
4. On the right, find **Retarget → Bone Map**, tap it, choose **New
   BoneMap**, then tap the BoneMap again to open it.
5. Set **Profile** to **SkeletonProfileHumanoid**. Godot tries to match the
   bones itself. Green dots = matched, red = missing. The important ones are
   Hips, Spine, Chest, Neck, Head, both arms (UpperArm, LowerArm, Hand), both
   legs (UpperLeg, LowerLeg, Foot). Tap a red dot and pick the right bone
   from the list if one is missing.
6. Turn on **Rename Bones** and **Unique Node → Make Unique** with the name
   **GeneralSkeleton**.
7. Press **Reimport**.
8. To use it:
   - As **Nash**: name the file `nash.glb` and replace the old one (simplest),
     or change `NASH := "res://assets/characters/nash.glb"` in
     `scripts/actors/humanoid.gd`.
   - As an **NPC**: put it in `assets/characters/npc/` and add its name
     (without `.glb`) to the `NPCS` list in `scripts/actors/humanoid.gd`.
9. Press ▶ and walk around. If the character lies down, floats, or twists:
   the bone map is wrong (go back to step 5), or the model faces the wrong
   way. Send me a screenshot.

**Tip:** ask ForgeGUI for **T-pose** and use its **Rig** option. Rigged
models map much better.

---

## 7. Working together with me

You have the project on the tablet; I have it on GitHub. To keep both the
same:

**When you fix something yourself**, tell me which file and what you changed
(a screenshot of the lines is perfect). I'll make the same change on GitHub
so the next APK has it and my next update doesn't undo it.

**When I push an update**, get the newest version:
1. Open https://github.com/tadiwashay-cpu/Lookout- on the tablet.
2. Switch the branch to `ccr-0b872a40-0ahxen`.
3. **Code → Download ZIP**, unzip it, and copy it over your project folder
   (keep your own changes somewhere first if you haven't sent them to me).

**Godot version:** the project was made in Godot **4.4**, and your tablet has
**4.7**. Opening it in 4.7 is fine, but Godot may ask to upgrade files. Say
yes on the tablet. Don't send me whole `.tscn` or `.import` files from 4.7;
send me the change instead (or ask me to move the project to 4.7).

**What's easier for whom**

| You (in the editor) | Me |
|---|---|
| Tuning numbers until it *feels* right (damage, speed, camera, buttons) | New features, new systems, anything with lots of code |
| Swapping pictures and sounds | Fixing errors you can't find on a line |
| Importing and bone-mapping models (needs looking at the screen) | Bulk work: converting, generating, building the APK |
| Watching it run on the real tablet and reading the FPS | Performance work across the whole game |
