extends Node
## Wrestling and the rest of social.gd (the web game's social tests): shoves, grabs, throws of
## men, weapons and limbs, and the inputs that carry them over the network.

var t

func _match() -> Match:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none"}, "headless": true, "seed": 3})
	return m

func _man(m: Match, pos: Vector3, yaw: float, lo: Dictionary, name_: String, team: int, drive: Callable, mods := {}) -> Dictionary:
	var e = m.spawn_fighter({"kind": "bot", "name": name_, "loadout": lo, "team": team, "pos": pos, "yaw": yaw, "mods": mods})
	e.erase("bot")
	e.drive = drive
	return e

func _steps(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func _idle(_e) -> Dictionary:
	return {"main": {"x": 0.1, "y": 0.1}}

func test_a_shove_pushes_a_man_back_and_downs_a_tired_one() -> void:
	var m := _match()
	m.me.f.state = "dead"
	var once := [true]
	var a := _man(m, Vector3(0, 0, 0), 0.0, {}, "A", 0, func(_e):
		var i := {"main": {"x": 0.1, "y": 0.1}, "look": {"yaw": 0.0, "pitch": 0.0}}
		if once[0] and m.time > 1.5:
			once[0] = false
			i.shove = true
		return i)
	var b := _man(m, Vector3(0, 0, 0.9), PI, {}, "B", 1, _idle)
	await _steps(170)
	var z0: float = b.f.torso.global_position.z
	await _steps(60)
	var moved: float = b.f.torso.global_position.z - z0
	t.check(moved > 0.05, "the shoved man went back (%.2f m)" % moved)
	t.check(a.f.stamina < 100.0, "shoving costs breath")
	# Winded, the same shove puts him down.
	b.f.stamina = 5.0
	b.f.stagger = 0.6
	a.f.shove_cool = 0.0
	once[0] = true
	var down := false
	for i in 120:
		await get_tree().physics_frame
		b.f.stamina = minf(b.f.stamina, 5.0)
		if b.f.state != "stand":
			down = true
			break
	t.check(down, "a tired man goes down")
	m.queue_free()

func test_grab_hold_and_throw_a_man() -> void:
	var m := _match()
	m.me.f.state = "dead"
	var phase := ["wait"]
	var a := _man(m, Vector3(0, 0, 0), 0.0, {}, "A", 0, func(_e):
		var i := {"main": {"x": 0.1, "y": 0.4}, "off": {"x": -0.1, "y": 0.4}, "look": {"yaw": 0.0, "pitch": 0.0}}
		if phase[0] == "grab":
			i.grab = true
			phase[0] = "hold"
		elif phase[0] == "throw":
			i.throw = true
			i.throwPower = 1.0
			phase[0] = "done"
		return i)
	var b := _man(m, Vector3(0, 0, 0.7), PI, {}, "B", 1, _idle)
	await _steps(150)
	var shift: Vector3 = a.f.hand_world("R") + Vector3(0, 0, 0.25) - b.f.torso.global_position
	shift.y = 0.0
	for p in b.f.parts:
		p.global_position += shift
	phase[0] = "grab"
	await _steps(30)
	t.check(a.f.holding != null, "the hand closed on him")
	if a.f.holding == null:
		m.queue_free()
		return
	t.check(b.f.grabbed_by == a.f, "he knows he is held")
	phase[0] = "throw"
	await _steps(2)
	t.check(a.f.holding == null, "let go with the throw")
	var v: Vector3 = b.f.torso.linear_velocity
	t.check(v.length() > 2.0, "he flies (%.1f m/s)" % v.length())
	await _steps(30)
	t.check(b.f.state != "stand", "and lands on the sand")
	m.queue_free()

func test_a_dropped_weapon_is_picked_up_and_thrown() -> void:
	var m := _match()
	m.me.f.state = "dead"
	var act := [""]
	var a := _man(m, Vector3(0, 0, 0), 0.0, {"main": "gladius"}, "A", 0, func(_e):
		var i := {"main": {"x": 0.1, "y": -0.6}, "look": {"yaw": 0.0, "pitch": 0.0}, "crouch": true}
		if act[0] != "":
			i[act[0]] = true
			if act[0] == "throw":
				i.throwPower = 1.0
			act[0] = ""
		return i)
	await _steps(120)
	var w: Weapon = a.f.release("R")
	t.check(m.combat.loose_weapons.has(w), "the dropped blade is loose")
	await _steps(90)
	act[0] = "grab"
	await _steps(4)
	t.eq(a.f.weapons.R, w, "picked it back up")
	await _steps(60)
	var x0: float = a.f.torso.global_position.z
	act[0] = "throw"
	# A bot draws the arm back first (0.45 s), then lets go.
	await _steps(3)
	t.check(a.f.weapons.R == w and a.f.throw_anim != null and a.f.throw_anim.phase == "wind", "it winds up first")
	await _steps(60)
	t.check(a.f.weapons.R == null, "it left the hand")
	t.check(w.thrown_t > 0.0 and w.thrower == a.f, "it flies as a thrown weapon")
	await _steps(30)
	t.check(w.global_position.z - x0 > 2.0, "forward, a good way (%.1f m)" % (w.global_position.z - x0))
	m.queue_free()

func test_a_giant_grabs_and_hurls_or_slams() -> void:
	seed(11)
	var m := _match()
	m.me.f.state = "dead"
	var victim := _man(m, Vector3(0, 0, 1.6), PI, {}, "Victim", 0, _idle)
	var giant = m.spawn_fighter({"kind": "bot", "name": "Giant", "loadout": {}, "team": 1, "pos": Vector3(0, 0, 0), "yaw": 0.0, "mods": {"bodyScale": 2.0, "strength": 2.0}, "diff": 0.9})
	var moves := []
	m.feed.connect(func(s): moves.append(s))
	for k in 50:
		await _steps(60)
		if moves.any(func(s): return s.contains("SLAMS") or s.contains("tossed")):
			break
		if OS.get_environment("DEBUG_GIANT") != "":
			print("  t=%.1f giant=%s holding=%s bot_hold=%.2f move=%s victim=%s y=%.2f" % [m.time, giant.f.state, giant.f.holding != null, giant.bot.hold_t, giant.bot.hold_move, victim.f.state, victim.f.torso.global_position.y])
	t.check(moves.any(func(s): return s.contains("grabbed")), "the giant took hold of him (%s)" % str(moves))
	t.check(moves.any(func(s): return s.contains("SLAMS") or s.contains("tossed")), "and hurled or slammed him (%s)" % str(moves))
	m.queue_free()

func test_inputs_survive_the_network() -> void:
	var inp := {"mx": 0.5, "mz": -1.0, "main": {"x": 0.2, "y": -0.3}, "off": {"x": -0.4, "y": 0.1}, "thrust": 0.5, "look": {"yaw": 1.0, "pitch": 0.2},
		"grab": true, "grabHands": "both", "throw": true, "throwPower": 0.7, "shove": true, "taunt": false, "limp": true, "kick": true}
	var back := PlayerInput.unpack(PlayerInput.pack(inp))
	for k in ["grab", "throw", "shove", "limp", "kick"]:
		t.eq(back.get(k), true, k)
	t.eq(back.get("taunt"), false, "taunt")
	t.eq(back.grabHands, "both", "grab hands")
	t.check(absf(back.throwPower - 0.7) < 0.01, "throw power")
	t.check(PlayerInput.has_one_shot(inp), "a press makes the packet reliable")
	# A press the host has not acted on yet survives the next packet, and is acted on once.
	Net.inputs[77] = PlayerInput.unpack(PlayerInput.pack({"grab": true}))
	Net._receive("input", PlayerInput.pack({"mz": 1.0}), 77)
	t.eq(Net.input_of(77).get("grab"), true, "kept until read")
	t.eq(Net.input_of(77).get("grab"), false, "read once")
	Net.inputs.erase(77)

func test_grabbing_an_arm_pins_it_and_a_severed_arm_is_a_club() -> void:
	var m := _match()
	m.me.f.state = "dead"
	var a := _man(m, Vector3(0, 0, 0), 0.0, {}, "A", 0, _idle)
	var b := _man(m, Vector3(0, 0, 1.0), PI, {"main": "gladius"}, "B", 1, _idle)
	await _steps(60)
	# Put B's sword forearm in A's right hand, then grab.
	var shift: Vector3 = a.f.hand_world("R") - b.f.arm.R.fore.global_position
	for p in b.f.parts:
		p.global_position += shift
	b.f.weapons.R.global_position += shift
	var held = m.social.grab_person(a, {})
	t.eq(held, b.f, "took hold of him")
	t.eq(b.f.pinned_arm, "R", "his sword arm is pinned")
	m.social.let_go(a.f)
	t.eq(b.f.pinned_arm, "", "free again")
	await _steps(30)
	# Cut B's left arm off and lay it by A's hand: G picks it up as a club.
	var res := {"removed": [], "severed": []}
	b.f.detach_limb(b.f.arm.L.upper, res)
	var limb: VoxelPart = b.f.arm.L.fore
	limb.global_position = a.f.hand_world("R") + Vector3(0, -0.1, 0.1)
	var took = m.social.grab_limb(a)
	t.check(took != null and a.f.holding != null and a.f.holding.limb != null, "a loose arm is picked up")
	if a.f.holding != null:
		m.social._throw_limb(a, {"throwPower": 1.0})
		t.check(a.f.holding == null and (took as VoxelPart).thrown_t > 0.0, "and thrown like a club")
	m.queue_free()
