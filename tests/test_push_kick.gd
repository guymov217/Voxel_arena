extends Node
## A push kick (user, #352: hold the kick's key to wind the kick up with a swing, let go to drive it home: it wounds and shoves a man hard): the key tapped is the kick it ever was; held
## past the knee coming up, the kick waits there, the knee up and the heel drawn in, and goes out as the key is let go, the harder the longer it was held (up to a full wind-up); it costs
## breath; a man out of breath or knocked down lets it go; the held key goes over the wire.

var t

func _steps(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

## A fresh match with a kicker (his input: the kick on the first step, the key held for `hold` seconds) and a man standing before him, and what came of it: {hits: [[J, dmg, push, where the foot met him
## (y), winded, the part]...], vmax, dx, dz, fell, wind: the kick's clock and wind-up state a step after `hold - 0.05`, stamina, kicker, victim, match}. `breath` is the kicker's stamina at the start,
## `during` a callback (steps, kicker) now and then, `gap` how far apart their trunks stand (m).
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
	var out := {"hits": [], "vmax": 0.0, "dx": 0.0, "dz": 0.0, "fell": false, "wind": [], "kicker": a.f, "victim": v.f, "match": m, "struck_while_held": 0, "kicker_fell": false}
	m.combat.hit.connect(func(h):
		if h.get("kick", false) and h.char == v.f:
			out.hits.append([float(h.get("J", 0.0)), float(h.res.get("dmg", 0.0)), float(h.get("push", 0.0)), (h.get("p", Vector3.ZERO) as Vector3).y, bool(h.res.get("winded", false)), String(h.part.part_name)])
			if a.f.kick_wind == 1:
				out.struck_while_held += 1)
	var x0: float = v.f.torso.global_position.x
	var z0: float = v.f.torso.global_position.z
	st.kick = true
	st.hold = hold > 0.0
	var t_hold := 0.0
	for k in int((hold + 1.4) * 120.0):
		await get_tree().physics_frame
		if st.hold:
			t_hold += 1.0 / 120.0
			if t_hold >= hold:
				st.hold = false
		if k % 6 == 0:
			out.wind.append([k / 120.0, a.f.kick_wind, a.f.kick_timer, a.f.kick_hold, a.f.stamina])
		if during.is_valid():
			during.call(k, a.f)
		out.vmax = maxf(out.vmax, v.f.torso.linear_velocity.length())
		if v.f.state != "stand":
			out.fell = true
		if a.f.state != "stand":
			out.kicker_fell = true
	out.dx = v.f.torso.global_position.x - x0
	out.dz = v.f.torso.global_position.z - z0
	return out

func _free(d: Dictionary) -> void:
	d.match.queue_free()

func test_a_tap_of_the_key_is_the_plain_kick_it_was() -> void:
	var d := await _duel(0.0, 0)
	var winds: Array = d.wind.filter(func(w): return w[1] != 0)
	t.check(winds.is_empty(), "a tap never winds the kick up")
	t.check(d.hits.size() == 1 and absf(d.hits[0][0] - 20.0) < 0.5 and d.hits[0][2] == 0.0, "the kick lands as it did: J %s" % str(d.hits))
	t.check(not d.fell and d.vmax < 2.0, "and shoves him a little (his top speed %.2f)" % d.vmax)
	t.check(d.kicker.kick_timer == 0.0 and d.kicker.kick_wind == 0 and d.kicker.kick_push == 0.0, "and is over")
	_free(d)
	# The key let go as the knee comes up, or a hair after: a short hold is a plain kick's.
	var d2 := await _duel(0.2, 1)
	t.check(d2.hits.size() == 1 and d2.hits[0][2] == 0.0 and absf(d2.hits[0][0] - 20.0) < 0.5, "held only as the knee comes up, it is the plain kick (J %s)" % str(d2.hits))
	_free(d2)

func test_the_key_held_winds_the_kick_up_with_the_knee_up() -> void:
	var d := await _duel(0.45, 2)
	var held: Array = d.wind.filter(func(w): return w[1] == 1)
	t.check(held.size() >= 6, "the kick waits wound up while the key is held (%d samples)" % held.size())
	var steady: bool = held.all(func(w): return absf(w[2] - (Fighter.KICK_TIME - Fighter.PUSH_AT)) < 0.002)
	t.check(steady, "its clock held where the knee is up (%s)" % str(held.slice(0, 3)))
	t.check(held.size() >= 2 and held[held.size() - 1][3] > held[0][3] + 0.15, "the wind-up grows the longer the key is held")
	t.check(d.struck_while_held == 0, "and no blow lands from the foot while it is held")
	t.check(held.size() >= 1 and held[held.size() - 1][4] < 100.0 - 12.0 - 3.0, "it costs breath over the kick's twelve (%.0f left)" % (held[held.size() - 1][4] if held.size() >= 1 else -1.0))
	t.check(d.hits.size() == 1 and d.hits[0][2] > 0.3, "and let go it lands as a push kick (%s)" % str(d.hits))
	_free(d)

func test_let_go_it_goes_out_harder_the_longer_it_was_held() -> void:
	# (One match at a time: two in the one physics world are bodies in each other's place.)
	var rows := []
	for hold in [0.0, 0.5, 0.9]:
		var d := await _duel(hold, 3)
		rows.append({"J": d.hits[0][0] if d.hits.size() > 0 else 0.0, "dmg": d.hits[0][1] if d.hits.size() > 0 else 0.0, "push": d.hits[0][2] if d.hits.size() > 0 else -1.0, "v": d.vmax, "winded": d.hits.size() > 0 and d.hits[0][4]})
		_free(d)
		await _steps(2)
	var plain: Dictionary = rows[0]
	var mid: Dictionary = rows[1]
	var full: Dictionary = rows[2]
	t.check(plain.J > 0.0 and mid.J > plain.J * 1.3 and full.J > mid.J * 1.15 and full.J > plain.J * 1.9, "the blow grows with the wind-up: %.1f, %.1f, %.1f" % [plain.J, mid.J, full.J])
	t.check(mid.v > plain.v * 1.8 and full.v > mid.v * 1.1 and full.v > plain.v * 3.0, "and so does the shove (his top speed %.1f, %.1f, %.1f m/s)" % [plain.v, mid.v, full.v])
	t.check(full.push >= 0.99 and mid.push > 0.3 and mid.push < 0.8, "(wound up %.2f and %.2f of a full one)" % [mid.push, full.push])
	t.check(full.dmg >= plain.dmg and full.winded and not plain.winded, "and it wounds: no less than a plain kick (%.0f against %.0f) and it takes his wind (%s, a plain one's %s)" % [full.dmg, plain.dmg, str(full.winded), str(plain.winded)])

func test_a_full_push_kick_lands_at_the_waist_in_one_blow() -> void:
	# (The foot comes out at the height of his belt, not up at his chest nor down at his shins, whether he stands close or a pace off, and the foot that has landed lands no more.)
	for gap in [0.85, 1.0]:
		var d := await _duel(0.9, 4, 100.0, Callable(), gap)
		t.check(d.hits.size() == 1, "one blow, the foot pressed on him lands no more (gap %.2f: %d hits)" % [gap, d.hits.size()])
		if d.hits.size() >= 1:
			var y: float = d.hits[0][3]
			t.check(y > 0.8 and y < 1.15, "at his waist (the foot met him at %.2f m up on his %s, gap %.2f)" % [y, d.hits[0][5], gap])
			t.check(not String(d.hits[0][5]).begins_with("shin") and not String(d.hits[0][5]).begins_with("thigh") and d.hits[0][5] != "head", "not on his legs nor his head (%s)" % d.hits[0][5])
		_free(d)
		await _steps(2)

func test_a_push_kick_drives_him_straight_back_and_the_kicker_keeps_his_feet() -> void:
	var d := await _duel(0.9, 5)
	t.check(absf(d.dz) > 0.5 and absf(d.dx) < 0.4 * absf(d.dz) + 0.05, "he goes back along the line from the kicker, not up or aside (%.2f m along, %.2f m across)" % [d.dz, d.dx])
	t.check(not d.kicker_fell and d.kicker.state == "stand", "and the kicker stays on his feet through it (%s)" % d.kicker.state)
	_free(d)

func test_a_full_push_kick_throws_a_man_off_his_feet_far_oftener_than_a_plain_one() -> void:
	var fell_full := 0
	var fell_plain := 0
	var shoved := 0.0
	for sd in 6:
		var f := await _duel(0.9, 10 + sd)
		var p := await _duel(0.0, 10 + sd)
		fell_full += 1 if f.fell else 0
		fell_plain += 1 if p.fell else 0
		shoved += absf(f.dz)
		_free(f)
		_free(p)
	t.check(fell_full >= 4, "a full push kick fells him most times (%d of 6)" % fell_full)
	t.check(fell_plain <= 1, "a plain one hardly ever (%d of 6)" % fell_plain)
	t.check(shoved / 6.0 > 1.2, "and sends him back (%.2f m on the average)" % (shoved / 6.0))

func test_a_man_out_of_breath_lets_the_wind_up_go() -> void:
	# Breath for the kick, and little over: the wind-up is let go as it runs out, the key still down.
	var d := await _duel(1.2, 20, 17.0)
	var held: Array = d.wind.filter(func(w): return w[1] == 1)
	var gone: Array = d.wind.filter(func(w): return w[1] == 2)
	t.check(not held.is_empty() and not gone.is_empty(), "held with the breath there is, then let go with the key still down (%d held samples, %d going out)" % [held.size(), gone.size()])
	t.check(d.kicker.kick_timer == 0.0 and d.kicker.kick_wind == 0, "and the kick is over, not hung")
	_free(d)

func test_a_man_knocked_down_in_the_wind_up_does_not_hang_the_kick() -> void:
	var drop := func(k: int, f: Fighter) -> void:
		if k == 50:
			f.fall(30.0, true)
	var d := await _duel(1.5, 21, 100.0, drop)
	t.check(d.kicker.kick_timer == 0.0 and d.kicker.kick_wind == 0 and d.kicker.kick_hold == 0.0, "the kick is over (clock %.2f, wind-up %d)" % [d.kicker.kick_timer, d.kicker.kick_wind])
	_free(d)

func test_a_push_kick_lands_on_a_beast_as_a_blow_and_a_shove() -> void:
	# (A beast is not sent back with the whole of him as a man is, nor felled as lightly when it is bigger than the man: the blow and the trunk's shove, no more.)
	var landed := 0
	for gap in [1.1, 1.3, 1.5]:
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
				if t_hold >= 0.9:
					st.hold = false
		if hits.size() > 0:
			landed += 1
			t.check(hits.size() == 1 and hits[0][1] > 0.99 and hits[0][0] >= 39.0, "it lands once and as a full push kick (%s, gap %.1f)" % [str(hits), gap])
		t.check(a.f.kick_timer == 0.0 and a.f.kick_wind == 0, "and the kick ends (gap %.1f)" % gap)
		m.queue_free()
		await _steps(2)
	t.check(landed >= 1, "it landed on the boar at one of the gaps at least (%d of 3)" % landed)

func test_the_held_key_goes_over_the_wire() -> void:
	var inp := {"mx": 1.0, "mz": -1.0, "sprint": true, "crouch": true, "jump": true, "kick": true, "kickHold": true, "grabHands": "both", "grip": true, "revive": true, "depthOn": true, "depth": 0.5, "aimAt": Vector3(1, 2, 3), "aimFrom": Vector3(0, 1, 0), "look": {"yaw": 1.5, "pitch": 0.2}, "seq": 77}
	var back := PlayerInput.unpack(PlayerInput.pack(inp))
	t.check(back.kickHold and back.kick and back.sprint and back.crouch and back.jump and back.grip and back.revive and back.depthOn and back.grabHands == "both" and int(back.seq) == 77, "the key held comes out held, and every other flag with it")
	inp.kickHold = false
	back = PlayerInput.unpack(PlayerInput.pack(inp))
	t.check(not back.kickHold and back.kick and back.grip and back.depthOn and int(back.seq) == 77, "and let go comes out let go, the kick's tap and the rest as they were")
	inp.erase("kickHold")
	t.check(not PlayerInput.unpack(PlayerInput.pack(inp)).kickHold, "an input that says nothing of it is not holding it")
