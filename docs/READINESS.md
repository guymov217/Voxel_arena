# Readiness: the demo and the full game

Where WRECKSMITH stands for a Steam release, what is done, what still needs a person (and a real
PC with a GPU) and what is known to be rough. Kept with the code; update it as items close.

## The short of it

| | Demo | Full game |
|---|---|---|
| Content | Ready: campaign bouts 1–8 (two bosses), duel / best of three / free-for-all, training, the forge (weapons and armour), the yard | Ready to play end to end: the whole campaign, 14 arena and party modes, 24 beasts and monsters, co-op and versus |
| Code and tests | 298 automated checks, run with `sh run_tests.sh` (parse, every suite, a host and a guest over ENet) | Same build |
| Store page | Copy, tags, 13 screenshots, all capsules, two key-art posters, the logo (`docs/store/`) | Same page; the demo is attached to it |
| Steamworks | Not set up yet (needs the account owner) | Not set up yet |
| Played on real hardware | Not by me: everything here was checked headless and with a software renderer | Same |

**Verdict:** the demo is feature-complete and ready for a closed playtest on real PCs; after a
playtest pass and the Steamworks steps below it can go up for Steam Next Fest or as a standalone
demo. The full game is content-complete; it needs playtesting for balance and a run of the
long campaign on real hardware before a release date is set.

## What a person still has to do

1. **Steamworks** (docs/DEMO.md has the steps): the full game's app and its *Coming soon* page
   (a demo cannot be public before its game's page), the demo app, depots, launch options,
   the real App IDs in `tools/steam/*.vdf`. Without `SteamAppId`, the game falls back to 480
   (Valve's test app), which is right for development only.
2. **Store review assets**: upload the capsules and screenshots from `docs/store/`, write the
   short and long description from `STEAM_PAGE.md`, fill in the content survey (violence and
   optional gore: the Gore setting turns blood, organs and severing down), the age rating
   questionnaire, and the system requirements once measured (below).
3. **A trailer**: the plan and the render kit are in `STEAM_PAGE.md`; it has to be recorded on a
   PC with a GPU (F9 records gameplay in the game).
4. **Builds**: the *Builds* workflow exports Windows, Linux and macOS, full game and demo. macOS
   builds are not signed or notarized (Steam does not require it for Windows/Linux; for macOS
   it does, with an Apple developer account), so ship Windows (and Linux) first.
5. **Measure on real hardware**: frame rate in a full arena (8 fighters, a beast, the crowd)
   on a low, a mid and a high PC, with and without the C++ voxel core. That gives the minimum
   and recommended requirements for the page and checks the "Low" performance mode.
6. **Steam Deck**: gamepad play and rebinding are in; check the text size and the forge with a
   pad on the Deck before asking for *Verified*.

## Tested and fixed in this round

- Two-handed weapons no longer get caught in the sand (weapons slip on it, spears keep their
  point over it): in a soak of random swings, turning and walking, frames with the blade more
  than 45° off the mouse went from 50 to 0 (longsword), 9 to 0 (zweihander), 70–185 to 5–34
  (spear).
- Thrusts go along the blade, the feet stepping that way (5–20° off the line, was 25–70°).
- A wounded arm sags and wanders slowly instead of buzzing (hand speed at rest 1.2 → 0.1 m/s).
- The forge: armour is made there (its Armour tab), grips placed per hand, sharpness priced.
- Short grips stay one-handed: two fists need 12 cm of grip, and a long one-hander taken in two
  hands spreads the hands to the ends of the grip (they sat 8 cm apart and jammed the swing).
- The armour bench takes 2400 plates, up to 6 blocks out from the body, and marks front and back.
- The arena sand: 10 cm voxels of their own shade and height, raked, trampled, damp by the wall,
  with pebbles and grass tufts.
- Two-handed guards and strokes (user video): a high guard holds the hands at the brow in front
  of the face instead of over the head; the trunk holds itself upright against a heavy haft and
  turns with a stroke out to the side; a mark held with the swing button down no longer locks the
  elbows straight. In a soak of fast strokes to eight marks, strokes still more than 30° off the
  mouse a second later went from 1–11 of 24 to 0 (longsword, zweihander, warhammer); the trunk's
  lean at a guard from 21–28° to 13–17°.
- The crocodile's death roll can be fought: pulling away prises the jaws open (faster with
  breath), and the roll slows while he struggles.
- Guests: a beast's status reached them in a form they could not read (an error each snapshot,
  no health or jaw shown); fixed. Measured otherwise, a guest costs no more than a local game.
- The floor: smooth sand and packed earth with a fine 5 cm voxel grain in its colour.
- Tests no longer depend on which ran before them: each test's world is cleared before the
  next starts (up to 400 bodies from earlier tests used to stand in later ones).

## Closed since (the campaign and the market round)

- The campaign: a purse of 60 to start, gentler bouts 2–4, the Big Lion first and the Cyclops
  eighth, bleeding a quarter slower for players, beasts' bites capped and paced, giants' blows
  pulled, death's door and the lift in co-op, the rudis and a second lap at the end, returning
  bosses in steel; the crowd pays a little more for a lively bout.
- Armour: every plate guards its spot until worn through (by its stuff), layers add up, plates
  can be painted at the bench, and knocked-off plates stay off until the armourer mends them.
- The market: the Hand of Jupiter (a grip on a man, steered by the crosshair and the wheel, F
  hurls him; twice a bout) and the fireball.
- The trainer in the yard: six abilities (strength, blow, wind, hide, blood, footing) bought
  a session at a time for denarii, two per cent a session, no further than a per cent for every
  bout won; a death takes it all. Measured in equal-bot duels (gladius and shield, sides swapped
  every bout, 24 bouts): untrained 14 of 24 won (noise about 50%), half-trained 17 of 24,
  fully trained 18 of 24. A trained body tells, and does not decide a fight. The campaign
  autopilot (which never blocks) still loses every bout with or without training, so the
  campaign's winnability still needs people.
- Settings: VSync, a frame-rate cap and the size of the text and menus (for a TV, 4K or the
  Deck), beside the display mode, window size, 3D resolution and anti-aliasing already there.
- The save is written beside the old one and moved into place whole, the last good one kept as
  `.bak` and read back when the save cannot be: a crash mid-write no longer loses a campaign.
- The *Builds* workflow builds the C++ core against godot-cpp 4.4 (the extension's
  `compatibility_minimum`); godot-cpp has no 4.7 branch, and a 4.4 build loads in 4.7.2. What
  cannot be checked here: that the exported Windows build loads the core (the game falls back to
  GDScript voxels without it, slower but whole), so run one export and look for the core in the
  log on a real PC.

## Known rough edges

- Two-handed stabs straight up or down travel little (the arms are already at full reach in a
  high guard): 0.16–0.28 m along the line, against about 0.5 m for a level stab.
- Heavy two-handers (the warhammer) are slow to come round to a new mark: by design, but it
  can read as lag.
- "The left arm locks up raised" (seen once in a screenshot) has not reproduced in soak tests
  of shield, dagger, empty hand, blows to the arm, falls and throws.
- The crocodile's death-roll test and the giant's grab test are timing-sensitive (beast AI
  with random decisions); they pass on their own and fail now and then in the full run.
- Everything above was checked headless and with a software renderer; lighting, shadows and
  frame rate must be looked at on a real GPU.

## Not in yet (later, not needed for the demo)

- Steam achievements and Steam Cloud (saves are local; Steam Auto-Cloud can be switched on in
  Steamworks without code, pointing at the game's user folder).
- Localisation: English only.
