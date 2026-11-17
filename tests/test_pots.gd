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
	# (Burst against his flank, as a pot thrown at him bursts: the bite it takes is where it touches.)
	var tp: VoxelPart = v.torso
	m.throwables.explode("pot_thunder", tp.global_position + tp.global_basis.x.normalized() * (tp.half_ext.x + 0.05), m.me.f)
	await _steps(20)
	t.check(v.state != "stand", "he is blown off his feet")
	t.check(hp0 - v.total_hp() > 60.0 and _lost(v) > 20, "and really hurt (%.0f hp, %d voxels)" % [hp0 - v.total_hp(), _lost(v)])
	m.queue_free()

## A pot goes off d metres from a bare man on the sand; what it does to him.
func _blown(bomb: bool, d: float) -> Dictionary:
	var m := _match()
	m.me.f.teleport(Vector3(0, 0, -14))
	var v := _victim(m, Vector3(0, 0, 0), func(_e): return {})
	await _steps(40)
	var hp0 := v.total_hp()
	m.throwables.explode("pot_thunder", Vector3(d, 0.2, 0), m.me.f, null, null, null, 1.0, bomb)
	var down := false
	for i in 120:
		await get_tree().physics_frame
		down = down or v.state != "stand"
	var out := {"hp": hp0 - v.total_hp(), "of": hp0, "down": down}
	m.queue_free()
	return out

## A thunder pot's blast is about two fifths weaker than it was (user: too strong): a man a metre
## off loses about a fifth of his strength where he lost nearly a third (312 of 1000 hp), it
## carries no farther than 2.6 m where it hurt at 3.3, and puts a man down only inside 1.8 m. The
## Hot Potato's bomb goes off as the pot did.
func test_a_thunder_pot_is_weaker_than_it_was_and_reaches_less_far() -> void:
	var near: Dictionary = await _blown(false, 0.9)
	var bomb: Dictionary = await _blown(true, 0.9)
	var mid: Dictionary = await _blown(false, 2.1)
	var edge: Dictionary = await _blown(false, 2.9)
	t.check(near.down and near.hp > 100.0 and near.hp < near.of * 0.26, "a man a metre off is put down and loses a fifth, not a third (%.0f of %.0f hp)" % [near.hp, near.of])
	t.check(bomb.down and bomb.hp > near.hp * 1.3 and bomb.hp > bomb.of * 0.28, "the Hot Potato's bomb still goes off as the pot did (%.0f against %.0f hp)" % [bomb.hp, near.hp])
	t.check(not mid.down, "two metres off he keeps his feet")
	t.check(edge.hp < 1.0 and not edge.down, "and nearly three metres off nothing reaches him (%.0f hp)" % edge.hp)

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
	t.check(nails.call(v) >= 6, "a hail of nails stays stuck in the man by the pot (%d)" % nails.call(v))
	t.check(nails.call(by) >= 2, "and in the one standing further off in their way (%d)" % nails.call(by))
	t.check(bleed > 1.5, "the nails went into him and he bleeds (%.1f)" % bleed)
	t.check(_lost(v) >= 6, "each nail that went in left its hole (%d voxels)" % _lost(v))
	t.check(hp0 - v.total_hp() > hp0 * 0.035, "and they hurt him (%.0f of %.0f hp)" % [hp0 - v.total_hp(), hp0])
	t.check(v.alive and hp0 - v.total_hp() < hp0 * 0.6, "a nail pot wounds, it does not shred (%.0f of %.0f hp)" % [hp0 - v.total_hp(), hp0])
	await _steps(240)
	t.check(nails.call(v) >= 6, "four seconds on, the nails are still in him (%d)" % nails.call(v))
	m.queue_free()

