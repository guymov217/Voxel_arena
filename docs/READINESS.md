# Readiness: the demo and the full game

Where WRECKSMITH stands for a Steam release, what is done, what still needs a person (and a real
PC with a GPU) and what is known to be rough. Kept with the code; update it as items close.

## The short of it

| | Demo | Full game |
|---|---|---|
| Content | Ready: campaign bouts 1–8 (two bosses), duel / best of three / free-for-all, training, the forge (weapons and armour), the yard | Ready to play end to end: the whole campaign, 14 arena and party modes, 24 beasts and monsters, co-op and versus |
| Code and tests | 260 automated checks, run with `sh run_tests.sh` (parse, every suite, a host and a guest over ENet) | Same build |
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
- Tests no longer depend on which ran before them: each test's world is cleared before the
  next starts (up to 400 bodies from earlier tests used to stand in later ones).

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
