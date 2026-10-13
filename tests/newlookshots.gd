extends Node
## The newer things in the voxel look (`-- --probe newlookshots`, needs a display): the armourer's
## pieces worn, the coated blades, a firebomb's splash and its pools. PNGs go to SHOT_DIR.

func _save(name_: String) -> void:
	for i in 3:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(OS.get_environment("SHOT_DIR").path_join("new_%s.png" % name_))
	print("saved ", name_)

func _ready() -> void:
	var menu = load("res://scripts/ui/menu.gd").new()
	add_child(menu)
	await get_tree().process_frame
	menu.start({"mode": "training", "training": {"enemy": "gladiator", "behaviour": "stand", "weapon": "gladius"}})
	var m: Match = menu.match_
	for i in 120:
		await get_tree().physics_frame
	var cam := Camera3D.new()
	m.add_child(cam)
	cam.current = true
	var foe = null
	for e in m.entities:
		if e != m.me:
			foe = e.f
	var me = m.me.f
	foe.set_armor_pieces(["steelLorica", "murmilloHelm", "pauldrons", "steelGreaves", "manicaL"])
	me.set_armor_pieces(["leatherJerkin", "leatherCap", "vambraces", "cuisses"])
	for i in 30:
		await get_tree().physics_frame
	m.set_process(false)
	var t: Vector3 = foe.torso.global_position
	cam.global_position = t + Vector3(0.3, 0.3, 2.4)
	cam.look_at(t + Vector3(0, -0.1, 0), Vector3.UP)
	await _save("armour_steel")
	t = me.torso.global_position
	var fwd: Vector3 = (foe.torso.global_position - t).normalized()
	cam.global_position = t + fwd * 1.9 + Vector3(0.6, 0.2, 0)
	cam.look_at(t + Vector3(0, -0.1, 0), Vector3.UP)
	await _save("armour_leather")
	# Three coated blades laid on a rack of air beside him: venom, fire, frost.
	var base: Vector3 = foe.torso.global_position + Vector3(2.5, 0, 0)
	var i := 0
	for c in ["venom", "fire", "frost"]:
		var d: Dictionary = Data.preset("gladius").duplicate(true)
		d["imbue"] = c
		var w := Weapon.new()
		w.freeze = true
		m.add_child(w)
		w.setup(d, 1.6)
		w.global_transform = Transform3D(Basis(Vector3.FORWARD, 0.15), base + Vector3(i * 0.45, 0.2, 0))
		i += 1
	m.set_process(true)
	for k in 40:
		await get_tree().physics_frame
	m.set_process(false)
	cam.global_position = base + Vector3(0.45, 0.6, 1.9)
	cam.look_at(base + Vector3(0.45, 0.5, 0), Vector3.UP)
	await _save("coatings")
	# A firebomb bursting on the sand and one of venom: the splash, the pools and the smoke.
	m.set_process(true)
	var p: Vector3 = foe.torso.global_position + Vector3(-1.5, 0.05, 1.2)
	m.throwables.splash_burning(p, Vector3(0.6, 0, 0.8).normalized(), 48, null, null, null, "fire")
	m.throwables.splash_burning(p + Vector3(2.6, 0, 0.4), Vector3(-0.3, 0, 1).normalized(), 48, null, null, null, "acid")
	for k in 25:
		await get_tree().physics_frame
	cam.global_position = p + Vector3(1.3, 1.6, 3.6)
	cam.look_at(p + Vector3(1.3, 0.3, 0.3), Vector3.UP)
	await _save("splash_flight")
	for k in 220:
		await get_tree().physics_frame
	await _save("splash_pools")
	get_tree().quit()
