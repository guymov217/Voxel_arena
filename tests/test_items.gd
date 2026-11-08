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
	# (A bot's shot scatters like a man's, at a mark of its own choosing: it may take him more than
	# one arrow, as it would a man.)
	var flew := false
	for shot in 3:
		phase[0] = 1
		await _steps(150)
		phase[0] = 2
		await _steps(4)
		flew = flew or m.items.list.any(func(it): return it.type == "pot_arrow")
		await _steps(60)
		if hits.any(func(h): return h.type == "point"):
			break
	t.check(flew, "an arrow is in the air")
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

func test_a_pot_leaves_from_the_hand_that_holds_it() -> void:
	seed(9)
	var m := _match()
	var a := _man(m, Vector3(0, 0, -4), 0.0, {}, "Kit", 0, _idle)
	a.kind = "local"
	await _steps(30)
	var pot_from := func() -> Vector3:
		var it = m.items.list.filter(func(i): return i.type == "pot_thunder").back()
		return it.p
	a.inventory = {"thunderPot": 2}
	m.throwables.use_item(a, 0)
	var side: String = a.f.held_item.side
	var hand: Vector3 = a.f.hand_world(side)
	m.throwables.throw_held(a, {"look": {"yaw": 0.0, "pitch": 0.0}, "throwPower": 0.8})
	t.check(pot_from.call().distance_to(hand) < 0.25, "it leaves the %s hand it was held in (%.2f m off)" % [side, pot_from.call().distance_to(hand)])
	# Readied in the left hand, and the left forearm taken off: it goes from the right one,
	# not from the forearm lying on the sand.
	m.throwables.use_item(a, 0)
	t.eq(a.f.held_item.side, "L", "readied in the free left hand")
	var fore: VoxelPart = a.f.arm.L.fore
	a.f.detach_limb(fore, {"removed": [], "severed": []})
	fore.global_position += Vector3(2.0, 0, 0)
	m.throwables.throw_held(a, {"look": {"yaw": 0.0, "pitch": 0.0}, "throwPower": 0.8})
	var from: Vector3 = pot_from.call()
	t.check(from.distance_to(a.f.hand_world("R")) < 0.25, "the good hand throws it (%.2f m from it, %.2f m from the cut-off one)" % [from.distance_to(a.f.hand_world("R")), from.distance_to(a.f.hand_world("L"))])
	t.eq(a.f.item_hand(), "R", "the next is readied in the right hand")
	m.queue_free()

## Both hands full (a sword and a shield): the pot is not put in a fist round the shield's grip.
## The shield hand puts the shield out of sight (hidden, touching nothing, still his), holds the
## pot, throws it from there, and has the very same shield back once the arm has come through;
## the same when the pot is put back in the kit, and for a bot that throws at once. Dying with
## the shield put away, it is dropped on the sand like his other arms (user).
func test_a_full_hand_puts_its_weapon_away_to_throw_and_takes_it_back() -> void:
	seed(4)
	var m := _match()
	var a := _man(m, Vector3(0, 0, -4), 0.0, {"main": "gladius", "off": "roundShield"}, "Kit", 0, _idle)
	a.kind = "local"
	await _steps(40)
	var f: Fighter = a.f
	var shield: Weapon = f.weapons.L
	t.check(shield != null and shield.is_shield, "a shield in the left hand")
	a.inventory = {"thunderPot": 3}
	m.throwables.use_item(a, 0)
	t.eq(f.held_item.side, "L", "the pot goes to the shield hand")
	t.check(f.weapons.L == null and f.stowed.L == shield, "which puts the shield away for it")
	t.check(not shield.visible and shield.collision_layer == 0 and shield.collision_mask == 0, "out of sight, touching nothing")
	t.check(f.weapons.R != null, "the sword stays in the right hand")
	await _steps(20)
	var hand: Vector3 = f.hand_world("L")
	m.throwables.throw_held(a, {"look": {"yaw": 0.0, "pitch": 0.0}, "throwPower": 0.8})
	f.throw_anim = {"side": "L", "phase": "follow", "t": 0.35}
	var it = m.items.list.filter(func(i): return i.type == "pot_thunder").back()
	t.check(it != null and (it.p as Vector3).distance_to(hand) < 0.3, "the pot leaves from that hand (%.2f m off)" % ((it.p as Vector3).distance_to(hand) if it else -1.0))
	t.check(f.weapons.L == null, "the shield still away while the arm comes through")
	await _steps(60)
	t.check(f.weapons.L == shield and f.stowed.L == null, "then the same shield is back in the hand")
	t.check(shield.visible and shield.collision_layer != 0 and not shield.freeze, "seen and solid again")
	t.check(shield.grip_world().distance_to(f.hand_world("L")) < 0.15, "held at its grip (%.2f m)" % shield.grip_world().distance_to(f.hand_world("L")))
	# Readied and put back in the kit: the shield comes back too.
	m.throwables.use_item(a, 0)
	t.check(f.stowed.L == shield, "readied again, the shield away")
	m.throwables.use_item(a, 0)
	await _steps(4)
	t.check(f.held_item == null and f.weapons.L == shield, "put back in the kit, the shield in the hand again")
	# A bot throws at once, from the shield hand, and has its shield back after (at a man far off:
	# its pot is not to land on the one being tested).
	_man(m, Vector3(3, 0, 16), PI, {}, "Mark", 1, _idle)
	var b := _man(m, Vector3(3, 0, -4), 0.0, {"main": "gladius", "off": "roundShield"}, "Bot", 0, _idle)
	await _steps(40)
	var bs: Weapon = b.f.weapons.L
	b.inventory = {"thunderPot": 1}
	m.throwables.use_item(b, 0)
	t.check(b.f.weapons.L == null and b.f.stowed.L == bs, "a bot's shield goes out of sight for the throw")
	await _steps(70)
	t.check(b.f.weapons.L == bs and bs.visible, "and is back in its hand after")
	# Killed with the shield put away: it falls on the sand.
	m.throwables.use_item(a, 0)
	t.check(f.stowed.L == shield, "readied once more")
	f.die("test")
	t.check(f.stowed.L == null and shield.holder == null and shield.visible and m.combat.loose_weapons.has(shield), "dead, the shield is dropped, seen, loose")
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

