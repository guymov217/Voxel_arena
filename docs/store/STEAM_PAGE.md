# WRECKSMITH: the Steam page kit

Copy-ready text for the store page (Steamworks → *Store presence → Edit store page*), the
tags, the art sizes and the trailer plan. The screenshots and capsules are made from the game
itself: `docs/store/screenshots/` and `docs/store/capsules/` (how to remake them at the end).

---

## Name

**WRECKSMITH**

## Short description (300 characters at most; this is 252)

> Forge a weapon voxel by voxel, then swing it with your own two hands. A physics gladiator game
> where every blow is real: blades bite, bones crack, limbs come off. Fight men, beasts and
> monsters, alone or with up to 8 friends, and earn the crowd's roar.

## About this game (Steamworks BBCode)

```
[h2]Build it. Swing it. Wreck everything.[/h2]
WRECKSMITH is a physics gladiator game. There are no canned attacks: your mouse is your arm. Swing hard and the blade bites deep; swing lazily and it glances off. Every fighter, beast and monster is made of voxels, and every voxel can be cut, crushed or torn away.

[h2]The forge[/h2]
[list]
[*]Build any weapon voxel by voxel: swords, axes, hammers, a two-person sword, a goose.
[*]Each material has its own weight, edge and strength. The centre of mass and the grip are yours to set.
[*]Set gems in the blade: ruby burns, sapphire freezes, emerald poisons.
[*]Weapons dull, chip and finally break where you used them most. Mend them, or forge a better one.
[/list]

[h2]Every blow is physical[/h2]
[list]
[*]Cuts, thrusts and blunt blows each wound in their own way, voxel by voxel.
[*]Limbs hang, swing and come off. Pick one up and hit someone with it.
[*]Organs, bones and blood under the skin: a crushed rib, a punctured lung, an artery that will not stop.
[*]Wrestle: grab, shove, trip. Run out of breath and every swing gets weaker.
[/list]

[h2]Men, beasts and monsters[/h2]
Lions, bears, crocodiles that drag you into a death roll, elephants that charge and stomp, a gorilla that tears men in two. Then the myths: the Cyclops, the Minotaur, Cerberus, the Hydra, the Titan and a dragon. 25 creatures, each with attacks you can see coming and must answer with steel.

[h2]The campaign[/h2]
Climb 64 stages, from a drunk in the sand to the Hydra, with 9 bosses on the way. Spend your purse at the smith, the armourer and the physician. Wounds stay with you, and so do the scars.

[h2]With friends[/h2]
[list]
[*]Up to 8 players over Steam: the co-op campaign, a free-for-all or a brawl where everyone fights everyone.
[*]14 arena and party modes: duels, best of three, teams, king of the hill, head football, last limb standing and more.
[*]The Emperor's decrees change the rules mid-fight. The crowd throws things.
[*]A kill cam replays the best kill of every fight in slow motion. Clip it and share it.
[/list]
```

## Demo (its own short description)

> The first 8 bouts of the campaign, up to the Big Lion. Alone or in co-op over Steam, plus the
> arena, the training ring with the bear and the gorilla, and the whole forge.

## Tags (20, most important first)

Steam weighs the first tags most. Pick from Steam's own list in this order:

1. Physics
2. Gladiator
3. Medieval
4. Violent
5. Gore
6. Sandbox
7. Voxel
8. Crafting
9. Online Co-Op
10. PvP
11. Action
12. Fighting
13. Funny
14. Destruction
15. Ragdoll
16. Character Customization
17. Multiplayer
18. Third Person
19. Indie
20. Early Access (only if released in Early Access; otherwise Singleplayer)

**Genre:** Action, Indie (also Early Access if it applies).
**Features:** Single-player, Online PvP, Online Co-op, Steam Cloud (when Save is moved there),
Full controller support only after a full pass with a pad (today: Partial Controller Support).

## Content survey (mature content)

The game shows strong realistic-style violence on voxel figures: severed limbs, organs and blood.
Answer **"Frequent violence or gore"** truthfully. It puts the page behind an age gate in some
countries but not off the store. Mention the in-game Gore setting (Full or Reduced).

## System requirements (check on a low-end PC before publishing)

| | Minimum | Recommended |
|---|---|---|
| OS | Windows 10 64-bit | Windows 10/11 64-bit |
| Processor | 4 cores, 3.0 GHz (Intel i5-6600 / Ryzen 3 1300X) | 6 cores (Intel i5-10400 / Ryzen 5 3600) |
| Memory | 8 GB RAM | 16 GB RAM |
| Graphics | Vulkan 1.1 or Direct3D 12 GPU, 2 GB (GTX 960 / RX 470) | GTX 1660 / RX 5600 XT, 6 GB |
| Storage | 1 GB | 1 GB |
| Network | Broadband for online play | Broadband for online play |
| Notes | Graphics quality: Low | Graphics quality: High |

The physics is the heavy part, on the processor: 8 fighters at once run at about 7.4 ms per
physics step on one core.

## Art the page needs (exact sizes)

| Asset | Size (px) | Where it shows | File |
|---|---|---|---|
| Header capsule | 920 × 430 | top of the page, lists | `capsules/header_920x430.png` |
| Small capsule | 462 × 174 | search, lists | `capsules/small_462x174.png` |
| Main capsule | 1232 × 706 | the front page carousel | `capsules/main_1232x706.png` |
| Vertical capsule | 748 × 896 | seasonal sales | `capsules/vertical_748x896.png` |
| Page background | 1438 × 810 | behind the page (optional) | `capsules/background_1438x810.png` |
| Library capsule | 600 × 900 | the Steam library grid | `capsules/library_600x900.png` |
| Library hero | 3840 × 1240 | the library page banner (no text) | `capsules/library_hero_3840x1240.png` |
| Library logo | 1280 × 720, transparent PNG | over the hero | `capsules/library_logo_1280x720.png` |
| Screenshots | 1920 × 1080, at least 5 | the gallery | `screenshots/*.png` |

Valve's rules for capsules: the game's name must be readable, and no review quotes, prices,
awards or "out now" text. The capsules here are made from real game frames with the title over
them. They are good for a first page. A hand-painted key art is the one thing worth paying an
artist for later.

## The trailer (30 to 45 seconds; the first 5 decide)

Steam autoplays the first trailer muted, so the first seconds must read without sound.

| Time | Shot | Text on screen |
|---|---|---|
| 0–3 s | The gorilla grabs a gladiator and tears him in two | — |
| 3–6 s | The forge: a weapon built voxel by voxel, fast | BUILD IT. |
| 6–10 s | First person: that weapon swung into a man, a limb flies | SWING IT. |
| 10–16 s | Fast cuts: elephant stomp, crocodile death roll, Cyclops | — |
| 16–22 s | Four friends against the Minotaur, the crowd on its feet | UP TO 8 PLAYERS |
| 22–28 s | The silliest weapons: the goose, the chicken, the two-person sword | — |
| 28–33 s | Kill cam slow motion of the best kill | — |
| 33–38 s | Logo | WRECKSMITH · Wishlist on Steam |

Record with the game's own F9 recorder or OBS at 1920×1080 60 fps, gameplay only.

## Remaking the screenshots and capsules

```
# screenshots (needs a display or xvfb-run), 1920x1080
SHOT_DIR=docs/store/screenshots godot --resolution 1920x1080 --path . -- --probe steamshots
# capsules from those screenshots
python3 tools/make_capsules.py
```
