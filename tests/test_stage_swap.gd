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
