extends Node
## The hydra's heads at a man standing with sword and shield (test_beast_attacks: its bites
## land seldom): each strike of each head, how near the head came to his body, and what came of
## it (a bite on him, or nothing). `-- --probe hydralog`. SEED (8), SECS (25), LOAD (gladius+roundShield).

func _ready() -> void:
	var sd := int(OS.get_environment("SEED")) if OS.get_environment("SEED") != "" else 8
	var secs := float(OS.get_environment("SECS")) if OS.get_environment("SECS") != "" else 25.0
	var ld := (OS.get_environment("LOAD") if OS.get_environment("LOAD") != "" else "gladius+roundShield").split("+")
	seed(sd)
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none"}, "headless": true, "seed": 3, "loadout": {"main": ld[0], "off": ld[1] if ld.size() > 1 else ""}})
	var man: Fighter = m.me.f
	man.teleport(Vector3(0, 0, 0))
	man.mods.toughness = 3.0
	var e = m.spawn_beast({"beast": "hydra", "team": Match.ENEMY_TEAM, "pos": Vector3(0, 0.1, 6.0), "yaw": PI})
	var b: Beast = e.f
	var bites := [0]
	m.combat.hit.connect(func(h):
		if h.attacker == b and h.char == man:
			bites[0] += 1
			print("  %5.2f BITE %s on %s J %.0f" % [m.time, String(h.att_part.part_name) if h.get("att_part") else "?", String(h.part.part_name) if h.get("part") else "?", float(h.J)]))
	var open := {}     # head -> {"t", "near", "shield"}
	var strikes := 0
	var near_t := 0
	for i in int(secs * 120):
		man.blood = 100.0
		man.head.hp = maxf(man.head.hp, 40.0)
		man.torso.hp = maxf(man.torso.hp, 40.0)
		b.target = man
		await get_tree().physics_frame
		var gap := Vector2(b.torso.global_position.x - man.torso.global_position.x, b.torso.global_position.z - man.torso.global_position.z).length()
		if gap < 2.0 * b.S:
			near_t += 1
		for h in b.heads:
			if not is_instance_valid(h) or h.severed:
				continue
			var live: bool = b.strikes.has(h) and float(b.wind.get(h, 0.0)) <= 0.0
			if live and not open.has(h):
				open[h] = {"t": m.time, "near": 99.0, "shield": 99.0}
				strikes += 1
			if open.has(h):
				var o: Dictionary = open[h]
				for p in man.parts:
					if not p.severed:
						o.near = minf(o.near, h.global_position.distance_to(p.global_position) - h.half_ext.length() * 0.6 - p.half_ext.length() * 0.6)
				var sh = man.weapons.get("L")
				if sh and sh.is_shield:
					o.shield = minf(o.shield, h.global_position.distance_to(sh.global_position))
				if not live:
					print("  %5.2f strike %-6s gap %.1f  nearest to him %.2f m  shield %.2f m" % [o.t, String(h.part_name), gap, o.near, o.shield])
					open.erase(h)
	print("hydra: %d strikes, %d bites in %.0f s; %.0f s within two lengths" % [strikes, bites[0], secs, near_t / 120.0])
	get_tree().quit()
