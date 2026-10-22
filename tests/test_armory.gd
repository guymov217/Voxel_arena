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
		got[gem] = {"burn": arm.spots.any(func(s): return s.kind == "fire"), "acid": arm.spots.any(func(s): return s.kind == "acid"), "frost": arm.spots.any(func(s): return s.kind == "frost"), "fn": arm.function(), "slow": v.slow_factor, "bleed": arm.bleed - b0}
		i += 1
	t.check(got.ruby.burn, "the ruby sets the forearm it struck alight (%s)" % [got.ruby])
	t.check(got.sapphire.fn < 0.3 and got.sapphire.slow < 0.5, "the sapphire freezes the forearm stiff (%s)" % [got.sapphire])
	t.check(got.sapphire.frost, "and frostbite sets in there")
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

## Gold in a weapon: the crowd loves the blows it lands, and more gold more.
func test_a_golden_blow_wins_the_crowd() -> void:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "duel", "headless": true, "seed": 2, "decrees": [], "hazards": []})
	var me: Fighter = m.me.f
	var foe = null
	for e in m.entities:
		if e != m.me:
			foe = e.f
	var d := Data.preset("gladius").duplicate(true)
	for v in d.voxels:
		if v[4] == "blunt":
			v[3] = "gold"
	var w := Weapon.new()
	w.setup(d)
	m.add_child(w)
	var f0: float = m.spectacle.get_favor(me)
	m._on_hit({"kind": "hit", "weapon": w, "char": foe, "part": foe.torso, "attacker": me, "p": foe.torso.global_position, "dir": Vector3(0, 0, 1), "J": 10.0, "type": "edge", "res": {"severed": []}, "killed": false})
	t.check(m.spectacle.get_favor(me) > f0 + 1.0, "the crowd roars (%.1f → %.1f)" % [f0, m.spectacle.get_favor(me)])
	m.queue_free()


## Frostbite: the flesh where it set in turns white, then black, then falls away, without a
## drop of blood; the limb is all but useless while the cold is in it.
func test_frostbite_kills_the_flesh_it_bites() -> void:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none"}, "decrees": [], "hazards": [], "headless": true})
	m.me.f.teleport(Vector3(0, 0, -10))
	var e = m.spawn_fighter({"kind": "bot", "name": "V", "loadout": {}, "team": 1, "pos": Vector3(0, 0.1, 0), "yaw": 0.0})
	e.erase("bot")
	e.drive = func(_e): return {}
	await _steps(10)
	var v: Fighter = e.f
	var thigh: VoxelPart = v.by_name["thighR"]
	var n0: int = thigh.alive_count
	var blood0: float = v.blood
	m.add_spot(v, thigh, "frost", 8.0, null, thigh.global_position + Vector3(0, 0, thigh.half_ext.z))
	await _steps(30)
	t.check(thigh.function() < 0.3, "the frozen thigh hardly works (%.2f)" % thigh.function())
	await _steps(120 * 7)
	t.check(thigh.alive_count < n0, "the frostbitten flesh died away (%d → %d voxels)" % [n0, thigh.alive_count])
	t.check(v.blood > blood0 - 3.0, "with hardly any blood lost (%.1f → %.1f)" % [blood0, v.blood])
	m.queue_free()