## Whoever stands in a nail's line takes it (user): the one who threw the pot too, when it bursts
## right by him.
func test_nails_hit_whoever_is_in_their_way_the_thrower_too() -> void:
	seed(9)
	var m := _match()
	var me: Fighter = m.me.f
	await _steps(30)
	var hp0 := me.total_hp()
	m.throwables.explode("pot_nail", me.torso.global_position + Vector3(0, 0.0, 0.9), me)
	await _steps(40)
	var nails: int = me.parts.reduce(func(a, p): return a + p.stuck.filter(func(n): return is_instance_valid(n)).size(), 0)
	t.check(nails >= 3, "nails stick in the thrower in their way too (%d)" % nails)
	t.check(me.total_hp() < hp0, "and they hurt him (%.0f -> %.0f)" % [hp0, me.total_hp()])
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
	# Not to be spammed: two grips a bout, whatever is in the bag, and a rest after each.
	me.mind_cool = -1.0
	me.inventory.telekinesis = 5
	var v2 := _victim(m, Vector3(6, 0, 0), func(_e): return {})
	phase.n = 0
	me.drive = func(_e):
		phase.n += 1
		var out := {"look": {"yaw": 0.0, "pitch": 0.0}, "aimFrom": Vector3(6, 1.4, -4), "aimAt": v2.torso.global_position}
		if phase.n == 1 or phase.n == 40:
			out["useItem"] = 0
		return out
	await _steps(3)
	t.check(m.social.minds.size() == 1 and int(me.mind_uses) == 2, "a second grip")
	t.check(float(me.mind_cool) > m.time + 5.0, "and a rest after it")
	await _steps(40)
	t.eq(int(me.inventory.telekinesis), 4, "a third try in the same bout seizes nobody and spends nothing")
	var packed := PlayerInput.pack({"aimAt": Vector3(1, 2, 3), "aimFrom": Vector3(0, 1, 0), "wheel": -2.0, "look": {"yaw": 0.0, "pitch": 0.0}})
	t.eq(float(PlayerInput.unpack(packed).get("wheel", 0.0)), -2.0, "a guest's wheel travels with his crosshair")
	m.queue_free()

## The trader's wares (user: the beehive and the fireball gone, the sand pot and the smoke pot one,
## a water skin and a torch added): on the market as they are now, and an old bag's gone kinds
## under their new names.
func test_the_trader_wares_as_they_are_now() -> void:
	var sh: Dictionary = Data.shop.throwables
	for gone in ["beehive", "fireball", "sandPot"]:
		t.check(not sh.has(gone) and not Throwables.POTS.has(gone), "no %s on the market" % gone)
	for now in ["smoke", "torch", "waterSkin", "telekinesis"]:
		t.check(sh.has(now), "%s on the market" % now)
	var menu_s = load("res://scripts/ui/menu.gd")
	t.eq(menu_s.kit_use("waterSkin"), "self", "the water skin is poured over yourself (the physician's supplies)")
	t.eq(menu_s.kit_use("torch"), "throw", "the torch is taken in hand and thrown")
	var old := Net.sanitize_kit({"sandPot": 2, "smoke": 1, "beehive": 1, "fireball": 1})
	t.eq(int(old.get("smoke", 0)), 3, "an old bag's sand pots are smoke pots now")
	t.check(int(old.get("honey", 0)) == 1 and int(old.get("greekFire", 0)) == 1, "its beehive a honey pot, its fireball Greek fire")

