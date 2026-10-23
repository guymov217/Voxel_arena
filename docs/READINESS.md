# Readiness: the demo and the full game

Where WRECKSMITH stands for a Steam release, what is done, what still needs a person (and a real
PC with a GPU) and what is known to be rough. Kept with the code; update it as items close.

## The short of it

| | Demo | Full game |
|---|---|---|
| Content | Ready: campaign bouts 1–8 (two bosses), duel / best of three / free-for-all, training, the forge (weapons and armour), the yard | Ready to play end to end: the whole campaign, 14 arena and party modes, 24 beasts and monsters, co-op and versus |
| Code and tests | 302 automated checks, run with `sh run_tests.sh` (parse, every suite, a host and a guest over ENet) | Same build |
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

- Two hands range like one (user video: with both hands on a longsword the fists never left the
  brow, the blade stood up out of them and the arms looked tangled, while one hand swung wide).
  Both hands now go where the mouse sends them, as one hand does: the main hand to the same mark
  one hand is given, the front hand ahead of it down the haft, and the pair is moved in toward
  the shoulders only as far as an arm needs to reach its grip. Over a grid of nine marks the
  main hand's box went from 0.98 × 0.90 m (across × up) to 1.13 × 1.09, against 1.35 × 1.13 in
  one hand; aimed right up the hands rise 0.5–0.6 m over the shoulder (0.4 before, 0.6 in one
  hand). Out to the main hand's own side the mark goes 0.4 as far (the other hand has to cross
  the whole chest to keep its grip there) and the hands go no lower than the hips (a long blade
  pointed down from lower went into the sand). In the soak of fast strokes to eight marks every
  stroke is on the mouse within 30° a second later (longsword worst 24°, warhammer 16°); thrusts
  still go to the arm's full reach (not pulled in).
- The joints drawn whole (user screenshots: the upper arm a hand off the chest with the arm
  raised, the forearm off the elbow). The shoulder's socket sits an arm's width out from the
  chest, so a raised arm pivoting there left its top that far from the chest, and a bent elbow,
  hip, knee or neck opens a wedge between its two blocks. A block of the limb's own thickness
  and colour now sits on every pivot: hidden inside the two parts while the limb is straight,
  filling the wedge as it bends; at the shoulder it turns with the arm and runs from the arm's
  top into the chest as far as the arm's line meets it (the deltoid). Drawing only: nothing in
  the physics, the cut and the hit are as they were; a cut-off, hanging or prosthetic limb has
  no cap. The kill cam draws the caps and the closed joints too (Fighter.draw_now).
- A stab block on a stab block (user screenshot: a column of points drawn as blocks with a
  small roof on top): a run of points is one spike now, each block narrowing from its base's
  width to its tip's, the honed end only on the last, the half of a plate two wide pinched
  toward the face it shares with the other half; a point the smith turned another way ends the
  run. The spike bits ride in the custom data's alpha (the taper's 16 bits fill what a float
  holds exactly beside the kind).
- Feet on a body (user video: standing on a fallen man the legs hung in the air). The stance
  ray read the sand alone, so on a body the fighter counted as off the ground and planted no
  foot. It now reads whatever lies under him (his own bodies kept out of it), each foot finds
  the ground under its own spot, and the stance pendulum measures from the foot's own height.
  Only a body lying still counts: read as ground, a boar charging under him threw him 3 m into
  the air (the creature tests caught it), so a body on the move is passed over for the sand.

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
- The failures that remained were not timing but order: the physics is deterministic, yet a
  blow's outcome depends on the bodies' history in the process, so a test that asserted dice
  (a cut landing, a hug given, a magnet's grip) passed alone and failed after another suite.
  Those tests now assert the mechanics (the rage, the hug, the nearest approach) and pass in
  any order: pots+social 14/14, beasts+materials 18/18, demo+tutorial+basics+training 11/11.
- Limbs stay on the body (user request): the joints of a ragdoll open under load (an elbow
  driving a heavy blade by 7–9 mm on average, up to 15 cm in a hard blow; a shoulder 2–7 mm,
  up to 4.5 cm; shoulders open past 3 cm in 2–4% of the frames of a duel, elbows in 3–7%).
  On screen every joint is now closed: each part is drawn against the part it hangs from and
  the weapon with its hand, so nothing floats until it is really cut off, when it is left to
  fall. The bodies themselves are left as they were: setting each limb back on its joint
  before every step, or 24 Jolt position iterations instead of 10, brought the physical gaps
  down to 1–3 mm (0–0.3% past 3 cm) but cost the heavy two-handers their precision (the
  warhammer 32–48° off its mark where 30° is allowed, a high guard 39° off), so neither is
  in; the drawing alone gives the 100% on screen with the arms untouched. Mobility and cutting
  are unchanged (arms, fight, footing, destructible, social, flaps, body, giants suites; a new
  `seating` suite measures the gaps, the drawn seating and a cut limb).
- The beasts (user's play): the lion took a man apart in ten seconds and nothing he did
  changed it. Measured with a gladius bot against the stage-4 Big Lion: dead in 10–13 s after
  7–9 bites, the lion at 95%. The cause was in the blows, not the lion: every touch of a
  beast's jaws at a walk's speed counted as a bite (one every half second, whatever the man
  did), and a bite cut like a keen blade. Now a beast bites only in a strike (Beast.strikes:
  the snap after the wind-up; the crocodile's jaws alone close on whatever touches them, its
  bite being the grab the man then fights), teeth go in at 0.65 of a blade's keenness, a bite takes at most
  30 off a limb (was 55: two bites and both arms hung useless), never opens an artery, and
  bleeds at 0.4 of a blade's wound (measured again after each step: the bot now lasts 20–23 s
  and the stage-4 autopilot 25–34 s where it lasted 6–13; neither blocks, a player does); the player bleeds at 0.6 of a bot's rate (was 0.75) and his wounds clot faster for it;
  the lion bites 30 (was 34), lunges 4.2 (4.5), every 2.0 s (1.2); the stage-4 Big Lion is 1.9×
  (was 2.2×). Beasts and monsters come apart more under a blow (Beast.CHUNK 1.25: the wound a
  blow cuts or craters is a quarter bigger; their toughness 1.55, was 1.7); the giants of myth
  are men and keep theirs. The crocodile's hold is 3 s (3.2), pulling free is faster (PRY_RATE 1.1, was 0.75: about
  a second of pulling with breath against a second and a half for the limb to give), and only
  a hold never fought off takes the limb; and a beast no longer circles a legless man
  for ever: one who cannot stand at all is prey still (the crocodile stopped attacking after
  it had taken two legs).
