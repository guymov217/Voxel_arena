extends Node
## A left arm lost (user: the cut-off part floated inside his body): cut off in a fight and left a
## few seconds, then a new bout with it missing, each from the front, his left and behind
## (`-- --probe severshot`, needs a display). PNGs to SHOT_DIR; positions of every severed or
## missing part against the trunk printed (SEVER lines).

var cam: Camera3D

func _snap(out: String, name: String, pos: Vector3, look: Vector3, fov := 40.0) -> void:
	cam.global_position = pos
	cam.look_at(look, Vector3.UP)
	cam.fov = fov
	for i in 14:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(out.path_join(name))
	print("saved ", name)

func _report(tag: String, f: Fighter) -> void:
	var tinv := f.torso.global_transform.affine_inverse()
	for p in f.parts:
		if p.severed or p.missing:
			var l: Vector3 = tinv * p.global_position
			var inside := absf(l.x) < f.torso.half_ext.x + 0.05 and absf(l.y) < f.torso.half_ext.y + 0.05 and absf(l.z) < f.torso.half_ext.z + 0.05
			print("SEVER %s %-10s visible %s frozen %s layer %d at %s from the trunk%s" % [tag, p.part_name, str(p.visible), str(p.freeze), p.collision_layer, str(l.snapped(Vector3(0.01, 0.01, 0.01))), "  <-- INSIDE THE TRUNK" if inside and p.visible else ""])

func _ready() -> void:
	var out := OS.get_environment("SHOT_DIR")
	var only := OS.get_environment("CASES").split(",", false)
	for case in ["cut", "missing"]:
		if not only.is_empty() and not only.has(case):
			continue
		var m := Match.new()
		add_child(m)
		var spec := {"mode": "training", "training": {"enemy": "none"}, "decrees": [], "hazards": [], "seed": 3, "loadout": {"main": "gladius", "off": "roundShield", "armor": ["manica", "helmet"]}}
		m.setup(spec)
		if m.cam:
			m.cam.set_process(false)
		cam = Camera3D.new()
		m.add_child(cam)
		cam.make_current()
		var f: Fighter = m.me.f
		if case == "missing":
			var e = m.spawn_fighter({"kind": "bot", "name": "Him", "loadout": {"main": "gladius", "off": "roundShield", "armor": ["manica", "helmet"]}, "team": 0, "pos": Vector3(3, 0, 0), "yaw": 0.0, "body": Body.sanitize({"missing": ["upperArmL"]})})
			e.erase("bot")
			e.drive = func(_e): return {"main": {"x": 0.1, "y": 0.15}, "off": {"x": -0.35, "y": 0.1}}
			m.me.f.teleport(Vector3(-8, 0, 6))
			f = e.f
		else:
			m.me.drive = func(_e): return {"main": {"x": 0.1, "y": 0.15}, "off": {"x": -0.35, "y": 0.1}}
		get_viewport().disable_3d = true
		var full := get_window().size
		get_window().size = Vector2i(160, 90)
		for i in 90:
			await get_tree().physics_frame
		if case == "cut":
			var res := {"removed": [], "severed": [], "dmg": 0.0}
			f.detach_limb(f.by_name.upperArmL, res)
		for i in 480:
			await get_tree().physics_frame
		_report(case, f)
		get_window().size = full
		get_viewport().disable_3d = false
		var c: Vector3 = f.torso.global_position
		var yq := Quaternion(Vector3.UP, f.yaw)
		await _snap(out, "sever_%s_front.png" % case, c + yq * Vector3(0, 0.25, 2.2), c)
		await _snap(out, "sever_%s_left.png" % case, c + yq * Vector3(2.2, 0.25, 0.2), c)
		await _snap(out, "sever_%s_back.png" % case, c + yq * Vector3(0.4, 0.4, -2.2), c)
		m.queue_free()
		for i in 5:
			await get_tree().process_frame
	get_tree().quit()
