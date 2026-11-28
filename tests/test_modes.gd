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

# ---------- A fight on a clock (user: Free For All on time, most kills wins, whoever dies stands up again and fights on) ----------

func test_a_free_for_all_on_a_clock_counts_kills_and_ends_on_the_clock() -> void:
	var m := _match("ffa", {"time_n": 3})
	m.modes.wait_t = 0.0
	t.eq(m.modes.time_s, 180.0, "three minutes on the clock")
	t.check(m.fight_status().contains("3:00"), "the state line has the clock (%s)" % m.fight_status())
	var result := []
	m.finished.connect(func(r): result.append(r))
	var foe: Dictionary = m.entities.filter(func(e): return e.kind == "bot")[0]
	# One bot falls to the player's blow: a kill for him; the last standing is no end of it, with the clock running.
	foe.f.last_attacker = m.me.f
	foe.f.die("wounds")
	await _steps(3)
	t.eq(int(m.modes.dm.kills.get(m.me.id, 0)), 1, "the kill is the player's")
	var rows: Array = m.modes.board()
	t.check(rows.size() == 4 and rows[0][4] == m.me.id and rows[0][1] == 1, "the board: the player first with one kill (%s)" % str(rows))
	for e in m.entities:
		if e != m.me and e.kind == "bot" and e.f.alive:
			e.f.die("wounds")
	await _steps(3)
	t.check(not m.over and result.is_empty(), "every foe fallen is no end of it: they stand up again")
	t.check(m.fight_status().contains(m.me.f.display_name), "the leader is on the state line (%s)" % m.fight_status())
	m.queue_free()

func test_the_fallen_stand_up_again_where_nobody_is() -> void:
	var m := _match("ffa", {"time_n": 5})
	m.modes.wait_t = 0.0
	var foe: Dictionary = m.entities.filter(func(e): return e.kind == "bot")[0]
	var id: int = foe.id
	var name_: String = foe.f.display_name
	var n0 := m.entities.size()
	foe.f.die("wounds")
	await _steps(3)
	t.check(m.modes.dm.fell.has(id) and int(m.modes.dm.deaths.get(id, 0)) == 1, "his fall is counted, and he lies a while")
	var old_f = foe.f
	m.modes.dm.fell[id] = 0.01
	await _steps(4)
	var back = m.entity_by_id(id)
	t.check(back != null and back.f.alive and not is_same(back.f, old_f), "he is a new man, on his feet, with the same name (%s)" % name_)
	t.eq(m.entities.size(), n0, "the same number on the sand")
	t.eq(String(back.f.display_name), name_, "and the same name")
	t.check(int(m.modes.dm.deaths.get(id, 0)) == 1, "his deaths are not lost")
	# Where nobody is: farther from every man on his feet than a corner of the ring.
	var p: Vector3 = back.f.torso.global_position
	var near := 99.0
	for e in m.entities:
		if e != back and e.f.alive:
			near = minf(near, Vector2(e.f.torso.global_position.x - p.x, e.f.torso.global_position.z - p.z).length())
	t.check(near > 3.0, "not among the others (%.1f m from the nearest)" % near)
	m.queue_free()

func test_the_player_who_falls_stands_up_again_and_is_his_own_man_still() -> void:
	var m := _match("ffa", {"time_n": 5})
	m.modes.wait_t = 0.0
	var id: int = m.me.id
	m.me.f.die("wounds")
	await _steps(3)
	m.modes.dm.fell[id] = 0.01
	await _steps(4)
	t.check(m.me != null and m.me.id == id and m.me.f.alive, "the player is on his feet again, and `me` is the new man")
	t.check(m.cam != null or m.headless, "the view has a man to follow")
	m.queue_free()

