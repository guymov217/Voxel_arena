# WRECKSMITH trailer kit

Two trailers, rendered from the game itself on your PC. Both need Godot 4.7 and Python 3. ffmpeg,
Pillow and numpy are found, or fetched, by the `.bat` files themselves.

| Double-click | Out | What it is |
|---|---|---|
| `tools\make_trailer.bat` | `docs\store\trailer.mp4` | The launch trailer: bot fights seen from the side, the forge, the boss music. |
| `tools\make_rise_trailer.bat` | `docs\store\trailer_rise.mp4` | One gladiator's rise, all from a camera on his helmet, under war drums. |

Godot is looked for in `D:\godot\Godot_v4.7.2-stable_win64.exe` (or its `_console.exe`). For
another place, set it once: `setx GODOT "C:\path\to\Godot_v4.7.2-stable_win64.exe"`.

A run takes 20 to 60 minutes with a graphics card. Shots already made are kept in
`..\trailer_work` beside the project, so a stopped run carries on. To make a shot again, delete
its `.mp4` there (`..\trailer_work\rise\lion.mp4`, say); to start over, delete the folder.

## The rise trailer, shot by shot

The camera is strapped to the right side of his helmet, like a GoPro: it moves and turns with
his head, with a wide lens that takes in the blade in his fist and the man in front of him, and it
jolts at every hard blow he gives or takes. Each bout runs from five seconds before the kill to two
after it, and comes up out of black and goes back into it. The killing blow plays at half speed,
its sound slowed and deepened with it. The fight's own sound runs loud under the drums: the blows,
his war cries, the cries of men and beasts, the crowd. The drums give way under every blow and cry
and swell back, so each one lands. The picture has a film look: a warm, hard grade, darkened
corners and cinema bars (2.39:1), with the titles over the bars. The game's music is off in the
shots.

| Shot | He carries | He faces | The card |
|---|---|---|---|
| slave | the training stick | a drunk | BOUT I · A SLAVE WITH A STICK |
| recruit | gladius, round shield | two recruits | BOUT IV · FIRST BLOOD |
| lion | gladius, scutum, arm guard | the lion | BOUT VIII · THE BIG LION |
| cyclops | spear, scutum, helmet | the cyclops | BOUT XVI · THE CYCLOPS |
| minotaur | axe, round shield, greaves | the minotaur | BOUT XXIV · THE MINOTAUR |
| troll | warhammer, full armour | a troll | BOUT XL · CHAMPION OF ROME |
| hydra | zweihander, full armour | the hydra | BOUT LXIV · THE HYDRA |
| end | | | WRECKSMITH · EARN YOUR FREEDOM · Wishlist on Steam |

He fights on autopilot, hard to bring down, so every bout is his. If a fight does not end with
the foe down, the kit tries other seeds by itself. A bout that never ends that way is left out,
and the trailer is cut from the rest.

The war drums are made by `tools\war_drums.py` for the trailer's exact length. They have big low
drums, toms and a frame drum, a horn over a low drone, and a men's choir on D minor. They build
bar by bar to one great hit on the end card. They are the game's own, free to use anywhere.

## Files

- `tools\make_trailer.bat`, `tools\make_rise_trailer.bat`: double-click these.
- `tools\make_trailer.py`, `tools\make_rise_trailer.py`: the two trailers.
- `tools\trailer_cards.py`, `tools\make_capsules.py`, `tools\fonts\Cinzel-Black.ttf`: the cards.
- `tools\war_drums.py`: the rise trailer's music.
- `tests\clipshots.gd`, `tests\forgeclip.gd`, `tests\musicbed.gd`: the launch trailer's shots.
- `tests\shouldershots.gd`: the rise trailer's shots and its camera.
