# Lookout changelog

Versions are `MAJOR.MINOR.PATCH`. The number lives in `project.godot`
(`config/version`) and shows on the menu, the loading screen, the pause menu,
the corner of the HUD and in every playtest report. Bump MINOR for a batch of
features, PATCH for fixes.

## 0.3.0 — Playtest build

First build meant for friends to play and report on.

**Feel**
- Camera trails Nash and the car with a short delay, leans into the direction
  of travel, dips on landings and gets shoved by hits and crashes.
- Speed builds up: a quick push off the mark, then the sprint winds up; the
  chase camera hangs further back the faster the car goes.
- Every hit bites (short freeze), heavy hits bite harder; screen shake on
  hits, landings, scrapes and crashes.
- Score moments: confetti and a "KNOCKOUT! +1" pop-up for KOs, sparks and
  pop-ups for laps, overtakes and the finish, cash pop-ups.
- Forgiving: swings from slightly too far step in and connect; buttons
  pressed a moment early are remembered; a jump just after running off an
  edge still counts; car scrapes give the speed back and cost no damage.

**New**
- Loading screen with key art, tips and a real progress bar.
- Full world map: tap the radar (or Pause > World map).
- Traffic in free roam: cars cruise the main loop both ways, brake for you,
  honk, and pull up smoking if you ram them.
- Recorded sound effects (punches, blocks, explosions, crashes, bell, door,
  engine) instead of the synthesised ones.
- How to play screen. Playtest report screen (device, frame rates per
  session, one tap to copy).
- 20 generated fight moves: longer combo, rotating heavy moves, stomp,
  new finisher, KO celebration.

**Performance (Redmi Pad 2, 4 GB)**
- The 3D scene now renders at a fixed line count per graphics level (HIGH =
  800 lines) and is sharpened up to the screen, instead of a percentage of
  a 2.5K panel.
- Auto-tune: if 60 fps still can't be held at the lowest allowed resolution,
  one effect at a time is switched off (bloom, then shadow range and MSAA,
  then shadows) and remembered for that device.
- Effect shaders are compiled behind the loading screen (no first-punch
  stutter); traffic uses no wheel physics.

**Fixed**
- Parked cars no longer spawn inside each other.
- Removed a generated spinning kick that ended with Nash on the floor.

## 0.2.0 — Rebuild
Open world (city, harbour, suburbs, forest, mountain pass), Clean Hands and
Street Race with LAN multiplayer, enterable services, story script.