## The armourer's bench plate by plate: a plate goes on the outside of the part only, never
## inside it or hanging in the air; a pair of limbs is plated alike; more plates weigh and cost
## more, and what is made is a piece the game knows and puts on.
func test_armour_plate_by_plate() -> void:
	var f := ArmourForge.new()
	add_child(f)
	var got := []
	f.open({"name": "Mine", "mat": "iron", "parts": {}}, "shins", func(d): got.append(d))
	f.mirror = false
	var X: int = f.dims.x
	t.check(not f.add_plate(Vector3i(0, 0, 0)), "no plate inside the leg")
	t.check(not f.add_plate(Vector3i(-1, f.dims.y + 1, -1)), "none hanging in the air")
	t.check(f.add_plate(Vector3i(0, 2, f.dims.z)), "one on the front of the shin")
	t.check(f.add_plate(Vector3i(0, 3, f.dims.z)), "and one above it")
	var d := f.design_now()
	t.eq((d.parts.shinR as Array).size(), 2, "two plates on the right shin")
	t.eq((d.parts.shinL as Array).size(), 2, "and the left alike")
	t.check(d.parts.shinL.has([X - 1, 2, f.dims.z]), "mirrored on the other leg")
	var kg1 := Armory.design_kg(d)
	var p1 := Armory.design_price(d)
	f.mirror = true
	f.add_plate(Vector3i(0, 4, f.dims.z))
	d = f.design_now()
	t.check(Armory.design_kg(d) > kg1 and Armory.design_price(d) > p1, "more plates: heavier and dearer")
	t.check(f.remove_plate(Vector3i(0, 4, f.dims.z)) and f.design_now().parts.shinR.size() == 2, "right click takes them off again")
	d.mat = "steel"
	var ids := Armory.register([d])
	t.eq(ids.size(), 1, "the game knows the piece")
	t.eq(Armory.design_cells(Data.armor[ids[0]]), Armory.design_cells(d), "every plate kept")
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none"}, "headless": true, "seed": 3})
	m.me.f.set_armor_pieces(ids)
	t.check(m.me.f.armor_weight() > 0.0, "and he wears it (%.1f kg)" % m.me.f.armor_weight())
	m.queue_free()
	f.queue_free()

## Armour is made at the forge: its Armour tab gives way to the armour bench (any part of the
## body, picked on the bench). From the main menu's forge the piece is kept in My designs, free,
## and the forge opens again; in training's forge it is kept and worn; the fighter goes out in it.
func test_armour_is_made_at_the_forge() -> void:
	var menu = load("res://scripts/ui/menu.gd").new()
	add_child(menu)
	await get_tree().process_frame
	menu._workshop_forge()
	await get_tree().process_frame
	var forge = _find(menu, func(n): return n.get_script() == load("res://scripts/ui/forge.gd"))
	t.check(forge != null, "the main menu's forge is open")
	var tab = _find(forge, func(n): return n is Button and (n as Button).text == "Armour")
	t.check(tab != null, "the forge has an Armour tab")
	tab.pressed.emit()
	await get_tree().process_frame
	var bench: ArmourForge = _find(menu, func(n): return n is ArmourForge)
	t.check(bench != null, "the Armour tab opens the armour bench")
	bench.switch_region("head")
	await get_tree().process_frame
	t.eq(bench.region, "head", "any part of the body is picked on the bench")
	_cover(bench)
	bench.done.call(bench.design_now())
	await get_tree().process_frame
	var designs: Dictionary = Save.get_value("armor_designs", {})
	t.eq(designs.size(), 1, "kept in My designs, free")
	await get_tree().process_frame
	t.check(_find(menu, func(n): return n.get_script() == load("res://scripts/ui/forge.gd")) != null, "and the forge opens again")
	# Training's forge: made there, it is worn as well.
	var f2 = _find(menu, func(n): return n.get_script() == load("res://scripts/ui/forge.gd"))
	f2.queue_free()
	await get_tree().process_frame
	menu._training_forge()
	await get_tree().process_frame
	var tf = _find(menu, func(n): return n.get_script() == load("res://scripts/ui/forge.gd"))
	menu.armour_from_forge(tf)
	await get_tree().process_frame
	bench = _find(menu, func(n): return n is ArmourForge)
	_cover(bench)
	bench.done.call(bench.design_now())
	await get_tree().process_frame
	t.eq((menu.training.armor as Array).size(), 1, "made at training's forge: worn as well as kept")
	t.eq(menu.screen, "training_armour", "back at training's armour")
	menu.show_screen("training")
	await get_tree().process_frame
	menu._start_training()
	await _steps(20)
	var f: Fighter = menu.match_.me.f
	var n := 0
	for p in f.parts:
		n += (p.get_meta("armor", []) as Array).size()
	t.check(n >= 1 and f.armor_weight() > 0.0, "the fighter wears it (%d pieces on, %.1f kg)" % [n, f.armor_weight()])
	menu.queue_free()
	await get_tree().process_frame

