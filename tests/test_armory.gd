extends Node
## The armourer and the coatings: every piece on the rack exists and fits a body, buying one
## takes off what it clashes with (sold back for half), a save cannot wear nonsense; venom, fire
## and frost (no longer sold: gems do it) still do what they say on a weapon coated before.

var t

func _steps(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func test_the_rack_and_what_clashes() -> void:
	for r in Armory.SHOP:
		t.check(Data.armor.has(r[0]) and not Armory.parts_of(r[0]).is_empty(), "%s is a real piece" % r[0])
	var b := Armory.buy(["helmet", "leatherJerkin"], "murmilloHelm")
	t.check(b.worn.has("murmilloHelm") and not b.worn.has("helmet") and b.worn.has("leatherJerkin"), "the murmillo helm replaces the galea, the jerkin stays (%s)" % [b.worn])
	t.eq(int(b.cost), Armory.price("murmilloHelm") - Armory.price("helmet") / 2, "the old helmet is taken in part exchange")
	t.eq(Armory.sanitize(["lorica", "steelLorica", "nonsense", "lorica", "hat_crown"]), ["lorica"], "a save wears each piece once, no clashes, nothing that is not sold")
	t.eq(int(Armory.take_off(["greaves"], "greaves").cost), -Armory.price("greaves") / 2, "taken off, it sells back for half")

func test_coatings_are_no_longer_sold() -> void:
	var a := Arms.empty()
	a.main = Data.preset("gladius").duplicate(true)
	for id in Arms.COATINGS:
		t.check(not Arms.can_upgrade(id, a.main), "%s: fire, frost and venom come from gems now" % id)

func test_a_coated_blow_does_what_it_says() -> void:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none"}, "decrees": [], "hazards": [], "headless": true})
	m.me.f.teleport(Vector3(0, 0, -10))
	var got := {}
	var i := 0
	for kind in ["fire", "venom", "frost"]:
		var d := Data.preset("gladius").duplicate(true)
		d.imbue = kind
		var w := Weapon.new()
		w.setup(d)
		m.add_child(w)
		var e = m.spawn_fighter({"kind": "bot", "name": "V", "loadout": {}, "team": 1, "pos": Vector3(i * 2.0, 0.1, 0), "yaw": 0.0})
		e.erase("bot")
		e.drive = func(_e): return {}
		await _steps(5)
		var v: Fighter = e.f
		var b0: float = v.torso.bleed
		m._on_hit({"kind": "hit", "weapon": w, "char": v, "part": v.torso, "attacker": null, "p": v.torso.global_position, "dir": Vector3(0, 0, 1), "J": 12.0, "type": "edge", "res": {"severed": []}, "killed": false})
		got[kind] = {"burn": Fire.is_burning(v), "slow": v.slow_factor, "bleed": v.torso.bleed - b0, "stamina": v.stamina}
		i += 1
	t.check(got.fire.burn, "a burning blade sets him alight")
	t.check(got.venom.slow < 1.0 and got.venom.bleed > 0.3 and not got.venom.burn, "venom: he slows and bleeds (%s)" % [got.venom])
	t.check(got.frost.slow <= 0.5 and got.frost.stamina < 100.0, "frost: he is slowed hard and loses breath (%s)" % [got.frost])
	m.queue_free()

## Gems set in a forged weapon: a ruby sets the part struck alight, a sapphire freezes that limb
## stiff, an emerald poisons the wound; a weapon packed with the stone does it most blows, more
## stones do it fiercer; and they cost far more than any other voxel.
func test_gems_set_in_a_weapon_burn_freeze_and_poison() -> void:
	t.check(Arms.voxel_price("ruby") >= 3 * Arms.voxel_price("gold"), "a gem costs far more than gold")
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none"}, "decrees": [], "hazards": [], "headless": true})
	m.me.f.teleport(Vector3(0, 0, -10))
	var got := {}
	var i := 0
	for gem in ["ruby", "sapphire", "emerald"]:
		var d := Data.preset("gladius").duplicate(true)
		var n := 0
		for v in d.voxels:
			if v[4] == "blunt" and n < 20:
				v[3] = gem
				n += 1
		var w := Weapon.new()
		w.setup(d)
		m.add_child(w)
		t.eq(int(w.gem_counts().get(gem, 0)), 20, "%s: twenty stones set" % gem)
		var e = m.spawn_fighter({"kind": "bot", "name": "V", "loadout": {}, "team": 1, "pos": Vector3(i * 2.0, 0.1, 0), "yaw": 0.0})
		e.erase("bot")
		e.drive = func(_e): return {}
		await _steps(5)
		var v: Fighter = e.f
		var arm: VoxelPart = v.arm.R.fore
		var b0: float = arm.bleed
		var tries := 0
		while tries < 12 and not v.has_meta("gem_t_" + gem):
			m._on_hit({"kind": "hit", "weapon": w, "char": v, "part": arm, "attacker": null, "p": arm.global_position, "dir": Vector3(0, 0, 1), "J": 12.0, "type": "edge", "res": {"severed": []}, "killed": false})
			tries += 1
		got[gem] = {"burn": arm.spots.any(func(s): return s.kind == "fire"), "acid": arm.spots.any(func(s): return s.kind == "acid"), "fn": arm.function(), "slow": v.slow_factor, "bleed": arm.bleed - b0}
		i += 1
	t.check(got.ruby.burn, "the ruby sets the forearm it struck alight (%s)" % [got.ruby])
	t.check(got.sapphire.fn < 0.3 and got.sapphire.slow < 0.5, "the sapphire freezes the forearm stiff (%s)" % [got.sapphire])
	t.check(got.emerald.acid and got.emerald.bleed > 0.5, "the emerald poisons the wound and it eats in (%s)" % [got.emerald])
	m.queue_free()

## The armourer's bench: a piece designed there protects by its stuff and weighs by it, costs
## by its plates, can be bought and worn like any other; a design from someone else is made
## safe; and the weight of what a man wears costs him breath when he runs and swings, and pace.
func test_armour_designed_at_the_bench_and_its_weight() -> void:
	var lth := Armory.design_piece("torso", "leather", 0.2, 1.0, false, true, "Light")
	var stl := Armory.design_piece("torso", "steel", 0.2, 1.0, false, true, "Heavy")
	t.check(Armory.design_kg(stl) > 4.0 * Armory.design_kg(lth), "steel weighs far more than leather (%.1f vs %.1f kg)" % [Armory.design_kg(stl), Armory.design_kg(lth)])
	t.check(Armory.design_price(stl) > Armory.design_price(lth), "and costs more")
	var ids := Armory.register([stl])
	t.eq(ids.size(), 1, "registered")
	t.check(Armory.custom(ids[0]) and Armory.protection(ids[0]) > 0.9, "a custom steel piece: high protection")
	var b := Armory.buy([], ids[0])
	t.check(not b.has("error") and b.worn.has(ids[0]), "bought and worn")
	t.eq(Armory.sanitize(b.worn), b.worn, "a save keeps it")
	t.check(Armory.clean_design({"mat": "uranium", "parts": {"torso": [[0, 0, 0]]}}) == null, "nonsense stuff is refused")
	var junk = Armory.clean_design({"mat": "iron", "parts": {"torso": [[0, 0, 99], [0, 1, -1]], "tail": [[0, 0, 0]]}})
	t.check(junk != null and junk.parts.size() == 1 and (junk.parts.torso as Array).size() == 1, "cells off the body and unknown parts dropped")
	var light := Armory.burden(2.0)
	var heavy := Armory.burden(40.0)
	t.check(heavy.breath > 2.0 and light.breath < 1.1, "breath: light ×%.2f, heavy ×%.2f" % [light.breath, heavy.breath])
	t.check(heavy.pace < 0.75 and light.pace == 1.0, "pace: heavy %.2f" % heavy.pace)
	# On a man: the heavier kit drains his breath faster in the same run.
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none"}, "decrees": [], "hazards": [], "headless": true})
	m.me.f.teleport(Vector3(0, 0, -10))
	var run := func(_e): return {"mz": 1.0, "sprint": true, "look": {"yaw": 0.0, "pitch": 0.0}}
	var used := []
	for kit in [[], ["steelLorica", "steelGreaves", "murmilloHelm", "cuisses"]]:
		var e = m.spawn_fighter({"kind": "bot", "name": "R", "loadout": {"main": "", "off": "", "armor": kit}, "team": 1, "pos": Vector3(4.0 * used.size(), 0.1, -6), "yaw": 0.0})
		e.erase("bot")
		e.drive = run
		await _steps(30)
		e.f.stamina = 100.0
		await _steps(120 * 2)
		used.append(100.0 - e.f.stamina)
	t.check(used[1] > used[0] * 1.4, "an armoured runner tires faster (%.0f vs %.0f breath)" % [used[1], used[0]])
	m.queue_free()
