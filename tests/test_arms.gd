extends Node
## No limb passes into its own body (limp, down or dead too). Both arms are the same arm, mirrored: neither the hand, the forearm nor the elbow of either
## ever goes in through its own chest or head, wherever the mouse sends the hand.

var t

func _deepest(f: Fighter, sd: String, hp: Dictionary) -> Array:
	var worst := 0.0
	var where := ""
	for x in [-2.0, 0.0, 2.0]:
		for y in [-1.4, 0.2, 1.6]:
			hp.x = x if sd == "R" else -x
			hp.y = y
			for i in 45:
				await get_tree().physics_frame
			for k in 3:
				var pt: Vector3 = [f.hand_world(sd), f.arm[sd].fore.global_position, f.arm[sd].upper.global_transform * Vector3(0, -f.arm[sd].upper.half_ext.y, 0)][k]
				for body in [f.torso, f.head]:
					var l: Vector3 = body.global_transform.affine_inverse() * pt
					var pen: float = minf(body.half_ext.x - absf(l.x), minf(body.half_ext.y - absf(l.y), body.half_ext.z - absf(l.z)))
					if pen > worst:
						worst = pen
						where = "x %.0f y %.1f in the %s" % [x, y, body.part_name]
	return [worst, where]

func test_neither_arm_goes_through_the_body() -> void:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none"}, "headless": true, "seed": 3})
	for lo in [{"main": "gladius", "off": "roundShield"}, {"main": "gladius", "off": "dagger"}, {"main": "", "off": ""}]:
		var e = m.spawn_fighter({"kind": "bot", "name": "A", "loadout": lo, "team": 1, "pos": Vector3(5, 0, 0), "yaw": 0.0})
		e.erase("bot")
		var hp := {"x": 0.0, "y": 0.0}
		var side := ["R"]
		e.drive = func(_e): return {"main": hp if side[0] == "R" else {"x": 0.1, "y": 0.1}, "off": hp if side[0] == "L" else {"x": -0.35, "y": 0.1}, "power": true}
		var f: Fighter = e.f
		for i in 100:
			await get_tree().physics_frame
		for sd in ["R", "L"]:
			side[0] = sd
			var r: Array = await _deepest(f, sd, hp)
			t.check(r[0] < 0.04, "%s arm with %s stays out of the body (deepest %.3f m, %s)" % [sd, lo.get("off" if sd == "L" else "main") if lo.get("off" if sd == "L" else "main") != "" else "nothing", r[0], r[1]])
		m.entities.erase(e)
		m.combat.fighters.erase(f)
		f.queue_free()
		await get_tree().physics_frame
	m.queue_free()

func _worst_in_body(f: Fighter) -> float:
	var worst := 0.0
	for sd in ["R", "L"]:
		var pts := [f.arm[sd].upper.global_transform * Vector3(0, -f.arm[sd].upper.half_ext.y, 0)]
		if not f.arm[sd].fore.severed:
			pts.append_array([f.arm[sd].fore.global_position, f.hand_world(sd)])
		for pt in pts:
			for body in [f.torso, f.head]:
				if body.severed:
					continue
				var l: Vector3 = body.global_transform.affine_inverse() * pt
				worst = maxf(worst, minf(body.half_ext.x - absf(l.x), minf(body.half_ext.y - absf(l.y), body.half_ext.z - absf(l.z))))
	# The head and the legs: no part's middle inside the chest.
	for q in [f.head, f.by_name.shinL, f.by_name.shinR, f.by_name.thighL, f.by_name.thighR]:
		if q.severed:
			continue
		var l: Vector3 = f.torso.global_transform.affine_inverse() * q.global_position
		var th: Vector3 = f.torso.half_ext
		worst = maxf(worst, minf(th.x - absf(l.x), minf(th.y - absf(l.y), th.z - absf(l.z))))
	return worst

