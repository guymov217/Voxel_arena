extends Node
## A match that is over is taken down over the frames that follow (with a screen: Match.let_go), not all in the frame the next match is built in; the next match's own time scale, gravity and
## crowd are not put back by the old one's late leaving; and the friends' men of a fight come in over the frames after its start, the player's own at once (Modes.setup).

var t

func _steps(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func _until(cond: Callable, most := 1500) -> int:
	for i in most:
		if cond.call():
			return i
		await get_tree().physics_frame
	return 0 if cond.call() else -1

func _fight(mode := "ffa", friends := 3, staged := true, seed_ := 4) -> Match:
	var m := Match.new()
	m.stage_always = staged
	add_child(m)
	var peers := []
	for i in friends:
		peers.append({"id": 7 + i, "name": "Friend%d" % i, "loadout": {"main": "gladius", "off": ""}, "kit": {"nailPot": 1 + i}})
	m.setup({"mode": mode, "role": "host", "headless": true, "name": "Ann", "seed": seed_, "decrees": [], "hazards": [], "loadout": {"main": "gladius", "off": ""}, "endless": {"seed": 11}, "peers": peers})
	return m

func _fighters_in(m: Match) -> int:
	return m.get_children().filter(func(c): return c is Fighter and is_instance_valid(c) and not c.is_queued_for_deletion()).size()

func test_a_match_let_go_of_is_taken_down_over_the_frames() -> void:
	var m := _fight("ffa", 3, true)
	await _until(func(): return m.coming == 0)
	var men := _fighters_in(m)
	t.check(men >= 4, "a fight of four and its bots (%d men)" % men)
	var arena := m.arena
	m.let_go_each = 2
	m.let_go()
	t.check(not m.visible and m.process_mode == Node.PROCESS_MODE_DISABLED, "at once nothing of it moves or is drawn")
	t.eq(_fighters_in(m), men, "its men are still there in the frame it is let go in")
	await get_tree().process_frame
	await get_tree().process_frame
	t.check(not is_instance_valid(arena), "its sand is gone at the end of that frame, as ever")
	var counts := [_fighters_in(m)]
	for i in 40:
		if not is_instance_valid(m):
			break
		await get_tree().process_frame
		if is_instance_valid(m):
			counts.append(_fighters_in(m))
	var steady := true
	for i in range(1, counts.size()):
		steady = steady and int(counts[i]) <= int(counts[i - 1])
	t.check(steady and counts.size() >= 3 and int(counts[0]) > 0, "its men go a few at a frame, never all in one (%s)" % str(counts))
	await _until(func(): return not is_instance_valid(m), 200)
	t.check(not is_instance_valid(m), "and the match itself goes last")

## Let go of in a frame's physics part (or from a timer's turn: a `process_frame` asked for there comes in the very frame it is asked in), its men must still stand for what looks at them once more in that frame
## (the HUD, queued to be freed, reads `me.f` in its `_process` before the frame is out): they are taken down in a frame after.
class Watcher extends Node:
	var man
	var seen := []
	func _process(_dt: float) -> void:
		seen.append(is_instance_valid(man))

func test_what_looks_at_the_match_once_more_in_the_frame_it_is_let_go_in_finds_its_men() -> void:
	var m := _fight("ffa", 2, true)
	await _until(func(): return m.coming == 0)
	var w := Watcher.new()
	w.man = m.me.f
	add_child(w)
	await get_tree().physics_frame   # (a turn of the frame's physics part: its process part, where the HUD looks, is still to come in the same frame)
	m.let_go_each = 100
	m.let_go()
	w.seen.clear()
	for i in 4:
		await get_tree().process_frame
	t.check(w.seen.size() >= 3 and bool(w.seen[0]), "his man is still there for what looks once more in the frame he is let go in (%s)" % str(w.seen))
	t.check(not bool(w.seen.back()), "and gone in a frame after")
	w.queue_free()

## The menu builds one man as the player's own while it stands (what a first fight's start would pay, caches and all) and lets him go: no man is left standing about.
func test_the_menu_warms_the_builds_up_with_one_man_the_player_would_be() -> void:
	var menu = load("res://scripts/ui/menu.gd").new()
	add_child(menu)
	var b := Match.new()
	add_child(b)
	b.setup({"mode": "training", "training": {"enemy": "none"}, "headless": true, "seed": 3, "decrees": [], "hazards": []})
	menu.backdrop = b
	Fighter._listed.clear()
	var before := b.get_children().filter(func(c): return c is Fighter).size()
	await menu._prewarm(0.0)
	t.check(Fighter._listed.size() > 0, "the body's builds are kept for the next (%d kinds)" % Fighter._listed.size())
	await get_tree().process_frame
	await get_tree().process_frame
	t.eq(b.get_children().filter(func(c): return c is Fighter and not c.is_queued_for_deletion()).size(), before, "and the man who was built is let go: nobody is left standing about")
	menu._prewarmed = false
	menu.backdrop = null
	await menu._prewarm(0.0)
	t.check(not menu._prewarmed, "with no backdrop (a game without a screen) there is nothing to build in, and nothing is said done")
	b.queue_free()
	menu.queue_free()
	await get_tree().physics_frame

func test_the_next_matchs_time_and_gravity_are_not_put_back_by_the_old_ones_leaving() -> void:
	var m := _fight("ffa", 1, true)
	await _until(func(): return m.coming == 0)
	m.let_go_each = 4
	m.let_go()
	# (The next match, built in the same frame, has its own: an Emperor's decree of slow time or of low gravity.)
	var space := m.get_world_3d().space
	Engine.time_scale = 0.6
	PhysicsServer3D.area_set_param(space, PhysicsServer3D.AREA_PARAM_GRAVITY, 3.0)
	await _until(func(): return not is_instance_valid(m), 300)
	t.check(not is_instance_valid(m), "the old match is gone")
	t.eq(Engine.time_scale, 0.6, "the time scale is the next match's")
	t.eq(PhysicsServer3D.area_get_param(space, PhysicsServer3D.AREA_PARAM_GRAVITY), 3.0, "and so is the gravity")
	Engine.time_scale = 1.0
	PhysicsServer3D.area_set_param(space, PhysicsServer3D.AREA_PARAM_GRAVITY, 9.81)

func test_a_match_without_a_screen_is_freed_as_it_always_was() -> void:
	var m := _fight("ffa", 1, false)
	t.check(not m.staged_exit(), "no screen: not taken down in stages")
	m.let_go()
	Engine.time_scale = 0.6   # (what the leaving puts back, at the end of the frame)
	await _steps(2)
	t.check(not is_instance_valid(m), "freed at the end of the frame")
	t.eq(Engine.time_scale, 1.0, "its leaving put the time scale back, as ever")

func test_the_crowds_murmur_is_the_last_arenas() -> void:
	var a := Arena.new()
	add_child(a)
	a.build("colosseum", true, "noon")
	t.check(is_same(Arena._murmur_of, a), "the first arena's crowd is the murmur")
	var b := Arena.new()
	add_child(b)
	b.build("colosseum", true, "noon")
	t.check(is_same(Arena._murmur_of, b), "a match built over it takes it over")
	a.free()
	t.check(is_same(Arena._murmur_of, b), "the old arena's leaving does not put it out")
	b.free()
	t.check(Arena._murmur_of == null, "the last one's does")

func test_the_friends_men_of_a_fight_come_in_over_the_frames_after_its_start() -> void:
	var m := _fight("endless", 3, true, 5)
	t.eq(m.humans().size(), 1, "in the frame the fight starts in only the host's man is in it")
	t.eq(m.coming, 3, "the three friends are on their way")
	t.eq(m.players_count, 4, "the party is four from the start (the waves are sized by it)")
	t.check(m.me != null and m.me.kind == "local", "the host's man is his own")
	var en: Endless = m.modes.endless
	t.eq(en.plan(1, maxi(m.humans().size(), m.players_count)).size(), 4, "and the first wave is for four")
	var took := await _until(func(): return m.coming == 0, 3000)
	t.check(took > 2, "they come over the frames that follow (%d frames)" % took)
	t.eq(m.humans().size(), 4, "the four in the fight")
	var names := m.humans().map(func(e): return String(e.f.display_name))
	t.eq(names, ["Ann", "Friend0", "Friend1", "Friend2"], "in the order they came in")
	for e in m.humans():
		if e.kind == "remote":
			t.eq(int(e.inventory.get("nailPot", 0)), int(e.peer) - 6, "%s has his kit" % e.f.display_name)
	t.check(not m.over, "the fight goes on: none of its rules asked while a man was on his way")
	en.update(Endless.START_DELAY + 0.1)
	t.eq(m.enemies().size() + m.coming, en.plan(1, 4).size(), "the first wave is the party's: four foes")
	m.queue_free()
	await get_tree().physics_frame

## A wave beaten with a friend of the party down: with a screen he stands up as his new man, built apart over the frames (a man built in the frame was 130 to 400 ms: the user's record, "frame 536 ms"),
## and the rewards, which are for the men as they stand, are held out when he is up.
func test_the_fallen_of_a_party_rise_over_the_frames_and_the_rewards_wait_for_them() -> void:
	var m := _fight("endless", 2, true, 9)
	await _until(func(): return m.coming == 0)
	var en: Endless = m.modes.endless
	var friend: Dictionary = m.humans().filter(func(e): return e.kind == "remote")[0]
	var old_f = friend.f
	en.update(Endless.START_DELAY + 0.1)
	await _until(func(): return m.coming == 0 and not m.enemies().is_empty())
	old_f.die("wounds")
	await _steps(2)
	for e in m.enemies():
		e.f.die("wounds")
	await _until(func(): return en.phase == "rest", 600)
	t.eq(en.phase, "rest", "the wave is beaten")
	t.check(en.offers.is_empty(), "the rewards are held back while a friend of the party is still down")
	var up := await _until(func(): return not en.offers.is_empty(), 3000)
	t.check(up > 2, "they come when he is up, over the frames that follow (%d frames)" % up)
	t.eq(en.offers.size(), 3, "a reward held out to each of the three")
	var back: Dictionary = m.humans().filter(func(e): return e.kind == "remote" and int(e.peer) == int(friend.peer))[0]
	t.check(back.f.alive and not is_same(back.f, old_f), "he is a new man, on his feet")
	t.eq(m.humans().size(), 3, "and the party is the three of them still")
	m.queue_free()
	await get_tree().physics_frame

func test_a_fight_with_no_man_of_the_hosts_own_is_built_as_it_was() -> void:
	var m := Match.new()
	m.stage_always = true
	add_child(m)
	m.setup({"mode": "emperor", "role": "host", "headless": true, "seed": 6, "decrees": [], "hazards": [], "loadout": {"main": "gladius", "off": ""}, "peers": [{"id": 7, "name": "Friend0", "loadout": {"main": "gladius", "off": ""}, "kit": {}}, {"id": 8, "name": "Friend1", "loadout": {"main": "gladius", "off": ""}, "kit": {}}]})
	t.eq(m.humans().size(), 2, "nobody of his own to stand ahead of them: the two friends are in at once")
	m.queue_free()
	await get_tree().physics_frame

func test_a_friend_who_leaves_while_his_man_is_built_is_not_left_in_the_fight() -> void:
	var dt: bool = Net.dtls
	Net.dtls = false
	var err: int = Net.host_enet(28618)
	Net.dtls = dt
	if err != OK:
		t.check(false, "a room could not be opened for the test (%d)" % err)
		return
	Net.peers[7] = {"name": "Friend0", "loadout": {"main": "gladius"}}
	Net.peers[8] = {"name": "Friend1", "loadout": {"main": "gladius"}}
	var m := _fight("endless", 2, true, 7)
	t.eq(m.humans().size(), 1, "only the host's man is in at the start")
	t.eq(m.coming, 2, "both friends are on their way")
	Net.peers.erase(8)   # (Friend1's line goes while Friend0's man is being built, and his own is not yet one of the match's)
	m.drop_peer(8)
	await _until(func(): return m.coming == 0, 3000)
	t.eq(m.humans().filter(func(e): return e.kind == "remote").size(), 1, "Friend0 is in the fight, no ghost of Friend1")
	t.eq(m.players_count, 2, "and the party is two")
	m.queue_free()
	await get_tree().physics_frame
	Net.leave()
