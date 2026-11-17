extends Node
## The special arrows for archers (user): six kinds bought one at a time at the market (the tab "For
## archers") and kept in the bag; a number on the hotbar picks one for the bow, which looses it, one
## out of the bag a shot, till it runs out (then plain arrows again); its number again puts it back.

var t

func _match(player_alive := false) -> Match:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none"}, "headless": true, "seed": 5})
	if not player_alive:
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

func _bleed(f: Fighter) -> float:
	var b := 0.0
	for p in f.parts:
		b += p.bleed
	return b

func _stuck(f: Fighter) -> int:
	var n := 0
	for p in f.parts:
		n += p.stuck.size()
	return n

## Where an arrow flying along +z meets a man facing the other way: the front of his torso.
func _front(f: Fighter) -> Vector3:
	var tp: VoxelPart = f.torso
	return tp.global_position + tp.global_basis * Vector3(0, 0, tp.half_ext.z)

# ---------- the market and the bag ----------

func test_the_archers_wares_have_a_tab_a_price_and_a_stack_of_five() -> void:
	var ids: Array = Throwables.ARROWS.keys()
	t.eq(ids.size(), 6, "six kinds of arrow")
	var tab := []
	for row in Market.TABS:
		if row[0] == "bow":
			tab = row[2]
	t.check(tab.size() == ids.size() and ids.all(func(id): return tab.has(id)), "the tab for archers holds them all")
	var menu_s = load("res://scripts/ui/menu.gd")
	for id in ids:
		var ware: Dictionary = Data.shop.throwables.get(id, {})
		t.check(int(ware.get("price", 0)) > 0 and str(ware.get("desc", "")) != "" and str(ware.get("name", "")) != "", "%s is on the table with a name, a word and a price" % id)
		t.check(Market.BASIC.has(id), "%s is there from the first visit" % id)
		t.eq(Throwables.stack_max(id), 5, "%s: five to a bag" % id)
		t.eq(menu_s.kit_use(id), "arrow", "%s is used on the bow, not thrown" % id)
		t.check(Items.TYPES.has(String(Throwables.ARROWS[id])) and Thumbs.item_type(id) == Throwables.ARROWS[id], "%s has an arrow of its own to draw and to fly" % id)
	# They are dear, the bursting one dearest (user: so that nobody can have the exploding arrows early in the campaign).
	var prices := {}
	for id in ids:
		prices[id] = int(Data.shop.throwables[id].price)
	t.check(prices.blastArrow == prices.values().max(), "the blasting arrow is the dearest of them (%s)" % str(prices))
	t.check(prices.blastArrow >= 2 * int(Data.shop.throwables.thunderPot.price), "and costs at least two thunder pots (%d)" % prices.blastArrow)
	t.check(prices.values().all(func(p): return p >= 30), "and none is pocket money")
	t.check(menu_s.MARKET_USE.has("arrow"), "the market tells how an arrow is used")
	t.check(menu_s.FRIENDLY_FIRE.has("blastArrow") and menu_s.FRIENDLY_FIRE.has("fireArrow"), "and warns of the two that burn and burst")
	# On the wire a guest's bag keeps them (five at most), and an arrow nobody sells is not one.
	var kit := Net.sanitize_kit({"fireArrow": 9, "blastArrow": 2, "silverArrow": 3})
	t.check(int(kit.get("fireArrow", 0)) == 5 and int(kit.get("blastArrow", 0)) == 2 and not kit.has("silverArrow"), "a guest's kit keeps the arrows, five at most (%s)" % str(kit))
	# On the hotbar after the pots and the food, in the order of the shop.
	t.eq(Throwables.hotbar_of({"fireArrow": 2, "bread": 1, "thunderPot": 1}), ["thunderPot", "bread", "fireArrow"], "the hotbar in shop order")

# ---------- the bow's choice ----------

## The archer draws and looses; the type of the arrow that left the bow.
func _loose(m: Match, phase: Array) -> String:
	var w: Weapon = null
	for e in m.entities:
		if e.get("is_archer", false):
			w = e.f.weapons.R
	phase[0] = 1
	for i in 500:
		await get_tree().physics_frame
		if float(w.get_meta("draw", 0.0)) > 0.35:
			break
	phase[0] = 2
	await _steps(3)
	var type := ""
	for it in m.items.list:
		if String(it.type).begins_with("pot_arrow") and not it.get("seen", false):
			it.seen = true
			type = it.type
	phase[0] = 0
	await _steps(120)   # (the pause to nock the next)
	return type

