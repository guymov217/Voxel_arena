extends Node
## The armourer and the coatings: every piece on the rack exists and fits a body, buying one
## takes off what it clashes with (sold back for half), a save cannot wear nonsense; venom, fire
## and frost go on a weapon at the smith and do what they say when it strikes.

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

func test_coatings_at_the_smith() -> void:
	var a := Arms.empty()
	a.main = Data.preset("gladius").duplicate(true)
	t.check(Arms.can_upgrade("venom", a.main) and Arms.can_upgrade("fire", a.main) and Arms.can_upgrade("frost", a.main), "a sword takes any coating")
	t.check(not Arms.can_upgrade("venom", Data.shop.stick), "venom needs an edge or a point: not on a stick")
	var r := Arms.upgrade(a, "R", "venom")
	t.eq(String(r.arms.main.get("imbue", "")), "venom", "coated with venom")
	r = Arms.upgrade(r.arms, "R", "fire")
	t.eq(String(r.arms.main.get("imbue", "")), "fire", "a new coating replaces the old")

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