## A torch in hand burns what its flame touches (anyone but him), and lowered into spilled oil the
## oil goes up; thrown, it burns where it lands; a water skin poured over a burning man puts him
## out (user: a torch that burns the foe, not only lights oil; a water skin).
func test_a_torch_burns_and_lights_oil_and_water_puts_it_out() -> void:
	var m := _match()
	m.me.f.teleport(Vector3(0, 0, -12))
	var v := _victim(m, Vector3(0, 0, 0), func(_e): return {})
	await _steps(30)
	var me: Dictionary = m.me
	me.inventory = {"torch": 2, "waterSkin": 1}
	var bar := Throwables.hotbar_of(me.inventory)
	m.throwables.use_item(me, bar.find("torch"))
	t.check(me.f.held_item != null and me.f.held_item.type == "torch", "the torch is in hand")
	await _steps(2)
	t.check(not Fire.is_burning(me.f), "it does not burn the man who holds it")
	# The flame put to his arm: he catches.
	var tip := Throwables.torch_tip(me.f)
	v.teleport(tip + Vector3(0, -1.25, 0.25))
	var touched := false
	for i in 60:
		await get_tree().physics_frame
		if Fire.is_burning(v):
			touched = true
			break
		tip = Throwables.torch_tip(me.f)
		var near: VoxelPart = v.arm.R.upper
		v.torso.global_position += tip - near.global_position
	t.check(touched, "what its flame touches catches fire")
	# Lowered into spilled oil: it goes up.
	var oil: Dictionary = m.throwables.add_zone("oil", Vector3(tip.x, 0, tip.z), 2.6, 14.0, null)
	m.throwables.ignite_oil(oil, me.f)
	await _steps(2)
	t.check(not m.throwables.zones.has(oil) or oil.t <= 0.0, "lit, the oil is gone")
	t.check(m.throwables.zones.any(func(z): return z.type == "fire" and Vector2(z.p.x - tip.x, z.p.z - tip.z).length() < 0.1 and z.r > 2.0), "and a fire as wide burns where it lay")
	# Thrown into oil on the sand five metres off: the oil goes up there too.
	var oil2: Dictionary = m.throwables.add_zone("oil", Vector3(6, 0, 6), 2.6, 14.0, null)
	m.throwables.explode("torch", Vector3(6.4, 0.05, 6.2), me.f)
	await _steps(2)
	t.check(oil2.t <= 0.0, "a torch thrown into spilled oil sets it ablaze")
	# Greek fire reaching oil sets it going as well.
	var oil3: Dictionary = m.throwables.add_zone("oil", Vector3(-6, 0, 6), 2.6, 14.0, null)
	m.throwables.add_liquid("fire", Vector3(-6.5, 0, 6.3), 0.4, me.f)
	await _steps(40)
	t.check(oil3.t <= 0.0, "burning oil from a Greek fire pot that runs into it lights it")
	# The water skin: his fire out.
	m.add_spot(me.f, me.f.torso, "fire", 8.0, v, null)
	t.check(Fire.is_burning(me.f), "set alight")
	m.throwables.put_away(me)
	m.throwables.use_item(me, Throwables.hotbar_of(me.inventory).find("waterSkin"))
	t.check(not Fire.is_burning(me.f), "the water skin puts the fire on him out")
	t.eq(int(me.inventory.get("waterSkin", 0)), 0, "and it is used up")
	m.queue_free()

## The torch in the hand is a weapon (user: swing it too, not only throw it, a burning weapon): a
## stick with a burning head in the free hand (the right when both are empty), what it took the place
## of put out of sight and back in the hand when it is put away or thrown; every blow of it, a tap
## too, sets the man alight; thrown (F) it is used up out of the kit.
func test_the_torch_is_a_weapon_in_the_hand_and_every_blow_sets_alight() -> void:
	var m := _match()
	m.me.f.teleport(Vector3(0, 0, -12))
	var v := _victim(m, Vector3(0, 0, 0), func(_e): return {})
	await _steps(30)
	var me: Dictionary = m.me
	var f: Fighter = me.f
	me.inventory = {"torch": 2}
	var sword = f.weapons.R
	var shield = f.weapons.L
	t.check(sword != null and shield != null and shield.is_shield, "he starts with a sword in the right hand and a shield in the left")
	m.throwables.use_item(me, Throwables.hotbar_of(me.inventory).find("torch"))
	var tw = Throwables.torch_weapon(f)
	t.check(tw != null and String(tw.design.get("name", "")) == "Torch" and String(tw.design.get("imbue", "")) == "fire", "the torch is a burning weapon in his hand")
	t.check(f.weapons.L == tw and f.weapons.R == sword and f.stowed.L == shield, "in the left hand, the shield put out of sight and the sword where it was")
	t.check(tw.mass > 0.25 and tw.mass < 1.0, "light as a stick of wood (%.2f kg)" % tw.mass)
	t.check(not Fire.is_burning(f), "it does not burn the man who holds it")
	# A blow of it, a light one: he is alight.
	m._coating({"char": v, "part": v.torso, "attacker": f, "J": 1.0, "weapon": tw, "p": v.torso.global_position})
	t.check(Fire.is_burning(v), "a tap of it sets him alight")
	# A sword's tap of the same weight does nothing (a coated blade burns on a blow, not a touch).
	var v2 := _victim(m, Vector3(3, 0, 0), func(_e): return {})
	m._coating({"char": v2, "part": v2.torso, "attacker": f, "J": 1.0, "weapon": sword, "p": v2.torso.global_position})
	t.check(not Fire.is_burning(v2), "a plain blade's tap does not")
	# Put away: the torch is gone from the hand, the shield is back in it, and the kit still has the torch.
	m.throwables.put_away(me)
	await _steps(10)
	t.check(f.held_item == null and Throwables.torch_weapon(f) == null and f.weapons.L == shield and f.weapons.R == sword, "put away, it is gone from the hand and the shield is back")
	t.eq(int(me.inventory.get("torch", 0)), 2, "nothing of the kit is spent")
	# Both hands empty: the torch goes in the right.
	for sd in ["R", "L"]:
		var lw = f.release(sd)
		if lw != null:
			if Combat.current:
				Combat.current.loose_weapons.erase(lw)
			lw.queue_free()
	await _steps(5)
	m.throwables.use_item(me, Throwables.hotbar_of(me.inventory).find("torch"))
	t.check(f.weapons.R != null and f.weapons.R == Throwables.torch_weapon(f), "with both hands empty it is in the right")
	# Thrown (F): the weapon is gone from the hand, one torch of the kit is used up.
	m.throwables.throw_held(me, {"look": {"yaw": 0.0, "pitch": 0.0}, "throwPower": 0.8})
	await _steps(5)
	t.check(f.held_item == null and f.weapons.R == null, "thrown, it is gone from the hand")
	t.eq(int(me.inventory.get("torch", 0)), 1, "and one torch of the kit is used up")
	# Knocked out of the hand: it is not his to hold any more.
	m.throwables.use_item(me, Throwables.hotbar_of(me.inventory).find("torch"))
	t.check(Throwables.torch_weapon(f) != null, "taken in hand again")
	var out = f.release("R")
	if out != null and Combat.current:
		Combat.current.loose_weapons.erase(out)
	await _steps(5)
	t.check(f.held_item == null, "knocked out of his hand, it is not held any more")
	m.queue_free()

