extends Node
## Knocked down and left alive, a man gets up again; and a blade opens the same wound in a
## giant as in a man (the wound is the size of the weapon, not of the one it is in).

var t

func _steps(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func _match() -> Match:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none"}, "headless": true, "seed": 3})
	m.me.f.teleport(Vector3(0, 0, -12))
	return m

func _man(m: Match, pos: Vector3, mods := {}) -> Fighter:
	var e = m.spawn_fighter({"kind": "bot", "name": "V", "loadout": {}, "team": 1, "pos": pos, "yaw": PI, "mods": mods})
	e.erase("bot")
	e.drive = func(_e): return {}
	return e.f

func test_a_man_knocked_out_comes_round_and_stands() -> void:
	var m := _match()
	for why in ["concussion", "blood"]:
		var f := _man(m, Vector3(0, 0, 0))
		await _steps(30)
		if why == "concussion":
			f.concussion = 1.0
		else:
			f.blood = 10.0
		f.fall(99.0, true)
		await _steps(60)
		t.check(f.state != "stand", "%s: he is down" % why)
		var up := false
		for i in 120 * 14:
			await get_tree().physics_frame
			if f.state == "stand":
				up = true
				break
		t.check(up and f.alive, "%s: he comes round and stands again (%s, blood %.0f, concussion %.2f)" % [why, f.state, f.blood, f.concussion])
		m.entities.erase(m.entity_of(f))
		m.combat.fighters.erase(f)
		f.teleport(Vector3(20, 0, 20 + (5 if why == "blood" else 0)))
	m.queue_free()

func test_a_cut_is_the_size_of_the_blade_in_a_giant_as_in_a_man() -> void:
	var m := _match()
	var man := _man(m, Vector3(0, 0, 0))
	var giant := _man(m, Vector3(6, 0, 0), {"bodyScale": 3.0})
	await _steps(60)
	var lost := []
	for f in [man, giant]:
		var p: VoxelPart = f.torso
		var tf := p.global_transform
		var fwd := tf.basis.orthonormalized() * Vector3(0, 0, 1)
		var n0 := p.alive_count
		f.apply_hit(p, {"impulse": 40.0, "type": "edge", "hardness": 0.9, "sharpness": 0.8, "point": tf * Vector3(0.0, 0.0, p.half_ext.z), "dir": -fwd, "axis": tf.basis.orthonormalized() * Vector3(1, 0, 0), "edge": -fwd, "heavy": 0.5, "wsz": 1.0})
		# In metres of flesh: each voxel of the giant is bigger.
		var vs: float = p.vf * p.part_scale
		lost.append((n0 - p.alive_count) * vs * vs * vs)
		print("   %s: %d voxels of %.3f m gone (of %d)" % [f.display_name, n0 - p.alive_count, vs, n0])
	t.check(lost[0] > 0.0 and lost[1] > 0.0, "both are cut (%.5f and %.5f cubic metres)" % [lost[0], lost[1]])
	t.check(lost[1] < lost[0] * 3.0, "the giant loses no great slab to a man's sword (%.1fx the man's wound)" % (lost[1] / maxf(1e-9, lost[0])))
	m.queue_free()
