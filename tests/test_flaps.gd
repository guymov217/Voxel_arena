extends Node
## Flaps: a lump of a part cut almost free hangs on by the strip left at the cut, a little body
## of its own on a loose joint, until a blow cuts that strip. And light cuts into the same wound
## go deeper every time (they once stalled a voxel short).

var t

func _steps(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func test_a_scalp_cut_almost_off_hangs_until_its_strip_is_cut() -> void:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none"}, "decrees": [], "hazards": [], "headless": true})
	m.me.f.teleport(Vector3(0, 0, -6))
	var e = m.spawn_fighter({"kind": "bot", "name": "V", "loadout": {}, "team": 1, "pos": Vector3(0, 0.1, 0), "yaw": PI})
	e.erase("bot")
	e.drive = func(_e): return {}
	var v: Fighter = e.f
	await _steps(40)
	var h: VoxelPart = v.head
	var cuts := 0
	var gone := []
	while cuts < 20 and v.flaps.is_empty() and not h.severed:
		h.hp = 1000.0
		var gt := h.global_transform
		var bx := gt.basis.orthonormalized()
		var res: Dictionary = v.apply_hit(h, {"impulse": 22.0, "type": "edge", "hardness": 0.9, "sharpness": 0.9, "point": gt * Vector3(h.half_ext.x - 0.004, h.half_ext.y * 0.35, 0.0), "dir": -bx.x, "axis": bx.z, "edge": -bx.x})
		gone.append(res.removed.reduce(func(a, r): return a + r.indices.size(), 0))
		cuts += 1
		await _steps(3)
	t.check(gone.slice(0, 6).all(func(n): return n > 0), "every light cut into the wound goes deeper (%s)" % [gone])
	t.check(v.flaps.size() == 1 and not h.severed, "the top of the head hangs on as a flap (%d cuts)" % cuts)
	if v.flaps.is_empty():
		m.queue_free()
		return
	var ch: Chunk = v.flaps[0].chunk
	var link: PackedInt32Array = v.flaps[0].link
	await _steps(60)
	t.check(ch.flap_of != null and ch.global_position.distance_to(h.global_position) < 0.4, "a minute on it still hangs off him")
	var at := Vector3.ZERO
	for i in link:
		at += h.world_of(i)
	at /= float(link.size())
	var side := PD.quat_of(h) * Vector3(1, 0, 0)
	var k := 0
	while ch.flap_of != null and k < 6:
		h.hp = 1000.0
		v.apply_hit(h, {"impulse": 22.0, "type": "edge", "hardness": 0.9, "sharpness": 0.9, "point": at, "dir": -side, "axis": PD.quat_of(h) * Vector3(0, 0, 1), "edge": -side})
		k += 1
		await _steps(3)
	t.check(ch.flap_of == null and v.flaps.is_empty(), "a blow at the strip it hangs by drops it (%d)" % k)
	await _steps(90)
	t.check(ch.global_position.y < 0.6, "and it falls to the sand (%.2f)" % ch.global_position.y)
	m.queue_free()
