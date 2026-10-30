extends Node
## Probe: a man alone on the sand, walking, running, strafing, turning, and struck by blows of set
## strength from set sides: how much of the time both his soles are off the sand, and why.

var w: TestWorld

func _sole(f: Fighter, sd: String) -> float:
	var sh: VoxelPart = f.by_name["shin" + sd]
	if sh.severed:
		return INF
	return _corner(f, sh)

## The lowest corner of a shin's box over what is under it (a heel or a toe on the sand is a foot on it).
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

func _air(f: Fighter) -> float:
	return minf(_sole(f, "L"), _sole(f, "R"))

func _ready() -> void:
	w = TestWorld.new()
	add_child(w)
	w.ready_arena()
	var f := w.fighter(Vector3(0, 0, 0), 0.0, {"main": "gladius"}, {"name": "A", "slot": 0})
	for i in 120:
		f.control(1.0 / 120.0, {})
		await get_tree().physics_frame
	for leg in [["walk", {"mz": 1.0}], ["run", {"mz": 1.0, "sprint": true}], ["strafe", {"mx": 1.0}], ["back", {"mz": -1.0}], ["turn", {"mz": 1.0, "turn": true}], ["stand", {}]]:
		var n := 0
		var up := 0
		var worst := 0.0
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
		print("LAB %-7s both soles off %.1f%% of the time, highest %.3f m (state %s)" % [leg[0], 100.0 * up / maxf(1, n), worst, f.state])
		f.teleport(Vector3(0, 0, 0))
		for i in 60:
			f.control(1.0 / 120.0, {})
			await get_tree().physics_frame
	# Blows: an impulse on the trunk, as a weapon's contact would put it (struck_frame set).
	for J in [15.0, 30.0, 60.0]:
		for dir in [Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0.7, 0.4, 0.7).normalized()]:
			f.teleport(Vector3(0, 0, 0))
			for i in 90:
				f.control(1.0 / 120.0, {})
				await get_tree().physics_frame
			var off := 0
			var worst := 0.0
			var fell := false
			for i in 120:
				if i < 6:
					f.struck_frame = Engine.get_physics_frames()
				if i == 0:
					f.torso.apply_impulse(dir * J, Vector3(0, 0.1, 0))
				f.control(1.0 / 120.0, {})
				await get_tree().physics_frame
				if f.state != "stand":
					fell = true
					break
				var a := _air(f)
				if a > 0.02:
					off += 1
				worst = maxf(worst, a)
			print("LAB blow J %3.0f %-10s feet off %.2f s, highest %.3f m%s" % [J, str(dir.snapped(Vector3(0.1, 0.1, 0.1))), off / 120.0, worst, ", fell" if fell else ""])
	get_tree().quit()
