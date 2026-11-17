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
  (`Throwables.BOMB_BLAST`).
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
- **Wrestling**: grabs, shoves, trips, and the giant's lift and throw. A kick at a man down at
  one's feet (lying, sitting, on his knees) is a stamp: the knee comes up and the foot is driven
  down onto him, where he is while the knee is up (`tests/stompprobe.gd`). A giant's blows vary:
  a chop from above, sweeps from either side, a low sweep at the legs and a thrust. A man it
  has knocked down it goes on striking; it does not stand off and watch him. Now and then it
  stoops to him instead, its hand right down on him, takes hold of him where he lies and lifts
  him to slam or throw him (`Bot.GRAB_DOWN_RATE`, `tests/giantpickprobe.gd`). A giant's hand
  closes on the part of the man it touches and he is drawn the last of the way into the fist
  (`Social._close_in`: the pin joint holds the two as they stand, so a man taken from a hand's
  breadth off hung that far under the fist); while he is held the arm that holds him does not
  strike him, nor for a moment after the throw the arm that threw him: the hold, the slam and the
  throw do the harm, and what a thrown man lands on does the rest (`Social._throw_land`).
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
  off its wind-up), and gathers it back when let be. The manticore stings a man at its flank and
  flings poisoned spikes from its tail at one out of its reach, after raising the tail with a roar.
  The enemy's health plate reaches nothing when the fight with him is over, whatever ends it:
  head, trunk, blood, a broken neck, the brain or a torn heart, or down and spent.
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
  tenth more than its list (`Match.PAY_RAISE`, `Match.paid`); what is counted in the list's pay,
  the physician's prices, stays where it was (`Body.price_unit`).
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
  and the host leads the party to the one most of them picked (his own when as many pick two).
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
  and the drawing and the graphics card's time in ms; in a room the connection's meter with it).
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
  thunder pot, and the archer's friends and he himself are not spared), bodkin (goes through up to three
  men, slower and weaker for each, `pierce` in `Items.TYPES`, and stays in the last) and barbed (bleeds
  on). A number on the hotbar picks one for the bow (`Fighter.arrow_pick`; its slot is edged in gold and
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
- **The smith**: buy bases, mend, hone and temper. A voxel forge reshapes a weapon voxel by voxel.
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
- **Modes**: training and 15 fight and party modes (duel, best of three, free for all, chaos, co-op,
  gauntlet, monster hunt, teams, king of the arena, the Emperor, king of the hill, last limb,
  head football, players' brawl, the endless arena).
- **The spectacle**: the Emperor's decrees, arena hazards, the crowd's favour and the announcer,
  and drops from the stands. A lively bout earns a small crowd bonus on the pay, in proportion
  to how much fighting the crowd saw.
- **Limbs that stay on**: the parts of a body are rigid bodies on joints, and a joint opens a
  few millimetres under load; on screen each part is drawn against the part it hangs from and
  the weapon with its hand, so nothing floats off the body until it is really cut off
  (`Fighter._seat_drawing`).
- **Achievements** (`scripts/game/achievements.gd`): fifteen, kept in the save and set on Steam
  when it runs (the list is in docs/DEMO.md).
- **Interface**: a title screen with a live fight behind it and a champion who wears your look.
  A gladiator editor (name, skin, cloth, hat, hair, beard, cape: the cape hangs from the shoulders
  in one smooth sheet that flares a little toward the hem, its tiles each laid across their
  neighbours so no gap shows, `Physique._cape_xf`). The HUD, menus and options
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

To use Steam:

1. Install the **GodotSteam GDExtension** for Godot 4.7 (GodotSteam 4.22 or later) from the Asset Library or godotsteam.com,
   or use the prebuilt GodotSteam editor.
2. Run with Steam open. During development the app id is 480 (Spacewar), or whatever the
   `SteamAppId` environment variable says. For release, put your own app id there and in
   `steam_appid.txt` next to the executable.
3. **Multiplayer → Host a Steam lobby** creates a lobby. Public lobbies show up in the room list,
   and friends can join from the Steam overlay. Traffic goes through Steam's relay, so no ports
   need opening.

**Room size.** A room holds 8 players (the host and 7 guests, over Steam and ENet alike), and every
arena and party mode takes them all. The co-op campaign is for 4 at most (`Net.CAMPAIGN_PLAYERS`;
its bouts are made for one to four): with more in the room, its buttons (room screen, yard gate,
the arena list) are held back with the reason under them.

**Proximity voice.** Hold N to talk: everyone in the room hears you from your gladiator's head,
loud up close and gone by 22 m, and his mouth moves with your voice (a crack, open, or wide with the
teeth and tongue showing, against your own microphone's loudest), timed to when the sound comes out
of the listener's speaker. Every player can be muted from the room screen.

The Steam path was written against the GodotSteam 4.x API. It is untested here because the test
machine has no Steam client. The ENet path is covered by `run_tests.sh`: a host and a guest
process play a campaign round over localhost, the guest's fighter played by a bot.

### The endless arena

Alone, from the main menu (rules in `scripts/game/endless.gd`, the screens in `menu.gd`'s
`_endless*`):

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
- **A short list of what guests may say.** Hello, input, voice, ping, the purse, the Forge and Fight kit and the
  physician are allowed. Anything else from a guest (a snapshot, a spawn, a banner) is dropped.
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

ENet's packet throttle is off: whenever the round trip wobbled it threw away unreliable packets on
purpose, up to a quarter of the voice and the snapshots on a jittery line. Without it a guest gets
every snapshot the line carries (about 12% more of them in the load test, the longest wait down from
over 300 ms to about 220 ms) and the voice whole.

What goes on the wire: each fighter's bodies in 14 bytes each (int16s, 2 mm), his state 8 times a
second, the dead once a second, and in a full room (4 guests or more, or more than 10 fighters) the
enemies at half the rate of the players. Measured: about 1.6 Mbit/s up from the host for 4
players and 8 fighters, about 7 Mbit/s for 8 players and 16 fighters. The host simulates every
fighter: about 1.5 ms of a physics step each on the test machine, so a full room with many
enemies asks a strong CPU of the host.

### Trying an online game on one machine

No command line: put the Godot 4.7.2 exe in the game's folder and double-click
**`multiplayer_test.bat`** (Windows); it opens the windows and asks what to try. The steps and
what to check are in `docs/MULTIPLAYER_TEST.md`. The long way:

`tools/mp_local.sh` (Linux/macOS) or `tools/mp_local.bat` (Windows, after
`set GODOT=D:\godot\Godot_v4.7.2-stable_win64.exe`) opens a host window and a guest window already
in the host's yard over ENet (online, the yard is the lobby: the host picks the next bout at the
gate). With `BOT=1`
the guests are played by bots, so you can host, play and watch a real online bout alone. `LAG=120
LOSS=3` holds every incoming message back 120 ms (±30) and drops 3% of the unreliable ones, a
pretend poor connection to see how the game feels at that latency. The same flags work on a plain
run: `godot --path . -- --host`, `--join <address>`, `--name <name>`, `--bot`, `--lag 120 --loss 3`.

## Exporting

`.github/workflows/build.yml` builds the game for Windows, Linux and macOS. Run **Godot builds**
from the repository's Actions tab, or push a tag such as `godot-v0.1`. Each build appears as a
download on the run page. The presets live in `export_presets.cfg`.

To export by hand, install the export templates for 4.7.2 (Editor → Manage Export Templates),
then run this:

```bash
godot --headless --path . --export-release "Windows Desktop" build/windows/WRECKSMITH.exe
```

The macOS build is not signed. On a Mac, right-click it and choose Open the first time.

For a Steam build, ship the GodotSteam extension's `addons/` folder and the `steam_api` library.
They come with the GodotSteam download. Upload the export through SteamPipe as described in
the Steamworks documentation.

Store screenshots: `xvfb-run -s "-screen 0 1920x1080x24" godot --rendering-driver vulkan
--resolution 1920x1080 --path . -- --probe steamshots` with `SHOT_DIR` set saves 1920×1080
shots of the title screen, the gladiator editor and six fights.
