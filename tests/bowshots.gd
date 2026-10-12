extends Node
## Bow and crossbow (`-- --probe bowshots`, needs a display): a player drawing a bow at a man
## (string back, arrow nocked, the off hand at the string), the loose, then a crossbow being
## cocked after a shot. Saves PNGs to SHOT_DIR.

func _save(name_: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(OS.get_environment("SHOT_DIR").path_join("bow_%s.png" % name_))
	print("saved ", name_)

func _ready() -> void:
	var menu = load("res://scripts/ui/menu.gd").new()
	add_child(menu)
	await get_tree().process_frame
	for w in ["bow", "crossbow"]:
		menu.start({"mode": "training", "training": {"enemy": "gladiator", "behaviour": "still", "weapon": "gladius"}, "loadout_override": {"main": w, "off": ""}})
		var m: Match = menu.match_
		var me: Dictionary = m.me
		var power := [false]
		me.drive = func(_e): return {"power": power[0], "aimAt": m.enemies()[0].f.torso.global_position, "look": {"yaw": 0.0, "pitch": 0.05}, "main": {"x": 0.2, "y": 0.3}}
		for i in 120:
			await get_tree().physics_frame
		var cam: Camera3D = m.cam
		m.set_process(false)
		cam.set_process(false)
		var f: Fighter = m.me.f
		var side := PD.quat_of(f.torso) * Vector3(1, 0, 0)
		cam.global_position = f.torso.global_position + side * -2.2 + Vector3(0, 0.5, 0.6)
		cam.look_at(f.torso.global_position + Vector3(0, 0.3, 0.4), Vector3.UP)
		await _save(w + "_rest")
		if w == "bow":
			power[0] = true
			for i in 120:
				await get_tree().physics_frame
			cam.global_position = f.torso.global_position + side * -2.2 + Vector3(0, 0.5, 0.6)
			cam.look_at(f.torso.global_position + Vector3(0, 0.3, 0.4), Vector3.UP)
			await _save("bow_drawn")
			print("draw ", f.weapons.R.get_meta("draw", 0.0), " off goal ", f.off_goal, " hand L ", f.hand_world("L"))
			power[0] = false
			for i in 30:
				await get_tree().physics_frame
			print("arrows ", m.items.list.filter(func(it): return String(it.type).begins_with("pot_arrow")).size())
		else:
			power[0] = true
			for i in 3:
				await get_tree().physics_frame
			power[0] = false
			for i in 90:
				await get_tree().physics_frame
			cam.global_position = f.torso.global_position + side * -2.2 + Vector3(0, 0.5, 0.6)
			cam.look_at(f.torso.global_position + Vector3(0, 0.3, 0.4), Vector3.UP)
			await _save("crossbow_cocking")
			print("reload ", f.weapons.R.get_meta("reload", 0.0), " off goal ", f.off_goal)
	get_tree().quit()
