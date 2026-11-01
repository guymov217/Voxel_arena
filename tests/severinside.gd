extends Node
## A cut-off arm that ends up inside its owner (user: the severed left arm floated inside his
## body): an arm cut off while a blow drives it into the chest, the man turning or stepping
## after it, at several strengths; where each piece is 3 s later against the trunk's box.
## `-- --probe severinside`.

func _ready() -> void:
	var bad := 0
	var runs := 0
	for push in [0.0, 2.0, 5.0, 9.0]:
		for turn in [0.0, 1.5]:
			for which in ["upperArmL", "forearmL"]:
				var m := Match.new()
				add_child(m)
				m.setup({"mode": "training", "training": {"enemy": "none", "respawn": false}, "headless": true, "seed": 3, "loadout": {"main": "gladius", "off": "", "armor": ["manica"]}})
				var f: Fighter = m.me.f
				var t := [0.0]
				m.me.drive = func(_e):
					t[0] += 1.0 / 120.0
					return {"main": {"x": 0.1, "y": 0.15}, "look": {"yaw": turn * minf(1.0, t[0]), "pitch": 0.0}, "mz": 0.6 if turn > 0.0 and t[0] < 1.0 else 0.0}
				for i in 90:
					await get_tree().physics_frame
				var part: VoxelPart = f.by_name[which]
				var res := {"removed": [], "severed": [], "dmg": 0.0}
				f.detach_limb(part, res)
				# The blow that took it drives it in toward the middle of his chest.
				var into: Vector3 = (f.torso.global_position - part.global_position)
				part.apply_central_impulse(into.normalized() * push * part.mass)
				for i in 360:
					await get_tree().physics_frame
				runs += 1
				var tinv := f.torso.global_transform.affine_inverse()
				for p in f.parts:
					if p.severed and not p.missing:
						var l: Vector3 = tinv * p.global_position
						var e: Vector3 = f.torso.half_ext + Vector3.ONE * 0.04
						var inside := absf(l.x) < e.x and absf(l.y) < e.y and absf(l.z) < e.z
						if inside:
							bad += 1
						print("INSIDE? push %.0f turn %.1f cut %-9s piece %-9s at %s from the trunk, %.2f m up off the sand%s" % [push, turn, which, p.part_name, str(l.snapped(Vector3(0.01, 0.01, 0.01))), p.global_position.y, "  <-- INSIDE THE TRUNK" if inside else ""])
				m.queue_free()
				for i in 3:
					await get_tree().physics_frame
	print("INSIDE %d pieces inside the trunk after %d cuts" % [bad, runs])
	get_tree().quit()
