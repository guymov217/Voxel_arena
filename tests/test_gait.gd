extends Node
## Walking and running on the legs (the stance-leg gait): a foot is always on the sand while he
## walks, the planted foot stays where it was put while the body goes over it, and the weight
## rides over the foot that bears it.

var t

func _gait(run: bool) -> Dictionary:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none"}, "headless": true, "seed": 3})
	m.me.f.teleport(Vector3(6, 0, 6))
	var e = m.spawn_fighter({"kind": "bot", "name": "W", "loadout": {"main": "gladius", "off": "roundShield"}, "team": 1, "pos": Vector3(0, 0, -12.5), "yaw": 0.0})
	e.erase("bot")
	e.drive = func(_e): return {"mz": 1.0, "sprint": run, "look": {"yaw": 0.0, "pitch": 0.0}}
	var f: Fighter = e.f
	for i in 120:
		await get_tree().physics_frame
	var n := 0
	var down_n := 0
	var gap := 0.0
	var gap_n := 0
	var z0 := f.torso.global_position.z
	for i in 300:
		await get_tree().physics_frame
		n += 1
		var any := false
		for sd in ["L", "R"]:
			var sh: VoxelPart = f.by_name["shin" + sd]
			var sole: Vector3 = sh.global_transform * Vector3(0, -sh.half_ext.y, 0)
			if sole.y < 0.04:
				any = true
			var ft = f.feet[sd]
			if ft != null and not ft.swing:
				gap += Vector2(sole.x - ft.anchor.x, sole.z - ft.anchor.z).length()
				gap_n += 1
		if any:
			down_n += 1
	var out := {"down": float(down_n) / n, "gap": gap / maxf(1, gap_n), "speed": (f.torso.global_position.z - z0) / 2.5, "state": f.state}
	m.queue_free()
	return out

func test_he_walks_on_his_feet() -> void:
	var r: Dictionary = await _gait(false)
	t.check(r.down > 0.97, "a foot is on the sand %d%% of the walk" % int(r.down * 100))
	t.check(r.gap < 0.07, "the planted foot holds its spot (%.3f m off)" % r.gap)
	t.check(r.speed > 1.2, "and he gets on (%.2f m/s)" % r.speed)
	t.eq(r.state, "stand", "on his feet")

func test_he_runs_on_his_feet() -> void:
	var r: Dictionary = await _gait(true)
	t.check(r.down > 0.9, "running, a foot is down %d%% of the time" % int(r.down * 100))
	t.check(r.speed > 3.0, "and he runs (%.2f m/s)" % r.speed)
	t.eq(r.state, "stand", "on his feet")
