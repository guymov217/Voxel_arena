extends Node
## The gate (Match.foe_gate_holds, bring_in): a foe waits outside while the host cannot afford one more man (the endless arena with eight players ran at 40% speed with sixteen
## on the sand: a step of 12 to 14 ms for the 8.3 there is, user's record), and comes in as the others fall; the wave is all of it, not all of it at once.

var t

func _foe(i: int) -> Dictionary:
	return {"kind": "bot", "name": "Foe%d" % i, "loadout": {"main": "gladius", "off": ""}, "team": Match.ENEMY_TEAM, "pos": Vector3(-6.0 + float(i) * 1.5, 0, 9), "yaw": PI, "diff": 0.3}

func _until(cond: Callable, most := 1800) -> int:
	for i in most:
		if cond.call():
			return i
		await get_tree().physics_frame
	return 0 if cond.call() else -1

func test_the_gate_asks_what_one_more_man_would_cost() -> void:
	t.check(not Match.foe_gate_holds(6.4, 9, 2), "9 men at 6.4 ms a step: one more is 7.1, within the 7.6")
	t.check(Match.foe_gate_holds(7.0, 10, 2), "10 men at 7.0 ms: one more is 7.7: held")
	t.check(Match.foe_gate_holds(9.8, 12, 4), "12 men at 9.8 ms: held")
	t.check(Match.foe_gate_holds(13.0, 16, 8), "16 men at 13 ms (the user's record): held")
	t.check(Match.foe_gate_holds(6.0, 12, 4, true), "a room over its budget holds them whatever the smoothed step says")
	t.check(not Match.foe_gate_holds(9.8, 12, 1), "never while fewer than two foes are on the sand")
	t.check(not Match.foe_gate_holds(0.0, 12, 4), "a step not measured yet: no gate")
	t.check(not Match.foe_gate_holds(5.0, 16, 8), "5 ms with sixteen: 5.3, nothing held")

## The frames have their share (the owner's choice after the second diagnostic report: 45 frames a second kept room for): what a step may cost is what is left of a second
## after GATE_FPS frames of the host's own measured rest.
func test_the_gate_keeps_the_frames_their_share() -> void:
	t.check(absf(Match.gate_budget(9.2) - 4.883) < 0.01, "a frame's rest of 9.2 ms (the owner's release build in a fight): a step may cost 4.9 ms (%.2f)" % Match.gate_budget(9.2))
	t.check(absf(Match.gate_budget(6.0) - 6.083) < 0.01, "of 6 ms: 6.1 ms")
	t.check(Match.gate_budget(1.0) == Match.GATE_BUDGET_MS and Match.gate_budget(0.0) == Match.GATE_BUDGET_MS, "a quick frame, or none read yet (a game with no screen): the old 7.6, never more")
	t.check(Match.foe_gate_holds(4.5, 8, 2, false, Match.gate_budget(9.2)), "eight men at 4.5 ms and frames of 9.2: one more is 5.1 of the 4.9 there is: held")
	t.check(not Match.foe_gate_holds(4.5, 8, 2, false, Match.gate_budget(6.0)), "with frames of 6 ms he comes in")
	t.check(not Match.foe_gate_holds(4.5, 8, 1, false, Match.gate_budget(30.0)) and Match.foe_gate_holds(4.5, 8, 2, false, Match.gate_budget(30.0)), "a card that cannot draw 45 frames at all: the two foes there always are, and no more")
	# What a frame costs beside its steps, smoothed.
	t.check(Net.rest_after(0.0, 8.0) == 8.0 and absf(Net.rest_after(8.0, 10.0) - 8.1) < 1e-6, "the first frame's rest as it is, the next ones smoothed in")
	t.check(Net.rest_after(8.0, 400.0) == 8.0 and Net.rest_after(8.0, 0.0) == 8.0, "a stall is not what a frame costs")
	# The room's own gate reads the host's frames; a test's own cost is held against the old budget.
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "campaign", "stage": 1, "role": "host", "headless": true, "loadout": {"main": "gladius", "off": ""}, "seed": 6})
	for i in 2:
		var e = m.spawn_fighter(_foe(i))
		e.erase("bot")
		e.drive = func(_e): return {}
	var step_was: float = Net.step_ms
	var rest_was: float = Net.rest_ms
	Net.step_ms = 4.5
	Net.rest_ms = 9.2
	t.check(m.enemies().size() >= 2 and m._foe_gate_holds(), "the room's gate holds a foe when the host's frames leave a step 4.9 ms and one more man makes it more")
	Net.rest_ms = 3.0
	t.check(not m._foe_gate_holds(), "and lets him in when the frames are quick")
	Net.rest_ms = 9.2
	m.gate_cost_ms = 4.5
	t.check(not m._foe_gate_holds(), "a test's own cost is held against the old budget")
	Net.step_ms = step_was
	Net.rest_ms = rest_was
	m.queue_free()
	await get_tree().physics_frame

