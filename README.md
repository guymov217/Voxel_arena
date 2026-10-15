# WRECKSMITH

A physics gladiator brawler in **Godot 4.4** (GDScript, Jolt physics at 120 Hz). Fighters are built
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
  A gladiator editor (name, skin, cloth, hat, hair, beard, cape). The HUD, menus and options.
- **Graphics**: the arena in 10 cm voxels in the manner of Teardown (the bowl, gatehouses, the
  Emperor's box, the arcade and the props are models built by `tools/gen_voxel_art.py`), bodies,
  armour and weapons shaded by what each voxel is made of. Physics interpolation, GPU particles (blood, sparks, dust, smoke, fire, embers),
  decals for blood and scorch marks, SSAO, SSIL, SDFGI, volumetric fog and glow by quality
  level. An animated crowd shader, braziers, awnings, flags and the Emperor's box.
- **Audio**: procedural sounds in several takes with varied pitch, a stone-arena reverb bus, a
  crowd murmur that follows the excitement and ducks under the blows.
- **Multiplayer**: host-authoritative. Guests send input; the host sends snapshots, spawns, voxel
  losses and effects.

## Still to come


## The C++ voxel core (GDExtension)

The hot voxel loops run in C++ when the extension is built: greedy box merging for the
colliders (about 8× faster) and the flood fill that finds the lumps a blow knocks loose. The source
is in `extension/`. `scripts/voxel/greedy.gd` falls back to GDScript when it is absent, so a
plain checkout runs without it (and the editor does not complain about a missing library).
`tests/test_native.gd` checks that both give the same results. To build it for Linux, then load it:

```bash
cd extension
git clone -b 4.4 --depth 1 https://github.com/godotengine/godot-cpp
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

1. Install the **GodotSteam GDExtension** for Godot 4.4 from the Asset Library or godotsteam.com,
   or use the prebuilt GodotSteam editor.
2. Run with Steam open. During development the app id is 480 (Spacewar), or whatever the
   `SteamAppId` environment variable says. For release, put your own app id there and in
   `steam_appid.txt` next to the executable.
3. **Multiplayer → Host a Steam lobby** creates a lobby. Public lobbies show up in the room list,
   and friends can join from the Steam overlay. Traffic goes through Steam's relay, so no ports
   need opening.

The Steam path was written against the GodotSteam 4.x API. It is untested here because the test
machine has no Steam client. The ENet path is covered by `run_tests.sh`: a host and a guest
process play a campaign round over localhost.

## Exporting

`.github/workflows/build.yml` builds the game for Windows, Linux and macOS. Run **Godot builds**
from the repository's Actions tab, or push a tag such as `godot-v0.1`. Each build appears as a
download on the run page. The presets live in `export_presets.cfg`.

To export by hand, install the export templates for 4.4.1 (Editor → Manage Export Templates),
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
