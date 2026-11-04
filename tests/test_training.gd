extends Node
## The trainer: six abilities bought a session at a time, capped by the bout and their own
## limit, dearer every time; what they teach shows in the man (his breath, his footing, his
## blow) and nothing is learned in the arena itself.

var t

func test_the_trainer_sells_sessions_within_the_bouts_cap() -> void:
	Edition.forced = false
	t.eq(Training.cap("vis", 1), 0, "nothing before the first bout is won")
	t.eq(Training.cap("vis", 6), 9, "two per cent a bout, in whole sessions (bout 6: 9%)")
	t.eq(Training.cap("vis", 40), 30, "and never past the ability's own limit")
	t.eq(Training.cap("corium", 40), 45, "hide goes further")
	var st := {}
	var r := Training.buy(st, "vis", 1, 1000)
	t.check(r.has("error"), "bout 1: nothing to teach yet (%s)" % r.get("error", ""))
	r = Training.buy(st, "vis", 5, 30)
	t.check(r.has("error") and String(r.error).begins_with("Not enough"), "no denarii, no session")
	r = Training.buy(st, "vis", 5, 100)
	t.check(not r.has("error") and int(r.cost) == 40 and int(r.stats.vis) == 3, "the first session: 40 denarii, +3%%")
	st = r.stats
	t.eq(Training.price(st, "vis"), 70, "the next costs more")
	r = Training.buy(st, "vis", 5, 1000)
	st = r.stats
	r = Training.buy(st, "vis", 5, 1000)
	t.check(r.has("error"), "bout 5 allows 6%%: the third session waits (%s)" % r.get("error", ""))
	t.eq(Training.bout_for(9), 6, "and comes before bout 6")
	t.eq(Training.cap("vis", Training.bout_for(9)), 9, "(as the cap says)")
	t.eq(Training.sanitize({"vis": 7, "bogus": 3, "corium": 99, "sanguis": "x"}).get("vis"), 6, "a save is made safe: whole sessions")
	t.eq(Training.sanitize({"corium": 99}).corium, 45, "and within the limit")
	t.eq(Training.sanitize({"virtus": 4}).get("virtus"), 4, "Valour keeps its sessions of 2%")
	t.eq(Training.from_old({"vis": 4, "corium": 24, "enemy": "bear", "bag": {}}), {"vis": 6, "corium": 36}, "the old save's sessions are kept, at today's 3% (the training ground's own keys left out)")
	var m := Training.mods_of({"vis": 9, "sanguis": 21, "spiritus": 6, "firmitas": 9, "ictus": 3, "corium": 12})
	t.check(is_equal_approx(m.strength, 1.09) and is_equal_approx(m.bleed, 0.79) and is_equal_approx(m.wind, 1.06) and is_equal_approx(m.footing, 1.09) and is_equal_approx(m.blow, 1.03) and is_equal_approx(m.toughness, 1.12), "the abilities become the man's mods (%s)" % [m])
	Edition.forced = true
	t.eq(Training.cap("corium", 40), Training.DEMO_MAX, "the demo's trainer teaches two sessions")
	Edition.forced = null

## What he was taught shows in him: more breath, a steadier stance, a heavier blow.
func test_training_shows_in_the_man() -> void:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none"}, "headless": true, "seed": 3, "mods": Training.mods_of({"spiritus": 21, "firmitas": 21, "ictus": 15, "vis": 9})})
	var me: Fighter = m.me.f
	t.check(is_equal_approx(float(me.mods.strength), 1.09) and is_equal_approx(float(me.mods.blow), 1.15), "the mods are on him")
	t.check(me.breath_cap() > 119.0, "a fifth more breath (%.0f)" % me.breath_cap())
	var plain = m.spawn_fighter({"kind": "bot", "name": "P", "loadout": {}, "team": 1, "pos": Vector3(3, 0, 0), "yaw": PI})
	plain.erase("bot")
	plain.drive = func(_e): return {}
	for i in 30:
		await get_tree().physics_frame
	var hit := func(f: Fighter) -> float:
		f.stagger = 0.0
		var p: Vector3 = f.torso.global_transform * Vector3(0, 0.1, -f.torso.half_ext.z)
		f.apply_hit(f.torso, {"impulse": 30.0, "type": "blunt", "hardness": 0.8, "sharpness": 0.0, "point": p, "dir": Vector3.FORWARD})
		return f.stagger
	var s_plain: float = hit.call(plain.f)
	var s_trained: float = hit.call(me)
	t.check(s_trained < s_plain * 0.9 and s_plain > 0.0, "the same blow rocks the trained man less (%.2f against %.2f)" % [s_trained, s_plain])
	m.queue_free()