## A torch does not burn for ever (user: it must be able to break at the end, it cannot be used without
## end): it burns down in the hand (and a little more with every blow it lands), the rag of its head
## burning away from the crown down; what is spent stays spent when it is put away and taken out
## again; when it is all burnt one torch of the kit is used up and the weapon it took the hand's
## place from is back.
func test_a_torch_burns_down_and_is_spent() -> void:
	var m := _match()
	m.me.f.teleport(Vector3(0, 0, -12))
	await _steps(30)
	var me: Dictionary = m.me
	var f: Fighter = me.f
	me.inventory = {"torch": 2}
	var shield = f.weapons.L
	m.throwables.use_item(me, Throwables.hotbar_of(me.inventory).find("torch"))
	var tw = Throwables.torch_weapon(f)
	t.check(tw != null, "the torch is in hand")
	t.check(Throwables.torch_gone(tw) == 0.0 and tw.flame_size == 1.0, "whole at first: its head all there")
	# Held, it burns down with time: half of its life, and the head is half gone (crown first).
	me.torch_burn = Throwables.TORCH_LIFE * 0.5
	await _steps(2)
	var half := Throwables.torch_gone(tw)
	t.check(half > 0.3 and half < 0.5, "half burnt, about 40%% of its head is gone (%.2f)" % half)
	var top_alive := false
	for i in tw.vox.size():
		if int(tw.vox[i][1]) == 16 and tw.alive[i] == 1:
			top_alive = true
	t.check(not top_alive, "the crown burnt first")
	t.check(tw.flame_size < 0.8, "and the flame is smaller (%.2f)" % tw.flame_size)
	# Put away and taken out again: it is not whole again.
	m.throwables.put_away(me)
	await _steps(5)
	t.eq(int(me.inventory.get("torch", 0)), 2, "put away, the kit still has both torches")
	m.throwables.use_item(me, Throwables.hotbar_of(me.inventory).find("torch"))
	var tw2 = Throwables.torch_weapon(f)
	t.check(tw2 != null and tw2 != tw and Throwables.torch_gone(tw2) > 0.3, "taken out again, it is as burnt as it was (%.2f)" % Throwables.torch_gone(tw2))
	t.check(me.torch_burn >= Throwables.TORCH_LIFE * 0.5, "its burn is kept")
	# A blow it lands costs it more than the time.
	var before: float = me.torch_burn
	m.throwables.torch_struck(f, 0.2)
	t.eq(me.torch_burn, before, "a graze costs it nothing")
	m.throwables.torch_struck(f, 6.0)
	t.check(me.torch_burn >= before + Throwables.TORCH_BLOW - 0.001, "a blow costs it %.1f s of its life" % Throwables.TORCH_BLOW)
	# Used up: out of the hand, one torch of the kit gone, the shield back.
	me.torch_burn = Throwables.TORCH_LIFE - 0.01
	await _steps(4)
	t.check(f.held_item == null and Throwables.torch_weapon(f) == null, "burnt out, it is gone from his hand")
	t.eq(int(me.inventory.get("torch", 0)), 1, "one torch of the kit is used up")
	await _steps(10)
	t.check(f.weapons.L == shield and f.stowed.L == null, "and the shield is back in the hand")
	t.check(float(me.get("torch_burn", 0.0)) == 0.0, "the next torch is whole")
	m.throwables.use_item(me, Throwables.hotbar_of(me.inventory).find("torch"))
	t.check(Throwables.torch_weapon(f) != null and Throwables.torch_gone(Throwables.torch_weapon(f)) == 0.0, "and it is, taken out")
	# Thrown: the one in the hand goes, and the next is whole too.
	me.torch_burn = Throwables.TORCH_LIFE * 0.3
	m.throwables.throw_held(me, {"look": {"yaw": 0.0, "pitch": 0.0}, "throwPower": 0.8})
	t.check(float(me.get("torch_burn", 0.0)) == 0.0, "thrown, its burn goes with it")
	m.queue_free()

