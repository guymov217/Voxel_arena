extends Node
## Nothing in the arena is armoured by being drawn outside the voxels: every part of every
## creature loses voxels to a hard cut or a hard blow.

var t

func test_every_part_of_every_creature_can_be_hurt() -> void:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none"}, "headless": true, "seed": 3})
	m.me.f.teleport(Vector3(12, 0, 12))
	var bad := []
	var n := 0
	for sp in Data.beasts.keys():
		var e = m.spawn_beast({"beast": sp, "team": 1, "pos": Vector3(0, 0.1, 0), "yaw": 0.0})
		var f = e.f
		for i in 5:
			await get_tree().physics_frame
		for part in f.parts:
			if part.severed:
				continue
			n += 1
			var before: int = part.alive_count
			var h: Vector3 = part.half_ext
			var pw: Vector3 = part.global_transform * Vector3(h.x, 0, 0)
			var dir: Vector3 = -(part.global_transform.basis * Vector3.RIGHT).normalized()
			f.apply_hit(part, {"impulse": 45.0, "type": "edge", "hardness": 0.8, "sharpness": 0.9, "point": pw, "dir": dir, "axis": part.global_transform.basis * Vector3.FORWARD, "edge": dir, "heavy": 0.5})
			var after_cut: int = part.alive_count
			if not part.severed:
				f.apply_hit(part, {"impulse": 45.0, "type": "blunt", "hardness": 0.8, "point": pw, "dir": dir, "heavy": 0.5})
			if after_cut >= before and part.alive_count >= after_cut:
				bad.append("%s.%s(S %.1f)" % [sp, part.part_name, float(f.S)])
		m.entities.erase(e); m.combat.fighters.erase(f); f.queue_free()
		await get_tree().physics_frame
	t.check(bad.is_empty(), "every one of %d parts of every creature loses voxels to a hard cut or blow (untouched: %s)" % [n, ", ".join(bad)])
	m.queue_free()

## Nothing stays on a body it is not joined to by voxels: the elbow end of the upper arm gone,
## the forearm (and the hand with it) falls; the flesh at the neck gone, the head falls.
func test_a_part_joined_to_nothing_falls() -> void:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none"}, "headless": true, "seed": 5})
	var f: Fighter = m.me.f
	for i in 30:
		await get_tree().physics_frame
	var up: VoxelPart = f.arm.R.upper
	var fore: VoxelPart = f.arm.R.fore
	var pt := up.anchor_point(fore)
	var near := []
	for i in up.fx.size():
		if up.alive[i] and up.local_of(i).distance_to(pt) < up.vf * up.part_scale * 2.4:
			near.append(i)
	t.check(not near.is_empty() and near.size() < up.alive_count, "the elbow end of the upper arm (%d of %d voxels)" % [near.size(), up.alive_count])
	up.remove_voxels(near)
	for i in 60:
		await get_tree().physics_frame
	t.check(fore.severed, "the forearm, joined to nothing, has fallen off")
	t.check(not up.severed, "the rest of the upper arm stays on")
	var tor := f.torso
	var neck := []
	var hp := tor.anchor_point(f.head)
	for i in tor.fx.size():
		if tor.alive[i] and tor.local_of(i).distance_to(hp) < tor.vf * tor.part_scale * 2.4:
			neck.append(i)
	tor.remove_voxels(neck)
	for i in 60:
		await get_tree().physics_frame
	t.check(f.head.severed, "the neck's flesh gone, the head falls")
	m.queue_free()

## A man's sword takes a giant apart as it takes a man, only slower: a thigh too broad for the
## blade is chopped through blow by blow, and once the slot is through the blade widens it
## until the leg is off (it used to hang by its sides for good); the same at the neck of a
## giant's head or a beast's. The blows land on one spot, as a player's aimed at a wound do.
func _root_spot(part: VoxelPart) -> Array:
	var vfs: float = part.vf * part.part_scale
	var ra: Array = part._root_axis()
	var ax: int = ra[0]
	var cx: int = 0 if ax != 0 else 2
	var la_ax: int = 3 - ax - cx
	var root: float = maxf(0.0, part.half_ext[ax] - 1.6 * vfs) * (1.0 if ra[1] else -1.0)
	var best := Vector3.ZERO
	var best_d := -INF
	for i in part.fx.size():
		if not part.alive[i]:
			continue
		var v: Vector3 = part.local_of(i)
		if absf(v[ax] - root) > vfs * 0.6 or absf(v[la_ax]) > vfs * 1.2:
			continue
		if v[cx] > best_d:
			best_d = v[cx]
			best = v
	var lp := best
	lp[cx] += vfs * 0.5 + 0.01
	var ld := Vector3.ZERO
	ld[cx] = -1.0
	var la := Vector3.ZERO
	la[la_ax] = 1.0
	return [lp, ld, la]

func _sword_at(c, part: VoxelPart, spot: Array) -> Dictionary:
	var b: Basis = part.global_transform.basis.orthonormalized()
	return c.apply_hit(part, {"impulse": 60.0, "type": "edge", "hardness": 0.9, "sharpness": 1.0, "heavy": 1.0, "wsz": 1.0, "point": part.to_global(spot[0]), "dir": b * spot[1], "axis": b * spot[2], "edge": b * spot[1]})

func _blows_to_sever(c, part: VoxelPart, cap: int) -> int:
	var spot := _root_spot(part)
	for n in cap:
		if part.severed:
			return n
		_sword_at(c, part, spot)
		c.blood = 100.0
		c.alive = true
	return cap if part.severed else -1

func test_a_mans_sword_takes_a_giants_limbs_and_head_off_blow_by_blow() -> void:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none"}, "headless": true, "seed": 5})
	m.me.f.teleport(Vector3(12, 0, 12))
	var spec: Dictionary = m.enemy_spec({"e": "giant"}, 0, 1)
	spec.pos = Vector3(0, 0.1, 0)
	var g = m.spawn_fighter(spec).f
	for i in 30:
		await get_tree().physics_frame
	t.check(g.S >= 3.5, "the giant is a giant (S %.1f)" % g.S)
	for pn in ["forearmR", "upperArmR", "shinR", "thighR", "head"]:
		var n := _blows_to_sever(g, g.by_name[pn], 20)
		t.check(n >= 1 and n <= 14, "a man's sword takes the giant's %s off in %s blows at one spot (at most 14)" % [pn, str(n) if n >= 0 else "more than 20"])
	m.entities.erase(m.entities.back()); m.combat.fighters.erase(g); g.queue_free()
	await get_tree().physics_frame
	for sp in ["lion", "gorilla", "elephant"]:
		var e = m.spawn_beast({"beast": sp, "team": 1, "pos": Vector3(0, 0.1, 0), "yaw": 0.0})
		var f = e.f
		for i in 30:
			await get_tree().physics_frame
		for part in [f.by_name["legFR"], f.head]:
			var n := _blows_to_sever(f, part, 30)
			t.check(n >= 1 and n <= 24, "a man's sword takes the %s's %s off in %s blows at one spot (at most 24)" % [sp, part.part_name, str(n) if n >= 0 else "more than 30"])
		m.entities.erase(e); m.combat.fighters.erase(f); f.queue_free()
		await get_tree().physics_frame
	m.queue_free()
