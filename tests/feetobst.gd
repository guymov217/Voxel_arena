extends Node
## Probe: a man walking and running over what lies on the arena sand (a dead man, a dead beast, a
## severed leg, a dropped sword, a low box): does he go over it on his feet or go down.
## OBST=name to run one; TRACE=1 prints the frames around a fall.

func _ready() -> void:
	var only := OS.get_environment("OBST")
	for what in ["man", "wolf", "lion", "leg", "sword", "axe", "box"]:
		if only != "" and only != what:
			continue
		for run in ([OS.get_environment("RUN") == "1"] if OS.get_environment("RUN") != "" else [false, true]):
			for off in ([float(OS.get_environment("OFF"))] if OS.get_environment("OFF") != "" else [0.0, 0.15, -0.15]):
				var m := Match.new()
				add_child(m)
				m.setup({"mode": "training", "training": {"enemy": "none"}, "headless": true, "seed": 3})
				m.me.f.teleport(Vector3(-12, 0, 0))
				var e = m.spawn_fighter({"kind": "bot", "name": "V", "loadout": {"main": "gladius"}, "team": 1, "pos": Vector3(0, 0, 0), "yaw": 0.0})
				e.erase("bot")
				var go := {"on": false, "yaw": 0.0}
				var f: Fighter = e.f
				e.drive = func(_e):
					if go.on:
						f.yaw = go.yaw
					return {"mz": 1.0, "sprint": run} if go.on else {}
				for i in 60:
					await get_tree().physics_frame
				var fwd := Vector3(sin(f.yaw), 0, cos(f.yaw))
				var side := Vector3(fwd.z, 0, -fwd.x)
				var at: Vector3 = f.torso.global_position * Vector3(1, 0, 1) + fwd * 3.0 + side * off
				match what:
					"man":
						var d = m.spawn_fighter({"kind": "bot", "name": "D", "loadout": {"main": "gladius"}, "team": 1, "pos": at, "yaw": f.yaw + PI * 0.5})
						d.erase("bot")
						d.drive = func(_e): return {}
						d.f.die("test")
					"wolf", "lion":
						var b = m.spawn_beast({"beast": what, "team": 1, "pos": at, "yaw": f.yaw + PI * 0.5})
						b.f.die("test")
					"leg", "sword", "axe":
						var d = m.spawn_fighter({"kind": "bot", "name": "D", "loadout": {"main": "gladius" if what != "axe" else "axe"}, "team": 1, "pos": at + Vector3(0, 0, 0) + side * 3.0, "yaw": 0.0})
						d.erase("bot")
						d.drive = func(_e): return {}
						for i in 30:
							await get_tree().physics_frame
						if what == "leg":
							var th: VoxelPart = d.f.by_name["thighL"]
							d.f.detach_limb(th, {"removed": [], "severed": []})
							for p in [th, d.f.by_name["shinL"]]:
								p.global_transform = Transform3D(Basis(Vector3.FORWARD, PI * 0.5).rotated(Vector3.UP, f.yaw + PI * 0.5), at + Vector3(0, 0.1, 0) + side * (0.2 if p == th else -0.25))
								p.linear_velocity = Vector3.ZERO
						else:
							var w: Weapon = d.f.release("R")
							if w:
								w.global_transform = Transform3D(Basis(Vector3.FORWARD, PI * 0.5).rotated(Vector3.UP, f.yaw + PI * 0.5), at + Vector3(0, 0.1, 0))
								w.linear_velocity = Vector3.ZERO
						d.f.teleport(at + side * 6.0)
					"box":
						var st := StaticBody3D.new()
						var cs := CollisionShape3D.new()
						var bx := BoxShape3D.new()
						bx.size = Vector3(0.5, 0.2, 0.4)
						cs.shape = bx
						st.add_child(cs)
						m.add_child(st)
						st.global_transform = Transform3D(Basis(Vector3.UP, f.yaw), at + Vector3(0, 0.1, 0))
				for i in 90:
					await get_tree().physics_frame
				if OS.get_environment("FREEZE") != "":
					for en in m.entities:
						var c = en.f
						if is_instance_valid(c) and c != f and c.get("state") == "dead":
							for p in c.parts:
								if not p.severed:
									p.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
									p.freeze = true
				go.yaw = f.yaw
				fwd = Vector3(sin(f.yaw), 0, cos(f.yaw))
				go.on = true
				var p0 := f.torso.global_position
				var fell := -1
				for i in 120 * 3:
					await get_tree().physics_frame
					if f.state != "stand" and fell < 0:
						fell = i
					if OS.get_environment("TRACE") != "" and i % 6 == 0 and fell < 0:
						var up_w := PD.quat_of(f.torso) * Vector3.UP
						var sl: Vector3 = f.by_name["shinL"].global_transform * Vector3(0, -4 * Fighter.V * f.S, 0)
						var sr: Vector3 = f.by_name["shinR"].global_transform * Vector3(0, -4 * Fighter.V * f.S, 0)
						print("   t%d at %.2f tilt %.2f y %.2f gr %.2f  L %s %.2f/%.2f aY %.2f  R %s %.2f/%.2f aY %.2f  v %.2f" % [i, (f.torso.global_position - p0).dot(fwd), acos(clampf(up_w.y, -1, 1)), f.torso.global_position.y, f.ground_level, f.feet.L.swing, (sl - p0).dot(fwd), sl.y, (f.feet.L.anchor as Vector3).y, f.feet.R.swing, (sr - p0).dot(fwd), sr.y, (f.feet.R.anchor as Vector3).y, Vector2(f.torso.linear_velocity.x, f.torso.linear_velocity.z).length()])
				var went := (f.torso.global_position - p0).dot(fwd)
				print("OBST %-6s %s off %+.2f: %s, went %.1f m" % [what, "run " if run else "walk", off, ("FELL at %.2fs" % (fell / 120.0)) if fell >= 0 else "on his feet", went])
				m.queue_free()
				await get_tree().physics_frame
	get_tree().quit()