func test_limp_and_dead_arms_stay_out_of_the_body() -> void:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none"}, "headless": true, "seed": 3})
	var e = m.spawn_fighter({"kind": "bot", "name": "D", "loadout": {"main": "gladius", "off": "roundShield"}, "team": 1, "pos": Vector3(5, 0, 0), "yaw": 0.0})
	e.erase("bot")
	e.drive = func(_e): return {}
	var f: Fighter = e.f
	for i in 60:
		await get_tree().physics_frame
	f.fall(99.0, true)
	var worst := 0.0
	for i in 360:
		await get_tree().physics_frame
		if i > 30:
			worst = maxf(worst, _worst_in_body(f))
	t.check(worst < 0.05, "knocked down and limp, no limb lies inside the chest (deepest %.3f m)" % worst)
	f.blood = 0.0
	worst = 0.0
	for i in 360:
		await get_tree().physics_frame
		if i > 60:
			worst = maxf(worst, _worst_in_body(f))
	t.eq(f.state, "dead", "he bled out")
	t.check(worst < 0.05, "and dead, they still do (deepest %.3f m)" % worst)
	m.queue_free()

## J: the sword goes to the left hand and the shield to the right, both held at the palm, and
## back again; a two-handed grip refuses.
func test_weapons_swap_hands() -> void:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none"}, "headless": true, "seed": 3})
	var e = m.spawn_fighter({"kind": "bot", "name": "A", "loadout": {"main": "gladius", "off": "roundShield"}, "team": 1, "pos": Vector3(5, 0, 0), "yaw": 0.0})
	e.erase("bot")
	var inp := {"main": {"x": 0.2, "y": 0.2}, "off": {"x": -0.35, "y": 0.1}, "power": false}
	e.drive = func(_e): return inp
	var f: Fighter = e.f
	for i in 60:
		await get_tree().physics_frame
	var sword: Weapon = f.weapons.R
	var shield: Weapon = f.weapons.L
	inp.swap = true
	await get_tree().physics_frame
	inp.erase("swap")
	for i in 60:
		await get_tree().physics_frame
	t.check(f.weapons.L == sword and f.weapons.R == shield, "the sword is in the left hand and the shield in the right")
	t.check(sword.grip_world().distance_to(f.hand_world("L")) < 0.08 and sword.holder == f, "the sword is held at the left palm (%.3f m off)" % sword.grip_world().distance_to(f.hand_world("L")))
	t.check(f.swap_hands() and f.weapons.R == sword, "and back again")
	m.queue_free()

## H after a pickup: a weapon taken up in the right hand with a shield on the left arm goes
## two-handed (the shield is let fall); one taken up in the left hand alone crosses to the right
## and both hands take it.
func test_h_takes_a_picked_up_weapon_in_both_hands() -> void:
	for lo in [{"main": "", "off": "roundShield"}, {"main": "", "off": ""}]:
		var m := Match.new()
		add_child(m)
		m.setup({"mode": "training", "training": {"enemy": "none"}, "headless": true, "seed": 3, "loadout": lo})
		var f: Fighter = m.me.f
		var inp := {"main": {"x": 0.2, "y": 0.2}, "power": false}
		m.me.drive = func(_e): return inp
		for i in 60:
			await get_tree().physics_frame
		var shield: Weapon = f.weapons.L
		var side := "R" if shield else "L"
		var w: Weapon = m.spawn_loose_weapon(Data.preset("axe"), f.hand_world(side))
		t.check(f.pick_up(side, w), "the gladius is taken up in the %s hand" % side)
		for i in 10:
			await get_tree().physics_frame
		inp.grip = true
		await get_tree().physics_frame
		inp.erase("grip")
		for i in 30:
			await get_tree().physics_frame
		t.check(f.two_handed and f.weapons.R == w, "%s: H puts both hands on it" % ("with a shield" if shield else "from the left hand"))
		if shield:
			t.check(f.weapons.L == null and shield.holder == null, "the shield was let fall")
		m.queue_free()
		await get_tree().process_frame

