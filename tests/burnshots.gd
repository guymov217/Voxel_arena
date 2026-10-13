extends Node
## Fire and poison on each kind of surface (`-- --probe burnshots`, needs a display): weapons of
## wood and of iron lying in a fire and in acid, a beast's fur alight, a man burning and
## poisoned, food in the flames. PNGs go to SHOT_DIR as burn_<view>.png.

func _save(name_: String) -> void:
	for i in 3:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(OS.get_environment("SHOT_DIR").path_join("burn_%s.png" % name_))
	print("saved ", name_)

func _ready() -> void:
	var menu = load("res://scripts/ui/menu.gd").new()
	add_child(menu)
	await get_tree().process_frame
	menu.start({"mode": "training", "training": {"enemy": "gladiator", "behaviour": "stand", "weapon": "gladius"}})
	var m: Match = menu.match_
	for i in 60:
		await get_tree().physics_frame
	var cam: Camera3D = m.cam
	cam.set_process(false)
	# Two pools away from everyone: fire on the left, acid on the right, weapons and food in each.
	var fz := Vector3(-3.0, 0, -8.0)
	var az := Vector3(3.0, 0, -8.0)
	m.throwables.add_zone("fire", fz, 1.3, 60.0)
	m.throwables.add_zone("acid", az, 1.3, 60.0)
	for base in [fz, az]:
		m.spawn_loose_weapon(Data.preset("spear"), base + Vector3(-0.4, 0.08, 0.2))
		m.spawn_loose_weapon(Data.preset("roundShield") if Data.presets.has("roundShield") else Data.preset("scutum"), base + Vector3(0.5, 0.1, -0.2))
		m.spawn_loose_weapon(Data.preset("gladius"), base + Vector3(0.0, 0.08, 0.6))
		m.items.spawn("bread", base + Vector3(-0.6, 0.1, -0.5))
	var goat = m.spawn_beast({"beast": "goat", "team": 2, "pos": Vector3(0, 0.1, -10.5), "yaw": 0.0, "harmless": true})
	for i in 30:
		await get_tree().physics_frame
	if goat and goat.get("f"):
		var g = goat.f
		for p in g.parts.slice(0, 3):
			m.add_spot(g, p, "fire", 60.0, null, p.global_position)
	for i in 150:
		await get_tree().physics_frame
	m.set_process(false)
	cam.global_position = fz + Vector3(0.0, 1.5, 2.6)
	cam.look_at(fz + Vector3(0, 0.1, 0), Vector3.UP)
	await _save("fire_wood_metal")
	cam.global_position = az + Vector3(0.0, 1.5, 2.6)
	cam.look_at(az + Vector3(0, 0.1, 0), Vector3.UP)
	await _save("acid_wood_metal")
	if goat and goat.get("f"):
		var gp: Vector3 = goat.f.parts[0].global_position
		cam.global_position = gp + Vector3(1.4, 0.8, 1.6)
		cam.look_at(gp, Vector3.UP)
		await _save("fur")
	get_tree().quit()
