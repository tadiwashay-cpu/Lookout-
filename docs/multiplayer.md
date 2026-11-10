# Multiplayer

## What works now: Wi-Fi play (local, no internet needed)
1. Everyone opens **Multiplayer** and picks the same **Mode**.
2. One player taps **HOST (WI-FI)**. The lobby shows that device's IP, for
   example `192.168.1.20`.
3. Everyone else types that IP and taps **JOIN**. Their names appear in the
   host's lobby.
4. The host taps **START MATCH**.

Uses Godot's built-in ENet on UDP port **7777**, up to 12 players.
**PRACTICE SOLO** runs any mode offline on one device.

## Modes
| Mode | Spawns | Win condition | Notes |
|---|---|---|---|
| **Battle Royale** | Random: harbour, suburb, forest or highway | Last alive | Zone shrinks in phases (minimap ring); outside it you take damage |
| **Street Race** | Start grid; route randomly city→highway→forest→suburb or reverse | First across the last checkpoint | Locked in an S-class car; **NADE** lobs a grenade behind you; a hit slows the car (power and top speed) for 2.5 s. Race-only cars slot into `VehicleCatalog` |
| **Robbers vs Police** | Robbers at the bank, police at the precinct | Robbers: any robber reaches the extraction zone (random region). Police: all robbers down, or the 7-minute clock runs out | Teams split at random by the host. Rifle, grenades and surge for both sides. No friendly fire. Robbers don't respawn; police do |
| **Clean Hands** | A ring (24 m) in a random region, same on every device | First to 10 knock-outs, or most KOs after 5 minutes | Fists only (no guns). Landing punches fills the surge meter (+12 a hit, +25 a finisher, +20 a KO); **SURGE** only fires when it's full. KO'd players get back up after 3 s elsewhere in the ring. Leaving the ring hurts. Solo practice: 5 brawler bots |

Winners earn money ($1000 heist, $800 battle royale, $700 race, $600 Clean Hands). Losers
get a little. Money is saved for the **gun shop** (next milestone).

## How it's built
- `Net` (`scripts/autoloads/network.gd`): host/join, lobby, state packets
  (about 15 per second), damage, eliminations and match events.
- Each device simulates its own player and sends position, animation,
  armed state and car. Other players are `RemoteAvatar`s.
- Hits are applied by the shooter's device and sent to the target
  (`send_damage`). This is fine between friends on Wi-Fi, but **not
  cheat-proof**.

## Online play (over the internet): what's needed
Wi-Fi play can't cross the internet on its own: phones sit behind routers
and mobile carriers. Options, cheapest first:
1. **Relay/matchmaking service**, for example **W4 Cloud** (built for
   Godot) or **Nakama** (open-source, self-hostable). Players find each
   other through it, and traffic is relayed.
2. **Dedicated server**: run the game headless (`--headless`) on a small
   VPS as an authoritative host. It's also the path to anti-cheat (the
   server validates hits).
3. **WebRTC** with a tiny signalling server (peer-to-peer, with a TURN
   relay as a fallback).

The game code already talks through `Net`, so switching to one of these
mostly changes `host()` and `join()`.
