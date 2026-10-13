extends Node
## The effects and small things (`-- --probe fxshots`, needs a display): blood, sparks, fire and
## poison on a fighter and on the sand, items thrown down from the stands, the hot potato's
## bomb, the crowd close up. PNGs go to SHOT_DIR as fx_<view>.png.

func _save(name_: String) -> void:
	for i in 3:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(OS.get_environment("SHOT_DIR").path_join("fx_%s.png" % name_))
	print("saved ", name_)

func _ready() -> void:
	var menu = load("res://scripts/ui/menu.gd").new()
	add_child(menu)
	await get_tree().process_frame
	menu.start({"mode": "training", "training": {"enemy": "gladiator", "behaviour": "stand", "weapon": "gladius"}})
	var m: Match = menu.match_
	for i in 120:
		await get_tree().physics_frame
	var cam: Camera3D = m.cam
	cam.set_process(false)
	m.set_process(false)
	var foe = null
	for e in m.entities:
		if e != m.me:
			foe = e.f
	var t: Vector3 = foe.torso.global_position
	# Fire on one arm, poison on the other, a pool of each on the sand next to him.
	m.add_spot(foe, foe.arm.R.upper, "fire", 30.0, null, foe.arm.R.upper.global_position)
	m.add_spot(foe, foe.arm.L.upper, "acid", 30.0, null, foe.arm.L.upper.global_position)
	m.throwables.add_zone("fire", Vector3(t.x + 1.4, 0, t.z + 0.6), 0.9, 30.0)
	m.throwables.add_zone("acid", Vector3(t.x - 1.5, 0, t.z + 0.4), 0.9, 30.0)
	for i in 60:
		await get_tree().physics_frame
	cam.global_position = t + Vector3(0.2, 0.6, 3.6)
	cam.look_at(t + Vector3(0, -0.3, 0), Vector3.UP)
	await _save("fire_poison")
	t = foe.torso.global_position
	cam.global_position = t + Vector3(0.0, 0.25, 1.6)
	cam.look_at(t + Vector3(0, 0.1, 0), Vector3.UP)
	await _save("body_close")
	# Bees on him, pools of oil and honey.
	foe.bee_timer = 30.0
	t = foe.torso.global_position
	m.throwables.add_zone("oil", Vector3(t.x + 1.1, 0, t.z + 1.0), 0.7, 30.0)
	m.throwables.add_zone("honey", Vector3(t.x - 1.1, 0, t.z + 1.0), 0.7, 30.0)
	m.set_process(true)
	for i in 60:
		await get_tree().physics_frame
	m.set_process(false)
	cam.global_position = t + Vector3(0.3, 0.7, 3.0)
	cam.look_at(t + Vector3(0, -0.4, 0), Vector3.UP)
	await _save("bees_pools")
	var sz: Dictionary = m.throwables.add_zone("sand", Vector3(t.x + 0.5, 0, t.z - 3.5), 3.2, 30.0)
	print("sand zone node ", sz.node, " children ", sz.node.get_child_count() if sz.node else -1)
	for i in 240:
		await get_tree().physics_frame
	m.fx.burst("dust", Vector3(t.x - 0.8, 0.05, t.z + 0.8), 60, Vector3.UP, 1.5)
	for i in 30:
		await get_tree().physics_frame
	cam.global_position = t + Vector3(-1.5, 1.4, 3.8)
	cam.look_at(Vector3(t.x + 0.3, 0.6, t.z - 2.5), Vector3.UP)
	await _save("sand")
	# Blood and sparks mid-flight, stains on the sand.
	for k in 5:
		m.fx.mark("blood", t + Vector3(randf_range(-1.2, 1.2), 0, randf_range(0.6, 1.8)), randf_range(0.4, 0.9))
	m.fx.burst("blood", t + Vector3(0, 0.2, 0.2), 120, Vector3(0.3, 0.8, 1).normalized(), 1.0)
	m.fx.burst("sparks", t + Vector3(0.3, 0.5, 0.3), 80, Vector3.UP, 1.0)
	for i in 8:
		await get_tree().process_frame
	await _save("blood_sparks")
	# Items from the stands lying on the sand, the bomb.
	var types := ["bread", "wine", "tomato", "banana", "coin", "rock", "pot_fire", "pot_thunder", "cheese", "bandage", "ball"]
	for i in types.size():
		m.items.spawn(types[i], Vector3(-2.0 + (i % 6) * 0.45, 0.12, -6.0 - (i / 6) * 0.5))
	var bomb := VoxelArt.place(m, "bomb", Vector3(1.0, 0.16, -6.2))
	for i in 30:
		await get_tree().physics_frame
	cam.global_position = Vector3(-0.2, 1.1, -4.3)
	cam.look_at(Vector3(-0.2, 0.0, -6.4), Vector3.UP)
	await _save("items")
	# The crowd close up.
	cam.global_position = Vector3(6.0, 2.6, 12.5)
	cam.look_at(Vector3(8.5, 3.6, 15.6), Vector3.UP)
	await _save("crowd")
	# The forge.
	m.queue_free()
	var f = load("res://scripts/ui/forge.gd").new()
	add_child(f)
	f.free_build = true
	f.open(Data.preset("gladius").duplicate(true), 0, func(_d, _c): pass)
	for i in 10:
		await get_tree().process_frame
	await _save("forge")
	get_tree().quit()