## A torch knocked to pieces (a hard blow on its stick, an arm that swings it into a wall) is spent
## as well, and it breaks into ash and splinters: no broken torch is left lying on the sand to pick up.
func test_a_torch_knocked_to_pieces_is_spent_and_leaves_no_weapon() -> void:
	var m := _match()
	m.me.f.teleport(Vector3(0, 0, -12))
	await _steps(30)
	var me: Dictionary = m.me
	var f: Fighter = me.f
	me.inventory = {"torch": 1}
	m.throwables.use_item(me, Throwables.hotbar_of(me.inventory).find("torch"))
	var tw = Throwables.torch_weapon(f)
	t.check(tw != null, "the torch is in hand")
	var loose_before: int = Combat.current.loose_weapons.size()
	# Its stick snapped through: the head goes with the piece that falls.
	var stick := []
	for i in tw.vox.size():
		if int(tw.vox[i][1]) == 8:
			stick.append(i)
	tw.remove_voxels(stick)
	var made: Array = tw.split_plan()
	t.check(not made.is_empty(), "the snapped stick falls into two pieces")
	for pc in made:
		t.check(tw._piece_weapon(pc).is_empty(), "and a piece of a torch is never a weapon of its own")
		tw.remove_voxels(pc)
	await _steps(4)
	t.check(f.held_item == null and Throwables.torch_weapon(f) == null, "spent: it is gone from his hand")
	t.eq(int(me.inventory.get("torch", 0)), 0, "and its torch is used up")
	t.eq(Combat.current.loose_weapons.size(), loose_before, "nothing of it lies on the sand")
	m.queue_free()

## The bees of a broken hive (a mystery amphora's): the swarm comes out short of the man and goes
## for him, and within a couple of seconds he is covered (a pot that broke on the sand five metres
## off did nothing: user).
func test_a_broken_hive_sends_its_swarm_at_the_nearest_foe() -> void:
	var m := _match()
	m.me.f.teleport(Vector3(0, 0, -12))
	var v := _victim(m, Vector3(0, 0, 0), func(_e): return {})
	await _steps(30)
	m.throwables.explode("pot_bees", Vector3(0, 0.3, 5.0), m.me.f)
	t.check(v.bee_timer <= 0.0, "broken five metres short, the bees are not on him yet")
	t.eq(m.throwables.swarms.size(), 1, "a swarm is in the air")
	await _steps(int(2.5 * 120))
	t.check(v.bee_timer > 0.0, "and within two and a half seconds it has found him (bees for %.1f s)" % v.bee_timer)
	t.eq(m.throwables.swarms.size(), 0, "and the swarm in the air is gone, the bees on him now")
	m.queue_free()


