extends Node
## Rules added together: an arrow's flight lands on the crosshair at any range, a man out cold
## for good is beaten, a hard landing hurts, a beast with no weapon left still comes on with
## its weight, and a man running from the python's coils tears free.

var t

func _steps(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func _world() -> TestWorld:
	var w := TestWorld.new()
	add_child(w)
	w.ready_arena()
	return w

func test_a_flat_shot_lands_on_the_mark() -> void:
	for d in [Vector3(0, 0, 10), Vector3(5, -1, 30), Vector3(-20, 2, 40)]:
		var speed := 58.0
		var v: Vector3 = Items.flat_shot(d, speed)
		var dx := Vector2(d.x, d.z).length()
		var tt := dx / Vector2(v.x, v.z).length()
		var at := Vector3(v.x * tt, v.y * tt - 0.5 * 9.81 * tt * tt, v.z * tt)
		t.check(at.distance_to(d) < 0.05, "a shot at %s lands %.3f m off" % [str(d), at.distance_to(d)])

func test_out_cold_is_beaten() -> void:
	var w := _world()
	var a := w.fighter(Vector3(0, 0, 0), 0.0, {}, {"name": "A"})
	await _steps(30)
	t.check(not a.is_beaten(), "standing, he is in the fight")
	a.concussion = 1.0
	a.fall(99.0, true)
	await _steps(5)
	t.check(not a.is_out(), "not counted out the instant he drops")
	for i in 90:
		await get_tree().physics_frame
		a.is_out()   # (the match asks every step)
	t.check(a.alive and a.is_out() and a.is_beaten(), "rung senseless on the sand, alive but beaten")
	w.queue_free()

## One hard knock that floors him is not the end of his bout: his head clears on the sand in a
## moment and he is in the fight again; only a knock that leaves him senseless counts him out.
func test_one_knock_is_not_a_knockout() -> void:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none"}, "decrees": [], "hazards": [], "headless": true, "seed": 5})
	m.me.f.teleport(Vector3(0, 0, -8))
	var e = m.spawn_fighter({"kind": "bot", "name": "V", "loadout": {}, "team": 1, "pos": Vector3(0, 0.1, 0), "yaw": PI})
	e.erase("bot")
	e.drive = func(_e): return {}
	var a: Fighter = e.f
	for i in 60:
		await get_tree().physics_frame
	a.concussion = 0.87
	a.fall(1.5, true)
	var out := false
	for i in 120 * 3:
		await get_tree().physics_frame
		out = out or a.is_beaten()
	t.check(not out, "floored by one knock, never counted out (concussion now %.2f)" % a.concussion)
	m.queue_free()

func test_a_hard_landing_hurts() -> void:
	var w := _world()
	var a := w.fighter(Vector3(0, 0, 0), 0.0, {}, {"name": "A"})
	await _steps(60)
	var hp0: float = a.by_name.shinL.hp + a.by_name.shinR.hp
	for p in a.parts:
		p.global_position += Vector3(0, 6.0, 0)
		p.linear_velocity = Vector3(0, -2.0, 0)
	var vmin := 0.0
	var falls := [0]
	w.combat.hit.connect(func(h): if h.get("fall", false): falls[0] += 1)
	for i in 150:
		a.control(1.0 / 120.0, {})
		await get_tree().physics_frame
		vmin = minf(vmin, a.torso.linear_velocity.y)
	var hp1: float = a.by_name.shinL.hp + a.by_name.shinR.hp
	var lowest := 9e9
	for p in a.parts:
		lowest = minf(lowest, p.hp)
	t.check(hp1 < hp0 or lowest < 100.0, "a fall of six metres hurts (shins %.0f -> %.0f)" % [hp0, hp1])
	w.queue_free()

func test_a_disarmed_beast_still_rams() -> void:
	var w := _world()
	var b := Beast.new()
	w.add_child(b)
	b.build_beast("cerberus", Vector3(0, 0.2, 0), 0.0, {"seed": 11})
	w.combat.fighters.append(b)
	t.check(not b.disarmed(), "with its heads it has jaws to fight with")
	# Jaws too broken to bite (the heads are still there to see with).
	for h in b.heads:
		h.def = h.def.duplicate()
		h.def.bite = false
	t.check(b.disarmed(), "with jaws that cannot bite, only its weight is left")
	var man := w.fighter(Vector3(0, 0, 4.0), PI, {}, {"name": "Man", "slot": 0})
	b.target = man
	var hits := [0]
	w.combat.hit.connect(func(h): if h.attacker == b: hits[0] += 1)
	for s in 8 * 120:
		man.control(1.0 / 120.0, {})
		b.control(1.0 / 120.0)
		await get_tree().physics_frame
		if hits[0] > 0:
			break
	t.check(hits[0] > 0, "toothless, it still runs him down or rams him")
	w.queue_free()

func test_running_tears_free_of_the_coils() -> void:
	seed(12)   # the game's dice (randf) the same whatever tests ran before
	var w := _world()
	var man := w.fighter(Vector3(0, 0, 0), 0.0, {}, {"name": "Man", "slot": 0})
	var b := Beast.new()
	w.add_child(b)
	b.build_beast("python", Vector3(0, 0.2, 1.2), PI, {"seed": 11})
	w.combat.fighters.append(b)
	b.target = man
	await _steps(30)
	b._start_coil(man)
	var freed := false
	for s in 6 * 120:
		man.stamina = 100.0
		man.control(1.0 / 120.0, {"mz": 1.0, "sprint": true})
		b.control(1.0 / 120.0)
		await get_tree().physics_frame
		if b.hug == null:
			freed = true
			break
	t.check(freed, "running hard away from the python, he tears out of its coils")
	w.queue_free()
