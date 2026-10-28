extends Node
## Taking a weapon up off the sand, the ways it happens in a bout: the hand that took it swings
## it, and can throw it, whatever state it lay there in (thrown, a dead man's, frozen for a
## guest, stuck in a body), and G with the button held near a sword takes the sword.
## And it is taken up by the hand itself (user: no weapon ever jumps into a hand): G sends the
## hand to the grip where the weapon lies, he stoops for one on the sand, the fingers close on
## it and the wrist turns it into line; it is held only then, and it never jumps on the way.
## A heavy blade driven hard into a body stays in the wound until it is wrenched out (dragging
## the man it is in) or let go of; taken hold of where it is stuck, it stays stuck till then.

var t

func _steps(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func _base() -> Dictionary:
	return {"main": {"x": 0.2, "y": 0.2}, "off": {"x": -0.35, "y": 0.1}, "power": false, "look": {"yaw": 0.0, "pitch": 0.0}, "mx": 0.0, "mz": 0.0}

## The player's own path (social.gd): G, then a swing, then F. Returns [picked, hand travel, thrown].
## (The hand goes to it and takes it: the swing waits until it has it. One stuck in a body is
## pulled on until it comes out.)
func _try(m: Match, f: Fighter, w: Weapon, side: String, q: Array, grab: Dictionary) -> Array:
	q.append(grab)
	for i in 420:
		await get_tree().physics_frame
		if f.weapons[side] == w and w.stuck == null:
			break
		if f.lodged_side() != "":
			var pull := _base()
			pull.main = {"x": -1.0, "y": -0.6}
			pull.mz = -0.6
			q.append(pull)
	await _steps(10)
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

func _match() -> Match:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none"}, "headless": true, "seed": 3})
	return m

func _bare(m: Match, pos: Vector3, yaw: float, loadout := {}) -> Fighter:
	var e = m.spawn_fighter({"kind": "bot", "name": "P", "loadout": loadout, "team": 0, "pos": pos, "yaw": yaw})
	e.erase("bot")
	e.drive = func(_e): return {}
	return e.f

## Steps until the hand on `side` holds `w` (or `n` steps): the most the grip moved in one step
## before it was held, how near the palm it was when the fingers closed, and when it was held.
func _watch(f: Fighter, w: Weapon, side: String, n: int) -> Dictionary:
	var out := {"jump": 0.0, "closed_d": -1.0, "turn": 180.0, "held_at": -1, "stood": true, "phases": [], "low": INF}
	var was: Vector3 = w.grip_world()
	for i in n:
		await get_tree().physics_frame
		var g: Vector3 = w.grip_world()
		if out.held_at < 0:
			out.jump = maxf(out.jump, g.distance_to(was))
		if f.weapons[side] == w and out.held_at < 0:
			out.held_at = i
		elif out.held_at < 0:
			out.closed_d = f.hand_world(side).distance_to(g)   # (the last step before it is held)
			out.turn = rad_to_deg(PD.quat_of(w).angle_to(PD.quat_of(f.arm[side].fore) * Fighter.grip_q(w)))
		was = g
		out.low = minf(out.low, f.hand_world(side).y)
		var r = f.reach[side]
		var ph: String = r.phase if r != null else ("held" if f.weapons[side] == w else "none")
		if out.phases.is_empty() or out.phases[-1] != ph:
			out.phases.append(ph)
		if f.state != "stand":
			out.stood = false
		if out.held_at >= 0 and i > out.held_at + 30:
			break
	return out

func test_a_weapon_on_the_sand_is_reached_for_and_taken_by_hand() -> void:
	var m := _match()
	var f := _bare(m, Vector3(0, 0, 4), 0.0)
	await _steps(60)
	var fwd := Vector3(sin(f.yaw), 0, cos(f.yaw))
	var right := Vector3(cos(f.yaw), 0, -sin(f.yaw))
	var w := m.spawn_loose_weapon(Data.preset("gladius"), f.torso.global_position * Vector3(1, 0, 1) + fwd * 0.45 - right * 0.15 + Vector3(0, 0.1, 0))
	await _steps(60)
	var got := f.grab_nearest(m.combat.loose_weapons)
	t.eq(got, w, "G picks the gladius out")
	t.check(f.weapons.R == null and f.weapons.L == null, "but no hand has it yet: it is only reached for")
	var side := "R" if f.reach.R != null else "L"
	var o: Dictionary = await _watch(f, w, side, 480)
	t.check(o.held_at > 20, "the hand takes it after going to it (held after %d steps; %s)" % [o.held_at, o.phases])
	t.check(o.low < 0.25, "down to it on the sand (the hand as low as %.2f m)" % o.low)
	t.check(o.jump < 0.06, "it never jumps on the way: at most %.3f m in a step" % o.jump)
	t.check(o.closed_d >= 0.0 and o.closed_d < 0.02 and o.turn < 10.0, "gripped only once it is in the palm (%.3f m off) and in line (%.1f deg)" % [o.closed_d, o.turn])
	t.check(o.stood, "he stoops for it and stays on his feet")
	t.check(f.weapons[side] == w and w.holder == f, "and holds it at the end")
	m.queue_free()

func test_out_of_reach_the_hand_gives_up() -> void:
	var m := _match()
	var f := _bare(m, Vector3(0, 0, 4), 0.0)
	await _steps(60)
	var fwd := Vector3(sin(f.yaw), 0, cos(f.yaw))
	var w := m.spawn_loose_weapon(Data.preset("gladius"), f.torso.global_position * Vector3(1, 0, 1) + fwd * 0.6 + Vector3(0, 0.1, 0))
	await _steps(30)
	f.grab_nearest(m.combat.loose_weapons)
	# Taken away as he reaches (nothing walks him after it): out of his reach.
	w.freeze = true
	w.global_position = f.torso.global_position * Vector3(1, 0, 1) + fwd * 1.8 + Vector3(0, 0.1, 0)
	await _steps(int(Fighter.REACH_T * 120.0) + 30)
	t.check(f.reach.R == null and f.reach.L == null, "the reach is given up after a while")
	t.check(f.weapons.R == null and f.weapons.L == null and w.holder == null, "and the weapon stays where it lies")
	m.queue_free()

## (A blade put into the man in front, where a blow would leave it: at his chest, nearest it.)
func _lodge(f: Fighter, v: Fighter, need := 0.6) -> Weapon:
	var w: Weapon = f.weapons.R
	var tip := w.global_position + PD.quat_of(w) * Vector3(0, w.reach * 0.9, 0)
	var at: Vector3 = v.torso.global_transform * (v.torso.global_transform.affine_inverse() * tip).clamp(-v.torso.half_ext, v.torso.half_ext)
	w.lodge_in(v, v.torso, at, need)
	return w

func _pair(m: Match, loadout: Dictionary) -> Array:
	var f := _bare(m, Vector3(0, 0, 4), 0.0, loadout)
	await _steps(60)
	var fwd := Vector3(sin(f.yaw), 0, cos(f.yaw))
	var e = m.spawn_fighter({"kind": "bot", "name": "V", "loadout": {}, "team": 1, "pos": f.torso.global_position * Vector3(1, 0, 1) + fwd * 0.95, "yaw": f.yaw + PI})
	e.erase("bot")
	e.drive = func(_e): return {}
	await _steps(60)
	return [f, e.f, m.entity_of(f)]

func test_a_blade_left_in_a_man_is_wrenched_out_and_drags_him() -> void:
	var m := _match()
	var pr = await _pair(m, {"main": "axe"})
	var f: Fighter = pr[0]
	var v: Fighter = pr[1]
	var said := []
	f.lodged.connect(func(_f, _w, what, _at): said.append(what))
	var w := _lodge(f, v, 1.2)   # (deep in, at the hardest a blow leaves it)
	await _steps(3)
	t.check(w.stuck != null and f.weapons.R == w and f.lodged_side() == "R", "the axe stays in him, still in the hand that struck")
	t.eq(said, ["in"], "and the match is told it went in")
	# Pulling back on it, stepping away: he comes with it until it tears out.
	var p0: Vector3 = v.torso.global_position
	var dragged := 0.0
	var back := -Vector3(sin(f.yaw), 0, cos(f.yaw))
	pr[2].drive = func(_e): return {"mz": -1.0, "main": {"x": 0.0, "y": -0.9}}
	for i in 400:
		await get_tree().physics_frame
		dragged = maxf(dragged, (v.torso.global_position - p0).dot(back))
		if w.stuck == null:
			break
	t.check(w.stuck == null and f.weapons.R == w, "it comes out at last, still in his hand")
	t.check(dragged > 0.08, "dragging the man with it till then (%.2f m)" % dragged)
	t.check(said.has("free"), "and its coming out is told too (%s)" % [said])
	m.queue_free()

func test_let_go_it_stays_in_him_and_is_taken_back_only_by_hand() -> void:
	var m := _match()
	var pr = await _pair(m, {"main": "axe"})
	var f: Fighter = pr[0]
	var v: Fighter = pr[1]
	var w := _lodge(f, v)
	await _steps(3)
	var q := [{"grab": true}]
	pr[2].drive = func(_e): return q.pop_front() if not q.is_empty() else {}
	await _steps(5)
	t.check(f.weapons.R == null and w.holder == null and w.stuck != null, "G lets go of it: it stays in him")
	await _steps(30)
	var at0 := w.global_position - v.torso.global_position
	q.append({"grab": true})
	var closed := false
	var moved := 0.0
	for i in 240:
		await get_tree().physics_frame
		moved = maxf(moved, (w.global_position - v.torso.global_position).distance_to(at0))
		if f.lodged_side() == "R":
			closed = true
			break
	t.check(closed, "G again: the hand goes to its grip and closes on it where it is")
	t.check(w.stuck != null and f.weapons.R == null, "it is still in him: the hand has it, but it has not come out")
	t.check(moved < 0.05, "nor did it move in him to meet the hand (%.3f m)" % moved)
	pr[2].drive = func(_e): return {"mz": -1.0, "main": {"x": 0.0, "y": -0.9}}
	for i in 600:
		await get_tree().physics_frame
		if f.weapons.R == w:
			break
	t.check(f.weapons.R == w and w.stuck == null, "pulled on, it tears out and is his again")
	m.queue_free()

func test_only_a_heavy_keen_blade_hit_hard_stays_in() -> void:
	var m := _match()
	var axe := m.spawn_loose_weapon(Data.preset("axe"), Vector3(0, 0.3, 0))
	var dagger := m.spawn_loose_weapon(Data.preset("dagger"), Vector3(1, 0.3, 0))
	var mace := m.spawn_loose_weapon(Data.preset("mace"), Vector3(2, 0.3, 0))
	t.eq(Combat.lodge_chance(dagger, "edge", 60.0, 0.0, {}), 0.0, "a dagger never stays in")
	t.eq(Combat.lodge_chance(mace, "blunt", 60.0, 0.0, {}), 0.0, "nor a mace")
	t.eq(Combat.lodge_chance(axe, "edge", 15.0, 0.0, {}), 0.0, "nor an axe's light blow")
	var hard := Combat.lodge_chance(axe, "edge", 50.0, 0.0, {})
	t.check(hard > 0.1 and hard < 0.7, "an axe's hard chop now and then (%.2f)" % hard)
	t.check(Combat.lodge_chance(axe, "edge", 50.0, 0.0, {"bone": true}) > hard, "likelier where it meets bone")
	var sword := m.spawn_loose_weapon(Data.preset("gladius"), Vector3(3, 0.3, 0))
	t.eq(Combat.lodge_chance(sword, "edge", 50.0, 0.0, {}), 0.0, "a sword's cut slides out of the wound it made")
	m.queue_free()

func test_a_bot_hauls_on_a_stuck_blade_or_lets_it_go() -> void:
	var m := _match()
	var e = m.spawn_fighter({"kind": "bot", "name": "B", "loadout": {"main": "axe"}, "team": 1, "pos": Vector3(0, 0, 4), "yaw": 0.0})
	await _steps(60)
	var f: Fighter = e.f
	var fwd := Vector3(sin(f.yaw), 0, cos(f.yaw))
	var d = m.spawn_fighter({"kind": "bot", "name": "D", "loadout": {}, "team": 0, "pos": f.torso.global_position * Vector3(1, 0, 1) + fwd * 0.95, "yaw": f.yaw + PI})
	d.erase("bot")
	d.drive = func(_e): return {}
	await _steps(30)
	var w := _lodge(f, d.f)
	await _steps(3)
	var stuck_for := 0
	for i in 480:
		await get_tree().physics_frame
		if f.lodged_side() == "":
			break
		stuck_for += 1
	t.check(stuck_for < 400, "the bot does not stand there holding it: freed or let go in %.1f s" % (stuck_for / 120.0))
	t.check(f.weapons.R == w or (f.weapons.R == null and w.stuck != null), "either it came out in his hand or it is left in the man")
	m.queue_free()
