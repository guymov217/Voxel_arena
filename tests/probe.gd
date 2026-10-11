extends Node
## Ad-hoc probe (`-- --probe`): a bot duel, printing what each fighter is doing.

func _ready() -> void:
	var w := TestWorld.new()
	add_child(w)
	w.ready_arena()
	var a := w.fighter(Vector3(0, 0, -1.5), 0.0, {"main": "gladius", "off": "roundShield"}, {"name": "A", "slot": 0})
	var b := w.fighter(Vector3(0, 0, 1.5), PI, {"main": "axe"}, {"name": "B", "slot": 1})
	var bots := {a: Bot.new(a, 0.8, "standard", 1), b: Bot.new(b, 0.8, "standard", 2)}
	var hits := [0]
	w.combat.hit.connect(func(h): hits[0] += 1)
	for i in 120 * 30:
		for f in [a, b]:
			var o: Fighter = b if f == a else a
			var d: Vector3 = o.torso.global_position - f.torso.global_position
			f.yaw = atan2(d.x, d.z)
			f.control(1.0 / 120.0, bots[f].update(1.0 / 120.0, o))
			if f.state != f.get_meta("last", "stand"):
				print("i=%d %s -> %s tilt=%.2f stagger=%.2f" % [i, f.display_name, f.state, acos(clampf((PD.quat_of(f.torso) * Vector3.UP).y, -1, 1)), f.stagger])
				f.set_meta("last", f.state)
		await get_tree().physics_frame
		if i % 240 == 0:
			print("t=%d dist=%.2f hits=%d A(%s hp %.0f blood %.0f) B(%s hp %.0f blood %.0f)" % [i / 120, (a.torso.global_position - b.torso.global_position).length(), hits[0], a.state, a.total_hp(), a.blood, b.state, b.total_hp(), b.blood])
	get_tree().quit()
