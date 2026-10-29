class_name Ladder
## The campaign's ladder, authored bout by bout (user: the stages in order of real difficulty,
## every bout unlike the one before, and surprises). Each stage is one bout: who comes through
## the gate ("foes", all at once), who comes through the other gate later ("late": the second
## wave, LATE_AFTER seconds in, or as soon as the first is beaten, unannounced on the board), and
## the bout's name. Men get the stage's gear, weapons and skill from the stage tables
## (data/campaign.json: Data.stage); beasts come at their species' size unless "scale" says
## otherwise; a boss stage is every fourth. The order was set from a bot-versus-bot survey of
## every foe (tools: tests/zz_balance, see README "Campaign"): the kinds that beat a plain
## swordsman fastest come last, bosses in order of what they did, and no kind twice running.
##
## Past the 36th bout the bosses come round again (steel on them, Match.RETURN_*), the dearest
## ones only, the Dragon last; the 64th is the campaign's end (Match.lap).

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
	{"foes": [{"e": "giant", "boss": true, "title": "Polyphemus the Giant"}]},
	{"foes": [{"beast": "hyena"}, {"beast": "hyena"}], "late": [{"beast": "hyena"}], "title": "Laughter in the Sand"},
	{"foes": [{"e": "retiarius"}], "late": [{"e": "berserker"}], "title": "The Net and the Axe"},
	{"foes": [{"beast": "bull"}], "title": "The Bull"},
	{"foes": [{"beast": "cerberus", "boss": true, "title": "The Hound of Hades"}]},
	# ---- Steel (17-24): the dangerous men, the first monsters.
	{"foes": [{"e": "executioner"}], "title": "The Headsman"},
	{"foes": [{"beast": "python"}], "title": "The Coils"},
	{"foes": [{"e": "berserker"}], "late": [{"e": "veles"}], "title": "No Brakes"},
	{"foes": [{"e": "minotaur", "boss": true, "title": "The Minotaur"}]},
	{"foes": [{"e": "pyro"}], "title": "Greek Fire"},
	{"foes": [{"beast": "tiger"}], "title": "The Tiger"},
	{"foes": [{"e": "murmillo"}], "late": [{"e": "flailman"}], "title": "Helm and Chain"},
	{"foes": [{"e": "titan", "boss": true, "title": "The Titan"}]},
	# ---- The killers (25-36): what beat the plain swordsman every time.
	{"foes": [{"beast": "bear"}], "title": "The Bear"},
	{"foes": [{"e": "praetorian"}, {"e": "praetorian"}], "title": "The Guard"},
	{"foes": [{"beast": "crocodile"}], "title": "The Crocodile Pit"},
	{"foes": [{"beast": "mammoth", "boss": true, "title": "The Mammoth"}]},
	{"foes": [{"e": "champion"}], "late": [{"e": "medicus"}, {"e": "medicus"}], "title": "The Champion's Doctors"},
	{"foes": [{"beast": "scorpion"}], "title": "The Sting"},
	{"foes": [{"e": "hoplite"}], "late": [{"e": "hoplite"}], "title": "The Phalanx"},
	{"foes": [{"beast": "hydra", "boss": true, "title": "The Hydra"}]},
	{"foes": [{"beast": "gorilla"}], "title": "The Gorilla"},
	{"foes": [{"e": "brute"}], "late": [{"e": "brute"}], "title": "Brothers in Arms"},
	{"foes": [{"beast": "griffin"}], "title": "The Griffin"},
	{"foes": [{"beast": "dragon", "boss": true, "title": "The Dragon"}]},
	# ---- The second lap of the bosses (37-64): steel and coatings on every man, packs, the monsters.
	{"foes": [{"e": "troll"}], "title": "The Troll"},
	{"foes": [{"e": "flailman"}, {"e": "flailman"}], "late": [{"e": "murmillo"}], "title": "Chains"},
	{"foes": [{"beast": "rhino"}], "title": "The Rhinoceros"},
	{"foes": [{"e": "giant", "boss": true, "title": "Polyphemus the Giant"}]},
	{"foes": [{"e": "sagittarius"}, {"e": "sagittarius"}], "late": [{"e": "praetorian"}], "title": "Under the Arrows"},
	{"foes": [{"beast": "basilisk"}], "title": "The Basilisk"},
	{"foes": [{"e": "pyro"}], "late": [{"e": "pyro"}], "title": "Fire from Both Gates"},
	{"foes": [{"beast": "cerberus", "boss": true, "title": "The Hound of Hades"}]},
	{"foes": [{"beast": "lion"}], "late": [{"beast": "lion"}], "title": "Two Lions"},
	{"foes": [{"e": "executioner"}, {"e": "executioner"}], "late": [{"e": "medicus"}], "title": "Two Headsmen"},
	{"foes": [{"beast": "chimera"}], "title": "The Chimera"},
	{"foes": [{"e": "minotaur", "boss": true, "title": "The Minotaur"}]},
	{"foes": [{"e": "praetorian"}, {"e": "praetorian"}], "late": [{"e": "praetorian"}], "title": "The Praetorian Guard"},
	{"foes": [{"beast": "elephant"}], "title": "The Elephant"},
	{"foes": [{"e": "troll"}], "late": [{"e": "troll"}], "title": "Two Trolls"},
	{"foes": [{"e": "titan", "boss": true, "title": "The Titan"}]},
	{"foes": [{"beast": "manticore"}], "title": "The Manticore"},
	{"foes": [{"e": "champion"}], "late": [{"e": "berserker"}, {"e": "berserker"}], "title": "The Champion's Seconds"},
	{"foes": [{"beast": "spider"}], "late": [{"beast": "scorpion"}], "title": "The Pit"},
	{"foes": [{"beast": "mammoth", "boss": true, "title": "The Mammoth"}]},
	{"foes": [{"e": "hoplite"}, {"e": "hoplite"}, {"e": "hoplite"}], "title": "The Shield Wall"},
	{"foes": [{"beast": "crocodile"}], "late": [{"beast": "crocodile"}], "title": "Two Crocodiles"},
	{"foes": [{"e": "troll"}, {"e": "troll"}], "late": [{"e": "pyro"}], "title": "Trolls and Fire"},
	{"foes": [{"beast": "hydra", "boss": true, "title": "The Hydra"}]},
	{"foes": [{"beast": "bear"}], "late": [{"beast": "bear"}], "title": "Two Bears"},
	{"foes": [{"e": "emperor", "name": "The Emperor", "title": "The Emperor"}], "late": [{"e": "praetorian"}, {"e": "praetorian"}]},
	{"foes": [{"beast": "griffin"}], "late": [{"beast": "manticore"}], "title": "Wings and Stings"},
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
	if foes.size() == 1:
		return nm
	var same := foes.all(func(f): return f.get("e", f.get("beast")) == first.get("e", first.get("beast")))
	return ("%s x%d" % [nm, foes.size()]) if same else ("%s and %d more" % [nm, foes.size() - 1])
