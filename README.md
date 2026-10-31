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
  Blunt and keen are different harm: a crushing weapon (a mace, a hammer: its head all blunt
  but a few studs) bruises and pulps rather than taking flesh away, and breaks bones sooner and
  worse the harder its head; blades cut. A nail pot's nails each punch a hole of their own where
  they go in, bleed and stay in; the ones that miss bounce and lie on the sand.
- **Broken bones**: a blow cracks a bone or breaks it, as hard as it was: cracked, the limb works
  at a little over half and a lesser blow breaks it through; broken under the skin (closed) or
  out through it (open, the bone showing), the limb is no use: not driven, held on by its muscle
  only, it flops from the joint and is drawn bent at the break, and still never passes through
  the body. The skull cracks, is driven in or breaks open; broken ribs cut the breath and, broken
  in, hurt the lung. In the campaign the bones stay broken from fight to fight until the
  physician sets them (no elixir needed: a bone knits, a hand does not grow back). A break is
  seen: a broken limb is drawn bent, an open break has the splinter standing out of the skin,
  the HUD figure marks the bone, the feed names it and it is heard over the blow.
- **Weapons**: built from the same voxel designs, with greedy-merged colliders and shields.
  Chain weapons, bows and crossbows, throwables and the market. A weapon is only ever taken up by
  hand (G): the hand reaches for the grip (he stoops for one on the sand, steps to one a pace
  off), and at the grip the fist closes on it and brings it into line along one smooth curve,
  carried by the hand the whole way, then it is held. The "Pick up" prompt shows exactly when G
  would take something. J changes hands, H puts both on the haft; neither ever drops a weapon.
  Whatever lies still on the sand (a weapon, a severed limb, chips) is walked over, not tripped on.
- **Glancing and lodged blows**: a weapon that meets a plate at a slant, or a blade that lands
  flat, skids off with sparks and a scrape and does little; a square cut chops in, bone crunches.
  A heavy keen blade driven hard can stay in the wound, still in the hand: it is wrenched out
  by pulling (the man it is in comes with it) or let go of (G), and taken back the same way.
  None holds a man for good: the man it is in tears it out with G, pulling away frees it
  sooner, and after three seconds it works loose by itself. A giant's blade never stays in.
- **Armour that wears**: every plate you put on protects the spot it covers until it is knocked
  off, at a force by its stuff (leather gives first, steel last); what came off stays off between
  fights until the smith mends it (Mend, in the armour tab), and plates are painted on the bench.
- **The trainer** (Doctore, in the yard): six abilities bought a session at a time, never earned
  in the arena: vis (strength, half of it behind every blow), ictus (the blow), spiritus (breath), corium (a thick hide),
  sanguis (slower bleeding) and firmitas (footing). Each costs more than the last and is capped
  by the bout you have reached (`scripts/game/training.gd`).
- **The Hand of Jupiter**: a telekinesis charge from the market seizes the foe under the
  crosshair, up to 12 m off (a man or a beast; not a giant, not the great monsters of myth), for three seconds (twice a
  bout), the wheel draws him nearer or further, and F lets him fly with the mouse's sweep; a
  hard landing hurts. A fireball pot bursts, burns and leaves
  fire on the sand.
- **Wrestling**: grabs, shoves, trips, and the giant's lift and throw. A giant's blows vary:
  a chop from above, sweeps from either side, a low sweep at the legs and a thrust.
- **Bots** and all 24 **beast** species with their behaviours, including flying and breath. A
  beast's jaws, claws and horns bite only in a strike (the snap after the wind-up), never by
  brushing against a man, so a lunge can be dodged or taken on the shield; a bite goes in
  like teeth, not a blade, and takes no more than 30 off a limb. Beasts and monsters chunk
  more under blows than men do (the giants of myth keep their own hide). The gorilla loses its
  nerve with every blow it takes (slower to come on, fewer blows and grabs, a solid one breaks
  off its wind-up), and gathers it back when let be. The manticore stings a man at its flank and
  flings poisoned spikes from its tail at one out of its reach, after raising the tail with a roar.
  The enemy's health plate reaches nothing when the fight with him is over, whatever ends it:
  head, trunk, blood, a broken neck, the brain or a torn heart, or down and spent.
- **Wounds change how they fight**: a hurt man grows wary (a longer distance, slower to begin
  a blow, fewer strung together) and, near the end of his blood, throws a desperate lunging
  blow now and then with all his weight in it; a boss has half the wariness. Of the beasts,
  the hunters, the crawlers and the gorilla grow careful when hurt, while the furies (the boar,
  bull, rhino, bear, mammoth, elephant, dragon, cerberus, manticore, griffin, chimera and
  basilisk: `Beast.FURIES`) come on harder the worse they are hurt, sooner and closer, but
  wilder, their charges, lunges and strikes thrown wide of the man. The hydra and the hound
  press after a lunge instead of backing off (their heads strike on their own), and a dragon
  with a man under its chin backs off a stride to pour fire on him.
- **The campaign**: a ladder of 64 bouts, authored one by one in `scripts/game/ladder.gd`
  (who comes through the gate, who comes through the *other* gate nine seconds in or as soon
  as the first is down: the board by the gate names the first wave alone), the men with the
  stage tables' gear, weapons and skill (`data/campaign.json`), a boss on every fourth bout,
  and no kind of foe twice running. The order came from a bot-versus-bot survey of every foe
  against a plain swordsman (what beat him, how fast, at what cost): the gentlest giant (the
  Cyclops) is the first boss, the Dragon the last, the crocodile, the hoplite's phalanx and the
  brutes wait for the thirties, and the bosses come round again in steel from bout 40
  (`tests/test_campaign.gd` checks the climb, the variety and the gates). Pay, checkpoints and
  persistent weapon wear as before.
