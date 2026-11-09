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

## Through the gate into the checkpoint's bout, what he walks in with is what a death brings him
## back to: what the physician mended in the yard after the checkpoint was won stays mended (user:
## back in the yard with a fight's wounds instead of as he left the checkpoint).
func test_a_legionary_comes_back_as_he_walked_into_the_checkpoints_bout() -> void:
	var menu = load("res://scripts/ui/menu.gd").new()
	menu.backdrop_off = true
	add_child(menu)
	await get_tree().process_frame
	CampaignRun.begin("legionary")
	CampaignRun.walk_in(1)
	t.eq(CampaignRun.falls_back_to(), 0, "no checkpoint yet: walking into bout 1 keeps none")
	# Bout 4 won (the checkpoint: bout 5 next), a forearm lost in it.
	Save.set_value("coins", 300)
	Save.set_value("body", {"missing": ["forearmL"]})
	Save.set_value("checkpoint", 5)
	Save.set_value("stage", 5)
	CampaignRun.keep()
	t.eq(CampaignRun.falls_back_to(), 5, "a death now goes back to bout 5")
	# In the yard: the physician gives the forearm back for 120.
	Save.set_value("coins", 180)
	Save.set_value("body", {"missing": []})
	CampaignRun.walk_in(6)
	t.eq(int((Save.get_value("checkpoint_save", {}) as Dictionary).get("coins", 0)), 300, "not the checkpoint's bout: nothing kept")
	menu.start({"mode": "campaign", "stage": 5})
	await get_tree().process_frame
	var kept: Dictionary = Save.get_value("checkpoint_save", {})
	t.eq(int(kept.get("coins", 0)), 180, "through the gate into bout 5: kept as he went in")
	menu._end_match()
	# Bout 5 won, a shin lost; bout 6 lost.
	Save.set_value("coins", 260)
	Save.set_value("body", {"missing": ["shinR"]})
	Save.set_value("stage", 6)
	menu._campaign_lost({})
	t.eq(int(Save.get_value("stage", 0)), 5, "dead at bout 6: back to bout 5")
	t.eq(int(Save.get_value("coins", 0)), 180, "with the purse he went in with")
	t.check((menu.body().missing as Array).is_empty(), "and whole, as the physician left him (%s)" % str(menu.body().missing))
	t.eq(Net.my_body.get("missing", []), [], "and a room he joins is told so")
	CampaignRun.begin("ironman")
	Save.set_value("checkpoint", 5)
	CampaignRun.keep()
	Save.set_value("coins", 999)
	CampaignRun.walk_in(5)
	t.eq(CampaignRun.falls_back_to(), 0, "an ironman has no checkpoint to go back to")
	menu.queue_free()
	await get_tree().process_frame

