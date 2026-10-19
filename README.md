# WRECKSMITH

A physics gladiator brawler in **Godot 4.7** (GDScript, Jolt physics at 120 Hz). Fighters are built
from voxels and lose them to every cut, thrust and blow. You build your own weapons in a voxel
forge, and you face 24 species of beasts. Multiplayer is host-authoritative, over **GodotSteam**
lobbies or plain ENet.

The game's tables (weapon presets, materials, body plans, beasts, the campaign's stages and pay,
shop prices, controls) live in `data/*.json`. They were exported from the original browser
prototype of the game.

```bash
godot --path .                   # play (or open project.godot in the editor)
sh run_tests.sh                  # parse check, headless test suites, two-process network test
godot --headless --path . -- --test test_fight   # one suite
```

`GODOT=/path/to/godot` points the scripts at a Godot binary other than `/opt/godot/...`.

## What is in the game

- **Fighters**: voxel body parts as rigid bodies on joints. A PD-driven balance spring and leg
  control. Falling, getting up, and Half Sword mouse hands, with each hand on its own button.
- **Damage**: per-voxel damage by material and hit type (cut, thrust, blunt). Dents, limbs that
  hang or come off, and blood and breath. Chips knocked off weapons wear them down. Fire.
- **Weapons**: built from the same voxel designs, with greedy-merged colliders and shields.
  Chain weapons, bows and crossbows, throwables and the market.
- **Wrestling**: grabs, shoves, trips, and the giant's lift and throw.
- **Bots** and all 24 **beast** species with their behaviours, including flying and breath.
- **The campaign**: stages of three rounds, pay, bosses on the same tables, checkpoints and
  persistent weapon wear.
- **Bread & Circuses**: the seven-day campaign (`scripts/game/circus.gd`). Every day has its
  bouts and bosses. The special bouts are in `scripts/game/bout_rules.gd`: gold rush, chariots,
  the Emperor's whims, hot potato, escorting the senator, holding the circle, and bringing back a
  head. Gold buys pots between bouts, and a god offers a blessing after each day (Fortuna spins a
  wheel). Between runs you buy ludus upgrades. There are also the Daily Games and a Hall of Fame.
- **The kill cam**: the match is recorded at 30 Hz. Every kill is scored for style (a head off,
  a throw, a punch, a giant brought down), and when the match ends the best one replays in slow
  motion, letterboxed, with a caption (`scripts/game/killcam.gd`).
- **Music**: a procedural band (frame drum, riq, drone, lyre, horn) in the Phrygian dominant. It
  has a loop for each state (menu, yard, fight, boss, victory), rendered on a thread and
  cross-faded (`scripts/autoload/music.gd`).
- **The tutorial**: eight steps in the training ring, each ticked off as soon as you do it, then a
  recruit to beat (`scripts/game/tutorial.gd`).
- **Controls**: rebindable keys (Settings → Controls) and gamepad support. The left stick walks,
  the right stick looks, and a held trigger turns the right stick into that hand.
- **The Ludus yard**: a walkable hub (`scripts/game/yard.gd`, `yard_play.gd`). It has stations
  (the arena gate, the smith, the market and the mission board; press G at one), two training
  dummies that never fall, three throwing boards that score a throw, and a shoving ring with a
  champion to push out. Three missions per fight pay denarii and reputation, and reputation
  earns ranks (Tiro up to Rudiarius). After a fight you come back to the yard.
- **The smith**: buy bases, mend, hone and temper. A voxel forge reshapes a weapon voxel by voxel.
- **Modes**: training and 14 fight and party modes (duel, best of three, free for all, chaos, co-op,
  gauntlet, monster hunt, teams, king of the arena, the Emperor, king of the hill, last limb,
  head football, players' brawl).
- **The spectacle**: the Emperor's decrees, arena hazards, the crowd's favour and the announcer,
  and drops from the stands.
- **Interface**: a title screen with a live fight behind it and a champion who wears your look.
  A gladiator editor (name, skin, cloth, hat, hair, beard, cape). The HUD, menus and options
  (four tabs: game, controls, graphics, sound). The menus in one imperial look (`scripts/ui/style.gd`):
  Cinzel capitals and Alegreya Sans (both OFL, `art/fonts`) on stone plates framed in gold; the
  fights as cards with a line each on what they are.
- **Graphics**: the arena in 10 cm voxels in the manner of Teardown (the bowl, gatehouses, the
  Emperor's box, the arcade and the props are models built by `tools/gen_voxel_art.py`), bodies,
  armour and weapons shaded by what each voxel is made of. Physics interpolation, GPU particles (blood, sparks, dust, smoke, fire, embers),
  decals for blood and scorch marks, SSAO, SSIL, SDFGI, volumetric fog and glow by quality
  level. Anti-aliasing to choose (MSAA 4x by default: the blocks' edges smooth, the rest sharp;
  or SMAA, FXAA, MSAA 2x/8x, off) and voxel corner shading (each voxel's face darkens toward the
  neighbours that shut it in, so creases and the gaps between blocks lie in shadow; on or off). An animated crowd shader, braziers, awnings, flags and the Emperor's box.
- **Audio**: procedural sounds in several takes with varied pitch, a stone-arena reverb bus, a
  crowd murmur that follows the excitement and ducks under the blows.
- **Multiplayer**: host-authoritative. Guests send input; the host sends snapshots, spawns, voxel
  losses and effects.

## Still to come


## The C++ voxel core (GDExtension)

The hot voxel loops run in C++ when the extension is built: greedy box merging for the
colliders (about 8× faster), the flood fill that finds the lumps a blow knocks loose, and the
searches over a part's voxels (wounds, craters, the flesh a joint hangs on, blood running down
the skin). With them the host's step is about 15–25% cheaper. The source
is in `extension/`. `scripts/voxel/greedy.gd` falls back to GDScript when it is absent, so a
plain checkout runs without it (and the editor does not complain about a missing library).
`tests/test_native.gd` checks that both give the same results, and `tools/replay_check.sh`
plays fixed 10-second fights single-threaded (16 and 6 fighters, and two of 24 with bows, two
hands, chains, giants and a dozen more creatures) and prints their fingerprints: a faster build
must print exactly the same ones as before. `tools/replay_bench.sh` times the same fights, so two
versions are compared on exactly the same work. The limbs' PD drives (`motor_rel`, `pd_relative`,
`pd_axis`, `pd_twist`) run in C++ too, giving the very floats the GDScript gives. To build it for Linux, then load it:

