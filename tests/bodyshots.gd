extends Node
## A campaign body on show (`-- --probe bodyshots`, needs a display): scars, a peg leg, a blade
## arm, a hook, a lost eye; then the physician's screen. PNGs go to SHOT_DIR.

func _ready() -> void:
	var out := OS.get_environment("SHOT_DIR")
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none"}, "decrees": [], "hazards": []})
	m.set_process(false)
	var cam: Camera3D = m.cam
	var b := Body.empty()
	b.missing = ["shinL", "forearmR", "forearmL"]
	b.scars = {}
	var names := ["torso", "thighR", "upperArmL", "head"]
	for n in names:
		var lst := []
		var total := Body.voxel_count(n)
		for k in range(total / 3, total / 3 + total / 12):
			lst.append(k)
		b.scars[n] = lst
	b = Body.apply(Body.apply(Body.apply(b, "peg:shinL"), "blade:forearmR"), "hook:forearmL")
	b.eyes = {"R": "lost"}
	var e = m.spawn_fighter({"kind": "bot", "name": "Veteran", "loadout": {"main": "gladius", "off": "roundShield"}, "team": 0, "pos": Vector3(0, 0, 2), "yaw": PI, "body": b})
	e.erase("bot")
	e.drive = func(_e): return {"main": {"x": 0.2, "y": 0.3}}
	m.me.f.teleport(Vector3(0, 0, -10))
	for i in 150:
		await get_tree().physics_frame
	var f: Fighter = e.f
	for n in ["shinL", "forearmL", "forearmR", "torso", "thighR", "head"]:
		var pp: VoxelPart = f.by_name[n]
		print(n, " alive ", pp.alive_count, "/", pp.fx.size(), " prosthetic ", pp.prosthetic, " visible ", pp.visible, " mmi ", pp.mmi.visible)
	for v in [["body_front", Vector3(0.3, 0.3, -1.0), "torso", 1.5], ["body_legs", Vector3(0.8, 0.2, -0.6), "shinL", 1.1], ["body_hook", Vector3(-0.6, 0.2, -0.8), "forearmL", 0.8], ["body_back", Vector3(-0.4, 0.3, 1.0), "torso", 1.6]]:
		var c: Vector3 = f.by_name[v[2]].global_position
		cam.fov = 45.0
		cam.global_position = c + (v[1] as Vector3).normalized() * float(v[3])
		cam.look_at(c, Vector3.UP)
		await get_tree().process_frame
		await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png(out.path_join(v[0] + ".png"))
		print("saved ", v[0], " ", Body.summary(f.body))
	m.queue_free()
	await get_tree().process_frame
	var menu = load("res://scripts/ui/menu.gd").new()
	add_child(menu)
	await get_tree().process_frame
	var b2 := Body.empty()
	b2.missing = ["shinR"]
	b2.eyes = {"L": "lost"}
	b2.scars = {"torso": [1, 2, 3]}
	menu._doctor_visit(b2, ["lost the right shin", "lost the left eye"], 4, func(_nb): pass)
	for i in 30:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(out.path_join("physician.png"))
	print("saved physician")
	get_tree().quit()
