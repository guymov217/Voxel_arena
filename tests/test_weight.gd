extends Node
## His weight is on his legs (user: he floated, the legs carried nothing): a jump comes down
## like a man's, not a feather's, the knees give as he lands and a little at every footfall, and
## the feet stay on the sand through it.

var t

func _match(lo := {"main": "gladius", "off": ""}) -> Match:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none"}, "headless": true, "seed": 3, "decrees": [], "hazards": [], "loadout": lo})
	return m

func test_a_jump_comes_down_with_his_weight_and_the_knees_take_it() -> void:
	var m := _match()
	var f: Fighter = m.me.f
	var k := [0]
	m.me.drive = func(_e):
		k[0] += 1
		return {"jump": k[0] == 120}
	for i in 110:
		await get_tree().physics_frame
	var stand_y := f.torso.global_position.y
	var top := stand_y
	var air := 0
	var low := stand_y
	for i in 240:
		await get_tree().physics_frame
		top = maxf(top, f.torso.global_position.y)
		if not f.on_ground:
			air += 1
		elif air > 0:
			low = minf(low, f.torso.global_position.y)
	print("  jump: up %.2f m, %.2f s in the air, the knees gave %.3f m on landing" % [top - stand_y, air / 120.0, stand_y - low])
	t.check(top - stand_y > 0.2, "he still gets off the ground (%.2f m)" % (top - stand_y))
	t.check(air / 120.0 < 0.75, "and comes down soon, not hanging (%.2f s)" % (air / 120.0))
	t.check(stand_y - low > 0.03 * f.S, "the knees give as he lands (%.3f m)" % (stand_y - low))
	t.eq(f.state, "stand", "on his feet after it")
	m.queue_free()

func test_walking_the_weight_comes_onto_each_foot_and_the_soles_stay_on_the_sand() -> void:
	var m := _match()
	var f: Fighter = m.me.f
	m.me.drive = func(_e): return {"mz": 1.0}
	for i in 120:
		await get_tree().physics_frame
	var lo := INF
	var hi := -INF
	var sunk := 0
	var ms := [0.0]
	for i in 360:
		await get_tree().physics_frame
		ms[0] = maxf(ms[0], f.land_sag)
		var y := f.torso.global_position.y - f.ground_level
		lo = minf(lo, y)
		hi = maxf(hi, y)
		for sd in ["L", "R"]:
			var sh: VoxelPart = f.by_name["shin" + sd]
			if (sh.global_transform * Vector3(0, -4 * Fighter.V * f.S, 0)).y - f.ground_level < -0.06 * f.S:
				sunk += 1
	print("  walk: the hips ride between %.3f and %.3f m (sag up to %.3f, speed %.2f)" % [lo, hi, ms[0], f.torso.linear_velocity.length()])
	t.check(ms[0] > 0.04 * f.S, "the knees give as the weight comes onto each foot (%.3f m)" % ms[0])
	t.check(hi - lo > 0.015 * f.S, "the hips dip and rise with the steps (%.3f m)" % (hi - lo))
	t.check(sunk < 20, "the soles stay on the sand (%d steps under)" % sunk)
	m.queue_free()
