extends Node
## Creatures attack as they should: a scorpion stings and poisons, a python coils round a man and
## crushes him, a bear rakes with its claws (cuts) and rears up to come down on him, a mammoth
## goes after him instead of keeping to its circle.

var t

func _setup(species: String, dist: float):
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none"}, "headless": true, "seed": 3})
	var man: Fighter = m.me.f
	man.teleport(Vector3(0, 0, 0))
	man.mods.toughness = 3.0
	var e = m.spawn_beast({"beast": species, "team": Match.ENEMY_TEAM, "pos": Vector3(0, 0.1, dist), "yaw": PI})
	return [m, man, e.f]

func _run(m: Match, man: Fighter, b: Beast, seconds: float, each: Callable) -> void:
	for i in int(seconds * 120):
		man.blood = 100.0
		man.head.hp = maxf(man.head.hp, 40.0)
		man.torso.hp = maxf(man.torso.hp, 40.0)
		b.target = man
		await get_tree().physics_frame
		each.call(i)

func test_the_scorpion_stings_and_poisons() -> void:
	seed(5)
	var s = _setup("scorpion", 2.6)
	var stings := [0]
	s[0].combat.hit.connect(func(h): if h.attacker == s[2] and h.get("part") and h.res and h.char == s[1] and String(h.get("weapon_part", "")) == "": pass)
	var poisoned := [false]
	await _run(s[0], s[1], s[2], 12.0, func(_i):
		if s[1].parts.any(func(p): return p.spots.any(func(x): return x.kind == "acid")):
			poisoned[0] = true)
	t.check(poisoned[0], "the sting went in and the venom eats into him")
	s[0].queue_free()

func test_the_python_coils_and_crushes() -> void:
	seed(6)
	var s = _setup("python", 2.4)
	var coiled := [false]
	var hp0: float = s[1].torso.hp
	var lost0: int = s[1].torso.fx.size() - s[1].torso.alive_count
	var hits := [0.0]
	s[0].combat.hit.connect(func(h): if h.attacker == s[2] and h.char == s[1] and h.type == "blunt": hits[0] = maxf(hits[0], h.J))
	await _run(s[0], s[1], s[2], 12.0, func(_i):
		if s[2].hug != null and s[2].hug.get("coil", false):
			coiled[0] = true)
	t.check(coiled[0], "the python threw its coils round him")
	t.check(hits[0] > 8.0, "and the squeeze crushed (strongest squeeze J %.0f)" % hits[0])
	s[0].queue_free()

func test_the_bear_rakes_with_its_claws_and_rears() -> void:
	seed(7)
	var s = _setup("bear", 2.6)
	var cuts := [0]
	var reared := [false]
	s[0].combat.hit.connect(func(h): if h.attacker == s[2] and h.char == s[1] and h.type == "edge": cuts[0] += 1)
	await _run(s[0], s[1], s[2], 12.0, func(_i):
		if float(s[2].ai.get("rear", 0.0)) > 0.0:
			var up: Vector3 = PD.quat_of(s[2].torso) * Vector3(0, 0, 1)
			if up.y > 0.45:
				reared[0] = true)
	t.check(cuts[0] > 0, "the claws cut (%d)" % cuts[0])
	t.check(reared[0], "it rose up on its hind legs")
	s[0].queue_free()

func test_the_mammoth_hunts() -> void:
	seed(8)
	var s = _setup("mammoth", 12.0)
	var closest := [INF]
	await _run(s[0], s[1], s[2], 10.0, func(_i):
		closest[0] = minf(closest[0], s[2].torso.global_position.distance_to(s[1].torso.global_position)))
	t.check(closest[0] < 5.0 * s[2].S * 0.5 + 2.0, "it came for him (closest %.1f m)" % closest[0])
	s[0].queue_free()
