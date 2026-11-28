extends Node
## The duel and the king's court with friends in the room (user: every mode of the Arena fits many players): each bout is a pair of the room, the rest of it looking on; the duel is the pair's, over
## the rounds the host set; the court keeps a line, the winner stays, the loser goes to the back, and the first to the number of wins is crowned. Alone against bots both are as they were.

var t

func _menu() -> Node:
	var menu = load("res://scripts/ui/menu.gd").new()
	menu.backdrop_off = true
	menu.series_look_ms = 100
	menu.series_score_ms = 100
	add_child(menu)
	return menu

func _steps(n: int) -> void:
	for i in n:
		await get_tree().process_frame

## A friends' room with `n` friends (peers 7, 8, 9...) and the host's menu in it.
func _room(n: int) -> Array:
	var menu := _menu()
	await _steps(2)
	var fake := Match.new()
	fake.mode = "yard"
	add_child(fake)
	menu.match_ = fake
	Net.transport = "test"
	Net.room_kind = Net.KIND_ARENA
	menu._box_on()
	Net.peers.clear()
	for i in n:
		Net.peers[7 + i] = {"name": "Friend%d" % i, "loadout": {"main": "gladius", "off": ""}, "kit": {}}
	var st: Dictionary = Save.get_value("settings", {})
	st["killcam"] = false
	Save.set_value("settings", st)
	return [menu, fake]

func _leave(pair: Array) -> void:
	pair[0]._end_match()
	pair[0]._box_off()
	pair[0].match_ = null
	if is_instance_valid(pair[1]):
		pair[1].queue_free()
	pair[0].queue_free()
	Net.peers.clear()
	Net.transport = ""
	Net.room_kind = Net.KIND_CAMPAIGN

func _bout_waiting(menu: Node, was: Match, ms := 9000) -> Match:
	var t0 := Time.get_ticks_msec()
	while menu.match_ == was and Time.get_ticks_msec() - t0 < ms:
		await get_tree().process_frame
	return menu.match_

func test_a_duel_in_a_room_of_three_is_the_two_picked_and_the_third_looks_on() -> void:
	var pair := await _room(2)
	var menu: Node = pair[0]
	menu.duel_pair = [7, 8]
	menu._fight_go("bo3")
	await _steps(2)
	var m: Match = menu.match_
	t.check(m != null and m.mode == "bo3" and m.paired_bout, "a duel begins, a bout of a pair")
	t.eq(m.entities.size(), 2, "two on the sand")
	t.check(m.me == null and m.watching(), "the host is not one of them: he looks on")
	t.eq(m.entities.map(func(e): return int(e.peer)), [7, 8], "the two he picked")
	t.check(not m.series.is_empty(), "over rounds: a match of rounds (best of three)")
	t.check(m.fight_status().contains("Friend0") and m.fight_status().contains("Friend1"), "the HUD says who against whom (%s)" % m.fight_status())
	# Friend0 wins the first round: the match goes on to the second, with the same two.
	m.entities.filter(func(e): return int(e.peer) == 8)[0].f.die("wounds")
	var next := await _bout_waiting(menu, m)
	t.check(next != m and next != null and next.mode == "bo3" and next.paired_bout, "the next round is another bout of the pair")
	if next != m and next != null:
		t.eq(next.entities.map(func(e): return int(e.peer)), [7, 8], "the same two")
		var sc := Series.from_dict(next.series)
		t.check(sc.played == 1 and sc.best() == 1 and sc.leaders() == [Series.human_key(7)], "the score is carried: one round played, Friend0's (%s)" % str(next.series))
	_leave(pair)

func test_a_duel_of_two_friends_has_the_two_and_a_host_who_is_one_of_them_fights() -> void:
	var pair := await _room(1)
	var menu: Node = pair[0]
	menu._fight_go("bo3")
	await _steps(2)
	var m: Match = menu.match_
	t.eq(m.entities.size(), 2, "the host and his friend")
	t.check(m.me != null and m.entities.any(func(e): return e.kind == "remote" and int(e.peer) == 7), "he fights, and the friend is the other")
	_leave(pair)

func test_the_kings_court_keeps_a_line_and_crowns_the_first_to_the_wins() -> void:
	var pair := await _room(2)
	var menu: Node = pair[0]
	menu._king_begin({"mode": "king", "rounds": 2})
	await _steps(2)
	var m: Match = menu.match_
	t.check(m != null and m.mode == "king" and m.paired_bout, "the court opens: a bout of the king and the first in the line")
	t.eq(m.entities.size(), 2, "two on the sand, the third looks on")
	var king_key := String(menu.king_run.king)
	var third_key := String((menu.king_run.queue as Array)[1])
	var challenger_key := String((menu.king_run.queue as Array)[0])
	# The king beats the challenger: he stays, the challenger goes to the back of the line, the third walks in.
	var king_peer := int(menu.king_run.peers[king_key])
	var foe: Dictionary = m.entities.filter(func(e): return Series.human_key(1 if e.kind == "local" else int(e.peer)) == challenger_key)[0]
	foe.f.die("wounds")
	var m2 := await _bout_waiting(menu, m)
	t.check(m2 != m and m2 != null and m2.mode == "king", "the next bout is the court's")
	t.eq(int(menu.king_run.wins.get(king_key, 0)), 1, "the king has one win")
	t.eq(String(menu.king_run.king), king_key, "and he stays")
	t.eq(String((menu.king_run.queue as Array)[0]), third_key, "the third is next in the line")
	t.eq(String((menu.king_run.queue as Array)[1]), challenger_key, "and the one he beat is at the back")
	if m2 != m and m2 != null:
		var keys := m2.entities.map(func(e): return Series.human_key(1 if e.kind == "local" else int(e.peer)))
		t.check(keys.has(king_key) and keys.has(third_key) and keys.size() == 2, "the king and the third")
		# Beaten by the third: the crown goes to him.
		var kfoe: Dictionary = m2.entities.filter(func(e): return Series.human_key(1 if e.kind == "local" else int(e.peer)) == king_key)[0]
		kfoe.f.die("wounds")
		var m3 := await _bout_waiting(menu, m2)
		t.eq(String(menu.king_run.king), third_key, "the third takes the crown")
		t.eq(int(menu.king_run.streak.get(king_key, 1)), 0, "the old king's run is over")
		if m3 != m2 and m3 != null:
			# He beats the next, too: two wins, crowned: the court is over.
			var nxt_foe: Dictionary = m3.entities.filter(func(e): return Series.human_key(1 if e.kind == "local" else int(e.peer)) != third_key)[0]
			nxt_foe.f.die("wounds")
			var t0 := Time.get_ticks_msec()
			while not menu.king_run.is_empty() and Time.get_ticks_msec() - t0 < 9000:
				await get_tree().process_frame
			t.check(menu.king_run.is_empty(), "the first to two wins is crowned: the court is over")
	t.check(king_peer != 0, "(a peer)")
	_leave(pair)

func test_a_court_without_a_friend_in_the_room_is_the_gauntlet_against_bots() -> void:
	var menu := _menu()
	await _steps(2)
	menu._fight_go("king")
	await _steps(2)
	var m: Match = menu.match_
	t.check(m != null and m.mode == "king" and not m.paired_bout, "alone it is the court of old: one man against bots")
	t.check(m.me != null and m.entities.size() == 2, "he and a bot")
	menu._end_match()
	menu.queue_free()
	await _steps(1)