func test_foes_wait_at_the_gate_and_come_in_when_the_host_can_afford_them() -> void:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "campaign", "stage": 1, "role": "host", "headless": true, "loadout": {"main": "gladius", "off": ""}, "seed": 6})
	m.stage_always = true   # (a game with a screen)
	m.me.drive = func(_e): return {"limp": true}
	var inert := func(e):
		e.erase("bot")
		e.drive = func(_e): return {}
	for e in m.enemies():
		inert.call(e)
	t.eq(m.enemies().size(), 1, "the bout's own foe stands on the sand")
	m.gate_cost_ms = 12.0   # (the host's step costs 12 ms)
	var specs := []
	for i in 4:
		specs.append(_foe(i))
	m.bring_in(specs, inert)
	await _until(func(): return m.enemies().size() >= 2, 900)
	for i in 120:
		await get_tree().physics_frame
	t.eq(m.enemies().size(), 2, "one comes in (two on the sand at least) and the others wait")
	t.eq(m.coming, 3, "three are still on their way")
	t.eq(m.gate_held, 1, "held at the gate")
	m.gate_cost_ms = 1.0   # (the others fell, the step is cheap again)
	var took := await _until(func(): return m.coming == 0 and m.enemies().size() == 5, 1800)
	t.check(took >= 0, "the host can afford them again: all of the wave is in (%d)" % took)
	t.eq(m.gate_held, 0, "nothing left at the gate")
	m.queue_free()
	await get_tree().physics_frame

func test_a_host_that_keeps_up_is_not_touched() -> void:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "campaign", "stage": 1, "role": "host", "headless": true, "loadout": {"main": "gladius", "off": ""}, "seed": 6})
	m.stage_always = true
	m.me.drive = func(_e): return {"limp": true}
	var inert := func(e):
		e.erase("bot")
		e.drive = func(_e): return {}
	for e in m.enemies():
		inert.call(e)
	m.gate_cost_ms = 4.0
	var specs := []
	for i in 4:
		specs.append(_foe(i))
	m.bring_in(specs, inert)
	var took := await _until(func(): return m.coming == 0 and m.enemies().size() == 5, 1800)
	t.check(took >= 0, "at 4 ms a step all four come in over the frames (%d)" % took)
	t.eq(m.gate_held, 0, "none was held")
	m.queue_free()
	await get_tree().physics_frame

func test_what_is_not_a_foe_is_not_held() -> void:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "campaign", "stage": 1, "role": "host", "headless": true, "loadout": {"main": "gladius", "off": ""}, "seed": 6})
	m.stage_always = true
	m.me.drive = func(_e): return {"limp": true}
	m.gate_cost_ms = 20.0
	var goat := {"kind": "beast", "beast": "goat", "team": 2, "pos": Vector3(3, 0.1, 3), "yaw": 0.0, "harmless": true}
	m.bring_in([goat])
	var took := await _until(func(): return m.coming == 0, 1800)
	t.check(took >= 0, "a goat out of a pot comes in however dear a step is (%d)" % took)
	m.queue_free()
	await get_tree().physics_frame

