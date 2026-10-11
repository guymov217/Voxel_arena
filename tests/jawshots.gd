extends Node
## Jaws and breath (`-- --probe jawshots`, needs a display): a few creatures beside a gladiator
## with their mouths shut, then wide open, then the dragon breathing fire, each saved close up.
## Then a lion bites the man for real and the wound and the piece it tore out are saved.

func _shot(cam: Camera3D, out: String, name_: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(out.path_join(name_ + ".png"))
	print("saved ", name_)

func _ready() -> void:
	var out := OS.get_environment("SHOT_DIR")
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none"}, "decrees": [], "hazards": []})
	m.set_process(false)
	var cam: Camera3D = m.cam
	var man: Fighter = m.me.f
	man.teleport(Vector3(0, 0, -6))
	for sp in (OS.get_environment("SHOT_ONLY").split(",", false) if OS.get_environment("SHOT_ONLY") != "" else PackedStringArray(["lion", "crocodile", "wolf", "bear", "dragon"])):
		var e = m.spawn_beast({"beast": sp, "team": Match.ENEMY_TEAM, "pos": Vector3(0, 0.1, 3.0), "yaw": -PI * 0.5, "harmless": true})
		var b: Beast = e.f
		b.sp = b.sp.duplicate(); b.sp.speed = 0.0; b.sp.lunge = 0.0
		b.target = null
		for i in 90:
			await get_tree().physics_frame
		var h: VoxelPart = b.head
		var c: Vector3 = h.global_position
		var side := PD.quat_of(b.torso) * Vector3(1, 0, 0)
		cam.fov = 40.0
		cam.global_position = c + side * (1.0 + h.half_ext.length() * 3.0) + Vector3(0, 0.15, 0)
		cam.look_at(c, Vector3.UP)
		await _shot(cam, out, "jaw_%s_shut" % sp)
		b.jaw_t = Beast.JAW_T * 0.5
		for i in 12:
			b.jaw_t = Beast.JAW_T * 0.5
			await get_tree().process_frame
		b.breath_t = 1.0
		await _shot(cam, out, "jaw_%s_open" % sp)
		var hq := PD.quat_of(h)
		c = h.global_position
		cam.global_position = c + hq * Vector3(0.35, 0.1, 1.0).normalized() * (h.half_ext.length() * 3.2 + 0.3)
		cam.look_at(c, Vector3.UP)
		b.breath_t = 1.0
		await _shot(cam, out, "jaw_%s_front" % sp)
		print(sp, " jaw ", h.jaw_pivot != null, " angle %.2f" % h.jaw_angle, " alive ", b.alive, " mode ", b.ai.mode, " jt ", b.jaw_t, " hug ", b.hug, " bt ", b.breath_t)
		if sp == "dragon":
			b.ai.breath_cool = 0.0
			b._breathe()
			cam.global_position = c + side * 9.0 + Vector3(0, 2.5, 0)
			cam.look_at(c + PD.quat_of(b.torso) * Vector3(0, -0.5, 4.0), Vector3.UP)
			for i in 20:
				m._update_breaths(1.0 / 60.0)
				await get_tree().process_frame
			await _shot(cam, out, "breath_dragon")
		m.entities.erase(e)
		m.combat.fighters.erase(b)
		b.queue_free()
		await get_tree().physics_frame
	# A real bite on the man's arm.
	man.teleport(Vector3(0, 0, 0))
	var le = m.spawn_beast({"beast": "lion", "team": Match.ENEMY_TEAM, "pos": Vector3(0, 0.1, 2.6), "yaw": PI})
	var lion: Beast = le.f
	lion.target = man
	var bites := []
	m.combat.hit.connect(func(hh): if hh.attacker == lion and hh.get("bite", false): bites.append(hh))
	for i in 120 * 8:
		man.blood = 100.0
		await get_tree().physics_frame
		if bites.size() >= 2:
			break
	for hh in bites:
		print("bite on %s: J %.1f removed %d torn %s mouthful %s" % [hh.part.part_name, hh.J, hh.res.removed.reduce(func(a, r): return a + r.indices.size(), 0), hh.res.get("torn", 0), hh.res.get("mouthful", false)])
	if not bites.is_empty():
		var p: VoxelPart = bites[0].part
		cam.global_position = p.global_position + Vector3(-1.4, 0.9, -1.4)
		cam.look_at(p.global_position, Vector3.UP)
		await _shot(cam, out, "bite_wound")
		var lh: VoxelPart = lion.head
		cam.global_position = lh.global_position + PD.quat_of(lion.torso) * Vector3(2.2, 0.6, 1.6)
		cam.look_at(lh.global_position, Vector3.UP)
		await _shot(cam, out, "bite_mouthful")
	print("chunks ", Chunk.all.size())
	get_tree().quit()