## A Legionary who falls after the checkpoint comes back to it as he walked into its bout, through
## the whole of a bout lost (the moment he falls, the banner, the result read): nothing that bout
## did to him (a forearm off, his blade's chips, the plates off his armour, the pots he drank) is
## on him, in the save or on the man in the next bout (user: back at the checkpoint with the
## damage of the bout he lost; it must be the checkpoint's save, all of it, as it was).
func test_a_legionary_fallen_in_a_bout_comes_back_without_what_it_did_to_him() -> void:
	var menu = load("res://scripts/ui/menu.gd").new()
	menu.backdrop_off = true
	add_child(menu)
	await get_tree().process_frame
	CampaignRun.begin("legionary")
	# Bout 4 won (the checkpoint: bout 5 next), whole, a purse, his armour on.
	Save.set_value("coins", 300)
	Save.set_value("body", Body.empty())
	Save.set_value("armor_worn", ["helmet", "lorica"])
	Save.set_value("checkpoint", 5)
	Save.set_value("stage", 5)
	CampaignRun.keep()
	menu.start({"mode": "campaign", "stage": 5})
	await get_tree().process_frame
	var kept: Dictionary = (Save.get_value("checkpoint_save", {}) as Dictionary).duplicate(true)
	var m: Match = menu.match_
	var f: Fighter = m.me.f
	for i in 30:
		await get_tree().physics_frame
	# In the bout: his left forearm off, then he falls.
	var fore: VoxelPart = f.arm.L.fore
	var all := PackedInt32Array()
	for i in fore.fx.size():
		if fore.alive[i]:
			all.append(i)
	f.sever(fore, {"severed": []}, all)
	for i in 10:
		await get_tree().physics_frame
	f.die("test")
	# The bout ends and its result is read (after its banner and the kill cam).
	var t0 := Time.get_ticks_msec()
	while menu.match_ == m and Time.get_ticks_msec() - t0 < 40000:
		await get_tree().process_frame
	t.check(menu.match_ != m, "the bout ended and its result was read")
	t.eq(int(Save.get_value("stage", 0)), 5, "back to bout 5")
	for key in CampaignRun.KEPT:
		if kept.has(key):
			t.eq(JSON.stringify(Save.get_value(key)), JSON.stringify(kept[key]), "%s as he walked into bout 5" % key)
	var b: Dictionary = menu.body()
	t.check((b.missing as Array).is_empty(), "his forearm on him again (%s)" % str(b.missing))
	# Into bout 5 again: the man as he went in.
	menu.start({"mode": "campaign", "stage": 5})
	await get_tree().process_frame
	var f2: Fighter = menu.match_.me.f
	t.check(not f2.arm.L.fore.severed and not f2.arm.L.fore.missing, "and in the next bout his forearm is on him")
	menu._end_match()
	menu.queue_free()
	await get_tree().process_frame

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

## An Ironman's death takes the pots in his bag with it: the new campaign starts with none
## (user). A Legionary gets the bag back as it was at the checkpoint.
func test_an_ironman_death_empties_the_bag() -> void:
	var menu = load("res://scripts/ui/menu.gd").new()
	add_child(menu)
	await get_tree().process_frame
	CampaignRun.begin("ironman")
	menu.set_kit({"greekFire": 2, "nailPot": 1})
	t.eq(int(menu.kit().get("greekFire", 0)), 2, "pots in the bag")
	menu._campaign_lost({})
	t.check(menu.kit().is_empty(), "dead on an Ironman run: the new campaign starts with an empty bag (%s)" % str(menu.kit()))
	menu.set_kit({"nailPot": 2})
	menu.restart_campaign()
	t.check(menu.kit().is_empty(), "and so does one begun over from the menu")
	CampaignRun.begin("legionary")
	menu.set_kit({"greekFire": 1})
	Save.set_value("checkpoint", 3)
	CampaignRun.keep()
	menu.set_kit({"greekFire": 3})
	menu._campaign_lost({})
	t.eq(int(menu.kit().get("greekFire", 0)), 1, "a Legionary's bag as it was at the checkpoint")
	menu.queue_free()
	await get_tree().process_frame

func test_a_legionary_rudis_gives_nothing_of_the_ironman() -> void:
	CampaignRun.begin("legionary")
	t.check(not CampaignRun.won(), "the rudis as a legionary")
	t.check(not CampaignRun.unbroken(), "is not the Unbroken's")

func test_virtus_is_taught_only_to_the_unbroken() -> void:
	var r := Training.buy({}, "virtus", 1, 10000)
	t.check(r.has("error"), "not unbroken: Doctore will not teach it (%s)" % r.get("error", ""))
	Save.set_value("ironman_won", true)
	r = Training.buy({}, "virtus", 1, 10000)
	t.check(not r.has("error") and int(r.stats.virtus) == Training.step("virtus"), "unbroken: taught even at bout 1")
	t.check(int(r.cost) > Training.price({}, "vis"), "and dearer than any other (%d)" % r.cost)
	var m := Training.mods_of({"virtus": 4, "vis": 3})
	t.check(absf(float(m.strength) - 1.03 * 1.04) < 1e-4, "a little more strength on top of Vis (%.4f)" % m.strength)
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