- The python flew into the sky with the man it coiled (user's play): the spiral its coils are
  pulled onto was centred on his chest wherever that was, so as the coils lifted him the
  spiral rose with him. Reproduced headless (man at 3.0 m, 15 m/s) and fixed: the spiral sits
  on the sand and the coils never heave upward (now 1.5–1.6 m, a man's standing height, in
  the same seeds). The python's and the hydra's calls are quieter (Voices.CALL_GAIN).
- A dragon's fire went through a wall: a breath's globs were not checked against the world
  for their first 0.05 s (a rule for the sand under a low spit), and out of a mouth held a hand
  from a wall at nine metres a second they were past it before the first check. Found by the
  fire-breath test failing in one full run (the neck's pose is dice) and traced with a probe;
  the globs are checked from their first step, and a wall now stops the stream every time.
- A lost campaign is reset the moment the bout is lost (Match.lost), not when its result is
  read after the kill cam: leaving the fight, or the game, during the kill cam used to leave
  the stage where it was.
- The Hand of Jupiter reaches 12 m (was 7) and takes any foe but the giants (men over MIND_S,
  beasts of 500 kg and more) and the monsters of myth that come as bosses (dragon, hydra,
  Cerberus, chimera, manticore, basilisk): men, bosses among them, and beasts up to a bull.
- The honey pot: the bees come to whoever it splashes (3.5 s), as well as the puddle.
- Bug "weapon no-clips into a head and sticks": not reproduced on the current build. A probe
  drove eight weapons (gladius, spear, dagger, executioner's axe, hammer, zweihander, trident,
  longsword) at a man's head, ten stabs and ten swings each, bare-headed, in a helmet and skull
  plate, and lying on the sand: 6–26 head blows per weapon, and never a frame with the blade
  inside the head once the hand was at rest, never a stuck weapon, never one out of the hand.
  The `seating` suite keeps that check (gladius and zweihander). The wheel-spin half of the
  report was fixed earlier.
- Bug "the left arm locks up raised": still not reproduced; a soak of ten states (a shield held
  high and let be, knocked out, a dagger, an empty hand, blows to the arm, falls, throws, a
  two-handed grip taken and let go) reads the elbow's limits and the hand's height after each,
  and finds the arm at rest every time (elbow span 2.65 rad, no lock flag left set).

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
- "The left arm locks up raised" (seen once in a screenshot) and "a weapon no-clips into a
  head and sticks" have not reproduced in soak tests (see above); if either is seen again, a
  kill-cam clip or the save and the weapon used would let it be traced.
- The crocodile's death-roll test and the giant's grab test are timing-sensitive (beast AI
  with random decisions); they pass on their own and fail now and then in the full run.
- Everything above was checked headless and with a software renderer; lighting, shadows and
  frame rate must be looked at on a real GPU.

## Not in yet (later, not needed for the demo)

- Steam achievements: in (`scripts/game/achievements.gd`, fifteen, kept in the save and set on
  Steam when it runs); the API names and texts to enter in Steamworks, the Auto-Cloud root for
  the save and the content survey answers are in docs/DEMO.md (4b). Icons still to draw.
- Localisation: English only.
