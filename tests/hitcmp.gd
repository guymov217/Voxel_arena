extends Node
## The same blows as new_project/tools/_hitcmp.mjs (the web game's applyHit), one fresh fighter
## per blow, headless: voxels removed, damage, what came off. `-- --probe hitcmp`.

func _ready() -> void:
	var parts := ["upperArmR", "forearmL", "thighL", "shinR", "torso", "head"]
	var blows := [["edge", 8, 0.9, 0.8, 0.0], ["edge", 15, 0.9, 0.8, 0.0], ["edge", 25, 0.9, 0.8, 0.3], ["edge", 40, 0.9, 0.9, 0.8], ["blunt", 10, 0.6, 0.0, 0.0], ["blunt", 20, 0.6, 0.0, 0.0], ["blunt", 35, 0.6, 0.0, 0.5], ["point", 8, 0.9, 0.9, 0.0], ["point", 20, 0.9, 0.9, 0.3]]
	for pn in parts:
		for b in blows:
			var w := TestWorld.new()
			add_child(w)
			w.ready_arena()
			var c := w.fighter(Vector3.ZERO, 0.0, {}, {"name": "A"})
			for i in 30:
				c.control(1.0 / 120.0, {})
				await get_tree().physics_frame
			var part: VoxelPart = c.by_name[pn]
			var q := PD.quat_of(part)
			var ctr := part.global_position
			var half := Vector3(part.dims.x, part.dims.y, part.dims.z) * Fighter.V * 0.5 * part.part_scale
			var p: Vector3 = ctr + q * (Vector3(0, 0, 1) * half * 1.02)
			var dir := (ctr - p).normalized()
			var axis := q * Vector3(1, 0, 0)
			var res: Dictionary = c.apply_hit(part, {"impulse": float(b[1]), "type": b[0], "hardness": b[2], "sharpness": b[3], "point": p, "dir": dir, "axis": dir if b[0] == "point" else axis, "edge": dir, "heavy": b[4]})
			var removed: int = res.removed.reduce(func(s, r): return s + r.indices.size(), 0)
			print("%s %s J=%d heavy=%s: removed %d/%d dmg %.1f severed %s hanging %s" % [pn, b[0], b[1], b[4], removed, part.fx.size(), res.dmg, res.severed.map(func(x): return x.part_name), res.hanging.part_name if res.get("hanging") else "-"])
			w.queue_free()
			await get_tree().physics_frame
	get_tree().quit()