func test_a_picked_arrow_is_loosed_one_out_of_the_bag_a_shot_till_it_is_used_up() -> void:
	seed(11)
	var m := _match()
	var phase := [0]
	var a := _man(m, Vector3(0, 0, -5), 0.0, {"main": "bow"}, "Archer", 0, func(_e):
		return {"main": {"x": 0.3, "y": 0.45}, "power": phase[0] == 1, "look": {"yaw": 0.0, "pitch": 0.0}})
	a.is_archer = true
	a.kind = "local"
	a.inventory = {"bread": 1, "fireArrow": 2}
	var said := []
	m.feed.connect(func(s): said.append(str(s)))
	await _steps(60)
	var slot: int = Throwables.hotbar_of(a.inventory).find("fireArrow")
	t.check(slot >= 0 and m.throwables.use_item(a, slot), "its number picks the fire arrow")
	t.eq(a.f.arrow_pick, "fireArrow", "the bow has it")
	t.eq(int(a.inventory.fireArrow), 2, "and nothing is spent till it is loosed")
	t.check(a.f.held_item == null, "it is not taken into the hand like a pot")
	t.check(said.any(func(s): return s.begins_with("Fire arrow ready")), "the player is told which is ready (%s)" % str(said))
	var first: String = await _loose(m, phase)
	t.eq(first, "pot_arrow_fire", "the first is the fire arrow")
	t.eq(int(a.inventory.fireArrow), 1, "one out of the bag")
	t.eq(a.f.arrow_pick, "fireArrow", "and the next is still the same")
	var second: String = await _loose(m, phase)
	t.eq(second, "pot_arrow_fire", "so is the second")
	t.eq(int(a.inventory.fireArrow), 0, "the bag is empty")
	t.eq(a.f.arrow_pick, "", "and the pick is gone with it")
	t.check(said.any(func(s): return s.begins_with("Out of Fire arrow")), "the player is told (%s)" % str(said))
	var third: String = await _loose(m, phase)
	t.eq(third, "pot_arrow", "plain arrows again")
	# Its number again puts it back, and nothing was spent.
	a.inventory.fireArrow = 1
	slot = Throwables.hotbar_of(a.inventory).find("fireArrow")
	m.throwables.use_item(a, slot)
	t.eq(a.f.arrow_pick, "fireArrow", "picked again")
	m.throwables.use_item(a, slot)
	t.eq(a.f.arrow_pick, "", "its number again puts it back")
	t.check(said.any(func(s): return s.begins_with("Fire arrow put back")), "and says so")
	var fourth: String = await _loose(m, phase)
	t.eq([fourth, int(a.inventory.fireArrow)], ["pot_arrow", 1], "a plain arrow, and the one in the bag still there")
	# A pick the bag cannot honour (the arrows gone some other way) is a plain arrow, not a lost shot.
	a.f.arrow_pick = "frostArrow"
	var fifth: String = await _loose(m, phase)
	t.eq([fifth, a.f.arrow_pick], ["pot_arrow", ""], "no frost arrows in the bag: a plain arrow, and the pick dropped")
	m.queue_free()

func test_a_picked_arrow_stands_in_for_the_bows_own_gem_and_it_comes_back() -> void:
	var m := _match()
	var a := _man(m, Vector3(0, 0, -5), 0.0, {"main": "bow"}, "Archer", 0, _idle)
	await _steps(30)
	var w: Weapon = a.f.weapons.R
	var was = w.design.get("gem")
	w.design["gem"] = "ice"
	t.eq(m.throwables._nock_type(w, a.f), "pot_arrow_ice", "the gem's own arrows while none is picked")
	a.f.arrow_pick = "poisonArrow"
	t.eq(m.throwables._nock_type(w, a.f), "pot_arrow_poison", "the one picked instead of them")
	a.f.arrow_pick = ""
	t.eq(m.throwables._nock_type(w, a.f), "pot_arrow_ice", "and the gem's again when it is put back")
	if was == null:
		w.design.erase("gem")
	else:
		w.design["gem"] = was
	t.eq(m.throwables._nock_type(w, a.f), "pot_arrow" if was == null else "pot_arrow_" + str(was), "the bow as it was")
	m.queue_free()