## The wheel turns the edge: the blade rolls in the hand to whatever twist is set, half a turn
## included.
func test_wheel_turns_the_edge() -> void:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none"}, "headless": true, "seed": 3})
	var e = m.spawn_fighter({"kind": "bot", "name": "A", "loadout": {"main": "gladius", "off": ""}, "team": 1, "pos": Vector3(5, 0, 0), "yaw": 0.0})
	e.erase("bot")
	var inp := {"main": {"x": 0.4, "y": 0.4}, "off": {"x": -0.35, "y": 0.1}, "power": true, "twist": 0.0}
	e.drive = func(_e): return inp
	var f: Fighter = e.f
	for i in 100:
		await get_tree().physics_frame
	for tw in [1.6, 3.1, -1.6]:
		inp.twist = tw
		for i in 90:
			await get_tree().physics_frame
		var w: Weapon = f.weapons.R
		var q := PD.quat_of(w)
		var ax := q * Vector3.UP
		var want: Vector3 = (f.aim_q.R as Quaternion) * Vector3.RIGHT
		want -= ax * want.dot(ax)
		var off := rad_to_deg((q * Vector3.RIGHT).angle_to(want))
		t.check(off < 15.0, "twist %.1f: the edge is where the wheel set it (%.0f° off)" % [tw, off])
	m.queue_free()

## A blade hanging at the side and asked high across the body (and a two-handed one) goes up
## round by the front: it is not stuck pressing in through its own hips with the blade down.
func test_a_blade_comes_up_across_the_body_from_hanging() -> void:
	for wk in ["gladius", "axe", "longsword"]:
		var m := Match.new()
		add_child(m)
		m.setup({"mode": "training", "training": {"enemy": "none"}, "headless": true, "seed": 3, "loadout": {"main": wk, "off": ""}})
		var f: Fighter = m.me.f
		m.me.drive = func(_e): return {"main": {"x": -1.5, "y": 1.3}, "power": false, "look": {"yaw": 0.0, "pitch": -0.3}}
		for i in 240:
			await get_tree().physics_frame
		var up: float = (PD.quat_of(f.weapons.R) * Vector3.UP).y
		t.check(up > 0.3, "%s held high across the body points up (%.2f)" % [wk, up])
		m.queue_free()
		await get_tree().process_frame

## A thrust is a stab along the blade's own line: drawn back along it, then driven out along
## it, point first, the blade not turned off it, one hand or two.
func test_a_thrust_drives_straight_along_the_blade() -> void:
	for wk in ["gladius", "longsword"]:
		var m := Match.new()
		add_child(m)
		m.setup({"mode": "training", "training": {"enemy": "none"}, "headless": true, "seed": 3, "loadout": {"main": wk, "off": ""}})
		var f: Fighter = m.me.f
		var st := {"th": 0.0}
		m.me.drive = func(_e): return {"main": {"x": 0.1, "y": 0.8}, "power": true, "thrust": st.th, "look": {"yaw": 0.0, "pitch": -0.2}}
		for i in 150:
			await get_tree().physics_frame
		var w: Weapon = f.weapons.R
		var ax0: Vector3 = PD.quat_of(w) * Vector3.UP
		var tip := func() -> Vector3: return w.global_position + PD.quat_of(w) * Vector3(0, w.reach, 0) - f.torso.global_position
		var start: Vector3 = tip.call()
		var back := start
		var turn := 0.0
		st.th = 1.0
		for i in 60:
			await get_tree().physics_frame
			var p: Vector3 = tip.call()
			if (p - start).dot(ax0) < (back - start).dot(ax0):
				back = p
			turn = maxf(turn, rad_to_deg((PD.quat_of(w) * Vector3.UP).angle_to(ax0)))
		var drive: Vector3 = tip.call() - back
		t.check(drive.dot(ax0) > 0.15, "%s: the point is driven out along the blade (%.2f m)" % [wk, drive.dot(ax0)])
		t.check(rad_to_deg(drive.angle_to(ax0)) < (45.0 if f.two_handed else 35.0), "%s: straight along the blade (%.0f deg off)" % [wk, rad_to_deg(drive.angle_to(ax0))])
		t.check(turn < 25.0, "%s: the blade keeps its line (turned %.0f deg)" % [wk, turn])
		m.queue_free()
		await get_tree().process_frame

