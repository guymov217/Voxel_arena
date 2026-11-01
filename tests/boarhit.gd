extends Node
## The same blows on every beast (user: the boar hardly loses a voxel to a blow): an axe's chop
## from above onto the back, from the side into the flank and onto a foreleg, a mace's blow and
## a thrust, each at two strengths, each on a fresh beast. Where the blow lands is where a
## weapon meets the part's box (its collision shape), as in a fight. How many voxels each took,
## and how far below the spot struck the flesh began (`-- --probe boarhit`). BEASTS: species.

func _first_flesh(part: VoxelPart, lp: Vector3, ld: Vector3, r: float) -> float:
	var best := INF
	for i in part.fx.size():
		if part.alive[i] == 0:
			continue
		var d := part.local_of(i) - lp
		var along := d.dot(ld)
		if (d - ld * along).length() < r:
			best = minf(best, along)
	return best

func _ready() -> void:
	var list := OS.get_environment("BEASTS").split(",", false)
	if list.is_empty():
		list = PackedStringArray(["boar", "wolf", "lion", "bear", "bull"])
	var blows := [
		["axe top", "edge", "beastBody", Vector3.DOWN],
		["axe rear", "edge", "beastBody", Vector3.DOWN],
		["axe side", "edge", "beastBody", Vector3.LEFT],
		["axe leg", "edge", "legFL", Vector3.RIGHT],
		["mace top", "blunt", "beastBody", Vector3.DOWN],
		["thrust", "point", "beastBody", Vector3.LEFT],
	]
	for sp in list:
		for b in blows:
			for J in [12.0, 24.0]:
				var m := Match.new()
				add_child(m)
				m.setup({"mode": "training", "training": {"enemy": sp, "immortal": true}, "headless": true, "seed": 3, "decrees": [], "hazards": []})
				m.me.f.teleport(Vector3(-14, 0, 10))
				var beast: Beast = null
				for e in m.entities:
					if e.f is Beast:
						beast = e.f
						e.drive = func(_e): return {}
				for i in 60:
					await get_tree().physics_frame
				var part: VoxelPart = beast.by_name.get(b[2])
				if part == null:
					m.queue_free()
					continue
				var q := part.global_transform.basis.orthonormalized()
				var dir_w: Vector3 = b[3]
				var ld := (q.inverse() * dir_w).normalized()
				# The spot on the box face the blow comes through: its middle, or (rear) a third of
				# the way back from the middle along the body.
				var lp := -ld * (absf(ld.x) * part.half_ext.x + absf(ld.y) * part.half_ext.y + absf(ld.z) * part.half_ext.z)
				if b[0] == "axe rear":
					lp += Vector3(0, 0, -part.half_ext.z * 0.45)
				var p_w := part.global_transform * lp
				var gap := _first_flesh(part, lp, ld, part.vf * part.part_scale * 1.5)
				var axis_w := (q * Vector3(0, 0, 1)) if absf(ld.z) < 0.7 else (q * Vector3(1, 0, 0))
				var hit := {"impulse": J, "type": b[1], "hardness": 0.85, "sharpness": 0.8 if b[1] != "blunt" else 0.0, "point": p_w, "dir": dir_w, "axis": dir_w if b[1] == "point" else axis_w, "edge": dir_w, "heavy": 0.2, "wsz": 1.0, "weapon": true, "thrust": 0.8 if b[1] == "point" else 0.0}
				var before := part.alive_count
				var res: Dictionary = beast.apply_hit(part, hit)
				var n := 0
				for r in res.get("removed", []):
					n += (r.indices as Array).size()
				print("HIT %-5s %-9s J %4.0f  took %4d voxels (part %d -> %d)  flesh starts %5.2f vox below the box  dmg %5.1f%s" % [sp, b[0], J, n, before, part.alive_count, gap / (part.vf * part.part_scale), float(res.get("dmg", 0.0)), "  bone" if res.get("bone", false) else ""])
				m.queue_free()
				await get_tree().physics_frame
	get_tree().quit()