func test_the_picked_arrow_comes_through_to_a_guests_copy_beside_the_grip() -> void:
	var m := _match()
	var host: Fighter = _man(m, Vector3(0, 0, 0), 0.0, {}, "Host", 0, _idle).f
	var copy: Fighter = _man(m, Vector3(3, 0, 0), 0.0, {}, "Copy", 0, _idle).f
	await _steps(5)
	host.arrow_pick = "blastArrow"
	copy.apply_status(host.status_packed())
	t.check(copy.arrow_pick == "blastArrow" and not copy.net_two_handed, "the copy has the pick, and no grip")
	host.two_handed = true
	host.two_side = "L"
	copy.apply_status(host.status_packed())
	t.check(copy.arrow_pick == "blastArrow" and copy.net_two_handed and copy.net_two_side == "L", "the grip rides beside it (%s, %s, %s)" % [copy.arrow_pick, copy.net_two_handed, copy.net_two_side])
	host.arrow_pick = ""
	host.two_handed = false
	host.two_side = "R"
	copy.apply_status(host.status_packed())
	t.check(copy.arrow_pick == "" and not copy.net_two_handed and copy.net_two_side == "R", "put back: plain again")
	for id in Throwables.ARROW_IDS:
		host.arrow_pick = id
		copy.apply_status(host.status_packed())
		t.eq(copy.arrow_pick, id, "'%s' goes over the wire as itself" % id)
	m.queue_free()

func test_the_hotbar_marks_the_arrow_picked_for_the_bow() -> void:
	var m := _match(true)
	m.me.inventory = {"bread": 1, "fireArrow": 2, "blastArrow": 1}
	var hud := Hud.new(m)
	add_child(hud)
	await _steps(3)
	await get_tree().process_frame
	var slot_of := func(id: String) -> Dictionary:
		for s in hud.slots:
			if s.id == id:
				return s
		return {}
	t.check(not slot_of.call("fireArrow").is_empty() and not slot_of.call("blastArrow").is_empty(), "the arrows are on the hotbar")
	t.check(not bool(slot_of.call("fireArrow").on) and not bool(slot_of.call("blastArrow").on) and hud.held_label.text == "", "none is marked while none is picked")
	m.me.f.arrow_pick = "blastArrow"
	await get_tree().process_frame
	t.check(bool(slot_of.call("blastArrow").on) and not bool(slot_of.call("fireArrow").on), "the picked one is marked")
	t.check(hud.held_label.text.contains("BLASTING ARROW"), "and the bow says what it looses (%s)" % hud.held_label.text)
	m.me.f.arrow_pick = ""
	await get_tree().process_frame
	t.check(not bool(slot_of.call("blastArrow").on) and hud.held_label.text == "", "put back: unmarked")
	hud.queue_free()
	m.queue_free()

# ---------- what each arrow does ----------

func test_fire_poison_frost_and_barbs_do_what_they_say() -> void:
	seed(7)
	var m := _match()
	var shooter: Fighter = _man(m, Vector3(0, 0, -9), 0.0, {}, "Shooter", 0, _idle).f
	var men := {}
	var x := -8.0
	for k in ["plain", "fire", "poison", "frost", "barb"]:
		men[k] = _man(m, Vector3(x, 0, 0), PI, {}, k, 1, _idle).f
		x += 4.0
	await _steps(40)
	var types := {"plain": "pot_arrow", "fire": "pot_arrow_fire", "poison": "pot_arrow_poison", "frost": "pot_arrow_ice", "barb": "pot_arrow_barb"}
	for k in men:
		m.throwables.explode(types[k], _front(men[k]), shooter, Vector3(0, 0, 1), men[k], men[k].torso, 1.0)
	var bleed := {}
	for k in men:
		bleed[k] = _bleed(men[k])
	await _steps(4)
	t.check(Fire.is_burning(men.fire) and not Fire.is_burning(men.plain), "a fire arrow sets the man alight, a plain one does not")
	t.check(m.throwables.zones.any(func(z): return z.type == "fire"), "and the sand where it fell")
	t.check(men.poison.slow_timer > 2.0 and men.poison.slow_factor < 0.8, "a poisoned man slows (%.1f s to %.2f)" % [men.poison.slow_timer, men.poison.slow_factor])
	t.check(men.poison.parts.any(func(p): return p.spots.any(func(s): return s.kind == "acid")), "and the poison eats into him")
	t.check(bleed.poison > bleed.plain + 1.0, "he bleeds more than from a plain arrow (%.1f against %.1f)" % [bleed.poison, bleed.plain])
	t.check(men.frost.slow_timer > 3.0 and men.frost.slow_factor <= 0.5, "a frost arrow chills him slow (%.1f s to %.2f)" % [men.frost.slow_timer, men.frost.slow_factor])
	t.check(men.plain.slow_timer <= 0.0, "a plain arrow does not")
	t.check(bleed.barb > bleed.plain + 1.0, "a barbed arrow leaves him bleeding hard (%.1f against %.1f)" % [bleed.barb, bleed.plain])
	t.check(_stuck(men.barb) == 1 and _stuck(men.plain) == 1, "and each of them stays in him")
	m.queue_free()