## A stab aimed across the body goes across: the feet step along the blade's line as it lies
## on the ground, not straight ahead, so the point (in the world, not just in his frame)
## travels where the blade points.
func test_a_thrust_across_the_body_steps_across() -> void:
	for wk in ["gladius", "spear"]:
		var m := Match.new()
		add_child(m)
		m.setup({"mode": "training", "training": {"enemy": "none"}, "headless": true, "seed": 3, "loadout": {"main": wk, "off": ""}})
		var f: Fighter = m.me.f
		var inp := {"main": {"x": 1.2, "y": 0.3}, "power": false}
		m.me.drive = func(_e): return inp
		for i in 150:
			await get_tree().physics_frame
		var w: Weapon = f.weapons.R
		var ax0: Vector3 = PD.quat_of(w) * Vector3.UP
		var tip := func() -> Vector3: return w.global_position + PD.quat_of(w) * Vector3(0, w.reach, 0)
		var body0 := f.torso.global_position
		var back: Vector3 = tip.call()
		var far := back
		inp.thrust = 1.0
		for i in 40:
			await get_tree().physics_frame
			var p: Vector3 = tip.call()
			if f.thrust_line.R != null and float(f.thrust_line.R.t) <= Fighter.THRUST_DRAW:
				back = p
				far = p
			elif (p - back).dot(ax0) > (far - back).dot(ax0):
				far = p
		var drive: Vector3 = far - back
		var step: Vector3 = f.torso.global_position - body0
		var side := Vector3(ax0.x, 0, ax0.z).normalized()
		t.check(drive.dot(ax0) > 0.2, "%s: the point goes out along the blade (%.2f m)" % [wk, drive.dot(ax0)])
		t.check(rad_to_deg(drive.angle_to(ax0)) < 25.0, "%s: in the world too (%.0f deg off)" % [wk, rad_to_deg(drive.angle_to(ax0))])
		t.check(Vector3(step.x, 0, step.z).dot(side) > 0.05, "%s: the feet step the way it points (%.2f m)" % [wk, Vector3(step.x, 0, step.z).dot(side)])
		m.queue_free()
		await get_tree().process_frame

## A wounded arm (red on the HUD) sags and wanders slowly; it does not buzz. A fast tremble on
## its mark had the hand and the blade shaking at more than a metre a second, standing still.
func test_a_wounded_arm_wanders_but_does_not_buzz() -> void:
	for hpv in [60.0, 30.0, -1.0]:
		var m := Match.new()
		add_child(m)
		m.setup({"mode": "training", "training": {"enemy": "none"}, "headless": true, "seed": 3, "loadout": {"main": "gladius", "off": ""}})
		var f: Fighter = m.me.f
		m.me.drive = func(_e): return {"main": {"x": 0.3, "y": 0.4}, "power": false}
		for i in 120:
			await get_tree().physics_frame
		if hpv < 0.0:
			f.arm.R.fore.fractured = true
		else:
			f.arm.R.upper.hp = hpv
			f.arm.R.fore.hp = hpv
		for i in 120:
			await get_tree().physics_frame
		var speed := 0.0
		var prev: Vector3 = f.hand_world("R") - f.torso.global_position
		for i in 240:
			await get_tree().physics_frame
			var h: Vector3 = f.hand_world("R") - f.torso.global_position
			speed += (h - prev).length() * 120.0 / 240.0
			prev = h
		t.check(speed < 0.4, "arm at %s: the hand wanders, it does not buzz (%.2f m/s)" % [hpv, speed])
		t.check(f.weapons.R != null, "arm at %s: the blade is still in the hand" % hpv)
		m.queue_free()
		await get_tree().process_frame

