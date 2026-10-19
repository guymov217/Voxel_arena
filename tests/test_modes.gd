extends Node
## The fight modes (game.js checkRound, partyModes.js): who wins, what comes next.

var t

func _match(mode: String, opts := {}) -> Match:
	var m := Match.new()
	add_child(m)
	var o := {"mode": mode, "headless": true, "seed": 3, "decrees": [], "hazards": []}
	o.merge(opts, true)
	m.setup(o)
	return m

func _steps(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func test_free_for_all_ends_with_the_last_man() -> void:
	var m := _match("ffa")
	t.eq(m.entities.size(), 4, "the player and three bots")
	var teams := {}
	for e in m.entities:
		teams[e.team] = true
	t.eq(teams.size(), 4, "each for himself")
	var result := []
	m.finished.connect(func(r): result.append(r))
	for e in m.entities:
		if e != m.me:
			e.f.die("wounds")
	await _steps(2)
	t.check(m.over and not result.is_empty() and result[0].won, "the player won")
	m.queue_free()

func test_the_hunt_sends_wave_after_wave() -> void:
	var m := _match("hunt")
	var beasts := m.entities.filter(func(e): return e.kind == "beast")
	var w1: Array = Data.modes.huntWaves[0]
	t.eq(beasts.size(), int(w1[0].n), "wave 1 is the table's")
	for b in beasts:
		b.f.die("wounds")
	await _steps(2)
	t.eq(m.modes.wave, 2, "wave 2")
	t.check(m.entities.filter(func(e): return e.kind == "beast" and e.f.alive).size() > 0, "fresh beasts")
	t.check(m.modes.frozen(), "a countdown before they come")
	m.queue_free()

func test_the_king_stays_and_the_next_challenger_walks_in() -> void:
	var m := _match("king")
	var before := m.entities.size()
	for e in m.entities:
		if e != m.me:
			e.f.die("wounds")
	await _steps(2)
	t.eq(m.modes.king.streak, 1, "one bout held")
	t.eq(m.entities.size(), before + 1, "a challenger")
	t.check(not m.over, "the reign goes on")
	m.queue_free()

func test_best_of_three_pauses_for_the_loser_and_raises_the_stake() -> void:
	seed(1)
	var m := _match("bo3")
	var foe = m.entities[1]
	await _steps(260)
	foe.f.blood = 10.0
	await _steps(2)
	t.check(float(m.modes.bo3.pause) > 0.0, "a pause for the loser to choose")
	t.eq(int(m.modes.bo3.wins.get(m.me.id, 0)), 1, "round one to the player")
	foe.f.blood = 60.0
	await _steps(120 * 5)
	t.check(m.over or int(m.modes.bo3.round) == 2, "he yielded, or fought on into round 2")
	if not m.over:
		t.eq(int(m.modes.bo3.stake), 60, "for double the stake")
	m.queue_free()

func test_king_of_the_hill_counts_time_alone_in_the_circle() -> void:
	var m := _match("hill")
	var result := []
	m.finished.connect(func(r): result.append(r))
	m.modes.hill.score[m.me.id] = 20.5
	await _steps(2)
	t.check(m.over and result.size() == 1 and result[0].won, "twenty seconds on the hill wins")
	m.queue_free()

func test_last_limb_takes_a_limb_from_everyone() -> void:
	var m := _match("lastLimb")
	m.modes.chop_t = 0.0
	await _steps(2)
	for e in m.entities:
		t.check(e.f.parts.any(func(p): return p.severed), "%s lost a limb" % e.f.display_name)
	m.queue_free()

func test_head_football_scores_a_goal() -> void:
	var m := _match("headball")
	await _steps(2)
	var it = m.modes.ball_item()
	t.check(it != null, "the head is on the field")
	it.p = Vector3(-Modes.GOAL_X - 0.5, 0.2, 0)
	it.grounded = true
	await _steps(3)
	t.eq(m.modes.ball.score[1], 1, "a goal for Blue in Red's goal")
	m.queue_free()

func test_the_emperor_meddles_from_his_box() -> void:
	var m := _match("emperor")
	t.check(m.me == null, "the Emperor does not fight")
	t.check(m.entities.size() >= 2, "the fighters are in")
	m.modes._emperor(0.016, {"useItem": 0})
	t.check(not m.decrees.is_empty(), "key 1 decrees something")
	m.modes._emperor(0.016, {"useItem": 1})
	t.check(m.entities.any(func(e): return e.kind == "beast"), "key 2 lets a beast in")
	m.queue_free()

func test_co_op_waves_and_teams_split() -> void:
	var m := _match("coop")
	var bots := m.entities.filter(func(e): return e.kind == "bot")
	t.check(bots.size() >= 2 and bots.all(func(e): return e.team == 1), "the bots against the players")
	for b in bots:
		b.f.die("wounds")
	await _steps(2)
	t.eq(m.modes.wave, 2, "wave 2")
	m.queue_free()
	var t2 := _match("teams")
	var red := t2.entities.filter(func(e): return e.team == 0).size()
	var blue := t2.entities.filter(func(e): return e.team == 1).size()
	t.check(red == 2 and blue == 2, "two against two (%d, %d)" % [red, blue])
	t2.queue_free()

## A duel starts with the two a few strides apart, each facing the other, and the camera behind
## the player looking the same way (it does not turn him round).
func test_a_duel_starts_face_to_face() -> void:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "duel", "headless": true, "seed": 3, "decrees": [], "hazards": []})
	var foe = null
	for e in m.entities:
		if e != m.me:
			foe = e.f
	var me: Fighter = m.me.f
	var gap: Vector3 = foe.torso.global_position - me.torso.global_position
	gap.y = 0.0
	t.check(gap.length() >= 6.0, "room to square up (%.1f m)" % gap.length())
	var fwd := Vector3(sin(me.yaw), 0, cos(me.yaw))
	t.check(fwd.dot(gap.normalized()) > 0.9, "he faces his foe")
	m.queue_free()

