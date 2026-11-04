class_name Ladder
## The campaign's ladder, authored bout by bout (user: the stages in order of real difficulty,
## every bout unlike the one before, and surprises; then: every stage a foe of a new kind or a
## new combination of them, never the same line-up or the same boss twice, each harder than the
## last). Each stage is one bout: who comes through the gate ("foes", all at once), who comes
## through the other gate later ("late": the second wave, LATE_AFTER seconds in, or as soon as
## the first is beaten, unannounced on the board), and the bout's name. Men get the stage's gear,
## weapons and skill from the stage tables (data/campaign.json: Data.stage); beasts come at their
## species' size unless "scale" says otherwise; a boss stage is every fourth, sixteen bosses and
## no two alike. The order was set from a bot-versus-bot survey of every foe (tools:
## tests/zz_balance, see README "Campaign"): the kinds that beat a plain swordsman fastest come
## later, each band of eight bouts harder than the one before, no kind twice running, and the
## kinds met alone come back later only in company they have not been seen in before.
##
## Past the 36th bout a boss of men comes in steel with a coated weapon (Match.RETURN_*); the
## 64th is the campaign's end (Match.lap).

const LATE_AFTER := 9.0   # the second gate opens this long into the bout, or when the first wave is down

const BOUTS := [
	# ---- The first blood (1-8): tunics, cheap iron, one at a time, the first bosses the gentlest.
	{"foes": [{"e": "recruit"}], "title": "First Blood"},
	{"foes": [{"beast": "boar"}], "title": "Pork Chops"},
	{"foes": [{"e": "dimachaerus"}], "title": "Two Swords"},
	{"foes": [{"e": "cyclops", "boss": true, "title": "The Cyclops"}]},
	{"foes": [{"e": "coward"}], "late": [{"e": "recruit"}], "title": "The Coward's Friend"},
	{"foes": [{"beast": "wolf"}], "late": [{"beast": "wolf"}], "title": "The Pack"},
	{"foes": [{"e": "veles"}], "title": "The Skirmisher"},
	{"foes": [{"beast": "lion", "scale": 2.0, "name": "The Big Lion", "boss": true, "title": "The Big Lion"}]},
	# ---- Iron (9-16): helmets come, the men's weapons grow, the first real beasts.
	{"foes": [{"e": "sagittarius"}], "late": [{"beast": "hyena"}], "title": "Arrows and Teeth"},
	{"foes": [{"e": "mimic"}], "late": [{"e": "mimic"}], "title": "Mirror, Mirror"},
	{"foes": [{"e": "shieldbearer"}], "title": "The Wall"},
	{"foes": [{"beast": "elephant", "boss": true, "title": "The Elephant"}]},
	{"foes": [{"beast": "hyena"}, {"beast": "hyena"}], "late": [{"beast": "hyena"}], "title": "Laughter in the Sand"},
	{"foes": [{"e": "retiarius"}], "late": [{"e": "berserker"}], "title": "The Net and the Axe"},
	{"foes": [{"beast": "rat"}, {"beast": "rat"}], "late": [{"beast": "rat"}], "title": "The Sewer"},
	{"foes": [{"e": "giant", "boss": true, "title": "Polyphemus the Giant"}]},
	# ---- Steel (17-24): the dangerous men, the first monsters.
	{"foes": [{"e": "executioner"}], "title": "The Headsman"},
	{"foes": [{"beast": "python"}], "title": "The Coils"},
	{"foes": [{"beast": "bull"}], "title": "The Bull"},
	{"foes": [{"beast": "griffin", "boss": true, "title": "The Griffin"}]},
	{"foes": [{"e": "pyro"}], "title": "Greek Fire"},
	{"foes": [{"beast": "tiger"}], "title": "The Tiger"},
	{"foes": [{"e": "murmillo"}], "late": [{"e": "executioner"}], "title": "Helm and Axe"},
	{"foes": [{"beast": "cerberus", "boss": true, "title": "The Hound of Hades"}]},
	# ---- The killers (25-32): what beat the plain swordsman every time.
	{"foes": [{"beast": "rhino"}], "title": "The Rhinoceros"},
	{"foes": [{"e": "praetorian"}, {"e": "praetorian"}], "title": "The Guard"},
	{"foes": [{"beast": "crocodile"}], "title": "The Crocodile Pit"},
	{"foes": [{"e": "troll", "boss": true, "title": "The Troll"}]},
	{"foes": [{"e": "champion"}], "late": [{"e": "medicus"}, {"e": "medicus"}], "title": "The Champion's Doctors"},
	{"foes": [{"beast": "scorpion"}], "title": "The Sting"},
	{"foes": [{"e": "hoplite"}], "late": [{"e": "hoplite"}], "title": "The Phalanx"},
	{"foes": [{"e": "minotaur", "boss": true, "title": "The Minotaur"}]},
	# ---- Beasts and brutes (33-40): the last kinds met alone, then the first of them together.
	{"foes": [{"beast": "bear"}], "title": "The Bear"},
	{"foes": [{"e": "brute"}], "late": [{"e": "brute"}], "title": "Brothers in Arms"},
	{"foes": [{"beast": "spider"}], "title": "The Spider"},
	{"foes": [{"beast": "gorilla", "boss": true, "title": "The Gorilla"}]},
	{"foes": [{"e": "shieldbearer"}, {"e": "shieldbearer"}], "late": [{"e": "sagittarius"}], "title": "Shields and Arrows"},
	{"foes": [{"e": "champion"}, {"e": "executioner"}], "late": [{"e": "berserker"}], "title": "The Last of the Ludus"},
	{"foes": [{"beast": "bear"}], "late": [{"beast": "wolf"}, {"beast": "wolf"}], "title": "The Bear and the Pack"},
	{"foes": [{"e": "titan", "boss": true, "title": "The Titan"}]},
	# ---- Mixed company (41-48): the foes met alone come back two kinds at once.
	{"foes": [{"beast": "spider"}], "late": [{"beast": "scorpion"}], "title": "The Pit"},
	{"foes": [{"e": "executioner"}, {"e": "executioner"}], "late": [{"e": "pyro"}], "title": "Two Headsmen"},
	{"foes": [{"e": "murmillo"}, {"e": "murmillo"}], "late": [{"e": "sagittarius"}, {"e": "sagittarius"}], "title": "Under the Arrows"},
	{"foes": [{"beast": "chimera", "boss": true, "title": "The Chimera"}]},
	{"foes": [{"beast": "crocodile"}], "late": [{"beast": "python"}], "title": "The River"},
	{"foes": [{"e": "champion"}], "late": [{"e": "berserker"}, {"e": "berserker"}], "title": "The Champion's Seconds"},
	{"foes": [{"beast": "rhino"}], "late": [{"beast": "bull"}, {"beast": "bull"}], "title": "The Stampede"},
	{"foes": [{"beast": "mammoth", "boss": true, "title": "The Mammoth"}]},
	# ---- No quarter (49-56): bigger second waves, a monster every fourth bout.
	{"foes": [{"e": "praetorian"}, {"e": "praetorian"}], "late": [{"e": "sagittarius"}, {"e": "sagittarius"}], "title": "The Praetorian Guard"},
	{"foes": [{"beast": "spider"}], "late": [{"beast": "rat"}, {"beast": "rat"}, {"beast": "rat"}], "title": "The Nest"},
	{"foes": [{"e": "pyro"}, {"e": "pyro"}], "late": [{"e": "murmillo"}], "title": "Fire from Both Gates"},
	{"foes": [{"beast": "basilisk", "boss": true, "title": "The Basilisk"}]},
	{"foes": [{"beast": "bear"}], "late": [{"beast": "crocodile"}], "title": "Tooth and Claw"},
	{"foes": [{"beast": "tiger"}, {"beast": "tiger"}], "late": [{"beast": "bear"}], "title": "Stripes and Claws"},
	{"foes": [{"e": "hoplite"}, {"e": "hoplite"}], "late": [{"e": "shieldbearer"}], "title": "The Shield Wall"},
	{"foes": [{"beast": "manticore", "boss": true, "title": "The Manticore"}]},
	# ---- The last (57-64): three kinds at once, the Emperor himself, the Dragon at the end.
	{"foes": [{"beast": "crocodile"}], "late": [{"beast": "scorpion"}, {"beast": "scorpion"}], "title": "Scales and Stings"},
	{"foes": [{"e": "executioner"}, {"e": "executioner"}], "late": [{"e": "brute"}, {"e": "brute"}], "title": "The Butchers"},
	{"foes": [{"e": "murmillo"}, {"e": "hoplite"}, {"e": "sagittarius"}], "late": [{"e": "praetorian"}], "title": "The Legion"},
	{"foes": [{"beast": "hydra", "boss": true, "title": "The Hydra"}]},
	{"foes": [{"beast": "bear"}, {"beast": "tiger"}], "late": [{"beast": "rhino"}], "title": "The Menagerie"},
	{"foes": [{"beast": "spider"}, {"beast": "scorpion"}], "late": [{"beast": "python"}], "title": "Venom"},
	{"foes": [{"e": "emperor", "name": "The Emperor", "title": "The Emperor"}], "late": [{"e": "praetorian"}, {"e": "praetorian"}]},
	{"foes": [{"beast": "dragon", "boss": true, "title": "The Dragon"}]},
]

## Bout `n` of the ladder (1-based), or {} past its end.
static func bout(n: int) -> Dictionary:
	if n < 1 or n > BOUTS.size():
		return {}
	return (BOUTS[n - 1] as Dictionary).duplicate(true)

## What the board calls the foe(s): "Hoplite", "Hoplite and 1 more", "Hyena x2".
static func foe_name(foes: Array) -> String:
	if foes.is_empty():
		return ""
	var first: Dictionary = foes[0]
	var nm := String(first.get("title", first.get("name", "")))
	if nm == "":
		nm = String(Data.beasts.get(first.beast, {}).get("name", first.beast)) if first.has("beast") else String(Data.enemy_type(String(first.get("e", ""))).get("label", String(first.get("e", "a gladiator")).capitalize()))
	nm = Loc.t(nm)
	if foes.size() == 1:
		return nm
	var same := foes.all(func(f): return f.get("e", f.get("beast")) == first.get("e", first.get("beast")))
	return ("%s x%d" % [nm, foes.size()]) if same else (Loc.t("%s and %d more") % [nm, foes.size() - 1])
