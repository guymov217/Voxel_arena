extends Node
## How the giants hold their great weapons in both hands (`-- --probe giantgrip`, needs a
## display): each giant held still in his guard and at the start of each of his blows (Bot.GIANT),
## seen from in front and from his side: the hands on the haft, and the face not hidden behind
## them. GRIP_ONLY picks one giant. PNGs to SHOT_DIR/grip_<giant>_<pose>_<view>.png; the head's
## and the hands' places are printed (GRIP <giant> <pose> ...).

## The guard, and the wind-up of each of the giants' blows as the bot draws it (Bot.GIANT).
static func poses() -> Dictionary:
	var out := {"guard": {"x": 0.15, "y": -0.2}}
	for k in Bot.GIANT:
		out[k] = {"x": Bot.GIANT[k][0][0], "y": Bot.GIANT[k][0][1]}
	return out

func _ready() -> void:
	var out := OS.get_environment("SHOT_DIR")
	var only := OS.get_environment("GRIP_ONLY")
	var shots := OS.get_environment("GRIP_SHOTS") != "0"
	RenderingServer.render_loop_enabled = false
	for k in ["cyclops", "giant", "minotaur", "troll", "titan"]:
		if only != "" and not (only.split(",") as Array).has(k):
			continue
		var m := Match.new()
		add_child(m)
		m.setup({"mode": "training", "training": {"enemy": "none"}, "decrees": [], "hazards": []})
		if m.killcam:
			m.killcam.queue_free()
			m.killcam = null
		m.cam.set_process(false)
		var cam := Camera3D.new()   # (the fight's own camera stays with the player)
		add_child(cam)
		cam.make_current()
		var spec: Dictionary = m.enemy_spec({"e": k}, 0, 1)
		spec.pos = Vector3(0, 0.1, 3)
		spec.yaw = PI
		var e = m.spawn_fighter(spec)
		e.erase("bot")
		m.me.f.teleport(Vector3(0, 0, -14))
		var POSES := poses()
		var pose := {"main": POSES.guard}   # (changed in place: a lambda keeps the value it was made with)
		e.drive = func(_e): return {"main": pose.main, "look": {"yaw": PI, "pitch": -0.2}, "twist": 0.0}
		for i in 180:
			await get_tree().physics_frame
		var f: Fighter = e.f
		for pn in POSES:
			pose.main = POSES[pn]
			for i in 150:
				await get_tree().physics_frame
			# Where the hands are against the face: from in front (the face's own direction), how far
			# off the line from the eyes the hands and the haft's middle lie, in head sizes.
			var head: Vector3 = f.head.global_position
			var face_dir := Vector3(sin(f.yaw), 0, cos(f.yaw))
			var cover := 99.0
			var pts := []
			for sd in ["R", "L"]:
				pts.append(f.hand_world(sd))
			var w = f.weapons.get("R")
			if w:
				# (and the haft and head, all along it)
				for k_ in 5:
					pts.append(w.global_position + PD.quat_of(w) * Vector3(0, w.reach * k_ / 4.0, 0))
			for p in pts:
				var rel: Vector3 = p - head
				if rel.dot(face_dir) > 0.0 and absf(rel.y) < 0.3 * f.S:   # in front of the face, at its height
					var lateral := (rel - face_dir * rel.dot(face_dir)).length()
					cover = minf(cover, lateral / (0.25 * f.S))
			print("GRIP %s %s face covered by %.2f head-widths (under 1: in front of the face) two_handed %s" % [k, pn, cover, f.two_handed])
			if not shots:
				continue
			for v in [["front", Vector3(0.0, 0.1, 1.0), 3.2], ["side", Vector3(1.0, 0.15, 0.25), 3.4]]:
				var dir: Vector3 = (Basis(Vector3.UP, f.yaw) * (v[1] as Vector3)).normalized()
				cam.fov = 45.0
				cam.global_position = f.torso.global_position + dir * float(v[2]) * f.S + Vector3(0, 0.25 * f.S, 0)
				cam.look_at(f.torso.global_position + Vector3(0, 0.35 * f.S, 0), Vector3.UP)
				RenderingServer.render_loop_enabled = true
				for i in 3:
					await get_tree().process_frame
				get_viewport().get_texture().get_image().save_png(out.path_join("grip_%s_%s_%s.png" % [k, pn, v[0]]))
				RenderingServer.render_loop_enabled = false
		m.queue_free()
		cam.queue_free()
		await get_tree().process_frame
	print("GRIP done")
	get_tree().quit()