## Knocked down but awake, a man still throws: the arm comes up off the sand as he winds up,
## and the pot leaves his hand.
func test_a_man_on_the_sand_still_throws() -> void:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none"}, "headless": true, "seed": 3, "loadout": {"main": "gladius", "off": ""}})
	var f: Fighter = m.me.f
	var inp := {"main": {"x": 0.2, "y": 0.2}, "look": {"yaw": 0.0, "pitch": 0.0}}
	m.me.drive = func(_e): return inp.duplicate()
	m.me.inventory = {"greekFire": 2}
	for i in 60:
		await get_tree().physics_frame
	f.fall(4.0, true)
	for i in 40:
		await get_tree().physics_frame
	t.eq(f.state, "down", "he is down")
	inp.useItem = 0
	await get_tree().physics_frame
	inp.erase("useItem")
	await get_tree().physics_frame
	t.check(f.held_item != null, "the pot is readied in his hand")
	inp.charging = 0.6
	var hy := -9.0
	for i in 30:
		await get_tree().physics_frame
		hy = maxf(hy, f.hand_world("L").y - f.torso.global_position.y)
	t.check(hy > 0.4, "the throwing arm comes up off the sand (%.2f m above the chest)" % hy)
	inp.erase("charging")
	inp.throw = true
	await get_tree().physics_frame
	inp.erase("throw")
	for i in 30:
		await get_tree().physics_frame
	t.check(f.held_item == null and int(m.me.inventory.greekFire) == 1, "and the pot is thrown")
	m.queue_free()

## The wind-up sets the throw: a flick tosses a pot a few paces, short of a far mark; held to the
## full it flies hard and reaches it.
func test_the_wind_up_sets_how_hard_a_pot_flies() -> void:
	var far := {}
	for power in [0.3, 1.0]:
		var m := _match()
		var a := _man(m, Vector3(0, 0, -6), 0.0, {}, "Thrower", 0, _idle)
		a.kind = "local"
		a.inventory = {"sandPot": 1}
		await _steps(30)
		m.throwables.use_item(a, 0)
		var from: Vector3 = a.f.torso.global_position
		m.throwables.throw_held(a, {"look": {"yaw": 0.0, "pitch": 0.0}, "throwPower": power, "aimAt": from + Vector3(0, 0, 14.0)})
		var it = null
		for x in m.items.list:
			if x.type == "pot_sand":
				it = x
		t.check(it != null, "thrown (power %.1f)" % power)
		var reach := 0.0
		for i in 240:
			await get_tree().physics_frame
			if it == null or not m.items.list.has(it):
				break
			reach = maxf(reach, (it.p as Vector3).z - from.z)
		far[power] = reach
		m.queue_free()
	t.check(float(far[0.3]) < 9.0, "a flick falls well short of a mark 14 m off (%.1f m)" % far[0.3])
	t.check(float(far[1.0]) > 12.5, "a full wind-up reaches it (%.1f m)" % far[1.0])

