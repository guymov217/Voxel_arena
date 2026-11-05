extends Node
## Every beast's insides on camera (`-- --probe anatomyshots`, needs a display): each beast stood
## still in the new look, then cut down the middle from nose to tail, the near half taken away, and
## seen from that side: the spine down its back, the ribs round its chest, the pelvis, the skull
## round the brain, the heart, the lungs, the liver, the guts, the bone down each leg, the muscle
## between (user: every beast's skeleton, muscles and organs as they should be). ONLY: a comma
## list; STYLE: the look (human). PNGs to SHOT_DIR as anatomy_<beast>.png.

var m
var cam: Camera3D
var _warmed := false

func _snap(out: String, name: String, pos: Vector3, look: Vector3, fov := 38.0) -> void:
	cam.global_position = pos
	cam.look_at(look, Vector3.UP)
	cam.fov = fov
	# (The first picture waits for the shaders; after it a few frames bring the scene up to date.)
	var warm := 4 if RenderingServer.render_loop_enabled else (5 if _warmed else 40)
	RenderingServer.render_loop_enabled = true
	for i in warm:
		await get_tree().process_frame
	_warmed = true
	get_viewport().get_texture().get_image().save_png(out.path_join(name))
	print("saved ", name)

func _ready() -> void:
	var out := OS.get_environment("SHOT_DIR")
	var only := OS.get_environment("ONLY")
	var style := OS.get_environment("STYLE") if OS.get_environment("STYLE") != "" else "human"
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
	var list: Array = Data.beasts.keys()
	if only != "":
		list = Array(only.split(","))
	for kind in list:
		Physique.forced = style
		var e = m.spawn_beast({"beast": kind, "team": Match.ENEMY_TEAM, "pos": Vector3(0, 0.1, 0), "yaw": 0.0, "harmless": true})
		Physique.forced = ""
		var b: Beast = e.f
		b.sp = b.sp.duplicate()
		b.sp.speed = 0.0
		b.sp.lunge = 0.0
		b.sp.ai = "statue"
		for i in 30:
			await get_tree().physics_frame
		# Held where it stands, and cut down the middle: the half toward the camera (+x) taken
		# away, as no blow does (nothing bleeds, nothing dies of it: only the look).
		var c: Vector3 = b.torso.global_position
		for p in b.parts:
			p.freeze = true
		var box := AABB(c, Vector3.ZERO)
		for p in b.parts:
			if not is_instance_valid(p) or p.severed:
				continue
			box = box.merge(AABB(p.global_position - p.half_ext, p.half_ext * 2.0))
			var lps: PackedVector3Array = p.local_positions()
			var gt: Transform3D = p.global_transform
			var near := []
			for i in lps.size():
				if p.alive[i] and (gt * lps[i]).x > c.x + 0.004:
					near.append(i)
			if not near.is_empty():
				p.remove_voxels(near, false, false)
		b.torso.bleed = 0.0
		for i in 6:
			await get_tree().process_frame
		get_tree().paused = true
		var at := box.get_center()
		var r := maxf(box.size.y, box.size.z) * 0.62
		await _snap(out, "anatomy_%s.png" % kind, at + Vector3(r / tan(deg_to_rad(19.0)) + box.size.x * 0.5, r * 0.15, 0.0), at, 38.0)
		RenderingServer.render_loop_enabled = false
		get_tree().paused = false
		m.entities.erase(e)
		for p in b.parts:
			if is_instance_valid(p):
				p.queue_free()
		b.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
		print("ANATOMY %s done" % kind)
	get_tree().quit()
