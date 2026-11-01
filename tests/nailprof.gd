extends Node
## The nail pot's hitch (user: a small hitch every time it hits): a pot burst by a man, headless,
## how long the burst itself takes and every step after it, against the steps before.
## `-- --probe nailprof`.

func _ready() -> void:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none", "respawn": false}, "headless": OS.get_environment("NAIL_HEADLESS") != "0", "seed": 3})
	m.me.f.teleport(Vector3(-6, 0, 0))
	var e = m.spawn_fighter({"kind": "bot", "name": "D", "loadout": {"main": "gladius"}, "team": 1, "pos": Vector3(0, 0, 0), "yaw": PI * 0.5})
	e.erase("bot")
	e.drive = func(_e): return {}
	for i in 120:
		await get_tree().physics_frame
	for round in 3:
		var base := []
		var t_prev := Time.get_ticks_usec()
		for i in 30:
			await get_tree().physics_frame
			var now := Time.get_ticks_usec()
			base.append(now - t_prev)
			t_prev = now
		var p: Vector3 = e.f.torso.global_position + Vector3(-0.35, 0.1, 0)
		var t0 := Time.get_ticks_usec()
		m.throwables.explode("pot_nail", p, m.me, Vector3(1, 0, 0))
		var t_burst := Time.get_ticks_usec() - t0
		t_prev = Time.get_ticks_usec()
		var after := []
		for i in 90:
			await get_tree().physics_frame
			var now := Time.get_ticks_usec()
			after.append(now - t_prev)
			t_prev = now
		var bmax := 0
		for x in base:
			bmax = maxi(bmax, int(x))
		var amax := 0
		var at := -1
		for i in after.size():
			if int(after[i]) > amax:
				amax = int(after[i])
				at = i
		var slow := after.filter(func(x): return int(x) > 2 * bmax).size()
		print("NAIL round %d: burst call %.1f ms; steps before max %.1f ms; after max %.1f ms (step %d), %d steps over twice the worst before; first 6 after: %s" % [round, t_burst / 1000.0, bmax / 1000.0, amax / 1000.0, at, slow, str(after.slice(0, 6).map(func(x): return snappedf(x / 1000.0, 0.1)))])
	get_tree().quit()
