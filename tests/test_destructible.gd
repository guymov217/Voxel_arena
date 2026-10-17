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
