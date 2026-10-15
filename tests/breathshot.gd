extends Node
## The dragon breathing fire (`-- --probe breathshot`, needs a display): head out at the man, jaws
## wide, the stream on him. PNGs to SHOT_DIR/breath_<n>.png.

func _ready() -> void:
	var out := OS.get_environment("SHOT_DIR")
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none"}, "decrees": [], "hazards": []})
	m.me.f.teleport(Vector3(0, 0, 0))
	m.set_process(false)
	var e = m.spawn_beast({"beast": "dragon", "team": Match.ENEMY_TEAM, "pos": Vector3(0, 0.1, 7.0), "yaw": PI})
	var b: Beast = e.f
	b.ai.fly_cool = 999.0
	var cam: Camera3D = m.cam
	cam.fov = 42.0
	var n := 0
	m.me.f.mods.toughness = 50.0
	for i in 20 * 120:
		b.target = m.me.f
		m.me.f.blood = 100.0
		for p in m.me.f.parts:
			p.hp = maxf(p.hp, 30.0)
		# The man stays on his feet five yards off the dragon: it is the pose that is on show.
		var dp: Vector3 = b.torso.global_position
		var mp0: Vector3 = m.me.f.torso.global_position
		var away := Vector3(mp0.x - dp.x, 0, mp0.z - dp.z)
		if m.me.f.state != "stand" or away.length() < 4.0:
			away = away.normalized() if away.length() > 0.5 else Vector3(0, 0, -1)
			m.me.f.teleport(Vector3(dp.x, 0, dp.z) + away * 5.0)
			m.me.f.set_standing(true)
		await get_tree().physics_frame
		var fire: bool = b.breath_t > 0.6 or (b.ai.mode == "breathe" and float(b.ai.t) < 0.3)
		if fire and i % 10 == 0:
			var hp: Vector3 = b.head.global_position
			var mp: Vector3 = m.me.f.torso.global_position
			var c := (hp + mp) * 0.5
			var axis := Vector3(hp.x - mp.x, 0, hp.z - mp.z).normalized()
			cam.global_position = c + axis.cross(Vector3.UP) * 7.0 + Vector3(0, 1.5, 0)
			cam.look_at(c, Vector3.UP)
			await get_tree().process_frame
			await get_tree().process_frame
			n += 1
			get_viewport().get_texture().get_image().save_png(out.path_join("breath_%d.png" % n))
			# A close-up of the open jaws from beside the head.
			var hd: VoxelPart = b.breath_part()
			var md: Vector3 = b.mouth_dir()
			cam.global_position = hd.global_position + Vector3(md.z, 0, -md.x).normalized() * 3.2 + Vector3(0, 0.3, 0)
			cam.look_at(hd.global_position + md * 0.4, Vector3.UP)
			await get_tree().process_frame
			await get_tree().process_frame
			get_viewport().get_texture().get_image().save_png(out.path_join("jaws_%d.png" % n))
			print("jaw angle ", hd.jaw_angle)
			print("saved breath ", n, " mode ", b.ai.mode, " t ", b.breath_t)
			if n >= 4:
				break
	get_tree().quit()
