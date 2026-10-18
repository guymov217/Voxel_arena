extends Node
## Pots, arrows, zones and the hotbar (throwables.js, items.js, weaponFx.js).

var t

func _match() -> Match:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none"}, "headless": true, "seed": 5})
	m.me.f.state = "dead"
	return m

func _man(m: Match, pos: Vector3, yaw: float, lo: Dictionary, name_: String, team: int, drive: Callable) -> Dictionary:
	var e = m.spawn_fighter({"kind": "bot", "name": name_, "loadout": lo, "team": team, "pos": pos, "yaw": yaw})
	e.erase("bot")
	e.drive = drive
	return e

func _idle(_e) -> Dictionary:
	return {"main": {"x": 0.1, "y": 0.1}}

func _steps(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func test_a_thunder_pot_knocks_a_man_down() -> void:
	seed(2)
	var m := _match()
	var a := _man(m, Vector3(0, 0, -4), 0.0, {}, "Thrower", 0, _idle)
	var b := _man(m, Vector3(0, 0, 0), PI, {}, "Target", 1, _idle)
	await _steps(120)
	m.items.throw_at("pot_thunder", a.f.hand_world("R") + Vector3(0, 0.3, 0), b.f.torso.global_position, a.f, 12.0)
	var down := false
	for i in 180:
		await get_tree().physics_frame
		if b.f.state != "stand":
			down = true
	t.check(down, "the blast put him down")
	t.check(b.f.concussion > 0.2, "and rang his bell (%.2f)" % b.f.concussion)
	t.check(b.f.last_attacker == a.f, "blamed on the thrower")
	m.queue_free()

func test_an_archer_draws_looses_and_the_arrow_sticks() -> void:
	seed(3)
	var m := _match()
	var phase := [0]
	var a := _man(m, Vector3(0, 0, -5), 0.0, {"main": "bow"}, "Archer", 0, func(_e):
		return {"main": {"x": 0.3, "y": 0.45}, "power": phase[0] == 1, "look": {"yaw": 0.0, "pitch": 0.0}})
	var b := _man(m, Vector3(0, 0, 0), PI, {}, "Target", 1, _idle)
	var hits := []
	m.combat.hit.connect(func(h): if h.char == b.f: hits.append(h))
	await _steps(90)
	# Aim straight at him: the look the archer looses along.
	var d: Vector3 = b.f.torso.global_position - a.f.weapons.R.global_position
	a.drive = func(_e): return {"main": {"x": 0.3, "y": 0.45}, "power": phase[0] == 1, "look": {"yaw": atan2(d.x, d.z), "pitch": atan2(d.y - 0.15, Vector2(d.x, d.z).length()) - 0.04}}
	phase[0] = 1
	await _steps(150)
	phase[0] = 2
	await _steps(4)
	t.check(m.items.list.any(func(it): return it.type == "pot_arrow"), "an arrow is in the air")
	await _steps(60)
	t.check(not hits.is_empty() and hits.any(func(h): return h.type == "point"), "it went in (%d hits)" % hits.size())
	var bleed := 0.0
	for p in b.f.parts:
		bleed += p.bleed
	t.check(bleed > 0.5, "and he bleeds (%.1f)" % bleed)
	m.queue_free()

func test_greek_fire_sets_a_man_alight_and_burns_him() -> void:
	seed(4)
	var m := _match()
	var b := _man(m, Vector3(0, 0, 0), PI, {}, "Target", 1, _idle)
	await _steps(60)
	var p: Vector3 = b.f.torso.global_position + Vector3(0, 0, 0.2)
	m.throwables.explode("pot_fire", p, null, Vector3(0, 0, -1), b.f, b.f.torso)
	await _steps(5)
	t.check(Fire.is_burning(b.f), "he is on fire")
	var hp0: float = b.f.torso.hp
	var alive0: int = b.f.torso.alive_count
	await _steps(120 * 4)
	t.check(b.f.torso.hp < hp0, "it hurts (%.0f -> %.0f)" % [hp0, b.f.torso.hp])
	t.check(b.f.torso.alive_count < alive0, "and burns the flesh away (%d -> %d voxels)" % [alive0, b.f.torso.alive_count])
	m.queue_free()

func test_olive_oil_makes_a_runner_slip() -> void:
	seed(5)
	var m := _match()
	var b := _man(m, Vector3(0, 0, -3), 0.0, {}, "Runner", 1, func(_e): return {"main": {"x": 0.1, "y": 0.1}, "mz": 1.0, "sprint": true, "look": {"yaw": 0.0, "pitch": 0.0}})
	m.throwables.add_zone("oil", Vector3(0, 0, 0), 2.6, 14.0)
	var slipped := false
	for i in 300:
		await get_tree().physics_frame
		if b.f.state != "stand":
			slipped = true
			break
	t.check(slipped, "he ran into the oil and went down")
	m.queue_free()

func test_the_hotbar_eats_bread_and_bots_throw_pots() -> void:
	seed(6)
	var m := _match()
	var a := _man(m, Vector3(0, 0, -4), 0.0, {}, "Kit", 0, _idle)
	var b := _man(m, Vector3(0, 0, 0), PI, {}, "Target", 1, _idle)
	a.inventory = {"bread": 1, "sandPot": 1}
	a.f.blood = 40.0
	t.eq(Throwables.hotbar_of(a.inventory), ["sandPot", "bread"], "the hotbar in shop order")
	t.check(m.throwables.use_item(a, 1), "bread used")
	t.check(a.f.blood > 70.0, "blood back (%.0f)" % a.f.blood)
	t.eq(Throwables.hotbar_of(a.inventory), ["sandPot"], "the bread is gone")
	m.throwables.use_item(a, 0)
	t.check(m.items.list.any(func(it): return it.type == "pot_sand"), "a bot throws the pot at once")
	await _steps(150)
	t.check(m.throwables.zones.any(func(z): return z.type == "sand"), "and it made a sand cloud")
	# A player readies it in hand instead, and F throws it.
	a.kind = "local"
	a.inventory = {"thunderPot": 1}
	m.throwables.use_item(a, 0)
	t.check(a.f.held_item != null, "a player holds the pot first")
	m.throwables.throw_held(a, {"look": {"yaw": 0.0, "pitch": 0.0}, "throwPower": 0.8})
	t.check(a.f.held_item == null and m.items.list.any(func(it): return it.type == "pot_thunder"), "and throws it")
	m.queue_free()

func test_a_crossbow_shoots_a_bolt_on_a_thrust() -> void:
	seed(7)
	var m := _match()
	var a := _man(m, Vector3(0, 0, -4), 0.0, {"main": "crossbow"}, "Shooter", 0, func(_e): return {"main": {"x": 0.0, "y": 0.2}, "thrust": 1.0})
	var b := _man(m, Vector3(0, 0, 0), PI, {}, "Target", 1, _idle)
	await _steps(60)
	t.check(m.items.list.any(func(it): return it.type == "pot_bolt") or a.f.weapons.R.get_meta("reload", 0.0) > 0.0, "a bolt went off")
	m.queue_free()

## The physician's supplies do what the stall says: a bandage stops every bleed (and beside a
## fallen friend it is his, and he is up twice as fast), bread brings blood back, wine gives
## the breath back and makes him a little drunk for a while, and no more than that.
func test_the_physicians_supplies_do_what_they_say() -> void:
	var m := _match()
	var a := _man(m, Vector3(0, 0, -4), 0.0, {}, "Medic", 0, _idle)
	var b := _man(m, Vector3(0.8, 0, -4), 0.0, {}, "Friend", 0, _idle)
	await _steps(20)
	# Bandage on himself.
	a.f.torso.bleed = 2.0
	a.f.arm.R.fore.artery = 1.0
	a.inventory = {"bandage": 2, "bread": 1, "wine": 1}
	m.throwables.use_item(a, Throwables.hotbar_of(a.inventory).find("bandage"))
	t.check(a.f.torso.bleed == 0.0 and a.f.arm.R.fore.artery == 0.0, "the bandage stops his bleeding")
	# Bandage beside a fallen friend.
	b.f.fall(6.0, true)
	b.f.torso.bleed = 2.0
	await _steps(5)
	var t0: float = b.f.down_timer
	m.throwables.use_item(a, Throwables.hotbar_of(a.inventory).find("bandage"))
	t.check(b.f.torso.bleed == 0.0, "the friend's bleeding is stopped")
	t.check(b.f.down_timer <= 0.5 and b.f.help_t > 0.0, "and he is helped up (down %.1f s → %.1f s)" % [t0, b.f.down_timer])
	await _steps(120 * 2)
	t.eq(String(b.f.state), "stand", "two seconds later he stands")
	# Bread.
	a.f.blood = 40.0
	m.throwables.use_item(a, Throwables.hotbar_of(a.inventory).find("bread"))
	t.check(absf(a.f.blood - 80.0) < 1.0, "bread: blood back (%.0f)" % a.f.blood)
	# Wine, under a drunk decree.
	a.f.mods.drunk = 0.5
	a.f.stamina = 10.0
	m.throwables.use_item(a, Throwables.hotbar_of(a.inventory).find("wine"))
	t.check(a.f.stamina >= a.f.breath_cap() - 0.01, "wine: full breath (%.0f)" % a.f.stamina)
	t.check(float(a.f.mods.drunk) >= 0.3, "and drunk")
	a.f.wine_timer = 0.01
	await _steps(3)
	t.check(absf(float(a.f.mods.drunk) - 0.5) < 0.01, "when it wears off he is as drunk as the decree had him (%.2f)" % float(a.f.mods.drunk))
	m.queue_free()

## The bag: nine kinds at most, one heavy thing, three pots, five of something light; an old
## save carrying more is cut down to that.
func test_the_bag_holds_nine_kinds_and_sensible_stacks() -> void:
	t.eq(Throwables.stack_max("anvil"), 1, "one anvil")
	t.eq(Throwables.stack_max("nailPot"), 3, "three nail pots")
	t.eq(Throwables.stack_max("bread"), 5, "five loaves")
	var inv := {"nailPot": 3}
	t.check(not Throwables.bag_has_room(inv, "nailPot"), "no fourth nail pot")
	t.check(Throwables.bag_has_room(inv, "bread"), "room for bread beside them")
	var nine := {}
	for id in (Data.shop.throwables.keys() as Array).slice(0, 9):
		nine[id] = 1
	var tenth: String = Data.shop.throwables.keys()[9]
	t.check(not Throwables.bag_has_room(nine, tenth), "no tenth kind")
	var old := Net.sanitize_kit({"nailPot": 9, "anvil": 4, "bread": 9})
	t.eq([int(old.nailPot), int(old.anvil), int(old.bread)], [3, 1, 5], "an old bag cut down to what it may hold")
