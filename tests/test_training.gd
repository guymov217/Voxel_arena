extends Node
## The trainer: six abilities bought a session at a time, capped by the bout and their own
## limit, dearer every time; what they teach shows in the man (his breath, his footing, his
## blow) and nothing is learned in the arena itself.

var t

func test_the_trainer_sells_sessions_within_the_bouts_cap() -> void:
	Edition.forced = false
	t.eq(Training.cap("vis", 1), 0, "nothing before the first bout is won")
	t.eq(Training.cap("vis", 6), 4, "a per cent a bout, in whole sessions (bout 6: 4%)")
	t.eq(Training.cap("vis", 40), 16, "and never past the ability's own limit")
	t.eq(Training.cap("corium", 40), 24, "hide goes further")
	var st := {}
	var r := Training.buy(st, "vis", 1, 1000)
	t.check(r.has("error"), "bout 1: nothing to teach yet (%s)" % r.get("error", ""))
	r = Training.buy(st, "vis", 5, 30)
	t.check(r.has("error") and String(r.error).begins_with("Not enough"), "no denarii, no session")
	r = Training.buy(st, "vis", 5, 100)
	t.check(not r.has("error") and int(r.cost) == 40 and int(r.stats.vis) == 2, "the first session: 40 denarii, +2%%")
	st = r.stats
	t.eq(Training.price(st, "vis"), 70, "the next costs more")
	r = Training.buy(st, "vis", 5, 1000)
	st = r.stats
	r = Training.buy(st, "vis", 5, 1000)
	t.check(r.has("error"), "bout 5 allows 4%%: the third session waits (%s)" % r.get("error", ""))
	t.eq(Training.sanitize({"vis": 7, "bogus": 3, "corium": 99, "sanguis": "x"}).get("vis"), 6, "a save is made safe: whole sessions")
	t.eq(Training.sanitize({"corium": 99}).corium, 24, "and within the limit")
	var m := Training.mods_of({"vis": 10, "sanguis": 20, "spiritus": 6, "firmitas": 8, "ictus": 4, "corium": 12})
	t.check(is_equal_approx(m.strength, 1.1) and is_equal_approx(m.bleed, 0.8) and is_equal_approx(m.wind, 1.06) and is_equal_approx(m.footing, 1.08) and is_equal_approx(m.blow, 1.04) and is_equal_approx(m.toughness, 1.12), "the abilities become the man's mods (%s)" % [m])
	Edition.forced = true
	t.eq(Training.cap("corium", 40), Training.DEMO_MAX, "the demo's trainer teaches two sessions")
	Edition.forced = null

## What he was taught shows in him: more breath, a steadier stance, a heavier blow.
func test_training_shows_in_the_man() -> void:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none"}, "headless": true, "seed": 3, "mods": Training.mods_of({"spiritus": 20, "firmitas": 20, "ictus": 14, "vis": 10})})
	var me: Fighter = m.me.f
	t.check(is_equal_approx(float(me.mods.strength), 1.1) and is_equal_approx(float(me.mods.blow), 1.14), "the mods are on him")
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
