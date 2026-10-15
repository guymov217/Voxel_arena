extends Node
## The giants of myth land their weapons on a man a third their size: each is let at a man for
## a while and must hit him with what it carries, not swing over his head.

var t

func _bout(kind: String, seconds: float, down: bool) -> Dictionary:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none"}, "headless": true, "seed": 5})
	var man: Fighter = m.me.f
	man.teleport(Vector3(0, 0, 0))
	man.mods.toughness = 4.0
	var spec: Dictionary = m.enemy_spec({"e": kind}, 0, 1)
	spec.pos = Vector3(0, 0.1, 7.0)
	spec.yaw = PI
	spec.diff = 0.6
	var e = m.spawn_fighter(spec)
	var g: Fighter = e.f
	var hits := {"weapon": 0, "any": 0, "J": 0.0, "first": -1.0, "killed": false}
	m.combat.hit.connect(func(h):
		if h.attacker == g and h.char == man:
			hits.any += 1
			if h.get("weapon") != null:
				hits.weapon += 1
				hits.J = maxf(hits.J, float(h.J))
				if hits.first < 0.0:
					hits.first = m.time
				if h.get("killed", false):
					hits.killed = true)
	for i in int(seconds * 120):
		man.blood = 100.0
		man.head.hp = maxf(man.head.hp, 40.0)
		man.torso.hp = maxf(man.torso.hp, 40.0)
		for p in man.parts:
			p.hp = maxf(p.hp, 30.0)
		if down and man.state == "stand":
			man.fall(2.0, true)
		await get_tree().physics_frame
		if not man.alive:
			break
	hits["S"] = g.S
	hits["weapon_name"] = String(g.weapons.R.design.name) if g.weapons.get("R") else "-"
	m.queue_free()
	return hits

func test_every_giant_lands_its_weapon_on_a_man() -> void:
	seed(7)
	for kind in ["cyclops", "giant", "minotaur", "troll", "titan"]:
		var h := await _bout(kind, 12.0, false)
		var msg := "%s (S %.1f, %s) lands its weapon on a standing man (first hit at %.1fs, J %.0f)" % [kind, h.S, h.weapon_name, h.first, h.J]
		printerr("   : " + msg)
		t.check(h.weapon >= 1 and h.first < 10.0, msg)
		var heavy := 40.0 if h.S >= 2.3 else 25.0   # the minotaur is a bull-man, not a titan
		t.check(h.J >= heavy or h.killed, "%s: and the blow is a giant's (J %.0f, killed %s)" % [kind, h.J, str(h.killed)])

func test_every_giant_reaches_a_man_on_the_sand() -> void:
	seed(8)
	for kind in ["cyclops", "giant", "titan"]:
		var h := await _bout(kind, 14.0, true)
		var msg := "%s brings its weapon down on a man on the sand (first hit at %.1fs, J %.0f)" % [kind, h.first, h.J]
		printerr("   : " + msg)
		t.check(h.weapon >= 1 and h.first < 12.0, msg)