## A banana peel under a sole floors whoever steps on it, a man or a beast (user: the banana peels
## did nothing; they looked for a man's shins only).
func test_a_banana_peel_floors_a_man_and_a_beast() -> void:
	seed(6)
	var m := _match()
	var man := _man(m, Vector3(-2, 0, 0), 0.0, {}, "Walker", 1, _idle)
	var lion = m.spawn_beast({"beast": "lion", "team": 1, "pos": Vector3(3, 0.1, 0), "yaw": 0.0, "harmless": true})
	await _steps(120)
	for c in [man.f, lion.f]:
		var sole: Vector3 = c.soles()[0][1]
		var it: Dictionary = m.items.spawn("banana", Vector3(sole.x, 0.06, sole.z), Vector3.ZERO, null)
		it.grounded = true
	var man_down := false
	var lion_down := false
	for i in 30:
		await get_tree().physics_frame
		man_down = man_down or man.f.state != "stand"
		lion_down = lion_down or float(lion.f.down_t) > 0.0
	t.check(man_down, "the man stepped on the peel and went down")
	t.check(lion_down, "and the lion went over on its side")
	m.queue_free()

## Olive oil floors anyone who moves in it, a walker as well as a runner; standing still in it a
## man keeps his feet (user: the oil pot did nothing: only a runner went down, and in a fight
## nobody runs).
func test_olive_oil_floors_a_walker_but_not_one_standing_still() -> void:
	seed(7)
	var m := _match()
	var walker := _man(m, Vector3(-1.0, 0, -2.5), 0.0, {}, "Walker", 1, func(_e): return {"main": {"x": 0.1, "y": 0.1}, "mz": 0.5, "look": {"yaw": 0.0, "pitch": 0.0}})
	var still := _man(m, Vector3(1.2, 0, 0.5), 0.0, {}, "Still", 1, _idle)
	m.throwables.add_zone("oil", Vector3(0, 0, 0), 2.6, 14.0)
	var down := false
	var still_down := false
	for i in 600:
		await get_tree().physics_frame
		down = down or walker.f.state != "stand"
		still_down = still_down or still.f.state != "stand"
	t.check(down, "a man walking through the oil went down")
	t.check(not still_down, "one standing still in it kept his feet")
	m.queue_free()

## A caltrop goes into the foot of whatever steps on it: a man's, a lion's, the Cerberus's (user:
## the caltrops did nothing to the Cerberus; make sure they work on everyone), and it limps.
func test_a_caltrop_goes_into_any_foot() -> void:
	seed(8)
	var m := _match()
	var man := _man(m, Vector3(-3, 0, 0), 0.0, {}, "Man", 1, _idle)
	var lion = m.spawn_beast({"beast": "lion", "team": 1, "pos": Vector3(0.5, 0.1, 0), "yaw": 0.0, "harmless": true})
	var dog = m.spawn_beast({"beast": "cerberus", "team": 1, "pos": Vector3(5, 0.1, 0), "yaw": 0.0, "harmless": true})
	await _steps(120)
	var who := [man.f, lion.f, dog.f]
	var feet := []
	for c in who:
		var so: Array = c.soles()
		t.check(so.size() == (2 if c == man.f else 4), "%s stands on %d soles" % [c.display_name, so.size()])
		var part: VoxelPart = so[0][0]
		feet.append([part, part.hp, part.bleed])
		var it: Dictionary = m.items.spawn("caltrop", Vector3((so[0][1] as Vector3).x, 0.03, (so[0][1] as Vector3).z), Vector3.ZERO, null)
		it.grounded = true
	await _steps(20)
	for k in who.size():
		var c = who[k]
		var p: VoxelPart = feet[k][0]
		t.check(p.hp < float(feet[k][1]) or p.bleed > float(feet[k][2]), "%s: the spike went into the foot" % c.display_name)
		t.check(c.slow_timer > 0.0, "%s limps" % c.display_name)
	m.queue_free()