## A thunder pot that goes off against a beast's flank blows the flesh out of that flank, where it
## went off, not out of the middle of each part it reached.
func test_a_thunder_pot_craters_the_spot_it_went_off_at() -> void:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "lion"}, "headless": true, "seed": 3})
	m.me.f.teleport(Vector3(0, 0, -14))
	await _steps(20)
	var lion = null
	for e in m.entities:
		if e.f is Beast:
			lion = e.f
	t.check(lion != null, "a lion to blow up")
	var tp: VoxelPart = lion.torso
	var side: Vector3 = tp.global_basis.x.normalized()
	var p: Vector3 = tp.global_position + side * (tp.half_ext.x + 0.05)
	var was := {}
	for part in lion.parts:
		for i in part.fx.size():
			if part.alive[i]:
				was[[part, i]] = part.world_of(i)
	m.throwables.explode("pot_thunder", p, m.me.f)
	var near := 0
	var lost := 0
	var on_side := 0
	for k in was:
		if not k[0].alive[k[1]]:
			lost += 1
			var w: Vector3 = was[k]
			if w.distance_to(p) < 0.4:
				near += 1
			if (w - tp.global_position).dot(side) > 0.0:
				on_side += 1
	t.check(lost >= 10, "it blows flesh away (%d voxels)" % lost)
	t.check(near >= lost * 0.7 and on_side >= lost * 0.8, "from where it went off (%d of %d within 0.4 m, %d on that flank)" % [near, lost, on_side])
	m.queue_free()

## A goat and the chickens out of their pots: there in the step the pot broke where nothing is
## drawn, as they always were; where the game brings things in over frames (a screen, Match.
## staging: the goat made in one step was a seventh of a second's stop, the six chickens a tenth),
## the goat is built over the frames that follow and the chickens come out one a frame.
func test_a_goat_and_the_chickens_come_out_of_their_pots() -> void:
	var m := _match()
	m.me.f.teleport(Vector3(0, 0, -12))
	await _steps(10)
	var goats := func() -> int:
		return m.entities.filter(func(e): return e.f is Beast and String(e.f.species) == "goat").size()
	m.throwables.explode("pot_goat", Vector3(3, 0.3, 0), m.me.f)
	t.eq(goats.call(), 1, "without a screen the goat is out of its pot at once")
	var w0: int = m.combat.loose_weapons.size()
	m.throwables.explode("pot_chickens", Vector3(-3, 0.3, 0), m.me.f)
	t.eq(m.combat.loose_weapons.size(), w0 + 6, "and the six chickens")
	m.stage_always = true
	m.throwables.explode("pot_goat", Vector3(3, 0.3, 4), m.me.f)
	t.check(goats.call() == 1 and m.coming == 1, "brought in over frames, the next goat is on its way, not there yet")
	var w1: int = m.combat.loose_weapons.size()
	m.throwables.explode("pot_chickens", Vector3(-3, 0.3, 4), m.me.f)
	t.eq(m.combat.loose_weapons.size(), w1 + 1, "and one chicken is out, the rest to come")
	var n := 0
	while (goats.call() < 2 or m.combat.loose_weapons.size() < w1 + 6) and n < 900:
		await get_tree().physics_frame
		n += 1
	t.check(goats.call() == 2 and m.coming == 0, "the goat comes in (%d steps)" % n)
	t.eq(m.combat.loose_weapons.size(), w1 + 6, "and all six chickens")
	var harmless: int = m.entities.filter(func(e): return e.f is Beast and String(e.f.species) == "goat" and bool(e.get("harmless", false))).size()
	t.eq(harmless, 2, "both goats harm nobody")
	m.queue_free()

## A pot's nails are all of one shape and bounce one way: one of each made for every nail of the
## hundred and twenty was a part of the stop the pot made.
func test_a_pots_nails_are_of_one_shape() -> void:
	seed(5)
	var m := _match()
	m.me.f.teleport(Vector3(0, 0, -12))
	await _steps(5)
	m.throwables.explode("pot_nail", Vector3(0, 1.0, 0), m.me.f)
	var shapes := {}
	var bounces := {}
	var n := 0
	for fl in m.throwables.flying_nails:
		var b: RigidBody3D = fl.b
		n += 1
		bounces[b.physics_material_override] = true
		for c in b.get_children():
			if c is CollisionShape3D:
				shapes[c.shape] = true
	t.check(n >= 60, "the nails fly (%d)" % n)
	t.check(shapes.size() == 1 and bounces.size() == 1, "all of one shape and one way of bouncing (%d, %d)" % [shapes.size(), bounces.size()])
	if shapes.size() == 1:
		var bx: BoxShape3D = shapes.keys()[0]
		t.check(bx.size.is_equal_approx(Vector3(0.014, 0.014, 0.09)), "a nail's own")
	m.queue_free()
