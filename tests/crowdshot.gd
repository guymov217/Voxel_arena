extends Node
## Close-ups of the crowd in the stands (`-- --probe crowdshot`, needs a display).
func _ready() -> void:
	var out := OS.get_environment("SHOT_DIR")
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none"}, "seed": 3})
	m.set_process(false)
	for i in 30:
		await get_tree().process_frame
	var cam: Camera3D = m.cam
	cam.set_process(false)
	cam.set_physics_process(false)
	var shots := [[Vector3(0, 4.5, 10.5), Vector3(0, 4.2, 20.0), "crowd_front.png"], [Vector3(3.0, 5.5, 13.0), Vector3(6.0, 5.0, 19.0), "crowd_side.png"]]
	for ex in [0.2, 1.0]:
		m.arena.crowd_mat.set_shader_parameter("excitement", ex)
		for s in shots:
			cam.global_position = s[0]
			cam.look_at(s[1], Vector3.UP)
			cam.fov = 50.0
			for i in 12:
				await get_tree().process_frame
			get_viewport().get_texture().get_image().save_png(out.path_join("%s_%s" % [str(ex), s[2]]))
	get_tree().quit()
