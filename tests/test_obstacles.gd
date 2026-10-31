extends Node
## He walks and runs on over whatever lies a little above the sand (user: every object a little
## off the ground threw him down): a shield lying flat, a sword, a mace, a low kerb, a step.

var t

func _box(m: Match, at: Vector3, yaw: float, size: Vector3) -> StaticBody3D:
	var b := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = size
	cs.shape = bx
	b.add_child(cs)
	m.add_child(b)
	b.global_transform = Transform3D(Basis(Vector3.UP, yaw), at + Vector3(0, size.y * 0.5, 0))
	return b

func test_he_walks_on_over_what_lies_in_his_way() -> void:
	var only := OS.get_environment("ONLY")
	for what in ["roundShield", "scutum", "longsword", "mace", "kerb", "step", "plank"]:
		if only != "" and not only.split(",").has(what):
			continue
		for run in [false, true]:
			var m := Match.new()
			add_child(m)
			m.setup({"mode": "training", "training": {"enemy": "none", "respawn": false}, "headless": true, "seed": 3})
			m.me.f.teleport(Vector3(-12, 0, 0))
			var e = m.spawn_fighter({"kind": "bot", "name": "V", "loadout": {"main": "gladius"}, "team": 1, "pos": Vector3(0, 0, 0), "yaw": 0.0})
			e.erase("bot")
			var f: Fighter = e.f
			var go := {"on": false, "yaw": 0.0}
			e.drive = func(_e):
				if go.on:
					f.yaw = go.yaw
				return {"mz": 1.0, "sprint": run} if go.on else {}
			for i in 60:
				await get_tree().physics_frame
			var fwd := Vector3(sin(f.yaw), 0, cos(f.yaw))
			var at: Vector3 = f.torso.global_position * Vector3(1, 0, 1) + fwd * 2.5
			match what:
				"kerb":
					_box(m, at, f.yaw, Vector3(3.0, 0.12, 0.5))
				"step":
					_box(m, at + fwd * 0.8, f.yaw, Vector3(3.0, 0.22, 2.0))
				_:
					# Lying across his way, flat on the sand, as it fell.
					var w := m.spawn_loose_weapon(Data.preset(what), at + Vector3(0, 0.3, 0))
					w.global_transform = Transform3D(Basis(Vector3.UP, f.yaw + PI * 0.5) * Basis(Vector3.RIGHT, PI * 0.5), at + Vector3(0, 0.15, 0))
			for i in 90:
				await get_tree().physics_frame
			go.yaw = f.yaw
			go.on = true
			var p0 := f.torso.global_position
			var fell := false
			var low := INF
			for i in 120 * 3:
				await get_tree().physics_frame
				fell = fell or f.state != "stand"
				low = minf(low, f.torso.global_position.y)
			var went := (f.torso.global_position - p0).dot(fwd)
			print("%s %s: fell=%s went=%.2f low=%.2f" % [what, "run" if run else "walk", fell, went, low])
			t.check(not fell and went > 4.0, "%s over a %s: on his feet (%s), past it (%.1f m)" % ["running" if run else "walking", what, not fell, went])
			m.queue_free()
			await get_tree().physics_frame