## A thunder pot going off beside a man in armour blows plates off the side of him turned to it,
## and wears the rest; a fire pot's blast does it on a smaller scale (user: the pots did no harm to
## armour at all, the thunder pot least of all).
func test_a_blast_blows_plates_off_armour() -> void:
	seed(9)
	var m := _match()
	var b := _man(m, Vector3(0, 0, 0), PI, {"armor": ["helmet", "lorica", "manica", "greaves"]}, "Armoured", 1, _idle)
	var c := _man(m, Vector3(6, 0, 0), PI, {"armor": ["helmet", "lorica", "manica", "greaves"]}, "Also armoured", 1, _idle)
	await _steps(120)
	var plates := func(f: Fighter) -> int:
		var n := 0
		for p in f.parts:
			for ad in p.get_meta("armor", []):
				n += int(ad.alive)
		return n
	var b0: int = plates.call(b.f)
	var c0: int = plates.call(c.f)
	# (In front of him, at his knees: the pot burst at his feet.)
	m.throwables.explode("pot_thunder", b.f.torso.global_position + Vector3(0, -0.7, -0.6), null)
	m.throwables.explode("pot_fireball", c.f.torso.global_position + Vector3(0, -0.3, -0.5), null)
	await _steps(10)
	var b1: int = plates.call(b.f)
	var c1: int = plates.call(c.f)
	t.check(b0 - b1 >= 12, "the thunder pot blew %d plates off him (of %d)" % [b0 - b1, b0])
	t.check(b1 > b0 / 3, "not every last one: the side away from it held (%d left)" % b1)
	t.check(c0 - c1 >= 2, "the fireball pot's blast took %d off the other" % (c0 - c1))
	m.queue_free()

## A honey pot broken on a man brings a swarm down on him, the thrower's: they sting him (his blood
## goes down), a blade swung fast through one kills it, a man they cover swats at them and kills
## some, and they leave him when he is dead (user: the honey pot did nothing; it must bring bees
## that attack the man it hit, that he can kill and that can kill him).
func test_a_honey_pot_brings_bees_that_sting_and_can_be_killed() -> void:
	seed(10)
	var m := _match()
	var a := _man(m, Vector3(0, 0, -3), 0.0, {"main": "gladius", "off": ""}, "Thrower", 0, _idle)
	var b := _man(m, Vector3(0, 0, 0), PI, {"main": "gladius", "off": ""}, "Target", 1, _idle)
	await _steps(60)
	m.throwables.explode("pot_honey", b.f.torso.global_position, a.f, Vector3(0, 0, 1), b.f, b.f.torso)
	t.eq(m.throwables.hives.size(), 1, "a swarm on the man it broke on")
	t.eq(m.throwables.hives[0].bees.size(), Throwables.BEES, "of %d bees" % Throwables.BEES)
	t.check(m.throwables.hives[0].target == b.f, "on him, not on the thrower")
	var blood0: float = b.f.blood
	await _steps(600)
	t.check(b.f.blood < blood0 - 3.0, "they stung him: his blood %.1f, was %.1f" % [b.f.blood, blood0])
	t.check(b.f.last_attacker == a.f, "the thrower's bees")
	# The rule: a blade going fast through a bee kills it; still, it does not.
	var w: Weapon = a.f.weapons.R
	var mid: Vector3 = w.global_transform * w.local_box().get_center()
	w.linear_velocity = Vector3.ZERO
	w.angular_velocity = Vector3.ZERO
	t.check(not m.throwables._swatted(mid), "a blade held still kills nothing")
	w.linear_velocity = Vector3(6, 0, 0)
	t.check(m.throwables._swatted(mid), "swung through a bee, it kills it")
	w.linear_velocity = Vector3.ZERO
	# A bot they cover swats about his head at them, and kills some.
	var c = m.spawn_fighter({"kind": "bot", "name": "Swatter", "loadout": {"main": "gladius", "off": ""}, "team": 1, "pos": Vector3(4, 0.1, 0), "yaw": PI})
	await _steps(30)
	m.throwables.bees_on(c.f, a.f, c.f.head.global_position + Vector3(0, 0.3, 0))
	var hv: Dictionary = m.throwables.hives.back()
	await _steps(1200)
	var left: int = hv.bees.filter(func(x): return x.on).size()
	t.check(left < Throwables.BEES, "he swatted %d of them out of the air" % (Throwables.BEES - left))
	# Dead, they leave him.
	b.f.die("test")
	await _steps(600)
	t.check(not m.throwables.hives.any(func(h): return h.target == b.f), "he is dead: his bees have left him")
	m.queue_free()
