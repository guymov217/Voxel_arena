extends Node
## A guest builds what the host spawns one fighter at a time over the frames (Match.guest_spawn, guest_staging), not all
## in the frame the message came in: eleven men of a free-for-all stopped a guest's game for 1.6 to 2.4 seconds, a wave
## in a bout every guest's at once. His own man is built at once (he must be able to act); what the host says of one not
## built yet is kept and said again when he is in; a fighter the host drops before his turn is never built.

var t

func _guest() -> Match:
	var m := Match.new()
	add_child(m)
	m.stage_always = true
	m.setup({"mode": "yard", "role": "guest", "headless": true, "seed": 1, "decrees": [], "hazards": []})
	return m

func _man(id: int, kind := "bot") -> Dictionary:
	return {"id": id, "kind": kind, "peer": 1 if kind == "remote" else -1, "name": "M%d" % id, "loadout": {"main": "gladius"}, "team": 1, "pos": [float(id % 5), 0.0, 4.0], "yaw": 0.0}

func _until(m: Match, n: int, ms := 20000) -> bool:
	var t0 := Time.get_ticks_msec()
	while (m.entities.size() < n or m._guest_building) and Time.get_ticks_msec() - t0 < ms:
		await get_tree().process_frame
	return m.entities.size() >= n and not m._guest_building

func test_what_the_host_spawns_comes_in_over_the_frames() -> void:
	var m := _guest()
	var base := m.entities.size()
	m.guest_spawn(_man(21))
	m.guest_spawn(_man(22))
	m.guest_spawn({"id": 24, "kind": "beast", "beast": "wolf", "name": "Wolf", "team": 1, "pos": [3.0, 0.0, 3.0], "yaw": 0.0})
	t.eq(m.entities.size(), base, "none of them built in the frame the messages came in")
	t.eq(m.guest_pending.size(), 3, "all three waiting for their turn")
	t.check(await _until(m, base + 3), "and all three in after a few frames")
	t.check(m.entity_by_id(21) != null and m.entity_by_id(22) != null and m.entity_by_id(24) != null, "the very ones the host spawned (by id)")
	t.check(m.guest_pending.is_empty(), "nothing left waiting")
	m.queue_free()
	await get_tree().process_frame

func test_his_own_man_is_built_at_once() -> void:
	var m := _guest()
	var base := m.entities.size()
	m.guest_spawn(_man(21))
	m.guest_spawn(_man(23, "remote"))
	t.eq(m.entities.size(), base + 1, "his own man is in the moment the message is (the other waits)")
	t.check(m.me != null and m.entity_by_id(23) != null and m.entity_by_id(21) == null, "and he is the one the camera and the hands are of")
	t.check(await _until(m, base + 2), "the other comes in after")
	m.queue_free()
	await get_tree().process_frame

func test_what_is_said_of_one_not_built_is_said_again_when_he_is_in() -> void:
	var m := _guest()
	var base := m.entities.size()
	m.guest_spawn(_man(21))
	m.guest_message("bone", {"id": 21})
	m.guest_vox({"id": 21, "part": 0, "idx": []})
	t.eq(((m.guest_pending[21] as Dictionary)["_said"] as Array).size(), 2, "a message and a cut kept for him")
	m.guest_message("bone", {"id": 99})
	t.eq(((m.guest_pending[21] as Dictionary)["_said"] as Array).size(), 2, "what is said of another is not his")
	t.check(await _until(m, base + 1), "he comes in")
	t.check(m.guest_pending.is_empty(), "and the kept words are said and gone")
	m.queue_free()
	await get_tree().process_frame

func test_a_fighter_dropped_before_his_turn_is_never_built() -> void:
	var m := _guest()
	var base := m.entities.size()
	m.guest_spawn(_man(21))
	m.guest_spawn(_man(22))
	m.guest_despawn(22)
	t.check(await _until(m, base + 1), "the one before him comes in")
	for i in 30:
		await get_tree().process_frame
	t.check(m.entity_by_id(21) != null and m.entity_by_id(22) == null, "and he never does")
	# (Dropped while he is being built, and sent again as the host does when it builds a man anew.)
	m.guest_spawn(_man(25))
	for i in 3:
		await get_tree().process_frame
	m.guest_despawn(25)
	m.guest_spawn(_man(25))
	t.check(await _until(m, base + 2), "a man dropped mid-build and sent again is there once")
	t.eq(m.entities.filter(func(e): return e.id == 25).size(), 1, "once")
	m.queue_free()
	await get_tree().process_frame

## Players who join together are built over the frames on the host too, each in a place of his own (not on top of each other).
func test_players_who_join_together_get_places_of_their_own() -> void:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "yard", "role": "host", "headless": true, "seed": 1, "decrees": [], "hazards": [], "loadout": {"main": "gladius", "off": ""}})
	m.stage_always = true   # (after the start: the yard's own people stand in it already, not still on their way in)
	await get_tree().physics_frame
	var base := m.entities.size()
	m.add_peer(101, {"name": "A", "loadout": {"main": "gladius"}})
	m.add_peer(102, {"name": "B", "loadout": {"main": "axe"}})
	t.eq(m.entities.size(), base, "neither is built in the frame that let him in")
	var t0 := Time.get_ticks_msec()
	while m.entities.size() < base + 2 and Time.get_ticks_msec() - t0 < 20000:
		await get_tree().process_frame
	t.eq(m.entities.size(), base + 2, "both are in after a few frames")
	var ps := m.entities.filter(func(e): return e.kind == "remote").map(func(e): return (e.spec.pos as Vector3))
	t.check(ps.size() == 2 and (ps[0] as Vector3).distance_to(ps[1]) > 0.5, "each in his own place (%s)" % str(ps))
	t.eq(m._joining, 0, "and no place is still kept")
	m.queue_free()
	await get_tree().process_frame