## A loose weapons' snapshot is sent in packets that fit the line (user's console: "Sending 1464 bytes unreliably which is above the MTU (1392)"): each part under the MTU, the
## hazards with the first, every row once and in order.
func test_the_loose_weapons_snapshot_is_cut_to_fit_the_line() -> void:
	var rows := []
	for i in 60:
		rows.append([i, 1.234, 0.5, -3.21, 0.1, 0.2, 0.3, 0.9])
	var haz := [[1, 2.0, 3.0], [2, 4.0, 5.0]]
	var parts := Match.lsnap_messages(rows, haz)
	t.check(parts.size() > 1, "sixty weapons are more than a packet (%d parts)" % parts.size())
	var seen := []
	var biggest := 0
	for p in parts:
		biggest = maxi(biggest, var_to_bytes(p).size())
		for r in p.w:
			seen.append(int(r[0]))
	t.check(biggest < 1392, "each part under the MTU (the biggest is %d bytes)" % biggest)
	t.eq(seen.size(), 60, "every row is sent")
	var in_order := true
	for i in seen.size():
		if seen[i] != i:
			in_order = false
	t.check(in_order, "once, in order")
	t.check((parts[0] as Dictionary).has("h") and not (parts[1] as Dictionary).has("h"), "the hazards with the first part only")
	var few := Match.lsnap_messages([rows[0]], haz)
	t.eq(few.size(), 1, "a few weapons are the one packet they were")
	t.eq(Match.lsnap_messages([], haz).size(), 1, "and none still says the hazards")

## What the room's cost does to the fight is said on the state line (to the host and, as the line goes to them, to every guest): foes kept outside the gate, and the world slowed with its speed.
func test_the_state_line_says_when_foes_wait_and_when_the_game_runs_slow() -> void:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "endless", "role": "host", "headless": true, "seed": 3, "decrees": [], "hazards": [], "loadout": {"main": "gladius", "off": ""}, "endless": {"seed": 11}})
	t.eq(m.load_note(), "", "a room within its budget: nothing is added")
	m.gate_held = 1
	t.eq(m.load_note(), "a foe waits outside", "one foe held outside")
	m.gate_held = 3
	var was_over: bool = Net.overloaded
	var was_rate: float = Net.step_rate
	Net.overloaded = true
	Net.step_rate = 70.0
	t.eq(m.load_note(), "3 foes wait outside · game at 60% speed: 1 man on the sand", "three held, and the world at 58% (said in fives), with who is on the sand")
	t.check(m.fight_status().contains("game at 60% speed: 1 man on the sand") and m.fight_status().begins_with("Wave"), "on the state line, after the wave's own words (%s)" % m.fight_status())
	Net.step_rate = 120.0
	t.eq(m.load_note(), "3 foes wait outside · game at 100% speed: 1 man on the sand", "a speed is never said above the whole of it")
	Net.overloaded = false
	m.gate_held = 0
	var g := Match.new()
	g.role = "guest"
	g.fstat = "Wave 2 · 4 slain · game at 60% speed: 5 men on the sand"
	t.eq(g.fight_status(), "Wave 2 · 4 slain · game at 60% speed: 5 men on the sand", "a guest reads what the host said, as it was")
	t.eq(g.load_note(), "", "and adds nothing of his own")
	g.free()
	Net.overloaded = was_over
	Net.step_rate = was_rate
	m.queue_free()
	await get_tree().physics_frame

## When the room turns heavy (or light again) what it was made of at that moment is written beside it in the performance record: who was alive, what was on its way or held, what lay about.
func test_the_room_turning_heavy_is_written_with_what_it_was_made_of() -> void:
	FpsMeter.force_record = true
	var path := FpsMeter.log_path()
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "endless", "role": "host", "headless": true, "seed": 3, "decrees": [], "hazards": [], "loadout": {"main": "gladius", "off": ""}, "endless": {"seed": 11}})
	var was_over: bool = Net.overloaded
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)   # (the match's own start was written: not what is looked at here)
	m._note_load()
	t.check(not FileAccess.file_exists(path), "a room that stays light writes nothing")
	m.gate_held = 2
	Net.overloaded = true
	m._note_load()
	var text := FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""
	t.check(text.contains("the room turned heavy: 1 players and 0 foes alive") and text.contains("2 held at the gate"), "going over its budget it says who was in it (%s)" % text.left(200))
	m._note_load()
	t.eq(text.split("\n", false).size(), FileAccess.get_file_as_string(path).split("\n", false).size(), "and once, not every second it stays so")
	Net.overloaded = false
	m._note_load()
	t.check(FileAccess.get_file_as_string(path).contains("the room turned light"), "coming back it says so")
	Net.overloaded = was_over
	m.gate_held = 0
	DirAccess.remove_absolute(path)
	FpsMeter.force_record = false
	m.queue_free()
	await get_tree().physics_frame