## `type` goes off against a bare man on the sand (struck: on the front of him; else `d` metres from him); what it does to him.
func _burst(type: String, struck: bool, d := 0.0) -> Dictionary:
	var m := _match()
	var shooter: Fighter = _man(m, Vector3(0, 0, -14), 0.0, {}, "Shooter", 0, _idle).f
	var v: Fighter = _man(m, Vector3(0, 0, 0), PI, {}, "V", 1, _idle).f
	await _steps(40)
	var hp0 := v.total_hp()
	if struck:
		m.throwables.explode(type, _front(v), shooter, Vector3(0, 0, 1), v, v.torso, 1.0)
	else:
		m.throwables.explode(type, Vector3(d, 0.2, 0), shooter)
	var down := false
	for i in 120:
		await get_tree().physics_frame
		down = down or v.state != "stand"
	var lost := 0
	for p in v.parts:
		lost += p.fx.size() - p.alive_count
	var out := {"hp": hp0 - v.total_hp(), "of": hp0, "down": down, "voxels": lost}
	m.queue_free()
	return out

func test_a_blasting_arrow_hurts_but_is_no_thunder_pot() -> void:
	var plain: Dictionary = await _burst("pot_arrow", true)
	var blast: Dictionary = await _burst("pot_arrow_blast", true)
	var pot: Dictionary = await _burst("pot_thunder", true)
	var near: Dictionary = await _burst("pot_arrow_blast", false, 0.7)
	var far: Dictionary = await _burst("pot_arrow_blast", false, 2.4)
	t.check(blast.hp > plain.hp * 1.5, "it hurts well beyond a plain arrow (%.0f against %.0f hp)" % [blast.hp, plain.hp])
	t.check(blast.hp < pot.hp * 0.7, "but nowhere near a thunder pot (%.0f against %.0f hp)" % [blast.hp, pot.hp])
	t.check(near.hp > 10.0, "it wounds a man beside where it burst (%.0f hp)" % near.hp)
	t.check(far.hp < 1.0 and not far.down, "and not one two metres off (%.1f hp)" % far.hp)

## An arrow shot so that it lands on the sand 0.8 m short of a man; what it did to his legs.
func _landed(type: String) -> Dictionary:
	var m := _match()
	var shooter: Fighter = _man(m, Vector3(0, 0, -6), 0.0, {}, "Archer", 0, _idle).f
	var v: Fighter = _man(m, Vector3(0, 0, 0), PI, {}, "V", 1, _idle).f
	await _steps(40)
	var hp0 := v.total_hp()
	var it: Dictionary = m.items.spawn(type, Vector3(0, 1.3, -3.0), Vector3(0, -6.0, 12.0), shooter)
	it.power = 1.0
	await _steps(60)
	var out := {"hp": hp0 - v.total_hp(), "left": m.items.list.any(func(i): return i == it), "stuck": _stuck(v)}
	m.queue_free()
	return out

func test_a_blasting_arrow_bursts_on_the_sand_where_it_lands() -> void:
	var plain: Dictionary = await _landed("pot_arrow")
	var blast: Dictionary = await _landed("pot_arrow_blast")
	t.check(plain.hp < 1.0 and blast.hp > 5.0, "it hurts the man it lands beside, a plain arrow does not (%.1f against %.1f hp)" % [blast.hp, plain.hp])
	t.check(not blast.left and blast.stuck == 0, "and it is spent, in nobody")

func test_a_bodkin_goes_through_three_men_and_stays_in_the_last() -> void:
	seed(21)
	var m := _match()
	var shooter: Fighter = _man(m, Vector3(0, 0, -6), 0.0, {}, "Archer", 0, _idle).f
	var men := []
	for i in 4:
		men.append(_man(m, Vector3(0, 0, 1.2 * i), PI, {}, "M%d" % i, 1, _idle).f)
	await _steps(60)
	var hurt := {}
	var js := []
	m.combat.hit.connect(func(h):
		if h.type == "point" and men.has(h.char):
			hurt[men.find(h.char)] = int(hurt.get(men.find(h.char), 0)) + 1
			js.append(float(h.J)))
	var y: float = men[0].torso.global_position.y
	var it: Dictionary = m.items.spawn("pot_arrow_pierce", Vector3(0, y, -3.0), Vector3(0, 0, 55.0), shooter)
	it.power = 1.0
	await _steps(90)
	t.eq([hurt.get(0, 0), hurt.get(1, 0), hurt.get(2, 0), hurt.get(3, 0)], [1, 1, 1, 0], "three men struck once each, the fourth not")
	t.eq(men.map(func(f): return _stuck(f)), [0, 0, 1, 0], "and it stays in the third only")
	t.check(js.size() == 3 and js[0] > js[1] and js[1] > js[2], "slower and weaker for each it passes (%s)" % str(js))
	t.check(not m.items.list.any(func(i): return i.type == "pot_arrow_pierce"), "and it is spent")
	# A plain arrow, shot the same way, stops in the first.
	var it2: Dictionary = m.items.spawn("pot_arrow", Vector3(0, y, -3.0), Vector3(0, 0, 55.0), shooter)
	it2.power = 1.0
	hurt.clear()
	await _steps(90)
	t.check(hurt.get(0, 0) == 1 and hurt.get(1, 0) == 0, "a plain arrow stops in the first (%s)" % str(hurt))
	m.queue_free()

