extends Node
## The pots as the web game defined them: a thunder pot is a real blast; a nail pot sprays nails
## that stick in whoever is near and wound him; a caltrop pot scatters caltrops that go into the
## foot that steps on one, and he bleeds and limps.

var t

func _match() -> Match:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none"}, "headless": true, "seed": 3})
	return m

func _steps(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func _victim(m: Match, pos: Vector3, drive: Callable) -> Fighter:
	var e = m.spawn_fighter({"kind": "bot", "name": "V", "loadout": {}, "team": 1, "pos": pos, "yaw": PI})
	e.erase("bot")
	e.drive = drive
	return e.f

func _lost(f: Fighter) -> int:
	return f.parts.reduce(func(a, p): return a + p.fx.size() - p.alive_count, 0)

func test_a_thunder_pot_is_a_real_blast() -> void:
	var m := _match()
	m.me.f.teleport(Vector3(0, 0, -12))
	var v := _victim(m, Vector3(0, 0, 0), func(_e): return {})
	await _steps(30)
	var hp0 := v.total_hp()
	m.throwables.explode("pot_thunder", v.torso.global_position + Vector3(0.6, -0.6, 0.0), m.me.f)
	await _steps(20)
	t.check(v.state != "stand", "he is blown off his feet")
	t.check(hp0 - v.total_hp() > 60.0 and _lost(v) > 20, "and really hurt (%.0f hp, %d voxels)" % [hp0 - v.total_hp(), _lost(v)])
	m.queue_free()

func test_nails_fly_all_round_and_stick() -> void:
	seed(5)
	var m := _match()
	m.me.f.teleport(Vector3(0, 0, -12))
	var v := _victim(m, Vector3(0, 0, 1.0), func(_e): return {})
	var by := _victim(m, Vector3(1.5, 0, 0.0), func(_e): return {})
	await _steps(30)
	var hp0 := v.total_hp()
	m.throwables.explode("pot_nail", Vector3(0, 1.0, 0), m.me.f)
	await _steps(40)
	var nails := func(f: Fighter) -> int: return f.parts.reduce(func(a, p): return a + p.stuck.filter(func(n): return is_instance_valid(n)).size(), 0)
	var bleed: float = v.parts.reduce(func(a, p): return a + p.bleed, 0.0)
	t.check(nails.call(v) >= 8, "a hail of nails stays stuck in the man by the pot (%d)" % nails.call(v))
	t.check(nails.call(by) >= 2, "and in the one standing further off in their way (%d)" % nails.call(by))
	t.check(bleed > 0.5, "the nails went into him and he bleeds (%.1f)" % bleed)
	t.check(v.alive and hp0 - v.total_hp() < hp0 * 0.6, "a nail pot wounds, it does not shred (%.0f of %.0f hp)" % [hp0 - v.total_hp(), hp0])
	await _steps(240)
	t.check(nails.call(v) >= 8, "four seconds on, the nails are still in him (%d)" % nails.call(v))
	m.queue_free()

func test_caltrops_scatter_and_wound_the_foot_that_steps_on_one() -> void:
	seed(7)
	var m := _match()
	m.me.f.teleport(Vector3(0, 0, -12))
	m.throwables.explode("pot_caltrops", Vector3(0, 0.3, 2.0), m.me.f)
	await _steps(120)
	var cal: Array = m.items.list.filter(func(it): return it.type == "caltrop")
	t.check(cal.size() >= 8, "caltrops lie all over the sand (%d)" % cal.size())
	var v := _victim(m, Vector3(0, 0, -1.0), func(_e): return {"mz": -1.0})
	var hits := []
	m.combat.hit.connect(func(h): if h.char == v: hits.append(h))
	await _steps(600)
	t.check(not hits.is_empty() and hits.any(func(h): return String(h.part.part_name).begins_with("shin")), "walking over them, a spike goes into his foot (%d)" % hits.size())
	t.check(v.slow_timer > 0.0 or v.parts.any(func(p): return p.bleed > 0.0), "he bleeds and limps")
	m.queue_free()

## An anvil is no pot: thrown, it strikes the man it meets with its weight, drops off him and
## lies on the sand where it fell, whole.
func test_an_anvil_strikes_hard_and_lies_where_it_falls() -> void:
	var m := _match()
	m.me.f.teleport(Vector3(0, 0, -12))
	var v := _victim(m, Vector3(0, 0, 2.0), func(_e): return {})
	await _steps(30)
	var hp0 := v.total_hp()
	var it: Dictionary = m.items.throw_flat("pot_anvil", Vector3(0, 1.3, 0.3), v.torso.global_position, m.me.f, 8.0)
	await _steps(150)
	t.check(hp0 - v.total_hp() > 15.0, "it hurts him badly (%.0f hp)" % (hp0 - v.total_hp()))
	t.check(_lost(v) >= 8, "and crushes the flesh it lands on (%d voxels)" % _lost(v))
	t.check(m.items.list.has(it), "the anvil is still there, not shattered")
	t.check(it.grounded and float(it.p.y) < 0.3 and Vector2(it.p.x, it.p.z).distance_to(Vector2(0, 2.0)) < 1.5, "it dropped at his feet (%s)" % str(it.p))
	m.queue_free()

## The Hand of Jupiter: a charge from the market seizes the man in the crosshair for three
## seconds (no giants); he hangs off his feet where his captor looks, and F hurls him that way;
## his landing hurts him by how hard he came down.
func test_the_hand_of_jupiter_holds_and_hurls_a_man() -> void:
	var m := _match()
	m.me.inventory = {"telekinesis": 2}
	m.me.f.teleport(Vector3(0, 0, -4))
	var v := _victim(m, Vector3(0, 0, 0), func(_e): return {})
	var g := _victim(m, Vector3(6, 0, 0), func(_e): return {})
	g.mods.bodyScale = 2.0
	g.S = 2.0
	await _steps(20)
	var me: Dictionary = m.me
	var phase := {"n": 0, "throw": false}
	me.drive = func(_e):
		phase.n += 1
		var out := {"look": {"yaw": 0.0, "pitch": 0.0}, "aimFrom": Vector3(0, 1.4, -4), "aimAt": v.torso.global_position}
		if phase.n == 1:
			out["useItem"] = 0
		if phase.get("wheel", 0.0) != 0.0:
			out["wheel"] = phase.wheel
			phase.wheel = 0.0
		if phase.throw:
			out["throw"] = true
			phase.throw = false
		return out
	await _steps(3)
	t.eq(m.social.minds.size(), 1, "seized")
	t.eq(int(me.inventory.telekinesis), 1, "one charge spent")
	await _steps(90)
	t.check(v.torso.global_position.y > 1.3 and v.state != "stand", "he hangs off his feet (%.2f m up, %s)" % [v.torso.global_position.y, v.state])
	t.check(v.torso.global_position.z < -0.5, "drawn to where his captor looks (z %.2f)" % v.torso.global_position.z)
	var z_near := v.torso.global_position.z
	phase["wheel"] = 2.0
	await _steps(120)
	t.check(v.torso.global_position.z > z_near + 0.5, "the wheel pushes him off (z %.2f → %.2f)" % [z_near, v.torso.global_position.z])
	var blood_before := v.blood
	phase.throw = true
	await _steps(4)
	t.check(m.social.minds.size() == 1 and m.social.minds[0].flung, "F hurls him")
	t.check(v.torso.linear_velocity.z > 6.0, "the way his captor looks (vz %.1f)" % v.torso.linear_velocity.z)
	await _steps(160)
	t.check(m.social.minds.is_empty(), "the grip is done with him")
	t.check(v.blood < blood_before or v.last_attacker == m.me.f, "his landing hurt him (blood %.0f → %.0f)" % [blood_before, v.blood])
	# A giant is beyond the grip: the charge is not spent.
	m.me.f.teleport(Vector3(6, 0, -4))
	phase.n = 0
	me.drive = func(_e):
		phase.n += 1
		var out := {"look": {"yaw": 0.0, "pitch": 0.0}, "aimFrom": Vector3(6, 1.4, -4), "aimAt": g.torso.global_position}
		if phase.n == 1:
			out["useItem"] = 0
		return out
	v.die("test")
	await _steps(3)
	t.check(m.social.minds.is_empty() and int(me.inventory.telekinesis) == 1, "a giant is beyond the grip, and the charge is kept")
	t.check(float(me.get("mind_cool", -1.0)) > m.time, "but the grip needs a moment before the next try")
	var packed := PlayerInput.pack({"aimAt": Vector3(1, 2, 3), "aimFrom": Vector3(0, 1, 0), "wheel": -2.0, "look": {"yaw": 0.0, "pitch": 0.0}})
	t.eq(float(PlayerInput.unpack(packed).get("wheel", 0.0)), -2.0, "a guest's wheel travels with his crosshair")
	m.queue_free()

## A fireball: Vulcan's fire in a clay sphere, a blast with flames in it and fire on the sand.
func test_a_fireball_blasts_and_burns() -> void:
	var m := _match()
	m.me.f.teleport(Vector3(0, 0, -12))
	var v := _victim(m, Vector3(0, 0, 0), func(_e): return {})
	await _steps(20)
	var wet_before: int = m.throwables.wet.size()
	m.throwables.explode("pot_fireball", v.torso.global_position + Vector3(0, -0.2, -0.4), m.me.f, Vector3.BACK)
	await _steps(5)
	t.check(v.last_attacker == m.me.f and v.torso.linear_velocity.length() > 0.5 or v.state != "stand", "the blast throws him (%s)" % v.state)
	t.check(m.throwables.wet.size() > wet_before, "fire on the sand")
	t.check(Throwables.POTS.has("fireball") and Data.shop.throwables.has("fireball") and Data.shop.throwables.has("telekinesis"), "both are on the market")
	m.queue_free()