## Training's difficulty reaches every kind of opponent: the sparring gladiator's skill, a
## beast's keenness (how soon it strikes again) and a campaign foe's skill.
func test_training_difficulty_reaches_every_opponent() -> void:
	for d in [0.2, 0.9]:
		var keen := {}
		for who in ["gladiator", "lion", "foe:giant"]:
			var m := _match("training", {"training": {"enemy": who, "count": 1, "difficulty": d, "behaviour": "fights"}})
			var foe = null
			for e in m.entities:
				if e != m.me:
					foe = e
			t.check(foe != null, "%s is there" % who)
			if foe == null:
				m.queue_free()
				continue
			if foe.f is Beast:
				t.eq(snappedf(foe.f.skill, 0.01), d, "the %s's keenness is the slider's %.1f" % [who, d])
				var head: VoxelPart = foe.f.head
				foe.f._strike(head, 0.3, 2.0, [], 0.0)
				keen[who] = float(foe.f.strike_cool[head])
			else:
				t.check(foe.has("bot"), "%s is a bot" % who)
				if foe.has("bot"):
					t.eq(snappedf(foe.bot.diff, 0.01), d, "the %s's skill is the slider's %.1f" % [who, d])
			m.queue_free()
		if d == 0.2:
			set_meta("slow", keen.get("lion", 0.0))
		else:
			t.check(float(keen.get("lion", 9.0)) < float(get_meta("slow", 0.0)), "a keener lion strikes again sooner (%.2f s against %.2f s)" % [keen.get("lion", 0.0), get_meta("slow", 0.0)])

## The menu's champion dressed again and again (the dressing screen) leaves no arms lying about,
## and the fight behind the menus starts again in place: the champion stays, fresh men come in.
func test_the_menu_champion_and_its_fight() -> void:
	var m := _match("ffa", {"autopilot": true})
	m.attract = true
	for k in 4:
		m.add_hero(Vector3(3, 0, -9), 0.0, {"main": "gladius", "off": "scutum"}, Color.RED, null, true)
		await _steps(4)
	await _steps(10)
	var loose := 0
	for n in m.get_children():
		if n is Weapon and not n.is_queued_for_deletion() and n.holder == null:
			loose += 1
	t.eq(loose, 0, "no sword or shield left lying from the earlier dressings")
	var hero := m.hero
	var before: Array = m.entities.map(func(e): return e.f)
	m.restart_attract({"mode": "ffa", "autopilot": true, "decrees": [], "hazards": [], "seed": 9})
	await _steps(4)
	t.check(m.hero == hero and is_instance_valid(hero), "the champion is still the same man")
	t.eq(m.entities.size(), before.size(), "a full set of fighters again")
	t.check(not m.entities.any(func(e): return before.has(e.f)), "and all of them fresh")
	t.check(not m.over, "the fight is on again")
	m.queue_free()
