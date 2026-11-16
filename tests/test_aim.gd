extends Node
## The mouse and the blade (user, a video: raised over his head, the weapon answered nothing to
## the mouse pulled left or right, and stuck there). A hand's mark stays on a round pane and slides
## along its rim (PlayerInput.slide); the blade lies the way the mark lies from the pane's middle
## (Fighter.aim_dir): whichever way the mouse goes, and wherever the blade stands, its point goes
## that way.

var t

func _steps(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

## How far out on the pane a mark is: 1 at the rim.
static func _out(h: Dictionary) -> float:
	return Vector2(float(h.x) / Fighter.PANE.x, float(h.y) / Fighter.PANE.y).length()

func test_the_mark_stays_on_a_round_pane_and_slides_along_its_rim() -> void:
	var h := {"x": 0.1, "y": 0.15}
	PlayerInput.slide(h, Vector2(0.5, -0.3))
	t.check(absf(float(h.x) - 0.6) < 1e-6 and absf(float(h.y) + 0.15) < 1e-6, "inside the pane the mark goes with the mouse, exactly")
	h = {"x": 0.0, "y": 0.0}
	for i in 100:
		PlayerInput.slide(h, Vector2(0, 0.05))
	t.check(absf(float(h.x)) < 1e-6 and absf(float(h.y) - Fighter.PANE.y) < 1e-6, "pushed up and on, it stops at the pane's top (%.2f, %.2f)" % [h.x, h.y])
	# Pulled left from the top it goes round the rim, down to the left, and never stands still.
	var stuck := 0
	var off_rim := 0.0
	for i in 40:
		var was := Vector2(float(h.x), float(h.y))
		PlayerInput.slide(h, Vector2(-0.05, 0.0))
		if float(h.x) > was.x - 0.005 or float(h.y) > was.y + 1e-9:
			stuck += 1
		off_rim = maxf(off_rim, absf(_out(h) - 1.0))
	t.eq(stuck, 0, "pulled left from the top, every bit of the pull takes it on to the left and down")
	t.check(off_rim < 1e-6, "along the rim all the way")
	t.check(float(h.x) < -1.2 and float(h.y) < 1.3, "two units of pull bring it well round to the left (%.2f, %.2f)" % [h.x, h.y])
	# And up again from the left end, pulled up.
	h = {"x": -Fighter.PANE.x, "y": 0.0}
	for i in 40:
		PlayerInput.slide(h, Vector2(0.0, 0.05))
	t.check(float(h.y) > 1.1 and float(h.x) > -1.7, "from the left end, pulled up, it goes up round the rim (%.2f, %.2f)" % [h.x, h.y])
	# Wherever the mouse wanders, the mark is on the pane.
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var worst := 0.0
	for i in 4000:
		PlayerInput.slide(h, Vector2(rng.randf_range(-0.4, 0.4), rng.randf_range(-0.4, 0.4)))
		worst = maxf(worst, _out(h))
	t.check(worst <= 1.0 + 1e-6, "never off the pane, however the mouse wanders (%.4f)" % worst)

func test_a_mark_lays_the_blade_the_way_it_lies_from_the_middle() -> void:
	var near := func(a: Vector3, b: Vector3) -> bool: return a.distance_to(b) < 1e-4
	t.check(near.call(Fighter.aim_dir(0, 0), Vector3(0, 0, 1)), "at the pane's middle: straight ahead")
	t.check(near.call(Fighter.aim_dir(0, 1.6), Vector3(0, 1, 0)), "at its top: straight up")
	t.check(near.call(Fighter.aim_dir(0, -1.6), Vector3(0, -1, 0)), "at its foot: straight down")
	t.check(near.call(Fighter.aim_dir(2, 0), Vector3(-1, 0, 0)), "at its right end: level, out to his right")
	t.check(near.call(Fighter.aim_dir(-2, 0), Vector3(1, 0, 0)), "at its left end: level, out to his left")
	t.check(near.call(Fighter.aim_dir(1, 0), Vector3(-sin(PI / 4.0), 0, cos(PI / 4.0))), "half way out: half a right angle that way")
	# Along the rim between its ends: every way between, across him (a clock's hand seen from behind).
	var rim_bad := 0
	for k in 64:
		var a := TAU * k / 64.0
		var d := Fighter.aim_dir(-sin(a) * 2.0, cos(a) * 1.6)
		var want := Vector2(sin(a) * 2.0, cos(a) * 1.6).normalized()
		if absf(d.z) > 1e-4 or Vector2(d.x, d.y).distance_to(want) > 1e-4:
			rim_bad += 1
	t.eq(rim_bad, 0, "round the rim the blade lies across him, the way the mark lies from the middle")
	# No place on the pane where the mouse moved does nothing: a tenth of a unit, any of eight
	# ways, turns the blade by a few degrees at least, unless it pushes straight out at the rim.
	var dead := []
	var least := 999.0
	for iy in range(-8, 9):
		for ix in range(-10, 11):
			var m := Vector2(ix * 0.2, iy * 0.2)
			var h0 := {"x": m.x, "y": m.y}
			PlayerInput.slide(h0, Vector2.ZERO)
			var d0 := Fighter.aim_dir(float(h0.x), float(h0.y))
			for k in 8:
				var way := Vector2(cos(TAU * k / 8.0), sin(TAU * k / 8.0))
				var h1: Dictionary = h0.duplicate()
				PlayerInput.slide(h1, way * 0.1)
				var turn := rad_to_deg(d0.angle_to(Fighter.aim_dir(float(h1.x), float(h1.y))))
				# (Straight out at the rim, or nearly: nothing more that way.)
				var outward := Vector2(float(h0.x) / 4.0, float(h0.y) / 2.56).normalized().dot(way) if _out(h0) > 0.999 else -1.0
				if outward > 0.7:
					continue
				least = minf(least, turn)
				if turn < 1.0:
					dead.append("(%.1f, %.1f) %d" % [m.x, m.y, k])
	t.check(dead.is_empty(), "everywhere on the pane the mouse moved a tenth turns the blade (least %.1f deg; dead: %s)" % [least, str(dead.slice(0, 6))])
	# And it turns it the way the mouse went: from the top, pulled left, the point goes to his left.
	var hl := {"x": 0.0, "y": 1.6}
	PlayerInput.slide(hl, Vector2(-0.5, 0.0))
	var dl := Fighter.aim_dir(float(hl.x), float(hl.y))
	t.check(dl.x > 0.2 and dl.y > 0.9 and absf(dl.z) < 1e-4, "raised, the mouse pulled left half a unit: the blade leans to his left (%.2f, %.2f, %.2f)" % [dl.x, dl.y, dl.z])

## The mark sent up past the pane's top (the mouse shoved up, as a man raises his weapon), then
## pulled `pull` (pane units a step, `n` steps), then held: the blade in his own frame (+x his left).
func _raise_and_pull(m, f: Fighter, box: Dictionary, pull: Vector2, n: int) -> Vector3:
	var h := {"x": 0.1, "y": 0.15}
	box.i = {"main": h.duplicate(), "power": false}
	await _steps(60)
	for i in 60:
		PlayerInput.slide(h, Vector2(0, 0.05))
		box.i = {"main": h.duplicate(), "power": true}
		await get_tree().physics_frame
	await _steps(110)
	for i in n:
		PlayerInput.slide(h, pull)
		box.i = {"main": h.duplicate(), "power": true}
		await get_tree().physics_frame
	await _steps(110)
	var w: Weapon = f.weapons[f.two_side]
	return Quaternion(Vector3.UP, f.yaw).inverse() * (PD.quat_of(w) * Vector3.UP)

func test_a_raised_weapon_pulled_left_or_right_comes_down_that_way() -> void:
	for wk in ["warhammer", "gladius"]:
		var m := Match.new()
		add_child(m)
		m.setup({"mode": "training", "training": {"enemy": "none"}, "headless": true, "seed": 3, "decrees": [], "hazards": [], "loadout": {"main": wk, "off": ""}})
		var f: Fighter = m.me.f
		var box := {"i": {"main": {"x": 0.1, "y": 0.15}, "power": false}}
		m.me.drive = func(_e): return box.i
		await _steps(90)
		var up: Vector3 = await _raise_and_pull(m, f, box, Vector2.ZERO, 1)
		t.check(up.y > 0.93, "%s: the mouse shoved up, the weapon stands over his head (%.2f, %.2f, %.2f)" % [wk, up.x, up.y, up.z])
		# (Two units of the pane: a hand's breadth of the mouse.)
		var left: Vector3 = await _raise_and_pull(m, f, box, Vector2(-0.05, 0.0), 40)
		t.check(left.x > 0.6 and rad_to_deg(up.angle_to(left)) > 40.0, "%s: raised and pulled left, it comes down to his left (%.2f, %.2f, %.2f: %.0f deg)" % [wk, left.x, left.y, left.z, rad_to_deg(up.angle_to(left))])
		var right: Vector3 = await _raise_and_pull(m, f, box, Vector2(0.05, 0.0), 40)
		t.check(right.x < -0.6 and rad_to_deg(up.angle_to(right)) > 40.0, "%s: raised and pulled right, it comes down to his right (%.2f, %.2f, %.2f: %.0f deg)" % [wk, right.x, right.y, right.z, rad_to_deg(up.angle_to(right))])
		# Pulled on round, it lies level out to the side: a clock's hand from twelve to nine.
		var round_l: Vector3 = await _raise_and_pull(m, f, box, Vector2(-0.05, -0.025), 60)
		t.check(round_l.x > 0.9 and absf(round_l.y) < 0.35, "%s: pulled on round to the left, it lies out level to his left (%.2f, %.2f, %.2f)" % [wk, round_l.x, round_l.y, round_l.z])
		t.eq(f.state, "stand", "%s: on his feet throughout" % wk)
		m.queue_free()
		await get_tree().process_frame

## A blade asked lower than the sand lets it go: along the sand its point still goes left and right
## with the mouse, a little for a little (kept on its heading, it swung a quarter turn round for a
## finger's breadth of the mouse at the pane's foot).
func test_a_low_blade_goes_along_the_sand_with_the_mouse() -> void:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none"}, "headless": true, "seed": 3, "decrees": [], "hazards": [], "loadout": {"main": "longsword", "off": ""}})
	var f: Fighter = m.me.f
	var box := {"i": {"main": {"x": 0.1, "y": 0.15}, "power": false}}
	m.me.drive = func(_e): return box.i
	await _steps(90)
	var yq := Quaternion(Vector3.UP, f.yaw).inverse()
	var heading := func(mark: Vector2) -> float:
		box.i = {"main": {"x": mark.x, "y": mark.y}, "power": true}
		await _steps(170)
		var b: Vector3 = yq * (PD.quat_of(f.weapons.R) * Vector3.UP)
		return rad_to_deg(atan2(b.x, b.z))
	var mid: float = await heading.call(Vector2(0.0, -1.6))
	var l: float = await heading.call(Vector2(-0.3, -1.55))
	var r: float = await heading.call(Vector2(0.3, -1.55))
	t.check(absf(mid) < 12.0, "at the pane's foot the point lies ahead of him on the sand (heading %.0f deg)" % mid)
	t.check(l > 3.0 and l < 30.0, "a little to the left of it, a little to his left (%.0f deg)" % l)
	t.check(r < -3.0 and r > -30.0, "a little to the right, a little to his right (%.0f deg)" % r)
	m.queue_free()
