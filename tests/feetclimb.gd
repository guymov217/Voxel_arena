extends Node
## Probe: a man walking and running up onto a step and off it again (steps of set heights): how much
## of the time both his feet are off what is under them, and how high (HIGH: taller steps;
## TRACE=height,walk|run: the frames, foot by foot).

func _corner(f: Fighter, sh: VoxelPart) -> float:
	var p := sh.global_transform * Vector3(0, -4 * Fighter.V * f.S, 0)
	var g := f._ground_under(p, f.ground_level)
	var lo := INF
	var h: Vector3 = sh.half_ext
	for cx in [-1, 1]:
		for cy in [-1, 1]:
			for cz in [-1, 1]:
				lo = minf(lo, (sh.global_transform * Vector3(cx * h.x, cy * h.y, cz * h.z)).y - g)
	return lo

func _ready() -> void:
	for hgt in ([float(OS.get_environment("TRACE").split(",")[0])] if OS.get_environment("TRACE") != "" else ([0.45, 0.6] if OS.get_environment("HIGH") != "" else [0.08, 0.15, 0.25, 0.35])):
		for run in ([OS.get_environment("TRACE").ends_with("run")] if OS.get_environment("TRACE") != "" else [false, true]):
			var w := TestWorld.new()
			add_child(w)
			w.ready_arena()
			var f := w.fighter(Vector3(0, 0, 0), 0.0, {"main": "gladius"}, {"name": "A", "slot": 0})
			for i in 120:
				f.control(1.0 / 120.0, {})
				await get_tree().physics_frame
			var fwd := Vector3(sin(f.yaw), 0, cos(f.yaw))
			var step := StaticBody3D.new()
			var cs := CollisionShape3D.new()
			var bx := BoxShape3D.new()
			bx.size = Vector3(4.0, hgt, 1.6)
			cs.shape = bx
			step.add_child(cs)
			w.add_child(step)
			step.global_transform = Transform3D(Basis(Vector3.UP, f.yaw), f.torso.global_position * Vector3(1, 0, 1) + fwd * 2.0 + Vector3(0, hgt * 0.5, 0))
			var n := 0
			var up := 0
			var worst := 0.0
			var p0 := f.torso.global_position
			for i in 120 * 5:
				f.control(1.0 / 120.0, {"mz": 1.0, "sprint": run})
				await get_tree().physics_frame
				if f.state == "stand":
					n += 1
					var a := minf(_corner(f, f.by_name["shinL"]), _corner(f, f.by_name["shinR"]))
					if OS.get_environment("TRACE") != "" and i > 150 and i < 200:
						print("  f%d L s %.2f late %.2f sw %s anc %.2f   R s %.2f late %.2f sw %s anc %.2f  a %.3f" % [i, f.feet.L.s, float(f.feet.L.get("late", 0.0)), f.feet.L.swing, (f.feet.L.anchor as Vector3).y, f.feet.R.s, float(f.feet.R.get("late", 0.0)), f.feet.R.swing, (f.feet.R.anchor as Vector3).y, a])
					if a > 0.02:
						up += 1
						if OS.get_environment("TRACE") != "":
							var sl: Vector3 = f.by_name["shinL"].global_transform * Vector3(0, -4 * Fighter.V * f.S, 0)
							var sr: Vector3 = f.by_name["shinR"].global_transform * Vector3(0, -4 * Fighter.V * f.S, 0)
							print("  t%d at %.2f  L %.3f (%.2f, swing %s) R %.3f (%.2f, swing %s) hipsY %.2f" % [i, (f.torso.global_position - p0).dot(fwd), _corner(f, f.by_name["shinL"]), (sl - p0).dot(fwd), f.feet.L.swing, _corner(f, f.by_name["shinR"]), (sr - p0).dot(fwd), f.feet.R.swing, f.torso.global_position.y])
					worst = maxf(worst, a)
			var went := (f.torso.global_position - p0).dot(fwd)
			print("CLIMB %.2fm %s both feet off %.1f%%, highest %.3f m, went %.1f m, state %s" % [hgt, "run " if run else "walk", 100.0 * up / maxf(1, n), worst, went, f.state])
			w.queue_free()
			await get_tree().physics_frame
	get_tree().quit()
