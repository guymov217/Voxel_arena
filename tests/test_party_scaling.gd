extends Node
## A party's bout is a little harder for every friend (user, #347: bosses a little harder for each player added, mainly in health, skill and damage; the bout's ordinary foes a little
## too, in damage and skill, not much): Data.duel tells what each foe is harder by, the match multiplies it into the foe as it builds him (a man or a beast), Combat reads the damage.

var t

func _foes(st: Dictionary) -> Array:
	var out := []
	for r in st.rounds:
		out.append_array(r)
	out.append_array(st.get("late", []))
	return out

# ---------- What Data.duel tells ----------

func test_every_friend_more_makes_every_foe_a_little_harder() -> void:
	for n in [5, 6, 26]:
		for players in [1, 2, 3, 4]:
			var foes := _foes(Data.stage(n, players))
			t.check(not foes.is_empty(), "bout %d has foes for %d" % [n, players])
			for f in foes:
				if players == 1:
					t.check(not f.has("party_dmg") and not f.has("party_skill"), "alone (bout %d): a foe as the ladder wrote him" % n)
				else:
					t.check(is_equal_approx(float(f.party_dmg), 1.0 + Data.FOE_DAMAGE * (players - 1)) and is_equal_approx(float(f.party_skill), 1.0 + Data.FOE_SKILL * (players - 1)), "bout %d for %d: his blows %.2f, his wits %.2f" % [n, players, float(f.party_dmg), float(f.party_skill)])
					t.check(not f.has("party_hp") and not f.has("party_str"), "an ordinary foe is no tougher or stronger for a party")
	t.eq(Data.stage(5, 3).late.size(), 1, "(bout 5 keeps a man for the second wave)")
	var late: Dictionary = Data.stage(5, 3).late[0]
	t.check(late.has("party_dmg"), "the second wave's man is harder too")

func test_a_boss_is_harder_in_health_strength_damage_and_skill() -> void:
	# A man (the Cyclops, 4), a beast (the Big Lion, 8), a giant (16).
	for n in [4, 8, 16]:
		for players in [2, 3, 4]:
			var foes := _foes(Data.stage(n, players))
			t.eq(foes.size(), 1, "a boss comes alone (bout %d)" % n)
			var f: Dictionary = foes[0]
			var k := float(players - 1)
			t.check(is_equal_approx(float(f.party_hp), 1.0 + Data.BOSS_HEALTH * k) and is_equal_approx(float(f.party_str), 1.0 + Data.BOSS_STRENGTH * k), "bout %d for %d: %.2f tougher, %.2f stronger" % [n, players, float(f.party_hp), float(f.party_str)])
			t.check(is_equal_approx(float(f.party_dmg), 1.0 + Data.BOSS_DAMAGE * k) and is_equal_approx(float(f.party_skill), 1.0 + Data.BOSS_SKILL * k), "his blows %.2f harder, his wits %.2f keener" % [float(f.party_dmg), float(f.party_skill)])
			t.check(not f.has("mods"), "and what he is himself is not written over (no toughness or strength of its own)")
	var alone: Dictionary = _foes(Data.stage(8, 1))[0]
	t.check(not alone.has("party_hp") and not alone.has("party_dmg"), "alone, the boss as he was")
	t.check(Data.BOSS_DAMAGE > Data.FOE_DAMAGE and Data.BOSS_SKILL > Data.FOE_SKILL, "a boss more than the rest")

# ---------- What the match makes of it ----------

func _specs(stage_n: int, players: int) -> Array:
	var m := Match.new()
	add_child(m)
	m.rng.seed = 3
	m.mode = "campaign"
	m.stage = stage_n
	var out := []
	var st := Data.stage(stage_n, players)
	var list := _foes(st)
	for i in list.size():
		m.rng.seed = 3 + i
		out.append(m.enemy_spec(list[i], i, list.size()))
	m.queue_free()
	return out