## Two fists need room on the haft: a short grip (a gladius, a dagger, a hammer) is not taken in
## two hands (H says so); a long one is, with the other hand at the far end of the grip, not
## crushed against the first. A design marked two-handed with too short a grip is held in one.
func test_a_short_grip_takes_one_hand() -> void:
	for wk in ["gladius", "dagger", "hammer", "axe", "mace"]:
		var m := Match.new()
		add_child(m)
		m.setup({"mode": "training", "training": {"enemy": "none"}, "headless": true, "seed": 3, "loadout": {"main": wk, "off": ""}})
		var f: Fighter = m.me.f
		for i in 30:
			await get_tree().physics_frame
		var r = f.toggle_grip()
		var long_grip: bool = wk == "axe" or wk == "mace"
		if long_grip:
			t.eq(r, "two", "%s: a long grip takes both hands" % wk)
			var w: Weapon = f.weapons.R
			t.check(w.grip_main.distance_to(w.grip_off) >= 0.115, "%s: the hands apart on it (%.2f m)" % [wk, w.grip_main.distance_to(w.grip_off)])
		else:
			t.eq(r, "short", "%s: too short a grip for two hands" % wk)
			t.check(not f.two_handed, "%s: still in one hand" % wk)
		m.queue_free()
		await get_tree().process_frame
	var stub := Data.preset("dagger").duplicate(true)
	stub.twoHanded = true
	var m2 := Match.new()
	add_child(m2)
	m2.setup({"mode": "training", "training": {"enemy": "none"}, "headless": true, "seed": 3, "loadout": {"main": stub, "off": ""}})
	t.check(not m2.me.f.two_handed, "a dagger marked two-handed is held in one hand")
	m2.queue_free()
	await get_tree().process_frame

## The weight of a weapon and where it lies tell in the hand: the same hammer with a lead head
## has its centre of mass further out, and the same sweep of the mouse swings it slower.
func test_a_heavy_head_moves_the_balance_and_swings_slower() -> void:
	var wood := Data.preset("hammer").duplicate(true)
	var lead := Data.preset("hammer").duplicate(true)
	for v in wood.voxels:
		v[3] = "wood"
	for v in lead.voxels:
		v[3] = "wood" if v[4] == "grip" else "lead"
	var ww := Weapon.new()
	ww.setup(wood)
	var wl := Weapon.new()
	wl.setup(lead)
	t.check(wl.mass > 4.0 * ww.mass, "lead is heavier (%.2f vs %.2f kg)" % [wl.mass, ww.mass])
	t.check((wl.center_of_mass - wl.grip_main).length() > (ww.center_of_mass - ww.grip_main).length() + 0.02, "the balance moves out to the head (%.2f vs %.2f m)" % [(wl.center_of_mass - wl.grip_main).length(), (ww.center_of_mass - ww.grip_main).length()])
	ww.free()
	wl.free()
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none"}, "headless": true, "seed": 3})
	m.me.f.teleport(Vector3(0, 0, -10))
	var peak := []
	for d in [wood, lead]:
		var e = m.spawn_fighter({"kind": "bot", "name": "S", "loadout": {"main": d, "off": ""}, "team": 1, "pos": Vector3(4.0 * peak.size(), 0.1, 0), "yaw": 0.0})
		e.erase("bot")
		var hp := {"x": 0.0, "y": 1.2}
		e.drive = func(_e): return {"main": hp, "power": true}
		var f: Fighter = e.f
		for i in 90:
			await get_tree().physics_frame
		hp.y = -1.2
		var sum := 0.0
		for i in 30:
			await get_tree().physics_frame
			var w: Weapon = f.weapons.R
			if w:
				sum += w.angular_velocity.length()
		peak.append(sum / 30.0)
	t.check(peak[1] < peak[0] * 0.9, "the lead-headed hammer comes down slower (mean %.1f vs %.1f rad/s)" % [peak[1], peak[0]])
	m.queue_free()

