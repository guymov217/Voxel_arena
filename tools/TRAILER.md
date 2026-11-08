# WRECKSMITH trailer kit (75 seconds)

One trailer, made from the game itself, shot by shot to its production script: 31 shots at the
script's own times (its 18 and 19, the armourer's bench, left out: their seconds go to 17 and 20),
its lines of text, the logo and WISHLIST NOW ON STEAM.

| Double-click | Out |
|---|---|
| `tools\make_trailer75.bat` | `docs\store\trailer75.mp4` (1920x1080, 30 fps, H.264 High, AAC 320 kb/s, -14 LUFS, fast start: ready for Steam), `docs\store\trailer75_clean.mp4` (the same without its text), `docs\store\trailer75_cut.json` (the cut list: every shot, its recording, where it is cut) |

It needs Godot 4.7 and Python 3; ffmpeg, Pillow and numpy are found, or fetched, by the `.bat`
itself. Godot is looked for in the `GODOT` variable, then wherever Godot 4.7 is usually unzipped
(the project folder, the folder above it, `D:\godot`, `C:\godot`, Downloads, the Desktop), then
`godot` on the PATH; if it is nowhere, the window asks for it.

A run takes 30 to 60 minutes with a graphics card. Each shot is recorded once into
`..\trailer_work\t75` beside the project and kept; once the game's scripts, data, shaders or
scenes change, the shots kept from before are thrown away and filmed again. To film one again:
`tools\make_trailer75.bat --shots 13` (or delete its `.avi` there).

Elsewhere: `python tools/make_trailer75.py` (a display is needed: `xvfb-run` on a Linux box
without one); `--preview` makes a rough cut at 640x360 from 30 fps recordings (for a computer
without a graphics card, which renders in software, slowly); `--fake` cuts the whole trailer
from made-up footage in a minute or two, to check the timing, the text and the sound.
`TRAILER_FPS=60` makes it at 60 frames a second.

Filmed in a copy of the project (`..\trailer_work\project`) with a user folder of its own: the
player's saves are never touched. Every shot is in the game's own look at its best quality,
whatever this PC's Options say.

## How every shot is made

Every shot is a scene staged in the game (`tests/trailer75.gd`, `SHOT=<n>`) and recorded by
Godot's movie maker at 120 frames a second. The scene puts the men where they stand and drives
each of them the way a player drives his gladiator: his look, his hand's mark (the mouse), the
button for a blow, a thrust, a kick (`kick`), a grab (`grab`), a throw (`throw`), his steps. The
game does the rest exactly as in a bout:

