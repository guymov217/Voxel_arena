# Performance research (#298k, #298l): where a fight's time goes and what each way of sparing it is worth

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

**In the step:** the armour adds 153 us to `control` (819 against 666), 110 of it in `_drive_arm`: the arms are kept out of the trunk as it is DRAWN (its fine outline, `sculpt`) when
there is armour on him, and out of its box when he is bare. `_clear_body` +36, `_elbow_clear` +16, `_keep_arm_out` +20, `_hand_off_trunk`/`_elbow_off_trunk` and the rest +38. Of the 153,
64 us are the memo and gating calls that only an armoured man makes (`_outline_m` 18, `_armored_m` 18, `_plate_band_now` 8, `_trunk_sculpt` +7, `_trunk_sculpt_worn` +6, `_armored` +8: 33
calls of 1-3 us each); the geometry itself, already in the C++ core, is the smaller part. A persistent per-man record of the armour state (built when his armour changes, `_armor_dirty`,
not worked out afresh each step) in place of those calls would take about 55-65 us a man and step off (6-8% of an armoured step, to the bit); the native functions taking that record
in place of the dictionaries would add 10.

**Building:** a first armoured man costs 750 ms of scripts, the next 364 (the shell layouts are cached): the hitch when a wave of armoured foes is brought in. Staged over the frames
(#182) it is spread, not removed.

What it would take to bring an armoured man to a bare man's price, in order of what it buys: the step's armour record (above, to the bit, 55-65 us a man and step), the frame's clip
pass in the C++ core (60-100 us a man and frame, drawing only), fewer cube instances in the shell (the largest part of the card's extra, a change of how the armour is drawn), and the
shell's multimeshes merged where nothing of them is knocked off.

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
| A load governor (shedding far men's work under overload) | changes far men's physics: not to the bit, outside this document's rule | #304 |

## 5. The model

`tools/loopsim.py`: see its header for the checks (it is within 10-15% of real-time runs on one core, nearer on the steps). Frames a second / game speed, all fighting, in armour:

| 8 fighters | weak laptop (0.8) | average (1.15) | good mid (1.5) | 13600KF (2.0) |
|---|---|---|---|---|
| no armour at all | 43 / 71% | 55 / 100% | 60 / 100% | 60 / 100% |
| as it is, in armour | 33 / 55% | 28 / 93% | 57 / 100% | 60 / 100% |
| armour fixes (step -6%, frame -0.7 ms) | 36 / 60% | 32 / 98% | 59 / 100% | 60 / 100% |
| + the ports left (-8% more) | 38 / 63% | 42 / 100% | 60 / 100% | 60 / 100% |
| all of `control` in C++ (-40%) + armour frame fix | 31 / 98% | 60 / 100% | 60 / 100% | 60 / 100% |
| the fighters in a process of their own | 60 / 77% | 60 / 100% | 60 / 100% | 60 / 100% |
| own process + all of `control` in C++ | 60 / 100% | 60 / 100% | 60 / 100% | 60 / 100% |

(6 and 12 fighters: `python3 tools/loopsim.py`.) The price of armour is the first two rows: on an average computer eight armoured fighters sit at 28-40 frames where eight bare ones
hold 55. The armour fixes of section 3 close a part of that; what is left of it is the step itself, and only the whole of `control` in C++ or the process of its own gets an average
computer to 60 with eight armoured men.

## 6. What to do, in order

1. The armour's frame clip pass and the step's armour record (section 3): the cheapest cuts that are not a rewrite, aimed at the thing the player sees (armoured fights); to the bit
   for the step, drawing only for the frame.
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
```
