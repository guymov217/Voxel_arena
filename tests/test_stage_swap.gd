extends Node
## A man built again in the yard while the game goes on (a friend's armour or body changed at the smith or the physician's, R) is built
## apart over the frames that follow and changes places with the old one in the one frame, instead of being a stop of his own of a tenth of
## a second to a third for the whole room (Match._rebuild_apart, _respawn_apart, Match.staging). The old man stands, or lies, until then.

var t

func _steps(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

## Physics frames until `cond` holds (or `most` of them): how many it took, -1 if it never did.
func _until(cond: Callable, most := 1500) -> int:
	for i in most:
		if cond.call():
			return i
		await get_tree().physics_frame
	return 0 if cond.call() else -1

## Whether every one of the yard's own people (its dummies and the keepers of its stalls) is in.
func _people_in(m: Match) -> bool:
	var keepers := 0
	for id in Yard.stations():
		if Yard.STATIONS[id].has("npc"):
			keepers += 1
	return m.yard.dummies.size() == Yard.DUMMIES.size() and m.yard.keepers.size() == keepers

func _yard(seed_: int, lo := {"main": "gladius", "off": ""}, peers := []) -> Match:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "yard", "role": "host", "headless": true, "name": "Ann", "seed": seed_, "decrees": [], "hazards": [], "loadout": lo, "peers": peers})
	m.stage_always = true   # (a game with a screen stages: here without one; set after the start, the yard's people stand in it already)
	return m

func test_a_friends_armour_taken_off_is_swapped_in_apart() -> void:
	var m := _yard(1, {"main": "gladius", "off": ""}, [{"id": 2, "name": "Bob", "loadout": {"main": "axe", "armor": ["steelLorica"]}}])
	await _steps(2)
	var bob := func(): return m.humans().filter(func(e): return e.kind == "remote")[0]
	var f0: Fighter = bob.call().f
	var id0 := f0.get_instance_id()
	var spec_pos: Vector3 = f0.torso.global_position
	t.check(f0.armor_kg > 0.0, "Bob comes into the yard in his steel lorica")
	m.peer_body(2, {}, {"main": "axe", "armor": []})
	t.check(is_same(bob.call().f, f0) and f0.alive, "told at once, the old man stands on while the new one is built")
	t.check(bool(bob.call().get("swapping", false)), "and the entity says one is on its way")
	var took := await _until(func(): return bob.call().f.get_instance_id() != id0)
	t.check(took > 2, "the new man is built over the frames that follow, not in the frame he is asked for (%d frames)" % took)
	var f1: Fighter = bob.call().f
	t.check(f1.alive and f1.armor_kg == 0.0, "and he has no armour on him")
	t.check(not bob.call().has("swapping"), "nothing is on its way now")
	t.eq(m.humans().size(), 2, "the two of them in the yard, no more")
	t.check(f1.torso.global_position.distance_to(spec_pos) < 3.0, "where the old one stood")
	await _steps(3)
	t.check(not is_instance_valid(f0), "the old man is gone")
	m.queue_free()
	await get_tree().physics_frame

## A second asking while the first is being built is done when the first is in, with what it left: the armour taken off and put on again
## (the last word) ends with the armour on him.
func test_a_second_asking_in_the_meantime_has_the_last_word() -> void:
	var m := _yard(2, {"main": "gladius", "off": ""}, [{"id": 2, "name": "Bob", "loadout": {"main": "axe", "armor": ["steelLorica"]}}])
	await _steps(2)
	var bob := func(): return m.humans().filter(func(e): return e.kind == "remote")[0]
	var id0 := (bob.call().f as Fighter).get_instance_id()
	m.peer_body(2, {}, {"main": "axe", "armor": []})
	await _steps(5)
	m.peer_body(2, {}, {"main": "axe", "armor": ["steelLorica"]})
	var ok := await _until(func(): return bob.call().f.get_instance_id() != id0 and not bool(bob.call().get("swapping", false)) and bob.call().f.armor_kg > 0.0, 3000)
	t.check(ok >= 0, "he ends in his lorica again (%d frames)" % ok)
	t.eq(m.humans().size(), 2, "still the two of them")
	m.queue_free()
	await get_tree().physics_frame