func test_a_man_who_stands_up_again_is_still_the_one_who_struck_last() -> void:
	var m := _match("ffa", {"time_n": 5, "killcam": true})
	m.modes.wait_t = 0.0
	var bots: Array = m.entities.filter(func(e): return e.kind == "bot")
	var a: Dictionary = bots[0]
	var b: Dictionary = bots[1]
	var c: Dictionary = bots[2]
	var old = a.f
	b.f.last_attacker = old
	var back: Dictionary = m.respawn_player(a)
	await _steps(3)
	t.check(is_instance_valid(b.f.last_attacker) and is_same(b.f.last_attacker, back.f) and not is_same(b.f.last_attacker, old), "the man he struck last was struck by him as he is now, not by a body that is gone")
	# A man carried off the sand is nobody's last blow: no freed man is left in the place of one.
	c.f.last_attacker = b.f
	m.remove_corpse(b)
	await _steps(3)
	t.check(c.f.last_attacker == null, "a man taken off the sand is nobody's last blow")
	# And the kill cam does not take a freed man for a killer.
	var gone := Node.new()
	gone.free()
	m.killcam.on_death(c.f, "wounds", {}, gone)
	var k: Dictionary = m.killcam.pending.back()
	t.check(k.killer == null and k.killer_node == null and not bool(k.friendly), "a killer freed since the blow is no killer on the tape")
	m.queue_free()

func test_the_clock_out_the_most_kills_wins_and_a_level_score_is_a_draw() -> void:
	var m := _match("ffa", {"time_n": 3})
	m.modes.wait_t = 0.0
	var result := []
	m.finished.connect(func(r): result.append(r))
	m.modes.dm.kills[m.me.id] = 4
	var other: Dictionary = m.entities.filter(func(e): return e.kind == "bot")[0]
	m.modes.dm.kills[other.id] = 2
	m.modes.dm.t = 179.99
	await _steps(4)
	t.check(m.over and not result.is_empty() and result[0].won, "the clock is out: the most kills, the player's, wins")
	m.queue_free()
	await get_tree().physics_frame
	var m2 := _match("ffa", {"time_n": 3})
	m2.modes.wait_t = 0.0
	var result2 := []
	m2.finished.connect(func(r): result2.append(r))
	m2.modes.dm.kills[m2.me.id] = 3
	var o2: Dictionary = m2.entities.filter(func(e): return e.kind == "bot")[0]
	m2.modes.dm.kills[o2.id] = 3
	m2.modes.dm.t = 179.99
	await _steps(4)
	t.check(m2.over and not result2.is_empty() and not result2[0].won, "level on kills and on deaths: a draw")
	m2.queue_free()

func test_a_team_fight_on_a_clock_counts_the_teams_kills() -> void:
	var m := _match("teams", {"time_n": 3, "bots": 3})
	m.modes.wait_t = 0.0
	var mine: Dictionary = m.me
	var foe: Dictionary = m.entities.filter(func(e): return e.kind == "bot" and int(e.team) % 2 != int(mine.team) % 2)[0]
	foe.f.last_attacker = m.me.f
	foe.f.die("wounds")
	await _steps(3)
	t.eq(int(m.modes.dm.kills.get(mine.id, 0)), 1, "a kill of the other side counts")
	var mate: Dictionary = m.entities.filter(func(e): return e.kind == "bot" and int(e.team) % 2 == int(mine.team) % 2 and e != mine)[0]
	mate.f.last_attacker = m.me.f
	mate.f.die("wounds")
	await _steps(3)
	t.eq(int(m.modes.dm.kills.get(mine.id, 0)), 1, "a team-mate's does not")
	t.check(m.fight_status().contains(Loc.t("Red")) and m.fight_status().contains(Loc.t("Blue")), "the state line has both sides' kills (%s)" % m.fight_status())
	m.modes.dm.t = 179.99
	var result := []
	m.finished.connect(func(r): result.append(r))
	await _steps(4)
	t.check(m.over and not result.is_empty() and result[0].won == (int(mine.team) % 2 == int(mine.team) % 2), "the clock is out: the side with the most kills wins (the player's)")
	m.queue_free()

func test_the_hill_stands_the_fallen_up_again_and_the_last_standing_is_no_end() -> void:
	var m := _match("hill")
	m.modes.wait_t = 0.0
	for e in m.entities:
		if e != m.me:
			e.f.die("wounds")
	await _steps(4)
	t.check(not m.over, "every foe fallen: the hill goes on, they stand up again")
	var fell: Array = m.modes.dm.fell.keys()
	t.eq(fell.size(), 3, "the three lie a while")
	for id in fell:
		m.modes.dm.fell[id] = 0.01
	await _steps(4)
	t.eq(m.entities.filter(func(e): return e.f.alive).size(), 4, "and the four are on their feet again")
	m.queue_free()

