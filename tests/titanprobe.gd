extends Node
## Why a titan with its war hammer lands nothing on a standing man (test_giants: first hit -1 in
## sixteen seconds, run after run; the sweep: a titan close by for nineteen seconds without a
## blow). Each of its blows: when, what kind, how far off the man stood, and how near the head
## of the hammer came to him (and where: over him, short of him, past him).
## `-- --probe titanprobe`. KIND (titan), SEED (5), BOUT_S (16).

func _ready() -> void:
	var kind := OS.get_environment("KIND") if OS.get_environment("KIND") != "" else "titan"
	var sd := int(OS.get_environment("SEED")) if OS.get_environment("SEED") != "" else 5
	var secs := float(OS.get_environment("BOUT_S")) if OS.get_environment("BOUT_S") != "" else 16.0
	seed(7)
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none"}, "headless": true, "seed": sd})
	var man: Fighter = m.me.f
	man.teleport(Vector3(0, 0, 0))
	man.mods.toughness = 4.0
	var spec: Dictionary = m.enemy_spec({"e": kind}, 0, 1)
	spec.pos = Vector3(0, 0.1, 7.0)
	spec.yaw = PI
	spec.diff = 0.6
	var e = m.spawn_fighter(spec)
	var g: Fighter = e.f
	var bot = e.get("bot")
	var w: Weapon = g.weapons.R
	print("%s S %.1f weapon %s reach %.2f two-handed %s" % [kind, g.S, String(w.design.name), w.reach, str(g.two_handed)])
	var hits := [0]
	m.combat.hit.connect(func(h):
		if h.attacker == g and h.char == man:
			hits[0] += 1
			print("   %.1f HIT %s J %.0f part %s" % [m.time, "weapon" if h.get("weapon") != null else "body", float(h.J), String(h.get("part").part_name) if h.get("part") else "?"]))
	var cur = null
	var was := ""
	for i in int(secs * 120):
		man.blood = 100.0
		man.head.hp = maxf(man.head.hp, 40.0)
		man.torso.hp = maxf(man.torso.hp, 40.0)
		for p in man.parts:
			p.hp = maxf(p.hp, 30.0)
		await get_tree().physics_frame
		var st: String = String(bot.state) if bot else "?"
		var head: Vector3 = w.global_position + PD.quat_of(w) * Vector3(0, w.reach * 0.85, 0)
		var mt: Vector3 = man.torso.global_position
		var flat := Vector2(g.torso.global_position.x - mt.x, g.torso.global_position.z - mt.z).length()
		if st == "attack" and was != "attack":
			cur = {"t": m.time, "kind": String(bot.giant_kind), "dist": flat, "near": INF, "at": Vector3.ZERO, "stam": g.stamina}
		if cur != null:
			var d := head.distance_to(mt)
			if d < float(cur.near):
				cur.near = d
				cur.at = head - mt
		if st != "attack" and was == "attack" and cur != null:
			var at: Vector3 = cur.at
			var fwd := (mt - g.torso.global_position)
			fwd.y = 0.0
			fwd = fwd.normalized()
			print("%5.1f %-7s from %.2f m: head nearest %.2f m to his chest (%.2f up, %.2f %s, %.2f aside) stamina %.0f" % [float(cur.t), String(cur.kind), float(cur.dist), float(cur.near), at.y, absf(at.dot(fwd)), "past" if at.dot(fwd) > 0.0 else "short", absf(at.dot(fwd.cross(Vector3.UP))), float(cur.stam)])
			cur = null
		if i % 120 == 0:
			print("  t %.0f state %s dist %.2f stamina %.0f titan %s man %s" % [m.time, st, flat, g.stamina, g.state, man.state])
		was = st
	print("weapon hits %d" % hits[0])
	get_tree().quit()