## R in the yard: the cooldown starts at once, the fallen man lies until the new one is built, and the new one has his kit.
func test_r_brings_the_new_man_in_apart() -> void:
	var m := _yard(3, {"main": "gladius", "off": ""})
	m.me["inventory"] = {"bread": 2}
	await _steps(30)
	var old: Fighter = m.me.f
	var oid := old.get_instance_id()
	var id: int = m.me.id
	t.check(m.respawn_request(m.me), "R is taken")
	t.check(is_same(m.me.f, old), "the man stands until the new one is built")
	t.check(not m.respawn_request(m.me), "and R again does nothing")
	var took := await _until(func(): return m.me.f.get_instance_id() != oid)
	t.check(took > 2, "the new man comes over the frames that follow (%d)" % took)
	t.check(m.me.f.alive and m.me.id == id, "the same player, whole")
	t.eq(int(m.me.get("inventory", {}).get("bread", 0)), 2, "with his kit")
	t.check(m.respawn_wait(m.me) > 8.0, "the ten seconds run from the asking (%.1f s left)" % m.respawn_wait(m.me))
	t.eq(m.humans().size(), 1, "one man of his, no more")
	m.queue_free()
	await get_tree().physics_frame

## A man who died in the yard is up by himself three seconds after, built apart; asked each step meanwhile it does not build him twice.
func test_a_fallen_man_is_up_by_himself_built_once() -> void:
	var m := _yard(4, {"main": "gladius", "off": ""})
	await _steps(30)
	var down: Fighter = m.me.f
	var did := down.get_instance_id()
	down.head.hp = 0.0
	down.die("test")
	await _steps(int(3.2 * 120.0))
	var took := await _until(func(): return m.me.f.get_instance_id() != did and m.me.f.alive and not bool(m.me.get("swapping", false)), 2400)
	t.check(took >= 0, "he is up again by himself (%d)" % took)
	t.eq(m.humans().size(), 1, "built once: one man of his")
	var kids := m.find_children("*", "Fighter", false, false)
	t.eq(kids.filter(func(f): return is_instance_valid(f) and not f.is_queued_for_deletion()).size(), m.entities.size(), "no spare man left standing about")
	m.queue_free()
	await get_tree().physics_frame

## With a screen the yard's dummies and the stall keepers are built apart, one after another, over the frames that follow its start,
## not all six in the frame it starts in (YardPlay._setup_staged): a stop of a second and more before anyone could move.
func test_the_yards_people_come_in_after_its_first_frame() -> void:
	var m := Match.new()
	m.stage_always = true
	add_child(m)
	m.setup({"mode": "yard", "role": "host", "headless": true, "name": "Ann", "seed": 6, "decrees": [], "hazards": [], "loadout": {"main": "gladius", "off": ""}, "peers": []})
	var keepers := 0
	for id in Yard.stations():
		if Yard.STATIONS[id].has("npc"):
			keepers += 1
	t.check(keepers >= 3, "the smith, the trader, the trainer and the physician keep stalls (%d)" % keepers)
	t.eq(m.entities.size(), 1, "in the frame the yard starts in only the player is in it")
	t.eq(m.yard.dummies.size() + m.yard.keepers.size(), 0, "none of the six stands yet")
	var took := await _until(func(): return m.yard.dummies.size() == Yard.DUMMIES.size() and m.yard.keepers.size() == keepers, 4000)
	t.check(took > 5, "they come over the frames that follow, not in the first (%d frames)" % took)
	t.eq(m.entities.size(), 1 + Yard.DUMMIES.size() + keepers, "and the yard is full of them in the end")
	var all_harmless := true
	for e in m.entities:
		if e.kind == "npc" and not e.harmless:
			all_harmless = false
	t.check(all_harmless, "each of them as he was built in one go: harmless")
	var kept := m.yard.keepers[0] as Fighter
	t.check(kept.parts[0].collision_layer == YardPlay.KEEPER_LAYER, "a keeper stands on the keepers' layer")
	var kids := m.find_children("*", "Fighter", false, false)
	t.eq(kids.filter(func(f): return is_instance_valid(f) and not f.is_queued_for_deletion()).size(), m.entities.size(), "no man built twice, none left standing about")
	m.queue_free()
	await get_tree().physics_frame

