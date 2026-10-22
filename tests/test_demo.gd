extends Node
## The demo edition: the campaign to its second boss and no further, the arena and the training
## with the bouts' own men and beasts (the rest left out), and it stops after its last bout. The full game is untouched by all of it.

var t

func test_the_demo_stops_after_its_second_boss() -> void:
	Edition.forced = true
	t.check(not Edition.demo_over(Edition.DEMO_STAGES), "the last demo bout is played")
	t.check(Edition.demo_over(Edition.DEMO_STAGES + 1), "the one after it is not")
	t.check(Data.stage(4).get("boss", false) and Data.stage(Edition.DEMO_STAGES).get("boss", false), "the demo has two bosses, the last its end")
	Edition.forced = false
	t.check(not Edition.demo_over(40), "the full game goes on")
	Edition.forced = null

func test_the_demo_shows_its_own_foes_and_locks_the_rest() -> void:
	Edition.forced = true
	var f := Edition.demo_foes()
	t.check(f.beasts.has("lion") and f.men.has("cyclops"), "its bosses are in: the lion and the cyclops")
	t.check(not Edition.foe_open("dragon") and not Edition.foe_open("hydra") and not Edition.foe_open("foe:titan"), "the dragon, the hydra and the titan wait for the full game")
	t.check(Edition.foe_open("foe:recruit") and Edition.foe_open("gladiator"), "the men of its bouts are there")
	t.check(Edition.mode_open("ffa", true) and Edition.mode_open("pvp", true), "in a room: everyone against everyone")
	t.check(Edition.mode_open("duel", false) and not Edition.mode_open("hunt", false), "alone: the duel, not the monster hunt")
	Edition.forced = false
	t.check(Edition.foe_open("dragon") and Edition.mode_open("hunt", false), "the full game locks nothing")
	Edition.forced = null

## The demo's yard and market: the new stations and wares are in it, within its limits, and no
## two stations stand on each other.
func test_the_demos_yard_and_market() -> void:
	Edition.forced = true
	t.check(Data.shop.throwables.has("telekinesis") and Data.shop.throwables.has("fireball"), "the Hand of Jupiter and the fireball are on the market")
	t.eq(Training.cap("corium", 40), Training.DEMO_MAX, "the trainer teaches two sessions of each in the demo")
	t.check(Training.buy({}, "vis", 8, 1000).has("stats"), "and sells one before its last bout")
	Edition.forced = null
	var st := Yard.stations()
	t.check(st.has("trainer") and st.has("physician") and st.has("smith") and st.has("market") and st.has("gate"), "the yard has its five stations")
	var ids: Array = st.keys()
	for i in ids.size():
		for j in range(i + 1, ids.size()):
			var a: Dictionary = st[ids[i]]
			var b: Dictionary = st[ids[j]]
			var d := Vector2(a.p.x - b.p.x, a.p.z - b.p.z).length()
			t.check(d > float(a.r) + float(b.r) + 1.0, "%s and %s stand apart (%.1f m)" % [ids[i], ids[j], d])
	t.check(Tutorial.STEPS.any(func(s): return s.id == "yard"), "the tutorial has a page on the yard")
	t.check(Achievements.LIST.size() >= 15 and Achievements.LIST.has("rudis"), "the achievements are listed")
