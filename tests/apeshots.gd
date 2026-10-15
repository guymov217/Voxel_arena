extends Node
## The gorilla's blows in motion (`-- --probe apeshots`, needs a display): it fights a man and a
## frame is saved at the top of each kind of blow's wind-up and as it lands. PNGs to SHOT_DIR.

func _ready() -> void:
	var out := OS.get_environment("SHOT_DIR")
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none"}, "decrees": [], "hazards": [], "seed": 4})
	m.set_process(false)
	var man: Fighter = m.me.f
	man.teleport(Vector3(0, 0, 0))
	man.mods.toughness = 4.0
	var e = m.spawn_beast({"beast": "gorilla", "team": Match.ENEMY_TEAM, "pos": Vector3(0, 0.1, 2.6), "yaw": PI})
	var b: Beast = e.f
	var seen := {}
	var cam: Camera3D = m.cam
	cam.fov = 42.0
	for i in 40 * 120:
		man.blood = 100.0
		man.head.hp = maxf(man.head.hp, 40.0)
		man.torso.hp = maxf(man.torso.hp, 40.0)
		b.target = man
		await get_tree().physics_frame
		for n in ["legFL", "legFR"]:
			var arm: VoxelPart = b.by_name[n]
			var k := String(arm.get_meta("ape", ""))
			if k == "":
				continue
			var phase := "wind" if float(b.wind.get(arm, 0.0)) > 0.0 else "blow"
			var key := k + "_" + phase
			if seen.has(key):
				continue
			# Catch the pose at its fullest: the end of the wind-up, the middle of the blow.
			if phase == "wind" and float(b.wind.get(arm, 0.0)) > 0.06:
				continue
			if phase == "blow" and float(b.strikes.get(arm, 0.0)) > 0.22:
				continue
			seen[key] = true
			var bp: Vector3 = b.torso.global_position
			var mp: Vector3 = man.torso.global_position
			var c := Vector3((bp.x + mp.x) * 0.5, 1.3, (bp.z + mp.z) * 0.5)
			var axis := Vector3(bp.x - mp.x, 0, bp.z - mp.z).normalized()
			var side := axis.cross(Vector3.UP)
			# From the side, a little toward the man's side of the pair, well back.
			cam.global_position = c + side * 7.0 - axis * 2.0 + Vector3(0, 1.4, 0)
			cam.look_at(c, Vector3.UP)
			await get_tree().process_frame
			await get_tree().process_frame
			get_viewport().get_texture().get_image().save_png(out.path_join("ape_%s.png" % key))
			print("saved ", key)
		if seen.size() >= 6:
			break
	print("kinds ", seen.keys())
	get_tree().quit()
