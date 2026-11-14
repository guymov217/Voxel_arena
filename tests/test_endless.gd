extends Node
## The endless arena (Endless): the same waves for the same seed (today's challenge is
## everyone's), a great foe every fifth wave, harder and more as it goes; in the demo its own
## foes alone; men of the waves armed at random (a blade and a shield, one in each hand, a
## great two-hander, a blade alone); a wave beaten is a breath and a reward; a fall keeps the
## best wave.

var t

func _match(opts := {}) -> Match:
	var m := Match.new()
	add_child(m)
	var o := {"mode": "endless", "headless": true, "seed": 3, "decrees": [], "hazards": [], "loadout": {"main": "gladius", "off": ""}, "endless": {"seed": 11}}
	o.merge(opts, true)
	m.setup(o)
	return m

func _steps(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func _names(list: Array) -> Array:
	return list.map(func(en): return String(en.get("e", en.get("beast", ""))) + ("*" if en.get("boss", false) else ""))

func test_the_same_seed_brings_the_same_waves() -> void:
	var a := Endless.new(null, {"seed": 5})
	var b := Endless.new(null, {"seed": 5})
	var c := Endless.new(null, {"seed": 6})
	var differ := false
	for n in range(1, 13):
		t.eq(str(_names(a.plan(n))), str(_names(b.plan(n))), "wave %d the same both times" % n)
		differ = differ or str(_names(a.plan(n))) != str(_names(c.plan(n)))
	t.check(differ, "another seed, other waves")
	var d1 := Endless.new(null, {"daily": true})
	var d2 := Endless.new(null, {"daily": true, "seed": 99})
	t.eq(str(_names(d1.plan(3))), str(_names(d2.plan(3))), "today's challenge is the same for everyone")
	t.eq(a.plan(1).size(), 1, "the first wave is one foe")
	t.check(a.plan(12).size() >= 3, "the twelfth more (%d)" % a.plan(12).size())
	for n in [5, 10, 15]:
		var w := a.plan(n)
		t.check(w[0].get("boss", false), "wave %d brings a great foe: %s" % [n, str(_names(w))])
	t.eq(a.plan(5).size(), 1, "the first great foe comes alone")
	t.check(a.plan(15).size() > 1, "a later one with men or beasts at his side")

func test_the_demo_draws_on_its_own_foes_alone() -> void:
	Edition.forced = true
	var p := Endless.pool()
	t.check(p.men.all(func(k): return Edition.foe_open("foe:" + String(k))), "its men: %s" % str(p.men))
	t.check(p.beasts.all(func(k): return Edition.foe_open(String(k))), "its beasts: %s" % str(p.beasts))
	t.eq(str(p.bosses.map(func(b): return b.get("title", ""))), str(["The Big Lion", "The Cyclops"]), "its two great foes, in the campaign's order")
	var e := Endless.new(null, {"seed": 1})
	t.eq(str(_names(e.plan(5))), str(["lion*"]), "the fifth wave: the Big Lion")
	t.eq(str(_names(e.plan(10)).slice(0, 1)), str(["cyclops*"]), "the tenth: the Cyclops")
	for n in range(1, 31):
		for en in e.plan(n):
			var open: bool = Edition.foe_open("foe:" + String(en.e)) if en.has("e") else Edition.foe_open(String(en.beast))
			t.check(open, "wave %d: %s is in the demo" % [n, str(en)])
	t.eq(Endless.held_back(), 7, "the full game's other great foes, counted, not named")
	Edition.forced = false
	t.eq(Endless.pool().bosses.size(), Data.campaign.bosses.size(), "the full game: every great foe")
	t.eq(Endless.held_back(), 0, "nothing held back")
	Edition.forced = null

func test_the_men_of_the_waves_take_up_arms_at_random() -> void:
	var r := RandomNumberGenerator.new()
	r.seed = 4
	var kinds := {}
	for i in 400:
		var n := 1 + i % 12
		var a := Endless.arms(r, n)
		var cap := Match.weapon_budget(1 + n)
		t.check(Match.ladder_power(a.main) <= cap, "wave %d: %s within the budget" % [n, a.main])
		var main: Dictionary = Data.preset(a.main)
		var off: Dictionary = Data.preset(a.off) if a.off != "" else {}
		var kind := "alone"
		if main.get("twoHanded", false) or Endless.TWO_HAND.has(a.main):
			kind = "two-handed"
			t.eq(a.off, "", "nothing in the other hand of a man with a two-hander")
		elif off.get("kind", "") == "shield":
			kind = "shield"
		elif not off.is_empty():
			kind = "two blades"
		kinds[kind] = int(kinds.get(kind, 0)) + 1
	for k in ["alone", "two-handed", "shield", "two blades"]:
		t.check(int(kinds.get(k, 0)) > 20, "%s: %d of 400" % [k, int(kinds.get(k, 0))])
	# A reward's weapon is a real one, never a foe's joke (a rubber chicken was offered).
	var given := {}
	for i in 200:
		var key := Endless.prize(r, 1 + i % 20)
		t.check(Endless.PRIZE_ARMS.has(key), "a prize: %s" % key)
		given[key] = true
	t.check(given.size() >= 4, "and not always the same one (%s)" % str(given.keys()))

func test_a_wave_comes_in_and_is_beaten() -> void:
	var m := _match()
	var en: Endless = m.modes.endless
	t.check(en != null and en.phase == "next" and m.enemies().is_empty(), "the sand empty, the horn to come")
	en.update(Endless.START_DELAY + 0.1)
	t.eq(en.wave, 1, "wave 1")
	t.eq(en.phase, "fight", "and the fight on")
	var foes := m.enemies()
	t.eq(foes.size(), en.plan(1).size(), "its foes on the sand")
	for e in foes:
		t.eq(int(e.get("endless_wave", 0)), 1, "marked as the first wave's")
		if e.kind == "bot":
			t.check(e.f.weapons.R != null or e.f.weapons.L != null, "%s comes armed" % e.f.display_name)
	var offers := []
	en.offered.connect(func(o): offers.append(o))
	var me: Fighter = m.me.f
	me.blood = 40.0
	me.stamina = 10.0
	for e in foes:
		e.f.die("wounds")
	await _steps(3)
	t.eq(en.phase, "rest", "the wave beaten: a breath")
	t.eq(offers.size(), 1, "and the rewards offered")
	t.eq(en.offer.size(), 3, "three of them")
	t.check(me.blood >= 40.0 + Endless.REST_HEAL - 0.5 and me.stamina >= 99.0, "patched up a little (blood %.0f)" % me.blood)
	t.eq(int(Save.get_value("endless", {}).get("best", 0)), 1, "the wave kept as the best")
	t.check(not m.over, "the run goes on")
	en.take(0)
	t.eq(en.phase, "next", "a reward taken: the next horn")
	en.update(Endless.START_DELAY + 0.1)
	t.eq(en.wave, 2, "wave 2 comes in")
	m.queue_free()

## With a screen a wave is built over the frames that follow (Match.bring_in), not all of it in
## the frame of the horn: none of it on the sand at once, the wave not beaten while its foes are
## still on their way in, each marked as the wave's as it comes in.
func test_a_wave_comes_in_over_the_frames_that_follow() -> void:
	var m := _match()
	m.stage_always = true
	var en: Endless = m.modes.endless
	en.wave = 5   # (the sixth wave: several foes)
	en.update(Endless.START_DELAY + 0.1)
	var want := en.plan(6).size()
	t.eq(en.wave, 6, "wave 6 called for")
	t.eq(en.phase, "fight", "the fight on")
	t.check(want >= 2, "several foes in it (%d)" % want)
	t.eq(m.coming, want, "all of them on their way in")
	t.eq(m.enemies().size(), 0, "none on the sand in the frame of the horn")
	var frames := 0
	var beaten := false
	var seen := 0
	while m.coming > 0 and frames < 3000:
		await get_tree().process_frame
		frames += 1
		beaten = beaten or en.phase != "fight"
		seen = maxi(seen, m.enemies().size())
	t.check(frames > 10 and frames < 3000, "built over the frames that follow (%d of them)" % frames)
	t.check(not beaten, "the wave not beaten while it was still on its way in")
	var foes := m.enemies()
	t.eq(foes.size(), want, "all of it on the sand")
	for e in foes:
		t.eq(int(e.get("endless_wave", 0)), 6, "%s marked as the wave's" % e.f.display_name)
		t.check(e.f.alive and e.f.visible and e.f.process_mode != Node.PROCESS_MODE_DISABLED, "%s whole and in the fight" % e.f.display_name)
	for e in foes:
		e.f.die("wounds")
	await _steps(3)
	t.eq(en.phase, "rest", "then beaten as any wave")
	m.queue_free()

func test_each_reward_gives_what_it_says() -> void:
	var m := _match()
	var en: Endless = m.modes.endless
	var me: Fighter = m.me.f
	var give := func(rw: Dictionary) -> void:
		en.phase = "rest"
		en.offer = [rw]
		en.take(0)
	me.blood = 30.0
	give.call({"id": "bind", "title": "Bind your wounds"})
	t.eq(me.blood, 100.0, "bound: all the blood back")
	m.me.inventory = {}
	give.call({"id": "pot", "arg": "nailPot", "title": "A gift from the stands"})
	t.eq(int(m.me.inventory.get("nailPot", 0)), 2, "two pots from the stands")
	give.call({"id": "blade", "arg": "axe", "title": "A new weapon"})
	t.eq(String(me.weapons.R.design.get("name", "")), String(Data.preset("axe").name), "a new weapon in the right hand")
	give.call({"id": "armour", "arg": "helmet", "title": "A piece of armour"})
	t.check(en._worn(me).has("helmet"), "a helmet on")
	t.check(not en._pieces_left(me).has("helmet"), "and not offered again")
	var w: Weapon = me.weapons.R
	var all := w.alive_count()
	w.remove_voxels(range(w.vox.size() - 4, w.vox.size()))
	t.eq(w.alive_count(), all - 4, "the blade chipped")
	t.check(en._chipped(me), "a chipped blade can be mended")
	give.call({"id": "mend", "title": "Mend your weapons"})
	t.eq(me.weapons.R.alive_count(), all, "mended: whole again")
	t.check(me.weapons.R != w, "taken up afresh")
	m.queue_free()

func test_a_fall_ends_the_run_and_keeps_the_best() -> void:
	Save.set_value("endless", {"best": 2})
	var m := _match()
	var en: Endless = m.modes.endless
	en.update(Endless.START_DELAY + 0.1)
	en.wave = 6
	var result := []
	m.finished.connect(func(r): result.append(r))
	m.me.f.die("wounds")
	await _steps(4)
	t.eq(en.phase, "over", "the run is over")
	t.check(m.over and not result.is_empty() and not result[0].won, "lost")
	t.eq(int(Save.get_value("endless", {}).get("best", 0)), 5, "five waves beaten: the best now")
	m.queue_free()
