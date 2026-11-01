extends Node
## Two swords held out in front, standing still, the man turned every which way, in the yard and
## in the arena (yardtremor.gd found a twelve-a-second kick in the yard, facing one way and not
## another): how much each blade's tip shakes. `-- --probe facetremor`.

func _tip(w: Weapon) -> Vector3:
	return w.global_position + PD.quat_of(w) * Vector3(0, w.reach, 0)

func _ready() -> void:
	for mode in (["training"] if OS.get_environment("NOARMS") != "" or OS.get_environment("RAMP") != "" else ["yard", "training"]):
		for yaw in [0.0, -2.75, 1.0, PI]:
			var m := Match.new()
			add_child(m)
			m.setup({"mode": mode, "training": {"enemy": "none", "respawn": false}, "headless": true, "seed": 1, "decrees": [], "hazards": [], "loadout": {} if OS.get_environment("NOARMS") != "" else {"main": "gladius", "off": "gladius"}})
			var f: Fighter = m.me.f
			f.teleport(Vector3(-2.1, 0, -5.9))
			var noarms := OS.get_environment("NOARMS") != ""
			# RAMP=1: turned to it over a second, as a mouse turns him, not all at once.
			var ramp := [0.0]
			var slow := OS.get_environment("RAMP") != ""
			m.me.drive = func(_e):
				ramp[0] = minf(1.0, ramp[0] + 1.0 / 120.0)
				var yw: float = yaw * ramp[0] if slow else yaw
				return {"look": {"yaw": yw, "pitch": 0.0}} if noarms else {"main": {"x": 0.25, "y": 0.3}, "off": {"x": -0.25, "y": 0.3}, "look": {"yaw": yw, "pitch": 0.0}}
			for i in 240:
				await get_tree().physics_frame
			var yq := Quaternion(Vector3.UP, f.yaw)
			for sd in ["L", "R"]:
				var ft = f.feet[sd]
				if ft != null:
					print("  FOOT %s yaw %.2f planted at yaw %s swing %s anchor in body frame %s" % [sd, f.yaw, str(ft.get("yaw", "-")), str(ft.swing), str((yq.inverse() * ((ft.anchor as Vector3) - f.torso.global_position)).snapped(Vector3(0.01, 0.01, 0.01)))])
			var vmax := 0.0
			var kicks := 0
			var a := []
			for i in 360:
				await get_tree().physics_frame
				var v := f.torso.linear_velocity.length()
				vmax = maxf(vmax, v)
				if v > 0.1:
					kicks += 1
				a.append((_tip(f.weapons.R) if f.weapons.R else f.hand_world("R")) - f.torso.global_position)
			var hf := 0.0
			for i in range(15, a.size() - 15):
				var avg := Vector3.ZERO
				for j in range(i - 15, i + 16):
					avg += a[j]
				hf += (a[i] - avg / 31.0).length_squared()
			print("FACE %-8s yaw %5.2f  R shake %.1f mm  trunk fastest %.2f m/s, %d steps over 0.1 m/s" % [mode, yaw, sqrt(hf / float(a.size() - 30)) * 1000.0, vmax, kicks])
			m.queue_free()
			for i in 3:
				await get_tree().physics_frame
	get_tree().quit()
