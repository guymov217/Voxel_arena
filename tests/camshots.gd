extends Node
## The fight camera at the moment my blows land (`-- --probe camshots`, needs a display): a bot
## fights for me against a gladiator, the view turned to the foe as a player would, and a frame is
## saved at each of the first blows that land. SHOT_DIR; (compare against git stash for the old camera).

func _ready() -> void:
	var out := OS.get_environment("SHOT_DIR")
	var tag := OS.get_environment("SHOT_TAG")
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "gladiator", "weapon": "gladius", "behaviour": "fights", "difficulty": 0.6, "immortal": true}, "seed": 4, "decrees": [], "hazards": [], "loadout": {"main": "axe", "off": ""}, "autopilot": true, "autopilot_diff": 0.9})
	var last_t := -1.0
	var shots := 0
	for i in 120 * 40:
		await get_tree().physics_frame
		var ne = m.nearest_enemy(m.me)
		if ne and m.input:
			var d: Vector3 = ne.f.torso.global_position - m.me.f.torso.global_position
			m.input.look_yaw = atan2(d.x, d.z)
			m.input.look_pitch = -0.15
		if not m.my_hit.is_empty() and float(m.my_hit.t) != last_t:
			last_t = float(m.my_hit.t)
			if m.time - float(m.my_hit.t) < 0.05 and m.time > 3.0:
				await RenderingServer.frame_post_draw
				get_viewport().get_texture().get_image().save_png(out.path_join("cam_%s_%02d.png" % [tag, shots]))
				shots += 1
				if shots >= 6:
					break
	get_tree().quit()
