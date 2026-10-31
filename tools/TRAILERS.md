# WRECKSMITH trailer kit

Two trailers, rendered from the game itself on your PC. Both need Godot 4.7 and Python 3. ffmpeg,
Pillow and numpy are found, or fetched, by the `.bat` files themselves.

| Double-click | Out | What it is |
|---|---|---|
| `tools\make_trailer.bat` | `docs\store\trailer.mp4` | The launch trailer: bot fights seen from the side, the forge, the boss music. |
| `tools\make_rise_trailer.bat` | `docs\store\trailer_rise.mp4` | WRECKSMITH - RISE: one gladiator's rise, from his helmet's camera and a film camera on the kills, cut to its own score. The Steam trailer. |

Godot is looked for in `D:\godot\Godot_v4.7.2-stable_win64.exe` (or its `_console.exe`). For
another place, set it once: `setx GODOT "C:\path\to\Godot_v4.7.2-stable_win64.exe"`.

A run takes 20 to 60 minutes with a graphics card. Shots already made are kept in
`..\trailer_work` beside the project, so a stopped run carries on. To make a shot again, delete
it there (`..\trailer_work\gorilla.mp4` for the launch trailer, `..\trailer_work\rise\lion.avi` for
the rise trailer); to start over, delete the folder.

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

- `tools\make_trailer.bat`, `tools\make_rise_trailer.bat`: double-click these.
- `tools\make_trailer.py`, `tools\make_rise_trailer.py`: the two trailers.
- `tools\trailer_edit.py`: the rise trailer's editor (motion blur, speed ramps, the sound with
  the picture).
- `tools\rise_score.py`: the rise trailer's score, made to its cue sheet; `tools\war_drums.py`:
  its drums and voices.
- `tools\trailer_cards.py`, `tools\make_capsules.py`, `tools\fonts\Cinzel-Black.ttf`: the cards.
- `tests\clipshots.gd`, `tests\forgeclip.gd`, `tests\musicbed.gd`: the launch trailer's shots
  (the forge clip is in the rise trailer too).
- `tests\shouldershots.gd`: the rise trailer's bouts and its two cameras.