- **Ironman or Legionary** (`scripts/game/campaign_run.gd`): chosen when a campaign begins (in
  co-op the host chooses in the room). A legionary who falls goes back to the last checkpoint
  (every four bouts) with the purse, arms, armour, body and training he had there; an ironman
  starts over at bout 1. The rudis won on Ironman gives the Unbroken laurel (a hat) and Virtus
  at the trainer (a little of every ability, never lost), both for good.
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
  dummies that never fall, three throwing boards that score a throw, and by the gate a board
  that names the next fight (the party's, in a room). Three missions per fight pay denarii and reputation, and reputation
  earns ranks (Tiro up to Rudiarius). After a fight you come back to the yard.
- **The smith**: buy bases, mend, hone and temper. A voxel forge reshapes a weapon voxel by voxel.
  In the forge, "Held in" one hand or two, and a button per hand puts it on the block you click
  (the rings are marked MAIN and OTHER). Two fists need 3 blocks (12 cm) between them, so a
  short grip (gladius, dagger, hammer) stays one-handed; a long one taken in two hands with H
  puts the other hand at the far end of the grip, so the hands never crush together mid-swing.
- **Armour at the forge**: the forge's Armour tab opens the armour bench, a body part in the
  round with plates put on it voxel by voxel (where it goes and its stuff picked on the bench).
  Up to 2400 plates, and they may stand up to 6 blocks out from the body (crests, wide
  pauldrons): each one weighs. The bench marks the FRONT and the BACK.
  The main menu's forge keeps it in My designs for free; training's forge makes it free and worn
  (training also puts on any piece, bought or designed); the smith's forge makes it for denarii.
- **Modes**: training and 14 fight and party modes (duel, best of three, free for all, chaos, co-op,
  gauntlet, monster hunt, teams, king of the arena, the Emperor, king of the hill, last limb,
  head football, players' brawl).
- **The spectacle**: the Emperor's decrees, arena hazards, the crowd's favour and the announcer,
  and drops from the stands. A lively bout earns a small crowd bonus on the pay, in proportion
  to how much fighting the crowd saw.
- **Limbs that stay on**: the parts of a body are rigid bodies on joints, and a joint opens a
  few millimetres under load; on screen each part is drawn against the part it hangs from and
  the weapon with its hand, so nothing floats off the body until it is really cut off
  (`Fighter._seat_drawing`).
- **Achievements** (`scripts/game/achievements.gd`): fifteen, kept in the save and set on Steam
  when it runs (the list is in docs/DEMO.md).
- **Interface**: a title screen with a live fight behind it and a champion who wears your look.
  A gladiator editor (name, skin, cloth, hat, hair, beard, cape). The HUD, menus and options
  (four tabs: game, controls, graphics, sound; VSync, an FPS cap and the interface scale among
  them). The menus in one imperial look (`scripts/ui/style.gd`):
  Cinzel capitals and Alegreya Sans (both OFL, `art/fonts`) on stone plates framed in gold; the
  fights as cards with a line each on what they are.
- **Graphics**: the arena in 10 cm voxels (the floor smooth sand and packed earth with a fine
  voxel grain, raked rings, the trampled middle, damp sand by the wall, pebbles and dry grass) in the manner of Teardown (the bowl, gatehouses, the
  Emperor's box, the arcade and the props are models built by `tools/gen_voxel_art.py`), bodies,
  armour and weapons shaded by what each voxel is made of. Physics interpolation, GPU particles (blood, sparks, dust, smoke, fire, embers),
  decals for blood and scorch marks, SSAO, SSIL, SDFGI, volumetric fog and glow by quality
  level. Anti-aliasing to choose (MSAA 4x by default: the blocks' edges smooth, the rest sharp;
  or SMAA, FXAA, MSAA 2x/8x, off) and voxel corner shading (each voxel's face darkens toward the
  neighbours that shut it in, so creases and the gaps between blocks lie in shadow; on or off). A
  weapon's sharp voxels are drawn tapered, in the forge and in the fight: the outer row of an edge a
  wedge thin across the blade with a honed line, a point a tip, and a run of points (one stab
  block on another) one spike narrowing unbroken from its base to its tip (only the look; they hit
  as cubes). Every joint of a fighter is drawn whole: each limb is drawn moved to close the few
  millimetres the physics leaves open at its joint, and a block of the limb's own colour sits on
  each pivot (the deltoid at the shoulder, the elbow, hip, knee and neck) to fill the wedge two
  blocks open between them when the joint bends. An animated crowd shader, braziers, awnings, flags and the Emperor's box.
- **Audio**: procedural sounds in several takes with varied pitch, a stone-arena reverb bus, a
  crowd murmur that follows the excitement and ducks under the blows. A blow is the body's knock
  and a few hundredths of a second of shaped noise (the thwack, the slap, the wet bite); a pot of
  powder has its own boom, and the blast's blows on every part in reach are heard as that boom.
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
godot --headless --path . --export-release "Windows Desktop" build/windows/WRECKSMITH.exe
```

The macOS build is not signed. On a Mac, right-click it and choose Open the first time.

For a Steam build, ship the GodotSteam extension's `addons/` folder and the `steam_api` library.
They come with the GodotSteam download. Upload the export through SteamPipe as described in
the Steamworks documentation.

Store screenshots: `xvfb-run -s "-screen 0 1920x1080x24" godot --rendering-driver vulkan
--resolution 1920x1080 --path . -- --probe steamshots` with `SHOT_DIR` set saves 1920×1080
shots of the title screen, the gladiator editor and six fights.