## A yard torn down while its people are still being built (the player leaves in the first seconds): nothing is left of it, no error.
func test_a_yard_left_before_its_people_are_in_is_let_go() -> void:
	var m := Match.new()
	m.stage_always = true
	add_child(m)
	m.setup({"mode": "yard", "role": "host", "headless": true, "name": "Ann", "seed": 7, "decrees": [], "hazards": [], "loadout": {"main": "gladius", "off": ""}, "peers": []})
	await _steps(6)
	m.queue_free()
	await _steps(30)
	t.check(not is_instance_valid(m), "the yard is gone")

## The friends' men come in over the frames that follow the yard's start as well (the user's record: "match setup: yard as host, 8 men in 1484 ms"): the host's man
## is in at once, the friends after him in the order they came and each in his place and with his kit, the boards by the gate are written again for the whole party
## when the last is in, and the yard's own people (dummies, keepers) after the friends.
func test_the_friends_men_come_into_the_yard_before_its_people() -> void:
	var m := Match.new()
	m.stage_always = true
	add_child(m)
	var peers := []
	for i in 3:
		peers.append({"id": 2 + i, "name": ["Bob", "Cat", "Dan"][i], "loadout": {"main": "axe", "off": ""}, "kit": {"nailPot": 1 + i}})
	m.setup({"mode": "yard", "role": "host", "headless": true, "name": "Ann", "seed": 8, "decrees": [], "hazards": [], "loadout": {"main": "gladius", "off": ""}, "peers": peers})
	t.eq(m.entities.size(), 1, "in the frame the yard starts in only the host's man is in it")
	t.eq(m.coming, 3, "the three friends are on their way")
	t.eq(m.players_count, 4, "the party is four from the start (the bouts are sized by it)")
	var took := await _until(func(): return m.coming == 0, 4000)
	t.check(took > 2, "they come over the frames that follow (%d frames)" % took)
	t.eq(m.humans().size(), 4, "the four of them in the yard")
	t.eq(m.yard.dummies.size() + m.yard.keepers.size(), 0, "the yard's own people not yet: the friends first")
	var names := []
	var in_order := true
	var last_id := -1
	for e in m.humans():
		names.append(String(e.f.display_name))
		in_order = in_order and int(e.id) > last_id
		last_id = int(e.id)
	t.eq(names, ["Ann", "Bob", "Cat", "Dan"], "the host's man and the friends in the order they came in")
	t.check(in_order, "with their ids in that order")
	for i in 3:
		var e: Dictionary = m.humans()[1 + i]
		t.eq(int(e.peer), 2 + i, "%s is his friend's man" % names[1 + i])
		t.eq(int(e.inventory.get("nailPot", 0)), 1 + i, "%s has his kit" % names[1 + i])
		t.check(absf(e.f.torso.global_position.x - 1.2 * float(1 + i)) < 1.0, "%s stands where the sync start would have put him (x %.1f)" % [names[1 + i], e.f.torso.global_position.x])
	t.eq(m.yard.board_texts_now, YardPlay.board_texts(4), "the boards by the gate are written for the party of four")
	var done := await _until(func(): return _people_in(m), 4000)
	t.check(done >= 0, "and then the yard's own people come in")
	var kids := m.find_children("*", "Fighter", false, false)
	t.eq(kids.filter(func(f): return is_instance_valid(f) and not f.is_queued_for_deletion()).size(), m.entities.size(), "no man built twice, none left standing about")
	m.queue_free()
	await get_tree().physics_frame

