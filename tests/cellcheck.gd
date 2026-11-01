extends Node
## VoxelPart keeps live_cell, live_coarse and the dead up as voxels go and come back (for
## loose_lumps, fit_collider and what is under a blow); after every one of many blows of every
## kind, and voxels put back, they must be what working them out afresh gives.
## `-- --probe cellcheck`.

func _check(part: VoxelPart, what: String) -> bool:
	var a := part.live_cell.duplicate()
	var b := part.live_coarse.duplicate()
	var t := part.total_coarse.duplicate()
	var dv := Array(part.dead_voxels())
	dv.sort()
	var n := 0
	for i in part.alive.size():
		n += part.alive[i]
	part._index_cells()
	var ok := a == part.live_cell and b == part.live_coarse and t == part.total_coarse and n == part.alive_count and dv == Array(part.dead_voxels())
	if not ok:
		print("CELLS WRONG after %s on %s (alive_count %d, counted %d)" % [what, part.part_name, part.alive_count, n])
	return ok

func _ready() -> void:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none", "respawn": false}, "headless": true, "seed": 5})
	var e = m.spawn_fighter({"kind": "bot", "name": "D", "loadout": {"main": "gladius"}, "team": 1, "pos": Vector3(3, 0, 0), "yaw": 0.0})
	e.erase("bot")
	e.drive = func(_e): return {}
	for i in 30:
		await get_tree().physics_frame
	var f: Fighter = e.f
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var hits := 0
	var bad := 0
	for k in 160:
		var live := f.parts.filter(func(p): return not p.severed and not p.missing and p.alive_count > 0)
		if live.is_empty() or not f.alive:
			break
		var part: VoxelPart = live[rng.randi() % live.size()]
		var p := part.global_transform * Vector3(rng.randf_range(-1, 1) * part.half_ext.x, rng.randf_range(-1, 1) * part.half_ext.y, part.half_ext.z)
		var hd := (part.global_position - p).normalized()
		var type: String = ["edge", "point", "blunt"][k % 3]
		var hit := {"impulse": rng.randf_range(4.0, 40.0), "type": type, "hardness": 1.0, "sharpness": 1.0, "point": p, "dir": hd, "axis": hd.cross(Vector3.UP).normalized() if type == "edge" else hd, "edge": hd.cross(Vector3.UP).normalized(), "wsz": 1.0, "weapon": true}
		var res: Dictionary = f.apply_hit(part, hit)
		hits += 1
		for q in f.parts:
			if not _check(q, "hit %d (%s)" % [k, type]):
				bad += 1
		# Now and then some of what a blow took goes back (a replay's mend, a net message).
		if k % 7 == 0:
			for r in res.get("removed", []):
				var rp: VoxelPart = r.part
				if is_instance_valid(rp) and not rp.severed:
					rp.restore_voxels(Array(r.indices).slice(0, 3))
					if not _check(rp, "restore after hit %d" % k):
						bad += 1
		await get_tree().physics_frame
	print("CELLCHECK %d hits, %d mismatches" % [hits, bad])
	get_tree().quit()
