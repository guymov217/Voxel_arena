extends Node
## What refitting a holed part's collision boxes costs (firsthit.gd: 10 ms on a gorilla's trunk
## once it has a hole, at every cut): the boxes worked out, against the nodes made for them.
## `-- --probe fitcost`. FOE (gorilla).

func _ready() -> void:
	var foe := OS.get_environment("FOE") if OS.get_environment("FOE") != "" else "gorilla"
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none"}, "headless": true, "seed": 3, "decrees": [], "hazards": []})
	var e = m.spawn_beast({"beast": foe, "team": Match.ENEMY_TEAM, "pos": Vector3(0, 0.1, 6.0), "yaw": PI, "harmless": true})
	var b: Beast = e.f
	for i in 60:
		await get_tree().physics_frame
	var part: VoxelPart = b.torso
	var dir := Vector3(0, 0, 1)
	b.apply_hit(part, {"impulse": 30.0, "type": "edge", "hardness": 0.8, "sharpness": 0.8, "point": part.global_position - dir * part.half_ext.z, "dir": dir, "axis": Vector3.UP, "edge": Vector3.RIGHT, "heavy": 0.2, "weapon": true, "mass": 1.2})
	await get_tree().physics_frame
	var w := part.dims.x; var h := part.dims.y; var d := part.dims.z
	print("coarse %dx%dx%d, boxes %d" % [w, h, d, part.boxes.size()])
	for k in 3:
		var t0 := Time.get_ticks_usec()
		part.fit_collider()
		var t1 := Time.get_ticks_usec()
		var solid := PackedByteArray(); solid.resize(w * h * d)
		for c in w * h * d:
			solid[c] = 1 if (part.total_coarse[c] > 0 and part.live_coarse[c] * 4 >= part.total_coarse[c]) else 0
		var t2 := Time.get_ticks_usec()
		var bx: Array = Greedy.boxes(w, h, d, solid)
		var t3 := Time.get_ticks_usec()
		print("fit_collider %.2f ms (boxes %d); solid %.2f ms; Greedy.boxes %.2f ms (%d)" % [(t1 - t0) / 1000.0, part.boxes.size(), (t2 - t1) / 1000.0, (t3 - t2) / 1000.0, bx.size()])
	get_tree().quit()
