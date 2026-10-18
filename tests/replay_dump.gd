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
	var offs := []
	var r := 4.0
	# REPLAY_MIX: the rest of the game's ways of fighting (bows, two hands, chains, throwing,
	# bare fists, two blades), its archers, net men and giants, and a dozen more creatures.
	if OS.get_environment("REPLAY_MIX") != "":
		foes = ["sagittarius", "retiarius", "dimachaerus", "cyclops", "minotaur", "hoplite", "veles", "flailman"]
		beasts = ["python", "gorilla", "elephant", "scorpion", "crocodile", "ostrich", "hydra", "griffin", "rhino", "spider", "cerberus", "tiger"]
		weapons = ["bow", "zweihander", "flail", "javelin", "", "whip", "crossbow", "nunchaku", "warhammer", "meteorHammer", "dagger", "trident"]
		offs = ["", "", "scutum", "", "", "", "", "", "", "", "dagger", ""]
		r = 6.5
	var n := int(OS.get_environment("REPLAY_N")) if OS.get_environment("REPLAY_N") != "" else 16
	var off := int(OS.get_environment("REPLAY_OFF")) if OS.get_environment("REPLAY_OFF") != "" else 0   # which foes and creatures come first
	for i in n:
		var a := TAU * i / n
		var pos := Vector3(sin(a) * r, 0.1, cos(a) * r)
		if i % 2 == 0:
			var lo := {"main": weapons[i % 4], "off": "roundShield" if i % 4 == 0 else ""}
			if weapons.size() > 4:
				var wi := (i / 2) % weapons.size()
				lo = {"main": weapons[wi], "off": offs[wi]}
			m.spawn_fighter({"kind": "bot", "name": "P%d" % i, "loadout": lo, "team": 0, "pos": pos, "yaw": a + PI, "diff": 0.8})
		elif i % 4 == 1:
			var spec: Dictionary = m.enemy_spec({"e": foes[(i / 4 + off) % foes.size()]}, 0, 1)
			spec.pos = pos
			spec.yaw = a + PI
			m.spawn_fighter(spec)
		else:
			m.spawn_beast({"beast": beasts[(i / 4 + off) % beasts.size()], "team": Match.ENEMY_TEAM, "pos": pos, "yaw": a + PI})
	var t_start := Time.get_ticks_usec()
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
	# (Not a REPLAY line: the time is the machine's, the fingerprints are the game's.)
	print("TIMING %.3f ms a step" % ((Time.get_ticks_usec() - t_start) / 1000.0 / (SECONDS * 120)))
	get_tree().quit()