## The forearm's roll on its own length against the upper arm, in degrees (the twist part of
## the elbow's turn: its bend is about x, the forearm's length is y).
func _fore_twist(f: Fighter, side: String) -> float:
	var r: Quaternion = PD.quat_of(f.arm[side].upper).inverse() * PD.quat_of(f.arm[side].fore)
	return absf(rad_to_deg(wrapf(2.0 * atan2(r.y, r.w), -PI, PI)))

## Both hands on a war hammer through a long run of hard strokes every way: neither forearm winds
## itself round on its own length (the hands looked tangled), and the hammer still goes where it
## is sent at the end as at the start.
func test_two_hands_stay_untangled_through_a_long_bout() -> void:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none"}, "headless": true, "seed": 3, "loadout": {"main": "warhammer", "off": ""}})
	var f: Fighter = m.me.f
	var inp := {"main": {"x": 0.1, "y": 0.1}, "power": false}
	m.me.drive = func(_e): return inp
	for i in 90:
		await get_tree().physics_frame
	t.check(f.two_handed, "the war hammer in both hands")
	var worst := 0.0
	var marks := [Vector2(0, 1.5), Vector2(1.8, 0), Vector2(0, -1.5), Vector2(-1.8, 0), Vector2(1.1, 1.1), Vector2(-1.1, -1.1)]
	for k in 24:
		var d: Vector2 = marks[k % marks.size()]
		inp.power = true
		inp.main = {"x": d.x, "y": d.y}
		for i in 40:
			await get_tree().physics_frame
		inp.main = {"x": -d.x, "y": -d.y}
		for i in 40:
			await get_tree().physics_frame
		worst = maxf(worst, maxf(_fore_twist(f, "L"), _fore_twist(f, "R")))
	t.check(worst < 100.0, "neither forearm winds round (worst %.0f deg)" % worst)
	inp.power = false
	inp.main = {"x": 0.0, "y": 1.5}
	for i in 90:
		await get_tree().physics_frame
	var w: Weapon = f.weapons.R
	var err := rad_to_deg(PD.quat_of(w).angle_to(f.aim_q.R))
	t.check(err < 30.0, "and the hammer still goes up where it is sent (%.0f deg off)" % err)
	t.eq(f.state, "stand", "on his feet throughout")
	m.queue_free()
	await get_tree().process_frame

