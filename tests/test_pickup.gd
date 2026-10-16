extends Node
## Taking a weapon up off the sand, the ways it happens in a bout: the hand that took it swings
## it, and can throw it, whatever state it lay there in (thrown, a dead man's, frozen for a
## guest, stuck in a body), and G with the button held near a sword takes the sword.

var t

func _steps(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func _base() -> Dictionary:
	return {"main": {"x": 0.2, "y": 0.2}, "off": {"x": -0.35, "y": 0.1}, "power": false, "look": {"yaw": 0.0, "pitch": 0.0}, "mx": 0.0, "mz": 0.0}

## The player's own path (social.gd): G, then a swing, then F. Returns [picked, hand travel, thrown].
func _try(m: Match, f: Fighter, w: Weapon, side: String, q: Array, grab: Dictionary) -> Array:
	q.append(grab)
	await _steps(30)
	var picked: bool = f.weapons[side] == w
	var h0 := f.hand_world(side)
	var moved := 0.0
	for i in 60:
		var s := _base()
		if side == "R":
			s.main = {"x": 1.5, "y": 1.2}
		else:
			s.off = {"x": -1.5, "y": 1.2}
		s.power = true
		q.append(s)
		await get_tree().physics_frame
		moved = maxf(moved, f.hand_world(side).distance_to(h0))
	for i in 10:
		var s2 := _base()
		s2.charging = 0.5
		q.append(s2)
	var th := _base()
	th.throw = true
	th.throwPower = 0.8
	th.throwOther = side == "L"   # (the left click while winding up: the other hand)
	q.append(th)
	await _steps(60)
	return [picked, moved, w.holder == null and w.thrown_t > 0.0]

func _setup(lo: Dictionary) -> Array:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none"}, "headless": true, "seed": 3, "loadout": lo})
	var f: Fighter = m.me.f
	f.teleport(Vector3(5, 0, 0))
	var q := []
	m.me.drive = func(_e): return q.pop_front() if not q.is_empty() else _base()
	await _steps(60)
	return [m, f, q]

func test_a_weapon_off_the_sand_swings_and_throws() -> void:
	for side in ["R", "L"]:
		var s = await _setup({"main": "" if side == "R" else "gladius", "off": ""})
		var m: Match = s[0]
		var f: Fighter = s[1]
		var w := m.spawn_loose_weapon(Data.preset("longsword" if side == "R" else "dagger"), f.hand_world(side) + Vector3(0.3 * (1 if side == "R" else -1), -0.3, 0.3))
		await _steps(30)
		var g := _base()
		g.grab = true
		var r = await _try(m, f, w, side, s[2], g)
		t.check(r[0] and r[1] > 0.4 and r[2], "%s hand: picked up (%s), swung it %.2f m and threw it (%s)" % [side, r[0], r[1], r[2]])
		m.queue_free()
		await get_tree().process_frame

func test_a_thrown_frozen_or_stuck_weapon_is_as_good_as_new_in_the_hand() -> void:
	for kind in ["thrown", "frozen", "stuck"]:
		var s = await _setup({"main": "gladius", "off": ""})
		var m: Match = s[0]
		var f: Fighter = s[1]
		var w: Weapon
		if kind == "thrown":
			w = f.throw_weapon("R", f.torso.global_position + Vector3(0, 1, 6))
			await _steps(120)
		else:
			w = m.spawn_loose_weapon(Data.preset("gladius"), Vector3(5, 0.5, 2))
			f.release("R").global_position = Vector3(20, 0, 20)
			await _steps(30)
			if kind == "frozen":
				w.freeze = true
			else:
				# Stuck in a man standing a pace off: it stays in him until the hand pulls it out.
				var v = m.spawn_fighter({"kind": "bot", "name": "V", "loadout": {}, "team": 1, "pos": Vector3(5, 0, 0.75), "yaw": PI})
				v.erase("bot")
				v.drive = func(_e): return {}
				await _steps(30)
				w.global_position = f.hand_world("R") + Vector3(0.2, 0, 0.3)
				w.impale(v.f, v.f.torso, w.global_position)
				await _steps(20)
		if kind != "stuck":
			w.global_position = f.hand_world("R") + Vector3(0.3, -0.3, 0.3)
			w.linear_velocity = Vector3.ZERO
			await _steps(10)
		var g := _base()
		g.grab = true
		var r = await _try(m, f, w, "R", s[2], g)
		t.check(r[0] and r[1] > 0.4 and r[2] and not w.freeze, "%s: picked up (%s), swung %.2f m, thrown (%s), unfrozen (%s)" % [kind, r[0], r[1], r[2], not w.freeze])
		m.queue_free()
		await get_tree().process_frame

func test_g_with_the_button_down_takes_the_sword_when_nobody_is_in_reach() -> void:
	var s = await _setup({"main": "", "off": ""})
	var m: Match = s[0]
	var f: Fighter = s[1]
	var w := m.spawn_loose_weapon(Data.preset("gladius"), f.hand_world("R") + Vector3(0.3, -0.3, 0.3))
	await _steps(30)
	var g := _base()
	g.grab = true
	g.power = true
	g.grabHands = "R"
	var r = await _try(m, f, w, "R", s[2], g)
	t.check(r[0] and r[2], "the sword is in the right hand (%s) and thrown after (%s)" % [r[0], r[2]])
	m.queue_free()
