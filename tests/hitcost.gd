extends Node
## What one nail's hit costs (nailprof.gd: ~25 ms an apply_hit, nine in a step): the whole
## apply_hit on a man's trunk, and on its own each thing it does after the voxels are chosen.
## `-- --probe hitcost`.

func _us(c: Callable) -> float:
	var t0 := Time.get_ticks_usec()
	c.call()
	return (Time.get_ticks_usec() - t0) / 1000.0

func _ready() -> void:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none", "respawn": false}, "headless": true, "seed": 3})
	var e = m.spawn_fighter({"kind": "bot", "name": "D", "loadout": {"main": "gladius"}, "team": 1, "pos": Vector3(3, 0, 0), "yaw": 0.0})
	e.erase("bot")
	e.drive = func(_e): return {}
	for i in 60:
		await get_tree().physics_frame
	var f: Fighter = e.f
	for name in ["torso", "thighL", "upperArmR", "head"]:
		var part: VoxelPart = f.by_name[name]
		var p := part.global_transform * Vector3(0, 0, part.half_ext.z)
		var hd := (part.global_position - p).normalized()
		var hit := {"impulse": 3.6, "type": "point", "hardness": 1.0, "sharpness": 1.0, "point": p + hd * 0.01, "dir": hd, "axis": hd, "wsz": 0.5, "weapon": true}
		var whole := _us(func(): f.apply_hit(part, hit))
		var lumps := _us(func(): part.loose_lumps())
		var fit := _us(func(): part.fit_collider())
		var thin := _us(func(): part.thin_ratio())
		var flaps := _us(func(): f._make_flaps(part, {"removed": [], "severed": [], "dmg": 0.0}))
		var near := part.voxels_within(part.local_of(0), 0.05)
		var rem := _us(func(): part.remove_voxels(Array(near).slice(0, 3)))
		var belly := _us(func(): f._check_belly({"removed": [], "severed": [], "dmg": 0.0})) if part == f.torso else 0.0
		var whole2 := _us(func(): f.apply_hit(part, hit))
		print("COST %-9s voxels %5d  apply_hit %.1f ms  loose_lumps %.1f  fit_collider %.1f  thin_ratio %.1f  make_flaps %.1f  remove 3 voxels %.1f  check_belly %.1f  apply_hit again %.1f" % [name, part.fx.size(), whole, lumps, fit, thin, flaps, rem, belly, whole2])
	get_tree().quit()