- a blow lands where the blade really meets the man, and its harm is the game's own;
- every fall, stagger, wound, lodged blade and limb off is the game's own physics and damage;
- nothing is added: no push, no blow made where none landed, nothing passing through anything;
- no man is stronger or harder than the game makes him: the champion is a gladiator the trainer
  has taught all he teaches (Training's limits), his foes are the campaign's men as they come;
- the beasts and the giants are the game's own; the big lion fights by its own mind.

A take that does not go as the plan has it is filmed again from another start (`SHOT_SEED`), as a
crew films another take. The scenes go the same way every time they are run (the contacts in a
fixed order, one worker thread, the same dice), so where several shots are one scene seen by
different cameras, the cut from one camera to the next is the same moment.

The editor (`tools/trailer_edit.py`) cuts each shot on its moment, read from the tags the scene
prints (`KEY` the blow it is cut on, `MARK` lodged, free, severed, down, killcam): at full speed
each film frame is the blend of the game frames a film camera's shutter would see; into a slow
motion the speed eases down and back up. The grade is light (a little contrast and colour, the
corners darkened). The text is set in Inter Display Black (`tools/fonts`, SIL Open Font License),
white with a dark edge, low on the left, away from the action, sliding and fading in and out.

## The shots

| # | Time | Shot | In the game |
|---|---|---|---|
| 1 | 0:00 | ECU, low, side on, still; cut on the blow | the champion's executioner's axe comes down on a swordsman's forearm |
| 2 | 0:01.5 | CU three-quarters, low; a short slow motion | the cut arm; the axe goes on into his thigh and sticks there |
| 3 | 0:03 | WS a little high, going with them | the axe wrenched free, the champion presses on, the man gives ground |
| 4 | 0:05 | WS high over the arena, pushing in | the champion and a shieldbearer trading blows in the middle of the arena |
| 5 | 0:07 | FS low, going along with him | the champion walks up on the shieldbearer, who turns to face him |
| 6 | 0:10 | Medium-wide, side on, going with them | sword on shield, his thrust back, the champion's blows |
| 7 | 0:13 | MS low before the champion; a ramp on the blow | the warhammer down on a praetorian's helmet: he drops |
| 8 | 0:15 | CU side on | the mace into a man's shin |
| 9 | 0:17 | CU a little high, side on; slow at the cut | the second chop into the same wound takes a swordsman's arm off at the shoulder |
| 10 | 0:19 | FS side on, going with him | the warhammer swung low into a shieldbearer's legs: he goes down |
| 11 | 0:21 | MS three-quarters, a little high | the champion takes hold of a berserker (G) and throws him (F) |
| 12 | 0:23 | Medium-close, side on | the kick |
| 13 | 0:25 | CU three-quarters from behind the man | the axe stuck in him, wrenched out, the man dragged with it |
| 14 | 0:27 | Medium-wide, pushing in | the forge's screen: the anvil, the smithy, the editor round it |
| 15 | 0:29 | CU a little high; three quick cuts | the axe built block by block: each block's material and job picked, the mouse on its cell (its ghost), a click |
| 16 | 0:32 | CU side on | the axe done, the forge's camera turned round it |
| 17 | 0:34 | Close on its head, then medium-low three-quarters | the same axe (the forge's own build of the same blocks) in the champion's hand, into a man; its ruby sets him alight |
| 20 | 0:39 | FS low three-quarters | a brute's warhammer on the champion, twice: his armour's plates knocked off |
| 21 | 0:45 | EWS very low, rising | the cyclops comes across the sand at the champion |
| 22 | 0:49 | FS low, side on | the cyclops's hammer on the champion: his helmet's plates fly |
| 23 | 0:52 | Medium-wide from behind the champion | up again, at the giant's legs: his axe into the knee (a take of its own) |
| 24 | 0:55 | Low three-quarters, two quick cuts | the big lion (the campaign's lion boss) charges and bowls the champion over; the minotaur's axe on him |
| 25 | 0:58 | WS a little high | the champion crossing the Ludus yard |
| 26 | 1:00 | MS over his shoulder | the smith turns to him; his stall opened (G) |
| 27 | 1:02 | MS three-quarters | his left hand lost, the physician fits him a hook; he stands with it |
| 28 | 1:04 | FS a little low | training: the sparring partner set to stand still (the Training screen's dummy) |
| 29 | 1:06 | WS low three-quarters | a melee, three against three, the champion in it |
| 30 | 1:08 | CU side on; a ramp into slow motion | the executioner's axe down into a man's head: he drops, out of the fight |
| 31 | 1:10 | the game's own kill cam | the kill cam's replay of it, as the game shows one (its camera, its bars, its caption) |
| 32 | 1:12 | A little high, three-quarters | the champion over the man on the sand |
| 33 | 1:13 | Black | the logo, BUILD YOUR WEAPON. ENTER THE ARENA. SURVIVE THE FIGHT., then WISHLIST NOW ON STEAM |

The lines: 0:05-0:08 PHYSICS-DRIVEN COMBAT; 0:13-0:17 EVERY HIT MATTERS; 0:17-0:23 BRUTAL.
PHYSICAL. UNPREDICTABLE.; 0:27-0:34 BUILD YOUR OWN WEAPONS; 0:38-0:45 CUSTOMIZE YOUR GLADIATOR;
0:45-0:58 FACE THE UNTHINKABLE; 0:58-1:06 FIGHT. HEAL. PREPARE.; 1:13-1:15 WISHLIST NOW ON STEAM.

## The sound

The game's own sound of every shot (the blows, the cries, the crowd), slowed with the picture in
the slow motions, runs under the game's own music (`art/audio/music`), laid along the script's
curve: the boss piece for the opening, the fight pieces for the combat, the forge's for the
making and the fitting out, the boss pieces for the giants and the finale, the yard's for the
yard, the victory's opening for the logo. Of each piece the stretch that fits is taken (the
strongest, or the quietest), cross-faded into the next; the music drops away under the kill cam
and comes back hard; a deep hit under the opening blow, the drop and the logo. The music gives way
to the loudest of the fight. The whole is brought to -14 LUFS, peaks under -1.5 dBTP.

## Files

- `tools\make_trailer75.bat`: double-click this.
- `tools\make_trailer75.py`: records the shots and cuts the trailer (the script's timeline is its
  `SHOTS`, `CUTS` and `TEXT`).
- `tools\trailer_edit.py`: the editor (motion blur, speed ramps, the sound with the picture).
- `tests\trailer75.gd`: the shots, staged in the game.
- `tools\fonts\InterDisplay-Black.otf` and `InterDisplay-OFL.txt`: the trailer's type and its licence.