func _cover(bench: ArmourForge) -> void:
	for c in Armory._wrap([bench.dims.x, bench.dims.y, bench.dims.z], 0, bench.dims.y - 1, "all"):
		bench.cells[Vector3i(c[0], c[1], c[2])] = true

func _find(n: Node, pred: Callable):
	if pred.call(n):
		return n
	for c in n.get_children():
		var r = _find(c, pred)
		if r != null:
			return r
	return null

## Armour may stand out from the body: a crest rising off the helmet, plates built up and out,
## up to Armory.DESIGN_OUT from the part, each holding on to the one before; it is kept as built
## and weighs what its plates weigh. The bench says which way is the front.
func test_armour_built_up_and_out() -> void:
	var bench := ArmourForge.new()
	add_child(bench)
	bench.open(Armory.design_piece("head", "iron", 0.0, 1.0, false, false, ""), "head", func(_d): pass)
	var top := Vector3i(bench.dims.x / 2, bench.dims.y, bench.dims.z / 2)
	bench.mirror = false
	var put := 0
	for k in Armory.DESIGN_OUT:
		if bench.add_plate(top + Vector3i(0, k, 0)):
			put += 1
	t.eq(put, Armory.DESIGN_OUT, "a crest of %d plates rises off the head" % Armory.DESIGN_OUT)
	t.check(not bench.add_plate(top + Vector3i(0, Armory.DESIGN_OUT, 0)), "but no further than the bench allows")
	var before := Armory.design_kg(bench.design_now())
	var ids := Armory.register([bench.design_now()])
	t.check(not ids.is_empty(), "the crest is kept as built")
	var d: Dictionary = Data.armor[ids[0]]
	var n := 0
	for p in d.parts:
		n += (d.parts[p] as Array).size()
	t.check(n >= put, "every plate of it (%d)" % n)
	t.check(Armory.design_kg(bench.design_now()) >= before and before > 0.0, "and it weighs (%.1f kg)" % before)
	var tags := []
	var stack: Array = [bench]
	while stack.size():
		var nd: Node = stack.pop_back()
		if nd is Label3D:
			tags.append((nd as Label3D).text)
		stack.append_array(nd.get_children())
	t.check(tags.has("FRONT") and tags.has("BACK"), "the bench marks the front and the back (%s)" % [tags])
	bench.queue_free()

