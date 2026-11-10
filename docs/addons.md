# Add-ons workflow

Add-ons (plugins) live in `addons/`. Each one is listed in
`addons/ADDONS.md` with its source, commit and licence.

## Fast path (recommended)
1. **You:** tell Claude the add-on's name in chat, for example "add
   ProtonScatter".
2. **Claude:** asks you to confirm, reads the add-on's code, then
   installs it:
   `tools/add_addon.sh <owner/repo> <addon_folder>`
   This copies it into `addons/`, enables it in `project.godot` and
   records it in `addons/ADDONS.md`. Claude then wires it into the game,
   checks the code and pushes to the working branch.
3. **You:** get the latest branch onto the tablet, open Godot and test.

You don't need to install anything in the editor yourself.

## Manual path (in the Godot editor)
1. Open the **AssetLib** tab at the top of the editor, search for the
   add-on, then click **Download** and **Install**.
2. Go to **Project → Project Settings → Plugins** and tick **Enable**.
3. Tell Claude which add-on you installed so it gets wired in and listed
   in `addons/ADDONS.md`.

## Rules for this project
- **GDScript add-ons** (no `.gdextension` file) work on every device.
  `add_addon.sh` handles them.
- **GDExtension add-ons** (native code, such as Terrain3D and LimboAI)
  need the prebuilt **Android** binaries from the add-on's Releases page.
  Claude installs these by hand. The script prints a warning if it sees
  one.
- **One add-on at a time.** Test FPS and memory on the Redmi Pad
  (4 GB) after each one.
- **Licence:** only MIT, Apache, CC0 or similar. Check `ADDONS.md`
  before release.

## Candidates
| Add-on | Repo (`owner/repo`) | Folder | Type | What for |
|---|---|---|---|---|
| Debug Menu | godot-extended-libraries/godot-debug-menu | debug_menu | GDScript | In-game FPS and frame time |
| Road Generator | TheDuckCow/godot-road-generator | road-generator | GDScript | Proper curved roads and junctions |
| ProtonScatter | HungryProton/scatter | proton_scatter | GDScript | Paint trees, rocks and props |
| Beehave | bitbrain/beehave | beehave | GDScript | Behaviour trees for goons and police |
| Netfox | foxssake/netfox | netfox | GDScript | Smoother multiplayer over Wi-Fi |
| Phantom Camera | ramokz/phantom-camera | phantom_camera | GDScript | Cinematic and chase cameras |
| Dialogic 2 | dialogic-godot/dialogic | dialogic | GDScript | Story dialogue and cutscenes |
| Terrain3D | TokisanGames/Terrain3D | terrain_3d | GDExtension | Sculpted forest and coast terrain |
| LimboAI | limbonaut/limboai | limboai | GDExtension | Advanced AI (alternative to Beehave) |

Folder names come from each repo's `addons/` directory. The script
lists the available folders if a name is wrong.
