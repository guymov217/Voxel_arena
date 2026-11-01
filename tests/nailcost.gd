extends Node
## Where a nail pot's cost goes (nailprof.gd: the steps after it bursts on a man): each step
## after the burst, then (NAIL_BYHAND=1) each queued nail wound dealt by hand, its apply_hit,
## report_hit and wound timed on their own. NAIL_AWAY=1: the hail where nobody stands (the
## nails' flight alone). `-- --probe nailcost`.

func _ms(t0: int) -> float:
	return (Time.get_ticks_usec() - t0) / 1000.0

func _ready() -> void:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none", "respawn": false}, "headless": OS.get_environment("NAIL_HEADLESS") != "0", "seed": 3})
	m.me.f.teleport(Vector3(-6, 0, 0))
	var e = m.spawn_fighter({"kind": "bot", "name": "D", "loadout": {"main": "gladius"}, "team": 1, "pos": Vector3(0, 0, 0), "yaw": PI * 0.5})
	e.erase("bot")
	e.drive = func(_e): return {}
	for i in 120:
		await get_tree().physics_frame
	var th = m.throwables
	for round in 3:
		var p: Vector3 = e.f.torso.global_position + Vector3(-0.35, 0.1, 0)
		if OS.get_environment("NAIL_AWAY") == "1":
			p = Vector3(-3, 1.0, 6)   # nobody near: the hail alone, no wounds
		th.explode("pot_nail", p, m.me.f, Vector3(1, 0, 0))
		var due: Array = []
		var steps := []
		var t_prev := Time.get_ticks_usec()
		for i in 12:
			await get_tree().physics_frame
			steps.append("%.1f" % _ms(t_prev))
			if OS.get_environment("NAIL_BYHAND") == "1":
				due.append_array(th.nail_hits_due)
				th.nail_hits_due.clear()
			t_prev = Time.get_ticks_usec()
		print("ROUND %d: %d nails in the air, %d nail wounds taken by hand, D alive %s; steps after the burst:" % [round, th.flying_nails.size(), due.size(), str(e.f.alive)])
		for st in steps.slice(0, 9):
			print("    STEP %s" % st)
		for q in due:
			var c = q[0]
			var part = q[1]
			if not is_instance_valid(c) or not is_instance_valid(part) or part.severed or not c.alive:
				print("  skipped (gone, severed or dead)")
				continue
			var gt: Transform3D = part.global_transform
			var entry: Vector3 = gt * (q[2] as Vector3)
			var hd: Vector3 = (gt.basis.orthonormalized() * (q[3] as Vector3)).normalized()
			var owner_ = q[4] if is_instance_valid(q[4]) else null
			var was: int = part.alive_count
			var t0 := Time.get_ticks_usec()
			var res: Dictionary = c.apply_hit(part, {"impulse": 3.6, "type": "point", "hardness": 1.0, "sharpness": 1.0, "point": entry + hd * 0.01, "dir": hd, "axis": hd, "wsz": 0.5 / maxf(1.0, c.S), "weapon": true})
			var t_hit := _ms(t0)
			t0 = Time.get_ticks_usec()
			m.report_hit({"kind": "hit", "p": entry, "dir": hd, "J": 3.6, "type": "point", "char": c, "part": part, "attacker": owner_ if owner_ != c else null, "res": res, "killed": not c.alive, "blast": true})
			var t_rep := _ms(t0)
			t0 = Time.get_ticks_usec()
			part.bleed += 0.2 / maxf(1.0, c.S)
			if part.alive_count == was:
				part.wound(q[2], 0.02 * c.S, "blood")
			var t_wound := _ms(t0)
			print("  %-9s took %2d voxels: apply_hit %.1f ms  report_hit %.1f  wound %.1f" % [part.part_name, was - part.alive_count, t_hit, t_rep, t_wound])
		t_prev = Time.get_ticks_usec()
		var after := []
		for i in 6:
			await get_tree().physics_frame
			after.append(snappedf(_ms(t_prev), 0.1))
			t_prev = Time.get_ticks_usec()
		print("  steps after: %s" % str(after))
		for i in 102:
			await get_tree().physics_frame
	get_tree().quit()
