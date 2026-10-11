extends Node
## The Emperor's decrees, traps, the crowd, the announcer and the drops (decrees.js, hazards.js,
## crowd.js, announcer.js, drops.js).

var t

func _match(opts := {}) -> Match:
	var m := Match.new()
	add_child(m)
	var o := {"mode": "duel", "headless": true, "seed": 9, "decrees": [], "hazards": []}
	o.merge(opts, true)
	m.setup(o)
	return m

func _steps(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func test_decrees_combine_and_roll() -> void:
	var d := Decrees.combine([Decrees.by_id("moon"), Decrees.by_id("turbo"), Decrees.by_id("glass"), Decrees.by_id("drunk")])
	t.eq(d.gravity, 3.2, "moon gravity")
	t.check(absf(d.timeScale - 1.45) < 0.001, "fast forward")
	t.eq(d.chip, 3.0, "glass weapons")
	t.eq(d.mods.drunk, 0.45, "free wine")
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	for i in 30:
		var r := Decrees.roll(1.0, 3, rng)
		t.check(r.size() == 3 and r.filter(func(x): return x.has("loadout")).size() <= 1, "three decrees, at most one on the weapons")
		if r.size() != 3:
			break

func test_fists_and_giant_weapons_and_moon_gravity() -> void:
	var m := _match({"decrees": ["fists", "moon"]})
	var space := m.get_world_3d().space
	t.check(absf(PhysicsServer3D.area_get_param(space, PhysicsServer3D.AREA_PARAM_GRAVITY) - 3.2) < 0.001, "the arena's gravity")
	for e in m.entities:
		t.check(e.f.weapons.R == null and e.f.weapons.L == null, "%s has only fists" % e.f.display_name)
		t.eq(e.f.gravity, 3.2, "%s stands under moon gravity" % e.f.display_name)
	m.queue_free()
	await get_tree().process_frame
	t.check(absf(PhysicsServer3D.area_get_param(get_viewport().world_3d.space, PhysicsServer3D.AREA_PARAM_GRAVITY) - 9.81) < 0.001, "gravity back after the fight")
	var m2 := _match({"decrees": ["chickens", "giant"]})
	for e in m2.entities:
		t.eq(e.f.weapons.R.design.get("name"), Data.preset("chicken").name, "%s fights with a chicken" % e.f.display_name)
	t.check(m2.me.f.weapons.R.vs > Data.weapon_voxel * 1.5, "and it is a giant chicken")
	m2.queue_free()

func test_a_spike_trap_comes_up_under_a_man() -> void:
	var m := _match({"hazards": [{"type": "spikes", "x": 0.0, "z": 0.0, "phase": 0.0}]})
	for e in m.entities:
		if e != m.me:
			e.f.state = "dead"
	# Stand on the plate and wait for it.
	var me = m.me
	me.erase("bot")
	me.drive = func(_e): return {"main": {"x": 0.1, "y": 0.1}}
	var shift: Vector3 = Vector3(0, 0, 0) - me.f.torso.global_position
	shift.y = 0.0
	for p in me.f.parts:
		p.global_position += shift
	for side in me.f.weapons:
		if me.f.weapons[side]:
			me.f.weapons[side].global_position += shift
	var hurt := []
	m.combat.hit.connect(func(h): if h.char == me.f and h.weapon and h.weapon.is_hazard: hurt.append(h))
	await _steps(120 * 7)
	t.check(not hurt.is_empty(), "the spikes came up through his feet (%d hits)" % hurt.size())
	m.queue_free()

func test_the_crowd_and_the_announcer_follow_the_blows() -> void:
	var m := _match()
	var lines := []
	m.feed.connect(func(s): lines.append(s))
	var a = m.me.f
	var v = m.entities[1].f
	var f0: float = m.spectacle.get_favor(a)
	m.spectacle.on_hit({"attacker": a, "char": v, "J": 40.0, "res": {"severed": [v.arm.R.fore]}, "killed": false})
	t.check(m.spectacle.get_favor(a) > f0 + 20.0, "the crowd loves a severed arm (%.0f)" % m.spectacle.get_favor(a))
	t.check(lines.any(func(s): return s.contains("FIRST BLOOD") or s.contains("first")), "first blood called (%s)" % str(lines))
	t.check(lines.any(func(s): return s.contains("forearm") or s.contains("loses") or s.contains("relieves") or s.contains("There goes")), "the limb called")
	v.last_attacker = a
	m.spectacle.on_death(v)
	t.check(lines.any(func(s): return s.contains(v.display_name) and (s.contains("kill") or s.contains("finishes") or s.contains("Farewell") or s.contains("down for good"))), "the kill called")
	t.eq(m.spectacle.verdict(a).thumb, "side" if m.spectacle.get_favor(a) < 55.0 else "up", "the Emperor's thumb follows the favour")
	m.queue_free()

func test_the_crowd_throws_down_a_weapon_and_guests_hear_of_it() -> void:
	seed(4)
	var m := _match()
	m.role = "host"
	var before: int = m.combat.loose_weapons.size()
	m.spectacle.arena_drop()
	t.eq(m.combat.loose_weapons.size(), before + 1, "a weapon lies loose on the sand")
	m._sync_loose()
	var w: Weapon = m.combat.loose_weapons[-1]
	t.check(w.net_id >= 0 and m.loose_ids.has(w.net_id), "and has a number for the guests")
	m.role = "local"
	m.queue_free()

func test_lions_den_lets_a_lion_in() -> void:
	var m := _match({"decrees": ["lions"]})
	await _steps(120 * 6)
	t.check(m.entities.any(func(e): return e.kind == "beast" and e.spec.get("beast") == "lion"), "a lion came in")
	m.queue_free()
