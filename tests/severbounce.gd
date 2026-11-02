extends Node
## A leg cut off the training dummy (user: the leg started jumping about the arena and moving on
## its own). The dummy as the training ring sets him up; the left leg taken off at the thigh,
## by the blows of a blade (CUT=blows) or at once (CUT=detach); then the severed thigh and shin
## are followed for TRACK_S seconds: how far they travel once they should be lying on the sand,
## how often they hop, their top speed after the first second. `-- --probe severbounce`.
## YARD=1: the yard's own dummy; TRACE=1: the pieces and the dummy twice a second.

func _ready() -> void:
	var how := OS.get_environment("CUT") if OS.get_environment("CUT") != "" else "both"
	var secs := float(OS.get_environment("TRACK_S")) if OS.get_environment("TRACK_S") != "" else 10.0
	for mode in (["blows", "detach"] if how == "both" else [how]):
		for leg in ["thighL", "shinR"]:
			var m := Match.new()
			add_child(m)
			var d: Fighter
			if OS.get_environment("YARD") != "":
				# The yard's own dummy, kept from bleeding out by the yard as in the game.
				m.setup({"mode": "yard", "headless": true, "seed": 2, "decrees": [], "hazards": [], "loadout_override": {"main": "gladius", "off": ""}})
				d = m.yard.dummies[0]
			else:
				m.setup({"mode": "training", "training": {"enemy": "none", "respawn": false}, "headless": true, "seed": 2, "decrees": [], "hazards": [], "loadout": {"main": "gladius", "off": ""}})
				var e = m.spawn_fighter({"kind": "npc", "name": "Training dummy", "loadout": {"main": "", "off": ""}, "team": Match.ENEMY_TEAM,
					"pos": Vector3(0, 0.02, -2.0), "yaw": 0.0, "mods": {"toughness": 3.0}, "color": 0xb08a5a})
				e.drive = func(_e): return {}
				e.harmless = true
				d = e.f
			for i in 120:
				await get_tree().physics_frame
			var part: VoxelPart = d.by_name[leg]
			if mode == "detach":
				d.detach_limb(part, {"removed": [], "severed": []})
			else:
				var n := 0
				while not part.severed and n < 60:
					n += 1
					var side := Vector3(1, 0, 0) if leg.ends_with("L") else Vector3(-1, 0, 0)
					var pt: Vector3 = part.global_position + side * part.half_ext.x
					d.apply_hit(part, {"impulse": 45.0, "type": "edge", "hardness": 0.9, "sharpness": 0.95, "point": pt, "dir": -side, "axis": Vector3(0, 0, 1), "edge": -side, "heavy": 0.4, "weapon": true, "mass": 1.5})
					await get_tree().physics_frame
				if not part.severed:
					print("%-6s %-7s never came off in %d blows" % [mode, leg, n])
					m.queue_free()
					continue
			var pieces: Array = d.parts.filter(func(p): return p.severed and not p.missing)
			var path := 0.0
			var hops := 0
			var top := 0.0
			var prev := {}
			var was_up := {}
			for p in pieces:
				prev[p] = p.global_position
				was_up[p] = false
			for i in int(secs * 120):
				await get_tree().physics_frame
				for p in pieces:
					if not is_instance_valid(p):
						continue
					if i >= 120:
						path += (p.global_position - prev[p]).length()
						top = maxf(top, p.linear_velocity.length())
						var up: bool = p.linear_velocity.y > 1.0
						if up and not was_up[p]:
							hops += 1
						was_up[p] = up
					prev[p] = p.global_position
				if OS.get_environment("TRACE") != "" and i % 60 == 0:
					var desc := []
					for p in pieces:
						if is_instance_valid(p):
							desc.append("%s y %.2f v %.2f w %.1f" % [p.part_name, p.global_position.y, p.linear_velocity.length(), p.angular_velocity.length()])
					print("   t %4.1f  dummy %s blood %.0f  %s" % [i / 120.0, d.state, d.blood, ", ".join(desc)])
			var lowest := INF
			for p in pieces:
				if is_instance_valid(p):
					lowest = minf(lowest, p.global_position.y)
			print("%-6s %-7s %d pieces; after the first second: travelled %.2f m, %d hops, top speed %.2f m/s; lowest centre %.2f m" % [mode, leg, pieces.size(), path, hops, top, lowest])
			m.queue_free()
			await get_tree().physics_frame
	get_tree().quit()
