# Voxel Arena

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
- **The smith**: buy bases, mend, hone and temper. A voxel forge reshapes a weapon voxel by voxel.
- **Modes**: training and 14 fight and party modes (duel, best of three, free for all, chaos, co-op,
  gauntlet, monster hunt, teams, king of the arena, the Emperor, king of the hill, last limb,
  head football, players' brawl).
- **The spectacle**: the Emperor's decrees, arena hazards, the crowd's favour and the announcer,
  and drops from the stands.
- **Interface**: a title screen with a live fight behind it and a champion who wears your look.
  A gladiator editor (name, skin, cloth, hat, hair, beard, cape). The HUD, menus and options.
- **Graphics**: physics interpolation, GPU particles (blood, sparks, dust, smoke, fire, embers),
  decals for blood and scorch marks, SSAO, SSIL, SDFGI, volumetric fog and glow by quality
  level. An animated crowd shader, braziers, awnings, flags and the Emperor's box.
- **Audio**: procedural sounds in several takes with varied pitch, a stone-arena reverb bus, a
  crowd murmur that follows the excitement and ducks under the blows.
- **Multiplayer**: host-authoritative. Guests send input; the host sends snapshots, spawns, voxel
  losses and effects.

## Still to come

- The 7-day "Bread & Circuses" campaign, with its special bouts, blessings, fortunes, ludus
  upgrades and the Hall of Fame. Its data is already in `data/modes.json`.
- The lobby hub and its minigames.
- The kill cam, music, the tutorial, key rebinding and gamepad support.

## The C++ voxel core (GDExtension)

The hot voxel loops run in C++ when the extension is built: greedy box merging for the
colliders (about 8× faster) and the flood fill that finds the lumps a blow knocks loose. The source
is in `extension/`. `native/voxel_core.gdextension` loads the library, and
`scripts/voxel/greedy.gd` falls back to GDScript when it is absent. `tests/test_native.gd` checks
that both give the same results. To build it for Linux:

```bash
cd extension
git clone -b 4.4 --depth 1 https://github.com/godotengine/godot-cpp
pip install scons
scons platform=linux target=template_release      # or windows use_mingw=yes, or macos
```

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
