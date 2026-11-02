extends Node
## What the blow that takes a limb off costs (the sweep: a 71 ms step when a gladius took a
## gorilla's leg off, 104 before): cuts laid at one spot of a limb until it is off, each timed,
## the severing one with the worst physics step after it. `-- --probe severcost`. FOE (gorilla),
## PART (legFL), N (40).

func _ready() -> void:
	var foe := OS.get_environment("FOE") if OS.get_environment("FOE") != "" else "gorilla"
	var pn := OS.get_environment("PART") if OS.get_environment("PART") != "" else "legFL"
	var n := int(OS.get_environment("N")) if OS.get_environment("N") != "" else 40
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none"}, "headless": true, "seed": 3, "decrees": [], "hazards": []})
	m.me.f.teleport(Vector3(12, 0, 12))
	var e = m.spawn_beast({"beast": foe, "team": Match.ENEMY_TEAM, "pos": Vector3(0, 0.1, 6.0), "yaw": PI, "harmless": true})
	var b: Beast = e.f
	for i in 60:
		await get_tree().physics_frame
	var part: VoxelPart = b.by_name[pn]
	for k in n:
		if part.severed or not is_instance_valid(part):
			break
		var dir: Vector3 = (part.global_transform.basis * Vector3.RIGHT).normalized()
		var pt: Vector3 = part.global_position - dir * part.half_ext.x
		var t0 := Time.get_ticks_usec()
		var res: Dictionary = b.apply_hit(part, {"impulse": 45.0, "type": "edge", "hardness": 0.8, "sharpness": 0.9, "point": pt, "dir": dir, "axis": part.global_transform.basis * Vector3.FORWARD, "edge": dir, "heavy": 0.5, "weapon": true, "mass": 1.5})
		var t1 := Time.get_ticks_usec()
		Combat.current.hit.emit({"kind": "hit", "p": pt, "dir": dir, "J": 45.0, "type": "edge", "char": b, "part": part, "attacker": m.me.f, "res": res, "killed": false})
		var t2 := Time.get_ticks_usec()
		var worst := 0.0
		var prev := Time.get_ticks_usec()
		for s in 20:
			await get_tree().physics_frame
			var now := Time.get_ticks_usec()
			worst = maxf(worst, (now - prev) / 1000.0)
			prev = now
		var sev: Array = res.get("severed", [])
		print("cut %2d apply_hit %6.1f ms, signal %5.1f ms, worst step after %5.1f ms%s" % [k + 1, (t1 - t0) / 1000.0, (t2 - t1) / 1000.0, worst, (" SEVERED " + str(sev.map(func(p): return p.part_name if p is VoxelPart else str(p)))) if not sev.is_empty() else ""])
	get_tree().quit()