## A plate struck hard enough flies off as a piece, whatever side and angle the blow came from;
## lighter blows on the same spot wear it until it gives. Where there is no armour, nothing flies.
func test_struck_plates_fly_off_from_any_side() -> void:
	var w := TestWorld.new()
	add_child(w)
	w.ready_arena()
	var sides := {"front": Vector3(0, 0, 1), "back": Vector3(0, 0, -1), "left": Vector3(1, 0, 0), "right": Vector3(-1, 0, 0),
		"above": Vector3(0.3, 1, 0.4), "below at an angle": Vector3(-0.5, -0.6, 0.6)}
	var x := 0.0
	for side in sides:
		x += 2.5
		var f := w.fighter(Vector3(x, 1.2, 0), 0.0, {"armor": ["steelLorica"]})
		var tor: VoxelPart = f.torso
		var out: Vector3 = (sides[side] as Vector3).normalized()
		# The point on the lorica's side of the trunk the blow comes in at.
		var he: Vector3 = tor.half_ext
		var lp := out / maxf(absf(out.x) / he.x, maxf(absf(out.y) / he.y, absf(out.z) / he.z))   # on the trunk's surface
		var at: Vector3 = tor.global_transform * lp
		var dir := -(tor.global_transform.basis * out).normalized()
		var ad: Dictionary = tor.get_meta("armor")[0]
		var before: int = ad.alive
		var pieces := Chunk.all.size()
		var res := f.apply_hit(tor, {"point": at, "dir": dir, "type": "blunt", "hardness": 1.0, "sharpness": 0.0, "impulse": 80.0, "heavy": 0.8})
		t.check(int(res.get("armor_hit", 0)) > 0 and ad.alive < before, "%s: a hard blow knocks plates off (%d)" % [side, before - ad.alive])
		t.check(Chunk.all.size() > pieces, "%s: they fly off as pieces" % side)
		var flying := Chunk.all.slice(pieces).filter(func(c): return is_instance_valid(c))
		t.check(flying.any(func(c): return c.linear_velocity.dot(dir) > 0.2), "%s: driven the way the blow went" % side)
	# Light blows that knock nothing at once wear the plate until it gives.
	var f2 := w.fighter(Vector3(-3, 1.2, 0), 0.0, {"armor": ["steelLorica"]})
	var t2: VoxelPart = f2.torso
	var ad2: Dictionary = t2.get_meta("armor")[0]
	var at2: Vector3 = t2.global_transform * Vector3(0, 0, t2.half_ext.z)
	var dir2 := -(t2.global_transform.basis * Vector3.BACK).normalized()
	var first := f2.apply_hit(t2, {"point": at2, "dir": dir2, "type": "blunt", "hardness": 0.6, "sharpness": 0.0, "impulse": 9.0})
	t.eq(int(first.get("armor_hit", 0)), 0, "one light knock takes no plate")
	var n := 1
	while int(ad2.alive) == ad2.cells.size() and n < 40:
		f2.apply_hit(t2, {"point": at2, "dir": dir2, "type": "blunt", "hardness": 0.6, "sharpness": 0.0, "impulse": 9.0})
		n += 1
	t.check(int(ad2.alive) < ad2.cells.size(), "light knocks wear a plate off in the end (%d blows)" % n)
	t.check(n > 2, "but not at the first few (%d)" % n)
	w.queue_free()

## Armour counts against a heavy blow too: the same club through a steel cuirass hurts less
## than through a tunic, and a leather jerkin takes a real bite out of a cut.
func test_armour_softens_clubs_and_cuts() -> void:
	var dmg := func(armor: Array, type: String, sharp: float, J: float) -> float:
		var m := Match.new()
		add_child(m)
		m.setup({"mode": "training", "headless": true, "loadout": {"main": "gladius", "armor": armor}, "training": {"enemy": "none"}, "seed": 5})
		var g: Fighter = m.me.f
		for i in 30:
			await get_tree().physics_frame
		var pt: Vector3 = g.torso.global_transform * Vector3(0, 0.1, -g.torso.half_ext.z)
		var r: Dictionary = g.apply_hit(g.torso, {"impulse": J, "type": type, "hardness": 0.9, "sharpness": sharp, "point": pt, "dir": Vector3.FORWARD, "axis": Vector3.RIGHT, "edge": Vector3.FORWARD})
		m.queue_free()
		await get_tree().process_frame
		return float(r.get("dmg", 0.0))
	var bare_club: float = await dmg.call([], "blunt", 0.0, 60.0)
	var steel_club: float = await dmg.call(["steelLorica"], "blunt", 0.0, 60.0)
	t.check(steel_club < bare_club * 0.7, "a club through steel: %.1f against %.1f bare" % [steel_club, bare_club])
	var bare_cut: float = await dmg.call([], "edge", 0.8, 40.0)
	var leather_cut: float = await dmg.call(["leatherJerkin"], "edge", 0.8, 40.0)
	t.check(leather_cut < bare_cut * 0.8, "a cut through leather: %.1f against %.1f bare" % [leather_cut, bare_cut])

