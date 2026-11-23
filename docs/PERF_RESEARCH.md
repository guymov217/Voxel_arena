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
| Pieces of voxels (`Chunk`) and loose weapons (`Combat._rest_weapons`) that have lain still for 1.5 s are put to sleep, as the dead's parts are (`Match._at_rest`) | **made, not to the bit** | the late Endless probe: the step -25 to -33%, the dead's parts awake 97 -> 22-41 |

How the sleeping goes: the physics wakes what is touched or pushed; what sleeps looks under itself every 0.5 s (what it lay on carried off, it falls); a weapon taken up is made sleepless
(`Fighter.pick_up`); a weapon in a hand is its man's and is left to him (the yard puts it to sleep with him and wakes it with him, `Match._stands_idle`: `tests/test_yard_rest.gd` is what
holds that). Gameplay is unchanged, but a body that sleeps is not stepped, so the fingerprints of a fight with pieces or weapons lying about differ from the old ones; the same run twice
still gives the same fingerprints (25 s, `REPLAY_BARE=1 REPLAY_KILL=2 REPLAY_SECS=25`; the armoured runs of `replay_check.sh` are not alike after 7-10 s whatever the build, their
staged builds being paced by the clock). To undo it: the REST block in `chunk.gd`, the sleep check at the top of `Weapon._physics_process`, `Combat._rest_weapons` and its call, and
the `can_sleep = false` line in `Fighter.pick_up` (`tests/test_rest_sleep.gd` goes with them).

What is left of the step is the arms' drive, about a quarter of it: only the port to C++ keeps every fight. What changes fights (the physics rate, Jolt's iterations, the governor of #304,
freezing the dead for good: about 7% more than the sleeping) waits for a decision.
