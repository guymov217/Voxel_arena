extends Node
## Over everything that can lie in his way, every way he can walk into it (user: he must never trip
## and fall over anything): a dead man, a man down but alive, dead beasts, a pile of two, a
## weapon or a shield, walked and run into forwards, backwards, sideways and slantwise.
## `-- --probe tripprobe`. TRIP: which obstacles; DIRS: which ways (fwd,back,side,diag).

const WHAT := ["deadman", "downman", "deadboar", "deadlion", "deadbear", "deadbull", "pile", "scutum", "spear", "axe"]
const DIRS := {"fwd": Vector2(0, 1), "back": Vector2(0, -1), "side": Vector2(1, 0), "diag": Vector2(0.7, 0.7)}

func _ready() -> void:
	var only := OS.get_environment("TRIP").split(",", false)
	var dirs := OS.get_environment("DIRS").split(",", false)
	var bad := 0
	var n := 0
	for what in WHAT:
		if not only.is_empty() and not only.has(what):
			continue
		for dn in DIRS:
			if not dirs.is_empty() and not dirs.has(dn):
				continue
			for run in [false, true]:
				var m := Match.new()
				add_child(m)
				m.setup({"mode": "training", "training": {"enemy": "none", "respawn": false}, "headless": true, "seed": 3})
				m.me.f.teleport(Vector3(-14, 0, 8))
				var e = m.spawn_fighter({"kind": "bot", "name": "V", "loadout": {"main": "gladius"}, "team": 1, "pos": Vector3(0, 0, 0), "yaw": 0.0})
				e.erase("bot")
				var f: Fighter = e.f
				var mv: Vector2 = DIRS[dn]
				var go := {"on": false}
				e.drive = func(_e):
					var inp := {"look": {"yaw": 0.0, "pitch": 0.0}}
					if go.on:
						inp.mx = mv.x
						inp.mz = mv.y
						inp.sprint = run
					return inp
				for i in 60:
					await get_tree().physics_frame
				var yq := Quaternion(Vector3.UP, f.yaw)
				# (mx is to his left: +x of his frame is his left hand side, as the input has it)
				var dir: Vector3 = (yq * Vector3(mv.x, 0, mv.y)).normalized()
				var across := dir.cross(Vector3.UP).normalized()
				var at: Vector3 = f.torso.global_position * Vector3(1, 0, 1) + dir * 2.2
				var ay := atan2(across.x, across.z)
				match what:
					"deadman", "downman":
						var d = m.spawn_fighter({"kind": "bot", "name": "D", "loadout": {}, "team": 1, "pos": at, "yaw": ay})
						d.erase("bot")
						d.f.set("spared", true)
						if what == "deadman":
							d.f.die("test")
						else:
							d.f.fall(99.0, true)
					"pile":
						for k in 2:
							var d = m.spawn_fighter({"kind": "bot", "name": "D%d" % k, "loadout": {}, "team": 1, "pos": at + across * (0.3 * k) + Vector3(0, 0.5 * k, 0), "yaw": ay + 0.6 * k})
							d.erase("bot")
							d.f.set("spared", true)
							d.f.die("test")
					"deadboar", "deadlion", "deadbear", "deadbull":
						var sp: String = String(what).substr(4)
						var b = m.spawn_beast({"beast": sp, "team": 1, "pos": at + dir * 0.4, "yaw": ay})
						b.f.die("test")
					_:
						var w := m.spawn_loose_weapon(Data.preset(what), at + Vector3(0, 0.3, 0))
						w.global_transform = Transform3D(Basis(Vector3.UP, ay + PI * 0.5) * Basis(Vector3.RIGHT, PI * 0.5), at + Vector3(0, 0.15, 0))
				for i in 240:
					await get_tree().physics_frame
				go.on = true
				var p0 := f.torso.global_position
				var fell := false
				var worst := 0.0
				for i in int(120 * 3.5):
					await get_tree().physics_frame
					fell = fell or f.state != "stand"
					var up: Vector3 = f.torso.global_transform.basis.y.normalized()
					worst = maxf(worst, rad_to_deg(acos(clampf(up.y, -1.0, 1.0))))
				var went := (f.torso.global_position - p0).dot(dir)
				n += 1
				var ok := not fell and went > 3.6
				if not ok:
					bad += 1
				print("TRIP %-9s %-5s %-4s fell=%-5s went=%5.2f tilt_max=%5.1f %s" % [what, dn, "run" if run else "walk", str(fell), went, worst, "" if ok else "  <-- BAD"])
				m.queue_free()
				await get_tree().physics_frame
	print("TRIP total %d bad %d" % [n, bad])
	get_tree().quit()
