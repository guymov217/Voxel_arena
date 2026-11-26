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
