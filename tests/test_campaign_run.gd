extends Node
## How a campaign deals with death (CampaignRun): Legionary goes back to the last checkpoint as
## he left it, Ironman starts over; the rudis won on Ironman gives the Unbroken laurel and
## Virtus at the trainer, for good.

var t

func test_an_old_save_is_an_ironman_run_and_a_new_one_is_chosen() -> void:
	t.eq(CampaignRun.mode(), "ironman", "a save from before the choice plays by the old rule")
	t.check(not CampaignRun.chosen(), "and the menu asks before the first bout")
	CampaignRun.begin("legionary")
	t.eq(CampaignRun.mode(), "legionary", "chosen: legionary")
	t.check(CampaignRun.chosen(), "and it is remembered")
	t.eq(CampaignRun.mode(true), "ironman", "the co-op campaign keeps its own")

func test_a_legionary_goes_back_to_the_checkpoint_as_he_left_it() -> void:
	CampaignRun.begin("legionary")
	t.eq(CampaignRun.fall_back(), 0, "fallen before any checkpoint: the run is over")
	# Bout 4 won (a checkpoint: the next run of bouts starts at 5), with this on him.
	Save.set_value("coins", 240)
	Save.set_value("arms", {"main": "gladius"})
	Save.set_value("armor_worn", ["helmet"])
	Save.set_value("training", {"vis": 4})
	Save.set_value("body", {"missing": ["forearmL"]})
	Save.set_value("checkpoint", 5)
	Save.set_value("stage", 5)
	CampaignRun.keep()
	# Two bouts on, poorer, more hurt, then dead.
	Save.set_value("coins", 12)
	Save.set_value("arms", {"main": "axe"})
	Save.set_value("armor_worn", [])
	Save.set_value("training", {"vis": 8})
	Save.set_value("body", {"missing": ["forearmL", "shinR"]})
	Save.set_value("stage", 7)
	t.eq(CampaignRun.fall_back(), 5, "dead at bout 7: back to bout 5")
	t.eq(int(Save.get_value("stage", 0)), 5, "the campaign goes on from bout 5")
	t.eq(int(Save.get_value("coins", 0)), 240, "with the purse he had there")
	t.eq(str(Save.get_value("arms", {}).get("main", "")), "gladius", "his arms")
	t.eq((Save.get_value("armor_worn", []) as Array).size(), 1, "his armour")
	t.eq(int(Save.get_value("training", {}).get("vis", 0)), 4, "his training")
	t.eq((Save.get_value("body", {}).get("missing", []) as Array).size(), 1, "and his body as it was")
	t.eq(CampaignRun.fall_back(), 5, "and as often as he falls")

func test_an_ironman_starts_over_and_takes_the_rudis_for_good() -> void:
	CampaignRun.begin("ironman")
	Save.set_value("checkpoint", 9)
	CampaignRun.keep()
	t.eq(CampaignRun.fall_back(), 0, "an ironman never goes back to a checkpoint")
	t.check(not CampaignRun.unbroken(), "not yet unbroken")
	t.check(CampaignRun.won(), "the rudis on Ironman: the reward, the first time")
	t.check(CampaignRun.unbroken() and Achievements.unlocked("unbroken"), "unbroken, and the achievement")
	t.check(not CampaignRun.won(), "won again, nothing new")
	CampaignRun.begin("legionary")
	t.check(CampaignRun.unbroken(), "kept in every campaign after")

func test_a_legionary_rudis_gives_nothing_of_the_ironman() -> void:
	CampaignRun.begin("legionary")
	t.check(not CampaignRun.won(), "the rudis as a legionary")
	t.check(not CampaignRun.unbroken(), "is not the Unbroken's")

func test_virtus_is_taught_only_to_the_unbroken() -> void:
	var r := Training.buy({}, "virtus", 1, 10000)
	t.check(r.has("error"), "not unbroken: Doctore will not teach it (%s)" % r.get("error", ""))
	Save.set_value("ironman_won", true)
	r = Training.buy({}, "virtus", 1, 10000)
	t.check(not r.has("error") and int(r.stats.virtus) == Training.STEP, "unbroken: taught even at bout 1")
	t.check(int(r.cost) > Training.price({}, "vis"), "and dearer than any other (%d)" % r.cost)
	var m := Training.mods_of({"virtus": 4, "vis": 2})
	t.check(absf(float(m.strength) - 1.02 * 1.04) < 1e-4, "a little more strength on top of Vis (%.4f)" % m.strength)
	t.check(absf(float(m.footing) - 1.04) < 1e-4 and absf(float(m.bleed) - 0.96) < 1e-4, "and of everything else: footing up, bleeding down")
	t.check(Training.summary({"virtus": 4}).contains("Valour"), "the trainer's summary names it")

func test_the_unbroken_laurel_is_worn_only_by_the_unbroken() -> void:
	var M = load("res://scripts/ui/menu.gd")
	t.check(Data.armor.has("hat_unbroken") and Fighter._cosmetic("hat_unbroken"), "the laurel is a hat to wear, not armour")
	t.check(M.LOOK_SLOTS.hat.has("hat_unbroken"), "offered with the hats")
	t.check(M.look_locked("hat_unbroken"), "locked until it is won")
	t.check(not M.look_locked("hat_laurel"), "the plain laurel is anyone's")
	Save.set_value("ironman_won", true)
	t.check(not M.look_locked("hat_unbroken"), "won: his to wear")
