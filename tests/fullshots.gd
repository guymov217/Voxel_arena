extends Node
## The giants of myth at full height (`-- --probe fullshots`, needs a display): the Titan, the
## troll and the Cyclops framed head to foot beside a man, face on and three-quarter. PNGs go to
## SHOT_DIR as full_<kind>_<view>.png.

func _ready() -> void:
	var out := OS.get_environment("SHOT_DIR")
	var kinds := OS.get_environment("SHOT_KINDS").split(",", false) if OS.get_environment("SHOT_KINDS") != "" else PackedStringArray(["titan", "troll", "cyclops"])
	for k in kinds:
		var m := Match.new()
		add_child(m)
		m.setup({"mode": "training", "training": {"enemy": "none"}, "decrees": [], "hazards": []})
		m.set_process(false)
		var spec: Dictionary = m.enemy_spec({"e": k}, 0, 1)
		spec.pos = Vector3(0, 0.1, 3)
		spec.yaw = PI
		var e = m.spawn_fighter(spec)
		e.erase("bot")
		e.drive = func(_e): return {"main": {"x": 0.0, "y": -0.9}, "off": {"x": 0.0, "y": -0.9}}
		# The man stands beside him for scale.
		m.me.f.teleport(Vector3(2.2, 0, 3.2))
		m.me.f.yaw = PI
		for i in 120:
			await get_tree().physics_frame
		var f: Fighter = e.f
		var box := AABB(f.torso.global_position, Vector3.ZERO)
		for p in f.parts:
			if is_instance_valid(p) and not p.severed:
				box = box.merge(AABB(p.global_position - p.half_ext, p.half_ext * 2.0))
		var c := box.get_center()
		var h := box.size.y
		for v in [["f", Vector3(0.0, 0.08, -1.0)], ["q", Vector3(0.75, 0.1, -0.75)]]:
			m.cam.fov = 38.0
			m.cam.global_position = c + (v[1] as Vector3).normalized() * (h * 1.75 + 1.5)
			m.cam.look_at(c, Vector3.UP)
			await get_tree().process_frame
			await get_tree().process_frame
			get_viewport().get_texture().get_image().save_png(out.path_join("full_%s_%s.png" % [k, v[0]]))
			print("saved full_%s_%s" % [k, v[0]])
		m.queue_free()
		await get_tree().process_frame
	get_tree().quit()
