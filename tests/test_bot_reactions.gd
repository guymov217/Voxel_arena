extends Node
## Bots react to a hit now and then like a man would (a hand to the wound, a jerk back, a stagger)
## and still come on: the reaction is short, seldom, and leaves the weapon hand alone.

var t

func _match() -> Match:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none"}, "headless": true, "seed": 3, "decrees": [], "hazards": []})
	return m

func _bot(m: Match, pos: Vector3, yaw: float, lo: Dictionary, team: int, pers := "standard") -> Dictionary:
	return m.spawn_fighter({"kind": "bot", "name": "B%d" % team, "loadout": lo, "team": team, "pos": pos, "yaw": yaw, "diff": 0.7, "personality": pers})

func _steps(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

## Hits `b` until it starts reacting (the chance is below one); returns the reaction or "".
func _provoke(b: Bot, part: String, dmg := 14.0) -> String:
	for i in 60:
		b.react_cd = 0.0
		b._on_hit(b.c, {"dmg": dmg, "part_name": part})
		if b.react != "":
			return b.react
	return ""

func test_a_hit_sometimes_makes_a_bot_clutch_the_wound_or_recoil() -> void:
	var m := _match()
	m.me.f.state = "dead"
	var e := _bot(m, Vector3(0, 0, 0), 0.0, {"main": "gladius", "off": ""}, 1)
	var foe := _bot(m, Vector3(0, 0, 3), PI, {"main": "gladius", "off": ""}, 0)
	await _steps(30)
	var b: Bot = e.bot
	t.check(_provoke(b, "torso") != "", "a solid hit on the body sets a reaction off")
	t.check(b.react_cd > b.react_t, "and the next one has to wait")
	var once := b.react
	b._on_hit(b.c, {"dmg": 30.0, "part_name": "head"})
	t.eq(b.react, once, "a second hit inside the cooldown does not restart it")
	var seen := {}
	for i in 40:
		b.react = ""
		b.react_cd = 0.0
		b._on_hit(b.c, {"dmg": 20.0, "part_name": "torso"})
		if b.react != "":
			seen[b.react] = true
	t.check(seen.size() >= 2, "different hits are met differently (%s)" % [seen.keys()])
	b.react = ""
	b.react_cd = 0.0
	for i in 40:
		b._on_hit(b.c, {"dmg": 1.0, "part_name": "torso"})
	t.eq(b.react, "", "a scratch is ignored")
	m.queue_free()

func test_the_free_hand_goes_to_the_wound_and_the_weapon_hand_is_left_alone() -> void:
	var m := _match()
	m.me.f.state = "dead"
	var e := _bot(m, Vector3(0, 0, 0), 0.0, {"main": "gladius", "off": ""}, 1)
	var foe := _bot(m, Vector3(0, 0, 3), PI, {"main": "gladius", "off": ""}, 0)
	await _steps(30)
	var b: Bot = e.bot
	b.react = "clutch"
	b.react_t = 1.0
	b.react_part = "head"
	var inp: Dictionary = b.update(1.0 / 120.0, foe.f, m._world_of(e))
	t.check(float(inp.off.y) > 0.9, "a blow to the head: the hand goes up to it (y %.2f)" % float(inp.off.y))
	b.react = "clutch"
	b.react_t = 1.0
	b.react_part = "thighL"
	inp = b.update(1.0 / 120.0, foe.f, m._world_of(e))
	t.check(float(inp.off.y) < -0.5, "a blow to the leg: the hand goes down to it (y %.2f)" % float(inp.off.y))
	var plan: Dictionary = b.update(1.0 / 120.0, foe.f, m._world_of(e))
	t.check(plan.main is Dictionary and plan.main.has("x"), "the main hand still has its plan")
	m.queue_free()

func test_a_man_with_a_shield_or_two_hands_flinches_instead_of_clutching() -> void:
	var m := _match()
	m.me.f.state = "dead"
	var e := _bot(m, Vector3(0, 0, 0), 0.0, {"main": "warhammer", "off": ""}, 1)
	var foe := _bot(m, Vector3(0, 0, 3), PI, {"main": "gladius", "off": ""}, 0)
	await _steps(30)
	var b: Bot = e.bot
	var kinds := {}
	for i in 60:
		b.react = ""
		b.react_cd = 0.0
		b._on_hit(b.c, {"dmg": 12.0, "part_name": "torso"})
		if b.react != "":
			kinds[b.react] = true
	t.check(not kinds.has("clutch") and not kinds.is_empty(), "both hands on a hammer: no clutching (%s)" % [kinds.keys()])
	m.queue_free()

## Two men with swords, one of them reacting to every hit he can; the other kind does not react
## at all. The reacting one still swings as much and hurts the other as much (within noise).
func _duel(reacts: bool, seed_: int) -> Dictionary:
	var m := _match()
	m.me.f.state = "dead"
	seed(seed_)
	var a := _bot(m, Vector3(-1.5, 0, 0), PI * 0.5, {"main": "gladius", "off": ""}, 1)
	var z := _bot(m, Vector3(1.5, 0, 0), -PI * 0.5, {"main": "gladius", "off": ""}, 0)
	var swings := 0
	var steps := 0
	var reactions := 0
	for i in 120 * 20:
		await get_tree().physics_frame
		steps += 1
		if not reacts:
			a.bot.react_cd = 1e9
		if a.bot.react != "":
			reactions += 1
		if a.bot.state == "attack":
			swings += 1
		if i % 240 == 0 and OS.get_environment("VA_DBG") != "":
			print("   t=%.0f dist=%.2f a=%s/%s blood %.0f z=%s blood %.0f" % [i / 120.0, a.f.torso.global_position.distance_to(z.f.torso.global_position), a.bot.state, a.f.state, a.f.blood, z.bot.state, z.f.blood])
		if not a.f.alive or not z.f.alive:
			break
	var out := {"swings": swings, "steps": steps, "reacting": reactions, "dealt": 100.0 - z.f.blood, "weapon": a.f.weapons.R != null or not a.f.alive or a.f.state != "stand"}
	m.queue_free()
	return out

func test_reacting_bots_stay_aggressive_and_keep_fighting_with_their_weapons() -> void:
	var with := {"swings": 0, "steps": 0, "reacting": 0, "dealt": 0.0}
	var without := {"swings": 0, "steps": 0, "reacting": 0, "dealt": 0.0}
	var armed := 0
	var armed0 := 0
	for s in [11, 12, 13, 14, 15, 16]:
		var r := await _duel(true, s)
		var n := await _duel(false, s)
		armed += 1 if r.weapon else 0
		armed0 += 1 if n.weapon else 0
		for k in with:
			with[k] += r[k]
			without[k] += n[k]
	print("  with reactions: %s\n  without:        %s" % [with, without])
	t.check(with.reacting > 0, "the reacting bots did react in a real fight (%d steps)" % with.reacting)
	t.eq(without.reacting, 0, "and the control group did not")
	# (Six duels a side are noisy: the control group alone swung 0.47 of the time in one build and
	# 0.65 in the next, with nothing about reactions changed. Only a bot made passive fails this.)
	t.check(float(with.swings) / with.steps >= 0.65 * float(without.swings) / without.steps, "they spend nearly as much of the fight swinging (%.2f vs %.2f)" % [float(with.swings) / with.steps, float(without.swings) / without.steps])
	t.check(with.dealt >= 0.5 * without.dealt, "and hurt the other man nearly as much (%.0f vs %.0f blood)" % [with.dealt, without.dealt])
	t.check(float(with.reacting) / with.steps < 0.2, "reacting is a small part of the fight (%.0f%%)" % (100.0 * with.reacting / with.steps))
	t.check(armed >= armed0 - 1, "they hold on to their swords as often as the others (%d vs %d of 6 duels)" % [armed, armed0])

func test_the_fist_really_comes_up_to_the_place_that_was_hit() -> void:
	var m := _match()
	m.me.f.state = "dead"
	var e := _bot(m, Vector3(0, 0, 0), 0.0, {"main": "gladius", "off": ""}, 1)
	var foe := _bot(m, Vector3(0, 0, 3), PI, {"main": "gladius", "off": ""}, 0)
	e.drive = func(_e): return {}
	e.erase("bot")
	foe.f.state = "dead"   # (nobody to hit him while his hand is measured)
	await _steps(60)
	var f: Fighter = e.f
	var b := Bot.new(f, 0.7, "standard", 5)
	var res := {}
	for part in ["head", "torso", "thighL"]:
		var best := 99.0
		for i in 150:
			b.react = "clutch"
			b.react_t = 1.0
			b.react_part = part
			e.drive = func(_e): return {"off": b._wound_mark(part), "main": {"x": 0.1, "y": 0.1}}
			await get_tree().physics_frame
			var target: Vector3 = (f.head if part == "head" else (f.torso if part == "torso" else f.by_name["thighL"])).global_position
			best = minf(best, f.hand_world("L").distance_to(target))
		res[part] = best
	print("  fist-to-wound distances: %s (body scale %.2f)" % [res, f.S])
	t.check(res.head < 0.5 * f.S, "the fist reaches the head (%.2f)" % res.head)
	t.check(res.torso < 0.5 * f.S, "the fist reaches the chest (%.2f)" % res.torso)
	t.check(res.thighL < 0.55 * f.S, "the fist reaches the thigh (%.2f)" % res.thighL)
	m.queue_free()