func test_a_friend_who_fell_in_the_hunt_stands_up_again_as_the_wave_is_beaten() -> void:
	var m := _match("hunt", {"peers": [{"id": 7, "name": "Friend0", "loadout": {"main": "gladius", "off": ""}, "kit": {}}]})
	m.modes.wait_t = 0.0
	var friend: Dictionary = m.entities.filter(func(e): return e.kind == "remote")[0]
	var id: int = friend.id
	friend.f.die("wounds")
	await _steps(2)
	t.check(not m.entity_by_id(id).f.alive or m.entity_by_id(id).f.dying > 0.0, "he lies (at death's door, as a friend in a party does: a friend may lift him)")
	for e in m.entities.filter(func(x): return x.kind == "beast"):
		e.f.die("wounds")
	await _steps(4)
	var back = m.entity_by_id(id)
	t.check(back != null and back.f.alive and back.f.dying <= 0.0 and not is_same(back.f, friend.f), "the wave is beaten: the fallen friend is a new man on his feet again")
	t.eq(m.modes.wave, 2, "and the next wave comes")
	t.eq(m.humans().size(), 2, "the party is the two of them")
	m.queue_free()

func test_a_fallen_player_looks_on_where_the_fallen_do_not_stand_up_again() -> void:
	var m := _match("ffa", {"time_n": 0})
	m.modes.wait_t = 0.0
	m.me.f.die("wounds")
	await _steps(30)
	t.check(not m.watching(), "he has just fallen: his own view still")
	await _steps(200)
	t.check(m.watching(), "a moment later the view is the fight's: the others fight on, and he looks on")
	m.queue_free()
	await get_tree().physics_frame
	var timed := _match("ffa", {"time_n": 3})
	timed.modes.wait_t = 0.0
	timed.me.f.die("wounds")
	timed.modes.dm.fell[timed.me.id] = 99.0
	await _steps(230)
	t.check(not timed.watching(), "where the fallen stand up again he stays in his own view")
	timed.queue_free()

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

## With a screen the next wave is built over the frames that follow (Match.bring_in), not in the
## frame the last beast of the wave before falls (a wave of beasts in one frame was a stop of a
## second and more, user: the frame rate drops); and no third wave is called for while the
## second is still on its way in.
func test_the_hunts_next_wave_comes_in_over_the_frames_that_follow() -> void:
	var m := _match("hunt")
	m.stage_always = true
	for b in m.entities.filter(func(e): return e.kind == "beast"):
		b.f.die("wounds")
	await _steps(2)
	t.eq(m.modes.wave, 2, "wave 2 called for")
	var want := 0
	for g in Data.modes.huntWaves[1]:
		want += 1 if g.get("boss", false) else int(g.n)
	t.eq(m.coming, want, "all of it on its way in (%d)" % want)
	t.eq(m.entities.filter(func(e): return e.kind == "beast" and e.f.alive).size(), 0, "none of it on the sand in the frame the last of the first wave fell")
	var frames := 0
	var waves := 2
	while m.coming > 0 and frames < 3000:
		await get_tree().process_frame
		frames += 1
		waves = maxi(waves, int(m.modes.wave))
	t.check(frames > 8 and frames < 3000, "built over the frames that follow (%d of them)" % frames)
	t.eq(m.entities.filter(func(e): return e.kind == "beast" and e.f.alive).size(), want, "then all of it on the sand")
	await _steps(4)
	t.eq(maxi(waves, int(m.modes.wave)), 2, "and no third wave called for meanwhile")
	t.check(not m.over, "the hunt goes on")
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

## Level on rounds, one each, and the man down yields: the duel goes to the other man, whichever
## of the two it is who yields (sorted by the rounds alone, it went to whoever was first on the
## list, the man who had just yielded as often as not).
func test_best_of_three_level_goes_to_the_man_who_did_not_yield() -> void:
	for who in ["the player", "his foe"]:
		var m := _match("bo3")
		var result := []
		m.finished.connect(func(r): result.append(r))
		var me = m.me
		var foe = m.entities[1]
		m.modes.bo3.wins = {me.id: 1, foe.id: 1}
		m.modes.bo3.round = 2
		m.modes.bo3.loser = me if who == "the player" else foe
		m.modes._bo3_end()
		for i in 30:
			await get_tree().physics_frame
			if not result.is_empty():
				break
		t.check(not result.is_empty(), "the duel is over")
		if not result.is_empty():
			t.eq(bool(result[0].won), who != "the player", "%s yields at one round each: the duel is the other man's" % who)
		m.queue_free()
		await get_tree().physics_frame

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
