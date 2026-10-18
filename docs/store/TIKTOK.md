# WRECKSMITH on TikTok (and Shorts, Reels, X)

The clips are made from the game itself, vertical 1080×1920 (`docs/store/clips/`, how to
remake them at the end). The same file goes to TikTok, YouTube Shorts and Instagram Reels.

## The rules that matter

1. **The first second is the whole video.** Open on the moment itself, never on a menu, a logo
   or a walk up to the fight. People scroll within a second.
2. **7 to 15 seconds.** A short clip watched twice beats a long one watched halfway, and
   re-watches are what the algorithm counts.
3. **One idea per clip**, written on screen in at most 6 words at the top. Most people watch
   with the sound off.
4. **The game's own sound plus a trending sound at low volume.** Add the sound in the TikTok
   app (its library is cleared for use; music added outside the app can get the clip muted).
5. **No "wishlist now" at the start.** At the end, one line: *WRECKSMITH, wishlist on Steam*.
   The Steam link goes in the profile bio (TikTok has no links in captions).
6. **Post 3 to 5 times a week, at the same hours.** Evenings, 18:00–21:00 in the US
   (01:00–04:00 Israel time), are the most watched for gaming; TikTok's scheduler posts for you.
7. **Answer every comment in the first hour.** A reply with a video ("you asked what the
   gorilla does to armour…") is a free next clip.

## The clips (hook on screen · caption · what it shows)

| # | File | Text on screen | Caption |
|---|---|---|---|
| 1 | `clip_gorilla.mp4` | he wanted to fight the gorilla | the gorilla does not lose #indiegame |
| 2 | `clip_cyclops.mp4` | 1 spear vs 1 cyclops | he had one eye and one plan |
| 3 | `clip_elephant.mp4` | never stand in front of the elephant | physics was not on his side |
| 4 | `clip_bear.mp4` | axe vs bear, who wins | every voxel can come off |
| 5 | `clip_duel.mp4` | real physics sword fight | no animations, only physics |
| 6 | `clip_zweihander.mp4` | the zweihander solves problems | swing hard or go home |
| 7 | `clip_chicken.mp4` | i forged a chicken. it works | the forge lets you build anything |

**Ideas to film next** (by hand, in the game, with the F9 recorder or OBS in a 9:16 window):

- *"Building the dumbest weapon possible"*: the forge sped up ×8, then one swing. The forge is
  the thing no other physics fighter has, so it gets a series.
- *"Rating every weapon 1–10"*: one swing each, a number on screen. A series of 5.
- *"POV: you are the gladiator's last opponent"*: first-person camera, kill cam ending.
- *"My friends tried co-op"*: four players against the Minotaur, chaos, real voice chat.
- *"The crocodile death roll"*, *"The hydra grows back"*: one creature per clip, 25 of them.
- *Dev clips*: "I added organs to my voxel game", "how voxel cutting works". Game-dev
  TikTok is a big audience of its own and brings wishlists too.

## Hashtags (3 to 5 per clip, no more)

Always: `#indiegame #gaming`
Pick 1–3: `#physicsgame #gladiator #voxel #halfsword #gamedev #indiedev #steam #funnygames`

## Profile

- **Name:** WRECKSMITH
- **Bio:** Physics gladiator game. Forge it, swing it, wreck it. ⚔️ Wishlist on Steam ↓
- **Link:** the Steam page (in the bio, once the account may show links).
- **Avatar:** `docs/store/capsules/library_logo_1280x720.png` cropped to the "W", or the
  gladiator's head.

## Where else the same clips go

| Site | What to post | Note |
|---|---|---|
| YouTube Shorts | the same files | Title = the screen text. Shorts last longest in search. |
| Instagram Reels | the same files | |
| X (Twitter) | the clip + a short line | Tag #screenshotsaturday on Saturdays. |
| Reddit | the best clip only, once a week | r/IndieGaming, r/godot (say it is Godot), r/HalfSword (ask the mods first), r/gamedev on Saturdays. Write as the developer, not as an ad. |

## Remaking the clips

The clips are cut from fights played by the game's bots, with a cinematic camera
(`tests/clipshots.gd`):

```
tools/make_clips.sh            # every scene; or: tools/make_clips.sh gorilla bear
```

The script runs each fight once without drawing (fast) to find its best seconds, then draws
those seconds at 1080×1920 with the game's own sound and writes the hook text on top.
