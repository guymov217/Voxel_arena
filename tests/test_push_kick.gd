extends Node
## A push kick (user, #352 and again: a long press of the kick's key is a hard kick to the belly, not a charged one, and the man who kicks is not launched by it): the key tapped is the kick it
## ever was; held past the knee coming up, the kick waits there, the knee up and the heel drawn in, and past PUSH_ARM s of the press it goes out by itself, at one strength whatever the hold,
## the foot at his waist, the man sent back (not up, not far) and often felled; the man who kicks is not carried with it; it costs breath; a man out of breath or knocked down lets it go
## as a plain kick; the held key goes over the wire.

var t

func _steps(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

## A fresh match with a kicker (his input: the kick on the first step, the key held for `hold` seconds) and a man standing before him, and what came of it: {hits: [[J, dmg, push, where the foot met him
## (y), winded, the part, the key still down]...], vmax (the victim's top speed), vrise (how high his trunk went), dx, dz, fell, wind: samples [s, the kick's wind state, its clock, how long held,
## stamina, the key down], held_s (how long the kick waited wound), dzpeak and dxpeak (how far back and aside his trunk went at the most), kicker, victim, match, kmax (the kicker's top flat speed), kup (his top upward speed), kcarried (how far his trunk was carried,
## m)}. `breath` is the kicker's stamina at the start, `during` a callback (steps, kicker) now and then, `gap` how far apart their trunks stand (m).
func _duel(hold: float, sd: int, breath := 100.0, during := Callable(), gap := 0.85) -> Dictionary:
	seed(100 + sd)
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none", "respawn": false}, "headless": true, "seed": 3 + sd, "decrees": [], "hazards": []})
	m.me.f.teleport(Vector3(0, 0, -12))
	var a = m.spawn_fighter({"kind": "bot", "name": "A", "loadout": {}, "team": 2, "pos": Vector3(0, 0, -gap), "yaw": 0.0})
	a.erase("bot")
	var v = m.spawn_fighter({"kind": "bot", "name": "V", "loadout": {}, "team": 1, "pos": Vector3(0, 0, 0), "yaw": PI})
	v.erase("bot")
	v.drive = func(_e): return {}
	var st := {"kick": false, "hold": false}
	a.drive = func(_e):
		var o := {"kick": st.kick, "kickHold": st.hold}
		st.kick = false
		return o
	await _steps(100)
	a.f.stamina = breath
	var out := {"hits": [], "vmax": 0.0, "vrise": 0.0, "dx": 0.0, "dz": 0.0, "dzpeak": 0.0, "dxpeak": 0.0, "fell": false, "wind": [], "held_s": 0.0, "kicker": a.f, "victim": v.f, "match": m, "struck_while_held": 0, "kicker_fell": false, "kmax": 0.0, "kup": 0.0, "kcarried": 0.0}
	m.combat.hit.connect(func(h):
		if h.get("kick", false) and h.char == v.f:
			out.hits.append([float(h.get("J", 0.0)), float(h.res.get("dmg", 0.0)), float(h.get("push", 0.0)), (h.get("p", Vector3.ZERO) as Vector3).y, bool(h.res.get("winded", false)), String(h.part.part_name), st.hold])
			if a.f.kick_wind == 1:
				out.struck_while_held += 1)
	var x0: float = v.f.torso.global_position.x
	var z0: float = v.f.torso.global_position.z
	var y0: float = v.f.torso.global_position.y
	var kz0: float = a.f.torso.global_position.z
	st.kick = true
	st.hold = hold > 0.0
	var t_hold := 0.0
	for k in int((hold + 1.4) * 120.0):
		await get_tree().physics_frame
		if st.hold:
			t_hold += 1.0 / 120.0
			if t_hold >= hold:
				st.hold = false
		if a.f.kick_wind == 1:
			out.held_s += 1.0 / 120.0
		if k % 6 == 0:
			out.wind.append([k / 120.0, a.f.kick_wind, a.f.kick_timer, a.f.kick_hold, a.f.stamina, st.hold])
		if during.is_valid():
			during.call(k, a.f)
		out.vmax = maxf(out.vmax, v.f.torso.linear_velocity.length())
		out.vrise = maxf(out.vrise, v.f.torso.global_position.y - y0)
		out.dzpeak = maxf(out.dzpeak, absf(v.f.torso.global_position.z - z0))
		out.dxpeak = maxf(out.dxpeak, absf(v.f.torso.global_position.x - x0))
		var kv: Vector3 = a.f.torso.linear_velocity
		out.kmax = maxf(out.kmax, Vector2(kv.x, kv.z).length())
		out.kup = maxf(out.kup, kv.y)
		if v.f.state != "stand":
			out.fell = true
		if a.f.state != "stand":
			out.kicker_fell = true
	out.dx = v.f.torso.global_position.x - x0
	out.dz = v.f.torso.global_position.z - z0
	out.kcarried = absf(a.f.torso.global_position.z - kz0)
	return out

func _free(d: Dictionary) -> void:
	d.match.queue_free()

## The kicker's breath a half second after the key was pressed (a sample of `wind`).
func _breath_at_half_second(d: Dictionary) -> float:
	for w in d.wind:
		if w[0] >= 0.5:
			return w[4]
	return -1.0

func test_a_tap_of_the_key_is_the_plain_kick_it_was() -> void:
	var d := await _duel(0.0, 0)
	var winds: Array = d.wind.filter(func(w): return w[1] != 0)
	t.check(winds.is_empty(), "a tap never winds the kick up")
	t.check(d.hits.size() == 1 and absf(d.hits[0][0] - 20.0) < 0.5 and d.hits[0][2] == 0.0, "the kick lands as it did: J %s" % str(d.hits))
	t.check(not d.fell and d.vmax < 2.0, "and shoves him a little (his top speed %.2f)" % d.vmax)
	t.check(d.kicker.kick_timer == 0.0 and d.kicker.kick_wind == 0 and d.kicker.kick_push == 0.0, "and is over")
	_free(d)
	# The key let go a moment after the knee is up, short of a long press: the plain kick, from where the knee is.
	var d2 := await _duel(0.2, 1)
	t.check(d2.hits.size() == 1 and d2.hits[0][2] == 0.0 and absf(d2.hits[0][0] - 20.0) < 0.5, "held a moment and let go, it is the plain kick (J %s)" % str(d2.hits))
	_free(d2)

func test_a_long_press_waits_with_the_knee_up_and_goes_out_by_itself() -> void:
	var d := await _duel(1.0, 2)
	var held: Array = d.wind.filter(func(w): return w[1] == 1)
	t.check(held.size() >= 2, "the kick waits, wound, while the key is down (%d samples)" % held.size())
	var steady: bool = held.all(func(w): return absf(w[2] - (Fighter.KICK_TIME - Fighter.PUSH_AT)) < 0.002)
	t.check(steady, "its clock held where the knee is up (%s)" % str(held.slice(0, 3)))
	t.check(d.struck_while_held == 0, "and no blow lands from the foot while it is held")
	t.check(absf(d.held_s - Fighter.PUSH_HOLD) < 0.03, "it waits no longer than the long press asks (%.2f s held past the knee; it asks %.2f)" % [d.held_s, Fighter.PUSH_HOLD])
	var out: Array = d.wind.filter(func(w): return w[1] == 2 and w[5])
	t.check(not out.is_empty(), "and it goes out by itself, with the key still down (%d samples)" % out.size())
	t.check(d.hits.size() == 1 and d.hits[0][2] == 1.0 and d.hits[0][0] >= 39.0, "and lands once, as a push kick (%s)" % str(d.hits))
	t.check(d.hits.size() == 1 and d.hits[0][6], "the key not yet let go when it lands")
	_free(d)

func test_the_push_kick_costs_breath_over_the_kicks_twelve() -> void:
	var plain := await _duel(0.0, 3)
	var plain_left := _breath_at_half_second(plain)
	_free(plain)
	await _steps(2)
	var hard := await _duel(1.0, 3)
	var hard_left := _breath_at_half_second(hard)
	_free(hard)
	t.check(plain_left > 0.0 and plain_left - hard_left >= Fighter.PUSH_COST - 3.0, "it takes its breath: %.0f left after a plain kick, %.0f after a push kick (it costs %.0f over)" % [plain_left, hard_left, Fighter.PUSH_COST])

func test_the_strength_is_the_same_however_long_the_key_is_held() -> void:
	# (Not a charge: held for a little over the long press or for a long while, the same kick.)
	var rows := []
	for hold in [0.4, 0.7, 1.3]:
		var d := await _duel(hold, 4)
		rows.append({"J": d.hits[0][0] if d.hits.size() > 0 else 0.0, "push": d.hits[0][2] if d.hits.size() > 0 else -1.0, "v": d.vmax, "winded": d.hits.size() > 0 and d.hits[0][4]})
		_free(d)
		await _steps(2)
	t.check(rows.all(func(r): return r.push == 1.0 and r.J >= 39.0 and r.winded), "each lands as the one push kick and takes his wind (%s)" % str(rows))
	t.check(absf(rows[0].J - rows[2].J) < 0.5 and absf(rows[0].v - rows[1].v) < 0.2 * rows[0].v and absf(rows[0].v - rows[2].v) < 0.2 * rows[0].v, "the blow and the shove are the same (J %.1f, %.1f, %.1f; his top speed %.1f, %.1f, %.1f m/s)" % [rows[0].J, rows[1].J, rows[2].J, rows[0].v, rows[1].v, rows[2].v])

func test_a_push_kick_lands_on_his_belly_in_one_blow() -> void:
	# (The foot comes out at the height of his belt, not up at his chest nor down at his shins, whether he stands close or a pace off, and the foot that has landed lands no more.)
	for gap in [0.75, 0.85, 0.95]:
		var d := await _duel(0.6, 5, 100.0, Callable(), gap)
		t.check(d.hits.size() == 1, "one blow, the foot pressed on him lands no more (gap %.2f: %d hits)" % [gap, d.hits.size()])
		if d.hits.size() >= 1:
			var y: float = d.hits[0][3]
			t.check(y > 0.8 and y < 1.15, "at his belly (the foot met him at %.2f m up on his %s, gap %.2f)" % [y, d.hits[0][5], gap])
			t.check(d.hits[0][5] == "torso", "on his trunk, not his legs nor his arms nor his head (%s, gap %.2f)" % [d.hits[0][5], gap])
			t.check(d.hits[0][4], "and it takes his wind (gap %.2f)" % gap)
		_free(d)
		await _steps(2)

func test_a_push_kick_sends_him_straight_back_not_up_and_the_kicker_is_not_carried_with_it() -> void:
	var d := await _duel(0.6, 6)
	t.check(d.dzpeak > 0.2 and d.dxpeak < 0.4 * d.dzpeak + 0.05, "he goes back along the line from the kicker, not aside (%.2f m along at the most, %.2f m across)" % [d.dzpeak, d.dxpeak])
	t.check(d.vmax > 2.2 and d.vmax < 5.0, "sent back, not launched: his top speed %.1f m/s" % d.vmax)
	t.check(d.vrise < 0.3, "and not up: his trunk rose %.2f m" % d.vrise)
	t.check(not d.kicker_fell and d.kicker.state == "stand", "the kicker stays on his feet through it (%s)" % d.kicker.state)
	t.check(d.kmax < 0.6 and d.kup < 0.5 and d.kcarried < 0.15, "and is not driven by it: his trunk's top speed %.2f m/s flat, %.2f up, carried %.2f m" % [d.kmax, d.kup, d.kcarried])
	_free(d)

func test_a_push_kick_throws_a_man_off_his_feet_far_oftener_than_a_plain_one() -> void:
	var fell_full := 0
	var fell_plain := 0
	var shoved := 0.0
	var moved := 0
	var peaks := []
	for sd in 6:
		var f := await _duel(0.6, 10 + sd)
		var p := await _duel(0.0, 10 + sd)
		fell_full += 1 if f.fell else 0
		fell_plain += 1 if p.fell else 0
		shoved += f.dzpeak
		moved += 1 if f.vmax > 2.5 else 0
		peaks.append("%.2f%s/%s" % [f.dzpeak, "F" if f.fell else "", ",".join(f.hits.map(func(h): return "%s@%.2f" % [h[5], h[3]]))])
		_free(f)
		_free(p)
	t.check(fell_full >= 3, "a push kick fells him most times (%d of 6)" % fell_full)
	t.check(fell_plain <= 1, "a plain one hardly ever (%d of 6)" % fell_plain)
	t.check(moved >= 6, "and it never fails to move him: every one of 6 shoves him at over 2.5 m/s, on his feet or off (%d: %s)" % [moved, str(peaks)])
	t.check(shoved / 6.0 > 0.8, "and sends him back (%.2f m at the most, on the average)" % (shoved / 6.0))

func test_a_man_out_of_breath_lets_the_long_press_go_as_a_plain_kick() -> void:
	# Breath for the kick, and little over: not enough for the hard one (it takes its ten over the kick's twelve), so the kick that goes out is the plain one, at once, the key still down.
	var d := await _duel(1.2, 20, 17.0)
	var wound: Array = d.wind.filter(func(w): return w[1] != 0)
	t.check(wound.is_empty(), "it does not wait wound for a hard kick he has not the breath for (%d samples)" % wound.size())
	t.check(d.hits.size() == 1 and d.hits[0][2] == 0.0 and absf(d.hits[0][0] - 20.0) < 0.5, "it is the plain kick (%s)" % str(d.hits))
	t.check(d.kicker.kick_timer == 0.0 and d.kicker.kick_wind == 0 and d.kicker.kick_push == 0.0, "and the kick is over, not hung (the breath got back in it does not wind it up again)")
	_free(d)
	# With the breath for it the same press is the hard kick.
	var d2 := await _duel(1.2, 20, 12.0 + Fighter.PUSH_COST + 6.0)
	t.check(d2.hits.size() == 1 and d2.hits[0][2] == 1.0, "and with the breath it is the push kick (%s)" % str(d2.hits))
	_free(d2)

func test_a_man_knocked_down_in_the_wind_up_does_not_hang_the_kick() -> void:
	var drop := func(k: int, f: Fighter) -> void:
		if k == 24:
			f.fall(30.0, true)
	var d := await _duel(1.5, 21, 100.0, drop)
	t.check(d.kicker.kick_timer == 0.0 and d.kicker.kick_wind == 0 and d.kicker.kick_hold == 0.0, "the kick is over (clock %.2f, wind-up %d)" % [d.kicker.kick_timer, d.kicker.kick_wind])
	_free(d)

func test_a_push_kick_lands_on_a_beast_as_a_blow_and_a_shove() -> void:
	# (A beast is not sent back with the whole of him as a man is, nor felled as lightly when it is bigger than the man: the blow and the trunk's shove, no more.)
	var landed := 0
	for gap in [0.9, 1.0, 1.1, 1.2]:
		seed(100)
		var m := Match.new()
		add_child(m)
		m.setup({"mode": "training", "training": {"enemy": "none", "respawn": false}, "headless": true, "seed": 3, "decrees": [], "hazards": []})
		m.me.f.teleport(Vector3(0, 0, -12))
		var a = m.spawn_fighter({"kind": "bot", "name": "A", "loadout": {}, "team": 2, "pos": Vector3(0, 0, -gap), "yaw": 0.0})
		a.erase("bot")
		var b = m.spawn_beast({"beast": "boar", "team": 1, "pos": Vector3(0, 0.1, 0.0), "yaw": PI, "harmless": true})
		var st := {"kick": false, "hold": false}
		a.drive = func(_e):
			var o := {"kick": st.kick, "kickHold": st.hold}
			st.kick = false
			return o
		await _steps(100)
		var hits := []
		m.combat.hit.connect(func(h):
			if h.get("kick", false) and h.char == b.f:
				hits.append([float(h.get("J", 0.0)), float(h.get("push", 0.0))]))
		st.kick = true
		st.hold = true
		var t_hold := 0.0
		for k in int(2.0 * 120.0):
			await get_tree().physics_frame
			if st.hold:
				t_hold += 1.0 / 120.0
				if t_hold >= 0.6:
					st.hold = false
		if hits.size() > 0:
			landed += 1
			t.check(hits.size() == 1 and hits[0][1] > 0.99 and hits[0][0] >= 39.0, "it lands once and as a push kick (%s, gap %.1f)" % [str(hits), gap])
		t.check(a.f.kick_timer == 0.0 and a.f.kick_wind == 0, "and the kick ends (gap %.1f)" % gap)
		m.queue_free()
		await _steps(2)
	t.check(landed >= 1, "it landed on the boar at one of the gaps at least (%d of 4)" % landed)

func test_the_held_key_goes_over_the_wire() -> void:
	var inp := {"mx": 1.0, "mz": -1.0, "sprint": true, "crouch": true, "jump": true, "kick": true, "kickHold": true, "grabHands": "both", "grip": true, "revive": true, "depthOn": true, "depth": 0.5, "aimAt": Vector3(1, 2, 3), "aimFrom": Vector3(0, 1, 0), "look": {"yaw": 1.5, "pitch": 0.2}, "seq": 77}
	var back := PlayerInput.unpack(PlayerInput.pack(inp))
	t.check(back.kickHold and back.kick and back.sprint and back.crouch and back.jump and back.grip and back.revive and back.depthOn and back.grabHands == "both" and int(back.seq) == 77, "the key held comes out held, and every other flag with it")
	inp.kickHold = false
	back = PlayerInput.unpack(PlayerInput.pack(inp))
	t.check(not back.kickHold and back.kick and back.grip and back.depthOn and int(back.seq) == 77, "and let go comes out let go, the kick's tap and the rest as they were")
	inp.erase("kickHold")
	t.check(not PlayerInput.unpack(PlayerInput.pack(inp)).kickHold, "an input that says nothing of it is not holding it")
