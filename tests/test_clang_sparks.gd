extends Node
## Sparks off two weapons that meet (user: they flew from every touch): only a clash hard AND fast enough
## throws them. The rule is Match.clang_sparks(J, v); Combat reports each clash with its impulse J and
## the speed `v` the two came together at, and the shield takes a blow's speed the same way.

var t

func _clashes(w: TestWorld, a: Weapon, b: Weapon, J: float, va: Vector3, vb: Vector3) -> Dictionary:
	var got := []
	var cb := func(c): got.append(c)
	w.combat.clang.connect(cb)
	# (As the step before the touch had them: Combat keeps the speeds each step ends with.)
	w.combat.vel[a.get_instance_id()] = [va, Vector3.ZERO]
	w.combat.vel[b.get_instance_id()] = [vb, Vector3.ZERO]
	var at: Vector3 = (a.global_position + b.global_position) * 0.5
	w.combat._clang({"clang": true, "a": a, "b": b, "sa": 0, "sb": 0, "p": at, "J": J}, [])
	w.combat.clang.disconnect(cb)
	return got[0] if not got.is_empty() else {}

func _weapons(w: TestWorld) -> Array:
	var a := Weapon.new()
	w.add_child(a)
	a.setup(Data.preset("gladius").duplicate(true))
	var b := Weapon.new()
	w.add_child(b)
	b.setup(Data.preset("gladius").duplicate(true))
	b.global_position = Vector3(0.0, 0.0, 0.5)
	return [a, b]

func test_sparks_need_a_hard_and_fast_clash() -> void:
	t.check(not Match.clang_sparks(2.3, 6.0), "a light touch, however fast, throws none")
	t.check(not Match.clang_sparks(8.0, 1.0), "nor a hard push at a crawl")
	t.check(not Match.clang_sparks(1.3, 0.2), "nor two blades laid together")
	t.check(Match.clang_sparks(20.0, 5.0), "a strong blow at speed does")
	t.check(Match.clang_sparks(Match.SPARK_J, Match.SPARK_V), "right at both bars it does")
	t.check(not Match.clang_sparks(Match.SPARK_J - 0.1, 9.0) and not Match.clang_sparks(30.0, Match.SPARK_V - 0.1), "just under either bar it does not")
	# A clash that gave no speed (a blow with none noted) is judged by its force alone.
	t.check(Match.clang_sparks(20.0, INF) and not Match.clang_sparks(3.0, INF), "with no speed to go by, the force decides")

## What was too slight to throw sparks was most of what the bots' blades did to each other (measured over
## 133 clashes: 30 threw sparks, 26 of them under 3 m/s): the bars sit between the two kinds.
func test_blades_swung_together_report_their_speed() -> void:
	var w := TestWorld.new()
	add_child(w)
	var ws := _weapons(w)
	var a: Weapon = ws[0]
	var b: Weapon = ws[1]
	var fast := _clashes(w, a, b, 20.0, Vector3(0, 0, 6.0), Vector3(0, 0, -2.0))
	t.check(is_equal_approx(float(fast.get("v", -1.0)), 8.0), "two blades met at 6 and 2 m/s head on come together at 8 (%.1f)" % float(fast.get("v", -1.0)))
	t.check(Match.clang_sparks(float(fast.J), float(fast.v)), "a hard clash at that speed throws sparks")
	var lazy := _clashes(w, a, b, 20.0, Vector3(0, 0, 0.8), Vector3(0, 0, 0.1))
	t.check(float(lazy.get("v", 99.0)) < 1.0, "one laid on another at under a metre a second is slow (%.1f)" % float(lazy.get("v", 99.0)))
	t.check(not Match.clang_sparks(float(lazy.J), float(lazy.v)), "and throws none, however hard its force")
	var touch := _clashes(w, a, b, 2.2, Vector3(0, 0, 6.0), Vector3(0, 0, 2.0))
	t.check(not Match.clang_sparks(float(touch.J), float(touch.v)), "a fast brush that passed on throws none")
	w.queue_free()
