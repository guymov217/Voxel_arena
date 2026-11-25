extends Node
## What a heap of the dead costs a step (a hundred contacts, each seen from both sides and noted twice) is not paid: the parts of two
## fallen men against each other note no touch (Combat.report: nobody asks who touched whom among the dead, and a blow wants a living
## hand), while the living pressed on one another are noted as they ever were. (A living man and a fallen one do not touch at all: a corpse
## is on a layer of its own, the sand's, the weapons' and its own kind's.)

var t

func _put_down(f: Fighter) -> void:
	f.set("spared", true)   # (no death's door: dead)
	f.die("test")

## Three men standing apart, each as he is put (nobody fights: they are not told to).
func _men() -> Array:
	# The last test's match is let go first: freed only at the end of the frame, its bodies stood where this one's men are made.
	await get_tree().physics_frame
	await get_tree().physics_frame
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none", "respawn": false}, "headless": true, "seed": 5, "decrees": [], "hazards": []})
	m.me.f.teleport(Vector3(0, 0, -14))
	var men := []
	for i in 3:
		var e = m.spawn_fighter({"kind": "bot", "name": "D%d" % i, "loadout": {"main": "gladius"}, "team": 0, "pos": Vector3(3.0 * (i - 1), 0.1, 0.0), "yaw": 0.0, "diff": 0.8})
		e.erase("bot")
		e.drive = func(_e): return {}
		men.append(e.f)
	return [m, men]

## How many touches between the two men were noted after `since`.
func _noted_since(m: Match, a: Fighter, b: Fighter, since: float) -> int:
	var n := 0
	for key in m.combat.touches:
		var r = m.combat.touches[key]
		if float(r.t) > since and is_instance_valid(r.a) and is_instance_valid(r.b):
			if (r.a.fighter == a and r.b.fighter == b) or (r.a.fighter == b and r.b.fighter == a):
				n += 1
	return n

## How many touches among any two of the men were noted after `since`.
func _noted_among(m: Match, men: Array, since: float) -> int:
	var n := 0
	for key in m.combat.touches:
		var r = m.combat.touches[key]
		if float(r.t) > since and is_instance_valid(r.a) and is_instance_valid(r.b) and men.has(r.a.fighter) and men.has(r.b.fighter):
			n += 1
	return n

## How many parts of `b` are pressed on parts of `a` this step.
func _pressed(a: Fighter, b: Fighter) -> int:
	var n := 0
	for p in b.parts:
		for o in p.get_colliding_bodies():
			if o is VoxelPart and o.fighter == a:
				n += 1
	return n

## `x` set down on `y` (made to overlap him: the physics presses them apart over the steps that follow), and what is noted and seen of
## their touching for `steps` steps: [touches noted, contacts seen].
func _press(m: Match, x: Fighter, y: Fighter, steps: int) -> Array:
	var since: float = m.combat.time
	var at := y.torso.global_position
	x.teleport(Vector3(at.x, at.y, at.z), true)
	var seen := 0
	for i in steps:
		await get_tree().physics_frame
		seen += _pressed(y, x) + _pressed(x, y)
	return [_noted_since(m, x, y, since), seen]

func test_the_dead_are_not_asked_who_touched_whom() -> void:
	var s = await _men()
	var m: Match = s[0]
	var a: Fighter = s[1][0]
	var b: Fighter = s[1][1]
	var c: Fighter = s[1][2]
	for i in 30:
		await get_tree().physics_frame
	# Alive, pressed on one another: what a hand that grabs asks for is noted (a forearm's touches: Combat._asked), and nothing else of a man's is (nobody asks what
	# his thigh touched: nearly all of a melee's touches, each spelt out and written twice a step and never read).
	var r: Array = await _press(m, b, a, 40)
	t.check(int(r[1]) > 0, "men pressed on one another touch (%d contacts seen)" % r[1])
	var fore := 0
	var other := 0
	for key in m.combat.touches:
		var rec = m.combat.touches[key]
		if is_instance_valid(rec.a) and (rec.a.fighter == a or rec.a.fighter == b):
			if String(key).begins_with("p") and String(rec.a.part_name).begins_with("forearm"):
				fore += 1
			else:
				other += 1
	t.check(other == 0, "of two men's touches only their forearms' are noted (%d others, %d forearms')" % [other, fore])
	t.check(Combat._asked(a.arm.R.fore) and Combat._asked(a.arm.L.fore) and not Combat._asked(a.torso) and not Combat._asked(a.by_name["thighR"]), "a forearm is asked about (the hand that grabs), a trunk or a thigh is not")
	t.check(Combat._may_strike(a.by_name["shinR"]) and Combat._may_strike(a.head) and Combat._may_strike(a.arm.R.fore) and not Combat._may_strike(a.torso) and not Combat._may_strike(a.by_name["thighL"]), "a shin, a head and a forearm may land a blow, a trunk or a thigh may not")
	_put_down(a)
	_put_down(b)
	for i in 120:
		await get_tree().physics_frame
	# Fallen, pressed on one another: the contacts are there, and nothing is noted of them.
	r = await _press(m, b, a, 40)
	t.check(int(r[1]) > 0, "two fallen men pressed together touch (%d contacts seen)" % r[1])
	t.eq(int(r[0]), 0, "and no touch between them is noted")
	# The last of them falls too, and lies on the two: a heap of three, and nothing is noted among them.
	_put_down(c)
	for i in 120:
		await get_tree().physics_frame
	var since: float = m.combat.time
	r = await _press(m, c, b, 40)
	t.check(int(r[1]) > 0, "a third fallen man pressed on them touches (%d contacts seen)" % r[1])
	t.eq(_noted_among(m, [a, b, c], since), 0, "and nothing is noted among the three")
	m.queue_free()
