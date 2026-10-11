extends Node
## Walking measurements (`-- --probe walkprobe`, headless): a gladius-and-shield fighter stands
## 3 s, walks forward 3 s, sideways 2 s, back 2 s. Prints leg jitter (how often the knee's
## bending speed reverses, and its RMS), torso height against standing height, drift, steps,
## and how far the feet slide while planted.

func _ready() -> void:
	var w := TestWorld.new()
	add_child(w)
	w.ready_arena()
	var f := w.fighter(Vector3.ZERO, 0.0, {"main": "gladius", "off": "roundShield"}, {"name": "A"})
	var dt := 1.0 / 120.0
	var phases := [["stand", 360, {}], ["fwd", 360, {"mz": 1.0}], ["side", 240, {"mx": 1.0}], ["back", 240, {"mz": -1.0}], ["sprint", 240, {"mz": 1.0, "sprint": true}]]
	for ph in phases:
		var flips := 0
		var prev_w := {"L": 0.0, "R": 0.0}
		var prev_s := {"L": 0.0, "R": 0.0}
		var rms := 0.0
		var hs := []
		var steps := 0
		var was := {"L": false, "R": false}
		var slide := 0.0
		var p0: Vector3 = f.torso.global_position
		var tw := 0.0
		for i in int(ph[1]):
			var inp: Dictionary = {"main": {"x": 0.1, "y": 0.1}}
			inp.merge(ph[2])
			f.control(dt, inp)
			await get_tree().physics_frame
			if i < 60:
				continue
			for s in ["L", "R"]:
				var th: VoxelPart = f.by_name["thigh" + s]
				var sh: VoxelPart = f.by_name["shin" + s]
				var axis := PD.quat_of(th) * Vector3(1, 0, 0)
				var wk := (sh.angular_velocity - th.angular_velocity).dot(axis)
				var acc: float = (wk - float(prev_w[s])) / dt
				rms += acc * acc
				if signf(acc) != signf(prev_s[s]) and absf(acc) > 30.0:
					flips += 1
				prev_s[s] = acc
				prev_w[s] = wk
				var ft = f.feet[s]
				if ft:
					if ft.swing and not was[s]:
						steps += 1
					was[s] = ft.swing
					if not ft.swing:
						slide += ft.slip
			hs.append(f.torso.global_position.y)
			tw += f.torso.angular_velocity.length()
		var n := float(ph[1] - 60)
		var mean_h: float = hs.reduce(func(a, b): return a + b, 0.0) / hs.size()
		var d: Vector3 = f.torso.global_position - p0
		print("%-6s knee-flips/s %5.1f  knee-acc-rms %7.1f  torso h %.3f (want %.3f)  drift x %.2f z %.2f  steps %d  plant-slide %.3f  torso-spin %.2f  state %s" % [ph[0], flips / (n * dt), sqrt(rms / (n * 2.0)), mean_h, f.torso_y * 0.95, d.x, d.z, steps, slide / maxf(1.0, n * 2.0), tw / n, f.state])
	get_tree().quit()
