# WRECKSMITH trailer kit

Three trailers, rendered from the game itself on your PC. All need Godot 4.7 and Python 3. ffmpeg,
Pillow and numpy are found, or fetched, by the `.bat` files themselves.

| Double-click | Out | What it is |
|---|---|---|
| `tools\make_blood_trailer.bat` | `docs\store\trailer_blood.mp4` | WRECKSMITH - THE CROWD WANTS BLOOD: the trailer that worked, its lines and order kept, made again as a film: a crane from the sky into the arena, every fight through a film camera, every kill in slow motion, cut to its own score. |
| `tools\make_trailer.bat` | `docs\store\trailer.mp4` | The launch trailer: bot fights seen from the side, the forge, the boss music. |
| `tools\make_rise_trailer.bat` | `docs\store\trailer_rise.mp4` | WRECKSMITH - RISE: one gladiator's rise, from his helmet's camera and a film camera on the kills, cut to its own score. |

Godot is looked for in the `GODOT` variable, then wherever Godot 4.7 is usually unzipped: the
project folder, the folder above it, `D:\godot`, `C:\godot`, Downloads, the Desktop, or a Godot
folder in those (the `_console.exe` first), then `godot` on the PATH; if it is nowhere, the window
asks for it (drag the exe onto it). To name it once: `setx GODOT "C:\path\to\Godot_v4.7.2-stable_win64_console.exe"`.

Every shot is filmed in the game's own look (the detailed men) at full quality, whatever this PC's
Options say (`FORCE_LOOK`, `FORCE_QUALITY`).

A run takes 20 to 60 minutes with a graphics card. Shots already made are kept in
`..\trailer_work` beside the project, so a stopped run carries on; but only for the same version of
the game: once the game's scripts, data, shaders, scenes, probes or these tools have changed, the
shots kept from before are thrown away and filmed again (`stamp.txt` in the work folder). To make
one shot again, delete it there (`..\trailer_work\gorilla.mp4` for the launch trailer,
`..\trailer_work\rise\lion.avi` for the rise trailer, `..\trailer_work\blood\dragon.avi` for the crowd
trailer); to start over, delete the folder.

## The crowd trailer (WRECKSMITH - THE CROWD WANTS BLOOD), shot by shot

The cut of the trailer that worked, its cards and their order kept, every shot of it made again
from the game as a film. About 75 seconds, 1920x1080 at 30 frames a second (`set TRAILER_FPS=60`
for 60), cut to its own score at 90 beats a minute: every cut on a beat, every kill on a beat.

| Beats | Shot | Over it |
|---|---|---|
| 4 | Black, a heartbeat, the crowd far off | THE CROWD WANTS BLOOD |
| 9 | A crane from the sky, high over the full stands and the awnings, coming down over the sand to the champion in gilded armour walking in from the gate, and leading him | ENTER THE ARENA |
| 3 | The crowd on its feet under the Emperor's box, low on the sand | |
| 9 | The fight: blade on blade, a gladius and a dagger against a spatha, both good; a short dip into slow motion on every clean blow of his, the kill in slow motion | |
| 9 | The big lion, its kill in slow motion | NOT EVERY FOE IS A MAN |
| 5 | The dragon pours its fire across the sand at a man running from it | |
| 6 | The forge: the executioner's axe going up on the anvil voxel by voxel, the anvil filling the screen | FORGE YOUR WEAPON / VOXEL BY VOXEL |
| 6 | Cut to the same axe in the champion's hands: a swordsman comes on with his blade up, the axe comes down on him edge first, in the slowest motion (0.12) | |
| 5 | A man charges; a wheel of cheese bowled along the sand takes him off his feet | ...AND CHEESE |
| 6 | A free-for-all of seven, from above the thick of it, the camera going round | CHOOSE YOUR CHAOS |
| 7 | Four friends, their names over their heads, charging the minotaur in a line, low behind them; the clash in slow motion | BRING YOUR FRIENDS / ONLINE MULTIPLAYER |
| 5 | A man charging the champion's spear takes it in the face: his head stops, his legs run on and he goes over backwards, heels over head, in slow motion | |
| 8 | Montage: eight cuts, one a beat, the hardest blows of all the bouts, those that take a limb off first, each with a dip into slow motion as it lands | EVERY BLOW LANDS / EVERY BONE BREAKS |
| 8 | The hydra (or the troll, when no seed gives a hydra that falls): its kill in the slowest motion of all (0.15), cut to black on the blow | |
| 2 | A breath of silence | |
| 12 | The title on one great hit, over the champion alone in the middle, his axe raised to the crowd | the logo, COMING SOON TO STEAM, WISHLIST NOW |