func test_a_party_boss_is_the_solo_boss_and_more_never_less() -> void:
	# The giant (16), the troll (28), the titan (40) have a toughness and a strength of their own; a party met a boss with a lesser one than one man did.
	for n in [4, 16, 28, 40]:
		var solo: Dictionary = _specs(n, 1)[0]
		var pair: Dictionary = _specs(n, 2)[0]
		var four: Dictionary = _specs(n, 4)[0]
		t.eq(solo.kind, "bot", "bout %d: a man" % n)
		var ts := float(solo.mods.get("toughness", 1.0))
		var ss := float(solo.mods.get("strength", 1.0))
		t.check(is_equal_approx(float(pair.mods.toughness), ts * 1.35) and is_equal_approx(float(four.mods.toughness), ts * 2.05), "bout %d: tougher than himself, 35%% for a pair (%.2f of %.2f), 105%% for four (%.2f)" % [n, float(pair.mods.toughness), ts, float(four.mods.toughness)])
		t.check(is_equal_approx(float(pair.mods.strength), ss * 1.08) and is_equal_approx(float(four.mods.strength), ss * 1.24), "and stronger than himself (%.2f of %.2f)" % [float(pair.mods.strength), ss])
		t.check(float(pair.mods.toughness) > ts and float(pair.mods.strength) > ss, "never weaker for a party than for one man")
		t.check(float(pair.foe_dmg) > 1.0 and float(solo.foe_dmg) == 1.0, "his blows harder for a party only")
	# A beast boss, who had nothing of it.
	var lion_solo: Dictionary = _specs(8, 1)[0]
	var lion_four: Dictionary = _specs(8, 4)[0]
	t.eq(lion_solo.kind, "beast", "bout 8: a beast")
	t.check(is_equal_approx(float(lion_four.hp_k), 2.05) and is_equal_approx(float(lion_four.str_k), 1.24) and is_equal_approx(float(lion_four.foe_dmg), 1.3) and is_equal_approx(float(lion_four.skill_k), 1.15), "its spec for four: 2.05 tougher, 1.24 stronger, 1.3 harder, 1.15 keener (%s)" % str([lion_four.hp_k, lion_four.str_k, lion_four.foe_dmg, lion_four.skill_k]))
	t.check(float(lion_solo.hp_k) == 1.0 and float(lion_solo.foe_dmg) == 1.0 and float(lion_solo.skill_k) == 1.0, "alone: as it was")

func test_an_ordinary_foe_thinks_keener_for_a_party_by_a_little() -> void:
	var solo: Dictionary = _specs(3, 1)[0]
	var four: Dictionary = _specs(3, 4)[0]
	t.eq([solo.kind, four.kind], ["bot", "bot"], "bout 3 is a bout of men")
	if solo.kind != "bot" or four.kind != "bot":
		return
	t.check(is_equal_approx(float(four.diff) / float(solo.diff), 1.0 + Data.FOE_SKILL * 3.0), "his skill %.3f for four against %.3f alone" % [float(four.diff), float(solo.diff)])
	t.check(is_equal_approx(float(four.foe_dmg), 1.0 + Data.FOE_DAMAGE * 3.0) and float(solo.foe_dmg) == 1.0, "his blows a little harder")
	t.eq(float(four.mods.get("toughness", 1.0)), float(solo.mods.get("toughness", 1.0)), "and no tougher")
	t.eq(float(four.mods.get("strength", 1.0)), float(solo.mods.get("strength", 1.0)), "nor stronger")