# ---------- the bow and the strength stats ----------

## The speed an arrow has just as the bow looses it at a full draw, for an archer of that strength (the
## trainer's Vis).
func _arrow_leaving(strength: float) -> float:
	var m := _match()
	var phase := [0]
	var a := _man(m, Vector3(0, 0, -5), 0.0, {"main": "bow"}, "Archer", 0, func(_e):
		return {"main": {"x": 0.3, "y": 0.45}, "power": phase[0] == 1, "look": {"yaw": 0.0, "pitch": 0.0}})
	a.is_archer = true
	a.kind = "local"
	a.f.mods.strength = strength
	await _steps(60)
	var w: Weapon = a.f.weapons.R
	phase[0] = 1
	for i in 600:
		await get_tree().physics_frame
		if float(w.get_meta("draw", 0.0)) >= 1.0:
			break
	phase[0] = 2
	await _steps(3)
	var v := 0.0
	for it in m.items.list:
		if String(it.type).begins_with("pot_arrow"):
			v = (it.vel as Vector3).length()
	m.queue_free()
	await _steps(2)
	return v

## A stronger man draws a stiffer bow: the arrow leaves it faster, the more of Vis the more (user: the
## shooting of arrows must grow with the stats of strength as they are raised).
func test_a_stronger_archer_looses_a_faster_arrow() -> void:
	seed(3)
	var plain := await _arrow_leaving(1.0)
	var trained := await _arrow_leaving(1.2)
	var best := await _arrow_leaving(1.36)
	t.check(plain > 50.0 and plain < 60.0, "a plain man's full draw: %.1f m/s" % plain)
	t.check(trained > plain * 1.07 and trained < plain * 1.13, "a fifth more Vis: the arrow %.1f m/s, a tenth faster than %.1f" % [trained, plain])
	t.check(best > trained * 1.03 and best < plain * 1.2, "the most the trainer teaches: %.1f m/s" % best)

## The arrow strikes as hard as a blow of his weapon does: half of his strength and the whole of his
## Ictus, a man of no training as before.
func test_a_stronger_archers_arrow_strikes_harder() -> void:
	var m := _match()
	var plain: Fighter = _man(m, Vector3(-4, 0, -9), 0.0, {}, "Plain", 0, _idle).f
	var strong: Fighter = _man(m, Vector3(4, 0, -9), 0.0, {}, "Strong", 0, _idle).f
	strong.mods.strength = 1.3
	strong.mods.blow = 1.2
	var v1: Fighter = _man(m, Vector3(-4, 0, 0), PI, {}, "V1", 1, _idle).f
	var v2: Fighter = _man(m, Vector3(4, 0, 0), PI, {}, "V2", 1, _idle).f
	await _steps(40)
	var js := {}
	m.combat.hit.connect(func(h):
		if h.get("char") != null and String(h.get("type", "")) == "point":
			js[h.char] = float(h.J))
	m.throwables._dart("pot_arrow", _front(v1), plain, Vector3(0, 0, 1), v1, v1.torso, 1.0)
	m.throwables._dart("pot_arrow", _front(v2), strong, Vector3(0, 0, 1), v2, v2.torso, 1.0)
	t.check(js.has(v1) and js.has(v2), "both arrows landed")
	if js.has(v1) and js.has(v2):
		var k: float = float(js[v2]) / maxf(0.01, float(js[v1]))
		t.check(absf(k - 1.15 * 1.2) < 0.02, "the strong man's arrow lands %.2f times as hard (a half of his 30 per cent of strength and all of his 20 of Ictus: 1.38)" % k)
		t.check(float(js[v1]) > 15.0 and float(js[v1]) < 17.0, "and a plain man's is what it was (%.1f)" % float(js[v1]))
	m.queue_free()