**Every blow on screen is a real one.** A bout is filmed only if its foe falls to a hard blow of
the champion's that the camera can see, not bleeding out after it; the fight scene only after a
real exchange (four blows either way in the five seconds before the kill). Each bout is played
undrawn seed after seed until one does (then drawn). The duel, the cyclops and the troll are
filmed for the montage's blows.

**The cameras.** No helmet here: every bout is seen through a film camera low on the sand, wide
while they fight (far off, a little high, drifting slowly round them, jolting with the hardest
blows), then cut in close on the same side of them for the kill (a long lens, the background
melting away in its depth of field), and wide again after. The staged shots (`tests\stageshots.gd`)
each have their own move: the crane, a dolly along the wall, a push in behind the champion, a
camera going round the melee, one low on the sand following the cheese, one beside the cut, one
square to the spear's charge, one low behind the friends' charge. The forge is the anvil alone
(`tests\forgeclip.gd` with FORGE_CINE=1). The cards are the trailer's own: gold Roman capitals
spaced wide, a thin gold rule each side, a smaller line under; the end card has the store's logo
(`docs\store\capsules\logo.png`).

**The picture and the sound** are the rise trailer's (the same editor, grade and score maker, see
below): motion blur from the 120 frames a second, smooth slow motion with a white flash on each
kill, the warm hard grade with grain and cinema bars, the fight's own sound under a score made to
the cut, brought to -14 LUFS.

**What comes out.** `docs\store\trailer_blood.mp4`: H.264 High (CRF 16), AAC 320 kb/s, 48 kHz,
fast start, ready to upload. Beside it `trailer_blood_cut.json`, the cut list.

**A check without the game**: `python tools\make_blood_trailer.py --fake` cuts the whole trailer
from made-up footage (test patterns), to see the cards, the timing and the sound. A staged shot's
framing can be looked at without the movie maker: `set STAGE=reveal`, `set STAGE_PEEK=4`,
`set SHOT_DIR=C:\some\folder`, then run the game with `-- --probe stageshots`: four frames of it
are saved there (for the cut and the spear, four round the moment itself).

## The rise trailer (WRECKSMITH - RISE), shot by shot

About 80 seconds, 1920x1080 at 30 frames a second (`set TRAILER_FPS=60` for 60), cut to its own
score at 90 beats a minute: every cut falls on a beat and every kill on a beat.

| Time | Shot | Over it |
|---|---|---|
| 0:00 | Cold open: the troll's kill, a flash-forward in deep slow motion (a fifth of the speed), the film camera's long lens | a sub boom and a braam on the blow |
| 0:03 | Black | EVERY CHAMPION OF ROME / BEGAN AS A SLAVE, over a heartbeat |
| 0:07 | Bout I: a slave with a stick against a drunk | BOUT I - A SLAVE WITH A STICK |
| 0:15 | Bout IV: gladius and shield against two recruits | BOUT IV - FIRST BLOOD |
| 0:23 | The forge: an axe going up on the anvil voxel by voxel | FORGE YOUR OWN STEEL |
| 0:27 | The big lion, the cyclops, the minotaur | their cards |
| 0:51 | Montage: eight cuts, one a beat, the hardest blows of all the bouts | EVERY BLOW LANDS / EVERY BONE BREAKS |
| 0:56 | The troll | BOUT XL - CHAMPION OF ROME |
| 1:04 | The hydra: its kill in the slowest motion of all (0.15), cut to black on the blow | BOUT LXIV - THE HYDRA |
| 1:10 | A breath of silence | |
| 1:11 | The title on one great hit | WRECKSMITH, EARN YOUR FREEDOM, WISHLIST NOW ON STEAM |

