extends Node
## What a sword cut costs on a creature (the sweep: a step of 50-100 ms when a blow landed, the
## first one on a dragon each bout): the same cut laid on its parts one after another, each
## timed, and the worst physics step after it. `-- --probe blowcost`. FOE (dragon), N (6).

func _ready() -> void:
	var foe := OS.get_environment("FOE") if OS.get_environment("FOE") != "" else "dragon"
	var n := int(OS.get_environment("N")) if OS.get_environment("N") != "" else 6
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none"}, "headless": true, "seed": 3, "decrees": [], "hazards": []})
	var e = m.spawn_beast({"beast": foe, "team": Match.ENEMY_TEAM, "pos": Vector3(0, 0.1, 6.0), "yaw": PI, "harmless": true}) if Data.beasts.has(foe) else m.spawn_fighter(m.enemy_spec({"e": foe}, 0, 1))
	var b = e.f
	for i in 120:
		await get_tree().physics_frame
	var parts: Array = b.parts.filter(func(p): return not p.severed)
	for k in n:
		var p: VoxelPart = parts[k % parts.size()]
		var dir: Vector3 = (p.global_position - m.me.f.torso.global_position).normalized()
		var t0 := Time.get_ticks_usec()
		var res: Dictionary = b.apply_hit(p, {"impulse": 30.0, "type": "edge", "hardness": 0.8, "sharpness": 0.8, "point": p.global_position - dir * p.half_ext.length() * 0.5, "dir": dir, "axis": Vector3.UP, "edge": dir.cross(Vector3.UP).normalized(), "heavy": 0.2, "weapon": true, "mass": 1.2})
		var t1 := Time.get_ticks_usec()
		Combat.current.hit.emit({"kind": "hit", "p": p.global_position, "dir": dir, "J": 30.0, "type": "edge", "char": b, "part": p, "attacker": m.me.f, "res": res, "killed": false})
		var t2 := Time.get_ticks_usec()
		var worst := 0.0
		var prev := Time.get_ticks_usec()
		for s in 30:
			await get_tree().physics_frame
			var now := Time.get_ticks_usec()
			worst = maxf(worst, (now - prev) / 1000.0)
			prev = now
		var removed := 0
		for r in res.get("removed", []):
			removed += (r.indices as Array).size()
		print("blow %d on %-10s apply_hit %6.1f ms, hit signal %6.1f ms, worst step after %5.1f ms, voxels %d%s" % [k + 1, p.part_name, (t1 - t0) / 1000.0, (t2 - t1) / 1000.0, worst, removed, " (severed)" if not (res.get("severed", []) as Array).is_empty() else ""])
	get_tree().quit()
