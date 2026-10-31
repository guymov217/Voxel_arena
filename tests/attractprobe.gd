extends Node
## The menu backdrop over a long while: the fallen are replaced, one at a time, and no frame
## takes long (`-- --probe attractprobe`).
func _ready() -> void:
	var m := Match.new()
	add_child(m)
	m.attract = true
	m.setup({"mode": "ffa", "autopilot": true, "decrees": [], "hazards": [], "seed": 3})
	var ids := {}
	var worst := 0
	var last := Time.get_ticks_usec()
	for i in 120 * 60:
		await get_tree().physics_frame
		var now := Time.get_ticks_usec()
		if i > 10:
			worst = maxi(worst, now - last)
		last = now
		for e in m.entities:
			ids[e.id] = true
		if i % 600 == 0:
			for e in m.entities:
				if is_instance_valid(e.f) and e.f.alive and randf() < 0.5:
					e.f.die()   # (help the fight along)
	print("ATTRACT over=%s men ever=%d now=%d alive=%d worst step %.0f ms" % [m.over, ids.size(), m.entities.size(), m.entities.filter(func(e): return e.f.alive).size(), worst / 1000.0])
	get_tree().quit()
