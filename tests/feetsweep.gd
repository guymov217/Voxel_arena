extends Node
## Probe: the gait's numbers (Fighter.GAIT) tried in turn on a man walking, running and turning:
## how much of the time both soles are off the sand, and how high (SWEEP: JSON list of overrides).

func _air(f: Fighter) -> float:
	var lo := INF
	for sd in ["L", "R"]:
		var sh: VoxelPart = f.by_name["shin" + sd]
		var p := sh.global_transform * Vector3(0, -4 * Fighter.V * f.S, 0)
		var g := f._ground_under(p, f.ground_level)
		if OS.get_environment("CORNER") == "":
			lo = minf(lo, p.y - g)
			continue
		# The lowest corner of the shin's box (a heel or toe on the sand is a foot on it).
		var h: Vector3 = sh.half_ext
		for cx in [-1, 1]:
			for cy in [-1, 1]:
				for cz in [-1, 1]:
					var c := sh.global_transform * Vector3(cx * h.x, cy * h.y, cz * h.z)
					lo = minf(lo, c.y - g)
	return lo

func _ready() -> void:
	var sets: Array = JSON.parse_string(OS.get_environment("SWEEP")) if OS.get_environment("SWEEP") != "" else [{}]
	var base := {}
	for over in sets:
		pass
		for k in over:
			pass
		var w := TestWorld.new()
		add_child(w)
		w.ready_arena()
		var f := w.fighter(Vector3(0, 0, 0), 0.0, {"main": "gladius"}, {"name": "A", "slot": 0})
		for i in 120:
			f.control(1.0 / 120.0, {})
			await get_tree().physics_frame
		var out := []
		var total := 0.0
		for leg in [["walk", {"mz": 1.0}], ["run", {"mz": 1.0, "sprint": true}], ["turn", {"mz": 1.0, "turn": true}]]:
			var n := 0
			var up := 0
			var worst := 0.0
			var dist0 := f.torso.global_position
			for i in 120 * 4:
				var inp: Dictionary = (leg[1] as Dictionary).duplicate()
				if inp.has("turn"):
					inp.erase("turn")
					f.yaw += 1.5 / 120.0
				f.control(1.0 / 120.0, inp)
				await get_tree().physics_frame
				if i > 60 and f.state == "stand":
					n += 1
					var a := _air(f)
					if a > 0.02:
						up += 1
					worst = maxf(worst, a)
			var sp := Vector2(f.torso.global_position.x - dist0.x, f.torso.global_position.z - dist0.z).length() / 4.0
			out.append("%s %.1f%% %.3fm %.1fm/s%s" % [leg[0], 100.0 * up / maxf(1, n), worst, sp, "" if f.state == "stand" else " FELL"])
			total += 100.0 * up / maxf(1, n)
			f.teleport(Vector3(0, 0, 0))
			for i in 60:
				f.control(1.0 / 120.0, {})
				await get_tree().physics_frame
		print("SWEEP %s -> %s | sum %.1f" % [JSON.stringify(over), ", ".join(out), total])
		w.queue_free()
		await get_tree().physics_frame
	get_tree().quit()