```bash
cd extension
git clone -b 4.4 --depth 1 https://github.com/godotengine/godot-cpp   # the 4.4 API: a library built for it loads in 4.7
pip install scons
scons platform=linux target=template_release      # or windows use_mingw=yes, or macos
cp ../native/voxel_core.gdextension.in ../native/voxel_core.gdextension
```

The release builds (GitHub Actions) build it for Windows, Linux and macOS and load it.

The CI workflow builds it for all three platforms before exporting.

## Multiplayer and GodotSteam

`scripts/net/net.gd` reaches GodotSteam only through `Engine.get_singleton("Steam")` and
`ClassDB`, so the project runs on stock Godot. It falls back to ENet on port 7777.

To use Steam:

1. Install the **GodotSteam GDExtension** for Godot 4.7 (GodotSteam 4.22 or later) from the Asset Library or godotsteam.com,
   or use the prebuilt GodotSteam editor.
2. Run with Steam open. During development the app id is 480 (Spacewar), or whatever the
   `SteamAppId` environment variable says. For release, put your own app id there and in
   `steam_appid.txt` next to the executable.
3. **Multiplayer → Host a Steam lobby** creates a lobby. Public lobbies show up in the room list,
   and friends can join from the Steam overlay. Traffic goes through Steam's relay, so no ports
   need opening.

The Steam path was written against the GodotSteam 4.x API. It is untested here because the test
machine has no Steam client. The ENet path is covered by `run_tests.sh`: a host and a guest
process play a campaign round over localhost, the guest's fighter played by a bot.

### Load test

`sh tools/net_load.sh [guests] [seconds] [stage]` (default 7 guests, a full room of 8) starts a
host and that many guests as headless games over ENet on localhost, plays a campaign bout and
reports, each second, how many physics steps the host keeps up (of 120), its CPU, what it sends
(by message type) and the size of a snapshot; each guest says how often snapshots came and the
longest wait between two. All of them share the one machine's CPU, so the times are worse than in
a real game, where each player has a computer of his own; the bytes are the same.

What goes on the wire: each fighter's bodies in 14 bytes each (int16s, 2 mm), his state 8 times a
second, the dead once a second, and in a full room (4 guests or more, or more than 10 fighters) the
enemies at half the rate of the players. Measured: about 1.6 Mbit/s up from the host for 4
players and 8 fighters, about 7 Mbit/s for 8 players and 16 fighters. The host simulates every
fighter: about 1.5 ms of a physics step each on the test machine, so a full room with many
enemies asks a strong CPU of the host.

### Trying an online game on one machine

No command line: put the Godot 4.7.2 exe in the game's folder and double-click
**`multiplayer_test.bat`** (Windows); it opens the windows and asks what to try. The steps and
what to check are in `docs/MULTIPLAYER_TEST.md`. The long way:

`tools/mp_local.sh` (Linux/macOS) or `tools/mp_local.bat` (Windows, after
`set GODOT=D:\godot\Godot_v4.7.2-stable_win64.exe`) opens a host window and a guest window already
in the host's yard over ENet (online, the yard is the lobby: the host picks the next bout at the
gate). With `BOT=1`
the guests are played by bots, so you can host, play and watch a real online bout alone. `LAG=120
LOSS=3` holds every incoming message back 120 ms (±30) and drops 3% of the unreliable ones, a
pretend poor connection to see how the game feels at that latency. The same flags work on a plain
run: `godot --path . -- --host`, `--join <address>`, `--name <name>`, `--bot`, `--lag 120 --loss 3`.

## Exporting

`.github/workflows/build.yml` builds the game for Windows, Linux and macOS. Run **Godot builds**
from the repository's Actions tab, or push a tag such as `godot-v0.1`. Each build appears as a
download on the run page. The presets live in `export_presets.cfg`.

To export by hand, install the export templates for 4.7.2 (Editor → Manage Export Templates),
then run this:

```bash
godot --headless --path . --export-release "Windows Desktop" build/windows/VoxelArena.exe
```

The macOS build is not signed. On a Mac, right-click it and choose Open the first time.

For a Steam build, ship the GodotSteam extension's `addons/` folder and the `steam_api` library.
They come with the GodotSteam download. Upload the export through SteamPipe as described in
the Steamworks documentation.

Store screenshots: `xvfb-run -s "-screen 0 1920x1080x24" godot --rendering-driver vulkan
--resolution 1920x1080 --path . -- --probe steamshots` with `SHOT_DIR` set saves 1920×1080
shots of the title screen, the gladiator editor and six fights.
