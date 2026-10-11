extends Node
## The damage system on show (`-- --probe damageshots`, needs a display): a gladiator and a lion
## take sword cuts, axe chops and club blows through the game's own apply_hit, and the frame is
## saved close up so the cuts, dents, holes, chunks knocked off and limbs cut away can be seen.
## Prints the voxels each one lost and which parts came off.

func _ready() -> void:
	var out := OS.get_environment("SHOT_DIR")
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none"}, "decrees": [], "hazards": []})
	m.set_process(false)
	var cam: Camera3D = m.cam
	var me = m.spawn_fighter({"kind": "npc", "name": "Victim", "loadout": {"main": "", "off": ""}, "team": Match.ENEMY_TEAM, "pos": Vector3(-1.2, 0.02, 2.0), "yaw": 0.0})
	me.drive = func(_e): return {}
	var man: Fighter = me.f
	var lion = m.spawn_beast({"beast": "lion", "team": Match.ENEMY_TEAM, "pos": Vector3(2.0, 0.1, 2.5), "yaw": -PI * 0.5, "harmless": true}).f
	lion.sp = lion.sp.duplicate(); lion.sp.speed = 0.0; lion.sp.lunge = 0.0
	m.me.f.global_position = Vector3(0, 0, -12)
	for i in 120:
		await get_tree().physics_frame
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var blows := [
		[man, "upperArmR", "edge", 30.0, 0.9], [man, "torso", "edge", 26.0, 0.8], [man, "torso", "point", 28.0, 0.9],
		[man, "thighL", "blunt", 34.0, 0.0], [man, "head", "edge", 18.0, 0.8], [man, "forearmL", "edge", 45.0, 1.0],
		[lion, "beastBody", "edge", 40.0, 0.9], [lion, "beastBody", "blunt", 45.0, 0.0], [lion, "beastHead", "edge", 35.0, 0.8],
		[lion, "legFLLo", "edge", 60.0, 1.0], [lion, "tail", "edge", 40.0, 1.0],
	]
	var before := {}
	for f in [man, lion]:
		before[f] = f.parts.reduce(func(a, p): return a + p.alive_count, 0)
	for b in blows:
		var f = b[0]
		var part: VoxelPart = f.by_name[b[1]]
		if part.severed:
			continue
		var side := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.3, 0.3), 1.0).normalized()
		var p: Vector3 = part.global_position + PD.quat_of(part) * (side * part.half_ext * 0.95)
		var dir := (part.global_position - p).normalized()
		var axis := dir.cross(Vector3.UP).normalized() if b[2] == "edge" else dir
		var res: Dictionary = f.apply_hit(part, {"impulse": b[3], "type": b[2], "hardness": 0.9, "sharpness": b[4], "point": p, "dir": dir, "axis": axis if b[2] == "edge" else dir, "edge": dir, "heavy": 0.6 if b[3] > 40.0 else 0.2})
		if m.fx and not res.removed.is_empty():
			m.fx.burst("blood", p, 30, -dir)
		for i in 8:
			await get_tree().physics_frame
		# Close up on the wound, from the side it was struck.
		var c: Vector3 = part.global_position if not part.severed else part.global_position
		cam.fov = 40.0
		cam.global_position = c - dir * 0.9 + Vector3(0, 0.25, 0)
		cam.look_at(c, Vector3.UP)
		await get_tree().process_frame
		await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png(out.path_join("dmg_%02d_%s_%s.png" % [blows.find(b), f.display_name, b[1]]))
		print("blow %s %s %s: -%d voxels, cut off %s" % [f.display_name, b[1], b[2], res.removed.reduce(func(a, r): return a + r.indices.size(), 0), res.severed.map(func(q): return q.part_name)])
	for i in 90:
		await get_tree().physics_frame
	for f in [man, lion]:
		var now: int = f.parts.reduce(func(a, p): return a + p.alive_count, 0)
		print("%s lost %d voxels; off: %s; holes in %s" % [f.display_name, before[f] - now, f.parts.filter(func(p): return p.severed).map(func(p): return p.part_name), f.parts.filter(func(p): return not p.severed and p.alive_count < p.fx.size()).map(func(p): return p.part_name)])
	for f in [man, lion]:
		for p in f.parts:
			print("%s %s alive %d/%d vis %s mmi %s aabb %s pos %s sev %s" % [f.display_name, p.part_name, p.alive_count, p.fx.size(), p.visible, p.mmi.visible if p.mmi else null, p.mm.get_aabb() if p.mm else null, p.global_position, p.severed])
	for v in [["dmg_gladiator_a", man, Vector3(0.9, 1.3, 0.9)], ["dmg_gladiator_b", man, Vector3(-1.0, 1.1, -0.8)], ["dmg_lion", lion, Vector3(1.6, 1.4, 2.0)]]:
		var box := AABB(v[1].torso.global_position, Vector3.ZERO)
		for p in v[1].parts:
			if not p.severed:
				box = box.merge(AABB(p.global_position - p.half_ext, p.half_ext * 2.0))
		var c: Vector3 = box.get_center()
		cam.fov = 45.0
		cam.global_position = c + v[2].normalized() * (box.size.length() * 1.1 + 0.4)
		cam.look_at(c, Vector3.UP)
		await get_tree().process_frame
		await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png(out.path_join(v[0] + ".png"))
		print("saved ", v[0])
	get_tree().quit()