## Two hands on a haft go to every mark and stay there, the button down or not: a high guard with
## the hands at the brow in front of the face (not over the head), the trunk upright, and after
## fast strokes all round the blade is on the mouse within a second, never stuck short of it.
func test_two_handed_reaches_every_mark_and_never_sticks() -> void:
	for wk in ["longsword", "warhammer"]:
		var m := Match.new()
		add_child(m)
		m.setup({"mode": "training", "training": {"enemy": "none"}, "headless": true, "seed": 3, "loadout": {"main": wk, "off": ""}})
		var f: Fighter = m.me.f
		var box := {"i": {"main": {"x": 0.1, "y": 0.1}, "power": false}}
		m.me.drive = func(_e): return box.i
		for i in 90:
			await get_tree().physics_frame
		box.i = {"main": {"x": 0.0, "y": 1.6}, "power": true}
		for i in 150:
			await get_tree().physics_frame
		var w: Weapon = f.weapons.R
		var hi_err := rad_to_deg(PD.quat_of(w).angle_to(f.aim_q.R))
		var yq := Quaternion(Vector3.UP, f.yaw).inverse()
		var sh_r: Vector3 = f.torso.global_position + f.torso.global_transform.basis.get_rotation_quaternion() * f.shoulder.R
		var high: Vector3 = yq * (f.hand_world("R") - sh_r)
		t.check(hi_err < 25.0, "%s: a high guard with the button down stands the blade up (%.0f deg off)" % [wk, hi_err])
		# Both hands go where the mouse sends them, as one hand does: aimed right up they rise
		# over the head, not held at the brow with the blade standing up out of the fists
		# (user video: the hands never left the face and the arms looked tangled).
		t.check(high.y > 0.35, "%s: aimed right up, the hands rise over the head (%.2f above the shoulder)" % [wk, high.y])
		var worst := 0.0
		var tilt := 0.0
		var lo := Vector3.INF
		var hi := -Vector3.INF
		var marks := [Vector2(0, 1.6), Vector2(0, -1.5), Vector2(1.8, 0.4), Vector2(-1.8, 0.4), Vector2(1.1, 1.3), Vector2(-1.2, -1.2), Vector2(-1.1, 1.3), Vector2(1.2, -1.2)]
		for d in marks:
			box.i = {"main": {"x": d.x, "y": d.y}, "power": true}
			# (On the mouse within a second: the nearest the blade comes over the last sixth of
			# it, not the one frame at the second; the blade settles on the mark with a little
			# sway, and the one frame read 34 deg or 20 by which tests had run before.)
			var near := 999.0
			for i in 120:
				await get_tree().physics_frame
				if i >= 80 and d.y > -0.5:   # (settled at the mark; bent over a low one by design)
					tilt = maxf(tilt, rad_to_deg(f.torso.global_transform.basis.y.angle_to(Vector3.UP)))
				if i >= 100:
					near = minf(near, rad_to_deg(PD.quat_of(f.weapons.R).angle_to(f.aim_q.R)))
			worst = maxf(worst, near)
			sh_r = f.torso.global_position + f.torso.global_transform.basis.get_rotation_quaternion() * f.shoulder.R
			var h: Vector3 = Quaternion(Vector3.UP, f.yaw).inverse() * (f.hand_world("R") - sh_r)
			lo = lo.min(h)
			hi = hi.max(h)
		# (Thirty-five: one second after a fast stroke the blade still sways a little on its mark,
		# and which way it is caught depends on what ran before; held three seconds it is on the
		# mouse within twenty-five, the test below.)
		t.check(worst < 35.0, "%s: after each fast stroke the blade is on the mouse within a second (worst %.0f deg)" % [wk, worst])
		t.check(tilt < 25.0, "%s: the trunk stays upright through the strokes (leans at most %.0f deg)" % [wk, tilt])
		# The main hand sweeps as wide and as high in two hands as in one (one hand: 1.3 m across,
		# 1.1 m up and down over these marks).
		t.check(hi.x - lo.x > 0.9 and hi.y - lo.y > 0.9, "%s: the hands range as wide as one hand's (%.2f m across, %.2f m up and down)" % [wk, hi.x - lo.x, hi.y - lo.y])
		t.eq(f.state, "stand", "%s: on his feet throughout" % wk)
		m.queue_free()
		await get_tree().process_frame

## Both hands on a longsword held still at a guard: the blade stays on the mouse, it does not
## wander off while held (it used to tilt 30 degrees off a high guard in two seconds and
## settle 34 off a low one, the edge being rolled round to the frame's while the arms held).
func test_two_hands_hold_a_guard_without_drifting() -> void:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none"}, "headless": true, "seed": 3, "loadout": {"main": "longsword", "off": ""}})
	var f: Fighter = m.me.f
	var box := {"i": {"main": {"x": 0.1, "y": 0.1}, "power": false}}
	m.me.drive = func(_e): return box.i
	for i in 90:
		await get_tree().physics_frame
	for d in [Vector2(0.0, 1.6), Vector2(1.8, 0.4), Vector2(1.2, -1.2), Vector2(-1.8, 0.4)]:
		box.i = {"main": {"x": d.x, "y": d.y}, "power": true}
		var near := 999.0
		for i in 360:
			await get_tree().physics_frame
			if i >= 340:
				near = minf(near, rad_to_deg(PD.quat_of(f.weapons.R).angle_to(f.aim_q.R)))
		t.check(near < 25.0, "held three seconds at (%.1f, %.1f) the blade is still on the mouse (%.0f deg off)" % [d.x, d.y, near])
	m.queue_free()