func test_the_foes_are_built_as_the_party_makes_them() -> void:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none", "respawn": false}, "headless": true, "seed": 3, "decrees": [], "hazards": []})
	m.me.f.teleport(Vector3(0, 0, -12))
	# A beast boss, alone and for four.
	var solo: Dictionary = _specs(8, 1)[0]
	var four: Dictionary = _specs(8, 4)[0]
	solo.pos = Vector3(-6.0, 0.1, 4.0)
	four.pos = Vector3(6.0, 0.1, 4.0)
	var bs = m.spawn_beast(solo)
	var bf = m.spawn_beast(four)
	var ts := float(bs.f.mods.toughness)
	t.check(is_equal_approx(float(bf.f.mods.toughness) / ts, 2.05), "the beast boss built 2.05 times as tough for four (%.2f against %.2f)" % [float(bf.f.mods.toughness), ts])
	t.check(is_equal_approx(float(bf.f.mods.strength) / float(bs.f.mods.strength), 1.24), "and 1.24 times as strong")
	t.check(is_equal_approx(float(bf.f.foe_dmg), 1.3) and float(bs.f.foe_dmg) == 1.0, "its blows 1.3 times as hard")
	t.check(float(bf.f.skill) > float(bs.f.skill) and is_equal_approx(float(bf.f.skill), minf(1.0, float(bs.f.skill) * 1.15)), "and its wits keener (%.3f against %.3f)" % [float(bf.f.skill), float(bs.f.skill)])
	# A man, alone and for four: his skill as the Bot has it (capped at one), his blows.
	var man1: Dictionary = _specs(3, 1)[0]
	var man4: Dictionary = _specs(3, 4)[0]
	t.eq([man1.kind, man4.kind], ["bot", "bot"], "bout 3 is a bout of men")
	man1.pos = Vector3(-6.0, 0.1, -3.0)
	man4.pos = Vector3(6.0, 0.1, -3.0)
	var e1 = m.spawn_fighter(man1)
	var e4 = m.spawn_fighter(man4)
	t.check(float(e4.f.foe_dmg) > 1.0 and float(e1.f.foe_dmg) == 1.0, "a man's blows harder for four (%.2f)" % float(e4.f.foe_dmg))
	t.check(e4.bot.diff >= e1.bot.diff and is_equal_approx(e4.bot.diff, clampf(float(man4.diff), 0.1, 1.0)), "and his wits keener, as far as a man's can be (%.3f against %.3f)" % [e4.bot.diff, e1.bot.diff])
	t.check(float(m.me.f.foe_dmg) == 1.0, "a player's own blows are never touched")
	m.queue_free()
	await get_tree().physics_frame

# ---------- What a blow does ----------

## A kick by a man whose blows land `k` harder, at a man standing before him: how hard it lands (a plain kick's 20, a fixed number) and what it does.
func _kick(k: float) -> Dictionary:
	seed(100)
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none", "respawn": false}, "headless": true, "seed": 3, "decrees": [], "hazards": []})
	m.me.f.teleport(Vector3(0, 0, -12))
	var a = m.spawn_fighter({"kind": "bot", "name": "A", "loadout": {}, "team": 2, "pos": Vector3(0, 0, -0.85), "yaw": 0.0})
	a.erase("bot")
	var v = m.spawn_fighter({"kind": "bot", "name": "V", "loadout": {}, "team": 1, "pos": Vector3(0, 0, 0), "yaw": PI})
	v.erase("bot")
	v.drive = func(_e): return {}
	a.f.foe_dmg = k
	var st := {"kick": false}
	a.drive = func(_e):
		var o := {"kick": st.kick}
		st.kick = false
		return o
	for i in 100:
		await get_tree().physics_frame
	var out := {"J": [], "dmg": []}
	m.combat.hit.connect(func(h):
		if h.get("kick", false) and h.char == v.f:
			out.J.append(float(h.get("J", 0.0)))
			out.dmg.append(float(h.res.get("dmg", 0.0))))
	st.kick = true
	for i in 160:
		await get_tree().physics_frame
	m.queue_free()
	await get_tree().physics_frame
	return out

func test_a_foe_of_a_party_lands_his_blows_harder() -> void:
	var one := await _kick(1.0)
	var harder := await _kick(1.3)
	t.check(one.J.size() >= 1 and harder.J.size() >= 1, "the kick lands both times (%d, %d)" % [one.J.size(), harder.J.size()])
	if one.J.size() >= 1 and harder.J.size() >= 1:
		t.check(absf(float(one.J[0]) - 20.0) < 0.5, "a plain kick lands 20 (%.1f)" % float(one.J[0]))
		t.check(absf(float(harder.J[0]) / float(one.J[0]) - 1.3) < 0.02, "a foe whose blows are 1.3 times as hard lands 1.3 times that (%.1f)" % float(harder.J[0]))
		t.check(float(harder.dmg[0]) >= float(one.dmg[0]), "and does no less (%.1f against %.1f)" % [float(harder.dmg[0]), float(one.dmg[0])])
	# Nothing can take the blows below what they were, nor past a third more than any man's.
	var junk := await _kick(0.2)
	if junk.J.size() >= 1:
		t.check(absf(float(junk.J[0]) - 20.0) < 0.5, "a multiplier under one is none: foes are never made weaker by it (%.1f)" % float(junk.J[0]))
