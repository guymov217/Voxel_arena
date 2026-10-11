extends Node
## Every beast stands; a lion hunts a man and bites him.

var t

func _world() -> TestWorld:
	var w := TestWorld.new()
	add_child(w)
	w.ready_arena()
	return w

func _beast(w: TestWorld, species: String, pos: Vector3, yaw := 0.0) -> Beast:
	var b := Beast.new()
	w.add_child(b)
	b.build_beast(species, pos, yaw, {"seed": 7})
	w.combat.fighters.append(b)
	return b

func test_every_species_stands() -> void:
	var w := _world()
	var list := []
	var i := 0
	for k in Data.beasts:
		var a := float(i) / Data.beasts.size() * TAU
		list.append(_beast(w, k, Vector3(sin(a) * 9.0, 0.2, cos(a) * 9.0), a + PI))
		i += 1
	for s in 240:
		for b in list:
			b.control(1.0 / 120.0)
		await get_tree().physics_frame
	var bad := []
	for b in list:
		var y: float = b.torso.global_position.y
		var up: float = (PD.quat_of(b.torso) * Vector3.UP).y
		if not is_finite(y) or y < 0.05 or y > b.height * 3.0 + 1.0 or up < 0.5:
			bad.append("%s y=%.2f up=%.2f" % [b.species, y, up])
	t.check(bad.is_empty(), "all standing: " + ", ".join(bad))
	w.queue_free()

func test_a_lion_bites() -> void:
	var w := _world()
	var man := w.fighter(Vector3(0, 0, 0), PI, {"main": "gladius"}, {"name": "Man", "slot": 0})
	var lion := _beast(w, "lion", Vector3(0, 0.2, 4.0), PI)
	lion.target = man
	var bites := [0]
	w.combat.hit.connect(func(h): if h.attacker == lion: bites[0] += 1)
	for s in 120 * 20:
		man.control(1.0 / 120.0, {"main": {"x": 0.1, "y": 0.1}})
		lion.control(1.0 / 120.0)
		await get_tree().physics_frame
	t.check(bites[0] > 0, "the lion got its teeth in (%d)" % bites[0])
	t.check(man.total_hp() < 1000.0 or man.blood < 100.0, "the man is hurt")
	w.queue_free()