## Nothing touched, the blade stays where it was aimed: a ringing head or wine had the hand going
## round in circles on its own (user: the weapon turned with the hands in a circle instead of
## staying where it was last aimed; 4 m of travel in eight seconds, circles 0.4 m across).
func test_a_dazed_or_drunk_mans_blade_holds_still() -> void:
	for cond in ["drunk", "concussed"]:
		var m := Match.new()
		add_child(m)
		m.setup({"mode": "training", "training": {"enemy": "none"}, "decrees": [], "hazards": [], "headless": true, "seed": 3, "loadout": {"main": "hammer", "off": ""}})
		var f: Fighter = m.me.f
		m.me.drive = func(_e): return {"main": {"x": 0.1, "y": 0.15}, "power": false}
		for i in 240:
			await get_tree().physics_frame
			if cond == "drunk":
				f.mods.drunk = 0.6
			else:
				f.concussion = 0.6
		var w: Weapon = f.weapons.R
		var lo := Vector3(INF, INF, INF)
		var hi := -lo
		for i in 480:
			await get_tree().physics_frame
			if cond == "concussed":
				f.concussion = 0.6
			var tip: Vector3 = w.global_transform * Vector3(0, w.reach, 0)
			lo = lo.min(tip)
			hi = hi.max(tip)
		var spread := (hi - lo).length()
		t.check(spread < 0.08, "%s: the blade holds its place (%.2f m across in four seconds)" % [cond, spread])
		m.queue_free()
		await get_tree().process_frame

## A blade pressed into a man's head, the head cut round it, and then pulled hard the other way
## comes out with the hand (user: the sword went into a head and stuck there; an axe stayed in
## two times in six before).
func test_a_blade_pulled_out_of_a_head_comes_free() -> void:
	for mark in [Vector2(-0.4, 0.6), Vector2(0.4, 0.9)]:
		var m := Match.new()
		add_child(m)
		m.setup({"mode": "training", "training": {"enemy": "none"}, "decrees": [], "hazards": [], "headless": true, "seed": 3, "loadout": {"main": "axe", "off": ""}})
		var f: Fighter = m.me.f
		f.teleport(Vector3(0, 0, 0))
		var e = m.spawn_fighter({"kind": "bot", "name": "V", "loadout": {}, "team": 1, "pos": Vector3(0, 0.1, 0.85), "yaw": PI})
		e.erase("bot")
		e.drive = func(_e): return {}
		e.f.mods.toughness = 20.0
		var inp := [{"main": {"x": 0.1, "y": 0.2}, "power": false}]
		m.me.drive = func(_e): return inp[0]
		for i in 120:
			await get_tree().physics_frame
		inp[0] = {"main": {"x": mark.x, "y": mark.y}, "power": true}
		for i in 180:
			await get_tree().physics_frame
			e.f.blood = 100.0
			e.f.head.hp = maxf(e.f.head.hp, 50.0)
		var w: Weapon = f.weapons.R
		var hp: VoxelPart = e.f.head
		var gone := hp.voxels_within(hp.global_transform.affine_inverse() * (w.global_transform * Vector3(0, w.reach * 0.8, 0)), 0.06)
		if not gone.is_empty():
			hp.remove_voxels(Array(gone))
		inp[0] = {"main": {"x": -0.9, "y": -0.3}, "power": true}
		for i in 120:
			await get_tree().physics_frame
		t.check(not w.get_colliding_bodies().has(hp), "%s: the axe is out of the head a second after the pull" % mark)
		t.check(f.weapons.R == w, "%s: and still in his hand" % mark)
		m.queue_free()
		await get_tree().process_frame
