extends Node
## The same fight, step for step, and a fingerprint of every body each second
## (`--headless --fixed-fps 120 -- --probe replay_dump`): two builds that print the same lines
## play the game the same way, to the last bit of every body's place and turn. Used to check
## that a faster implementation (the C++ core, a cache) changes nothing.

const SECONDS := 10

func _ready() -> void:
	seed(12345)
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none"}, "headless": true, "seed": 7, "decrees": [], "hazards": []})
	m.me.f.teleport(Vector3(0, 0, -14))
	var foes := ["recruit", "shieldbearer", "brute", "murmillo"]
	var beasts := ["wolf", "lion", "bear", "boar"]
	var weapons := ["gladius", "axe", "mace", "spear"]
	var n := int(OS.get_environment("REPLAY_N")) if OS.get_environment("REPLAY_N") != "" else 16
	for i in n:
		var a := TAU * i / n
		var pos := Vector3(sin(a) * 4.0, 0.1, cos(a) * 4.0)
		if i % 2 == 0:
			m.spawn_fighter({"kind": "bot", "name": "P%d" % i, "loadout": {"main": weapons[i % 4], "off": "roundShield" if i % 4 == 0 else ""}, "team": 0, "pos": pos, "yaw": a + PI, "diff": 0.8})
		elif i % 4 == 1:
			var spec: Dictionary = m.enemy_spec({"e": foes[(i / 4) % foes.size()]}, 0, 1)
			spec.pos = pos
			spec.yaw = a + PI
			m.spawn_fighter(spec)
		else:
			m.spawn_beast({"beast": beasts[(i / 4) % beasts.size()], "team": Match.ENEMY_TEAM, "pos": pos, "yaw": a + PI})
	var hits := [0]
	m.combat.hit.connect(func(_h): hits[0] += 1)
	for s in SECONDS:
		for k in 120:
			await get_tree().physics_frame
		var ctx := HashingContext.new()
		ctx.start(HashingContext.HASH_MD5)
		var alive := 0
		for e in m.entities:
			if not is_instance_valid(e.f):
				continue
			alive += 1 if e.f.alive else 0
			ctx.update(Match.pack_parts(e.f.parts))
			var hp := PackedFloat32Array()
			for p in e.f.parts:
				hp.append(p.hp)
				hp.append(float(p.alive_count))
			ctx.update(hp.to_byte_array())
			for side in ["R", "L"]:
				var w = e.f.weapons.get(side)
				if w:
					ctx.update(Match.pack_parts([w]))
		print("REPLAY s=%d alive=%d hits=%d %s" % [s, alive, hits[0], ctx.finish().hex_encode()])
	get_tree().quit()
