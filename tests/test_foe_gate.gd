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
