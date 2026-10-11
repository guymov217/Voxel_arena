extends Node
## Creatures in action (`-- --probe actionshots`, needs a display): each species fights a
## gladiator who cannot die, and the frame is saved the moment one of its strikes starts (a bite,
## a sting, a swipe, a horn toss), from the side, so the animation can be checked by eye.
## SHOT_DIR, SHOT_ONLY (comma list) as in beastshots.

func _ready() -> void:
	var out := OS.get_environment("SHOT_DIR")
	var only := OS.get_environment("SHOT_ONLY").split(",", false)
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none"}, "decrees": [], "hazards": []})
	m.set_process(false)
	var cam: Camera3D = m.cam
	var man: Fighter = m.me.f
	if OS.get_environment("SHOT_TOUGH") != "":
		man.mods.toughness = 80.0
	# Unarmed, so whatever is missing from a beast in the shots is not a sword's work.
	if OS.get_environment("SHOT_UNARMED") != "":
		for side in ["R", "L"]:
			var w = man.release(side)
			if w:
				w.queue_free()
	var n := 0
	for sp in Data.beasts:
		n += 1
		if not only.is_empty() and not only.has(sp):
			continue
		man.teleport(Vector3(0, 0, 0))
		var e = m.spawn_beast({"beast": sp, "team": Match.ENEMY_TEAM, "pos": Vector3(0, 0.1, 3.5 + float(Data.beasts[sp].scale)), "yaw": PI})
		var f = e.f
		if not ("strikes" in f): f.set_meta("old", true)
		f.target = man
		f.ai.fly_cool = 999.0
		var shots := 0
		for i in 120 * 14:
			man.blood = 100.0
			await get_tree().physics_frame
			if not f.alive:
				break
			var fresh := false
			for p in (f.strikes if "strikes" in f else {}):
				if f.strikes[p] > 0.0 and f.strikes[p] < 0.2:
					fresh = true
			if (fresh or (not ("strikes" in f) and i % 400 == 200)) and shots < 3 and i % 6 == 0:
				var c: Vector3 = (f.torso.global_position + man.torso.global_position) * 0.5
				var span: float = f.torso.global_position.distance_to(man.torso.global_position) + f.torso.half_ext.length() * 2.0
				var side := Vector3(1, 0, 0) if shots % 2 == 0 else Vector3(-0.7, 0, 0.7).normalized()
				cam.fov = 45.0
				cam.global_position = c + side * (span * 1.3 + 1.5) + Vector3(0, span * 0.25 + 0.6, 0)
				cam.look_at(c, Vector3.UP)
				await get_tree().process_frame
				await get_tree().process_frame
				get_viewport().get_texture().get_image().save_png(out.path_join("act_%02d_%s_%d.png" % [n, sp, shots]))
				print("saved act_%02d_%s_%d %s head %.2f body %.2f lost %s" % [n, sp, shots, (f.strikes.keys().map(func(p): return p.part_name) if "strikes" in f else []), f.head.integrity, f.torso.integrity, f.parts.filter(func(p): return p.severed).map(func(p): return p.part_name)])
				shots += 1
		# And one close look at the man after the fight: his cuts, holes and lost pieces.
		if f.alive or true:
			var c2: Vector3 = man.torso.global_position
			cam.global_position = c2 + Vector3(1.6, 0.5, 1.6)
			cam.look_at(c2, Vector3.UP)
			await get_tree().process_frame
			await get_tree().process_frame
			get_viewport().get_texture().get_image().save_png(out.path_join("act_%02d_%s_man.png" % [n, sp]))
			print("man after %s: hp %.0f lost %s voxels %d/%d" % [sp, man.total_hp(), man.parts.filter(func(p): return p.severed).map(func(p): return p.part_name), man.parts.reduce(func(a, p): return a + p.alive_count, 0), man.parts.reduce(func(a, p): return a + p.fx.size(), 0)])
		print("done ", sp, " shots ", shots)
		m.entities.erase(e)
		m.combat.fighters.erase(f)
		f.queue_free()
		await get_tree().physics_frame
	get_tree().quit()
