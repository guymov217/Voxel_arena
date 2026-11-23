extends Node
## The endless arena with friends in the room: the waves grow with the party; the fallen stand up again as a wave is beaten;
## every one of them is patched up and picks a reward of his own (a pick not made in time is the first), and the next wave is
## called when all have picked; the run is over when all are down and is not a lone player's record; what a guest is told
## of his rewards is read back made safe; a guest has the fight's state line from the host.

var t

func _party(extra := 1) -> Match:
	var m := Match.new()
	add_child(m)
	var peers := []
	for i in extra:
		peers.append({"id": 7 + i, "name": "Friend%d" % i, "loadout": {"main": "gladius", "off": ""}, "kit": {}})
	m.setup({"mode": "endless", "role": "host", "headless": true, "seed": 3, "decrees": [], "hazards": [], "loadout": {"main": "gladius", "off": ""}, "endless": {"seed": 11}, "peers": peers})
	return m

func _steps(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func _names(list: Array) -> Array:
	return list.map(func(en): return String(en.get("e", en.get("beast", ""))) + ("*" if en.get("boss", false) else ""))

func test_the_waves_grow_with_the_party() -> void:
	var e := Endless.new(null, {"seed": 5})
	t.eq(e.plan(1, 1).size(), 1, "alone: one foe in the first wave")
	t.eq(e.plan(1, 2).size(), 2, "two players: two")
	t.eq(e.plan(1, 4).size(), 4, "four players: four")
	t.check(e.plan(30, 8).size() <= Endless.MOST_FOES, "never more than the host's physics can keep up with (%d)" % e.plan(30, 8).size())
	t.eq(e.plan(5, 1).size(), 1, "the first great foe alone comes alone")
	t.eq(e.plan(5, 3).size(), 2, "with two friends he has a man at his side")
	t.check(e.plan(15, 4).size() > e.plan(15, 1).size(), "a later great foe has more for a party")
	t.eq(str(_names(e.plan(3, 1))), str(_names(e.plan(3, 1))), "the same party, the same wave")
	t.eq(_names(e.plan(1, 3))[0], _names(e.plan(1, 1))[0], "the first foe of a wave is the one a lone player meets")

func test_the_rewards_a_guest_is_told_are_read_back_safe() -> void:
	var cards := [Endless.card("bind"), Endless.card("pot", "nailPot"), Endless.card("blade", "axe")]
	var back := Endless.clean_offer(Endless.offer_wire(cards))
	t.eq(back.size(), 3, "three rewards told, three read")
	t.eq(str(back.map(func(c): return c.id)), str(["bind", "pot", "blade"]), "each as it was")
	t.check(String(back[1].text).length() > 0 and String(back[2].title).length() > 0, "each with its words, made by the one who reads")
	t.eq(Endless.clean_offer("x").size(), 0, "not a list: nothing")
	t.eq(Endless.clean_offer([["pot", "hack"]]).size(), 0, "a pot the game has not: nothing")
	t.eq(Endless.clean_offer([["blade", "nonsense"]]).size(), 0, "a weapon the game has not: nothing")
	t.eq(Endless.clean_offer([["armour", "lorica"], ["armour", "crown_of_thorns"]]).size(), 1, "an armour piece the game has: kept; another: not")
	t.eq(Endless.clean_offer([[1, 2], ["bind"], "bind", ["unknown", ""]]).size(), 0, "rows that are not rows of two known words: nothing")
	t.eq(Endless.clean_offer([["bind", ""], ["bind", ""], ["bind", ""], ["bind", ""], ["bind", ""]]).size(), 3, "three at most")

func test_every_friend_picks_a_reward_of_his_own() -> void:
	var m := _party()
	var en: Endless = m.modes.endless
	t.check(en.party() and m.humans().size() == 2, "a party of two")
	en.update(Endless.START_DELAY + 0.1)
	t.eq(m.enemies().size(), en.plan(1, 2).size(), "two foes for two")
	for e in m.enemies():
		e.f.die("wounds")
	await _steps(3)
	t.eq(en.phase, "rest", "the wave beaten: a breath")
	t.eq(en.offers.size(), 2, "a reward on offer for each of them")
	t.check(en.offers.has(1) and en.offers.has(7), "the host (1) and his friend (7)")
	t.eq(en.offer.size(), 3, "the host's own three")
	t.check(en.rest_t > Endless.PICK_TIME - 1.0 and en.rest_t <= Endless.PICK_TIME, "the time they have (%.1f s)" % en.rest_t)
	var done := []
	en.picked_all.connect(func(): done.append(1))
	# Pinned: the friend is offered a pot.
	en.offers[7] = [Endless.card("pot", "nailPot")]
	var friend = en.entity_of(7)
	friend.inventory = {}
	en.take_for(7, 0)
	t.eq(int(friend.inventory.get("nailPot", 0)), 2, "his two pots in his own bag")
	t.eq(en.phase, "rest", "the host has not picked: the wave waits")
	t.check(done.is_empty(), "nobody told to go on")
	t.check(en.status().contains("still choosing"), "the line says who is still choosing (%s)" % en.status())
	en.take_for(7, 0)
	t.eq(int(friend.inventory.get("nailPot", 0)), 2, "a second pick of his is nothing")
	en.take_for(99, 0)
	t.eq(en.phase, "rest", "nor is a stranger's")
	en.take(0)
	t.eq(en.phase, "next", "all picked: the next horn")
	t.eq(done.size(), 1, "and the screens of the rewards told to close")
	en.update(Endless.START_DELAY + 0.1)
	t.eq(en.wave, 2, "wave 2 comes in")
	m.queue_free()

func test_a_pick_not_made_in_time_is_the_first() -> void:
	var m := _party()
	var en: Endless = m.modes.endless
	en.update(Endless.START_DELAY + 0.1)
	for e in m.enemies():
		e.f.die("wounds")
	await _steps(3)
	t.eq(en.phase, "rest", "beaten")
	en.update(Endless.PICK_TIME - 1.0)
	t.eq(en.phase, "rest", "not yet")
	t.eq(en.offers.size(), 2, "both still choosing")
	en.update(1.5)
	t.eq(en.phase, "next", "the time is out: the first reward of each is his, and the next horn")
	t.check(en.offers.is_empty(), "nothing left on offer")
	m.queue_free()

func test_the_fallen_stand_up_when_a_wave_is_beaten() -> void:
	var m := _party()
	var en: Endless = m.modes.endless
	en.update(Endless.START_DELAY + 0.1)
	var friend = en.entity_of(7)
	var friend_id: int = int(friend.id)
	friend.f.die("decap")   # (dead for good: no death's door for a man with no head)
	await _steps(2)
	t.check(not friend.f.alive, "the friend is dead")
	t.eq(en.phase, "fight", "one of them down: the wave goes on")
	var host: Fighter = m.me.f
	host.blood = 20.0
	for e in m.enemies():
		e.f.die("wounds")
	await _steps(3)
	t.eq(en.phase, "rest", "beaten")
	var up = en.entity_of(7)
	t.check(up != null and is_instance_valid(up.f) and up.f.alive, "the fallen friend is on his feet again")
	t.eq(int(up.id), friend_id, "the same man (the same place in everyone's game)")
	t.eq(int(up.get("peer", -1)), 7, "still his friend's")
	t.check(host.blood >= 20.0 + Endless.REST_HEAL - 0.5, "the host patched up (blood %.0f)" % host.blood)
	t.eq(en.offers.size(), 2, "and he is offered a reward too")
	m.queue_free()

## The fallen foes of the waves are carried off a few seconds after they fall (a long run filled the sand with them and the game
## hung, user), each of them slain all the same; a player's own body stays where it fell; a player standing over a foe keeps him a
## little longer.
func test_the_fallen_foes_are_carried_off_and_a_players_body_stays() -> void:
	var m := _party()
	var en: Endless = m.modes.endless
	en.corpse_linger = 1.0
	en.wave = 11
	en.update(Endless.START_DELAY + 0.1)   # (the twelfth: several foes)
	var foes := m.enemies()
	t.check(foes.size() >= 3, "a wave of several foes (%d)" % foes.size())
	var ids := foes.map(func(e): return int(e.id))
	var friend = en.entity_of(7)
	var friend_id: int = int(friend.id)
	# One foe dies, and a player stands over another who dies too.
	foes[0].f.die("wounds")
	foes[1].f.die("wounds")
	m.me.f.teleport(foes[1].f.torso.global_position + Vector3(1.0, 0.1, 0.0))
	friend.f.die("decap")   # (dead for good)
	await _steps(30)
	t.check(m.entity_by_id(ids[0]) != null, "a body lies where he fell for its linger (not yet carried off)")
	await _steps(120)
	t.check(m.entity_by_id(ids[0]) == null, "then the foe is carried off")
	t.check(m.entity_by_id(ids[1]) != null, "the one a player stands over is let lie a while longer")
	t.check(m.entity_by_id(friend_id) != null and not friend.f.alive, "a friend's own body stays where it fell")
	m.me.f.teleport(Vector3(0, 0.1, -20.0))
	await _steps(120 * 3)
	t.check(m.entity_by_id(ids[1]) == null, "and he is carried off too, the player gone or the longer wait up")
	t.check(m.entity_by_id(friend_id) != null, "the friend's body is still there")
	t.eq(en._gone, 2, "both are counted as slain")
	for e in m.enemies():
		e.f.die("wounds")
	await _steps(3)
	t.eq(en.phase, "rest", "the wave is beaten")
	t.eq(en.slain, foes.size(), "all of its foes slain, those carried off too (%d of %d)" % [en.slain, foes.size()])
	m.queue_free()

func test_one_at_deaths_door_is_up_for_the_rest() -> void:
	var m := _party()
	var en: Endless = m.modes.endless
	en.update(Endless.START_DELAY + 0.1)
	m.me.f.die("wounds")   # (his friend stands: he is at death's door, not dead)
	await _steps(2)
	t.check(m.me.f.alive and m.me.f.dying > 0.0, "at death's door (%.1f s)" % m.me.f.dying)
	for e in m.enemies():
		e.f.die("wounds")
	await _steps(3)
	t.eq(en.phase, "rest", "beaten")
	t.check(m.me.f.alive and m.me.f.dying <= 0.0, "up again for the rest")
	t.eq(en.offers.size(), 2, "both offered a reward")
	m.queue_free()

func test_the_party_falls_only_when_all_are_down() -> void:
	Save.set_value("endless", {"best": 2})
	var m := _party()
	var en: Endless = m.modes.endless
	en.update(Endless.START_DELAY + 0.1)
	en.wave = 6
	var result := []
	m.finished.connect(func(r): result.append(r))
	en.entity_of(7).f.die("decap")
	await _steps(4)
	t.eq(en.phase, "fight", "the friend is down but the host fights on")
	t.check(not m.over, "the run goes on")
	m.me.f.die("wounds")   # (nobody left to lift him: dead)
	await _steps(4)
	t.eq(en.phase, "over", "all down: the run is over")
	t.check(m.over and not result.is_empty() and not result[0].won, "lost")
	t.eq(int(Save.get_value("endless", {}).get("best", 0)), 2, "a room's run is nobody's lone record")
	m.queue_free()

func test_a_lone_players_run_is_still_his_record() -> void:
	Save.set_value("endless", {"best": 1})
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "endless", "headless": true, "seed": 3, "decrees": [], "hazards": [], "loadout": {"main": "gladius", "off": ""}, "endless": {"seed": 11}})
	var en: Endless = m.modes.endless
	t.check(en.is_solo() and not en.party(), "alone, on his own machine")
	en.update(Endless.START_DELAY + 0.1)
	for e in m.enemies():
		e.f.die("wounds")
	await _steps(3)
	t.eq(int(Save.get_value("endless", {}).get("best", 0)), 1, "wave 1 beaten: the best is 1")
	en.take(0)
	en.update(Endless.START_DELAY + 0.1)
	for e in m.enemies():
		e.f.die("wounds")
	await _steps(3)
	t.eq(int(Save.get_value("endless", {}).get("best", 0)), 2, "wave 2 beaten: the best is 2")
	m.queue_free()

func test_a_guest_reads_the_hosts_state_line() -> void:
	var g := Match.new()
	add_child(g)
	g.setup({"mode": "endless", "role": "guest", "headless": true, "decrees": [], "hazards": []})
	t.eq(g.fight_status(), Modes.title_of("endless"), "before the host says anything: the fight's name")
	g.guest_message("fstat", "Wave 4 · 3 slain")
	t.eq(g.fight_status(), "Wave 4 · 3 slain", "then what the host says")
	g.guest_message("fstat", 12345)
	t.eq(g.fight_status(), "Wave 4 · 3 slain", "a number is not a line")
	g.guest_message("fstat", "x".repeat(500))
	t.eq(g.fight_status().length(), 120, "a long one is cut")
	g.queue_free()