## Armour built thicker at the bench protects more: a second ring of steel plates round the
## trunk takes more out of the same blow than one.
func test_thicker_armour_protects_more() -> void:
	var one := Armory.design_piece("torso", "steel", 0.0, 1.0, false, false, "One")
	var two := one.duplicate(true)
	two.name = "Two"
	var X: int = Armory._dims("torso")[0]
	var Z: int = Armory._dims("torso")[2]
	var outer := []
	for c in two.parts.torso:
		var x: int = c[0]
		var z: int = c[2]
		outer.append([x - 1 if x == -1 else (x + 1 if x == X else x), c[1], z - 1 if z == -1 else (z + 1 if z == Z else z)])
	two.parts.torso = two.parts.torso + outer
	var ids := Armory.register([one, two])
	t.eq(ids.size(), 2, "both pieces registered")
	var dmg := func(id: String) -> float:
		var m := Match.new()
		add_child(m)
		m.setup({"mode": "training", "headless": true, "loadout": {"main": "gladius", "armor": [id], "armor_defs": Armory.defs_of([id])}, "training": {"enemy": "none"}, "seed": 5})
		var g: Fighter = m.me.f
		for i in 30:
			await get_tree().physics_frame
		var pt: Vector3 = g.torso.global_transform * Vector3(0, 0.1, -g.torso.half_ext.z)
		var r: Dictionary = g.apply_hit(g.torso, {"impulse": 40.0, "type": "edge", "hardness": 0.9, "sharpness": 0.8, "point": pt, "dir": Vector3.BACK, "axis": Vector3.RIGHT, "edge": Vector3.BACK})
		m.queue_free()
		await get_tree().process_frame
		return float(r.get("dmg", 0.0))
	var d1: float = await dmg.call(ids[0])
	var d2: float = await dmg.call(ids[1])
	t.check(d1 > 0.0 and d2 < d1 * 0.8, "two layers of steel: %.1f against %.1f through one" % [d2, d1])

## A plate painted at the bench keeps its colour: in the design the bench gives, through the
## cleaning a design gets when it arrives from another machine, and on the piece as worn.
func test_painted_plates_keep_their_colour() -> void:
	var bench := ArmourForge.new()
	add_child(bench)
	bench.open(Armory.design_piece("torso", "iron", 0.0, 1.0, false, false, ""), "torso", func(_d): pass)
	bench.mirror = false
	bench.paint = 0x9b1c1c
	var top := Vector3i(bench.dims.x / 2, bench.dims.y, bench.dims.z / 2)
	t.check(bench.add_plate(top), "a plate is laid in red")
	var d: Dictionary = bench.design_now()
	var red := (d.parts.torso as Array).filter(func(c): return c.size() > 3 and int(c[3]) == 0x9b1c1c)
	t.eq(red.size(), 1, "the design carries the colour")
	var plain := (d.parts.torso as Array).filter(func(c): return c.size() == 3)
	t.check(plain.size() > 0, "the unpainted plates carry none")
	var c = Armory.clean_design(d)
	t.check(c != null and (c.parts.torso as Array).any(func(x): return x.size() > 3 and int(x[3]) == 0x9b1c1c), "cleaning keeps it")
	var junk = Armory.clean_design({"mat": "iron", "parts": {"torso": [[0, 0, 0, "red"], [1, 0, 0, 0x1ff0000ff]]}})
	t.check(junk != null and (junk.parts.torso as Array)[0].size() == 3 and int((junk.parts.torso as Array)[1][3]) == 0x0000ff, "nonsense colours dropped, big ones clipped")
	var ids := Armory.register([d])
	t.eq(ids.size(), 1, "registered")
	var cells: Array = Data.armor[ids[0]].parts.torso
	var styled := ArmorStyle.cells(ids[0], Data.armor[ids[0]], cells, Color.WHITE)
	var reds := 0
	var greys := 0
	for k in cells.size():
		var col: Color = styled[k][0]
		if col.r > 2.0 * col.g and col.r > 2.0 * col.b:
			reds += 1
		elif absf(col.r - col.g) < 0.05 and absf(col.g - col.b) < 0.05:
			greys += 1
	t.eq(reds, 1, "and the worn piece shows the red plate")
	t.eq(greys, cells.size() - 1, "the rest keep the stuff's colour")
	bench.queue_free()

