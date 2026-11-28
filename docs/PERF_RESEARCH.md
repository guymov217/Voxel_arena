# Performance research (#298k, #298l, #310, #312): where a fight's time goes and what each way of sparing it is worth

Rule kept throughout: the game as played must not change. A way that changes a fight (not to the bit, and not only in how it is drawn) is listed as such and not recommended
without the owner's word. Every figure is from this repository's own probes on one core of the build machine (a Xeon that runs at about 2.85 GHz, no graphics card), release
scripts, one physics thread, unless it says otherwise; "k" below is how many times as fast a computer's core is (0.8 a weak laptop, 1.15 an average gamer's, 1.5 a good
mid-range, 2.0 a 13600KF). Nothing here was run on a graphics card: where that matters it says so and names what to read off F3 on a real machine.

## 1. The tools (all in the repository)

| tool | what it does |
|---|---|
| `tools/profile_funcs.py` | times whole functions a call at a time, in a scratch copy of the project (the figures below are from it) |
| `tests/lobby298.gd`, `tests/mix298.gd` | the host's step with N men in the yard / a mix of men, foes, beasts; `RT=1` runs in real time on one core |
| `tests/frame298.gd` | the frame's own scripts (the men's drawing, the match's), `ARMOR_IDS=lorica` for one piece |
| `tests/render298.gd` | a frame drawn for real: draw calls, objects, primitives, the engine's recording time. Runs on Mesa's software Vulkan (lavapipe) under Xvfb when there is no card: `tools/render_load.sh` |
| `tests/nodes298.gd` | what a man is made of (nodes, multimeshes, instances) and what building him costs, bare and in each piece of armour |
| `tools/loopsim.py` | a model of the main loop (frames, steps, the engine's cap, the governor, vsync) for four kinds of computer; checked against real-time runs |

## 2. Where a step goes (8 men fighting, 10.8 ms)

`control` is 60% of the step (806 us a man and step), the arm drive `_drive_arm` 417 of it (31% of the whole step), then a flat tail of forty functions of 2 to 60 us (the README's
"What is left to spare" section has the list). The rest of the step: Match's own work 1.4 ms, Combat's contacts and blows 0.8, the parts' and weapons' `_integrate_forces`
0.55, the physics engine proper about 1.9. With eight bots and six armoured men (15 on the sand, 20.1 ms): `control` 10.4 ms (52%), the bots' `update` 1.1 (a third of it
`nearest_enemy`, a scan of every fighter for each bot), contacts 1.4, `_integrate_forces` 1.2.

## 3. Armour: why it takes so much

Eight men walking about (nobody dies, so the two runs are of the same fight), the same kit but for the armour (helmet, lorica, manica, greaves):

| where | with | without | armour's share |
|---|---|---|---|
| the host's step (`tests/lobby298.gd`) | 8.92 ms | 7.52 | **+19%** (175 us a man and step) |
| the frame's scripts, the men's drawing (`tests/frame298.gd`) | 2.1-2.4 ms | 0.9-1.0 | **x2.3** (175 us a man and frame) |
| building a man (`tests/nodes298.gd`, scripts only; the first, then the next) | 750, 364 ms | 357, 162 | x2 |
| what a man is made of | 25 multimeshes, 23.7 thousand cube instances | 13, 15.2 thousand | +12 and +56% |
| what is drawn, 8 men standing (`tests/render298.gd`, software Vulkan, all passes) | 720 draw calls, 7.14 M primitives | 610, 5.50 M | +18% and +30% |

On a 60-frame second the step runs twice a frame, so armour costs a frame about 4 ms of the processor at eight men (2 x 1.4 for the steps and 1.3 for the drawing), a quarter of
the 16.7 there is. On the card it is a third more triangles (a man is 15 thousand cube instances bare, 24 thousand in armour, each drawn in the main pass and in the sun's shadow
passes: 0.53 M primitives a bare man and a frame, 0.73 M in armour). The engine's own recording of the frame is not the cost (1.5 ms for 443 draw calls and for 720).

**In the frame:** `Fighter._clip_arm_armor` is 160 us a man and frame in armour against 3 bare, nine tenths of what armour adds to the drawing. It runs for every armoured man every
frame (his arm's plates against his chest's: a plate that has gone in is not drawn), and is three parts: the shoulder guards (`_clip_shoulder_guards`, 96 us: `guard_hidden` 44,
`FineArmor._over_top` 11), the plate loop (35 us; 69 plates of a manica, each a box test and the outline's `in_outline`) and the limbs' cones into the shell's shader parameters
(`_limbs_in_armor`, 28 us). It is drawing only, so it can be made cheaper without touching a fight, and one piece alone does not cost it: the lorica alone adds 0.48 ms to eight men's
drawing, the manica 0.08, the greaves 0.07, the helmet nothing, all four 1.04: it is the chest and the arm armour together that cost, because they are clipped against one another.

**Cut (#298k, the first of "what to do", drawing only, each part held to the old pass by a test):** `FineArmor._over_top` is kept on the piece (it walked the plate list of every cuirass piece
in every frame: 9.6 us to 1.7); the arm's plate loop is pre-filtered by the C++ core (`VoxelCore.clip_plates`: the few plates that lie in the chest's box or are hidden now, the only ones the
script has anything to decide on; `test_the_arm_armours_clip_pass_is_the_old_pass` runs the old loop beside it over random boxes and knocked-off plates, with and without the core);
the shoulder guard's cut-off search is made round the voxels under the arm only (`VoxelCore.guard_cut_near`, from the guard's own base: 62 us a call to 23, a third of the frames; a
differential test on random graphs and on lattices with walls across them); and the arms' cones are kept per part (`_limb_cone`: 14 us to 7). A man's `_clip_arm_armor` falls from 157 us a
frame to 99 (instrumented, `tools/profile_funcs.py`). Not instrumented, the same tree with the scripts of `2774cd1` against these, alternating, eight armoured men on the sand: the men's
drawing walking 2.14 ms to 1.73 (-19%), the frame's scripts 2.87 to 2.48 (-14%); fighting the men's drawing 2.62 to 1.92 (-27%), the scripts 3.58 to 2.79 (-22%). What is left of the pass: the guard's
`guard_reach` (12 us a man and frame), the cones' four shader parameters a shell (about 20 us), and about 30 us of the guard pass's own bookkeeping (string keys, `get_meta`, dictionary
lookups) that a per-shell record would take down by perhaps a third.

**In the step:** the armour adds 153 us to `control` (819 against 666), 110 of it in `_drive_arm`: the arms are kept out of the trunk as it is DRAWN (its fine outline, `sculpt`) when
there is armour on him, and out of its box when he is bare. `_clear_body` +36, `_elbow_clear` +16, `_keep_arm_out` +20, `_hand_off_trunk`/`_elbow_off_trunk` and the rest +38. Of the 153,
64 us are the memo and gating calls that only an armoured man makes (`_outline_m` 18, `_armored_m` 18, `_plate_band_now` 8, `_trunk_sculpt` +7, `_trunk_sculpt_worn` +6, `_armored` +8: 33
calls of 1-3 us each); the geometry itself, already in the C++ core, is the smaller part. A persistent per-man record of the armour state (built when his armour changes, `_armor_dirty`,
not worked out afresh each step) in place of those calls was expected to take about 55-65 us a man and step off (6-8% of an armoured step, to the bit); it took about 5% (below).

*Made* (#298k): the armour state is kept across steps. `Fighter.armor_changed()` is called by whoever puts a new armour list on a part (`_add_armor`, `set_armor_pieces`, the forge's bench,
`_clear_shell`) and counts `_armor_ver`; each arm phase (`_arm_phase_begin`) clears the memos of the step alone and, when the count has moved, those of the armour (`_armored`, `_outline`, the band, and
`_arm_rec`: for each arm the four things the C++ core is given, the upper arm's outline and whether it wears armour, the forearm's). A plate knocked off changes no list and nothing of this reads which plates
are on. Checking the five parts' lists by identity instead of a counter cost 23 us a step (the engine's `get_meta` is about 1.5 us a call) and ate all of it: the counter is the way
(`test_the_arm_records_follow_his_armour` fails when a call to `armor_changed` is taken out). The memo and gating calls an armoured man makes: 33 a step before, 9 now (`_outline_m` 17.5 us to 2.2,
`_armored_m` 16.3 to 2.5, `_armored` 11.9 to 0, `_plate_band_now` 8.2 to 3.5, the record 6.3 added; `_clear_body` 64 to 46, `_elbow_off_trunk` 32 to 19, `_elbow_clear` 23 to 15; instrumented, so the
figures overstate the saving by the timers that went with the calls). Wall clock, eight armoured men walking about and fighting, alternating, 20 runs in two sets (one set on two trees, one on the same
tree with the scripts swapped): the median step 7.37 ms to 7.01 walking (-4.8%) and 9.65 to 9.18 fighting (-4.9%), the mean -5.1% and -7.3%; the machine's own spread from run to run is +-8%, so
read it as "about 5%". The fight comes out the same to the bit: the `LOBBYHASH` of every run is the same, and the seven fights of `tests/lobby298.gd` (idle, walking, fighting, other
weapons, with and without armour) and the forty lines of `tools/replay_check.sh` are identical to those of `2774cd1`, 47 of 47.

