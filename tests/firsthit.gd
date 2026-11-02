extends Node
## The first blow on a creature's trunk cost ten times the next (blowcost.gd: 40-53 ms on a
## dragon's or a gorilla's body, then 2-7): where each limb is rooted in the trunk was found by
## going over all its voxels, once per limb, and the guts' voxels were looked for among all of
## them, both at the first wound. Each stage of a hit timed twice on a fresh trunk.
## `-- --probe firsthit`. FOE (dragon).

func _us(c: Callable) -> float:
	var t0 := Time.get_ticks_usec()
	c.call()
	return (Time.get_ticks_usec() - t0) / 1000.0

func _ready() -> void:
	var foe := OS.get_environment("FOE") if OS.get_environment("FOE") != "" else "dragon"
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none"}, "headless": true, "seed": 3, "decrees": [], "hazards": []})
	var e = m.spawn_beast({"beast": foe, "team": Match.ENEMY_TEAM, "pos": Vector3(0, 0.1, 6.0), "yaw": PI, "harmless": true})
	var b: Beast = e.f
	for i in 120:
		await get_tree().physics_frame
	var part: VoxelPart = b.torso
	print("trunk voxels %d" % part.fx.size())
	for round_ in 2:
		var near: PackedInt32Array = part.voxels_within(part.local_of(0), 0.05)
		var row := {
			"voxels_within": _us(func(): part.voxels_within(part.local_of(0), 0.15)),
			"loose_lumps": _us(func(): part.loose_lumps()),
			"thin_ratio": _us(func(): part.thin_ratio()),
			"fit_collider": _us(func(): part.fit_collider()),
			"remove 3": _us(func(): part.remove_voxels(Array(near).slice(0, 3))),
		}
		var dir := Vector3(0, 0, 1) if round_ == 0 else Vector3(1, 0, 0)
		row["apply_hit"] = _us(func(): b.apply_hit(part, {"impulse": 30.0, "type": "edge", "hardness": 0.8, "sharpness": 0.8, "point": part.global_position - dir * (part.half_ext.z if round_ == 0 else part.half_ext.x), "dir": dir, "axis": Vector3.UP, "edge": Vector3.RIGHT if round_ == 0 else Vector3.BACK, "heavy": 0.2, "weapon": true, "mass": 1.2}))
		print("round %d: %s" % [round_ + 1, str(row)])
	get_tree().quit()
