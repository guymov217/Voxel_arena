extends Node
## Why an axe straight down on the middle of a boar's back takes two voxels (boarhit.gd): where
## the blow is carried to (Fighter._to_flesh), and which voxels lie in the cut from there.
## `-- --probe boartop`.

func _ready() -> void:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "boar", "immortal": true}, "headless": true, "seed": 3, "decrees": [], "hazards": []})
	m.me.f.teleport(Vector3(-14, 0, 10))
	var beast: Beast = null
	for e in m.entities:
		if e.f is Beast:
			beast = e.f
			e.drive = func(_e): return {}
	for i in 60:
		await get_tree().physics_frame
	var part: VoxelPart = beast.torso
	var q := part.global_transform.basis.orthonormalized()
	var ld := (q.inverse() * Vector3.DOWN).normalized()
	var lp := -ld * (absf(ld.x) * part.half_ext.x + absf(ld.y) * part.half_ext.y + absf(ld.z) * part.half_ext.z)
	var S: float = beast.S
	var vfs := part.vf * part.part_scale
	var snapped: Vector3 = Fighter._to_flesh(part, lp, ld, Fighter.V * S * 1.2, Fighter.V * S * 3.0)
	print("TOP lp %s -> %s (moved %.2f vox)  ld %s  half_ext %s  vfs %.3f" % [str(lp.snapped(Vector3(0.001, 0.001, 0.001))), str(snapped.snapped(Vector3(0.001, 0.001, 0.001))), (snapped - lp).length() / vfs, str(ld.snapped(Vector3(0.01, 0.01, 0.01))), str(part.half_ext), vfs])
	var la := (q.inverse() * (q * Vector3(0, 0, 1))).normalized()
	var n := la.cross(ld).normalized()
	var width := Fighter.V * 1.0 * 0.85
	var span := 0.256
	for depth in [0.054, 0.1, 0.2]:
		var cnt := 0
		var bones := 0
		for i in part.fx.size():
			if part.alive[i] == 0:
				continue
			var d := part.local_of(i) - snapped
			if absf(d.dot(n)) < width and d.dot(ld) > -Fighter.V * S and d.dot(ld) < depth and absf(d.dot(la)) < span:
				cnt += 1
				if part.bone[i]:
					bones += 1
		print("TOP slab to depth %.3f: %d voxels (%d bone)" % [depth, cnt, bones])
	var res: Dictionary = beast.apply_hit(part, {"impulse": 24.0, "type": "edge", "hardness": 0.85, "sharpness": 0.8, "point": part.global_transform * lp, "dir": Vector3.DOWN, "axis": q * Vector3(0, 0, 1), "edge": Vector3.DOWN, "heavy": 0.2, "wsz": 1.0, "weapon": true})
	var took := 0
	for r in res.get("removed", []):
		took += (r.indices as Array).size()
	print("TOP apply_hit took %d  res %s" % [took, str(res.keys())])
	get_tree().quit()
