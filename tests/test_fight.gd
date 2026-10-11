extends Node
## Fighters stand, walk, and hurt each other (as the web game's strikes and sim tests).

var t

func _world() -> TestWorld:
	var w := TestWorld.new()
	add_child(w)
	w.ready_arena()
	return w

func _step(w: TestWorld, n: int, inputs: Callable) -> void:
	for i in n:
		for f in w.fighters:
			f.control(1.0 / 120.0, inputs.call(f, i))
		await get_tree().physics_frame

func test_a_fighter_stands_and_walks() -> void:
	var w := _world()
	var f := w.fighter(Vector3.ZERO, 0.0, {"main": "gladius", "off": "roundShield"}, {"name": "A"})
	await _step(w, 360, func(_f, _i): return {"main": {"x": 0.1, "y": 0.1}})
	t.eq(f.state, "stand", "still standing after 3 s")
	t.check(f.torso.global_position.y > 1.0, "torso at standing height (%.2f)" % f.torso.global_position.y)
	var z0 := f.torso.global_position.z
	await _step(w, 360, func(_f, _i): return {"main": {"x": 0.1, "y": 0.1}, "mz": 1.0})
	t.eq(f.state, "stand", "walked without falling")
	t.check(f.torso.global_position.z - z0 > 2.0, "walked forward (%.2f m)" % (f.torso.global_position.z - z0))
	w.queue_free()

func test_a_sword_sweep_cuts_a_dummy() -> void:
	var w := _world()
	var a := w.fighter(Vector3(0, 0, 0), 0.0, {"main": "gladius"}, {"name": "a", "slot": 0})
	var b := w.fighter(Vector3(0, 0, 1.1), PI, {}, {"name": "dummy", "slot": 1})
	var hits := []
	w.combat.hit.connect(func(h):
		if h.char == b:
			hits.append(h)
			if OS.get_environment("DEBUG_HITS") != "":
				print("     hit J=%.1f type=%s part=%s dmg=%.1f removed=%d" % [h.J, h.type, h.part.part_name, h.res.dmg, h.res.removed.size()]))
	await _step(w, 720, func(f, i):
		if f == b:
			return {"main": {"x": 0.0, "y": 0.0}}
		var ph := fmod(i / 120.0 * 0.6, 1.0)
		var k := 0.0 if ph < 0.5 else (ph - 0.5) / 0.5
		return {"main": {"x": 1.5 - 3.0 * k, "y": 0.3}, "power": k > 0.0})
	var edge := hits.filter(func(h): return h.type == "edge")
	t.check(edge.size() > 0, "the blade hit (%d hits, %d edge)" % [hits.size(), edge.size()])
	t.check(b.total_hp() < 1000.0 - 20.0, "real damage (%.0f hp lost)" % (1000.0 - b.total_hp()))
	w.queue_free()

func test_two_bots_fight() -> void:
	var w := _world()
	var a := w.fighter(Vector3(0, 0, -1.5), 0.0, {"main": "gladius", "off": "roundShield"}, {"name": "A", "slot": 0, "bot": true})
	var b := w.fighter(Vector3(0, 0, 1.5), PI, {"main": "axe"}, {"name": "B", "slot": 1, "bot": true})
	var bots := {a: Bot.new(a, 0.8, "standard", 1), b: Bot.new(b, 0.8, "standard", 2)}
	var hits := [0]
	w.combat.hit.connect(func(h): hits[0] += 1)
	await _step(w, 120 * 25, func(f, _i):
		var o: Fighter = b if f == a else a
		var d: Vector3 = o.torso.global_position - f.torso.global_position
		f.yaw = atan2(d.x, d.z)
		return bots[f].update(1.0 / 120.0, o))
	var lost := 2000.0 - a.total_hp() - b.total_hp()
	t.check(hits[0] > 3, "blows landed (%d)" % hits[0])
	t.check(lost > 30.0, "they hurt each other (%.0f hp)" % lost)
	for f in [a, b]:
		t.check(is_finite(f.torso.global_position.y), "physics stayed sane")
	print("   duel: hits=%d lost=%.0f A=%s B=%s" % [hits[0], lost, a.state, b.state])
	w.queue_free()

## Swept hard across the body and back, the sword arm bends like an arm: the elbow stays on its
## own side of the chest, and the blade never passes through its owner's torso.
func test_the_arm_keeps_to_its_side() -> void:
	var w := _world()
	var f := w.fighter(Vector3.ZERO, 0.0, {"main": "longsword"}, {"name": "A"})
	var worst_x := -1.0
	var inside := 0
	await _step(w, 720, func(_f, i):
		var ph := fmod(i / 120.0 * 0.5, 1.0)
		var x := -2.0 + 4.0 * absf(ph * 2.0 - 1.0)
		return {"main": {"x": x, "y": 0.2 if i % 240 < 120 else -0.4}, "power": true})
	for i in 480:
		var ph := fmod(i / 120.0 * 0.7, 1.0)
		f.control(1.0 / 120.0, {"main": {"x": -2.0 + 4.0 * absf(ph * 2.0 - 1.0), "y": 0.3}, "power": true})
		await get_tree().physics_frame
		var inv := PD.quat_of(f.torso).inverse()
		var elbow: Vector3 = inv * (f.arm.R.fore.global_transform * f.arm.R.fore.ca - f.torso.global_position)
		worst_x = maxf(worst_x, elbow.x)
		var wpn: Weapon = f.weapons.R
		var q := PD.quat_of(wpn)
		for k in 6:
			var p: Vector3 = wpn.global_position + q * Vector3(0, wpn.reach * (0.2 + 0.16 * k), 0)
			var d: Vector3 = inv * (p - f.torso.global_position)
			if absf(d.x) < f.torso.half_ext.x * 0.8 and absf(d.y) < f.torso.half_ext.y * 0.8 and absf(d.z) < f.torso.half_ext.z * 0.8:
				inside += 1
	t.eq(f.state, "stand", "still on his feet")
	t.check(worst_x < 0.03 * f.S, "the right elbow stays right of the chest (x %.2f)" % worst_x)
	t.check(inside < 10, "the blade stays out of his own chest (%d samples inside)" % inside)
	w.queue_free()