**The cameras.** Every bout is seen through the camera on his helmet, strapped to its right side
like a GoPro: it turns with his head, a wide lens that takes in the blade in his fist and the man
in front of him, and it jolts at every hard blow. For the kill of the big ones (the lion, the
cyclops, the minotaur, the troll, the hydra) it cuts to a film camera low on the sand: a long
lens (34-46 degrees) that stacks him and the beast together, drifting slowly round them, the
background melting away in its depth of field. After the kill, the helmet again, looking down at
what fell.

**The picture.** The game is recorded at 120 frames a second, a frame for every physics step, and
drawn at its best (MSAA 4x, the voxels' corner shading, the 3D supersampled 1.5x). The editor
(`tools/trailer_edit.py`) uses the extra frames: at full speed each film frame is the blend of the
game frames a 180-degree shutter would see (a film camera's motion blur on every swung blade);
into each kill the speed eases down to slow motion and back up, and the slow motion is smooth (no
frame shown twice). A white flash on each blow that kills. The grade: warm highlights, cool
shadows, a little more contrast, darkened corners, a film's grain, a touch of colour fringing,
cinema bars (2.39:1). The cards fade in and drift up a little; the end card comes in in three
steps.

**The sound.** The fight's own sound (the blows, his war cries, the cries of men and beasts, the
crowd; the game's music is off) runs under the score, slowed with the picture in the slow motion
(its pitch falling, as on film) and muffled there. The score (`tools/rise_score.py`) is made for
the cut from the cue sheet: a heartbeat and a drone in the dark, the drums coming in bar by bar
(taiko, toms, frame drums), low strings at eighths then sixteenths on D minor, a choir of men and
a horn at each act, a sub boom and a braam on every kill, a reversed cymbal into it, whooshes
under the cuts, risers into the montage and the finale, a silence of a breath, and one great hit
on the title that rings out under the end card. The score gives way to the fight's loudest moments
(side-chained). The whole mix is brought to -14 LUFS with peaks under -1 dBTP, what Steam and
YouTube play at. Everything is the game's own: free to use anywhere.

**What comes out.** `docs\store\trailer_rise.mp4`: H.264 High (CRF 16), AAC 320 kb/s, 48 kHz,
fast start, ready to upload to Steam as is. Beside it `trailer_rise_cut.json`, the cut list.

**How long.** Each bout is played twice (once to find the kill, once filmed): with a graphics card
the shots take 20-40 minutes and the edit 5-15. A run that is stopped carries on where it was.

**If a bout will not end with the foe down**, the kit tries other seeds by itself; a bout that
never does is left out and the cut is made from the rest. Should a filmed bout go another way
than its first run did, it is filmed again round the kill it made (it says so as it goes). To
film a bout again, delete its `.avi` in `..\trailer_work\rise`; to film all again, delete the
folder.

**Settings** (set before running, e.g. `set TRAILER_SSAA=2`): `TRAILER_FPS` 30 or 60;
`TRAILER_SSAA` the supersampling (1.5; 2 for the sharpest picture, slower); `TRAILER_AA` the MSAA
(msaa4; msaa8).

**A check without the game**: `python tools\make_rise_trailer.py --fake` cuts the whole trailer
from made-up footage (test patterns), to see the cards, the timing and the sound.

## Files

- `tools\make_blood_trailer.bat`, `tools\make_trailer.bat`, `tools\make_rise_trailer.bat`:
  double-click these.
- `tools\make_blood_trailer.py`, `tools\make_trailer.py`, `tools\make_rise_trailer.py`: the
  three trailers.
- `tools\trailer_edit.py`: the crowd and rise trailers' editor (motion blur, speed ramps, the
  sound with the picture).
- `tools\rise_score.py`: the crowd and rise trailers' score, made to the cue sheet;
  `tools\war_drums.py`: its drums and voices.
- `tools\trailer_cards.py`, `tools\make_capsules.py`, `tools\fonts\Cinzel-Black.ttf`: the cards.
- `tests\clipshots.gd`, `tests\forgeclip.gd`, `tests\musicbed.gd`: the launch trailer's shots
  (the forge clip is in the other two too).
- `tests\shouldershots.gd`: the bouts of the rise trailer (its two cameras) and of the crowd
  trailer (CLIP_CAM=film).
- `tests\stageshots.gd`: the crowd trailer's staged shots (the crane, the crowd, the dragon, the
  cheese, the chaos, the friends, the finale).
