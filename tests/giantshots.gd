extends Node
## The giants of myth on show (`-- --probe giantshots`, needs a display): the Cyclops, the
## Minotaur, a troll and the Titan, face on and three-quarter. PNGs go to SHOT_DIR.

func _ready() -> void:
	var out := OS.get_environment("SHOT_DIR")
	for k in ["cyclops", "minotaur", "troll", "titan"]:
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
		m.me.f.teleport(Vector3(0, 0, -12))
		for i in 120:
			await get_tree().physics_frame
		var f: Fighter = e.f
		for v in [["f", Vector3(0.0, 0.35, -1.0)], ["q", Vector3(0.7, 0.45, -0.8)]]:
			var c: Vector3 = f.head.global_position
			m.cam.fov = 40.0
			m.cam.global_position = c + (v[1] as Vector3).normalized() * 0.9 * f.S
			m.cam.look_at(c, Vector3.UP)
			await get_tree().process_frame
			await get_tree().process_frame
			get_viewport().get_texture().get_image().save_png(out.path_join("giant_%s_%s.png" % [k, v[0]]))
		m.queue_free()
		await get_tree().process_frame
	get_tree().quit()