## Every plate guards the spot it sits on until worn through, and a harder stuff holds longer:
## one gladius cut goes through a leather plate, a steel plate takes several.
func test_a_plate_holds_until_worn_through() -> void:
	t.check(Fighter.plate_wear("steel") > Fighter.plate_wear("iron") and Fighter.plate_wear("iron") > Fighter.plate_wear("leather"), "harder stuff wears slower (%.0f/%.0f/%.0f)" % [Fighter.plate_wear("leather"), Fighter.plate_wear("iron"), Fighter.plate_wear("steel")])
	var w := TestWorld.new()
	add_child(w)
	w.ready_arena()
	var blows := func(armor: String, x: float) -> int:
		var f := w.fighter(Vector3(x, 1.2, 0), 0.0, {"armor": [armor]})
		var tor: VoxelPart = f.torso
		var ad: Dictionary = tor.get_meta("armor")[0]
		var at: Vector3 = tor.global_transform * Vector3(0, 0, tor.half_ext.z)
		var dir := -(tor.global_transform.basis * Vector3.BACK).normalized()
		var n := 0
		while int(ad.alive) == ad.cells.size() and n < 20:
			f.apply_hit(tor, {"point": at, "dir": dir, "type": "edge", "hardness": 0.9, "sharpness": 0.8, "impulse": 30.0, "axis": Vector3.RIGHT, "edge": Vector3.BACK})
			n += 1
		return n
	var lth: int = blows.call("leatherJerkin", -3.0)
	var stl: int = blows.call("steelLorica", 3.0)
	t.check(lth <= 2, "a gladius cut goes through leather at once (%d)" % lth)
	t.check(stl > lth and stl < 20, "steel holds for more of them (%d)" % stl)
	w.queue_free()

## The plates a bout knocks off stay off: the man reports them, the save keeps them, he comes
## into the next bout without them, and the armourer puts them back for a price.
func test_knocked_plates_stay_off_until_mended() -> void:
	var w := TestWorld.new()
	add_child(w)
	w.ready_arena()
	var f := w.fighter(Vector3(0, 1.2, 0), 0.0, {"armor": ["steelLorica"]})
	var tor: VoxelPart = f.torso
	var at: Vector3 = tor.global_transform * Vector3(0, 0, tor.half_ext.z)
	var dir := -(tor.global_transform.basis * Vector3.BACK).normalized()
	f.apply_hit(tor, {"point": at, "dir": dir, "type": "blunt", "hardness": 1.0, "sharpness": 0.0, "impulse": 80.0, "heavy": 0.8})
	var rep := f.armor_wear()
	t.check(rep.has("steelLorica") and (rep.steelLorica.get("torso", []) as Array).size() > 0, "the man reports the plates off his lorica (%s)" % [rep])
	var n: int = (rep.steelLorica.torso as Array).size()
	var saved := Armory.add_wear({}, rep, ["steelLorica"])
	t.eq(int(Armory.plates_lost("steelLorica", saved)[0]), n, "the save keeps them")
	t.check(Armory.condition("steelLorica", saved) < 1.0, "condition below whole")
	t.eq(Armory.mend_cost("steelLorica", saved), n * 1, "mending costs half a plate's steel each (%d)" % Armory.mend_cost("steelLorica", saved))
	t.check(Armory.add_wear({}, {"steelLorica": {"tail": [1], "torso": [999, -1, 0]}}, ["steelLorica"]).steelLorica.torso == [0], "nonsense parts and cells dropped")
	t.check(Armory.clean_wear(saved, []).is_empty(), "a piece taken off takes its wear with it")
	w.queue_free()
	# Next bout: he comes in without those plates.
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "headless": true, "loadout": {"main": "gladius", "armor": ["steelLorica"], "armor_wear": saved}, "training": {"enemy": "none"}, "seed": 5})
	var ad: Dictionary = m.me.f.torso.get_meta("armor")[0]
	t.eq(int(ad.alive), ad.cells.size() - n, "the next bout starts with them off")
	t.eq(m.my_wear().get("armor", {}).get("steelLorica", {}).get("torso", []).size(), n, "and reports them again, unmended")
	m.queue_free()
	var mended := Armory.mend(saved, "steelLorica")
	t.check(int(mended.cost) > 0 and not mended.wear.has("steelLorica"), "mended: whole again for %d" % int(mended.cost))
