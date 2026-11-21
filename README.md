# WRECKSMITH

A physics gladiator brawler in **Godot 4.7** (GDScript, Jolt physics at 120 Hz). Fighters are built
from voxels and lose them to every cut, thrust and blow. You build your own weapons in a voxel
forge, and you face 24 species of beasts. Multiplayer is host-authoritative, over **GodotSteam**
lobbies or plain ENet.

The game's tables (weapon presets, materials, body plans, beasts, the campaign's stages and pay,
shop prices, controls) live in `data/*.json`. They were exported from the original browser
prototype of the game.

```bash
godot --path .                   # play (or open project.godot in the editor)
sh run_tests.sh                  # parse check, headless test suites, two-process network test
godot --headless --path . -- --test test_fight   # one suite
FOES=dragon,foe:titan godot --headless --path . -- --probe sweep   # automated bouts, anything odd flagged
```

`GODOT=/path/to/godot` points the scripts at a Godot binary other than `/opt/godot/...`.

## What is in the game

- **Fighters**: voxel body parts as rigid bodies on joints. A PD-driven balance spring and leg
  control. Falling, getting up, and Half Sword mouse hands, with each hand on its own button.
- **Damage**: per-voxel damage by material and hit type (cut, thrust, blunt). Dents, limbs that
  hang or come off, and blood and breath. Chips knocked off weapons wear them down. Fire.
  Blunt and keen are different harm: a crushing weapon (a mace, a hammer: its head all blunt
  but a few studs) bruises and pulps rather than taking flesh away, and breaks bones sooner and
  worse the harder its head; blades cut. A nail pot's nails each punch a hole of their own where
  they go in, bleed and stay in; the ones that miss bounce and lie on the sand.
  A thrust is as hard as the man behind it and the weapon in his hand (`Combat.thrust_power`: his
  strength, the training's Vis, in proportion, and the weapon's weight): a knife to the belly hurts
  and bleeds him but does not kill him at once or go through him, and one lunge is one blow
  (`tests/test_thrust.gd`).
  A harder and a faster swing takes more flesh, by the physics alone: the blow's momentum sets how
  deep a cut goes and how wide a crushing blow's hollow is, and past the most a part gives to one
  blow they go on growing, slowly, as the root of the force (`Fighter.past_cap`, `tests/test_blunt.gd`).
  A cut is the size of the blade that made it: as wide as the blade is thick where it landed
  (`Weapon.blade_at`: the voxels through it across its flat, one on nearly every blade, so a row or
  two of a man's fine voxels, and never less than a row of a beast's or a giant's bigger ones), as
  long as its own keen run reaches from the place it touched, towards the hand and away from it (the
  rows that carry an edge or a point, unbroken: a dagger's cut across a chest is a dagger long, a
  longsword's runs right across it, a cut with the end of the edge runs back from there), and as deep
  as the blow drove it, as ever; the harm and the bleeding are the blow's and are what they were. (A
  cut was a hand's breadth across and half a metre long whatever opened it: one hard cut down an
  upper arm took a third of the arm.) An open cut within a hand's breadth still draws the next blade
  in, down its middle (`Fighter._slot_draws`), so a limb is chopped off by blows about one place and
  the cut stays as thin as the blade to the last; a cut across a limb is through its bone when it
  has taken `BLADE_THROUGH` of the bone's width there, however small a share of the whole bone that
  is (`_edge_on_bone`, `VoxelPart.bone_across`; a graze of its edge is no break); and a limb it has
  gone most of the way through hangs at whatever slant the cut runs (`VoxelPart.left_across`). A paw's claws, which are no blade, open what they did, and a
  crushing blow's hollow and a point's hole are as they were (`tests/test_blade_cuts.gd`).
  A soft weapon (a rubber chicken, a fish, a goose on a stick: a thing softer as a whole than
  `Fighter.BONE_SOFT_H`) gives way on what it strikes, so only a share of its blow goes in
  (`Fighter.soft_share`: a tenth at the very softest, a sixth for the chicken, under a third for a
  fish, all of it from `BONE_SOFT_H` up); the harm, the rocking, the hollow and the plates it
  knocks off all go by that share, not by the weight swung (it was the whole blow: a chicken did
  two thirds of a club's harm and hollowed a man like one; `tests/test_fractures.gd`). It is judged
  by the weapon as a thing (the harder of the stuff that touched and the weapon's mean), so the
  leather on a sword's grip and the stick under the goose hit as they always did.
  Everyone bleeds by one law, a man, a giant, a beast, a boss: the blood a body loses is the bleeding
  on it (its wounds, cut arteries and stumps) over its size, so a body twice a man's loses it half
  as fast from the same wounds, never none (`Fighter.blood_lost`; it went with the size squared
  and a cut artery's flow was cut by the size as well, so the lion boss lost 4 blood in 160 s of
  cuts and a giant next to none, and none of them could bleed to death). A dozen hard cuts in the
  limbs bled a man out in 4 s, a goat in 6, a lion in 7, the Big Lion in 10, a gorilla in 15, the
  giants in 7 (the minotaur) to 17 s (Polyphemus); an elephant, a rhino or a dragon, whose hides take
  little of a cut, kept two thirds of their blood from a dozen, and lost it all in under 20 s to
  three dozen (`tests/test_bleed_out.gd`). What a torn organ runs out is by its share of the organ,
  not by the voxel (`Fighter._organ_bleed`; a lion's heart is 150 voxels to a man's 27): half a
  heart torn kills a man in 3 s, a lion in 8, a bear in 9, the Big Lion in 11, an elephant in 14
  and a dragon in 18, none sooner than a man.
- **Broken bones**: a blow cracks a bone or breaks it, as hard as it was: cracked, the limb works
  at a little over half and a lesser blow breaks it through; broken under the skin (closed) or
  out through it (open, the bone showing), the limb is no use: not driven, held on by its muscle
  only, it flops from the joint and is drawn bent at the break, and still never passes through
  the body. The skull cracks, is driven in or breaks open; broken ribs cut the breath and, broken
  in, hurt the lung. In the campaign the bones stay broken from fight to fight until the
  physician sets them (no elixir needed: a bone knits, a hand does not grow back). A break is
  seen: a broken limb is drawn bent, an open break has the splinter standing out of the skin,
  the HUD figure marks the bone, the feed names it and it is heard over the blow. A player's
  arm is the sturdier kind (`Fighter.sturdy_arms`, set by `Match` for the men's own fighters, not
  at the trainer's Extreme, where the old rules stand): a sound arm bone only cracks from one
  blow, however hard, and breaks through only under a second, separate blow (`ARM_CRACK_GRACE`
  s after the crack, a blade having to cut `ARM_CRACK_CUT` of the cracked bone); a hairline crack
  in an arm mends between bouts (`Body.snapshot`), a break stays until the physician sets it.
  The bots' and the beasts' bones, and a player's legs, break as ever (`tests/test_arm_cracks.gd`).
  With his weapon arm out and his good hand on a shield only, G lets the shield go and takes
  the weapon lying by him (`Fighter.swap_target`; the HUD's "Pick up" shows it).
- **Weapons**: built from the same voxel designs, with greedy-merged colliders and shields.
  Chain weapons, bows and crossbows, throwables and the market. A weapon is only ever taken up by
  hand (G): the hand reaches for the grip (he stoops for one on the sand, steps to one a pace
  off), and at the grip the fist closes on it and brings it into line along one smooth curve,
  carried by the hand the whole way, then it is held. The "Pick up" prompt shows exactly when G
  would take something. J changes hands, H puts both on the haft; neither ever drops a weapon.
  A head far heavier about the hands than about itself (the war hammer) is turned by a torque
  averaged over two steps (`Fighter._drive_haft`), so the hands and elbows do not flicker with
  every swing; a sword, a spear or an axe is driven exactly as before.
  Whatever lies still on the sand (a weapon, a severed limb, chips) is walked over, not tripped on.
- **Glancing and lodged blows**: a weapon that meets a plate at a slant, or a blade that lands
  flat, skids off with sparks and a scrape and does little; a square cut chops in, bone crunches.
  Two weapons that meet ring (`Combat.clang`) but throw sparks only when they meet hard and fast
  (`Match.clang_sparks`: an impulse of 5 or more at 3 m/s or more, the speed the two came together at
  there, `v` of the signal); blades laid together or a parry that barely moves ring and spark nothing.
  A heavy keen blade driven hard can stay in the wound, still in the hand: it is wrenched out
  by pulling (the man it is in comes with it) or let go of (G), and taken back the same way.
  None holds a man for good: the man it is in tears it out with G, pulling away frees it
  sooner, and after three seconds it works loose by itself. A giant's blade never stays in, nor
  carries a man off on it: a heavy blow from one goes on through him for a moment, so it knocks
  him down where it lands instead of flinging him, or the limb it took, across the sand.
- **Armour that wears**: every plate you put on protects the spot it covers until it is knocked
  off, at a force by its stuff (leather gives first, steel last); what came off stays off between
  fights until the smith mends it (Mend, in the armour tab), and plates are painted on the bench.
  A plate stops a cut and a stab outright: what reaches the man under it is only the blow's
  weight, as a bruise (a club's most of it, a great sword's much, a light blade's little), and
  every blow wears the plate, until it flies off and the gap it leaves lets the next blade in.
- **The trainer** (Doctore, in the yard): six abilities bought a session at a time, never earned
  in the arena: vis (strength: half of it behind every blow, and all of it in every throw, a weapon, a pot, darts, a discus, which leave the hand faster and land harder), ictus (the blow), spiritus (breath), corium (a thick hide),
  sanguis (slower bleeding) and firmitas (footing). Each costs more than the last and is capped
  by the bout you have reached (`scripts/game/training.gd`). What the points are worth is shown as
  it is (`Training.effect`): the first sessions count about twice what they did (one is over five
  per cent, three about fifteen), each after it a little less, and at 45 points it is what it always
  was; Ictus raises the damage a blow is held to as well as its weight.
- **The Hand of Jupiter**: a telekinesis charge from the market seizes the foe under the
  crosshair, up to 12 m off (a man or a beast; not a giant, not the great monsters of myth), for three seconds (twice a
  bout), the wheel draws him nearer or further, and F lets him fly with the mouse's sweep; a
  hard landing hurts. Its price follows the purses (`Market.price`: nine tenths of the best
  a bout has paid by then, in fives), so its two lifts a bout never cost next to nothing.
- **The market** (`scripts/game/market.gd`): the trader's wares lie in six tabs by what they do
  (Fire & blast, Floor traps, Snares & tricks, Thrown arms, For archers, For the crowd). Something of every
  tab is on the table from the first visit (`Market.BASIC`) and one more ware is brought after
  each boss beaten, in the order of `Market.AFTER_BOSS` (the torch after the first, then the goat,
  the bola, Greek fire...); a ware not yet come lies dim with the bout it comes after, and in the
  second time round the campaign everything is there. The count is kept in the save (alone and in
  a party apart) and a death never takes a ware off the table. Training has every ware, free; the
  physician sells what is used on oneself (bandages, bread, wine, the water skin). The torch is
  held in the free hand (the right one when both are empty) as a weapon of its own, a thin stick
  with a bulb of burning rag on its end and a flame standing up out of it (`Throwables.torch_design`,
  `Weapon._torch_flame`; lent to the hand and gone from it when put away or thrown; the weapon it
  took the hand's place from is back in it then): every blow of it sets alight what it strikes
  (`Match._coating`, a tap too), what its flame touches catches fire and spilled oil goes up; or
  thrown (F: it burns where it lands). A torch does not burn for ever: held, it burns down in
  `Throwables.TORCH_LIFE` seconds and each blow it lands takes `TORCH_BLOW` more, its head burning
  away from the crown down and its flame shrinking with it; the burn is kept when it is put away
  and taken out again (`torch_burn` of the man's entry), and when it is spent (or knocked to
  pieces: no broken torch is left to pick up) one torch of the kit is used up and the weapon it
  took the place of is back in the hand; the water skin, poured over oneself, puts out the fire on him and
  washes off acid; the smoke pot is the old sand pot and smoke pot in one; Greek fire is the old
  fireball pot, burning oil that pools on the sand; the beehive is gone (the honey pot's bees stay).
  A bag from an older save keeps its wares under their new names. The thunder pot's blast is
  about two fifths weaker than it was (`Throwables.THUNDER`: power, reach, shove, ringing, and how
  near a man must be to be put down); the Hot Potato's bomb goes off as the pot used to
  (`Throwables.BOMB_BLAST`). Every kind of pot bursts with a sound of its own (`art/audio/pots/<kind>.wav`, made
  for the game: the clay breaking, then what was in it; the thunder pot's has the blast in it too, the soft boom
  with the pot loud over it, the one the user picked of three): `Sfx.pot` plays it, `Match.pot_sound` sends it
  to the guests (an `fx` message "pot"), and nothing is laid over it (the old clang, slash, slap and boom are gone).
  A kind with no file of its own breaks as clay (`pot_clay`); a build without the files falls back to the shatter
  `Sfx` makes on the fly (the pot's knock, a crack and single shards ringing down, no rattle of noise: that was a
  static at every impact). `project.godot` makes WAVs import uncompressed (`importer_defaults`).
- **Fists**: with both hands empty he stands in a boxer's guard (an empty hand beside a weapon
  hangs at his side), and a click throws a punch with an empty hand: the elbow stays bent as the
  fist is drawn in, opens on the way out and locks straight for the blow, then folds straight
  back into the guard, the elbow down (`Fighter.JAB_*`, `tests/punchprobe.gd`). The punch is one
  motion (`jab_reach_at`): a short load, out faster and faster, home again; the trunk turns and
  leans in ahead of the fist (`jab_turn_at`, the later of two punches taking it), the guard hand
  goes round with it, and a click while that fist is still coming home is thrown as it gets
  there. A fist strikes only while it is thrown or swung by its owner (`fist_strike`), one that
  lands solidly starts home at once, and one strike of a fist or a foot lands once on a man
  whatever parts of him it crosses. A front kick shifts the weight onto the standing foot as the
  knee comes up, drives the foot out, draws it back in and sets it down (`kick_pose`); it
  strikes only on its way out (`kick_strike`).
- **A spear is thrown as a javelin is, over the shoulder** (user: the javelin was held a third of
  the way up its shaft where it balances two thirds of the way, and its wind-up never drew the arm
  back; then, of a hold drawn back at the shoulder's height: spears are thrown over the shoulder;
  and that hold only when the player presses to throw). Carried, a spear is held as it always was.
  Only while winding up to throw (F held, or a bot's wind-up) the hand shifts its hold up the
  shaft to just behind the balance point over 0.12 s, the spear coming through the fist
  (`Weapon.throw_point`, `Fighter._throw_hold`, `_throw_grip`: the grip's 6-DOF joint is made
  again with its weapon end moved along the shaft), and goes up over the shoulder and behind it,
  by the head (`THROW_HAND`), the spear level on the line it will fly and the forearm standing up
  to it from an elbow back and out (`throw_fore`; the elbow goes round the outside of the body,
  `Fighter._route_front`'s `out_x`). The shaft lies across the fist there, not down the forearm:
  the fist is loose on it (the joint a ball while the throw lasts) and the wrist holds the spear
  on its line (`_drive_shaft`). The throw drives the hand forward over the shoulder (`THROW_OUT`)
  and the spear leaves it at the top of its speed, 0.07 s on (`Social.SPEAR_GO`); a bot's too,
  which left its drawn-back hand before the arm had moved. A throw called off, the hold goes back
  to the grip and the fist closes on the shaft when it lies along the forearm again
  (`THROW_LOCK_ANGLE`). (`tests/test_fight.gd`, `tests/test_social.gd`.)
- **Wrestling**: grabs, shoves, trips, and the giant's lift and throw. A kick at a man down at
  one's feet (lying, sitting, on his knees) is a stamp: the knee comes up and the foot is driven
  down onto him, where he is while the knee is up (`tests/stompprobe.gd`). A giant's blows vary:
  a chop from above, sweeps from either side, a low sweep at the legs and a thrust. A man it
  has knocked down it goes on striking; it does not stand off and watch him. Now and then it
  stoops to him instead, its hand right down on him, takes hold of him where he lies and lifts
  him to slam or throw him (`Bot.GRAB_DOWN_RATE`, `tests/giantpickprobe.gd`). A giant's hand
  closes only on what the fist has touched: a part the physics has the forearm on, with the fist
  at it (`Social.FIST_REACH`), or one the fist is at the surface of (`Social.TOUCH_GAP`, the few
  centimetres the physics keeps a fist off a body); a man half a metre off, near enough for the
  reach it once had, is neither taken nor drawn across (`tests/test_colossus.gd`: Polyphemus now
  takes hold with the fist within 6 cm of the man, where it took hold from 50 cm). The man is
  then brought the last of the way into the fist (`Social._close_in`: the pin joint holds the two
  as they stand, so a man taken from a hand's breadth off hung that far under the fist, and now no
  more than that breadth); a trunk sinking as the giant stoops to a grip or slams the man he holds
  is not a fall that lands hard (`Fighter.prev_vy`); the stoop is a man's bending, not a collapse:
  the hips are let down, and up again, at a pace the legs hold (`Fighter.STOOP_RATE`,
  `Fighter.lowered`; dropped at the pace of a fall the soles went through the sand and the knees
  onto it, and he sprang up at the end), the feet stay planted, and to a man lying on the sand he
  leans on out over him (`Fighter.grab_deep`), with longer to reach him (`Bot.GRAB_DOWN_REACH`),
  till the hand is down on him (`tests/test_stoop.gd`); while he is held the arm that holds him does not
  strike him, nor for a moment after the throw the arm that threw him: the hold, the slam and the
  throw do the harm, and what a thrown man lands on does the rest (`Social._throw_land`).
  A man's grab is a reach, not a snatch (user: no physical contact was to be seen when a player
  pressed G at a foe; the hand took whatever part of him had its middle within 70 cm, from where
  it hung, and he was held on nothing): G sends the hand out to the nearest part of him the arm
  can reach, the man stooping to one on the sand (`Social.grab_go`, `Social._spot_on`,
  `Social.GRAB_STOOP`, `Fighter.grab_bend`), and the hold is taken the moment the hand is on him
  (`Social.MAN_REACH`: a forearm's half-width and the little the physics keeps two bodies apart;
  `Social.GRAB_LAST` for a forearm that lies along him, in the last third of the reach); the other
  hand the same. The hand then closes on the part over a tenth of a second (`Social._grip_onto`:
  a limb is clasped round its middle line, a hand's breadth in from its end), so a hold is a
  hand on the man for as long as it lasts. F is a heave: the arms draw him back, then drive him
  out, and he leaves them at the end of the drive, 0.34 s after F (`Social.HEAVE_T`; he flew from
  still arms the step F was pressed). `tests/test_social.gd`.
  Polyphemus alone has no weapon and fights as the colossus he is (`mods.colossus`,
  `Bot._colossus`, `tests/test_colossus.gd`), every move shown in a wind-up a man can read: a fist
  drawn up over his head and brought down on a man's head (`crush`, `Fighter.CRUSH_SLOW`: the fist
  has the length of him to come down), the foot stamped down on a man on his feet as on one
  lying (`stamp`, `Fighter.COLOSSUS_SMALL`), a low kick swept through a man's middle that
  knocks him back (`punt`), and the grab, with the lift and the throw.
- **Bots** and all 24 **beast** species with their behaviours, including flying and breath. A
  beast's jaws, claws and horns bite only in a strike (the snap after the wind-up), never by
  brushing against a man, so a lunge can be dodged or taken on the shield; a bite goes in
  like teeth, not a blade, and takes no more than 30 off a limb. Beasts and monsters chunk
  more under blows than men do (the giants of myth keep their own hide). The gorilla loses its
  nerve with every blow it takes (slower to come on, fewer blows and grabs, a solid one breaks
  off its wind-up), and gathers it back when let be. Its hold is a beating (`Beast._rag_doll`):
  one hand closes on the very point of the man it touches (the other lets go), lifts him over
  its head and brings him down on the sand, three times over (twice when it is cowed; a man
  gone limp it drops sooner), then throws him aside. He hangs limp in its hand; every landing is
  a blow by the speed the sand took off him, by the one law a thrown man lands by
  (`Social.landing_blow`); a blow that staggers the ape, its arms ruined or the man slipped
  out of its hand ends it (`tests/test_beast_attacks.gd`). The manticore stings a man at its flank and
  flings poisoned spikes from its tail at one out of its reach, after raising the tail with a roar.
  The enemy's health plate reaches nothing when the fight with him is over, whatever ends it:
  head, trunk, blood, a broken neck, the brain or a torn heart, or down and spent.
  A bot archer misses (`Throwables.bot_aim`): his hand is never quite steady (`AIM_HAND`, more
  the poorer he is by the difficulty), his eye is a moment behind a man on the move and he does not
  lead him quite right (`AIM_LAG`), and now and then a shot is plainly bad (`AIM_BAD`). From seven
  paces about half of a good archer's arrows struck a man who stood still (65 of 141 in the arena
  against the sagittarius, three in four before), and as many one who strafed (42 of 96); a poorer
  archer's fall on him less often still (`tests/test_bows.gd`).
- **Wounds change how they fight**: a hurt man grows wary (a longer distance, slower to begin
  a blow, fewer strung together) and, near the end of his blood, throws a desperate lunging
  blow now and then with all his weight in it; a boss has half the wariness. Of the beasts,
  the hunters, the crawlers and the gorilla grow careful when hurt, while the furies (the boar,
  bull, rhino, bear, mammoth, elephant, dragon, cerberus, manticore, griffin, chimera and
  basilisk: `Beast.FURIES`) come on harder the worse they are hurt, sooner and closer, but
  wilder, their charges, lunges and strikes thrown wide of the man. The hydra and the hound
  press after a lunge instead of backing off (their heads strike on their own, each steered at
  the man as it snaps), and a dragon
  with a man under its chin backs off a stride to pour fire on him.
- **The campaign**: a ladder of 64 bouts, authored one by one in `scripts/game/ladder.gd`
  (who comes through the gate, who comes through the *other* gate nine seconds in or as soon
  as the first is down: the board by the gate names the first wave alone), the men with the
  stage tables' gear, weapons and skill (`data/campaign.json`), a boss on every fourth bout,
  and no kind of foe twice running. Every bout brings a foe of a new kind or a company of foes
  never seen together before: no line-up comes twice, and no boss either (sixteen of them: the
  Cyclops, the Big Lion, the Elephant, Polyphemus, the Griffin, the Hound of Hades, the Troll,
  the Minotaur, the Gorilla, the Titan, the Chimera, the Mammoth, the Basilisk, the Manticore,
  the Hydra, the Dragon). The order came from a bot-versus-bot survey of every foe against a
  plain swordsman (what beat him, how fast, at what cost): each band of eight bouts is harder
  than the one before, the crocodile, the hoplite's phalanx and the brutes wait for the
  thirties, the kinds met alone come back later two and three kinds at once, and a boss of men
  past bout 36 comes in steel (`tests/test_campaign.gd` checks the climb, that nothing repeats,
  and the gates). Pay, checkpoints and persistent weapon wear as before, except that a bout pays a
  quarter more than its list (`Match.PAY_RAISE`, `Match.paid`; a tenth at first, then raised again:
  the money hardly paid for the physician and a better weapon both); what is counted in the list's
  pay, the physician's prices, stays where it was (`Body.price_unit`).
- **The fight chosen at the gate** (`scripts/game/gate_choice.gd`): before every bout the boards
  by the yard's gate offer two or three bouts of the stretch of eight the run has reached, none
  won yet this time round: the ladder's own, the crowd's fight (that bout with one more of its
  foes, for double the prize) and another of the stretch drawn by the run (a beast hunt for a
  bout of men, men for beasts). A stage is fought as the bout chosen with the stage's own gear,
  pay and checkpoint (`Data.stage(n, players, bout, crowd)`), every bout is won once a time round
  whatever the way, and the won bouts go back with a checkpoint. A boss's day is the boss the run
  drew of its stretch's two (never the last stretch's: the Dragon ends it). E at the gate or at a
  board opens the gate's cards (`scripts/ui/gate_screen.gd`): a card for each fight on offer, its
  kind on a ribbon, its foes by name with what they carry and what it pays, and the foes
  themselves, the very ones the fight brings (`Match.bout_foes`: the same names, faces and arms,
  the second wave as it will come), standing in the arena itself (one built for the cards in a
  world of their own, late in the day: the wall, the stands and their crowd, the gates, the
  Emperor's box), each kind of fight in its own place in it. The card under the pointer (or
  picked with ← →) comes forward lit, its foes take their stance and stir, its view comes nearer
  and turns with a drag; its button, a double click, Enter or E goes through the gate, Esc back to
  the yard. A boss's day is one big card. In a room each one's pick is the card he picked on his own
  screen or the board he last walked up to, the names of those for each fight are on its card,
  and the host's own pick (its button, a double click, Enter) leads the party to the one most of them
  picked (his own when as many pick two); there is no button of its own for leading them through.
- **A party's own glory** (`scripts/game/party_glory.gd`): in the co-op campaign, after every bout
  won the crowd crowns the one of the party it loved most (the most favour, above indifference):
  he brings the party's purse a fifth of the bout's prize more and wears a laurel wreath through
  the next bout and in the yard (`Fighter.set_wreath`: leaves in two greens round his head or
  his helmet, tied at the back). The run's scroll counts each man's kills, the friends he lifted,
  the limbs he left on the sand and his crowns, bout by bout, and is unrolled for the party when
  the run ends. At the end of the ladder the Emperor has one rudis for the party: each says
  whether to share the glory (their names together in the Hall of Fame) or to fight one another
  for it in the players' brawl (the last on his feet takes it).
- **The campaign's end** (`scripts/ui/ending_scene.gd`, `scripts/game/run_scroll.gd`): the ladder
  ends with the Dragon on bout 64 (bout 63's foe, in the Emperor's gold, is the Emperor's
  Champion: the Emperor himself watches from his box), and the campaign closes in the arena
  itself: the crowd on its feet, the Emperor rising in his box to give the thumb, the rudis put
  in the gladiator's hand and held up while the crowd roars, then the rudis screen (26 seconds;
  any key or click skips it). The rudis is his for good: a
  wooden sword in the rack that fights as one, and the freedman's cap, a look picked in Your
  Gladiator that is locked until then. A man alone keeps a run's scroll too (`RunScroll`: the bouts
  won, the kills, the limbs he cut off and lost, the falls and the weapon that killed the most,
  counted bout by bout in `Match._tally`), unrolled when the run ends, by the rudis or by a death.
- **Ironman or Legionary** (`scripts/game/campaign_run.gd`): chosen when a campaign begins (in
  co-op the host chooses in the room). A legionary who falls goes back to the last checkpoint
  (every four bouts) with the purse, arms, armour, body and training he had there; an ironman
  starts over at bout 1. The rudis won on Ironman gives the Unbroken laurel (a hat) and Virtus
  at the trainer (a little of every ability, never lost), both for good.
- **Bread & Circuses**: the seven-day campaign (`scripts/game/circus.gd`). Every day has its
  bouts and bosses. The special bouts are in `scripts/game/bout_rules.gd`: gold rush, chariots,
  the Emperor's whims, hot potato, escorting the senator, holding the circle, and bringing back a
  head. Gold buys pots between bouts, and a god offers a blessing after each day (Fortuna spins a
  wheel). Between runs you buy ludus upgrades. There are also the Daily Games and a Hall of Fame.
- **The kill cam**: the match is recorded at 30 Hz. Every kill is scored for style (a head off,
  a throw, a punch, a giant brought down), and when the match ends the best one replays in slow
  motion, letterboxed, with a caption (`scripts/game/killcam.gd`).
- **Music**: a procedural band (frame drum, riq, drone, lyre, horn) in the Phrygian dominant. It
  has a loop for each state (menu, yard, fight, boss, victory), rendered on a thread and
  cross-faded (`scripts/autoload/music.gd`).
- **The tutorial**: eight steps in the training ring, each ticked off as soon as you do it, then a
  recruit to beat (`scripts/game/tutorial.gd`).
- **Controls**: rebindable keys (Settings → Controls) and gamepad support. The left stick walks,
  the right stick looks, and a held trigger turns the right stick into that hand. F11 is full
  screen, F12 a screenshot, F3 the frame rate in the corner (`scripts/ui/fps_meter.gd`: frames
  a second, the mean and the longest frame, the longest physics step and frame without physics,
  and the drawing and the graphics card's time in ms, and whether the C++ core is loaded: without it a
  step costs a fifth more; in a room the connection's meter with it).
  The stalls (the market, the smith, the trainer, the physician) are as easy with the keys or a
  pad as with the mouse: the arrows, the stick or the D-pad move from card to button, Enter, Space or
  the pad's A press, Esc or the pad's B leave; a bold ring shows where the keys are (not after a
  click), a stall opens on what it sells, and the place is kept when the screen is drawn again
  after a pick or a purchase (`StationKit.pickable`, `focus_key`, `tests/test_stations.gd`).
- **The Ludus yard**: a walkable hub (`scripts/game/yard.gd`, `yard_play.gd`). It has stations
  (the arena gate, the smith, the market and the mission board; press G at one), two training
  dummies that never fall, three throwing boards that score a throw, and by the gate a board
  for each fight on offer (the party's, in a room: the fight chosen at the gate). Three missions per fight pay denarii and reputation, and reputation
  earns ranks (Tiro up to Rudiarius). After a fight you come back to the yard.
- **Special arrows** (`Throwables.ARROWS`): the market's For archers tab sells six kinds one at a time, five
  to a bag: fire (alight on the man and the sand), poison (bleeds on, slows, eats like acid), frost
  (slows), blasting (a small burst where it lands, `Throwables.BLAST_ARROW`: it hurts, nowhere near a
  thunder pot, and the archer's friends and he himself are not spared), bodkin (made for armour: a plate stops a
  plain arrow, a bodkin goes through it, punching out the plate it met (one for each layer, three layers
  at most) and the one it comes out through, and wounding the man under it with three quarters of its weight through steel against a plain
  point's quarter, `pierce_armor` on the blow, `Fighter.PIERCE_*`, `Fighter.armour_pass`; it stays in the
  man it strikes, right through him, its point out of his far side and its fletching out of the near,
  `VoxelPart.stick`) and barbed (bleeds on). A number on the hotbar picks one for the bow
  (`Fighter.arrow_pick`; its slot is edged in gold and
  the HUD reads BOW: ...): every arrow he looses is that one, one out of the bag a shot, till the bag runs
  out (plain arrows again, or the bow's own gem), and the number again puts it back. The host spends
  the arrows; the pick goes to guests with the grip number of the status row (`Fighter._held_bits`: bit 0
  both hands on one haft, bit 1 the left side, the bits above the arrow's number in `Throwables.ARROW_IDS`).
- **The yard's stalls**: G at a station opens its screen over the yard, each with a live 3D view
  (it draws only while it is on the screen). The market
  (`scripts/ui/market_screen.gd`): the ware on a stand that turns with Buy and a count under it, what
  he carries of it and how many more fit (or why none: the most he can hold, or every slot taken;
  `StationKit.carry_of`, the same words at the physician's supplies), the six tabs, the trader's road of what each boss brings, the bag along the foot. The smith
  (`smith_screen.gd`): the weapon on his anvil, the hammer coming down when a job is paid for; your
  arms, his wares, his masterworks and your own designs in four lists; `armour_shop.gd` the rack with
  the gladiator, in the new look, trying each piece on, and `armour_bench.gd` the bench for armour
  of your own making. The trainer (`trainer_screen.gd`): a radar of the six abilities that grows with
  each session. The physician (`physician_screen.gd`): the man stripped, what the arena left on him
  in numbered pins on his body and in the list, the supplies for the fight; he offers only what the
  man needs (old scars alone are no hurt: no rare medicine, no elixir for them; the jar is for a bone
  broken under a scar, the elixir for a lost limb or eye, and a scratch of fewer than
  `Body.STITCH_MIN` voxels heals by itself). An old wound shows as a soft, small mark of paler skin
  that fades into it, no border, over the middle of what the blow took, and a hard blow leaves a tiny
  dent at its heart (`VoxelPart.scar_core`: a cut keeps its length, a crushed patch shrinks; at most
  four voxels, a hundredth of a part). They are drawn with
  `station_kit.gd` (cards, purse, bars, the price that rises from the purse, the red line that says
  why a deed cannot be done), `stage3d.gd` (the 3D view) and `menu_man.gd` (the player's gladiator
  for the dressing room); what is bought, mended or taught is Menu's, as it was. They fit the
  interface scale and the shape of the window (`tests/test_stations.gd`).
- **The smith and the armourer**: buy bases, mend, hone and temper. What they mend in a weapon or in
  armour is what bouts in the arena took out of it: the knocks they take in the yard (the post, a
  friend's blade) are never counted, and the next time he is built, at the gate or at a purchase,
  they are gone (`tests/test_yard.gd`: the blade and the armour both).
  A voxel forge reshapes a weapon voxel by voxel.
  In the forge, "Held in" one hand or two, and a button per hand puts it on the block you click
  (the rings are marked MAIN and OTHER). Two fists need 3 blocks (12 cm) between them, so a
  short grip (gladius, dagger, hammer) stays one-handed; a long one taken in two hands with H
  puts the other hand at the far end of the grip, so the hands never crush together mid-swing.
  The forge's bars (speed, damage, reach, against armour) have a fifth beside them, how well the
  weapon stands its blows (`ForgeLib.durability_bar`, by the rules a fight wears a weapon by:
  harder stuff wears slower and chips less, ice shatters, more blocks can lose more, a weapon made
  to last lasts). The smith's stock has bronze, a soft metal for edges, and bone, light and quick. The four tricks
  (explosive, spring, glue, magnet) are set aside for now (`ForgeLib.SET_ASIDE`): not on the anvil,
  not dealt as twists; a weapon already made with them keeps them. An Edge or a Point block faces
  away from the face it is put on; R turns the sharp block under the mouse to the next of its six
  ways (a halo marks it, `Forge.turn_ghost`), and the blocks the mirrors made of it turn with it,
  the mirrored way (`Forge.turn_face`). R and F go by where the key is as well as by what it says,
  as the forge's other keys do, so they work on any keyboard layout (`tests/test_forge.gd`).
  The forge puts no weight on a weapon: what is too heavy to lift the player finds out by trying
  it (the arm cannot raise it, it drags on the sand, and a blow's force is capped, so a great
  weight is no great blow). Only the room limits it: 1600 blocks within about 3.5 m by 1.3 by 0.5
  (`ForgeLib.GRID`, `ForgeLib.MAX_VOXELS`), so no 30 m pole. The smith's own stock is still made
  to be lifted (`Masterworks.load_of`).
  The anvil stands in a smithy (`Forge._dress_smithy`, the models from `tools/gen_voxel_art.py`):
  a room of tufa, brick and smoked plaster under a roof of beams, its floor laid in basalt round
  the anvil and in brick herringbone out to the walls; the hearth with a blade heating in its
  coals, the bellows, the charcoal, the quenching trough under the smith's tools, his own anvil
  on its stump, a rack of arms and a banner, the bench and the grindstone under the windows, a
  little shrine to Vulcan, and the way out to the yard between two braziers. It is drawing only.
  The weapon stands in the light it always stood in: the room's fires light the room alone, and
  the room throws no shadow. A wall, or the roof, is put away while the camera is out beyond it
  (backed off from a long weapon it looks into the room as into a doll's house), and a thing on
  the floor while the camera is in it or it stands before the anvil (`tests/test_forge.gd`).
- **Armour at the forge**: *taken down for now* (`Armory.plate_bench_open` is false: the forge's
  Armour tab, the smith's "Shape it plate by plate", training's and the contest's bench are not
  shown; every line of it is still here, and a test that goes in sets the switch). The forge's
  Armour tab opens the armour bench, a body part in the
  round with plates put on it voxel by voxel (where it goes and its stuff picked on the bench).
  Up to 2400 plates, and they may stand up to 6 blocks out from the body (crests, wide
  pauldrons): each one weighs. The bench marks the FRONT and the BACK. It shows the piece as the
  arena draws it, on the man himself (every plate laid where a fight lays it on his outline, in the
  new look, and a moment after the last change the piece's own shell over them: its rim, rivets and
  bands), so what is built there is what he wears.
  The main menu's forge keeps it in My designs for free; training's forge makes it free and worn
  (training also puts on any piece, bought or designed); the smith's forge makes it for denarii.
- **Modes**: training and the Arena's fights: best of three (the duel), king of the arena, the
  tournament, free for all (with a choice of bots and of the Emperor's decrees), teams (red against
  blue), forge and fight, the endless arena, monster hunt, the Emperor, king of the hill and last
  limb; and the co-op campaign, which is the campaign room's. Each fight has its own settings (how
  many rounds, how many bots, how many decrees: `scripts/game/fight_opts.gd`), set on a screen
  of its own before it begins.
- **The spectacle**: the Emperor's decrees, arena hazards, the crowd's favour and the announcer,
  and drops from the stands. A lively bout earns a small crowd bonus on the pay, in proportion
  to how much fighting the crowd saw.
- **Limbs that stay on**: the parts of a body are rigid bodies on joints, and a joint opens a
  few millimetres under load; on screen each part is drawn against the part it hangs from and
  the weapon with its hand, so nothing floats off the body until it is really cut off
  (`Fighter._seat_drawing`).
- **Every part comes apart, wherever it is struck**: a part's skin in the new look runs on over its
  joints (a man's trunk draws his neck up into the foot of his head, the slopes of his shoulders,
  the caps of his shoulders over his arms and his hips over his thighs), so a blow at a joint
  falls on the part beside it and takes only that part's voxels. The fine voxels drawn out of a
  part's own box are therefore tied to the voxels of the part beside them that they lie on
  (`FineBody._hosts`: inside that part's box, or nearer to it than to the part's own) and are
  not drawn while those voxels are gone (`FineBody.guests`, on every voxel lost or put back),
  nor once the limb or the part they lay on is cut off (`FineBody.parted`); a figure drawn anew
  with wounds on him takes the same (`FineBody.guests_anew`), and a guest mirrors the host's cut
  stump (`Match.guest_vox`). Only the drawing: every voxel, blow and wound is the game's.
  `tests/test_fine_body.gd` takes a man's neck, shoulders and hips apart and cuts him through at
  each of his nine joints, looking for skin left standing where no flesh is.
- **Every voxel a man is drawn with can be hit**: his sculpt stands out of the boxes his parts are made
  of at the shoulders (the slope from his neck to them, the deltoids), four to nine centimetres from
  every collider he has, so a blade slashed across his shoulders went through the skin untouched and a
  blow from above landed on the head's box or the arm's, never on what was drawn (the trapezius was not
  destroyed by sword blows). Skin two centimetres or more from every collider of his
  (`FineBody.SHELL_OUT`) is covered by shells: boxes of their own on the part that draws it
  (`VoxelPart.skin_shapes`), laid over it in bins of the part's fine voxel together with what lies
  between them and the flesh (`FineBody._shell_map`, worked out once a build, a part and a size) and
  kept to the skin still drawn, so they go with it as the flesh it lies on is cut away
  (`FineBody.shells_refresh`, once a frame after voxels are lost or put back). A blow on one is a blow
  on the part whose flesh the skin lies on (`VoxelPart.host_part`, read in `Combat.process_contacts`;
  an arrow's `Social.struck_part`; `Social.box_distance` reaches them for grabs and fire), which is
  where it is cut. The part's own box, weight and joints are as they were; the classic look draws
  nothing out of its boxes and has none. `tests/test_skin_shells.gd`.
- **No beast is hollow**: a beast's organs and its trunk's bones were laid by its box of voxels,
  and the body it is drawn with (its sculpt) is slimmer than that here and there, a boar's by a
  third: a third of the boar's organs lay in its drawn skin or out of its drawn body altogether,
  its ribs with them, and the first cut in its flank bared a dark hollow with a rib in it. Its
  insides are fitted to the body it is drawn with (`Beast._fit_insides`, whichever look is drawn,
  so every machine has the same beast): an organ keeps the voxels with two voxels of drawn flesh
  over them on every side (one, in a body too small or thin for that), a trunk's bones the same,
  and what they give up is plain flesh. The flesh a wound bares in a beast is drawn as flesh, red
  muscle like a man's, not in the dark of the blood run over it (`FineBody._layer`, and the same in
  the C++ core), and shows as itself in the shade of the wound too (`bare_glow` in the body's
  shader, set on a beast's wound: `FineBody._wound_mm`). `tests/test_beast_look.gd` goes over every
  beast: no organ in its drawn skin, none lost, and a club's blow on the boar's flank bares red
  flesh, no organ and no rib.
- **Achievements** (`scripts/game/achievements.gd`): fifteen, kept in the save and set on Steam
  when it runs (the list is in docs/DEMO.md).
- **Interface**: a title screen with a live fight behind it and a champion who wears your look.
  A gladiator editor (name, skin, cloth, hat, hair, beard, cape: the cape hangs from the shoulders
  in one smooth sheet that flares a little toward the hem, its tiles each laid across their
  neighbours so no gap shows, `Physique._cape_xf`; a beard is his own hair, fine voxels grown on
  his jaw, his chin and his lip, and whatever hangs from the chin, a long beard, a fork, a braid,
  grows out of the hair on it: none of it loose blocks under his head, `tools/gen_fine_head.py`,
  `tests/test_fine_head.gd`). The HUD, menus and options
  (four tabs: game, controls, graphics, sound; VSync, an FPS cap and the interface scale among
  them). The menus in one imperial look (`scripts/ui/style.gd`):
  Cinzel capitals and Alegreya Sans (both OFL, `art/fonts`) on stone plates framed in gold; the
  fights as cards with a line each on what they are.
- **Languages** (`scripts/autoload/loc.gd`): English and fifteen more, Steam's most played first
  (Simplified and Traditional Chinese, Russian, Spanish for Spain and for Latin America, Brazilian
  Portuguese, German, Japanese, French, Polish, Korean, Turkish, Italian, Ukrainian, Thai); the
  system's language unless one is picked in Options. Every line is written in English in the code
  and the data; `python3 tools/i18n_extract.py . i18n/catalog.json` lists them all, and
  `i18n/<code>.json` holds each language's lines (`tests/test_loc.gd` checks that every one keeps
  its placeholders). A line made up with names or numbers in it goes through `Loc.t()` whole.
- **Graphics**: the arena in 10 cm voxels (the floor smooth sand and packed earth with a fine
  voxel grain, raked rings, the trampled middle, damp sand by the wall, pebbles and dry grass) in a voxel world's manner (the bowl, gatehouses, the
  Emperor's box, the arcade and the props are models built by `tools/gen_voxel_art.py`), bodies,
  armour and weapons shaded by what each voxel is made of. Physics interpolation, GPU particles (blood, sparks, dust, smoke, fire, embers),
  decals for blood and scorch marks, SSAO, SSIL, SDFGI, volumetric fog and glow by quality
  level. Anti-aliasing to choose (MSAA 4x by default: the blocks' edges smooth, the rest sharp;
  or SMAA, FXAA, MSAA 2x/8x, off) and voxel corner shading (each voxel's face darkens toward the
  neighbours that shut it in, so creases and the gaps between blocks lie in shadow; on or off). A
  weapon's sharp voxels are drawn tapered, in the forge and in the fight: the outer row of an edge a
  wedge thin across the blade with a honed line, a point a tip, and a run of points (one stab
  block on another) one spike narrowing unbroken from its base to its tip (only the look; they hit
  as cubes). Every joint of a fighter is drawn whole: each limb is drawn moved to close the few
  millimetres the physics leaves open at its joint, and a block of the limb's own colour sits on
  each pivot (the deltoid at the shoulder, the elbow, hip, knee and neck) to fill the wedge two
  blocks open between them when the joint bends. An animated crowd shader, braziers, awnings, flags and the Emperor's box.
  The finer touches, drawing only: the velarium's sails over the stands on their masts and long
  banners from the arcade, rippling in the wind (`shaders/cloth.gdshader`); by day the shadows of
  clouds drifting over the arena; metal that shows the bowl round it (a reflection of the arena
  taken once); a film's colour grade (a 3D table: the shade a touch cooler, the sunlight a touch
  more gold) and, at high and ultra, a sharpening pass; a faint sweep behind a fast swing
  (`scripts/fighter/swing_trail.gd`); blood that stays on the blade or the fist that drew it and
  dries brown; footprints, a peg's round marks and the furrow of a dragged body in the sand; faces
  that blink, screw up at a blow that hurts and breathe, quicker and deeper out of breath.
  The arena's materials and life, drawing only too: stone streaked with grime, damp at its foot,
  its edges chipped; frescoes on the podium's panels (gladiators, a lion, wreaths, shields, palms)
  on plaster that flakes, cracks and carries old blood; grain and knots in the props' wood, rust on
  their iron, green on their bronze; a livelier crowd (togas in the best seats, women, children,
  vendors in the aisles, signs waved, the keen on their feet when the fight is at its height); Rome
  beyond the walls in the haze (hills, temples, roofs, an aqueduct); broken arrows, splinters,
  bones and straw by the wall, the hollow a body leaves where it falls, blood soaking into the
  sand; embers off the braziers; scratches and dents in steel, rivets on armour, stitches on dark
  leather grips; bots' faces that have lived (stubble, scars, heavy brows), sweat as a man tires,
  sand on him where he went down; the beasts' coats (a lion's mane in strands, grizzled wolves and
  boars, a goat's patches), wet noses, a sheen on scales; and a time of day for each bout, the host
  telling the guests: noon, late in the day (the sun low and gold), overcast, or dusk with the
  torches lit, with shafts of sun through the velarium and dust turning in them.
- **Audio**: procedural sounds in several takes with varied pitch, a stone-arena reverb bus, a
  crowd murmur that follows the excitement and ducks under the blows. A blow is the body's knock
  and a few hundredths of a second of shaped noise (the thwack, the slap, the wet bite); a pot of
  powder has its own boom, and the blast's blows on every part in reach are heard as that boom.
- **Multiplayer**: host-authoritative. Guests send input; the host sends snapshots, spawns, voxel
  losses and effects.

## Still to come


## The C++ voxel core (GDExtension)

The hot voxel loops run in C++ when the extension is built: greedy box merging for the
colliders (about 8× faster), the flood fill that finds the lumps a blow knocks loose, and the
searches over a part's voxels (wounds, craters, the flesh a joint hangs on, blood running down
the skin). With them the host's step is about 15–25% cheaper. The source
is in `extension/`. `scripts/voxel/greedy.gd` falls back to GDScript when it is absent, so a
plain checkout runs without it (and the editor does not complain about a missing library).
`tests/test_native.gd` checks that both give the same results, and `tools/replay_check.sh`
plays fixed 10-second fights single-threaded (16 and 6 fighters, and two of 24 with bows, two
hands, chains, giants and a dozen more creatures) and prints their fingerprints: a faster build
must print exactly the same ones as before. `tools/replay_bench.sh` times the same fights, so two
versions are compared on exactly the same work. The limbs' PD drives (`motor_rel`, `pd_relative`,
`pd_axis`, `pd_twist`) run in C++ too, giving the very floats the GDScript gives. So does the
drawing of a limb bent at a break (`lay_band`: the voxels over the break laid round the bend every
frame, for a quarter of what the GDScript cost; `lay_plates`: the armour on it and its shell with
it), and what a blow changes of the fine look (`fine_show`, `fine_wound`, `fine_colored`,
`fine_taken`: the fine voxels over the voxels knocked out, the wound's cells, the blood soaked in
round it, the piece cut off; `reshade`: the shading round the cut; `fine_swell`: a bruise's
swelling), a third of the time the blow took in the script. And what a man or a beast is made of
as he comes into a fight (`shade_all`, `local_all`, `index_cells`, `part_rows`, `shape_all`,
`fine_own`: each voxel's shading and place, the maps of a part's cells, its drawing, its fine
voxels' own colours), a tenth of the time.

What a blow has drawn is kept out of the step it lands in where it can be (a thunder pot's blast
is thirty blows in one step): the piece past a new break is set swinging in the frame after, one
limb a frame (`VoxelPart.start_due`); a part's own boxes are not written while a finer look draws
it, and are written whole if that look is taken off (`_boxes`, `boxes_back`); the plates one blow
knocks off a helmet lay his hair again once (`Fighter._tuck_end`); and what comes out of a pot (a
goat, the chickens) comes in over the frames that follow, as a wave's foes do (`Match.bring_in`).

To build it for Linux, then load it:

```bash
cd extension
git clone -b 4.4 --depth 1 https://github.com/godotengine/godot-cpp   # the 4.4 API: a library built for it loads in 4.7
pip install scons
scons platform=linux target=template_release      # or windows use_mingw=yes, or macos
cp ../native/voxel_core.gdextension.in ../native/voxel_core.gdextension
```

The release builds (GitHub Actions) build it for Windows, Linux and macOS and load it.

The Linux and Windows libraries are committed (`native/bin/`, with the `.gdextension` that loads
them), so a checkout on either runs the C++ core as it is. After changing `extension/src`, build
both again (Windows with `use_mingw=yes`) and commit them with it.

The CI workflow builds it for all three platforms before exporting.

## Multiplayer and GodotSteam

`scripts/net/net.gd` reaches GodotSteam only through `Engine.get_singleton("Steam")` and
`ClassDB`, so the project runs on stock Godot. It falls back to ENet on port 7777.

To use Steam, put **GodotSteam** in `addons/` (from the editor's Asset Store, or by hand: `tools/package.py --godotsteam <zip>`,
`docs/PACKAGING.md` says where to download it):

- **GodotSteam** (Godot 4.7; godotsteam.com): the `Steam` singleton: overlay, lobbies, rich presence, achievements, cloud.
- **The Steam multiplayer peer** (`SteamMultiplayerPeer`): carries the game's online traffic over Steam's relay. The GodotSteam
  build from the Asset Store already carries one; only if `steam_check.bat` says it is NOT FOUND is a separate extension added
  (two of them clash: Godot prints "already registered"). Without a peer, lobbies are off (`steam_check.bat` and the multiplayer
  screen say so) and joining by address still works.

Then:

1. Run with Steam open. During development the app id is 480 (Spacewar), or whatever the `SteamAppId` environment variable
   says. Outside Steam, a `steam_appid.txt` next to the program does the same; it is never put in a depot.
2. **Multiplayer → Host a Steam lobby** makes a room. Public lobbies show up in the room list (only those of this game and
   this build), a friend joins from the Steam overlay, and **Invite friends (Steam)** in the room screen opens Steam's invite
   window. A friend who accepts an invite while the game is closed starts it with `+connect_lobby <id>` and lands in the room.
   Traffic goes through Steam's relay, so no ports need opening.
3. **One build to a room.** The host's lobby and every guest's hello carry `Net.build_tag()` (version, net protocol, edition);
   a guest on another build is not listed and, if invited, told to update. Bump `Net.PROTOCOL` when what two games say to
   each other changes in a way an older game cannot follow.
4. **`steam_check.bat`** (or `-- --steam-check`) says what the game finds on this PC: the library, the Steam client, the
   multiplayer extension (with its calls and their arguments: the `peer API` line) and every call the lobbies use; READY when
   all are there. Then it runs a live test: opens a room (`create_host`), joins it as the same Steam id (`create_client`; Steam may
   not allow that, and it says so) and sends a packet. It writes `user://steam_check.txt`.

**Room size.** A room holds 8 players (the host and 7 guests, over Steam and ENet alike), and every
arena and party mode takes them all. The co-op campaign is for 4 at most (`Net.CAMPAIGN_PLAYERS`;
its bouts are made for one to four): with more in the room, its buttons (room screen, yard gate,
the arena list) are held back with the reason under them.

**Proximity voice.** Hold N to talk: everyone in the room hears you from your gladiator's head,
loud up close and gone by 22 m, and his mouth moves with your voice (a crack, open, or wide with the
teeth and tongue showing, against your own microphone's loudest), timed to when the sound comes out
of the listener's speaker. Every player can be muted from the room screen.

**What is tested, and what is not.** `run_tests.sh` plays a campaign round between two real game processes twice: over ENet
on localhost (a host and a guest by address), and over the Steam path (`tests/net_steam_host.gd` and `net_steam_guest.gd`).
In the second, Steam itself is a stand-in (`tests/steam_loopback.gd`: the folder both processes share plays Valve's servers, and
`FakePeer` carries the bytes over ENet), so everything of the game's own that sits between runs for real: the lobby and its
data, the filtered list, the join, the build check, the hello, the bout, a kick. `tests/test_net_steam.gd` holds the rest in
one process (a different build, a missing extension, a failing peer, an invite while in a room, `+connect_lobby`). `run_tests.sh` also runs the end-to-end check (`tests/e2e_run.gd`: a host and two friends play the lobby, the yard, the fights,
the endless arena, a removal and a campaign room through the game's own screens); `E2E=full sh run_tests.sh` leaves nothing of
the Arena out. What only
Steam can show is Valve's real calls and relay: one test with a second person, in `docs/MULTIPLAYER_TEST.md`.

### The two kinds of room

A room is opened for one of two things, chosen on the Multiplayer screen (`Net.room_kind`, kept in the
settings; the guest is told it as he comes in, with a `room` message from the host, and the Steam list shows it):

- **Campaign together.** The co-op campaign, bout after bout. The party's purse is the host's, so money is limited as in
  the campaign, and the gate leads to the campaign's bouts (it no longer offers the Arena's fights).
- **Arena with friends.** Fights, tournaments, teams and the endless arena. Every player has a gladiator of his own for
  the room, kept apart from the campaign's: his purse, arms, bag, armour, wounds and training (`Save.BOX_KEYS`) are read
  and written in an *arena profile* (`Save.box_begin`: one key of the save, `arena_profile`), never in the campaign's,
  and his purse has no limit (shown as an infinity). Nothing he buys, spends, wears out or loses there reaches the
  campaign, and nothing the campaign holds is spent there. Everyone fights with the arms and armour he took in the
  room's yard (the endless arena and Forge and Fight give their own). The gate opens the Arena's list of fights (the
  host's), there is no campaign, and the guest's campaign gladiator is not even sent (the host takes nothing of him from
  his hello: he comes in plain and his arena profile follows as `me`). Menu starts the sandbox when the room opens (the
  host) or when the guest is told what the room is (`Menu._box_on`), and ends it by any way out of the room;
  `Menu.start` refuses the campaign while it is on. `tests/test_room_kind.gd`.

### The room's lobby

A room opens on its lobby (`scripts/ui/lobby_screen.gd`, `LobbyScreen`, drawn by `Menu._room`), for the host and for every guest.
It has no written instructions, only what a player acts on: a card for each of the eight places (a medallion with the first letter
of the name, a crown on the host, the connection in bars and milliseconds, **Mute** and, for the host, **Remove**, which asks
twice), the places still free as dashed rings (to the host a ring is a button that gives a friend the way in: the address of this
computer, copied, or Steam's invite window), and a row of big buttons: the host's **Enter the yard** (in a campaign room **Begin
bout N**, **Into the yard** and how death is dealt with), a guest's pulsing "Waiting for the host...", and **Close the room** /
**Leave the room**. The yard is entered from it for everyone at once; a friend who comes later walks in by himself. The pause menu's
**The room** opens the same lobby over the yard (the host's **Go to the gate**). A guest knows only the host and himself, so the
host tells every guest who is in the room (`Net` "roster": id, name and round trip of each, made safe on arrival, sent when
someone comes or goes and every two seconds); `Net.room_list()` gives either side the same list, and the lobby follows it by
itself. `tests/test_lobby.gd`; the whole of it, with two games, in `tests/e2e_*.gd`.

### Friends in the yard

The yard is open between friends: a blade there hurts, and a man killed is up again by the gate three seconds later
(`Match.respawn_player`: the body he came into the yard with, his kit, full of blood; nobody bleeds there). Two rules go with it
(`tests/test_yard.gd`, and in the end-to-end run). **A man at a stall cannot be hurt**: while a stall's menu is open over the yard
(the market, the smith and its forge, the physician, the trainer, the gate; not the pause menu's screens) his fighter is
`untouchable` (`Fighter.apply_hit` takes no blow, blast, arrow or fall; `Combat._blow` lets the blade meet him as a wall). The
host's own man is marked by the menu at once (`Menu._process`); a guest says so with a "stall" message when it changes and every
second after, and the host lets it lapse `Match.STALL_TTL` (3 s) after the last word, so that a game that is lost does not leave
him untouchable. Everyone sees it as the name above a man turned gold and faint (the flag rides in the grip number of his status).
**R** in the yard (the key that restarts a fight alone) puts a man back on his feet by the gate whole, with the body and the kit he
came in with, at once if he is down, every `Match.RESPAWN_COOLDOWN` (10 s) and never at a stall; a guest's R is a "respawn"
message, and the host keeps the clock. (In a campaign room it is the body he came into the yard with: the wounds of the last bout
are the physician's, not free.)

### Rounds, bots and decrees

Every Arena fight is set on its own screen (`scripts/game/fight_opts.gd`; the host's last choice per fight is kept in the
settings under `fight_opts`): the **rounds** (`scripts/game/series.gd`: a match over several bouts, most rounds wins, a
level score is settled by up to two deciding rounds; the duel's best-of, the king's reign and the hunt's waves have their
own meaning), the **bots** beside the players (none to seven; the team fights and the tournament may fill their sides and
bracket), and, for the free-for-all, the number of the Emperor's **decrees** (none, one, three: it is where chaos went).
The screen says what the sand will hold ("You and 2 friends, with 3 bots"); a room of eight and the bots with them never
pass 8 fighters (`FightOpts.MAX_FIGHTERS`: one man with seven bots, a room of eight with none). The host keeps the score between bouts (`Menu._series_after`) and tells the
guests (`series` message, read back made safe: `Series.clean`); a guest is also told the fight's state line (the wave, the
round, the hill's leader) by the host (`fstat`).

### Team fights: the circles

A team fight begins in the yard (`scripts/game/team_setup.gd`, `YardPlay.begin_teams`): two circles on the sand, red and
blue, each player walks into the one he plays for, and the host begins with E when everybody stands in one; a team with
nobody in it is filled with bots. Everyone reads who stands in each circle and who is still out (`teams` message).

### The tournament

One-on-one bouts, single elimination (`scripts/game/tourney.gd`, `Menu._tournament*`): the players and the bots that
fill the bracket are drawn in pairs, the pair fights a bout (a duel, over as many rounds as the host set) while the room
watches, the winner goes on, until one is crowned. A bout of two bots is settled unseen; a player who leaves forfeits his.

### The endless arena

Alone from the main menu, or with friends in an Arena room (rules in `scripts/game/endless.gd`, the screens in `menu.gd`'s
`_endless*`). With friends: the host sets the kit for the whole room; the waves grow with the party (`Endless.plan` takes
the number of players); each wave beaten, the fallen (and those at death's door) stand up again, everyone is patched up
and picks a reward of his own on his own screen (`endless_offer` to him, `endless_pick` back, `endless_done` to close the
screens; a pick not made in 25 s is the first), and the next wave is called when all have picked; the run is over when
everybody is down, and it is nobody's lone best wave or leaderboard entry. `tests/test_endless_party.gd`, and
`tests/net_party_host.gd` / `net_party_guest.gd` play it between two real processes.

Alone:

1. Before the run: a weapon for each hand (off the rack, or forged there, free), ready-made
   armour, and up to three kinds of pot, two of each.
2. Wave after wave of men and beasts, drawn at random from the campaign's foes, more of them and
   harder as the waves go. Every fifth wave a great foe walks in (the campaign's bosses, in the
   campaign's order). A man of the waves takes up arms at random: a blade and a shield, a blade
   in each hand, a great two-hander, or a blade alone, better ones as the waves go.
3. A wave beaten: some blood and all the breath back, the bleeding stopped, and one of three
   rewards picked (bind the wounds, mend the weapons, two pots, a new weapon, a piece of armour).
   The arena waits while the player picks.
4. The run ends when the player falls. The best wave is kept. *Today's challenge* draws the same
   waves for everyone on the same day (UTC). With Steam, the waves beaten go on a leaderboard
   (`endless_best`, or `endless_YYYYMMDD` for the day's challenge).

### Forge and Fight

A room's own game, under **The Arena → The melee** (rules in `scripts/game/forge_fight.gd`, the
screens in `menu.gd`'s `_ff_*`):

1. The host sets the times: the weapons (1 to 10 minutes), the armour (none, or 1 to 5) and a
   limit on the fight (none, or 2 to 10 minutes).
2. Everyone forges at once, the clock over the forge. Each hand gets a forged weapon, or the off
   hand a plain round shield. When the time is up, whatever is on the anvil is taken as it stands,
   if it can be held and carried.
3. Then the armour bench, with the same clock. A piece counts once it is made. (While the
   bench is down, `Armory.plate_bench_open`, this step is skipped: no time is asked for it.)
4. All fight to the death with what they made. At the time limit, the one standing with the most
   blood left wins.

Every kit is checked on the host like any loadout. Only forged weapons, the round shield and the
player's own armour come through. A ready-made weapon or a piece off the armourer's rack is
dropped, and a weapon that does not hold up leaves the hand empty.

### Playing safely

- **Encrypted.** Steam lobbies use Steam's encrypted networking, and players' addresses stay
  hidden behind Steam's relays. A game joined by address is encrypted with DTLS: the host makes
  a key for the session, and a game that does not speak it cannot join.
- **Host-authoritative.** Guests send only their input. The host runs the physics, so a modified
  game cannot move its fighter faster, hit harder or teleport.
- **A short list of what guests may say.** Hello, input, voice, ping, the purse, the Forge and Fight kit, the
  physician, the gate's pick, the Emperor's vote and the endless arena's reward pick are allowed. Anything else from a guest (a snapshot, a spawn, a banner) is dropped.
  Guests talk only to the host, never to each other through him.
- **Everything from a guest is checked.**
  - Names: no markup, 24 letters at most.
  - Forged weapons: only what the forge can make (its grid, its materials, its block limit).
  - Armour, kits, bodies and input: no NaNs, every value clamped.
  - Volume: more than 240 messages a second from one guest are dropped, and a second hello is
    ignored.
- **The shared purse.** A guest adds no more than he spent, what his fights' missions paid, and a
  little for what he brought to sell.
- **Muting and removal.** Every player can be muted, and the host can remove one (room screen
  or pause menu). A removed player cannot rejoin that room.
- **Privacy.** Voice is push-to-talk (N). Steam lobbies can be friends-only. Nothing personal is
  sent: only the gladiator's name, gear and body, and voice while N is held.
- **What is not covered.** A guest's own gear and wounds are kept by his own game and only
  checked for being makeable. Someone who edits his own game can give his own fighter gear he
  never paid for, but nothing of anyone else's.

`tests/test_net_safety.gd` covers the checks. `tests/net_host.gd`/`net_guest.gd` play a bout over
DTLS and send a tone through the proximity voice both ways: it must come through and be heard from
the speaker's gladiator's head. With `KICK=1`
remove a guest and see him turned away again; with `NO_DTLS=1` on the guest, an unencrypted game
is refused.

### Load test

`sh tools/net_load.sh [guests] [seconds] [stage]` (default 7 guests, a full room of 8) starts a
host and that many guests as headless games over ENet on localhost, plays a campaign bout and
reports, each second, how many physics steps the host keeps up (of 120), its CPU, what it sends
(by message type) and the size of a snapshot; each guest says how often snapshots came and the
longest wait between two. All of them share the one machine's CPU, so the times are worse than in
a real game, where each player has a computer of his own; the bytes are the same.

`tools/net_load.sh` takes more: `NET_MODE=ffa|teams|hill|lastLimb|king` plays that arena mode (8 players: free-for-all is 11
fighters with its 3 bots, teams and pvp 8), `HOST_CPUS=0 GUEST_CPUS=1-3` pins the host to its own core and the guests to the
others (so the guests' work does not take the host's time, as in a real room), `NET_LAG=100 NET_LOSS=3` makes every line poor,
`NET_NOSTAGE=1` builds fighters in one frame as before. The host reports how long its physics steps took one after another
(median, 99th, worst, how many over a frame at 60 and at 30 and over a tenth of a second: a stall is a long step, not a high
mean), each guest the same for its own steps and how long it was held up taking in each kind of message. Measured here (a
4-vCPU 2.1 GHz Xeon, the host on one core of it, about half of a gaming PC's core): 8 players in a free-for-all, 11 fighters:
steps 9.1-9.7 ms median, 18-19 ms at the 99th, 29-37 ms worst, none over 100 ms; 95-103 of 120 steps a second at 100% of that
core; 500 KB/s up from the host (70 KB/s a guest); a guest 25-28% of a core without drawing, snapshots 28 ms apart at the 95th.
Teams, 8 players, 100 ms and 3% loss: 8.2 ms median, 114 steps, 21-23 ms apart. A guest used to build every fighter the host
spawned in the frame the message came in (a man 130-440 ms, the eleven of a free-for-all 1.6-2.4 s of a stopped game); it now
builds them one at a time over the frames (`Match.guest_staging`: his own man at once, what the host says of the others meanwhile
kept and said again, a spawn the host takes back before its turn never built), as the host does for a wave, and a player who
joins is built over the frames on the host too.

After the guest-delay work (a player's row every frame, his own man walked ahead: the section on the delay a guest feels), the same
room on the same machine (`NET_MODE=ffa HOST_CPUS=0 GUEST_CPUS=1-3 sh tools/net_load.sh 7 25`, the old numbers from f8b1707 in
brackets): 8 players and 3 bots, 11 fighters: a step 10.5 ms median (9.7), 21 ms at the 99th (22), 92 of 120 steps a second (95);
489 KB/s up from the host, 70 a guest (462, 66); a snapshot 4073 B (3765); a guest 29-30% of a core (28-29%), snapshots 228 a
second, 33-34 ms apart at the 95th (32-33). Teams, 8 players, 100 ms and 3% loss: 8.1 ms median (8.6), 114 steps a second (106), 483
KB/s (459), a guest 25-26% of a core (24-25%). That is about 5-8% more on the wire, within the run-to-run spread of the host's
steps, and a point more of a guest's CPU, for a guest's own man answering in 32 ms instead of 115.

A room keeps time (`Net.steps_cap`, `Net._pace`). The engine runs at most 4 physics steps in a frame and lets the
game fall behind the clock beyond that, so below 30 frames a second a game runs in slow motion; alone that stops a
heavy moment snowballing, in a room it made the host's world, which every guest draws, run slow for all of them (two
windows on one computer, one behind the other, or a first-time shader build: with frames of 45 ms the guest saw the
host at 68 of 120 steps and 22 snapshots a second, not 40). A room lets a frame run as many steps as fit in 50 ms of
physics at the cost one step has been taking (at most 12; with steps dearer than 8 ms, the engine's 4, as more of them
would only slow the picture), and F3 shows the frames a second of each side with the steps.

A room of windows of one computer (`Net.local_room`: the guest joined 127.0.0.1 or this computer's own address, or the
host has a guest that did) lowers the picture of both windows (`Menu.room_scale`: at most 0.7 of the resolution,
`Menu.room_fps`: at most 60 frames a second) while the room is open, so that two windows on one graphics card both keep
up; a room between computers is never touched, and the picture comes back when the room closes. When a snapshot is late
a guest's bodies go on the way they were going for up to 50 ms, easing to a stop (`Match.EXTRAP`, `Match.puppet_weight`),
instead of standing still until it comes. The connection's meter (NetMeter) opens by itself with the frame rate's
whenever a room is open.

ENet's packet throttle is off: whenever the round trip wobbled it threw away unreliable packets on
purpose, up to a quarter of the voice and the snapshots on a jittery line. Without it a guest gets
every snapshot the line carries (about 12% more of them in the load test, the longest wait down from
over 300 ms to about 220 ms) and the voice whole.

The delay a guest feels (his hands to his man moving on his own screen) is measured by `tests/net_lat_host.gd` +
`net_lat_guest.gd` (two games held to 60 frames a second in the host's yard; the guest presses forward and times it; F3's
ping is only the line): 115 ms, of which the host's own physics answer is about 21. Three things were in the rest.
The engine reads the line in the idle part of a frame, after that frame's physics steps, so a guest's hands and the host's
snapshots were taken up a whole frame later, on each side of the round trip: `Net._physics_process` now reads it at the start
of every physics step (before the game's own: 81 ms). The players' fighters went out every third step, which at 60 frames a
second is one frame then two (a gap of 17 ms then 33 ms): they now go from `Match._send_player_rows`, once a frame after the
last step, at most 60 a second, while the room is not full (the others, and a full room, as before); a guest takes gaps as
short as two steps (`Match.MIN_SNAP_GAP`) and his hands go every frame (`Match.INPUT_EVERY`; a frame a hair short of a
sixtieth was left out). Now 64 ms at 60 frames a second, 66 at 45, 62 at 144, for about 10% more on the wire and 1-2% more of
a guest's CPU.

What was left was the round trip itself: the keys, the host's step, the snapshot back; with a line of 100 ms it was 100 ms more.
A guest's own man is therefore walked ahead of the host's word, on a model of the host's walking (`MovePredictor`, DOM-free;
`Match._predict_own`, `_reconcile_own`, `_show_own`). Every input goes out with a number (7 bits above the flags of
`PlayerInput.pack`); the host sends in his snapshot row (its last element, 6 numbers: `Match.snapshot`) the number it had got
to, for how many of its steps it had walked by that input, where his torso was and how fast it went, which way he faces and
his pace (`Fighter.walk_pace`: his speed over the plain walk's or run's, 0 when he is not on his own legs: down, held, in
the air, hopping). The guest puts the model there and walks it on through the inputs sent since (the log of what it sent),
up to now, and shows his man where the model has him: all his bodies by the same along-the-sand shift over the host's picture
of him, a limb he lost where it fell. The model is his velocity closing on what the keys ask at 40 a second (measured on the
host's own walking with `tests/walkresp.gd`: 63% of the pace in 25-33 ms); a host that does not agree (a wall, another man:
the host's velocity along the keys' way is under what they ask, after they have been held a tenth of a second) is believed,
and the model's walk is cut by as much along that way, so a man pushing on a wall is not shown into it; what the host's
word moves the picture by is taken up over 60 ms, not in a jump, and when he cannot walk (down, held) the shift is eased out
over 0.15 s. The guest's hands are also read in the first physics step of each frame (`Match._send_guest_input`), not in the
frame's process after the steps: the keys were taken a frame after the steps that could walk his man by them. Together:
32 ms at 60 frames a second, and the same with a pretend 30 ms each way (`NET_LAG=30`; ping about 100 ms), where it was 165 ms
without. His man is within 1-3 mm of where the host has him once the keys are let go, never steps back while he walks, and runs
on at most a hand's breadth into a wall (`tests/test_move_predictor.gd`, `tests/test_predict_own.gd`). `run_tests.sh` runs the
probe plain and with the lag ("net (delay)", the medians may not pass 55 and 60 ms). The others (the host's man, bots, other
guests) are the host's picture a trip and a snapshot behind, drawn on by their pace (see "The others ahead" below).

What the host sees of the guest's man (the probes stamp the press and the move with the system clock; `python3 tools/lat_join.py
host.log guest.log` joins them): from the key going down on the guest to his man 2 cm on in the host's game, 58 ms before,
49 ms now (the keys are read a frame earlier; the rest is the host's step and the wait for its next frame). `NET_HAND=12` on the
guest times a swing as well (his hand's mark across the pane to his weapon 3 cm on): the host's own arm takes 34 ms of that, and
about 66-82 ms in all on his screen. The hand is not walked ahead, as the body is.

**No host advantage** (user: in a fight of people against each other the host must have none). A guest's hands reach the host's physics
a trip of the line after his keys, the host's at once: measured in the host's physics (`tools/lat_join.py`; `NET_OWN=12` makes the host's
own man swing the way the guest's is made to), a guest's swing starts 12 / 36 / 61 ms after the host's own at a ping of 14 / 51 / 86 ms
(`NET_LAG` 0 / 15 / 30 ms each way). In a fight of people against each other (two of them on different sides: a free for all, teams,
duels, the tournament, the party modes; not the yard, not the campaign's bouts, where the people are one side against the foes) every
man's hands are held on the host (`Match._fair_active`, `_fair_update`, `_fair_input` over `InputDelay`, DOM-free): the physics acts on
the input of so many ticks ago. The host's wait is the slowest friend's trip one way (half the round trip each guest measures and tells
the host about once a second, `Net.guest_pings`) and 4 ms for the line's wobble, 90 ms at most; each guest's is what is left of it
after his own trip. A press (a jump, a kick, a grab, an item) rides with its tick: none is lost when the wait is made shorter, none
repeated when it is made longer (`tests/test_input_delay.gd`). Now the guest's swing is -5 / +3 / +5 ms from the host's own, and
`run_tests.sh` ("net (fair hands)") keeps it within 15 ms. The price is the host's own hands, 18 / 32 / 49 ms slower in such a fight
(his swing 42 -> 60, 44 -> 76, 44 -> 93 ms in the physics); the guests' are as they were. What the wait cannot take away is the
view: the host sees a guest's blow start as it starts, a guest sees the host's a trip and a snapshot later (about 40-60 ms at a ping of 60-100).

**The others ahead.** On a guest's screen the others (men, foes, beasts, giants) are the host's picture a trip and a snapshot behind (57 ms
at 15 ms each way, 75 at 30), and a blow of his lands a trip after he made it: against a man walking at 2.5 m/s the picture is 14-18 cm
off by then, against a charging beast more. `Lead` (DOM-free; `Match._lead_for`, in `apply_snapshot`) keeps the pace of each other
fighter's torso from the rows of his snapshots, and every body of his (and what he holds) is drawn on from where the snapshot has it by
that pace over the round trip and the snapshot's wait, 0.9 of it, along the sand, at most 30 cm, coming and going by easing (at most
2.5 m/s of change); not for a man who is down, rising or dead, a limb he lost, or the guest's own man (`MovePredictor` has him).
Measured with the host's man walking to and fro (`NET_TGT=25 NET_TGT_ONLY=15`, `tools/lat_tgt.py`): the picture 57 -> 0 ms behind
and 14 -> 5 cm off from where a blow lands at 15 ms each way, 75 -> 0 ms and 18 -> 7 cm at 30 ms each way (`run_tests.sh` "net (the
others ahead)"). The price: a man who stops is drawn on past his stop, 9 cm on average (14 cm at 30 ms each way), and eased back in
a tenth of a second. The pace is measured from the rows' arrival times, which a line and the guest's own steps jitter: a short gap
between two rows weighs less in it (else the jitter makes it 20-30% too fast), a gap of over 80 ms (a stall) is left out, and rows that
come together after a stall do not make him run a whole stall's way (`tests/test_lead.gd`). `Match.lead_on` switches it off. Not done: the hand and the weapon (a man's swing is shown late as it was, and a
guest's own weapon is the host's picture of it, 80-180 ms after his hand moved).

What goes on the wire: each fighter's bodies in 14 bytes each (int16s, 2 mm), his state 8 times a
second, the dead once a second, and in a full room (4 guests or more, or more than 10 fighters) the
enemies at half the rate of the players. Measured: about 1.6 Mbit/s up from the host for 4
players and 8 fighters, about 7 Mbit/s for 8 players and 16 fighters. The host simulates every
fighter: about 1.5 ms of a physics step each on the test machine, so a full room with many
enemies asks a strong CPU of the host.

### The yard with a full room (#298)

The host plays every man in the yard, at 120 steps a second, and a man costs a step about a millisecond (armoured and active; 0.7 bare):
eight friends in the yard asked for more than the 8.3 ms a step has. F3 then says "keeps up 57/120", the world runs in slow motion for
everybody, and a frame holds up to four steps (`Net.steps_cap`) so the picture drops to 14 frames a second. Two things are spared in the
Ludus yard now, on the host only (a guest draws what he is told), and neither touches a fight, the campaign's bouts or the arena modes:

- **A man who stands sleeps** (`Match._human_idle`; the yard's keepers have `_stands_idle`). A player's man (his own, a friend's) who has
  had nothing ordered of him for half a second (no key, no button or press of the hands, the marks of his hands and his view where they were),
  who stands on his feet with no man within 2.5 m, and in whom nothing is still running down or building up (`Fighter.at_ease`: his breath
  full, nothing bleeding, burning or stinging, no daze, drunkenness, net, bees, shove, kick or jump, no throw or reach under way; looked
  at once, after the half second, not every step) is put to sleep where he stands: his bodies sleep and `control` is not called. He is awake
  in the very step a key, his view or a hand moves, a man comes within 2.5 m, a blow touches him, a hold takes him, or anything of what
  he has changes without the physics saying so (his blood, pain, breath, hit points, a fire, a wound), and one killed asleep falls
  (`tests/test_yard_rest.gd`).
- **The arms of a man at rest** (`Fighter._arms_unordered`, `_arms_still`; the Match says `arm_lod_ok`). A man walking about with his hands
  unordered for a fifth of a second (no button or press, the marks of the hands where they were, nothing thrown, thrust, grabbed or held),
  whose forearms and weapon lie all but still on his trunk, has the drive of the arm with no weapon in it (a shield's, an empty one's) and
  the push of both arms out of the trunk and the head seen to every other step, with the time of both. The weapon arm is driven every step
  (at half the rate it came to rest a hand's breadth off). The step anything orders the arms or strikes them, all is seen to every step.
  A guard held is held: hands within 1 cm and a blade's tip within 2 of where they lie at the full rate.

`Match.human_idle_on` and `Fighter.arm_lod_on` switch the two off; off, the build plays the yard and the 40 fights of `tools/replay_check.sh`
to the last bit as before (`sh tools/lobby_load.sh` prints a fingerprint of every body; the same one with both off as on the build before).
`tools/lobby_load.sh [men] [idle|walk|brawl] [seconds]` puts N men in the yard on one physics thread and prints what a step costs;
`tools/friends_load.sh [friends] [seconds]` does it with a real room: friends' games (FriendPilot) join the host's yard and wander it,
and the host reports its scripts' steps, how many men sleep and how many arm turns were let rest (those games take the host's CPU, as
they would not on a room of computers, and the friends do different things from run to run: a sanity check, not a figure).

What a step costs with eight men in the yard (this machine, a 2.1 GHz Xeon core, release build, medians of three; off -> on):

| the eight | before | after |
|---|---|---|
| standing | 8.20 ms | 1.18 ms |
| walking about, armoured | 8.53 ms | 7.70 ms |
| walking about, bare | 7.15 ms | 6.17 ms |
| four walking about | 4.62 ms | 3.51 ms |
| bots fighting (only the host's own idle man sleeps) | 11.28 ms | 9.81 ms |

Seven friends in a real room: the host's scripts took 8.0 and 8.3 ms a step with both off and 7.8 and 3.5 with them on (1.3-1.4 of the
eight men asleep on average, 4000-7000 arm turns let rest a run).

What is not solved: men who fight, or walk about with their hands busy, cost what they cost: about a millisecond a step each, and eight of
them are 9-11 ms here, more than the 8.3 a step has, so the host keeps up 88-100 of 120 steps. A frame must fit `120 x step + FPS x
the frame's own work <= 1000 ms`; with a step of 9 ms and the frame's own work (F3: "frame without physics") 16 ms that is about 14 frames
a second, what F3 showed in an eight-player room. F3's "physics" figure is the longest step of the last second, not the mean. The next
things to spare are the arm drive of a man who fights (`_drive_arm`, `_keep_arm_out`, `_clear_body`, `_elbow_clear` are over half of
`control`, which is 86% of a step: a native version, to the bit as `drive.cpp` is) and the frame's own work.

### Trying an online game on one machine

No command line: put the Godot 4.7.2 exe in the game's folder and double-click
**`multiplayer_e2e.bat`** (Windows; `sh tools/mp_e2e.sh` elsewhere) and the game plays all of multiplayer by itself, three
games (a host and two friends) through its own screens: the lobby, the yard, the smith, every fight of the Arena, the endless
arena, a removal, a campaign room (`tests/e2e_run.gd`, `e2e_host.gd`, `e2e_guest.gd`, `e2e_kit.gd`); each check is shown as it
passes and the list is written to `e2e_report.txt`. To play it yourself double-click **`multiplayer_test.bat`**; it opens the
windows and asks what to try. The steps and what to check are in `docs/MULTIPLAYER_TEST.md`. The windows open small (`-- --keep-window` keeps the
window the engine's `--position`/`--resolution` made, instead of the saved display mode, which is full
screen unless the player chose otherwise: two full-screen windows share one graphics card and the one
behind draws a fraction of the frames). The long way:

`tools/mp_local.sh` (Linux/macOS) or `tools/mp_local.bat` (Windows, after
`set GODOT=D:\godot\Godot_v4.7.2-stable_win64.exe`) opens a host window and a guest window over ENet: the host on its
room's lobby (a card for each player), the guest joining it, and a press of Enter the yard walks them into the yard, the
place where the host picks the next bout at the gate (`--yard` goes in at once). With `BOT=1`
the guests are played by bots, so you can host, play and watch a real online bout alone. `LAG=120
LOSS=3` holds every incoming message back 120 ms (±30) and drops 3% of the unreliable ones, a
pretend poor connection to see how the game feels at that latency. The same flags work on a plain
run: `godot --path . -- --host`, `--join <address>`, `--name <name>`, `--bot`, `--lag 120 --loss 3`.

### Friends who are not there: trying a room by yourself

To try multiplayer by hand with no one to play with, double-click **`multiplayer_playtest.bat`** (Windows; `sh tools/mp_playtest.sh`
elsewhere). One window opens, yours, on an Arena room's lobby (`ROOM=campaign` for a campaign room, `YARD=1` to go straight
into the yard), with a small strip in its top corner: **F6** (or the **+** button) a friend comes in, **F7** (−) the newest one
says goodbye and goes, **F8** (×) the newest one's line is cut at once, as a game that crashes or a cable pulled, **F9** (~) the friends
who come now come over a poor line (120 ms each way, 3% lost). Each friend is a game of this project of his own (`scripts/net/friends.gd`
opens them with no window, `-- --friend --join 127.0.0.1 --port N --persona I`) that joins the room by its address as a friend's
game does, with a name, arms and a face of his own (seven personas, Brutus, Cassia, Decimus...), and plays one (`friend_pilot.gd`):
in the yard he wanders, goes up to the stalls and into them, now and then picks a quarrel with whoever is near; in a fight a bot plays
his fighter; the endless arena's rewards, the rudis and the forge's ready he answers after a moment's thought. What he does is only
what a player's hands and the game's own calls do, so what you see is what a friend's game would show you. Up to seven at once.
`tests/test_friends.gd` is the table and the strip; `tests/friend_probe.gd` (in `run_tests.sh`, "net (friends)") opens a room, brings
two in with the strip's own button and key, and looks at all of the above, a free for all and a leaving included.

## Exporting

`tools/package.py` (on Windows, double-click `tools\package.bat`) exports the game and packs it two ways, for the demo
and for the full game: for **Steam** (`dist/steam/`: the files of each depot, the SteamPipe scripts and `upload.bat`) and
as a download for **people without Steam** (`dist/standalone/`: a zip, a tar.gz and a Windows installer; these builds never
start Steam). It needs Godot 4.7 with its export templates (`--install-templates` fetches them), and for the Windows
installer NSIS (fetched for you on Windows, `--install-nsis`). `docs/PACKAGING.md` has the whole story: the ids to fill in,
the upload, what it checks, what is not done. `docs/RELEASE_HE.md` (in Hebrew) is the road from a working build to a
release, step by step: the Steamworks account, tax, the store page, review, Next Fest, launch.

The game opens with its own picture, not Godot's logo: `art/splash.png` is the boot splash (`project.godot`:
`application/boot_splash/*`), and `scripts/ui/intro.gd` takes it up as the first scene and brings it to life for two
seconds and a half (the swords strike, a gleam runs across the logo, embers drift up; any key skips it) while the menu
is built behind its last frame (`tests/test_intro.gd`; not played in the tests or probes, headless, or with
`-- --no-intro`). The `.exe`'s icon, the installer's pictures and these pieces are made by `tools/make_app_icon.py`.

`.github/workflows/build.yml` does it for Windows, Linux and macOS. Run **Builds** from the repository's Actions tab, or
push a tag such as `v1.0`; the packages appear as downloads on the run page.

To export by hand, install the export templates for 4.7.2 (Editor → Manage Export Templates), then run this
(`export_presets.cfg` has twelve presets: full game and demo × Windows, Linux, macOS × Steam and standalone):

```bash
godot --headless --path . --export-release "Windows Desktop" build/steam/full/windows/WRECKSMITH.exe
```

The macOS build is not signed. On a Mac, right-click it and choose Open the first time.

For a Steam build, ship both Steam extensions' `addons/` folders (GodotSteam brings the `steam_api` library);
`tools/package.py --godotsteam <GodotSteam zip> <multiplayer peer zip>` puts them in (`--require-steam-lib` stops the run when
one is missing), and the downloads without Steam leave `addons/` out. The packager's SteamPipe scripts upload the result.
Every package carries `THIRD_PARTY_LICENSES.txt`, which the game writes itself (the menu's **Credits** screen shows the same
text); the line of the copyright holder (Edella Studios) is in `data/legal.json`, and from there in the installer and the downloads' README.

Store screenshots: `xvfb-run -s "-screen 0 1920x1080x24" godot --rendering-driver vulkan
--resolution 1920x1080 --path . -- --probe steamshots` with `SHOT_DIR` set saves 1920×1080
shots of the title screen, the gladiator editor and six fights.
