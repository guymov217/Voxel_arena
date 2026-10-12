extends Node
## Wear over a fight, the gates and the throw line: a blade dulls and, knocked again and again in
## one place, chips there and finally breaks there; a wave comes in at the gates, not at your
## back; a thrown pot flies at the mark along a flat line, not on a lob.

var t

func _match() -> Match:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none"}, "headless": true, "seed": 3})
	return m

func test_a_blade_dulls_with_use_and_only_so_far() -> void:
	var m := _match()
	var w: Weapon = m.me.f.weapons.R
	t.check(is_equal_approx(w.keenness(), 1.0), "a fresh blade is fully keen")
	for i in 40:
		w.wear_edge(0.02)
	t.check(w.keenness() < 0.5 and w.keenness() >= 1.0 - Weapon.DULL_MAX - 1e-4, "it dulls with use, never to nothing (%.2f)" % w.keenness())
	m.queue_free()

func test_knocks_in_one_place_chip_it_then_break_it_there() -> void:
	var m := _match()
	var w: Weapon = m.me.f.weapons.R
	var n0 := w.alive_count()
	# The voxel half way up the blade.
	var spot := -1
	var best := INF
	for i in w.vox.size():
		var v: Array = w.vox[i]
		if v[4] != "grip":
			var d := absf(float(v[1]) - w.reach / w.vs * 0.5) + absf(float(v[0])) + absf(float(v[2]))
			if d < best:
				best = d
				spot = i
	var first: Dictionary = w.knock(spot, 12.0)
	t.check(first.is_empty(), "one light knock takes nothing off")
	var chipped_at := -1
	var broke := false
	for k in 80:
		var idx := spot
		if w.alive[idx] == 0:
			# Keep knocking the same place: the nearest voxel still there.
			var p0 := Vector3(w.vox[spot][0], w.vox[spot][1], w.vox[spot][2])
			var bd := INF
			for i in w.vox.size():
				if w.alive[i] and w.vox[i][4] != "grip":
					var d := Vector3(w.vox[i][0], w.vox[i][1], w.vox[i][2]).distance_to(p0)
					if d < bd:
						bd = d
						idx = i
		var r: Dictionary = w.knock(idx, 12.0)
		if not r.is_empty() and chipped_at < 0:
			chipped_at = k
		if r.get("broke", false):
			broke = true
			break
	t.check(chipped_at >= 0, "the same spot, knocked again and again, gives way (after %d knocks)" % chipped_at)
	t.check(broke, "and in the end the blade breaks there")
	t.check(w.components().size() == 1, "what is left in the hand is one piece")
	t.check(w.alive_count() < n0 and w.vox.size() - w.alive_count() > n0 * 0.1, "the broken-off part is gone (%d of %d left)" % [w.alive_count(), n0])
	m.queue_free()

func test_waves_come_in_at_the_gates() -> void:
	var m := _match()
	var me: Vector3 = m.me.f.torso.global_position
	for total in [1, 2, 4]:
		for i in total:
			var spec := m.enemy_spec({"beast": "lion"} if i == 0 else {"type": "recruit"}, i, total)
			var p: Vector3 = spec.pos
			t.check(absf(p.x) > Arena.RADIUS - 6.0 and absf(p.z) < 1.5, "enemy %d of %d starts just inside a gate (%.1f, %.1f)" % [i + 1, total, p.x, p.z])
			t.check(p.distance_to(me) > 8.0, "and nowhere near your back (%.1f m off)" % p.distance_to(me))
	m.queue_free()

func test_a_thrown_pot_flies_flat_at_the_mark() -> void:
	var m := _match()
	var from := Vector3(0, 1.5, 0)
	for target in [Vector3(0, 1.0, 6), Vector3(4, 0.3, 9), Vector3(0, 6.0, 40)]:
		var it: Dictionary = m.items.throw_flat("pot_fire", from, target, null, 15.0)
		var v: Vector3 = it.vel
		var line: Vector3 = (target - from).normalized()
		var off := rad_to_deg(v.normalized().angle_to(line))
		t.check(off < 15.0, "to %s it leaves within %.0f° of the line to the mark" % [target, off])
		m.items.remove(it)
	m.queue_free()
