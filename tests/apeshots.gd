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
	for i in 20 * 120:
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
			var c: Vector3 = (b.torso.global_position + man.torso.global_position) * 0.5 + Vector3(0, 0.6, 0)
			var side: Vector3 = (b.torso.global_position - man.torso.global_position).normalized().cross(Vector3.UP)
			cam.global_position = c + side * 5.5 + Vector3(0, 1.2, 0) - (b.torso.global_position - man.torso.global_position).normalized() * 1.5
			cam.look_at(c, Vector3.UP)
			await get_tree().process_frame
			await get_tree().process_frame
			get_viewport().get_texture().get_image().save_png(out.path_join("ape_%s.png" % key))
			print("saved ", key)
		if seen.size() >= 6:
			break
	print("kinds ", seen.keys())
	get_tree().quit()
