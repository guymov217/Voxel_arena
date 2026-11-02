extends Node
## The physician's work up close (`-- --probe prostheticshots`, needs a display): a blade arm, a
## hook and a peg leg on a veteran in the training ground, each from the side and from the front,
## and the whole man. PRO_LEVEL (0-2): the smith's steps on all three (Body.PRO_STEPS), the shots
## named _lv1, _lv2. PNGs go to SHOT_DIR.

func _ready() -> void:
	var out := OS.get_environment("SHOT_DIR")
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none"}, "decrees": [], "hazards": []})
	m.set_process(false)
	var cam: Camera3D = m.cam
	var b := Body.empty()
	b.missing = ["shinL", "forearmR", "forearmL"]
	b = Body.apply(Body.apply(Body.apply(b, "peg:shinL"), "blade:forearmR"), "hook:forearmL")
	var lv := int(OS.get_environment("PRO_LEVEL")) if OS.has_environment("PRO_LEVEL") else 0
	b.pro_up = {"shinL": lv, "forearmR": lv, "forearmL": lv}
	var tag := ("_lv%d" % lv) if lv > 0 else ""
	var e = m.spawn_fighter({"kind": "bot", "name": "Veteran", "loadout": {"main": "gladius", "off": "roundShield"}, "team": 0, "pos": Vector3(0, 0, 2), "yaw": PI, "body": b})
	e.erase("bot")
	e.drive = func(_e): return {"main": {"x": 0.35, "y": 0.25}, "off": {"x": -0.45, "y": 0.2}}
	m.me.f.teleport(Vector3(0, 0, -10))
	for i in 180:
		await get_tree().physics_frame
	var f: Fighter = e.f
	for n in ["shinL", "forearmL", "forearmR"]:
		var pp: VoxelPart = f.by_name[n]
		print(n, " alive ", pp.alive_count, "/", pp.fx.size(), " prosthetic ", pp.prosthetic)
	var fwd := Vector3(sin(f.yaw), 0, cos(f.yaw))
	var right := Vector3(cos(f.yaw), 0, -sin(f.yaw))
	var shots := [
		["pro_blade_side", "forearmR", -right * 0.9 + fwd * 0.35 + Vector3(0, 0.15, 0), 0.75],
		["pro_blade_front", "forearmR", fwd + Vector3(0, 0.2, 0) - right * 0.2, 0.8],
		["pro_hook_side", "forearmL", right * 0.9 + fwd * 0.35 + Vector3(0, 0.15, 0), 0.65],
		["pro_hook_front", "forearmL", fwd + Vector3(0, 0.15, 0) + right * 0.2, 0.7],
		["pro_peg_side", "shinL", right * 0.9 + fwd * 0.5 + Vector3(0, 0.1, 0), 0.8],
		["pro_peg_front", "shinL", fwd + Vector3(0, 0.1, 0) + right * 0.25, 0.85],
		["pro_whole", "torso", fwd + Vector3(0, 0.15, 0) - right * 0.35, 2.3],
	]
	for v in shots:
		var c: Vector3 = f.by_name[v[1]].global_position
		cam.fov = 40.0
		cam.global_position = c + (v[2] as Vector3).normalized() * float(v[3])
		cam.look_at(c, Vector3.UP)
		await get_tree().process_frame
		await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png(out.path_join(v[0] + tag + ".png"))
		print("saved ", v[0] + tag)
	get_tree().quit()
