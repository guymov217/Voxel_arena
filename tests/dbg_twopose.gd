extends Node
## Two-handed posture: for each weapon and mark, the trunk's tilt (back arch), how far the
## blade is off the mouse, whether an upper arm crosses the face, the hands' spacing.

func _ready() -> void:
	for wk in ["longsword", "zweihander", "warhammer"]:
		var m := Match.new()
		add_child(m)
		m.setup({"mode": "training", "training": {"enemy": "none"}, "headless": true, "seed": 3, "loadout": {"main": wk, "off": ""}})
		var f: Fighter = m.me.f
		var box := {"i": {"main": {"x": 0.1, "y": 0.1}, "power": false}}
		m.me.drive = func(_e): return box.i
		for i in 90:
			await get_tree().physics_frame
		var marks := {"high": Vector2(0, 1.6), "high_r": Vector2(1.1, 1.3), "high_l": Vector2(-1.1, 1.3), "right": Vector2(1.8, 0), "left": Vector2(-1.8, 0), "low": Vector2(0, -1.5), "low_r": Vector2(1.2, -1.2), "mid": Vector2(0, 0.2)}
		var worst_tilt := 0.0
		var worst_err := 0.0
		for name in marks:
			var d: Vector2 = marks[name]
			box.i = {"main": {"x": d.x, "y": d.y}, "power": false}
			var tilt_max := 0.0
			for i in 90:
				await get_tree().physics_frame
				var up: Vector3 = f.torso.global_transform.basis.y
				tilt_max = maxf(tilt_max, rad_to_deg(up.angle_to(Vector3.UP)))
			var up2: Vector3 = f.torso.global_transform.basis.y
			var fwd := Quaternion(Vector3.UP, f.yaw) * Vector3(0, 0, 1)
			var pitch := rad_to_deg(asin(clampf(up2.dot(fwd), -1, 1)))   # + leaning forward, - arched back
			var w: Weapon = f.weapons.R
			var err := rad_to_deg(PD.quat_of(w).angle_to(f.aim_q.R)) if w else -1.0
			var face: Vector3 = f.head.global_position
			var arm_face := 9.0
			for sd in ["R", "L"]:
				for part in [f.arm[sd].upper, f.arm[sd].fore]:
					arm_face = minf(arm_face, part.global_position.distance_to(face))
			var spacing := f.hand_world("L").distance_to(f.hand_world("R"))
			var leg_bend := rad_to_deg(f.by_name.thighR.global_transform.basis.y.angle_to(f.torso.global_transform.basis.y))
			worst_tilt = maxf(worst_tilt, tilt_max)
			worst_err = maxf(worst_err, err)
			print("%s %-7s two=%s tilt_max=%4.0f pitch=%4.0f hip=%4.0f err=%4.0f arm_face=%.2f hands=%.2f" % [wk, name, f.two_handed, tilt_max, pitch, leg_bend, err, arm_face, spacing])
		# Sweeps: how far the blade trails the mouse through fast strokes.
		var lag := 0.0
		var stuck := 0
		var pairs := [[Vector2(0, 1.6), Vector2(0, -1.5)], [Vector2(1.8, 0.4), Vector2(-1.8, 0.4)], [Vector2(1.1, 1.3), Vector2(-1.2, -1.2)], [Vector2(-1.1, 1.3), Vector2(1.2, -1.2)]]
		for k in 12:
			var pr: Array = pairs[k % pairs.size()]
			for e in pr:
				box.i = {"main": {"x": e.x, "y": e.y}, "power": true}
				for i in 50:
					await get_tree().physics_frame
				var w: Weapon = f.weapons.R
				var er := rad_to_deg(PD.quat_of(w).angle_to(f.aim_q.R))
				lag = maxf(lag, er)
				if er > 35.0:
					stuck += 1
		print("%s SUMMARY worst_tilt=%.0f worst_err=%.0f sweep_worst=%.0f stuck=%d/24 state=%s" % [wk, worst_tilt, worst_err, lag, stuck, f.state])
		m.queue_free()
		await get_tree().process_frame
	get_tree().quit()
