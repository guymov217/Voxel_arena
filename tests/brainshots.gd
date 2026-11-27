extends Node
## A man's head cut down the middle, the near half taken away, and seen from that side (`-- --probe brainshots`, needs a display): the skull, the brain in it and what lies round them.
## BRAIN_N: how many shots (default 1: the side), SHOT_DIR: where the PNGs go (brain_<n>.png), BRAIN_LOSE: share of the brain torn away first (0..1).

var m
var cam: Camera3D

func _snap(name_: String, pos: Vector3, look: Vector3, fov := 30.0) -> void:
	cam.global_position = pos
	cam.look_at(look, Vector3.UP)
	cam.fov = fov
	RenderingServer.render_loop_enabled = true
	for i in 30:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(OS.get_environment("SHOT_DIR").path_join(name_))
	RenderingServer.render_loop_enabled = false
	print("saved ", name_)

func _ready() -> void:
	m = Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none"}, "decrees": [], "hazards": [], "seed": 9})
	m.me.f.teleport(Vector3(0, 0, -30))
	var hud = m.get("hud")
	if hud and hud is CanvasItem:
		hud.visible = false
	if m.cam:
		m.cam.set_process(false)
	cam = Camera3D.new()
	m.add_child(cam)
	cam.make_current()
	RenderingServer.render_loop_enabled = false
	var e = m.spawn_fighter({"kind": "bot", "name": "A", "loadout": {"main": "gladius", "off": "", "armor": []}, "team": 2, "pos": Vector3(0, 0.1, 0), "yaw": 0.0, "diff": 0.5, "personality": "standard"})
	var f: Fighter = e.f
	for i in 40:
		await get_tree().physics_frame
	for p in f.parts:
		p.freeze = true
	var lose := float(OS.get_environment("BRAIN_LOSE")) if OS.get_environment("BRAIN_LOSE") != "" else 0.0
	if lose > 0.0:
		var idx := []
		for i in f.head.organ.size():
			if f.head.organ[i] == Anatomy.BRAIN and f.head.alive[i]:
				idx.append(i)
		idx.sort_custom(func(a, b): return f.head.fz[a] > f.head.fz[b])
		f.head.remove_voxels(idx.slice(0, int(idx.size() * lose)), false, false)
	var c: Vector3 = f.head.global_position
	var lps: PackedVector3Array = f.head.local_positions()
	var gt: Transform3D = f.head.global_transform
	var near := []
	for i in lps.size():
		if f.head.alive[i] and (gt * lps[i]).x > c.x + 0.004:
			near.append(i)
	f.head.remove_voxels(near, false, false)
	f.torso.bleed = 0.0
	for i in 6:
		await get_tree().process_frame
	get_tree().paused = true
	await _snap("brain_side.png", c + Vector3(0.9, 0.05, 0.0), c, 24.0)
	get_tree().paused = false
	get_tree().quit()