## A friend who leaves while his man is being built is not left in the yard: the room has no peer of that id by the time his man is in, and `Net.peer_left` found no man of his to take away.
func test_a_friend_who_leaves_while_his_man_is_built_is_not_left_in_the_yard() -> void:
	var dt: bool = Net.dtls
	Net.dtls = false
	var err: int = Net.host_enet(28617)
	Net.dtls = dt
	if err != OK:
		t.check(false, "a room could not be opened for the test (%d)" % err)
		return
	Net.peers[2] = {"name": "Bob", "loadout": {"main": "axe"}}
	Net.peers[3] = {"name": "Cat", "loadout": {"main": "axe"}}
	var m := Match.new()
	m.stage_always = true
	add_child(m)
	m.setup({"mode": "yard", "role": "host", "headless": true, "name": "Ann", "seed": 9, "decrees": [], "hazards": [], "loadout": {"main": "gladius", "off": ""}, "peers": [{"id": 2, "name": "Bob", "loadout": {"main": "axe", "off": ""}}, {"id": 3, "name": "Cat", "loadout": {"main": "axe", "off": ""}}]})
	t.eq(m.coming, 2, "both are on their way")
	Net.peers.erase(3)   # (Cat's line goes while Bob's man is being built, and his own man is not yet one of the match's)
	m.drop_peer(3)
	var took := await _until(func(): return m.coming == 0, 4000)
	t.check(took >= 0, "the others come in all the same")
	t.eq(m.humans().size(), 2, "Ann and Bob in the yard, no ghost of Cat")
	t.eq(m.players_count, 2, "and the party is two")
	var left_over := m.entities.filter(func(e): return e.kind == "remote" and int(e.peer) == 3)
	t.eq(left_over.size(), 0, "no man of the peer who left")
	await _until(func(): return _people_in(m), 4000)
	var kids := m.find_children("*", "Fighter", false, false)
	t.eq(kids.filter(func(f): return is_instance_valid(f) and not f.is_queued_for_deletion()).size(), m.entities.size(), "and his man is not left standing about unregistered")
	m.queue_free()
	await get_tree().physics_frame
	Net.leave()

## With a screen a campaign bout's first foes come through the gates over the frames that follow its start (the players are in at once), not
## all built before its first frame: and the second wave is not called while the first is still on its way in, nor the bout won.
func test_a_bouts_first_foes_come_in_over_the_frames_after_its_start() -> void:
	var m := Match.new()
	m.stage_always = true
	add_child(m)
	m.setup({"mode": "campaign", "stage": 5, "role": "host", "headless": true, "loadout": {"main": "gladius", "off": ""}, "peers": [{"id": 2, "name": "Bob", "loadout": {"main": "axe"}}], "seed": 4})
	t.eq(m.humans().size(), 2, "the two players are in at once")
	t.eq(m.enemies().size(), 0, "no foe is built before the first frame")
	var want: int = (Data.stage(5, 2).rounds[0] as Array).size()
	t.eq(m.coming, want, "the first wave is on its way in")
	t.check(not m.late_wave.is_empty(), "the second wave is kept back")
	await _steps(2)
	t.check(not m.late_wave.is_empty(), "and not called for while the first is not yet in")
	t.check(not m.over, "nor the bout won")
	var took := await _until(func(): return m.enemies().size() == want and m.coming == 0, 3000)
	t.check(took > 2, "the foes come over the frames (%d)" % took)
	t.eq(m.enemies().size(), want, "all of the first wave in the end")
	t.check(not m.late_wave.is_empty() or m.time > Ladder.LATE_AFTER, "the second wave still waits its turn")
	m.queue_free()
	await get_tree().physics_frame