**Building:** a first armoured man costs 750 ms of scripts, the next 364 (the shell layouts are cached): the hitch when a wave of armoured foes is brought in. Staged over the frames
(#182) it is spread, not removed.

What it would take to bring an armoured man to a bare man's price: the step's armour record and the frame's clip pass are done (above); what is left is the guard pass's bookkeeping (10-15 us a man
and frame), fewer cube instances in the shell (the largest part of the card's extra, a change of how the armour is drawn), and the shell's multimeshes merged where nothing of them is knocked off.

## 3b. The card's side: what the knobs save (software Vulkan, 8 armoured men standing, 320x180, `tools/render_load.sh`)

| run | draw calls | primitives (all passes) | the software rasteriser's time |
|---|---|---|---|
| default (high) | 720 | 7.14 M | 5.0 s |
| the same, bare | 610 (-15%) | 5.50 M (-23%) | 4.3 s (-14%) |
| `SHADOWS=0` | 272 (-62%) | 2.92 M (-59%) | 4.3 s (-13%) |
| `QUALITY=low` (the game's own low level) | 713 (-1%) | 7.35 M (+3%) | 3.9 s (-21%) |
| `QUALITY=low SHADOWS=0 FOG=0` | 272 (-62%) | 2.92 M (-59%) | 3.3 s (-35%) |
| **now: `QUALITY=low`, one shadow cascade** | 533 (-26%) | 5.52 M (-23%) | |
| **now: `QUALITY=medium`, two cascades** | 559 (-22%) | 5.85 M (-18%) | |
| now: `QUALITY=high` (four cascades, as it was) | 720 | 7.14 M | |

What is drawn is the men, nearly all of it (the arena alone with one man is 2.0 M primitives and 390 draw calls; a man is 0.54 M bare, 0.74 M in armour), and **the sun's shadow passes
are 59% of the triangles**: every man's 15-24 thousand cube instances are drawn again in each of the shadow cascades. The game's `low` quality level (`Arena.apply_quality`) takes out the
pixel work (SSAO, SSIL, fog, glow: the rasteriser's time falls a fifth) and leaves the geometry exactly as it was (+3% primitives: the shadow distance of 25 m takes in every fighter), so on a card
that is held back by the triangles `low` did nothing. **Cut (#298k, drawing only):** the sun's shadow map is now cut into one cascade on `low`, two on `medium` and the four it always was on
`high` and `ultra` (`Arena.apply_quality`; `test_the_suns_cascades_follow_the_quality_level`): the men are drawn once, not once in each cascade they stand in, and one cascade over `low`'s 25 metres is 6 mm
a texel of the 4096, finer than a voxel. The first row of the table with the new figures: `low` 7.35 M primitives to 5.52 (-25%) and 713 draw calls to 533. Left to do on the same road, also drawing
only: a cheaper mesh for the men's shadow pass, shadows only from the men near the camera, fewer cube instances in the armour's shell. What the real card makes of any of it is F3's "graphics card" figure; the rasteriser's time here is not a card's. The
engine's recording of the frame on the processor is 1.0-1.7 ms in every run (it does not grow with the draw calls).

## 4. The ways tried

| way | verdict | evidence |
|---|---|---|
| Script-level changes to `control` (memos into fields, guards of calls that do nothing) | 1-2% of the step; not made | the call overhead is 0.1 us; what costs is inside the functions |
| Native ports of what is left (`weapon_aim`, `_drive_forearm`, `_hold_elbow`, `_lock_elbow`, `hand_target_local`, `_elbow_clear`) | 6-8% of the step, two days, to the bit | 108 us a man and step to port at the 60-65% the first ports saved (`arm_micro298`) |
| All of `control` and the arm drive in C++ | 35-45% of the step; weeks; to the bit (the same gates) | `control` 806 + contacts + callbacks; no hot spot, so only the whole is worth it |
| Visual LOD of the men's drawing in scripts | +0.6 ms a frame at 9 fighters, +0.9 at 15 (5-6% of a step); half of it at best | `pacehash298` with `DRAW=1` against `DRAW=0` |
| `control` in parallel | not possible to the bit: the same fight with the fighters seen to in the reverse order has another fingerprint (120 and 480 steps), also with the dice seeded afresh for every fighter every step: the fighters see one another's changes within a step. And the physics calls (impulses, rays) belong to the main thread | scratch loop over `Match.entities` |
| The engine rebuilt with profile-guided optimisation | not testable here: the engine's source cannot be fetched from this machine (403 from the proxy); `clang` and `gcc` are here. Worth trying on a machine that can; to the bit as far as the scripts go, but the physics engine's floats may differ from the stock build's | |
| The fighters in a process of their own | the picture on its own core at the vsync interval whatever the steps cost; the game runs slow only if the steps alone do not fit. A room of 8 free-for-all, host on core 0: the host that draws its men (scripts only) keeps up 102 of the 120 steps (42 frames, worst second 26), the host that does not 115 | `tools/net_load.sh`, `HOSTDRAW=1` scratch |
| Shadow cascades / `low` quality (drawing only) | **made**: one cascade on `low`, two on `medium`: -25% and -18% of the triangles; changes no fight | section 3b |
| The armour state kept across steps | **made**: about -5% of the step for an armoured man, to the bit (47 fingerprints) | section 3 |
| The armour's clip pass in the frame | **made**: the men's drawing -19% walking, -27% fighting (eight armoured men), drawing only | section 3 |
| The dead's contacts, the pieces and the loose weapons (the late Endless Arena) | **made**: two cuts to the bit and the sleeping of what lies still, which is not to the bit (gameplay unchanged) | section 8 |
| A load governor (shedding far men's work under overload) | changes far men's physics: not to the bit, outside this document's rule | #304 |

## 5. The model

`tools/loopsim.py`: see its header for the checks (it is within 10-15% of real-time runs on one core, nearer on the steps). Frames a second / game speed, all fighting, in armour:

| 8 fighters | weak laptop (0.8) | average (1.15) | good mid (1.5) | 13600KF (2.0) |
|---|---|---|---|---|
| no armour at all | 43 / 71% | 55 / 100% | 60 / 100% | 60 / 100% |
| as it is, in armour | 33 / 55% | 28 / 93% | 57 / 100% | 60 / 100% |
| armour fixes, made (step -5%, frame -0.7 ms fighting) | 36 / 59% | 31 / 97% | 59 / 100% | 60 / 100% |
| + the ports left (-8% more) | 38 / 63% | 40 / 100% | 60 / 100% | 60 / 100% |
| all of `control` in C++ (-40%) + armour frame fix | 31 / 98% | 60 / 100% | 60 / 100% | 60 / 100% |
| the fighters in a process of their own | 60 / 77% | 60 / 100% | 60 / 100% | 60 / 100% |
| own process + all of `control` in C++ | 60 / 100% | 60 / 100% | 60 / 100% | 60 / 100% |

(6 and 12 fighters: `python3 tools/loopsim.py`.) The price of armour is the first two rows: on an average computer eight armoured fighters sit at 28-40 frames where eight bare ones
hold 55. The armour fixes of section 3 close a part of that; what is left of it is the step itself, and only the whole of `control` in C++ or the process of its own gets an average
computer to 60 with eight armoured men.

## 6. What to do, in order

1. **Done (#298k):** the armour's frame clip pass (the men's drawing -19% walking, -27% fighting), the step's armour record (-5%, to the bit) and the sun's cascades on the lower quality
   levels (-25% of the triangles on `low`): the cheapest cuts that are not a rewrite, aimed at the thing the player sees (armoured fights). On the card's side what is left is a cheaper
   shadow mesh for the men, shadows only from the men near, and fewer cube instances in the armour's shell (section 3b).
2. A real reading from a real machine before anything larger: `tools\host_bench.bat` and F3 ("physics", "frame without physics", "drawing", "graphics card") in a full room, on the
   owner's computer and on an average one. They say whether a computer is held back by the steps (then 3 and 4), by the processor's drawing, or by the card (then the quality level,
   the resolution scale and fewer triangles: what `tests/render298.gd` counts).
3. The fighters in a process of their own, if a floor under the frame rate on average computers is the aim (it does not make the steps cheaper).
4. All of `control` in C++, if the steps themselves must get cheaper for every mode: weeks, the only large cut that keeps every fight.

## 7. Reproducing

```
sh tools/lobby_load.sh 8 walk 6            the step (ARMOR=0 for bare men); tools/frame_load.sh the frame's scripts (ARMOR_IDS=lorica one piece)
RT=1 sh tools/mix_load.sh "men:8,foe:8"    a real-time run on one core (CPU=n picks it)
tools/render_load.sh                       a frame drawn for real (software Vulkan under Xvfb when there is no card): draw calls, primitives
IDS=lorica,manica godot --headless --path . -- --probe nodes298     what a man is made of, and what building him costs
python3 tools/loopsim.py                   the model
godot --headless --fixed-fps 120 --path . -- --probe endless_fps     the late Endless Arena's step, scripts and counts (env MIX, SECS, EVERY, SEED)
```

## 8. The late Endless Arena: the dead, the pieces and the loose weapons (#310, #312)

`tests/endless_fps.gd` plays the Endless Arena of a full room wave after wave, the dead left where they fall. On this machine, late in a run, a step is Jolt about 40%, the nodes'
phase about 45% (94% of it the entity loop: a living man's `control` 5.7 ms, the arms 52% of that) and the bodies' `_integrate_forces` callbacks 10-18%. The dead, the pieces they
leave and the weapons they drop keep Jolt's islands awake and fill the callbacks with contacts nobody reads.

| change | kind | what it did |
|---|---|---|
| Parts of two fallen men in contact are not asked who touched whom (`Combat.report`) | **made, to the bit** | a heap of the dead no longer costs a pass for every touching pair (`tests/test_corpse_touch.gd`) |
| The struck-by-a-weapon scan folded into `Combat.report`'s one pass over a part's contacts (it was a second loop in `VoxelPart._integrate_forces`) | **made, to the bit** | one pass instead of two; the fingerprints of `tools/replay_check.sh` and of the dead-among-the-living runs (`REPLAY_BARE=1 REPLAY_KILL=2`) are the same as before |
| Pieces of voxels (`Chunk`) and loose weapons (`Combat._rest_weapons`) that have lain still for 1.5 s are put to sleep, as the dead's parts are (`Match._at_rest`) | **made, not to the bit** | the late Endless probe (measured below): the step -18% on average (-8 to -31% over three seeds), p99 -18%; what is awake of the dead's parts, loose weapons and pieces 127 -> 61 |

Measured with `tests/endless_fps.gd` (`MIX="men:8,foe:6,beast:wolf*2,beast:lion" SECS=60 EVERY=10 DRAW=0`, one worker thread, seeds 7, 8 and 9, the tree before (d6dddee) and the tree after taken in turn), the mean of the
prints at 40, 50 and 60 s of game time: the step 18.3 -> 15.1 ms (by seed 20.1 -> 13.9, 16.4 -> 14.3, 18.6 -> 17.1), p99 29.3 -> 24.2 ms, the nodes' phase 8.2 -> 7.5 ms; at 60 s the awake bodies of the dead,
the loose weapons and the pieces 127 -> 61. The two trees do not play the same fight (the sleeping is not to the bit, and the bots have their whims), hence three seeds and a spread this wide; the figures are
for this machine, one core, no drawing. Not measured: bouts of two to four men with few dead about, where there is little to put to sleep, and the frame.

How the sleeping goes: the physics wakes what is touched or pushed; what sleeps looks under itself every 0.5 s (what it lay on carried off, it falls); a weapon taken up is made sleepless
(`Fighter.pick_up`); a weapon in a hand is its man's and is left to him (the yard puts it to sleep with him and wakes it with him, `Match._stands_idle`: `tests/test_yard_rest.gd` is what
holds that). Gameplay is unchanged, but a body that sleeps is not stepped, so the fingerprints of a fight with pieces or weapons lying about differ from the old ones; the same run twice
still gives the same fingerprints (25 s, `REPLAY_BARE=1 REPLAY_KILL=2 REPLAY_SECS=25`; the armoured runs of `replay_check.sh` are not alike after 7-10 s whatever the build, their
staged builds being paced by the clock). To undo it: the REST block in `chunk.gd`, the sleep check at the top of `Weapon._physics_process`, `Combat._rest_weapons` and its call, and
the `can_sleep = false` line in `Fighter.pick_up` (`tests/test_rest_sleep.gd` goes with them).

What is left of the step is the arms' drive, about a quarter of it: only the port to C++ keeps every fight. What changes fights (the physics rate, Jolt's iterations, the governor of #304,
freezing the dead for good: about 7% more than the sleeping) waits for a decision.

## 9. The dead carried off, and what a brawl of eight costs (#316, #317)

**The Endless Arena carries its dead off** (`Endless._sweep`, `Match.remove_corpse`): a fallen foe is taken off the sand 8 s after he falls (a little longer while a player
stands within 2.5 m), on the host and on every guest (the `despawn` message), and still counts as slain; a player's own body stays. Before, the dead of the last two waves lay where
they fell (`_clear_old` took the ones two waves back), up to sixteen bodies with a full party's eight foes a wave. Measured with `tests/endless_fps.gd` (`SWEEP=0` against `SWEEP=8`,
`MIX="men:8,foe:6,beast:wolf*2,beast:lion" SECS=60 EVERY=20 DRAW=0`, one worker thread, seeds 7, 8 and 9; the pairs ran side by side and three games at once on four cores, so the milliseconds
are a loaded machine's, and the comparison is the pair's):

| game time | step, dead left lying | step, dead carried off | p99 | steps a second |
|---|---|---|---|---|
| 20 s | 26.1 ms | 24.7 ms (-5%) | 45.4 -> 42.6 ms | 38 -> 41 |
| 40 s | 20.1 ms | 15.7 ms (-22%) | 33.2 -> 30.4 ms | 51 -> 66 |
| 60 s | 15.5 ms | 11.9 ms (-23%) | 25.2 -> 21.1 ms | 65 -> 84 |

At 60 s the bodies awake (men, dead, weapons, pieces) went 148-188 -> 122-127. Not to the bit, and meant not to be: the dead of a wave are not on the sand to be stepped, nor to be
struck; the arms they dropped stay (the newest dozen, `_clear_old`). Not measured: a real run with waves and players (the probe has no waves: the heap there is what one fight leaves,
a real run leaves more), and what the frame saves in draw calls.

**The eight in a clump** (the user's video of a friends' playtest, #317: seven pilot games and the host's on one PC, a quarrel of all eight in the arena). The meter reads: physics
17.1-19.7 ms a step and 46 of 120 steps a second (the game at 38% of its speed: "slow motion"), the frame without physics 16.5-16.8 ms of which the drawing 3.1-3.6 ms and the card
13.5-13.9 ms, the men 3.4 ms, the match 0.5-0.6 ms, all the rest 12.6-12.9 ms (the wait on the card, mostly), 2971-3273 draw calls, the line out 1.18-1.29 MB/s and in 167-176 KB/s,
and "two windows on one computer: the picture is lowered" already on. On this machine eight men fighting cost 10.8 ms a step (section 2): the user's PC pays 1.6-1.8 times that, with seven
other games on it. The 8.3 ms a step that 120 Hz allows is out of reach for eight men in one clump here and there both; the game falls back to two steps a frame (#307) and the world
goes slower. What would cut it, in the order the measures point: the arms' drive in C++ (a quarter of the step, to the bit; section 8), the governor (#304: far men's physics eased
only while the step is over budget), and the card (13.5 ms at 3k draw calls with the picture already lowered: section 3b). What the playtest itself adds is the pilots' games on the same
cores (`Engine.max_fps = 60` for each, `friend_pilot.gd`): a room of eight real machines does not pay it.

## 10. Inside the arm drive, statement by statement (#312)

`tools/profile_lines.py` marks the statements of one function (the ones of its own level, with `--depth 2` the ones one level in) in a scratch copy of the project and prints what each
costs a man and a step (`tools/profile_funcs.py` does the same for whole functions). The 8-man brawl of `tests/lobby298.gd` (`NONPC=1 ARM_LOD=0 IDLE=0`, one worker thread; 10.28 ms a step at
this commit), the figures in microseconds a man and a step, each mark costing about half a microsecond (read them against one another):

| where | us | what it is |
|---|---|---|
| `control`, the loop over the two arms (`for side in [two_side, two_off()]`) | 423 of 756 | 56% of `control`, a third of the step |
| `control`, the loop over the two legs | 94 | feet, kicks, the gait |
| `control`, `_no_fling` / the ground ray / the `for p in parts` passes | 22 / 12 / 16 + 9 | |
| `_drive_arm` (two calls) | 449 (depth 2) | the arm loop's own |
| of it `_clear_body` | 36 | already a native call: 18.7 us a call, the memos and the 20 arguments are what it costs |
| `weapon_aim` / `_drive_forearm` / `_hold_elbow` | 30 / 22 / 19 | an armed arm only |
| `hand_target_local` / `_elbow_clear` / `_unwedge` | 14 / 12 / 11 | |
| `arm_straight` (an elbow's angle asked of every arm, to be thrown away by an `and`) | 10 | cut, below |
| `_lock_elbow` / `arm_func` / `_free_wedged` / `_route_front` / `_keep_weapon_out` | 9 / 9 / 8 / 7 / 6 | |
| the other two hundred statements | about 170 | each 0.5-1.5 us: a dictionary, a vector, a call |

It is flat: no statement is a tenth of the arm drive but `_clear_body`, and that one is the cost of the way a script hands a native call its arguments, not of what the native does.
What that means for the ways of sparing it:
- A native port of one piece is worth what is left once its arguments are paid for: `_drive_forearm` (22 us, a dozen values in, two impulses out) saves about 15, `hand_target_local`
  about 8, the six pieces together the 6-8% of the step this document gave before. Cuts at the script level (the dead work of a statement whose answer an `and` throws away: `arm_straight`;
  a list built where it is not used: `_unwedge`'s three parts) are to the bit (the 8-man brawl, the 6-man mix and the 25 s replay give the same fingerprints) and come to about 1% of
  `control`: below what two runs of the same tree differ by (the step 10.28 ms before and after, the median 10.11 and 9.76).
- The large cut that keeps every fight is the whole armed arm's drive in C++ in one call (a fast path for the common arm, a sword or an axe on a standing man, with the script's drive as the
  fallback for a bow, a thrown spear, a thrust line): it pays its arguments once. About 280 of the 449 us would go: a fifth of the step. It is some 800 lines of C++ that must do the
  script's arithmetic to the bit (doubles for scalars, floats for vectors, the same order), checked against the script call for call; days of work, and nothing of it pays until the whole
  tree under `weapon_aim` is native.
- Even so, 8 men in one clump on this core are 10.3 ms a step against the 8.3 that 120 steps a second allow: with the whole arm drive native about 8.0 (10.28 less 8 x 0.28), just inside it.
  Section 5's model puts it for an average gamer's core (k = 1.15) at 6 fighters held at full speed today and 9 with all of `control` native. A slower core, or the playtest's seven other games on
  the same one, is that much further.
- What does not help to the bit and cannot be had by other means: the physics rate (60 steps a second for the room under load). A blow's harm reads the contact impulse of a step
  (`Combat.report`'s `J`), which is a force times the step's length: at half the rate every impulse is double, and the damage numbers with it. It would have to be retuned.

## 11. The friends' game: stalls, and what the playtest's own windows cost (#319, #321)

The user's video of a game with three friend windows on the same PC ("it feels slower"), F3 on: 13-29 ms a physics step, 14-33 frames a second, the steps-per-frame cap letting go to 5-6 steps a frame
(fps 14-17), the card at 7-17 ms. What it is and what it is not:

- **Not a regression.** The 8-man brawl of `tests/lobby298.gd` (`NONPC=1 ARM_LOD=0 IDLE=0`, one worker thread) at the four builds d6dddee / f7b267a / 4d826d1 / the head: 10.1 to 10.6 ms a step in each, within
  the run-to-run spread.
- **The playtest's own windows.** The three (in the other playtests seven) friend windows are whole games on the one machine. Each cost 41% of a core (`tools/friends_load.sh`'s pilots: `scripts/net/friend_pilot.gd`):
  the 120 physics steps of their own men, the HUD, a 60 frames a second of drawing nobody sees. Now 29%: a window of 30 frames a second (`Engine.max_fps`), its HUD's `_process` off, and the process at below-normal
  priority (`renice` / PowerShell's `PriorityClass`), so the host's window gets the core when the two meet. Still, seven pilots roughly double the host's step on a 4-core box:
  **a playtest on one machine is not what the game costs on separate machines**, and its F3 numbers are the rig's. The pilots keep 120 physics steps a second: `MovePredictor.DT` assumes 120 ticks.
- **What is the game's own: the stalls**, a frame of 100 to 650 ms in the middle of play, each a man built in one frame. Found with the longest-single-call profile (`tools/profile_funcs.py`: `BLKMAX <function> <longest ms>
  <calls> <total ms>`; `tools/profile_lines.py`: `LNMAX <line> <longest ms> ...`, the same for the statements of one function) over the host and three pilots in the yard (`friends_load298`), and, in a
  real game, the F3 hitch record below.

| what | before (one frame) | now |
|---|---|---|
| a friend's armour or body changed at the smith or the physician's (`Match.peer_body` -> `rebuild`) | 425-556 ms | built apart, swapped in the one frame: 20-29 ms the worst frame (`_rebuild_apart`) |
| R in the yard, the yard's auto-respawn (`respawn_request`, `_respawn_apart`) | 121 ms | the fallen man lies until the new one is built over the frames that follow, 20-29 ms |
| the dressing room's man (`MenuMan.stand`, `ArmourStage.dress`: each card of the smith, the gate) | a man built in one frame (60-500 ms) | built over the frames (a staged build, latest asked wins, one at a time) |
| the yard's start: the two dummies and the four keepers (`YardPlay._setup_staged`) | `Match.setup` 2.46 s (host and three friends, one machine, cold) | 1.28 s; the six come in over the next two seconds, worst frame 69 ms |

All of it only with a screen (`Match.staging()`, `stage_start()`: not a guest's, not headless): without one (the tests, `tools/sim.mjs`) every man is built in the frame that asks, as before, so a fight plays out to the bit.
A staged man is built out of the world (`process_mode` disabled, not drawn, not in the physics space) and made one of the match's in the frame he is whole (`_build_apart`, `_bring_in`).

Where a man's build goes (10 men of a yard, cold caches, the first build of a game; 236 ms a man): `Physique.dress` 182 ms (`place_armor` 106, `FineHead.build` 43, `FineBody.build` 29), the parts' voxels 54. The caches
(`Fighter._listed`, `FineBody._shell_maps`, `FineArmor._shells`) make the second man of a look cheap: what is left in a staged build is the first time a build, a helmet, a hairstyle is seen, in chunks of up to 46 ms
(`FineBody._layout`; `shells_make` 36, `_shell_map` 34, a weapon's `equip` 14). The dressing room's man at the menu warms the player's own look before he joins anything.

What is left, with the host staged and three friends in the yard (60 s): no single call over 35 ms on the host in play (`match._physics_process` 34.9 at the worst, the step under the pilots' load), none of the
network's messages; what stops a window is the start of a game: the host's `Match.setup` (the own man and the friends' men, built at once: 0.6-2.2 s cold), a guest's own man (0.3-0.65 s, built at once: he must be
able to act) and its `setup` (0.45 s), the station screen's first showing (0.3 s). Moving those means a start behind a cover, or a man whose first frames are not his own.

**The performance record** (`hitches.txt`, in the game's own folder like `host_check.txt`: the project's, run from the editor or the .bat files; next to the executable, exported; `user://` only where that
cannot be written. Kept whether or not F3 is on: the first version wrote only a frame over 60 ms, with F3 on, in the user data folder, and a game in slow motion has no such frame, its frames are all a
little long: the file never appeared. A game without a screen, the friends' windows, keeps none, or seven windows would write into the host's.) Made at the game's start with a head line (`SESSION START`: the
system, the processor and its threads, the graphics card, Godot's and the game's version, the window), and from then on: `NOTE` lines the game makes of its own starts (`match setup: campaign as host, 4 men in
302 ms`, `the first of the bout's foes are all in: 4 in 3171 ms`, `room over its budget (two steps a frame, the game runs slow): a step costs 9.4 ms of the 8.3 there is`), a `SLOW` line for every stretch of
two seconds in which the game kept under 97% of its speed or ran under 45 frames a second, and, as before, a line for a frame over 60 ms (the steps it took, the nodes made or freed, the messages of the room
that came in: those only with F3 on). The file is begun again past 200 KB. The game prints its path in the Output as it starts.

A `SLOW` line says the game's speed and steps a second, the frames and those over 33 ms, **what a step cost and what the rest of a frame** (by the wall clock: `FpsMeter` is first in the order of the physics
steps and of the process, and reads the time between the frame's first step and its process), the men on the sand, the bodies awake, the draw calls, the room (over its budget or not, the steps a frame it
lets itself take, the friend windows on the machine), and **a cause** (`FpsMeter.slow_cause`): `STEPS TOO COSTLY` (a step over the 8.3 ms there is for it: the machine cannot hold that many fighters, or is
shared), `FRAMES TOO COSTLY` (the steps are under half of the time: drawing, scripts, waiting on the card) or `NEITHER` (the steps and the frames are within what the machine does and it fell behind
all the same: it was not getting the processor). After it, once in twenty seconds of a slow stretch, a `CPU` line: **who had the processor** over three seconds (Windows: PowerShell's `Get-Process` twice;
Linux: /proc; in a thread of its own): the machine's fullness, this game, the friend windows (by their pids, `Friends.live_pids`) and the busiest other programs by name.

**Telling the slow motion's source** (what to run, and what each answer means):
1. `tools\host_bench.bat` (no window, no friends, a minute; it keeps `host_check.txt`): the steps of 2, 4, 6 and 8 fighters on this machine alone. 8 smooth: the machine holds a full room and the slow motion
   is what shares it (the friends' windows, the recorder) or the drawing; 8 too slow: the steps themselves (the machine, the game's cost: the native port, a governor).
2. The slow game as it is played (the eight, seven friend windows, F3 or not), then `hitches.txt`: the `SLOW` lines' causes and the `CPU` lines. `STEPS TOO COSTLY` with the machine over 85% busy and the
   friend windows or another program at a few threads: shared. `STEPS TOO COSTLY` with the machine not full: the game's own cost. `FRAMES TOO COSTLY`: the card or the drawing (F3's card figure).
3. The same fight with fewer friend windows (3, the campaign that ran well), or the recorder off: if the speed comes back, it was shared.

**A bout's start** (a campaign bout, a host and three friends, 4 foes; `tests/startbout`): the first wave was built before the first frame, the stop of "some seconds" at the start of a stage (user). With a screen
its foes now come through the gates over the frames that follow, one after another, as a later wave's do (`Match._spawn_round`, `bring_in(... at_start)`): `Match.setup` 2855 ms -> 1058 ms cold, and 1415 -> 302 ms
after a yard of the same men (a game's usual way into a bout); the foes are in some seconds later (3.4 s when every look is new to the game, the worst frame in it 85 ms). The second wave is not called, nor the
bout won, while the first is on its way in (`coming`). A larger share of each frame for building them (as the gate's cards have) brings them in no sooner: a cold look is made of chunks of 30-46 ms that a
frame's budget does not split, and the worst frame grows to 115 ms; not done.

**The playtest's windows**: the friends' games run with their match told it has no screen (`headless`) cost 26% of a core against 27%: what they cost is the simulation (their own man's steps, the
puppets, the physics), not the drawing. Seven of them are some two cores, whatever the host does: on a machine of fewer than eight cores the playtest's eight-player fight runs in slow motion because of
the playtest. Where a window's 30% goes (20 s of one, the scripts' functions timed): `Match._physics_process` 6.5% of a core (540 us a step: the puppets), the room's poll in `Net._physics_process` 3.8% (the messages
and their snapshots in it), `Combat._physics_process` 2.3% (190 us a step, on a game whose combat is off), `Match._process` 1.3%, the parts' `_process` and `_integrate_forces` 1.9%: a little over half in all, the
engine's own steps and network the rest. At 60 physics steps a second instead of 120 a window costs 21%, not half of 27%: not worth what it takes from its likeness to a friend's game. To play eight without
them, a friend that only sends hands and reads positions would have to stand in for these (not made).

## 12. The user's record: the endless arena with eight players (#310, #321)

His `hitches.txt` (a host with an i5-14600KF, 20 threads, an RTX 4070, and seven friend windows on the same machine; the version that wrote it to the user data folder, with `SLOW` lines and no
cause yet). The room as it went:

| where | men alive | a step | game speed | frames a second |
|---|---|---|---|---|
| the yard (8 players, 6 stall people standing) | 14 | 5.8-6.8 ms | 100% | 35-45 |
| the endless arena, first foes | 11 | 7.6-8.5 | 93%, 83% | 23, 17 |
| one more foe in: the room goes over its budget (two steps a frame) | 12 | 9.8 | 66% | 16 |
| the wave of eight foes against the eight players | 14-16 | 11.6-14.2 | 38-46% (45-56 steps a second) | 23-28 |

- **The slow motion is not a stall.** It is every step costing 12-14 ms of the 8.3 there are: 120 of them need 1.5 s of every second whatever the frames are. The stalls of the session are two
  (1647 ms at the yard's start, the 1484 ms of `match setup` in it; 923 ms at the arena's start) and 22 frames of 60-100 ms in a hundred seconds.
- **It is the game's own cost, not the friend windows'.** His `host_check.txt` (the machine alone, no friends): 8 plain fighters 7.6 ms a step, 6 of them 6.1. The README's table has 8 players and 8 foes at
  20.3 ms on the machine it was made on, which is 1.6 times slower than his by `host_check` (12.1 against 7.6 ms for eight): 20.3 / 1.6 = 12.7 ms, what his record says. Twenty threads leave seven friend windows room.
- **Made: the foes' gate** (`Match.foe_gate_holds`, `bring_in`). A foe of a wave waits outside while one more man would take the step over 7.6 ms (the record's 7.6 ms was 93% of the speed, 8.5 was 83%, 9.8 was
  66%) or the room is over its budget, never while fewer than two foes are on the sand, and the foes come in as the others fall: the wave is all of it, not all of it at once; nothing is held on a host that keeps up, and
  only a foe (not a goat out of a pot, not the first wave of a bout). `tests/gate298.gd` (eight bot players, the arena's waves of eight, `--fixed-fps 120`, on the 1.6 times slower machine): gate off, sixteen on the
  sand, a step of 14.4 ms on average and 89% of the steps over the 8.33; gate on, two or three foes at a time and the wave coming in as they fall. Where eight players alone are over the budget (a slower
  processor) nothing can be held but the foes; the step itself has to get cheaper (sections 6 and 10).
- **Found with it:** `Match._sync_loose` assigned a weapon freed with the dead carried off to a typed variable, which stopped the function there on every step from the first one (a script error a step, and the
  loose weapons' picks not sent); and the loose weapons' snapshot of eight friends' weapons lying about was 1464 bytes, over ENet's 1392 for an unreliable packet (the host's console: "Sending 1464 bytes
  unreliably which is above the MTU"): it goes in parts that fit now (`lsnap_messages`), the hazards with the first.
- **Made: the yard's start** (`Match._setup`, `YardPlay._setup_staged`). The 1484 ms of `match setup: yard as host, 8 men` was the host's man and seven friends' men built before the yard's first frame. With a
  screen the host's man is still built at once (the camera is on him), the friends' are built over the frames that follow, each in his place and with his kit (the boards by the gate are written again for the party when
  the last is in; a friend who left on the way is not brought in), and the yard's own people (dummies, keepers) after them. `tests/yardstart.gd` (`-- --probe yardstart`, STAGE=0 or 1, FRIENDS=7), on the 1.6 times
  slower machine with its suite running beside: setup 2788 ms before, 1056 ms now (the colosseum 210, the host's man 550, the first friend's first piece 200), the friends all in after 1.5 s and everyone after 4.5 s, no frame over 100 ms.
- **The console's `Buffer full, dropping packets!`** came from a process that did not read its socket for half a second or more (the friend windows building their worlds, 1-3.7 s each, as they came into a
  yard or an arena): the packets of that time are lost, the reliable ones sent again. Harmless to the host's game; noise.

## 13. The second record, with the new build: the stops that are left, and where the speed goes (#310, #321)

His next `hitches.txt` (the same machine, the build of section 12 with the log in the game's folder; eight players and seven friend windows, a free-for-all, the yard, the endless arena, a free-for-all):

| where | before | now |
|---|---|---|
| the yard's start (`match setup: yard as host`) | 1484 ms (8 men in the one frame) | **188 ms**, then the friends' men over about four seconds in frames of 60-130 ms |
| the endless arena's start | 918 ms of setup (the eight players built at once) and 1129 ms the frame it is in (with the yard's 1371 nodes freed in it) | cut in this section |
| the endless arena's end | 896 ms (2054 nodes freed, the next match's 344 ms built in the same frame) | cut |
| a wave beaten with friends down | a frame of 536 ms (three or four men built in the one frame to stand up) | cut |
| the first fight of a game | 1229 ms (4 men; 344 ms the next time) | cut |

**Where the speed goes** (the endless arena, 11-12 men on the sand): a step costs 9.3 ms by the clock (`Net.step_ms`), of which the nodes' scripts are 5.4 and the physics engine's own work the rest; there is 8.33. 120 steps need
1116 ms of every second, so the game cannot be at its speed whatever the frames cost: with the engine's catch-up allowed (6-8 steps a frame) it ran at 82-90% and 16-18 frames a second, and over its budget the two-steps cap
gives 35 frames and 58% (35 x 2 / 120). The speed with c steps allowed a frame is `1000c / (120 (9.3c + 10))`: c = 2 is 58%, 4 is 71%, 12 is 82%, and no cap gets past 90%. The card is not the bound: 6-24 ms
in frames of 28-58 ms, 700-2900 draw calls; nor the friend windows (seven of them took 250-660% of a core on his twenty threads). Jolt's solver is not what the step is made of either: with eight men and three foes
(`tools/mix_load.sh`) a step is 13.4 ms at 10 position steps and 12 velocity steps (the project's), 13.7 at 6, 13.1 at 3, 12.5 at 1 and 1, 14.8 at 30 and 30. What would bring it under 8.33 is a cheaper `control` (section 6, the
only large cut that keeps every fight) or the load governor (#304).

**Made.**
- *The friends' men at a fight's start* (`Modes.setup`): with a screen the host's own man is built at once and the friends' over the frames that follow (`Match.bring_in`, as in the yard, section 12); the first wave of the endless arena and a hunt are
  sized for the whole party (`players_count`), and none of the rules that end a round is asked while a man is on his way (`Modes.check`). A friend who left on the way is not left standing in the fight. Eight men: 1081 ms of setup before, 542 now (headless, `tests/teardown_probe.gd`; a screen's colosseum and drawing come on top of both).
- *A match let go of* (`Match.let_go`, the menu's `_end_match` and the backdrop's): the match is out of the world at once (disabled, hidden), its systems go at the end of the frame as ever, its men and what they left a few a frame (6 ms of a frame, one at least), the match last.
  A fight of eight is 1400 to 2100 nodes (1411 collision shapes, 193 bodies, 239 multimeshes, 168 joints): freed it is 50 ms headless or on software Vulkan and 210-960 ms on his card, which is the drawing's and the physics' bookkeeping of every resource, so it is spread.
  Found with it, and mended: the old match's late leaving (`_exit_tree`, at the end of the frame the next match is built in) put the next match's time scale and gravity back to the world's (an Emperor's decree of gravity or of slow time was lost from the yard on) and put the crowd's murmur out (`Arena._murmur_of`: the second match of a session had none).
- *The fallen of a party stand up one at a time* (`Endless._rise`, `Match._respawn_apart`) with a screen, and the rewards, which are for the men as they stand, are offered when the last is up (a pick before it would have found him dead and been lost).
- *The first man of a game* (`Menu._prewarm`): built apart while the menu stands, as the player's own would be (his arms, his armour, his look), then let go; the caches a build keeps are warm for the first fight: 632 ms for the first build of an armoured man, 84 for the second, 103 after the warm-up (`tests/coldwarm_probe.gd`).
- `STAGED=1 sh tools/mp_e2e.sh` plays the whole of multiplayer with every game building as one with a screen does (`Match.screen_emulated`): the friends' men, the waves, the match let go of, against real guests. It found the two assumptions of the e2e's own made right in section 12, and, before the `let_go` waited for a whole frame, the HUD reading the men of a match let go of in the frame it was let go in.
- *The slowing is told* (`Match.load_note`, `Match._note_load`). The two steps a frame (`Net.OVERLOAD_STEPS`, section 12) were meant, but silent: the game went to 58% in the middle of a fight and the player, who had been told nothing, took it for a fault. The state line (the host's and, as it goes to them, every guest's) now says when
  the gate holds foes outside ("3 foes wait outside": a step over 7.6 ms) and when the room is over its budget ("game at 60% speed: 11 men on the sand": over 8.6 ms for two looks), the first of the two being the warning of the second; and each time the room turns heavy or light the record writes what it was made of
  (players and foes alive, the fallen lying, men on their way in or held at the gate, bits of flesh, loose weapons, the step's cost). In the second record it turned heavy twice: for three seconds in the yard as the friends' men came in (21:35:38-41, a step of 10.0 ms with 11 to 14 men still settling), and from the eleventh man of the endless arena on
  (21:36:21, 9.5 ms), to the end of the record. The first is a transient, the second is the step itself, and the line only says so: what takes it away is in section 6.
- *A start waits for everyone* (`Match.hold`, `StartVeil`; README, "A start waits for everyone"). The third record (be3e8934) showed the staged build working (the endless arena's start 101 ms of setup against 918, its first frame 202 ms against 1129) and the user, seeing the friends come in one by one over
  3.5 to 5.6 s on a map already shown and a fight already on, called it an unequal start. In a room with a screen the world is now held from the first frame (physics asleep, `Match._physics_process` out at once, the picture not drawn: `Viewport.disable_3d`), the menu's veil is up, the men are built 30 ms of every frame
  (`Physique.budget_us`: nobody is looking) and, when the host has them all in, each guest has said he has too, the host says "go" and the game begins for all at once. The held frames are not a stall anyone sees, and a third of the time the friends' builds took behind a drawn map goes (the real e2e, host and a guest, eight men: 3.6 s on the host, 4.2 s on the guest).
  What the room's step cost is read as while it is held is the old value (`Net.sim_held`: the held steps are empty ones, and the host would have let every foe of the first wave in at once).
- *The step's cost is read to where the frame's own work begins* (`Net._time_steps`, `Net._on_frame_begins`; `tests/test_step_cost.gd`). In the third record the same seconds read 9.7 ms in `Net` (the number the overload valve and the foe gate go by) and 8.6 in the meter's own steps window at five steps a frame, 7.4 and 4.7 at the two of the valve:
  a fixed 5.5 ms of every frame lay in `Net`'s window and not in the meter's (1.1 ms a step at five steps a frame, 2.7 at two, both lines giving the same 5.5). `Net` read the steps to its own `_process`, and in between the coroutines that waited for the frame, the internal processes and the first nodes' work had run.
  The valve's lines (8.6 on, 7.8 off) and the gate's 7.6 were drawn from the meter's figures, so they were being fed dearer ones: the valve came on at the fight's peak, and then, at two steps a frame, read 2.7 ms too much for 38 s (17:55:50 to 17:56:28: 50-61% of the game's speed) after the fight had eased to 5.7 ms a step; with the steps read as the steps, it goes off at the first
  look under 7.8 and the catch-up (76-93% of the speed at 17 frames a second in that record) takes over. What the 5.5 ms are is not known: the SLOW lines now say where a slow stretch's frames went (`FpsMeter.compose_text`: the steps, between them and the first process, the scripts, drawing and waiting, and a step's own gaps), to be read in the next record.
  The same experiment played with the cap of the steps a frame (`tests/stepcost_probe.gd`, one core, ten bots, a frame's own 8 ms): a step cost 9.3, 9.6, 10.1, 8.2 and 8.5 ms at caps of 2, 3, 4, 6 and 12 (the fight is not the same twice), so the catch-up does not make a step dearer; the speed went 57, 63, 65, 84 and 89% and the frames 34, 25, 20, 17 and 9 a second.

**Left.** The step (above). The first draw of a new material on a card (the veil now fades over the first frame of the map, 0.35 s, so a stop there is behind it) cannot be seen here (the software renderer takes 1-4 s a frame of the yard whatever is built).

## 14. The one test (#325): what it measures, and what each reading says to do

**Version 2** (after the first report, section 15): the parts that report answered (the threads' number, seven games beside it, the sound, the caches, the other renderer, interpolation, full screen, priority, most of the
picture's settings) are run only with `--all`; in their place the test asks what only the player's own computer can say: `cores`, `steps_fast`, `fight_fast`, `readback`, `release_room`, and the core's speed in every sample. About 27 minutes.

**Version 3** (after the second report, section 18): the cores, the fast ones, the threads, the read-back, the render thread, the yard's picture and the room in the editor's build go to `--all` as answered; the test keeps the step and the fight in both builds and the room in the release build (to be read against the second report's, the dead now resting), and adds `wreck`. About 13 minutes. (The parts of the experiment of section 19 are run with `--all`.)

`tools\diagnose.bat` (`sh tools/diagnose.sh`; `scripts/diag/`: `Diag` the test, `DiagPhase` a part, `DiagFrames` the reading of a stretch of frames, `DiagStats` the arithmetic; `tests/test_diag.gd`) is the reading of a real
machine that sections 6 and 11 ask for, as one run and one file (`diagnose_report.txt`). Each part is a game of its own (`-- --diag-phase NAME`): the engine's thread count, its renderer, its caches and
its physics interpolation are settings read at its start, so the test writes an `override.cfg` (marked as its own, the player's put aside and back) or engine flags for each. A part writes a line a result
in a file; the test reads them back, copes with a part that crashes or does not end (a timeout kills it and the report says so, and shows the first errors of its log), and writes the report as it goes.

| part (ids in the report) | what it plays | the reading |
|---|---|---|
| `facts` | the machine, the game, the saved settings, what else is busy (a three-second census, the same as the record's CPU line), Windows' power plan | a computer already over 25% busy is a problem named in the report |
| `steps_auto` | 2, 4, 6, 8 men, 8 men and 3 foes, 8 men and 8 foes, 8 men and 3 lions, 8 men and a cyclops, in armour; 8 men bare; the scripts' own ways (native core off); a minute's drift; a fixed script loop | a step in ms, split into the nodes' scripts, the engine's step after them, and what comes before them; the curve of cost against men; what armour and the native core are worth; whether the step grows as the machine warms |
| `steps_t1/t2/t4/t8` | the same fights with 1, 2, 4, 8 worker threads (`threading/worker_pool/max_threads`), the engine's own pick being `steps_auto` | what threads are worth to the engine's part |
| `steps_burners` | the same fights with seven other games beside it (`DiagPhase._burn`: a third of a core each at below-normal priority, as the playtest's friend windows are, no network) | what the friend windows' share of the processor costs the host's step, apart from everything else a room is (the hybrid cores' scheduling shows here) |
| `release_*` | a pack made with `--export-pack`, a copy of Godot's release template and the native library beside it (no installer, no icon editing: nothing the packager needs); the step and a fight in it | what the build a player runs costs against the editor's debug build (measured here: 8 men and 3 foes 13.0-14.2 ms against 15.4-17.7, 10-20% less) |
| `fight_*` | the endless arena, eight bot players (`tests/gate298.gd`'s) with the foes' gate off (the load is the same every run and every wave comes in whole), drawn, 12 s then 24 s, one window each, muted (`fight_sound` is not) | the frame's make-up (steps, between, scripts, drawing and waiting), the card, the draw calls, a frame over 50 ms with the notes the game had just made, the nodes and resources and pipelines made in it |
| `fight_cold` | the same with the pipeline and shader caches off | what a player's first launch costs: the pipelines compiled in the first seconds, the frames over 100 ms |
| `fight_render_thread`, `fight_<other renderer>`, `fight_no_interpolation`, `fight_fullscreen`, `fight_high_priority` | one setting each | the frame in ms against `fight_base` |
| `render_steady` | eight armoured men walking in the yard (nothing changes from second to second), 5 s a setting | what the men's drawing, the HUD, the sun's shadows, a half-size picture, no anti-aliasing, the quality levels, the fog and occlusion, vsync each are worth to the frame |
| `room_eight` | the game's own menu as the playtest runs it: a host (`--bot`), seven friend windows, the yard, the endless arena from the gate, 4 minutes in half-minute windows, the counters every few seconds, the host's network traffic, the record the game made of it (the room draws the 3D at 70% and caps the frames at 60, `Menu.room_scale`) | the real thing: speed and frames, the valve (`Net.overloaded`), the gate, nodes, orphans and memory over the minutes, KB/s, who had the processor |
| `cores` (version 2) | a game with no window held to each logical processor in turn (`DiagPhase.pin`: PowerShell's `ProcessorAffinity`, `taskset` on Linux), an eighth of the fixed script work on each, then let go | whether the processor has two kinds of core and how much slower the slow kind is (`Diag.core_classes`); "let go" says which kind a game with no window is given. Every `sample` of a fight and of the room carries the same work timed on the game's own thread (`core_ms`): which kind the game is on while it is played |
| `steps_fast`, `fight_fast` (version 2) | the step with no window, and the fight, held to the fast cores (skipped where the cores are of one speed) | the windowless figures as they would be on the cores the game really gets; and whether holding the game to the fast cores (the engine's worker threads with it) is worth doing for the player |
| `readback` (version 2) | 48 MultiMeshes of 1200 instances given as one buffer and drawn; then one instance's colour read, one written, the whole buffer read, the first time and again, a frame between each | what `get_instance_color`/`custom_data` and `buffer` cost on a real card (the engine fetches the buffer back and waits for the card): the game asks at every chip off a part (section 15, the render thread) |
| `release_room` (version 2) | `room_eight` again from the release build's pack (the friends are the same exe) | the room as a player's game runs it: the first report had it in the editor's debug build only |
| `wreck` (version 3) | the endless fight of eight played for 45 s of the game in a window with vsync off, then the match stopped where it is (nothing steps, nothing moves) and each kind of thing taken out of the picture in turn: the pieces, their shadows, the dead, their shadows, the living, the weapons lying, the marks, the blood, the sun's shadows, the anti-aliasing, the HUD, all 3D; and what lay there, counted | what the drawing of a fight's leavings costs on this card, kind by kind: `WRECK` in the summary. The room's drawing and waiting grew from 5.7 to 9.6 ms as a wave went on (section 18) and this machine has no card to say of what |
| `steps_half`, `fight_half`, `room_half` (version 3, with `--all`) | the fights of `steps_auto`, the fight of `fight_base` and the room of `release_room` with `Match.control_half` on (section 19) | what a man's control every other step is worth on this processor: `CONTROL AT 60`, `half` in `FIGHT A/B`, `ROOM, AT 60` |
| `steps_threads`, `fight_threads` (version 2) | the fights of `steps_auto` and the fight of `fight_base` with `Match.control_threads` on (section 17) | what the men's controls cost on this processor's many cores: `CONTROL THREADS` in the summary, `threads` in `FIGHT A/B`, and the errors of their logs, which say whether the hand-made list of plain cases holds |

**What a reading sends us to do.** (The ways are those of sections 4 to 6; the report gives the figure that decides each.)

| reading | what it says | what it sends us to |
|---|---|---|
| `CORES` two kinds, `IN PLAY` near the slow kind's time (or far apart from sample to sample) | the system runs the game's own thread on the slow cores, some or all of the time: a step costs up to twice what it need | hold the game to the fast cores from inside it (the native library can ask Windows: thread affinity or a CPU set), and see `fight_fast` for what it is worth |
| `fight_fast` faster than `fight_base` | the same, or the engine's worker threads on slow cores hold the step's parallel part back | the same |
| `READ-BACK` the first time over a millisecond | every part's first chip stops the frame for that long (the card must finish what it is drawing) | keep the voxels' colours and marks on the CPU's side and never ask the card (task #327): they are written from there |
| `CONTROL THREADS` and `fight_threads` far under the base, their logs clean | the step's largest part can be spread over the cores | section 17's two pieces of work (the couplings between controls, the list of plain cases) are worth their days: do them, then turn it on |
| `ROOM, RELEASE` at 100% where `THE ROOM` is not | the owner's playtests in the editor's exe are the slow thing; the player's game holds the room | play the playtests in the release build (`multiplayer_playtest_release.bat`) |
| `RELEASE BUILD` -10% or more on the step | the editor's binary is the slow part of the owner's playtests; the player's game is that much cheaper | measure and playtest in the release build; no code to change; the models of section 5 hold for the player |
| the scripts' part 70% or more of a step, the engine's 10-20% | the step is the scripts' | the native ports of section 4 (the arm drive, then all of `control`); threads and the engine's settings are worth little |
| the engine's part 40% or more, or `steps_t4`/`t8` clearly under `t1` and the engine's pick | the engine's step | worker threads set in the project; the physics settings; fewer contact pairs |
| `NATIVE CORE` off, or `native core OFF` in a part's first line | the library is not loaded on this machine | find why (the extension file, the system's DLL loading); a fifth of every step |
| `THE FRAME` "between them and the scripts" over 2 ms | work that runs after the steps and before the first process (coroutines that wait for the frame, internal processes) | find it (`fight_no_interpolation` against `fight_base` says whether it is the interpolation of every moving node) |
| `fight_render_thread` faster than `fight_base` | the main thread waits on the engine's drawing | `rendering/driver/threads/thread_model=2` in the project (one frame of latency) |
| the other renderer faster, or a part with errors in its log | the driver's own cost or fault | the renderer the game starts on, per system |
| `render_steady`: "3D not drawn" far under the base, "the men not drawn" most of it | drawing is the frame's cost, and the men are most of the drawing | the men's shadow pass, their cube instances (section 3b); the card's own time says whether it is the card or the recording |
| `fight_cold` against `fight_base`: many pipelines compiled, frames over 100 ms in its first seconds | first-draw stalls (the first launch of a player) | a warm-up of the materials behind the start's veil (`StartVeil`), or the shader baker at export |
| `room_eight` against `fight_base` | what seven friend windows and the network cost the host | the playtest's windows (section 11) against the game's own costs; the valve and the gate's behaviour in a real room |
| `FRIEND WINDOWS` a step dearer with the seven busy games beside it | the processor is shared (too few cores, or the scheduler puts the host's thread on a slow core) | the friend windows' own cost (section 11), or a priority for the host (`fight_high_priority` says whether it helps) |
| `fight_sound` slower than `fight_base` | the sound costs the main thread | the sound's own way (the number of voices, the 3D sound's work) |
| a part's log: a line written thousands of times (`PROBLEM ... the same line`) | a message in the step or the frame (a console build prints each of them: slow) | stop it at its source |
| `DRIFT` upward over the minute | the processor slows as it warms (power plan, cooling, a laptop) | nothing in the game: the owner's machine, and the reading of every other part with it |
| a step under the budget but `THE FRAME` over it | the frames, not the steps | section 6's items 2 and 3 |

The quick run (`--quick`) is the same list with every part cut to a few seconds, for a look at whether a computer gets through the test at all (and `HEADLESS=1 sh tools/diagnose.sh --quick` plays the parts that need no window:
it is a check of `run_tests.sh`). What the test does not play: a guest's computer (it draws what the host sends: `tools/net_load.sh`, `tests/net_load_guest.gd`), the network's own latency (`net (delay)`), audio, and a game
longer than four minutes.

## 15. The first report from the owner's machine (#325)

`diagnose_report.txt` of 24 November: an i5-14600KF (14 cores, 20 threads), an RTX 4070 on Vulkan (driver 32.0.16.1088), 32 GB, Windows 11 (26200) on the Balanced plan, a 165 Hz screen at 2560x1440, the player's saved
settings quality ultra and MSAA 8x, run from the editor's exe (a debug build): 22 minutes, 3% busy before it began, nothing in the way. What it says, and what it does not.

**Where the time goes** (the fight of eight in the endless arena, drawn, gate off; the real game's foreground): a frame of 32 ms at 58% of the game's speed is **the steps 21.8 ms** (2.2 a frame of 9.9 ms each: the nodes'
scripts 7.9, the engine's step 1.9) and **10.1 ms that are not steps** (the scripts' `_process` 4.2, drawing and waiting 5.6, between the steps and the scripts 0.4). The card is 10.4 ms of 32 and does not wait for anything.
The steps are 68% of the frame and the scripts 80% of a step (headless: 6.5 of 8.1 ms for nine men, 10.1 of 13.0 for twelve). The "between them and the scripts" of section 13 (5.5 ms in the meter's record) is
0.4 ms here: whatever it was lay in the room's own menu and builds, not in a fight.

**What is not it** (each against the base fight, the speed of a window and the step of the same load):

| tried | result |
|---|---|
| the engine's worker threads 1, 2, 4, 8, its own pick | the step 13.8 / 12.4 / 13.2 / 12.7 / 13.0 ms (men:8,foe:3): noise; the engine's part is 10-14% of a step |
| seven other games busy beside the step (the friend windows' share) | 12.8 against 13.0 ms: nothing (the friend windows take 2.4-3.3 cores of 20 in the room, and the host does not feel it) |
| physics interpolation off | 9.5 against 9.8 ms: nothing |
| sound on | +3%: noise |
| full screen at 2560x1440 | the same frame (the card 11.2 against 10.4 ms) |
| the game at high priority | no better (53% against 58%, noise) |
| the picture's settings (3D at half size, no anti-aliasing, low and ultra quality, no fog/occlusion/glow, vsync off) | the rest of a frame moves by 0.3 ms or less; the card's time moves 8-15 ms and nothing waits for it |
| the sun's shadows off, the men not drawn | -0.8 and -0.2 ms of the rest of a frame |
| the HUD not drawn, the 3D not drawn | -1.9 and -1.9 ms of the rest of a frame |

**What is**
- **The debug build: 12 to 23% of a step.** The release build made from the pack and Godot's release template: a step of nine men 6.50 against 8.09 ms (-20%), of twelve 11.16 against 13.04 (-14%); in the fight, at equal numbers
  alive (14-16), 8.15 against 9.2-10.8 ms; the whole fight 77% of the game's speed against 58% (that fight happened to be a lighter one: at equal load it is about 10 points). A player runs the release build. The owner's playtests
  (the editor's exe) are 15-20% worse than the game as shipped: `multiplayer_playtest_release.bat` plays them in the release build.
- **The native core is worth 23%** (nine men 8.09 against 10.46 ms with the scripts' own ways): it is loaded (`native core ON`).
- **The room, at ten to twelve men, is just over the budget**: 8.0-9.5 ms a step against the 8.33 there is, 0.8 ms a man (the bots' fight: 0.6, 15 men 9.3 ms). The room says so in its record: "foes held at the gate: a step costs
  8.0-8.4 ms, 10-13 men on the sand", "room over its budget (two steps a frame, the game runs slow): 9.1 ms". With the valve on: 55-71% of the speed at 33 frames; with it off (fewer men) 88-98% at 20 frames, five to ten steps a frame,
  frames of 60-90 ms. So the owner sees two kinds of bad: slow motion at 10-12 men, and a choppy game below 10. The network's share of the host's step is small: with seven friends in the yard (`tools/friends_load.sh`, profiled)
  `Net.send_all` 0.39 ms, `snapshot` 0.08, the poll 0.1, `input_of` 0.07: about 0.6 of 7.0 ms (9%); `Fighter.control` is 4.85 ms of it (70%).
- **The match's start (section 13)**: eight men built in 750-780 ms, the game begins 0.9-1.1 s after the start for all of them at once; the yard with 14 men 2.0-2.2 s; the worst frames at the changes 273, 153 and 106 ms.
- **The first 3D frame of a process costs 1.9 s** (174 pipelines compiled, 51 more in the next frame; 2.5 s with the caches off; a fullscreen run that waited 1.5 s first paid 0.29 s) and on the D3D12 renderer the first frame took 14 s: stay on Vulkan.
  The game as played does not meet it where it matters (his record of the game's start: the worst frame 134 ms: the title's backdrop takes it); a guest who comes straight into a room may. New pipelines later cost 50-85 ms for three or four.
- **The render thread** (`thread_model=2`): drawing and waiting fell from 5.6 to 2.8 ms, but the speed fell from 58% to 49% (the scripts' time in a step 17.6 to 20.1 ms, the frame's `_process` 4.2 to 7.4 ms). The log of that run held
  159,606 lines, and they are not the `Condition "p_image.is_null() || p_image->is_empty()"` error (5 times, once at the start): they are 18,608 warnings of `multimesh_instance_get_color` and
  `multimesh_instance_get_custom_data` "causing RenderingServer synchronizations on every frame", each with a script backtrace (`apply_hit` <- `_blow`, `taken`, `spawn` <- `piece_cells`). The game reads
  the voxels' colours and custom data back out of the MultiMeshes (`FineBody.taken`, `FineArmor`, `FineHead`, `Chunk.spawn` through `VoxelPart.piece_cells`, `Fighter` 1533 and 4572, about fifteen places), and with the render thread
  each read waits for the other thread to catch up: that wait is the time the thread was to save. (Reproduced here under a virtual display with 3D switched off: the same warnings from the same calls.) The way
  through: keep the colours and custom data of a part's voxels on the CPU side (they are written from there, `buffer` and `set_instance_*`) and read them from that copy; then the render thread is a gain, and the
  read-backs (a GPU read-back the first time, a second copy of the buffer after) are gone from the default model as well.
**What the test did badly** (to mend in the next one): the games with no window seem to run slower than the real game: a fixed piece of script work took 118 ms against 66 on the build machine's core (0.56 times as fast), and a
step of eleven men took 13.0 ms headless where the window's fight of fourteen to sixteen men took 9.8. The likely cause is that Windows gives a process with no window a slower core or clock (the owner's own host_check, eight bare
men 7.6 ms, is one of those), but it is not confirmed. If it holds the windowless figures are up to 1.6 times too dear and only their ratios (release, threads, the native core) are to be trusted. Also: the drift over a minute
(13.4 to 6.7 ms) was the fight thinning out, not a clock (now a fight with nobody to kill); the D3D12 part's first window held no frame, so its fight began late; the first window of the render A/B carried 4.7 ms of start-up (a
longer warm-up now); `ram_free_mb` counted the page file (mended). The next run has `steps_window` (the same fights with a window of their own) and the core's speed in the fight's own window to settle the first.

**What it sends us to.** The model that fits the fight above (58%, 31.7 ms against the 32.0 measured) is speed = 1000 c / (120 (c s + r)) for c steps a frame of s ms and r ms of everything else. With the room at ten men (s 8.5 ms,
r 9.7 ms, the valve's two steps a frame) and what each cut is worth (the release build: the step -17%, the rest -13%; the arms' drive in C++: a fifth of a step, to the bit, sections 8 and 10; the rest's cuts from above):

| | a step | the rest | speed | frames a second |
|---|---|---|---|---|
| now | 8.5 | 9.7 | 62% | 37 |
| the release build | 7.1 | 8.4 | 74% | 44 |
| the arms' drive native | 6.8 | 9.7 | 72% | 43 |
| both (what is left of the scripts gains less in release) | 5.8 | 8.4 | 83% | 50 |
| and the frame's rest cut by 3 ms (the HUD 1.9, the render thread 2.8 once mended) | 5.8 | 5.4 | 98% | 59 |

With the last, the valve could be let off (2.15 steps a frame are enough for 100% at 56 frames). Without the port the release build and the rest's cuts alone reach about 85% (s 7.1, r 5.4: 2000 / (120 x 19.6)).
1. Play and measure in the release build (done: `multiplayer_playtest_release.bat`).
2. The arms' drive in C++ (#320): the one large cut that keeps every fight.
3. The frame's rest: the HUD's 1.9 ms (done: section 16), the render thread once the MultiMesh read-backs are gone, the men's `_process` (4.2 ms a frame).
4. The valve: a cap of three steps (71% at 28 frames by the model, for a step of 8.5 ms) in place of two (62% at 37 by the model; the room's own record 55-71% at 33), or aiming at 24 frames rather than 30 (the owner's choice: speed or frames).
5. Half the controllers' rate, or 60 steps a second for the room under load, are the only cuts that reach 100% on a 10-12 man room without the port (the release build and the rest's cuts reach about 85%), and they change every blow (section 10): the owner's word.

## 16. After the first report: what was cut, and what the second test asks

**The HUD** (`scripts/ui/hud.gd`, `tests/test_hud_cost.gd`). The report's "the HUD not drawn" was 1.9 ms of a frame, and its scripts are half of that: timed here in the same fight with no window (`Hud._process` and the
figure's own drawing), 1.2 to 1.4 ms a frame, now 0.4:
- the figure's columns (every voxel of every part walked, to count what is left of each column) were counted over again every half second whether or not a voxel had gone, 6 ms of that frame: now a part's columns are
  counted again only when its voxels have changed (`_col_sig`: the part, its grid, a hash of its `alive` bytes), 0.2 ms;
- the figure was drawn anew every frame (a few hundred rectangles of script): now 20 times a second, and every frame while the plate is knocked (its shake is quick);
- each gauge put its label's colour on again and asked for its icon to be drawn again every frame: now when it goes low or comes back, and the gauge itself is drawn when it has moved or pulses;
- the prompt's and the place's texts were built every frame: now 10 times a second.
Nothing of it is seen: `tests/hudshots.gd`'s pictures before and after are the same figure, gauges and plates.

**The render thread, read again** (section 15, corrected there): the log's 159,606 lines are the engine's warnings of MultiMesh read-backs, not the image error. The second test's `readback` part says what one costs on the card.

**The second test** (section 14, version 2) asks what this machine cannot say: the speed of each core of the owner's processor (six fast cores of two threads and eight slow ones: the games with no window of the first report
were given the slow ones, which is why their steps cost what this 2.1 GHz machine's do and the window's fight 1.6 times less), which kind the game's own thread is on while it plays (every sample), what the fight and
the step are worth held to the fast ones, the room in the release build, and a read-back's cost on the card.

## 17. The men's controls on the worker threads (an experiment, off in the game)

A fighter's `control` is 70 to 80% of a step's scripts (sections 8, 10, 15) and the game runs it for one man after another on one core. The owner's processor has twenty threads. `Match.control_threads`
(`-- --control-threads`; `scripts/game/match.gd`, `tests/test_control_threads.gd`): the loop of `_physics_process` still goes over everyone (wishes, AI, items), but the control of a man who is only fighting
(`_threadable`) is put on a list, and the list is run on the engine's worker pool when the loop is done (`WorkerThreadPool.add_group_task`); beasts and the men in a rare state run where they always did.

What it took to make the engine let it:
- the engine's checks on touching nodes from a thread are for the debug build only and can be put off for a thread (`Thread.set_thread_safety_checks_enabled(false)`), each thread touching its own man's bodies;
- the physics space's state cannot be asked for from a thread ("!Thread::is_main_thread()"): it is handed over (`Match.dss`), and rays through it from a thread are answered;
- what a thread asks of the physics server (a torque, an impulse) goes into a queue that the main thread empties when it next speaks to the server, and the step itself does NOT empty it first: the forces
  of every control came a step late and the men thrashed. The main thread asks the server a question when the threads are done (`get_process_info`), and they land;
- a node cannot be added to the tree from a thread at all (`pick_up` -> `_grip_joint`): such steps are not the threads' (`_threadable`: no hand reaching or wrenching, no grip or swap asked, nothing readied
  to throw, no net, on his feet, not near death, past his first second).

What it gives, here (four threads: two cores; the diagnostic test's `steps` part, `#thr`):

| | as it is | on the threads | |
|---|---|---|---|
| 8 men | 7.7-8.1 ms | 5.5 ms | -30% |
| 8 men and 3 foes | 13.7-15.6 | 11.0 | -20 to -29% |
| 8 men and 8 foes | 21.3-22.1 | 15.5-16.4 | -27% |

and with every control on the threads, the beasts' too (the first sketch): 7.7 to 4.7, 12.9 to 9.5, 21.0 to 13.6 ms (-39, -26, -36%). Two cores halve the controls at best; six fast cores and eight slow ones should
take them to a fifth or less, which would be a step of the room's ten to twelve men at about 4 ms where it is 8 to 9.5. That is the one cut found that is larger than everything else on the list together,
and only the owner's machine can say what it is there: the test's `steps_threads` and `fight_threads` (version 2).

What stands between it and the game:
- **It is not the same fight.** All the controls held back to the loop's end and run in the same order: the same to the bit (`tools/replay_check.sh`'s fingerprints). The men's controls in another order, still one
  after another: another fight from the first step they are run so (three of seven men differ in that step, then all). No dice are drawn in a control, so it is something one man's control writes that another's
  reads in the same step, or the order in which their forces reach the physics; not found yet. On threads the order is the threads' own, so no two runs are alike: a fair fight, not a repeatable one. The tests
  are run without it. To ship it the coupling is to be found and given to each man for himself (or the order made not to matter), which the fingerprints can then prove: forwards and backwards the same.
- **The list of plain cases is made by hand.** 217 functions can be reached from `control`; those that add nodes, free them, emit to the game's listeners or draw dice are in the rare branches (a reach, a wrench,
  a fall, a death, eyes and ribs), and `_threadable` keeps those steps on the main thread by their signs. A sign missed is an engine error in the log (adding a node) or a race with no error (a listener
  run on a thread). The test's parts report every error of their logs.
- Beasts are not on the threads yet (their `control` has not been read for this).


## 18. The second report from the owner's machine (test version 2), and what lies on the sand

**What it settled** (i5-14600KF, RTX 4070, Windows 11, the editor's binary and the release build):
- **The cores.** 12 logical processors are fast (the fixed loop's eighth in 7.2 ms) and 8 slow (15.5 ms, 2.15 times as long); a game with no window is put between them (11.2). So the first report's windowless figures were the slow
  cores'. In play the game's own thread has a fast one: 7.1-7.4 ms in the fights, 8.4-8.8 in the room (seven friends' games beside it). Held to the fast cores the fight gains 2 points of speed: not where the time is.
- **The release build**: a step 14-18% cheaper (men:8 3.28 against 3.88 ms; the fight 8.4 against 9.8), the rest of a frame the same (9.2 against 9.3).
- **The controls on threads** (section 17): men:8 -13%, with 3 foes -8%, with 8 foes +3%; in the fight the speed fell to 32% (42,176 engine errors: a wound's blood added to the scene from a thread, a case the list of plain
  steps missed, and each error printed with its trace). On twenty threads, eight of them slow, a script's work does not spread: not for the game as built.
- **The render thread**: drawing and waiting 5.4 -> 2.4 ms, but the steps cost 15% more and the frame's scripts 3.7 -> 6.0: the game's reads of its MultiMeshes each wait for that thread. (The first read of a MultiMesh given whole
  costs 5.8 ms on this card, the worst 9.6; the game's own are kept in memory from the start, `FineBody._keep_in_memory`, and never pay it.) Its 3 ms are there to be had once the reads are of the game's own copies.
- **The HUD** (section 16): the yard's frame 8.4 ms with it, 7.8 without: 0.6 where the first report had 1.9.
- "WINDOWLESS +57%" is not a finding: a step's gap in a window holds the frame's drawing as well (the scripts' part is 3.44 against 3.24).

**The room in the release build** is the report's news. A step, in each half minute of a wave of eight players (the scripts' and the engine's part):

| when | alive | the scripts | the engine | drawing and waiting | draw calls |
|---|---|---|---|---|---|
| the yard | 8 men | 4.08 | 0.62 | 5.7 | 841 |
| 0-30 s | 8 men, 2-5 foes | 6.25 | 1.73 | 6.7 | 1583 |
| 30-60 s | 7-8 men, 2-3 foes | 6.84 | 2.70 | 8.7 | 3296 |
| 60-90 s | 5-6 men, 2-3 foes | 5.76 | 2.60 | 9.6 | 3946 |
| 90-120 s | 1-4 men, 3-4 foes | 5.17 | 2.53 | 9.0 | 2707 |

With seven or eight alive a step costs 8.4 ms where eight in the yard cost 4.7, and it is over the 8.33 there is from the tenth second to the hundredth: what the fight leaves on the sand costs as much as the living.

**The cause, found here** (`FX_ON=1` and the endless fight of eight played to 45 s with no window: 5-6 alive of 9-10, 57 pieces hanging, 155 bodies awake). A dead man's guts are a rope of up to 28 jointed pieces, his flaps
hang by joints; none of them was ever put to sleep, the rope pushed its links and his trunk out of each other every step (`GutRope._keep_out`), and a body awake on a joint keeps what it hangs on awake: the dead never rested,
however long they lay. Now the rope of a dead man lies still with him (`GutRope._lies_still`: his trunk and every link slow for 1.5 s, nothing left to pour) and `Match._at_rest` puts what hangs on a resting corpse to
sleep with it (`Chunk.hanging_on`). Before and after, the same fight: a step 9.1-9.9 -> 7.7-8.2 ms, bodies awake 155 -> 78, all 40 parts of the dead asleep. A blade laid on the guts still cuts them
(`test_organs`). The fingerprints of `tools/replay_check.sh` are the same on every line that repeats.

With it in this batch:
- **Contacts nobody reads are not written down** (`Combat.report`): a touch is noted only for a beast's part or a forearm (their only readers), a pair kept only if one of the two can strike. 3% of a step in a clump of sixteen.
- **Blood and sparks throw no shadow** (`Fx.make_burst`, `emitter`): 67 emitters late in a fight, each drawn again into each of the sun's shadow maps.

**What is left**, by size (the function profile of the same late fight, eight alive): the living men's `control` is three quarters of the scripts (778 us a man, `_drive_arm` 46% of it: section 10); thirty weapons, held and
lying, 0.75 ms (`_process`, `_dry_blood`, `_physics_process`); 50-90 pieces 1.3 ms of a step and its frame; the pieces' and the dead's draw items (two shadow-casting MultiMeshes a piece).

**The sum for the goal** (eight players and their foes at sixty frames): two steps and the frame's rest in 16.7 ms. Today, release, sixteen fighting: 2 x 8.4 + 9.2 = 26 ms. The arm drive native (section 10) brings a step to about
6.5; the render thread, its reads gone, the rest to about 6; so 19 ms, 52 frames at the full speed, before anything of sections 4 and 17. The rate of the physics is the other half of it and is the owner's to choose.

## 19. A man's control every other step (an experiment, off in the game), and what the gate does with a saving

**The experiment** (`Match.control_half`, `-- --control-half`): a man's `control` is run every other step with its `dt` doubled (the same pushes in a second, given half as often), half of the men on the even steps and half
on the odd; the bodies, their contacts and a blow's harm are stepped as ever. An order given for one step only is carried over the step left out (`Match.merge_skipped`).
- **What it saves** (the endless fight of eight with no window, two runs side by side on this machine): a step 15.2 -> 11.1 ms with fifteen or sixteen fighting (-27%), 7.7 -> 5.0 ms with eight men standing after the wave
  (-33%). The wave was beaten in the same time by the same men (ten alive at 20 s, eight at 30 s, in both).
- **What it breaks**: the whole test suite run with it on, 144 checks of 1205 fail in 24 suites. A weapon is not picked up off the sand (`test_pickup`, 6), a jump leaves the ground by a centimetre (`test_fight`), a guard's point
  wanders 2 to 6 mm about its mark and two hands' blade lies 33 degrees off the mouse at the far marks (`test_arms`, 8), a light blade held low out to a side 16 to 19 degrees off (`test_aim`), a thrust 14 degrees off the
  crosshair (`test_controls`, `test_thrust`), the yard's rest (`test_yard_rest`, 12). The drives are tuned to a push a step; some of what they do is counted in steps, not in seconds.
- So it is not a switch to be thrown: it is off, its parts of the test are run only with `--all`. What could be made of it, each a piece of work of its own: the arms' drive every step and the rest of `control` every other
  (the arm loop is half of `control`: about a fifth off a step; `control` has to be cut in two for it), or the foes' controls alone while the room is over its budget (half of the saving in a room of eight players, and foes
  that strike less truly on a slow host).

**What the gate does with a saving.** A foe is held at the gate until a step costs less than `GATE_BUDGET_MS`, 7.6 ms: 912 ms of every second for the steps and 88 for the frames. So whatever is saved in a step is spent
on more foes on the sand at once, not on frames: the room sits at the edge of its slow motion by design, however fast the code. For f frames a second of r ms each beside the steps, a step may cost (1000 - f x r) / 120:

| frames a second | the frame's rest | a step may cost | the owner's release build today |
|---|---|---|---|
| 30 | 9.2 ms | 6.0 ms | eight men fighting cost about 4.5: three foes with them |
| 45 | 9.2 ms | 4.9 ms | one foe |
| 60 | 9.2 ms | 3.7 ms | not eight men |
| 60 | 6.0 ms (the render thread, section 18) | 5.3 ms | one or two foes |

A gate that keeps the frames their share (a budget worked out from the frame's own rest and a frame rate to keep) holds more foes back on a slow host and lets them in as the others fall: the wave is the same, fewer of
it at once. That is the game's pace in a full room, so it is the owner's to choose, with the frame rate to keep. With the arm drive native (section 10) a man costs a fifth less and every row gains a foe or two.

**The owner's choice: 45 frames.** The gate now works its budget out (`Match.gate_budget`, `GATE_FPS`): what is left of a second after 45 frames of the host's own measured rest (`Net.rest_ms`: a frame from where its idle part
begins to where its picture is handed over, the engine's `frame_post_draw`; the sleep of a frame cap comes after that and is not in it, so a game held to 30 or 60 frames by a cap is not read as a slow one), over 120 steps,
never more than the old 7.6 ms. A frame's rest of 9.2 ms leaves a step 4.9 ms, of 6 ms 6.1; a game with no screen reads no frame and keeps the old budget (the tests are not touched). There are always the two foes of
`GATE_MIN_FOES` on the sand; the rest of a wave come in as the others fall. The report's room samples say the rest and the budget beside the step (`a frame's rest ... (the gate lets a step cost ...)`).

## 20. The arm's drive in C++ (#312b, the owner's word given): the plan

What section 10 measured holds: `_drive_arm` is 46% of a living man's `control` (177 us a call here in a late fight, two calls a man), about 60 us of it already in native calls that are paid their arguments one by one
(`clear_body`, `keep_arm_out`, `keep_hand_front`, `hand_off`, `elbow_off`, `keep_elbow_low`), and the rest two hundred statements of half a microsecond to a microsecond and a half and thirty-odd script functions
(`weapon_aim` 172 lines, `_drive_forearm` 52, `_free_wedged` 44, `hand_target_local` 40, `_elbow_clear` 33, `_lock_elbow` 29, `_drive_wrist` 28...: about 1300 lines under it).

- **A fast path, the script the fallback.** One native call drives the plain arm whole: a man on his feet, the arm whole and unbroken, a blade or a shield or nothing in the hand, in one hand, no punch on its way, no throw, no
  bow, no reach, no thrust line, no crawl. Any other step of any arm is the script's `_drive_arm` as it is. The native path must leave every field the script would have left (the ones it sets to nothing as well).
- **The state is handed over once.** The per-side dictionaries are reference types: an array of them, made once for a fighter and kept, is one argument; the native reads and writes `d[side]` through it. The scalars of the step
  go in one packed array. What the bodies say (transforms, velocities) is read once a body: within a step a node's own velocity and place do not change with the pushes given (they are the step's first state).
- **To the bit, proved twice.** Each section is first run dry beside the script (it works its values out and gives nothing a push; the script, marked in a scratch copy, gives the same values at the same places, and the
  two are compared bit for bit over real fights), then switched on and proved by `tools/replay_check.sh`'s fingerprints. The types are section 4's: scalars double, vectors float, a vector times a scalar taking the scalar as a float, the engine's own normalize.
- **In this order**: the shield's and the empty hand's arm (the shorter drive: the mark, the elbow, four PD drives, the hand's pull), then the blade's (`weapon_aim` and the forearm, elbow and wrist drives under it), then two hands on a haft.
  Expected when both of a man's arms are on it: about 230 us of his 780, a fifth of a step.

**The first three pieces** (`extension/src/arm_drive.cpp`; `Greedy.arm_drive_ok`):
- `VoxelCore.arm_plain`: the bones of a shield's or an empty hand's arm and the hand's pull to its mark (the last branch of `_drive_arm` and its tail: `_elbow_dir`, `_limit_dir`, the elbow off the drawn trunk, four PD drives, `_twist_to`,
  `_orient_shield`, the pull). The script works the mark out as before and hands it over.
- `VoxelCore.arm_elbow`: the way a blade arm's elbow goes and its upper arm driven there (`_elbow_dir` with its drop, `_route_front`, the elbow off the drawn trunk, `pd_axis` with the load's scale and the elbow's own turn,
  `pd_twist`), where the arm is a plain blade's and the trunk's sculpt is there. The swing's reading and the elbow's set (`_hold_elbow`) between it and the next are still the script's.
- `VoxelCore.arm_blade`: a blade's arm from its forearm on, in the plain case (one hand on it, no thrust line, the fist firm, no throw): `_drive_forearm`, `_lock_elbow`, `_unjam_blade`, `_keep_blade_front`, the swing's cap,
  `_drive_wrist`, the pull, `_keep_weapon_out`. `_free_wedged`, which gives no push and reads nothing the others change, stays the script's and runs after.
- **To the bit**: `tests/test_native.gd` drives the same man from the same state through the script's branch and the core's, 1800 steps of a shield's, an empty hand's and a blade's arm (a fist on its way home, a blade long behind
  him among them), and every body's speeds and every field of his come out the same; `tools/replay_check.sh` prints the same fingerprints on every line that repeats.
- **What it is worth**, timed at the calls themselves (two clock reads a call) in the same fight of sixteen, three runs each: the arm's drive 112 -> 88 us a call (-21%), a man's `control` 499 -> 450 us (-10%), a step's
  controls 7.2 -> 6.5 ms, the step 14.0 -> 13.4 ms (-4%). `arm_plain` and `arm_blade` are all of it; `arm_elbow` by itself is worth about a microsecond (what it spares the script it pays back in its own arguments): only
  the large pieces pay, and it is kept for the one call the blade's arm is to become.
- **The marks overstated it**, and the plan with them: sections 10 and 18 read the drive at 177 us a call and the step's gain at a fifth; a mark is half a microsecond and more, and the drive is 112 us. The controls are 52%
  of a step here (7.2 of 14.0 ms). What is left in the 88 us: the mark's working out (about 35 us, both arms), `weapon_aim` (about 18, a blade's arm), the swing's reading, `_hold_elbow`, `_hand_off_trunk` and `_free_wedged`
  (about 12), and the natives' own work (about 20). With the mark and the aim there too and the blade's arm one call: about 50 us a call, a man's `control` about 375 us (-25%), 13% of a step here and about 15% in the
  release build, where the scripts are more of a step. Not the fifth this document promised.
- The Linux library is built in an Ubuntu 20.04 root (glibc 2.31, Steam's runtime: `tools/test_package.py` holds it to that); built on this machine's own system it asked for glibc 2.38.

**The mark in the core** (the next two pieces; the same file):
- `VoxelCore.arm_free`: a shield's or an empty hand's arm in a plain step, whole, in one call: the hand's mark worked out (the strength, the player's mark eased, `hand_target_local`, the hurt arm's sag, a bot's ringing head,
  `_clear_body`, the hand's lead toward the mark, its speed, the handling) and then `arm_plain`. A man down or getting up as well (his arm at a fallen man's mark), a fist with its button held while the elbow is still bent,
  and the guard hand carried round with the trunk by the other fist's punch. It answers false, having changed nothing, where the step is not a plain one (a punch asked for or on its way, a throw wound up, a frost on the
  arm, a hand caught behind the back, an elbow still set), and the script's own lines run as before.
- `VoxelCore.arm_mark`: the same working out for a blade's arm (the thrust's harder drive, the swung weapon out at the end of the arm, a short blade taken lower, a long one slower to its mark); `Fighter._drive_blade_plain`
  asks it and then runs the lines of `_drive_arm`'s weapon branch a plain step runs (`weapon_aim`, the elbow, the swing read, `_hold_elbow`, `_hand_off_trunk`, `arm_blade`, `_free_wedged`). A thrust along the blade's line,
  a bow, a throw, two hands on a haft and a reach are the script's as before.
- `arm_elbow` now keeps the elbow out of the trunk's box as well (`_elbow_clear` where there is no sculpt: a man without armour, or off his feet). Until then a blade's arm took the core's way only in armour: of the
  test's 1500 blade steps 166.
- **To the bit**: `tests/test_native.gd` now drives 3600 steps (a spear, a dagger and a bow added; a man down, a bot's ringing head, thrusts asked, a stroke a moment ago) through the script's lines and the core's, and
  compares every body's speeds, every field of his and the elbow's set; 1330 of the 1500 steps of a blade that is no bow are the core's own. `tools/replay_check.sh`: the same fingerprints on every line that repeats.
- **What it is worth**, timed at the calls in the same fight of sixteen (the least of five runs each way; two sittings, the machine a tenth slower in the second, so each pair is its own): with `arm_free`, a shield's or an
  empty hand's arm 59 -> 27 us a call and a man's `control` 495 -> 420 us (-15%); with `arm_mark` on top, a blade's arm 154 -> 120 us (-22%) and `control` 475 -> 444 us (-7%). Together a man's `control` is about a fifth
  cheaper than with the first three pieces alone, and a step's controls about 7.2 -> 5.7 ms.

**A blade's arm in one call** (`VoxelCore.arm_armed`; `arm_mark` as a call of its own is gone again):
- The mark, then `weapon_aim` whole (the pane's line, a spear couched on the line he looks along and trued to it, the blade kept from pointing back past the shoulders, `_route_front`, the sand under a low blow, the edge
  where the wheel set it, a bot's edge led by its stroke, the line held to the speed the weapon allows, the edge carried round with the blade), how fast the aim turns, the forearm's line, `arm_elbow`, the swing read and
  `_hold_elbow` (the hinge's two limits set by name: the joint's class is not among the ones the core is built with), `hand_off`, and `arm_blade`. What is left in `Fighter._drive_blade_plain` is the scalars handed over,
  `low_hand`, the off hand's place, the haft's memory and `_free_wedged`.
- **The engine's shortest arc is not the library's.** `Quaternion(from, to)` in the 4.7.2 engine makes the two lines unit ones, answers "no turn" only where their dot is over 1 - 4 * 2^-24, and makes the turn itself a unit
  one at the end; godot-cpp 4.4's leaves that last step out and answers "no turn" from 1 - 0.00001 on (two lines four thousandths of a radian apart). Read off the engine itself (`ad_arc` in `arm_drive.cpp`: 4400 pairs, every
  one to the bit). The unit test passed with the library's arc and the fights did not: a blade held all but still turns its line a thousandth of a radian a step, which the test's leaping marks never did. The test now
  holds a blade nearly still for a third of its steps (294 of them turn between 0.0007 and 0.004), and reads back the hinge's limits and `low_hand` as well.
- **To the bit**: `tests/test_native.gd` (3600 steps: a bot's leading edge, the wheel, a look, the input's power by turns; 1390 of the 1500 steps of a blade that is no bow the core's own) and `tools/replay_check.sh` (the
  same fingerprints on every line that repeats, with the library as it ships).
- **What it is worth**, eight runs each way in the same sitting: a blade's arm 125 -> 90 us a call (-27%; the least of each 110 -> 86), a man's `control` about 6% cheaper again. Since the first three pieces: a shield's or
  an empty hand's arm 59 -> 27 us, a blade's 154 -> 90 us, a man's `control` about a quarter cheaper (495 -> about 370 us at the first sitting's pace), a step's controls 7.2 -> about 5.4 ms of a 14 ms step: 13% of the step.
- **Left of the arms**: about 90 us a blade's arm and 27 a free one, a man's two arms 117 us of his 370: the natives' own work (the PD drives, the body queries), `_free_wedged`, and what handing sixty scalars over costs
  (about 8 us an arm). The rest of `control` is the legs' loop (about 85 us: the gait, the feet's plants, the kicks; ground rays from the script) and the stance and balance before it.

**The arm kept out of his body in the same call** (`VoxelCore.arm_keep`, the tail of `arm_free` and `arm_armed`):
- `control`'s loop over the arms does more than drive them: after each drive the arm is kept out of his own trunk and head (`_keep_arm_out`, which ends in `_keep_hand_front`) and its elbow kept low (`_keep_elbow_low`): three
  native calls an arm, each paid its twenty arguments and the script's memos and conditions before it. A profile of `control` one level in (the 8-man brawl, where 94% of the arms' steps are the core's own): the two
  drives 170 us a man, the two keepings 64, the legs' loop 89.
- The core's call now takes the time since the arm was last kept (`keep_dt`; under 0 where `control` rests a far man's arm this step) and does the three after its drive, under the script's own conditions (on his feet
  or getting up and not staggering, the trunk not flung, the arm not pinned, no beast's hold; alive and not limp for the elbow), and says so in `_arm_kept`; `control` keeps the arm itself only where the core has not.
  Nothing pushes those bodies between the drive and the keeping (the breath's sums read the pane; `_free_wedged` gives no push), so the order of every push on every body is as it was.
- **To the bit**: `tests/test_native.gd` does what the loop does (the drive, then the keeping unless the core has done it; staggering, limp, flung and getting up by turns; one step in five not kept): 1658 steps kept in
  the core; `tools/replay_check.sh`: the same fingerprints.
- **What it is worth**: a man's `control` 503 -> 454 us (the middle of five runs each way in a slow sitting): another 10%. Since the first three pieces a man's `control` is about a third cheaper, and the controls of a
  14 ms step about 2.3 ms less: a sixth of the step.

**Asked once a step, and the end of a leg's step** (after the arms):
- Three askings cut in the script, to the bit: whether a beast has hold of him (each man looked through every fighter for the beasts, every step: `Combat.beasts()` picks them out once a step), what his weapons touch
  (`_no_fling` and `_free_wedged` asked the same of the physics twice in one `control`), and what each leg can do (asked at every line of the legs' loop that read it). By a profile of the 8-man brawl: 8, 4 and 5 us a man.
- `VoxelCore.leg_tail`: the end of a leg's step (`Fighter._leg_end`: a planted foot held to its place, or a stepping foot kept no higher than its step; `motor_rel` for the thigh and the shin; the sole kept out of the
  sand) in one call. The ground asked under a foot that stands higher than its plant is a ray: the core hands that step back, the script asks the ray and calls again. The plants' own working out (where each foot goes,
  when it steps: a ray a foot every step, two more for a stepping one) is still the script's: the rays are a third of the legs' loop (34 of 89 us a man) and stay whoever asks them.
- The blade arm's script side trimmed where it was plain: `_free_wedged` leaves at once where nothing touches the blade (most steps), and `hold_q` / `grip_q` are not asked of a weapon already known to be no bow.
- The core says which arguments its calls take (`VoxelCore.drive_api`, `Greedy.DRIVE_API`): a library left from another build is not called with the wrong ones, the script's own lines run.
- **To the bit**: `tests/test_native.gd` (a new test: 900 leg steps through the script's lines and the core's; kicks, a man getting up, a weak leg, a foot on a heap) and `tools/replay_check.sh`.
- **What it is worth**: a man's `control` 533 -> 503 us (the middle of five runs each way; the machine a fifth slower than in the morning, so each pair is its own): about 6% for the four together.

**Where a man's step is now** (the same brawl, by `tools/profile_funcs.py` and clocks inside the core; a slow sitting, read the shares):
- A blade's arm: the core's own work 44 us (the mark 14, the swing read and the elbow's set 10, `arm_blade` 7, `weapon_aim` 5, the elbow 5, the keeping 3), the script round it about 80 (the scalars handed over 14, `_free_wedged` 8,
  `arm_func` 4, the trunk's sculpt and the arm's record 6, `_beast_has_me` 2, and sixty statements of a microsecond). A shield's or an empty hand's: 20 in the core, about 22 round it. What is left of the arms is the
  script's side of the call, not the call.
- Of the 10 us the elbow's set costs, most is the hinge's two limits written to the physics every step a swing is held: 69% of those writes are the two numbers that stood. Written only when they change, the fights
  come out otherwise from their first second (the physics makes the hinge anew at every write, and a hinge left alone keeps what it had worked out): it is not the same game, for under 1% of a step. Left as it is.
- The rest of the step (the endless fight of sixteen, the scripts' 15 ms of a slow sitting's 19): `control` 55%, the combat 20% (`process_contacts` 1.15 ms, `report` 1.3 ms for 71 bodies a step, `record_velocities` 0.2),
  the bots 7% (87 us a bot), the Match's own lines 7% (a round's check, the snapshot every third step, materials, items, throwables: none over 1%).
- **How well a part works, kept** (`VoxelPart.function`): 372 calls a step in that fight (a leg's `leg_func` 135 times, eight a man: `control` three times over, his bot's `wound`, `can_stand`; an arm's 38), each working
  the same answer out of the part's health, voxels, break and prosthetic. Kept now until one of those is written (each write says so through a setter; a frost thawing by the clock is asked afresh), and
  `tests/test_body.gd` holds the kept answer to the working out through every kind of write. `Combat.report` asks of a body whether anybody may ask who touched it, and whether it may land a blow, only at a touch that
  gets as far as needing to know (most have the sand under them and their own man's parts beside them). To the bit, both: the same fingerprints.
- **Measured by instructions**, since the machine's clock is too unsteady today for a few per cent (five runs each way of the same tree differ by a tenth): the fight is the same fight step for step, so
  `valgrind --tool=cachegrind --cache-sim=no` counts the same instructions whatever else the machine does; a second of the fight, less the first, is what a change is read against.
  The part's function kept and the report's two askings put off: 19.49 -> 18.47 million instructions a step of that fight, all of the step counted, the engine's own part too: -5.2%.
- **The frame's side**: a man's drawing is 263 us a frame (the brawl of eight in armour: 2.1 ms a frame, sixteen men 4.2): `_clip_shoulder_guards` 68, `_seat_drawing` 41, `_draw_joint_caps` 29, `_limbs_in_armor` 21,
  `_bend_drawing` 21, his parts' `_process` 24, the swing's trails 21. The shoulder guards are worked out again every frame an arm has moved on the trunk, which in a fight is every frame.

## 21. Counted in instructions: where a step goes, function by function and line by line

**The way.** A clock on a shared machine cannot tell five per cent (the same tree, five runs: a tenth apart), and what is left to cut is a per cent at a time. The fight is the same
fight step for step, so valgrind counts the same instructions for it whatever else runs: `tools/ir_profile/ir_profile.py` (its head says how) wraps script functions so that each runs
inside a native function of its own name (callgrind's inclusive count of it is the function's cost, with what it calls), or puts a mark before every statement of a function and
counts one statement at a time. A copy of the core built with the counting calls in it (never the game's library), a copy of the project, `tests/irfight.gd` (the diagnostic test's
eight in the endless arena). Instructions are not time (a call into the physics is few instructions and many cache misses), so the shares are read as shares of the scripts' work,
and a change is still checked for what it is worth by the whole step's count (`valgrind --tool=cachegrind --cache-sim=no`, a second of the fight less the first).

**The second second of that fight** (eight men closing in, before the first blow; 18.47 million instructions a step, the engine's part in it about 3):
- `Fighter.control`: 1.35 million a man, 10.8 a step: **six tenths of everything**. In it the two arms 467 thousand (35%), the legs' loop 222 (16%), and 664 in some ninety
  statements of its own: the ground under his feet 92, the bleeding of each part 83, the feet's plant 35, the body's mass 32, `keep_above_ground` 32, his breath 29, the head 19,
  the weapon kept off the sand 24, the ray under him 18, `_no_fling` 17, his burden asked twice 25, `can_stand` 21, the legs' function asked six times a step 51.
- An arm: a blade's 261 thousand, of which the core's own work 108 and the script round it 153 (the scalars handed over 47, the trunk's outline 15, the call's own
  twenty-eight arguments 20, `arm_func` 9, the weapon's check 10, `_free_wedged` 6.5, `is_spear` 4.5, the fifteen statements before the call 29); a shield's or an empty hand's 172,
  the core 67 of it. **The script round the call costs more than the call.**
- What a script statement costs: a line of the man's own numbers 65 to 200 instructions; a number read off another object 400; a call of a script function 2000 before it has
  done anything; a dictionary asked by a word 300 to 700. What is dear in `control` is not arithmetic: it is calls of small functions and readings of other objects, thousands a step.
- The rest of a step: the combat's keeping of every body's velocity 0.52 million, the weapons' own step 0.37 (23 thousand a weapon: the eight corners of its box, the lying
  check), a snapshot's rows 0.37 (1.1 million every third step), the bots 0.34 (43 thousand each), the round's check 0.28, the magnets' look over every weapon 0.28 (3.3 million
  every tenth of a second, in a fight with no magnet in it), each bot's list of allies 0.23, its nearest foe 0.18, the holds 0.26.

**Cut on these counts, to the bit** (the same fingerprints, `tools/replay_check.sh`; the tests named):
- The magnets' look: a weapon's count of its voxels of a stuff is kept until voxels come off it (`Weapon.material_count`; `tests/test_materials.gd`).
- Every body's velocity for the combat, and a snapshot's rows of the parts' places, each in one call of the core (`VoxelCore.record_vel`, `pack_parts`, `extension/src/bulk.cpp`;
  `tests/test_native.gd`: the same entries in the same order, the same bytes, for the bodies of a fight and for places made up: far off, scaled, mirrored).
- The arm's script side: the trunk's outline for an arm kept while his armour stays as it is (it was asked of three memos and an outline every arm every step;
  `tests/test_items.gd`), `arm_func` in its line where both parts are known to be on him, a blade's design read once.
- In `control`: a part that does not bleed is not written and its two blood functions are not called where they would come straight back; each part's share of the body's
  mass kept while the part's mass stays; a part well above the sand not handed to `_lift_out`; the lungs asked once for the breath that comes back and the most there can be.
- A weapon's lowest corner (asked of every weapon every step, and of the blade in his hand again in `control`): the one corner that takes the lower end along each of the box's
  axes, in place of the eight worked out one by one. The least of the eight to the bit, since a sum is never smaller for a larger term (`Weapon.box_low_y`; twenty thousand
  boxes placed every way, `tests/test_materials.gd`).
- **What it is worth**: counted function by function on the tree before and the tree after (the same wrappers on both): the scripts' work of a step (the Match's step,
  the combat's, the weapons') 15.07 -> 13.65 million instructions, **-9.4%**, which is about 7.7% of the whole step. `control` 11.02 -> 10.31 (an arm 219 -> 207 thousand, the
  rest from the bleeding, the mass, the lungs, `keep_above_ground`, the weapon off the sand); the magnets' look 0.278 -> 0.015; a snapshot 0.366 -> 0.206; the velocities
  0.511 -> 0.343; the weapons' own step 0.561 -> 0.453.
- **Two things the count taught.** (1) The core is no cheaper than the script at making lists: of the velocities' 0.343 the core's call is 0.211 (a list of two vectors
  put in a dictionary for each of 96 bodies is some 2200 instructions a body through the extension's interface). It pays where there is arithmetic, not where there are
  containers; a cheaper keeping of the velocities (two packed arrays) is left to do. (2) The whole program's count is not as steady as it was taken to be: for the first half
  of this batch it read -0.32 million a step where the functions' counts add up to -0.77 (the physics' worker threads wait in loops, and their waiting is counted). So the
  -5.2% given above for the part's function kept is good to two or three points either way; changes are read from the main thread's functions from here on.

**A fault of the last batch found by the suite's own diagnostic check, and put right** (f460914): the list of beasts the combat keeps since 66ca6f1 was picked out by whichever man
asked first in a step; with the men's controls on worker threads (the test's experiment, off in the game) several picked it out at once, and the engine reported the list let go
under a reader. It is picked out on the main thread before the threads start. With it right, that experiment reads -28% of a step in the quick check (it read -12% with the fault).

**A second pass over `control`'s small statements** (the counts of its blocks two and three levels in): a leg's thigh and shin read from the list `leg_func` keeps instead of
`by_name` asked by a name put together each time (17 places a step, 1600 instructions each); `Armory.burden`'s pace and breath by their own lines (the call made a dictionary of
both for the one wanted); the lungs' health in one function; the ground under a leg's neutral place asked with the space `control` already holds; the core read where it is kept
(`Greedy.nc`, held right by `core()` and by `use_native`'s setter) in the drives called thousands of times a step. The scripts' work of a step 13.65 -> 13.42 million (-1.7%;
`control` 10.31 -> 10.05). **Since f460914: 15.07 -> 13.42, -10.9%.** What a statement costs sets the floor now: a leg's ray for the ground 18 thousand (the engine's answer is a
dictionary), a drive called through its wrapper 7 thousand round 3 of work, a flag read off another class 1200. The cuts left in `control` are a quarter of a per cent each;
what is left to take is whole blocks moved to the core (the legs' 107 thousand a leg, the ground block's 92) or the men's controls on several threads (section 17).

**The frame's side, counted the same way** (`IR_DRAW=1`: the men drawn as with a screen, a frame a step): a man's drawing is **0.80 million instructions a frame**, the same order
as his control's 1.2 a step: `_clip_arm_armor` 255 thousand (the shoulder guards 135, the limbs in armour 63), `_seat_drawing` 193, `_draw_joint_caps` 179, `_bend_drawing` 98,
`_foot_drawing` 23, and his ten parts' own `_process` 17 thousand each. At 45 frames and 120 steps a second with sixteen men that is a fifth of all the scripts do in a second,
and none of it has been counted before (the measurements had no screen, and the drawing leaves at once without one).
- **The first cut on the frame's side**: a man drawn fine all over (the three builds and his head: nearly every man) has no joint caps, and `_draw_joint_caps` found that out
  for every part and its parent every frame, by `_fine_man` asked twice a part (152 of his 796 thousand a frame, to draw nothing). Asked once while each part's fine record is
  the very one it was (`_all_fine_men`: a record is made once and its build never written again; put aside for the voxel look, the caps are back the next frame, and
  `tests/test_seating.gd` and `test_smooth.gd` hold both ways). And `_seat_drawing` does not call on a parent for its broken piece's turn where nothing of it swings. A man's
  drawing **796 -> 625 thousand instructions a frame, -21.5%** (`_draw_joint_caps` 179 -> 19, `_seat_drawing` 193 -> 182). Left there, in order: the shoulder guards' two sides
  111, the knees' and elbows' bends 91, the grip's drawing 46, the limbs in armour 41, his parts' own `_process` 17 each.
- **The bends**: `_bend_drawing` made the list of his two knees and two elbows anew every frame (the knees' parts asked of `by_name` by a name put together) and called
  `_bend_set` twice a joint to say "no bend" to parts that had none. The list is made once, and with nothing bent on him those calls are not made. 98 -> 43 thousand a
  man a frame; his drawing **796 -> 569 thousand, -28.5%** with the caps.

## 22. The owner's third report: the room holds its speed and loses its frames as a wave comes in

The third `diagnose_report.txt` (the owner's computer: i5-14600KF, RTX 4070, the settings at their highest; the files somewhere between `dcfefbe` and `d0ca350`: the folder was out
of a zip and the report could not say, which `build_stamp.txt` now does). What it reads:

| the reading | editor | release |
|---|---|---|
| a step, eight men (no screen) | 5.82 ms | 4.56 |
| eight men and three foes | 9.90 | 8.57 |
| eight and eight | 14.91 | 12.63 |
| the C++ core's worth, eight men | -38% | |
| one fight on the screen (15 on the sand) | 29.7 fps at 69% of the speed | 26.7 fps at 86% (a step 7.24 ms) |
| the room of eight, each half minute | | 98-100% of the speed; 36, 57, 41, 58, 60 fps |

- **The room keeps the game's speed now** (98 to 100%, where the second report had 62%), and the yard sits at 60. What is lost is the picture, **as a wave comes in**: 15 to 17
  frames a second for about eight seconds of each wave (frames of 60 to 76 ms: seven or eight steps of 6 to 7.5 ms, the frame's own 9 to 16, the card 16 to 25 with seven friend
  windows drawing on it too). The arithmetic of section 19 says why: at 120 steps a second a step of 7.5 ms is 900 ms of every second, and the 100 left are thirteen frames of
  7.6; a step of 5.5 leaves 340, forty-five frames. Each half millisecond a step costs over its budget is ten frames a second.
- **The gate was right about the budget and late about the cost.** It let a step cost 5.5 ms, and all eight foes of the wave were let in while the step read 4.0: a foe costs
  little while he is built and walks to the fight, and `Net.step_ms` is a smoothed reading. It began to hold at "6.0 ms of the 4.6 it may, 14 men on the sand", five seconds
  too late, and the fight then cost 7.5 ms a step until enough had fallen.
- **The fix: near its budget the gate lets the foes in one at a time** (`Match.foe_gate_waits`). Where one more man would bring the step within a quarter of what it may cost
  (`GATE_NEAR` 0.75), the next foe waits until the last one let in has been on the sand four seconds (`GATE_SETTLE_S`): by then the step says what he costs, and the gate's own
  rule holds or lets go on a true reading. A host far from its budget is not touched; the first two foes of a wave come as before (`GATE_MIN_FOES`); nothing of it is asked in a
  game with no screen (the tests, the fingerprints: `bring_in` builds them at once). On this computer with eight players the eight alone cost 3.8 ms of the 5.5: the third foe
  on comes four seconds after the second, and the gate holds where three or four are fighting (5.4 to 6 ms a step in the report's own lines) instead of at six. The wave is
  still all of it; fewer of it at once, as the gate was asked to do (section 19). To be read in the next report: the room's second and fourth half minutes above 40 fps.
- **Not from the code**: a single step of 92.9 ms once in the 150 seconds (nothing compiled, 31 nodes built: one man's build ending in a step, or the system's own with eight
  games on it: not known); the first 3D frame's 1.8 s (173 pipelines: #329); the eight men's start, built behind the veil (frames of 143 to 231 ms that are not shown).
- **Nothing left lying on the sand costs the frame** (`WRECK`: +0.0 ms for the pieces, their shadows and the dead alike): what a long fight costs is its living men's steps.
- What decides the room now is the step with a fight on: 7.2 to 7.5 ms with thirteen to fifteen fighting, against the 5.5 a step may cost for 45 frames. The gate keeps the
  count to what the step affords; to afford more of them at once the step has to cost less (the legs' and the ground's blocks in the core, section 21; the men's controls on
  threads, section 17).

## 23. A standing leg's step in the core (`VoxelCore.leg_plant`)

The legs' loop of `control`, for the leg of a man who stands on the ground and is not kicking or getting up (nearly every leg of every step): where the foot stands or steps
to (its record in `feet`: the plant, the step's start and end, how far through it, the lift over what lies between), the two-bone aim that puts the sole there, and the leg's
end (`_leg_end`: the planted foot held, the thigh and the shin driven, the sole kept out of the sand). It was 73 thousand instructions a leg; it is one call.

- **What moved**: the branch became a function of its own, `Fighter._leg_plant` (the script's lines as they were: the script's path still runs them, for a man getting up, a
  foot with no record yet, and where the library is an older one), and `VoxelCore.leg_plant` does it and `_leg_end` after it. The foot's record stays the script's own
  dictionary, written key for key as the script writes it (others read it: the ground block, the balance, the drawing of the feet). The ground under a place is the script's
  own two rays, handed over (`_ray_all`, `_ray_sand`); what a ray meets that is a body is asked of the script (`_is_dead_ground`: a dead man lying still is ground, a live
  one is not), which is rare.
- **One thing was not the same at first**: of 600 states 46 left the thigh a last bit off. The shortest turn from one direction to another (`Quaternion(from, to)`) is
  another version's in the library's own copy of the engine's maths (godot-cpp's, a 4.4 one); the core now asks the running engine's constructor for it
  (`vc::eng_quat_arc`). After that 3000 of 3000.
- **Held to the script**: `tests/test_native.gd` (`test_native_leg_plant_matches_the_gdscript`): 1600 states of feet standing, stepping, set down, lifted, slipping, hopping,
  over the sand and over a man lying under them, dead and alive: the foot's record, the other foot's, the speeds of trunk, thigh and shin and the knees' give, to the bit.
  The fingerprints of the four fights: 0 lines of 39 differ.
- **What it is worth** (`tools/ir_profile`, the fight of eight, second 1): `control` 1 214 482 -> 1 148 630 instructions a man a step, **-5.4%** (9.80 -> 9.27 million a step
  for the eight); the call itself is 32.7 thousand a leg, 9.2 of them the leg's end, most of the rest the ray for the ground under the foot's place (the engine's, and its
  answer a dictionary). About 4% of what the scripts do in a step. The estimate of section 21 (the legs and the ground block together a tenth) was high for the legs: a
  third of a leg's cost was the ray and the leg's end, which were the engine's and the core's already.
- **The ground block the same way** (`VoxelCore.ground_ride` for `Fighter._ground_ride`: the block of `control` under "the ground found under the trunk"): whether he
  stands on it, the height his hips ride at (the planted leg's reach, a big man's stoop let down at a pace, the soles neither in the sand nor over it), the push on the trunk
  that holds his weight there, the knees' give under a landing. Three loops over the two feet in the script; in the core each foot's record is read once. It reads the
  feet's records and writes none; what it leaves (`stance_h`, `lowered`, `land_sag`, whether he is on the ground) comes back in one array. To the bit at the first try:
  `test_native_ground_ride_matches_the_gdscript`, 1600 states (standing, getting up, lying; feet planted, stepping, none; on a ledge, sunk in, both soles in the air; a
  big man stooping; over a man lying under his feet), and the fingerprints again 0 of 39. `control` 1 154 117 -> 1 109 287 instructions a man a step, **-3.9%**; the call
  itself is 4.8 thousand.
- **The two together**: `control` 1 214 482 -> 1 109 287, **-8.7%** (9.80 -> 8.95 million a step for the eight), about 6.5% of what the scripts do in a step: the "tenth"
  of section 21 at its lower end.
- **Left of the legs**: the kick's branch (rare), and the script's side of the two calls (some thirty numbers handed over for each: 6 to 7 thousand a call).

## 24. The fourth report, and the half of a fighting step that had not been counted

The owner's fourth `diagnose_report.txt` (the same computer; the files `86826be`, which the report now says). Against the third:

| the reading | third | fourth |
|---|---|---|
| one fight on the screen, release (up to 15 on the sand) | 26.7 fps at 86% of the speed, a step 7.24 ms | **44.1 fps at 98%, a step 5.8** |
| the room of eight, the half minutes with a wave in them | 36, 41 fps | 38, 35, 29 fps |
| the room's lows | 15 to 17 fps | 16 to 25 fps |
| the room's speed | 98 to 100% | 98 to 100% |

- **The fight alone is two thirds faster; the room on one computer is not.** The forecast of section 22 (40 to 50 frames as a wave comes in) was wrong. The gate holds
  at three or four foes now where it held at five or six, and it does not matter: **eight players fighting two or three foes cost 6.2 to 6.9 ms a step**, over the 5.5 a
  step may cost before a single foe more is asked about. The forecast took the eight to cost what they cost standing in the yard (3.6 to 3.8 ms); fighting, they cost
  about 5. At 6.5 ms a step thirty frames a second is all there is at the game's full speed, and thirty is what the room shows.
- **The gate cannot mend that**, only trade foes for frames, and with eight players alive there is nothing left to trade (two foes are let in whatever a step costs). Its
  rule for a step near its budget reads the step as it is when a wave comes in, the men standing: 3.9 ms with twelve on the sand, a fight of whom costs 6.9; and the
  budget moves with every reading of the frame's rest (4.2 to 6.2 in one wave), so a foe waiting his turn is let in at the next low reading.
- **A fighter in the room costs 0.58 ms a step, in the fight alone 0.45.** Most of that is the test's own: the seven friend windows on the same computer (the same fixed
  piece of work takes the game's thread 8.5 ms in the room and 7.1 alone, a fifth more). A host whose friends are on computers of their own is nearer the fight alone
  than the room of this test; that is an inference from these numbers, not a measurement.
- **A fighting step costs half as much again as a standing one, and none of that had been counted.** The yard: the scripts' 3.12 ms and the engine's 0.49 a step with
  eight men; a fight of eight and three: 4.75 and 1.26. Every count of `tools/ir_profile` so far was of the fight's second 1: the men closing in, before a blow, with no
  effects. Counted now in second 6 (sixteen on the sand, 33 blows landing in it, the effects made as in play: `IR_FX`), **45 million instructions a step**:

| | million a step | share |
|---|---|---|
| the men's `control` (sixteen) | 23.7 | 52% |
| the contacts: `Combat.report` out of every body's `_integrate_forces`, `process_contacts`, the blows | 11.4 | 25% |
| the bots' thinking (`Bot.update`) | 3.2 | 7% |
| each bot's nearest foe and its team's world (`nearest_enemy`, `_world_of`) | 2.6 | 6% |
| the rest of the match's step (the social rules, things thrown, the snapshot, the effects) | 4 | 9% |

  In second 3 (the same sixteen walking in, no blow yet) the contacts are 1.8 million: a fight is the contacts.
- **The first cuts there, each to the bit** (the fingerprints: 0 lines of 39):
  - a fighter's `alive` is a flag kept with his `state`, not a function asked of it at each of some hundreds of readings a step;
  - the step's roster (`Match._roster_begin`): for each team its possible foes and its own men, made once in the loop over the men, where every bot asked every
    entity's record for its team, kind and harmlessness every step (`nearest_enemy` 2.07 -> 1.32 million a step, `_world_of` 0.57 -> 0.12);
  - a touch is noted under the two ids, one table in another, not under a key spelt out of them, and only for the part somebody asks about; a blow's group likewise;
    the two questions asked of every touch of another man's part (a giant over him? a beast on him?) are asked in the lines themselves (`Combat.report` 3.36 -> 2.91).
  The fighting step **45.0 -> 43.0 million, -4.4%**.
- **What is left there, in order**: the contacts' records (a dictionary of six made for each, 140 a step, read once and thrown away), the checks of a part's blow on a
  part (`process_contacts`: 0.6 million), a blow that lands (`apply_hit`: 5 million instructions each, which is the step of 11 to 15 ms the game's own record shows),
  the bots (`wound`, `_react`, `_wrestle`). To be worth it the contacts want the core, as the arms and the legs did.
- **`tools/ir_profile` goes to a second deep in a fight** in a few minutes now (the counting is switched on at the second asked for), with the effects on (`IR_FX`),
  and `tests/irfight.gd` says what each second holds (`IR_SAY`).

## 25. The fighting step, statement by statement

The fight's second 6 again (section 24), each of `control`'s statements counted, then `_drive_arm`'s, then the small things every man does every step
(`tools/ir_profile` `lines`, 22.7 million instructions a step for the sixteen men's `control`):

| of `control`, a fighting step | million | |
|---|---|---|
| the two arms | 8.9 | of which 5.5 are the arms the core does NOT drive (below) |
| the two legs (`VoxelCore.leg_plant` and its handing over) | 2.6 | the core's own work is 1.5 |
| `_no_fling` (a weapon presses on him: his limbs held back) | 1.3 | three quarters of the men, in a melee |
| each part's bleeding | 1.2 | |
| the ground under him (`ground_ride`) | 0.9 | |
| the arms kept out of his body | 0.8 | |
| what his legs can do (`leg_func`), asked eight times a step by `control`, `can_stand`, `wound`, the bot's `_react` | 1.0 | |
| the mass his legs carry, the parts sunk in the sand, his weapons unburied, wrenched, reached for | 1.5 | |

- **What a statement costs.** A member of the object's own read or written: 30 to 150 instructions (the 67 numbers handed to the core for an arm are 7 thousand,
  not the cost that was feared). A member of ANOTHER object (`for p in parts: p.bleed`): 400 to 1200, and a method called on it 1500 and more. A type on the
  variable buys little: a fifth off the engine's own properties (`p.global_position`), nothing off a script's (`o.f.alive` through a typed `Fighter` came out 1%
  dearer, for the check the assignment makes, and was taken out again). What pays is the question asked from INSIDE the object, once (`bleed_step`: 1.7 thousand a
  part where the loop outside paid 9), and the answer kept. A dictionary made (`{"x": .., "y": ..}`, an input's default included, made whether it is used or not):
  2 to 4 thousand and five to ten trips to the allocator. The allocator is 6 of the 68 million instructions a fighting step costs
  the whole process (the scripts' calls are 43 of the 68, the script machine's own loop 18 of those).
- **The cuts of this round, each to the bit** (the fingerprints: 0 lines of 39):
  - `VoxelPart.bleed_step`: a part's step of bleeding in the part's own lines, where the man's loop asked each of ten parts six things from outside;
  - `Fighter.leg_func` keeps each leg's answer while none of his parts has changed in what it can do (`fn_ver`, counted up by every part as it counts its own
    `_fn_ver`) and his spine and pelvis are as they were; never while a frost thaws on the leg, which goes by the clock;
  - the mass his legs carry and the limbs `_no_fling` holds back are kept while no part is cut off (`body_ver`, counted by `VoxelPart.severed` and `nominal_mass`);
  - a contact that may be a blow is a list of six, not a table of six names (`Combat.pending`: 140 made a step, read once and thrown away);
  - the parts sunk in the sand are looked for through a typed variable (a sixth off that loop, no more).
  The fighting step **43.0 -> 40.4 million, -6.0%** (`control` -6.8%, `Combat.report` -13%, a weapon's contacts -29%, `Bot.update` -10%); with section 24, **-10.1%**
  of what a fighting step cost this morning. The whole process: 68.0 -> 65.4 million a step.
- **The arms the core does not drive are the dearest thing left.** In second 6, of the 17.7 arms with a weapon a step: 12.4 are driven whole in the core
  (`arm_armed`, about 165 thousand instructions each with the handing over), and 5.3 fall to the script's own lines at about 600 thousand each: **a thrust along
  the blade's line** (2.3 a step: `arm_mark_core` sends back every arm whose thrust is over a half), **both hands on a haft** (a two-hander's two arms, every step),
  an archer's arms, a shove, a man crawling. A man with a two-handed weapon costs four times a man with sword and shield in his arms; a spearman thrusting, three
  times. After it, small: a weapon's box by the shape touched is kept while its shapes are what they were (`Weapon.box_for_shape`, four questions of the engine
  sixty times a step), the ids of a blow's pair asked of typed objects: `process_contacts` -3.6%, the step 40.45 -> 40.27.
  **Next: the thrust's line and the two-handed drive in the core** (`_thrust_ext`, `_hold_thrust_line`, `_drive_haft`, the guard hand's place), about 4 of
  the 40 million; then the contacts.

## 26. The thrust along the blade's line, in the core

Section 25's dearest thing, its first part. `VoxelCore.arm_mark_core` sent every blade arm with its thrust over a half back to the script (2.3 arms a step in the
fight's second 6, each some 600 thousand instructions against the core's 165). The line is the core's now (`arm_armed`, drive API 5):

- **the mark**: the line the blade lies on when the button goes down, kept where it lies in the arena (`thrust_line`: the same record under the same names, read by
  `control`'s lunge as before), laid on the crosshair while a stab of the key is drawn back or while the player's mouse has not yet driven it in
  (`_line_to_mark`), how far along it the hand is (`_thrust_ext`: drawn back, driven out past the arm's end, or as deep as the mouse has pushed it), the lean of the
  body into a level stab handed back to the script (`thrust_lean`), the hand's pace along it (three times a stroke's speed, six times its push);
- **the aim**: the blade asked onto the line as far past it as it sags off (`thrust_aim`); a couched spear learns nothing of its line while it thrusts
  (`_spear_trued`: the one place the first build parted from the script, found by the replay's fingerprints, 20 lines of 39, and not by the test of single steps,
  whose only spear was held in both hands; the test has a spear and shield now, and fails on that build);
- **the drive**: the forearm and the wrist lock the blade on the line (`_drive_forearm` 1.8 times as stiff, no easing onto the forearm's own line), the hand's drift
  off the line and the blade's turn off it braked (`_hold_thrust_line`), the swing's cap 45, the hand's pull 2.5 times as hard and half as much again at most; the
  hand's goal not moved out of the drawn trunk.

Held to the script's lines by `test_native_arm_drive_matches_the_gdscript` (4200 steps to the bit; more than 200 of them with a line: a stab of the key, the mouse
driving it in depth, with a crosshair and without, the line's clock sent on past the drive and the lunge; a frost thawing on the forearm among the steps handed
back) and by the fingerprints (0 lines of 39). `_drive_arm` -9.2%, **the fighting step 40.27 -> 39.27 million, -2.5%**; since the fourth report 45.0 -> 39.3, **-12.7%**.

Left of the arms the core does not drive: both hands on a haft (the guard hand's place and the front hand's, `_drive_haft`), an archer's, a shove's, a crawling man's.

## 27. Where the blows, the blood and the dead make a fight dearer (the fifth report, #345)

The fifth report's word, and the owner's: the drops begin when weapons swing, limbs are cut and blood flows. Counted in instructions (`tools/ir_profile`, the endless fight of
eight men and their foes with the effects on, `IR_FX=1`, the second 28: eight alive, two of them foes, seven blows in the second, 13 parts bleeding, an arrow flying, 160 lumps on the sand and two gut ropes)
what a step and a frame do, function by function (million instructions, the scripts' own, inclusive of what a function calls):

| the step | before | after | |
|---|---|---|---|
| `VoxelPart._integrate_forces` (the contacts of 95 bodies; 57 of them reach `Combat.report`) | 4.49 | 3.59 | `report` 3.90 -> 3.01 |
| `Combat._physics_process` | 3.05 | 2.44 | `process_contacts` 2.49 -> 1.95, `record_velocities` 0.48 -> 0.41 |
| the gut ropes (two) | 1.17 | 0.81 | |
| `Items.update` (an arrow in the air) | 1.04 | 0.42 | |
| `Weapon._physics_process` (27 weapons) | 0.56 | 0.43 | |
| `Match._physics_process` (the men's `control`, 12.1 of it, and the rest of the step) | 18.02 | 17.21 | the arrow and the bow, 0.9 |
| **the step's callbacks together** | **28.1** | **25.3** | **-2.8, -10.0%** |

| a frame | before | after | |
|---|---|---|---|
| `Fx._process` (every blood stain, faded each frame) | 1.11 | 0.06 | |
| `Fighter._clip_arm_armor` (ten men) | 3.57 | 2.53 | the arm's plates 1.6 -> 0.5 |
| `Fighter._process` | 8.56 | 7.53 | |

At the owner's 51 frames a second a step is worth 2.35 times a frame's instruction: -2.8 a step and -2.1 a frame are 8.7 million of about 79 a frame, **-11% of the scripts' work**.
All of it to the bit: the fingerprints (0 lines of 39), the equivalence tests below, the whole suite.

**What each cut is.**

- **The contacts.** `Combat.report` (a body's contacts, 57 a step at 68 thousand each) reads each thing once: the owner's and the other's members hoisted out of the loop, `bf is Fighter`
  asked once, the sum of a body's damage (`b_sev`) and whether it is dead (`b_dead`) only where a blow is possible, and what of `_may_strike` does not change as a man is hurt (a striking
  part, a jaw, a point, a tusk) told of a part once (`VoxelPart.strike_ok`, let go again where a beast is given a bite: `Beast`). The notes a contact leaves (`Combat._note`) are arrays of five,
  not dictionaries (`touch_notes()` makes the dictionaries the callers want). `process_contacts` has one branch for the regular blow (`a_man`/`b_man`, a club or a severed piece asked once, the
  skin shapes looked at before `host_part`). **The velocities** (`VoxelCore.record_vel_all`): the core is given the fighters and the loose weapons and goes over their parts, weapons and chain heads in
  the order the script did (the same entries in the same order: `tests/test_native.gd`, three ways), a man or a weapon freed in the list skipped as `is_instance_valid` skipped it.
- **The gut ropes.** A link's `_keep_out` asks `voxels_within` for the voxels of his trunk near it, and the core's `within` went over every voxel of the trunk (3 500; 79 thousand
  instructions a call, five and a half calls a step). `VoxelCore.within_cells` looks at the cells of the part's grid round the point only (two more all round than the sphere needs, the same test
  made of each voxel found, sorted by index, cut at the limit): 12.6 thousand a call. `VoxelPart.voxels_within` uses it where each voxel has a cell of its own (`_cells_single`).
- **Blood.** A stain's fade (a decal of blood drying to brown) every frame, for every stain, was 1.05 million a frame with the fight going: it is worked out every quarter of a second now
  (`Fx._dry_t`; a new stain is red at once), and a drip's emitter, a spurt, are asked to emit or to stop only when that changed (`d["em"]`, `d["ar"]`, `s["on"]`: an engine property's
  setter is 2 thousand instructions, the same value again as much).
- **Things lying about.** A weapon that nobody holds and that sleeps asked the floor and its own lie each step; it does not (`Weapon._out_of_the_floor`, `_lie`).
- **The arm's armour in the frame.** `_clip_arm_armor` asked the outline of the chest of each of the few plates in or near its box (13 thousand instructions a plate) in script: the core names
  the plates whose clip is to change (`VoxelCore.clip_plates_flip`: `FineArmor.in_outline` in C++, to the bit), the script flips those.
- **Arrows and bows.** An arrow in the air asks every part of every man near it, at a point every eight centimetres of its flight, how far it is from the part's box and from its skin
  (`Social.box_distance`): the skin is some thirty boxes in script, 72 thousand instructions a part (a flying arrow was 0.9 million a step). The skin is looked at only where the point is
  within the arrow's reach of the box that holds all its shapes (`VoxelPart.skin_box`, kept while `skin_set` does not change the shapes; a tenth of a millimetre of margin for the floats):
  `Social.box_reaches`, the answers of `Items.hit_char` to the line. And a bowman's bow asked the heights of all its hundred voxels twice every step (`_draw_bow`, `_show_draw`, 0.5 million a step for
  the archers of the fight): they are kept on the bow (`Weapon.bow_geo`, `Throwables._bow_geo`; a weapon's design is its own copy and is not changed).

**Held by**: `test_native_within_cells_matches_the_full_search` (about a thousand searches a run on a man's parts and a lion's, whole, cut about and scaled, the radius on a voxel's distance and a hair either side, no number at all,
every limit), `test_native_clip_plates_flip_matches_the_script` (160 sets of plates against random outlines, the box's faces and corners), `test_native_bulk_matches_the_gdscript` (the velocities three ways: script,
the bodies in one call, the lists in the core), `test_an_arrows_questions_of_a_part_are_what_the_distance_to_the_box_and_the_skin_said` (400 points a part in and round the skin of a man, six radii; `Items.hit_char` and the old one), `test_the_box_that_holds_a_parts_skin_follows_its_shapes`, `test_a_bows_drawing_asks_the_same_of_its_design_as_the_lines_over_every_voxel_did`, the fingerprints
(0 lines of 39) and the suite.

**What was found and is left** (all of it exact; the cost is where it is at the second 28, a step or a frame):

- *the step*: the men's `control` 12.2 (the arms 4.7, 19 calls: the two-handed arms, an archer's, a shove's and a crawler's are the dear ones, about 3.2 of it; the rest 7.4: `_no_fling`,
  bleeding, the legs, the ground, the glue of the core's calls), the contacts 3.6 (57 reports at 52 thousand: each contact's reads of the engine's state) and `process_contacts` 2.0, `Bot.update`
  1.5 (155 thousand a man), the gut ropes 0.8 (two at 400 thousand: the engine's contacts of every link), 161 sleeping chunks 0.6 (the call itself, 3.8 thousand each), `nearest_enemy` 0.45,
  a hit (`apply_hit` 4.7 million a hit; an arrow's splat event 20 million: the dearest single thing of a step);
- *the frame*: `_seat_drawing` 3.6 (the parts' loop 1.2, `_off_clear_drawing` 1.5 for a two-hander, the guard arm's turn 0.5, the grip 0.3), the shoulder guards 1.45 and the limbs in armour 0.5, `Match._process` 1.5,
  the parts' own `_process` 1.0 (101 calls: the engine's property sets), the weapons' 0.9, `_bend_drawing` 0.4.
  Each is one to two per cent of a step's work once the frame's weight is taken: a port of the two-handed arm drive (the one that is largest) is the next piece.

## 28. The sixth and seventh reports: the games with no window were throttled; what the room says now

The sixth report (`a7c6925a`) found the fixed piece of script work taking 130 ms against the test's own machine's 66 (0.51 times as fast) in the parts with no window, and 58 in the parts with one. The guess of
section 15 (Windows gives a process with no window the efficiency cores at a low clock, EcoQoS) was answered by the game itself: the native extension now asks Windows not to throttle the process
(`keep_the_game_fast`, Windows only, `SetProcessInformation` with the power-throttling state; a `--friend` window, which should take little of the host's cores, is left as Windows has it; `1e899fe`). The seventh report:

| | sixth (`a7c6925a`) | seventh (`1e899fe`) |
|---|---|---|
| the fixed piece of script work, no window | 130 ms (0.51 times) | 59 ms (1.12 times) |
| a step, no window: 4 men / 8 / 8 + 3 foes / 8 + 8 foes | 2.95 / 5.02 / 9.05 / 13.67 ms | 1.58 / 2.53 / 4.62 / 7.78 ms (-43 to -50%) |
| the same fixed piece in the games with a window, in play (fight, release fight, room) | 8.3 / 7.7 / 8.4 ms | 7.4 / 7.2 / 8.6 ms (the same) |
| the fight in a window, debug build | 39.4 ms a frame, 85% speed | 22.5 ms, 98% |
| the room, release build (8 players, 7 friend windows), speed and frames a second in each half minute | 97-100%; 38, 53, 60, 57, 36 | 100%; 42, 60, 46, 42, 59 |

So the game as played was never throttled (a process with a window was not); the figures of the parts with no window (the steps, the release steps, the threads, the native core's share) were up to twice too dear in
the first six reports, and only their ratios stand. The first measure of the men's controls on the threads (-13, -8, +3%, the second report) was taken in those parts, where the worker threads were throttled too: **to be taken again**
(`tools/diagnose_decide.bat`: the step, the fight and the room with the threads, and the fight with the render thread, each beside the same without, 16 minutes).

**What the room says now.** The speed is 100% all through (the valve of section 12 never closes: the steps cost 6.8 ms at most, its line is 8.6). The frames are 60 when few are on the sand and 22-35 in the stretches
where the foes come in (a step 5.4-6.8 ms, the frame's rest 8.6-8.9 ms, 14 men and more on the sand); 76 frames of the first half minute and 120 of the 150 seconds were over 50 ms, in clusters (a dozen frames of
55-90 ms, six to nine steps each, within three or four seconds). That is the room's catch-up (`Net.ROOM_STEPS_MAX` 12 within `PHYSICS_BUDGET_MS` 50, kept so that a host that falls behind does not slow every guest's world): a late frame
asks for the steps it missed, which makes the next frame late too, and it dies away slowly (a single 45 ms bump with a step of 5.5 ms and a rest of 7: frames of 63, 51, 40 and 34 ms with the cap at 12; one of 63 ms
and 33 ms of the game's time let go with the cap at 4). With the frame c steps long and the speed 1000 c / (120 (c s + r)), in a heavy moment of the report (s 6.6 ms, r 8.9 ms, 100.4 s):

| steps a frame at most | frames a second | speed of the game |
|---|---|---|
| 12 (now; the frame settles at r / (1 - 120 s)) | 23 (the record at that second: 19) | 100% |
| 4 | 28 | 94% |
| 3 | 35 | 87% |
| 2 | 45 | 75% |

That is the valve's policy (#328) as the room puts it now: not the owner's choice between slow motion and a slide show only above 8.6 ms a step, but between the chains of long frames in every heavy moment and a
little slow motion in them. A steady frame shorter than the cap's frames is not touched by any of it.

## 29. The arms of a man with both hands on the weapon, in the core (#344)

A man who holds a weapon in both hands (a zweihander, a warhammer, a longsword with the off hand empty, a trident, a falx, a spear) drives two arms through a path of their own, and it was the dearest piece of
the men's `control` that the core did not do (section 27: the guard hand's drive 190-210 microseconds a call in script, the hand on the haft below it 13 microseconds). Both are in the core now, to the bit:

- **The hand on the haft below the guard hand** (`VoxelCore.arm_off_two`, from `Fighter._drive_arm` where the script's `if side == two_off() and two_handed ...` block began): the giant's branch, the elbow's routing with the
  preferences, `ad_elbow_dir`, `ad_twist_to`, the weight's impulses and the pull of the front hand. It answers nothing and changes nothing but the bodies' velocities; a hand whose joint is gone (a weapon dropped, a cut)
  is the script's, as it was.
- **The guard hand** is a mode of `arm_armed` (`kk[73] != 0`: the parameters 73 to 97 of `_arm_f` and the other arm's two bodies in `_arm_refs[35..36]`; the answer is ten numbers long and carries what the script wrote to
  `two_main`, `two_gap`, `two_front`, `haft_i`, `haft_lp` and `haft_raw`): the strength and the mark's shape of both hands (`arm_mark_core`'s `two` flag), the front hand's place (the block of the thrust's line and of the
  weapon's own line), the elbow's variants (0.06 and 5 in place of 0.18 and 12, a guard's bend of 0.9 and a stroke's of 1.6, a stroke's hold of 6 in place of 0.2) and the drive of the haft (`arm_blade_impl`: the haft's own torque on the weapon, the
  trunk and both upper arms, its constants 12, 6 and 70). The steps that are not plain ones (a jab, a throw, a frost on the forearm, a hand that is not there) are handed back to the script untouched, as for any blade.

`Greedy.two_ok` says the loaded core has them (it has `arm_off_two`, which an older core has not): with an older core the two-handed arms are the script's, as they were, to the bit, and the drive API stays 5.

**What the script did that the first port left out.** A two-handed thrust differed from the script's in one step of about 6600 by a unit in the last place of one velocity: in its front-hand block the script lays the
thrust's line into the body's frame a second time (`_line_in_body(tl2)`), and the line that `_hold_thrust_line` is handed afterwards is that second one, not the first; the core takes the line it computed the second time
(`m.line_o`, `m.line_dir`). Found by bisecting the one step (switches in the test for the number of steps, the arm kept out, the quaternion arithmetic, and a trace of the front block against the script's).

**Measured.** A melee of twelve men on the sand (zweihander, spear, warhammer, longsword, trident, falx, twice over, in two teams; `Greedy.two_ok` on or off, the same fight to the bit), the time of a step after the first
second, 1000 steps, seven pairs run one after the other: the core 9.26-9.90 ms, the script 10.09-12.64 ms, the core faster in every pair by 4-22% (median 12.7%; the best of each, 8%). In a call (the test's own mix of steps,
with the steps the core hands back and the arm's keeping out in it): the guard hand 314 -> 160 microseconds, the hand below it 109 -> 81. A room with a mix of weapons has fewer such men (an estimate from the profile of section 27: about 4% of a step
with a third of the men two-handed, the 8-12% above only in a crowd of them).

**Held by**: `test_native_arm_drive_matches_the_gdscript` (11 loadouts now: the four two-handed ones with an armoured longsword among them, 6600 steps; every body's velocity bit for bit, the fields, the elbow's set and limits;
the other hand's joint gone for a step by turns; and a third pass for the two-handed men with `two_ok` off, which has to leave what the script leaves with the one-handed arms still the core's), a longer run of 12,500
steps by hand (0 differences), the replay fingerprints of four runs (16 men and 6 men with gladius, axe, mace and spear; two mixes of 24 with the game's bows, zweihanders, flails, trident, hammers, giants and creatures; 0 of 40 lines differ from the figures before the port) and the suite.

**The Linux binary.** The container this was built in has GCC 13 and glibc 2.39: a Linux library built here asks for `GLIBC_2.38`, where the committed one (GCC 9.3) asks for 2.29 or less and runs on the Steam
Deck and the older distributions. So only the Windows library is rebuilt (mingw, statically linked, no new dependency) and committed; the committed Linux library is the old one, which has no `arm_off_two`: there `two_ok` is false and
the two-handed arms run in the script, the same fight to the bit. **To do on a machine with an older toolchain**: `cd extension && scons platform=linux target=template_release arch=x86_64 -j4`, then run
`--test test_native` there (the test reports the third pass's count) and commit `native/bin/libvoxelcore.linux.template_release.x86_64.so`.

**Left** (all exact): an archer's arms, a shove's, a crawler's (about 1 million a fighting step together), the two legs' calls' glue, the kick.

## 30. Where a frame's script work goes (the men's drawing), measured

The owner's reports put the men's `_process` at 4.2 ms of a frame's 8.6-8.9 ms rest (section 28), so it is as large a piece of a frame as the step is of the physics. Measured on this machine, with the
timing marks of a scratch copy (`Fighter._process_frame` cut in sections; thirteen men in armour in a melee, six of them with both hands on a weapon, a frame a step, no window): the frame is 12.5 ms, the
men's drawing 3.1 ms of it. In microseconds a frame for the thirteen (a man's share in brackets):

| piece | us a frame | per man |
|---|---|---|
| `_clip_shoulder_guards` (of `_clip_arm_armor`, 1330 in all) | 860 | 65 |
| &nbsp;&nbsp;`guard_hidden`: `guard_reach` (C++) 17 us a call, `guard_cut_near` (C++) 27 us a call, the script round them 4 | 520-560 | 47 a call |
| &nbsp;&nbsp;the turn loop (`bytes_changed`, the voxels' places, `count`), `_arm_reach`, the sides' heads, the pieces' checks | 130, 85, 75, 95 | |
| `_limbs_in_armor` (the cones of both arms into the trunk's shells: 4 shader parameters a shell) | 271 | 22 |
| the arms' plate loop of `_clip_arm_armor` | 198 | 16 |
| `_off_clear_drawing` (only the six two-handed men: 68 us each) | 450 | 36 |
| `_swivel_drawing` | 230 | 18 |
| `_seat_drawing`'s parts loop, the weapons' | 200, 59 | 15, 5 |
| `_grip_drawing` | 155 | 12 |
| `_bend_drawing`, `_foot_drawing`, `_draw_joint_caps` | 140, 90, 77 | 11, 7, 6 |
| the parts' own `_draw_at` (130 parts, 2.0 us each: the engine's property sets of the part, its skin and what is drawn with it) | 260 | 20 |

A call of `get_global_transform_interpolated()` is 57 nanoseconds (a plain `global_transform` read 187, `global_position` 52): the transforms the functions ask for again and again are not what costs, the script
round them is (array and closure allocations in `_off_clear_drawing`'s `depth`, three `Geometry3D.get_closest_points_between_segments` calls for each of its up to eleven turns).

**What it would take** (all exact; drawing only, so the replay fingerprints stay as they are and each port is held by a test that sets the script's answer beside the core's on random placings):
`_off_clear_drawing`'s search as one call (the engine's closest points of two segments reproduced in float32 and held against the engine's own), `_swivel_drawing` the same, `guard_reach`'s `atan2` (probably the dear thing in
it, one for each voxel within the armour's reach: the sector it lies in could be told by cross products, `atan2` kept for the voxels near a sector's edge), the pieces' checks of `_clip_shoulder_guards` memoed on the armour piece, and the cones' shader
parameters sent only when they change. Together about 1 ms of the 3.1, a tenth of this frame; none of it is the physics.
