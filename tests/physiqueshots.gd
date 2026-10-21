extends Node
## The six gladiator looks side by side (`-- --probe physiqueshots`, needs a display): whole, then
## the same wounds on each (belly opened, a forearm and a thigh hacked), then in hair and armour.
## PNGs go to SHOT_DIR; ORDER=a,b limits the looks to those (whole only).

func _save(n: String) -> void:
	RenderingServer.render_loop_enabled = true
	for i in 4:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(OS.get_environment("SHOT_DIR").path_join("look_%s.png" % n))
	RenderingServer.render_loop_enabled = false

func _ready() -> void:
	RenderingServer.render_loop_enabled = false
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none"}, "decrees": [], "hazards": [], "seed": 5})
	m.me.f.teleport(Vector3(0, 0, -12))
	var men := []
	var i := 0
	for st in (OS.get_environment("ORDER").split(",") if OS.has_environment("ORDER") else Physique.STYLES):
		Physique.forced = st
		var e = m.spawn_fighter({"kind": "bot", "name": st, "loadout": {}, "team": 1, "pos": Vector3((i - 2.5) * 1.4, 0.1, 0), "yaw": 0.0, "skin": 0xc68e5e})
		Physique.forced = ""
		e.erase("bot")
		e.drive = func(_e): return {}
		men.append(e.f)
		i += 1
	for k in 150:
		await get_tree().physics_frame
	m.set_process(false)
	for f in men:
		for p in f.parts:
			p.freeze = true
	var cam := Camera3D.new()
	m.add_child(cam)
	cam.current = true
	cam.fov = 34
	var shots := func(tag: String):
		for f in men:
			var t: Vector3 = f.torso.global_position
			cam.global_position = t + Vector3(0.9, 0.25, 2.6)
			cam.look_at(t + Vector3(0, -0.22, 0), Vector3.UP)
			await _save("%s_%s" % [tag, f.display_name])
			cam.global_position = f.head.global_position + Vector3(0.35, 0.08, 0.85)
			cam.look_at(f.head.global_position, Vector3.UP)
			await _save("%s_%s_head" % [tag, f.display_name])
	await shots.call("whole")
	if OS.has_environment("ORDER"):
		get_tree().quit()
		return
	# The same wounds on each: the belly opened, a forearm and a thigh hacked.
	var plan := [["torso", Vector3(0, -0.06, 1), "edge"], ["torso", Vector3(0.05, -0.06, 1), "point"], ["torso", Vector3(-0.05, -0.04, 1), "edge"],
		["forearmL", Vector3(0, 0.05, 1), "edge"], ["forearmL", Vector3(0, 0.05, 1), "edge"], ["forearmL", Vector3(0, 0.05, 1), "edge"], ["forearmL", Vector3(0, 0.05, 1), "edge"],
		["thighR", Vector3(0, 0.02, 1), "edge"], ["thighR", Vector3(0, 0.02, 1), "edge"], ["head", Vector3(0.06, 0.04, 1), "edge"]]
	for f in men:
		for k in plan.size():
			var pl: Array = plan[k]
			var p: VoxelPart = f.by_name[pl[0]]
			var o: Vector3 = pl[1]
			var side := Vector3(o.x, 0, o.z).normalized()
			var lp := Vector3(side.x * p.half_ext.x, o.y, side.z * p.half_ext.z) * 1.02
			var at: Vector3 = p.global_transform * lp
			var dir := -(p.global_transform.basis * side).normalized()
			seed(1000 + k)
			f.apply_hit(p, {"point": at, "dir": dir, "type": pl[2], "hardness": 1.0, "sharpness": 0.95, "impulse": 70.0, "heavy": 0.7, "edge": dir, "axis": (p.global_transform.basis * Vector3.RIGHT).normalized(), "wsz": 1.0})
	await shots.call("hurt")
	for f in men:
		f.set_armor_pieces(["hair_long", "steelLorica", "greaves", "manica"])
	await shots.call("gear")
	get_tree().quit()