## Strength (Vis) is in every throw too (user): a weapon, darts, a discus leave a stronger arm
## faster, still on the line to the crosshair (a bot's lob too), and land harder: half of the
## strength goes into the blow, as into a weapon's.
func test_a_stronger_arm_throws_faster_and_harder() -> void:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none"}, "headless": true, "seed": 3})
	var me: Fighter = m.me.f
	var foe = m.spawn_fighter({"kind": "bot", "name": "V", "loadout": {}, "team": 1, "pos": Vector3(0, 0, 3), "yaw": PI})
	foe.erase("bot")
	foe.drive = func(_e): return {}
	var v: Fighter = foe.f
	for i in 20:
		await get_tree().physics_frame
	var blows := []
	m.combat.hit.connect(func(h): if h.get("char") == v: blows.append(float(h.J)))
	var runs := []
	for s in [1.0, 1.3]:
		me.mods.strength = s
		var aim := Vector3(0.0, 1.2, 14.0)
		var n0: int = m.items.list.size()
		m.throwables.throw_type(me, "pot_dart", aim, null, true, 1.0)
		m.throwables.throw_type(me, "pot_discus", aim, null, true, 1.0)
		m.throwables.throw_type(me, "pot_discus", aim, null, false)
		var thrown: Array = m.items.list.slice(n0)
		var dart: Dictionary = thrown[1]   # the middle one of the three goes at the mark
		var p0: Vector3 = dart.p
		var dv: Vector3 = dart.vel
		var tt := Vector2(aim.x - p0.x, aim.z - p0.z).length() / Vector2(dv.x, dv.z).length()
		var lob: Vector3 = thrown[4].vel
		runs.append({"weapon": me.launch_velocity(me.torso.global_position + Vector3(0, 0.3, 0), aim, 1.0, 1.0).length(),
			"dart": dv.length(), "discus": (thrown[3].vel as Vector3).length(), "lob": Vector2(lob.x, lob.z).length(),
			"miss": absf(p0.y + dv.y * tt - 0.5 * 9.81 * tt * tt - aim.y)})
		for it in thrown:
			m.items.remove(it)
		blows.clear()
		m.throwables.explode("pot_dart", v.torso.global_position, me, Vector3(0, 0, 1), v, v.torso)
		m.throwables.explode("pot_discus", v.torso.global_position + Vector3(0, -0.2, 0), me, Vector3(0, 0, 1), v, v.torso)
		runs[-1]["blows"] = blows.duplicate()
	var a: Dictionary = runs[0]
	var b: Dictionary = runs[1]
	for k in ["weapon", "dart", "discus", "lob"]:
		t.check(absf(float(b[k]) / float(a[k]) - 1.3) < 0.01, "a third more strength, a third faster: the %s (%.1f against %.1f m/s)" % [k, b[k], a[k]])
	t.check(float(a.miss) < 0.02 and float(b.miss) < 0.02, "and still on the crosshair (%.3f and %.3f m off)" % [a.miss, b.miss])
	t.check(a.blows.size() == 2 and b.blows.size() == 2, "the dart and the discus land (%d, %d)" % [a.blows.size(), b.blows.size()])
	if a.blows.size() == 2 and b.blows.size() == 2:
		for i in 2:
			t.check(absf(float(b.blows[i]) / float(a.blows[i]) - 1.15) < 0.01, "half of it goes into the blow: %s (%.1f against %.1f)" % [["the dart", "the discus"][i], b.blows[i], a.blows[i]])
	m.queue_free()
