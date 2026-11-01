extends Node
## The hands shaking in the yard (user video 1135: two swords held out in front, wounded, at the
## physician's stall, the blades on the physician): how much each blade's tip shakes (mm, the
## part of its motion faster than a quarter second) standing up against the keeper and standing
## clear of him. `-- --probe yardtremor`.

func _tip(w: Weapon) -> Vector3:
	return w.global_position + PD.quat_of(w) * Vector3(0, w.reach, 0)

func _shake(a: Array) -> Vector2:
	var hf := 0.0
	var step := 0.0
	var k := 15
	for i in range(k, a.size() - k):
		var avg := Vector3.ZERO
		for j in range(i - k, i + k + 1):
			avg += a[j]
		avg /= float(2 * k + 1)
		hf += (a[i] - avg).length_squared()
		step = maxf(step, (a[i] - a[i - 1]).length())
	return Vector2(sqrt(hf / float(maxi(1, a.size() - 2 * k))) * 1000.0, step * 1000.0)

func _ready() -> void:
	for case in ["at the keeper", "clear of him"]:
		for hurt in [false, true]:
			var m := Match.new()
			add_child(m)
			m.setup({"mode": "yard", "headless": true, "seed": 1, "decrees": [], "hazards": [], "loadout": {"main": "gladius", "off": "gladius"}})
			var f: Fighter = m.me.f
			var keeper: Fighter = null
			for e in m.entities:
				if String(e.f.display_name).contains("physician"):
					keeper = e.f
			if keeper == null:
				print("YARD no physician")
				get_tree().quit()
				return
			var kp: Vector3 = keeper.torso.global_position
			var away := Vector3(-kp.x, 0, -kp.z).normalized()
			var stand: Vector3 = kp + away * (0.85 if case == "at the keeper" else 3.5)
			var face := atan2(kp.x - stand.x, kp.z - stand.z)
			f.teleport(Vector3(stand.x, 0, stand.z))
			if OS.get_environment("KEEP_YAW") != "":
				face = f.yaw
			m.me.drive = func(_e): return {"main": {"x": 0.25, "y": 0.3}, "off": {"x": -0.25, "y": 0.3}, "look": {"yaw": face, "pitch": 0.0}}
			if hurt:
				for s in ["R", "L"]:
					f.arm[s].fore.hp *= 0.35
					f.arm[s].upper.hp *= 0.5
			var hits := [0]
			m.combat.hit.connect(func(h): if h.get("char") == keeper: hits[0] += 1)
			for i in 240:
				await get_tree().physics_frame
			var tips := {"R": [], "L": []}
			for i in 360:
				await get_tree().physics_frame
				for s in ["R", "L"]:
					var w = f.weapons[s]
					if w:
						tips[s].append(_tip(w) - f.torso.global_position)
				if OS.get_environment("TRACE") != "" and case == "clear of him" and not hurt and i < 120:
					var tq := PD.quat_of(f.torso)
					var lead = f.hand_lead.R
					var wr: Weapon = f.weapons.R
					print("  yaw %.2f face %.2f t %3d lead %s hand %s tip %s touching %s/%s tilt %.3f vel %.3f" % [f.yaw, face, i, str((tq.inverse() * ((lead as Vector3) - f.torso.global_position)).snapped(Vector3(0.001, 0.001, 0.001))) if lead != null else "-", str((tq.inverse() * (f.hand_world("R") - f.torso.global_position)).snapped(Vector3(0.001, 0.001, 0.001))), str((tq.inverse() * (_tip(wr) - f.torso.global_position)).snapped(Vector3(0.001, 0.001, 0.001))), str(wr.get_colliding_bodies().map(func(b): return String(b.name))) if wr.contact_monitor else "?", str(f.weapons.L.get_colliding_bodies().map(func(b): return String(b.name))) if f.weapons.L and f.weapons.L.contact_monitor else "?", acos(clampf((tq * Vector3.UP).y, -1.0, 1.0)), f.torso.linear_velocity.length()])
			var out := []
			for s in ["R", "L"]:
				if (tips[s] as Array).size() > 60:
					var r := _shake(tips[s])
					out.append("%s shake %.1f mm step %.1f mm" % [s, r.x, r.y])
			print("YARD %-14s %-5s %s  blows on the keeper %d  keeper %.2f m away" % [case, "hurt" if hurt else "whole", "  ".join(out), hits[0], Vector2(kp.x - f.torso.global_position.x, kp.z - f.torso.global_position.z).length()])
			m.queue_free()
			for i in 3:
				await get_tree().physics_frame
	get_tree().quit()
