extends Node
## The yard's stalls in their showcase layout (MarketScreen, SmithScreen with its armour rack and
## armour bench, TrainerScreen, PhysicianScreen): each fits the screen at the sizes a player has
## (the user: everything in, nothing cut off), and what is asked of them is done as it was: paid
## once, and in the man's save.

var t

const SIZES := [Vector2i(1600, 900), Vector2i(1280, 720), Vector2i(1067, 600), Vector2i(2000, 1125)]

## The first node of the script class `cls` under `root` (a stall's screen).
static func _screen(root: Node, cls: Script) -> Node:
	for n in root.find_children("*", "VBoxContainer", true, false):
		if is_instance_of(n, cls):
			return n
	return null

func _steps(n: int) -> void:
	for i in n:
		await get_tree().process_frame

## A menu with a yard in name only: what the screens ask is whether he is in it (the way out they
## show), and that is all.
func _menu() -> Array:
	var menu = load("res://scripts/ui/menu.gd").new()
	menu.backdrop_off = true
	add_child(menu)
	var fake := Match.new()
	fake.mode = "yard"
	add_child(fake)
	menu.match_ = fake
	return [menu, fake]

func _gone(pair: Array) -> void:
	pair[0].match_ = null
	pair[1].queue_free()
	pair[0].queue_free()

func _wounded() -> Dictionary:
	var b := Body.empty()
	b.missing = ["shinR"]
	b.eyes = {"L": "lost"}
	b.fractures = {"forearmL": 2, "ribs": 4}
	b.scars = {"torso": range(0, 40), "thighL": range(0, 20)}
	b.fresh = {"torso": range(0, 25)}
	return Body.sanitize(b)

func _arms() -> Dictionary:
	var worn := []
	for i in range(10, 25):
		worn.append(i)
	return {"main": Data.preset("gladius").duplicate(true), "off": Data.preset("dagger").duplicate(true), "rack": [Data.preset("axe").duplicate(true)], "wear": {"R": worn, "L": []}}

## Every button of the screen that is on show and not inside something that scrolls.
func _loose(n: Node, out: Array) -> Array:
	if n is ScrollContainer:
		return out
	if n is Button and (n as Button).is_visible_in_tree():
		out.append(n)
	for c in n.get_children():
		_loose(c, out)
	return out

func test_every_stall_fits_the_screen_at_every_size() -> void:
	Save.set_value("coins", 900)
	Save.set_value("stage", 13)
	Save.set_value("kit", {"thunderPot": 3, "bread": 5})
	Save.set_value("body", _wounded())
	Save.set_value("arms", _arms())
	Save.set_value("armor_worn", ["lorica", "greaves", "helmet"])
	Save.set_value("forge_gallery", [Data.preset("warhammer").duplicate(true), Data.preset("axe").duplicate(true)])
	var shots := [
		["market", "the market", {"market_tab": "fire", "market_sel": ""}],
		["market", "the market, a ware at its most", {"market_tab": "fire", "market_sel": "thunderPot"}],
		["yard", "the smith's arms", {"smith_tab": "weapons", "smith_group": "arms", "smith_sel": {"kind": "arm", "side": "R"}}],
		["yard", "the smith's wares", {"smith_group": "sale", "smith_sel": {"kind": "base", "key": "longsword"}}],
		["yard", "the masterworks", {"smith_group": "works", "smith_sel": {"kind": "odd", "i": 1}}],
		["yard", "his designs", {"smith_group": "designs", "smith_sel": {"kind": "design", "i": 0}}],
		["yard", "the armour rack", {"smith_tab": "armour", "armour_sel": "steelLorica"}],
		["yard", "the armour bench", {"smith_tab": "bench"}],
		["trainer", "the trainer", {}],
		["physician", "the physician", {}],
	]
	var root := get_tree().root
	var size0 := root.content_scale_size
	var bad := []
	for sz in SIZES:
		root.content_scale_size = sz
		var pair := _menu()
		var menu: Control = pair[0]
		for shot in shots:
			for k in shot[2]:
				menu.set(k, shot[2][k])
			menu.show_screen(shot[0])
			await _steps(40)
			var vp: Vector2 = menu.get_viewport_rect().size
			var r: Rect2 = menu.panel.get_global_rect()
			if r.position.x < -1.0 or r.position.y < -1.0 or r.end.x > vp.x + 1.0 or r.end.y > vp.y + 1.0:
				bad.append("%s: %s's panel %s is not inside the screen %s" % [sz, shot[1], r, vp])
			var room := r.grow(2.0)
			for b in _loose(menu.panel, []):
				var br: Rect2 = (b as Button).get_global_rect()
				if br.size.x > 1.0 and not room.encloses(br):
					bad.append("%s: %s: the button \"%s\" %s is outside its panel %s" % [sz, shot[1], (b as Button).text, br, r])
		_gone(pair)
		await _steps(2)
	root.content_scale_size = size0
	t.check(bad.is_empty(), "everything is in, nothing cut off (%d: %s)" % [bad.size(), "; ".join(bad.slice(0, 3))])

func test_the_physician_treats_and_is_paid() -> void:
	Save.set_value("coins", 1000)
	Save.set_value("stage", 4)
	Save.set_value("body", _wounded())
	var pair := _menu()
	var menu: Control = pair[0]
	menu.show_screen("physician")
	await _steps(5)
	var ps: PhysicianScreen = _screen(menu, PhysicianScreen)
	t.check(ps != null, "the physician's table is there")
	if ps == null:
		_gone(pair)
		return
	var keys: Array = ps.groups.map(func(g): return String(g.key))
	t.check(keys.has("lost:shinR") and keys.has("eye:L") and keys.has("bone:forearmL") and keys.has("bone:ribs") and keys.has("wounds"), "what the arena left on him, by the part of him (%s)" % [keys])
	var offers: Array = Body.offers(menu.body(), 4)
	var peg: Dictionary = offers.filter(func(o): return String(o.id) == "peg:shinR")[0]
	# Too poor: nothing is done.
	Save.set_value("coins", int(peg.price) - 1)
	ps._treat("peg:shinR", int(peg.price))
	t.eq(menu.coins(), int(peg.price) - 1, "without the price nothing is paid")
	t.check(Body.sanitize(menu.body()).missing.has("shinR"), "and nothing is done")
	# Paid: the peg is fitted, the purse is lighter, the table is drawn again without it.
	Save.set_value("coins", 1000)
	ps._treat("peg:shinR", int(peg.price))
	await _steps(5)
	t.eq(menu.coins(), 1000 - int(peg.price), "the peg leg is paid for")
	var b := Body.sanitize(menu.body())
	t.check(b.prosthetics.get("shinR", "") == "peg" and not b.missing.has("shinR"), "and fitted")
	ps = _screen(menu, PhysicianScreen)
	t.check(ps != null and not ps.groups.any(func(g): return String(g.key) == "lost:shinR"), "the table no longer offers it")
	# The one button sees to what is left of the bones and the wounds.
	var all: Dictionary = Body.offers(menu.body(), 4).filter(func(o): return String(o.id) == "heal:all")[0]
	var coins1: int = menu.coins()
	ps._treat("heal:all", int(all.price))
	await _steps(5)
	t.eq(menu.coins(), coins1 - int(all.price), "treating everything is paid for once")
	b = Body.sanitize(menu.body())
	t.check(b.fractures.is_empty() and b.fresh.is_empty(), "every bone set and every fresh wound stitched")
	_gone(pair)
	await _steps(2)

func test_the_physician_sells_his_supplies_into_the_bag() -> void:
	Save.set_value("coins", 100)
	Save.set_value("body", Body.empty())
	Save.set_value("kit", {})
	var pair := _menu()
	var menu: Control = pair[0]
	menu.show_screen("physician")
	await _steps(5)
	var ps: PhysicianScreen = _screen(menu, PhysicianScreen)
	var price := int(Data.shop.throwables.bandage.price)
	ps._buy_supply("bandage", price)
	await _steps(3)
	t.eq(menu.coins(), 100 - price, "a bandage is paid for")
	t.eq(int(menu.kit().get("bandage", 0)), 1, "and in the bag")
	# A purse too light, and a bag too full.
	Save.set_value("coins", price - 1)
	ps = _screen(menu, PhysicianScreen)
	ps._buy_supply("bandage", price)
	await _steps(3)
	t.eq(int(menu.kit().get("bandage", 0)), 1, "no price, no bandage")
	Save.set_value("coins", 1000)
	var full := {}
	var kinds: Array = (Data.shop.throwables.keys() as Array).filter(func(i): return i != "bread").slice(0, Throwables.BAG_KINDS)
	for id in kinds:
		full[id] = 1
	t.eq(full.size(), Throwables.BAG_KINDS, "a bag with every kind it holds, and no bread")
	menu.set_kit(full)
	ps = _screen(menu, PhysicianScreen)
	var coins0: int = menu.coins()
	ps._buy_supply("bread", int(Data.shop.throwables.bread.price))
	await _steps(30)
	t.eq(menu.coins(), coins0, "nine kinds in the bag: nothing is bought")
	var pill := _warning(menu)
	t.check(pill != null and String((pill.get_child(0) as Label).text) == Loc.t("All %d slots are taken") % Throwables.BAG_KINDS, "and he is told why: every slot is taken")
	# The trader says no more than that either.
	menu.show_screen("market")
	await _steps(5)
	var ms: MarketScreen = _screen(menu, MarketScreen)
	ms.sel = "bread"
	ms.qty = 1
	ms._buy()
	await _steps(30)
	pill = _warning(menu)
	t.check(pill != null and String((pill.get_child(0) as Label).text) == Loc.t("All %d slots are taken") % Throwables.BAG_KINDS, "the trader tells it the same way")
	t.eq(menu.coins(), coins0, "and sells nothing")
	_gone(pair)
	await _steps(2)

func test_the_trainer_teaches_a_session_for_its_price() -> void:
	Save.set_value("coins", 1000)
	Save.set_value("stage", 13)
	Save.set_value("trainer", {})
	var pair := _menu()
	var menu: Control = pair[0]
	menu.show_screen("trainer")
	await _steps(5)
	var ts: TrainerScreen = _screen(menu, TrainerScreen)
	t.check(ts != null, "the trainer's table is there")
	var price := Training.price({}, "vis")
	var train: Button = null
	for b in menu.find_children("*", "Button", true, false):
		if String(b.text) == Loc.t("Train · %d denarii") % price and train == null:
			train = b
	t.check(train != null and not train.disabled, "a session of strength is on offer at %d" % price)
	if train:
		train.pressed.emit()
	await _steps(3)
	t.eq(menu.coins(), 1000 - price, "paid for once")
	t.eq(int(menu.training_stats().get("vis", 0)), Training.step("vis"), "and taught: strength up one session")
	_gone(pair)
	await _steps(2)

func test_the_smith_mends_a_weapon_and_the_armour_rack_sells_and_takes_back() -> void:
	Save.set_value("coins", 1000)
	Save.set_value("stage", 13)
	Save.set_value("arms", _arms())
	Save.set_value("armor_worn", [])
	var pair := _menu()
	var menu: Control = pair[0]
	menu.smith_tab = "weapons"
	menu.smith_group = "arms"
	menu.smith_sel = {"kind": "arm", "side": "R"}
	menu.show_screen("yard")
	await _steps(5)
	var rc := Arms.repair_cost(menu.arms(), "R")
	t.check(rc > 0, "the sword has lost voxels, and mending costs %d" % rc)
	var mend: Control = null
	for c in menu.find_children("*", "Control", true, false):
		if c.has_meta("job") and String(c.get_meta("job")) == "Mend":
			mend = c
	t.check(mend != null and bool(mend.get_meta("ok")), "the smith offers to mend it")
	if mend:
		mend.get_meta("cb").call()
		var sm: SmithScreen = _screen(menu, SmithScreen)
		var guard := 0
		while sm != null and is_instance_valid(sm) and sm.busy and guard < 600:
			await get_tree().process_frame
			guard += 1
		await _steps(3)
	t.eq(menu.coins(), 1000 - rc, "the hammer's work is paid for once")
	t.eq(Arms.repair_cost(menu.arms(), "R"), 0, "and the sword is whole")
	# The armour rack: buy a piece, then give it back at half.
	menu.smith_tab = "armour"
	menu.armour_region = "all"
	menu.armour_sel = "steelLorica"
	menu.show_screen("yard")
	await _steps(5)
	var cost := int(Armory.buy([], "steelLorica").cost)
	var coins0: int = menu.coins()
	var buy: Button = null
	for b in menu.find_children("*", "Button", true, false):
		if String(b.text) == Loc.t("Buy · %d denarii") % cost:
			buy = b
	t.check(buy != null and not buy.disabled, "the steel lorica is for sale at %d" % cost)
	if buy:
		buy.pressed.emit()
	await _steps(5)
	t.eq(menu.coins(), coins0 - cost, "paid for")
	t.check(menu.worn_armor().has("steelLorica"), "and worn")
	menu.armour_sel = "steelLorica"
	menu.show_screen("yard")
	await _steps(5)
	var off: Button = null
	for b in menu.find_children("*", "Button", true, false):
		if String(b.text) == Loc.t("Take off · %d denarii back") % (Armory.price("steelLorica") / 2):
			off = b
	t.check(off != null, "he can give it back at half")
	if off:
		off.pressed.emit()
	await _steps(5)
	t.check(not menu.worn_armor().has("steelLorica"), "taken off")
	t.eq(menu.coins(), coins0 - cost + Armory.price("steelLorica") / 2, "and the half is paid back")
	_gone(pair)
	await _steps(2)

## The red word a stall shows when a deed cannot be done (the newest, on the menu or on the panel
## the stall is in).
func _warning(menu: Control) -> Control:
	var newest: Control = null
	for host in [menu, menu.panel]:
		if host.has_meta("warn") and is_instance_valid(host.get_meta("warn")):
			var w: Control = host.get_meta("warn")
			if newest == null or w.get_instance_id() > newest.get_instance_id():
				newest = w
	return newest

## Every text under `root` but those inside `skip`.
func _texts(root: Node, skip: Node = null) -> Array:
	var out := []
	for l in root.find_children("*", "Label", true, false):
		if skip == null or not skip.is_ancestor_of(l):
			out.append(String((l as Label).text))
	return out

func test_no_stall_keeper_speaks_in_a_bubble() -> void:
	Save.set_value("coins", 900)
	Save.set_value("stage", 13)
	Save.set_value("body", _wounded())
	Save.set_value("arms", _arms())
	Save.set_value("armor_worn", ["lorica"])
	var names := ["MERCATOR THE TRADER", "VULCANUS THE SMITH", "DOCTORE THE TRAINER", "GALEN THE PHYSICIAN"]
	var parchment := Color(0.93, 0.87, 0.72)
	var pair := _menu()
	var menu: Control = pair[0]
	var heard := []
	for shot in [["market", {}], ["yard", {"smith_tab": "weapons"}], ["yard", {"smith_tab": "armour"}], ["yard", {"smith_tab": "bench"}], ["trainer", {}], ["physician", {}]]:
		for k in shot[1]:
			menu.set(k, shot[1][k])
		menu.show_screen(shot[0])
		await _steps(30)
		for x in _texts(menu):
			if names.has(x.to_upper()):
				heard.append("%s says it is %s" % [shot[0], x])
		for p in menu.find_children("*", "PanelContainer", true, false):
			var sb := (p as PanelContainer).get_theme_stylebox("panel")
			if sb is StyleBoxFlat and (sb as StyleBoxFlat).bg_color.is_equal_approx(parchment):
				heard.append("%s has a parchment" % shot[0])
	t.check(heard.is_empty(), "no speech bubble in any stall (%s)" % [heard])
	_gone(pair)
	await _steps(2)

func test_a_deed_that_cannot_be_done_is_told_in_a_red_line_that_goes() -> void:
	Save.set_value("coins", 0)
	Save.set_value("stage", 13)
	Save.set_value("body", _wounded())
	Save.set_value("arms", _arms())
	var why := Loc.t("Not enough denarii")
	var pair := _menu()
	var menu: Control = pair[0]
	# The trader: a ware he cannot pay for.
	menu.show_screen("market")
	await _steps(5)
	var ms: MarketScreen = _screen(menu, MarketScreen)
	ms._buy()
	await _steps(30)
	var pill := _warning(menu)
	t.check(pill != null and String((pill.get_child(0) as Label).text) == why, "the trader's table tells why: %s" % [why])
	if pill != null:
		var vp: Vector2 = menu.get_viewport_rect().size
		var r := pill.get_global_rect()
		t.check(Rect2(Vector2.ZERO, vp).encloses(r), "it is all on the screen (%s of %s)" % [r, vp])
		t.check(r.position.y >= ms.purse.get_global_rect().end.y - 1.0 and r.end.x <= ms.purse.get_global_rect().end.x + 1.0, "under the purse, ending where it ends (%s, the purse %s)" % [r, ms.purse.get_global_rect()])
		t.check(pill.modulate.a > 0.9, "and it can be read")
		var guard := 0
		while is_instance_valid(pill) and guard < 900:
			await get_tree().process_frame
			guard += 1
		t.check(not is_instance_valid(pill), "and then it goes (%d frames)" % guard)
	# The smith: what Menu says over his screen is not left lying there as a line of its own.
	menu.show_screen("yard", "Not enough denarii")
	await _steps(30)
	pill = _warning(menu)
	t.check(pill != null and String((pill.get_child(0) as Label).text) == why, "the smith's screen tells why")
	t.check(not _texts(menu.panel).has("Not enough denarii"), "and the old red line is not drawn as well")
	# The physician: a bandage he cannot pay for.
	menu.show_screen("physician")
	await _steps(5)
	var ps: PhysicianScreen = _screen(menu, PhysicianScreen)
	ps._buy_supply("bandage", int(Data.shop.throwables.bandage.price))
	await _steps(30)
	pill = _warning(menu)
	t.check(pill != null and String((pill.get_child(0) as Label).text) == why, "the physician's table tells why")
	t.check(not _texts(menu.panel, pill).has("Not enough denarii"), "and nothing else on it says so")
	# A long reason is broken into lines and stays on the screen.
	var long_why := "A reason that is far too long for one line, and goes on and on until it has to be broken into lines to stay on the screen"
	menu.show_screen("yard", long_why)
	await _steps(30)
	pill = _warning(menu)
	t.check(pill != null, "a long reason is told too")
	if pill != null:
		var vp2: Vector2 = menu.get_viewport_rect().size
		var r2 := pill.get_global_rect()
		t.check(Rect2(Vector2.ZERO, vp2).encloses(r2) and r2.size.x <= 470.0, "and fits the screen in lines (%s of %s)" % [r2, vp2])
	_gone(pair)
	await _steps(2)

func test_a_price_paid_rises_from_the_purse_of_the_screen_drawn_again() -> void:
	Save.set_value("coins", 500)
	Save.set_value("stage", 13)
	Save.set_value("trainer", {})
	var pair := _menu()
	var menu: Control = pair[0]
	menu.station_note = {"rise": "−17"}
	menu.show_screen("trainer")
	await _steps(8)
	var ts: TrainerScreen = _screen(menu, TrainerScreen)
	var rise: Label = null
	for l in menu.find_children("*", "Label", true, false):
		if (l as Label).text == "−17":
			rise = l
	t.check(rise != null, "the price paid is shown")
	if rise != null:
		var pr := ts.purse.get_global_rect()
		t.check(rise.global_position.x >= pr.position.x - 4.0 and rise.global_position.x <= pr.end.x and rise.global_position.y >= pr.position.y - 8.0 and rise.global_position.y <= pr.end.y + 60.0, "and it comes up from the purse %s, not from a corner (%s)" % [pr, rise.global_position])
	t.check(menu.station_note.is_empty(), "the note is spent")
	_gone(pair)
	await _steps(2)

# ---------- The armour bench plate by plate is down for now ----------

func test_no_way_into_the_plate_by_plate_bench_is_left() -> void:
	Save.set_value("coins", 900)
	Save.set_value("stage", 13)
	Save.set_value("arms", _arms())
	Save.set_value("armor_worn", ["lorica"])
	t.eq(Armory.plate_bench_open, false, "the bench is down by default")
	var pair := _menu()
	var menu: Control = pair[0]
	# The smith's own bench still forges a piece and puts it on; only the plate by plate is gone.
	menu.smith_tab = "bench"
	menu.show_screen("yard")
	await _steps(20)
	var texts := []
	for b in menu.find_children("*", "Button", true, false):
		texts.append(String((b as Button).text))
	t.check(texts.has(Loc.t("Forge and wear · %d denarii") % Armory.design_price(Armory.design_piece(menu.bench.region, menu.bench.mat, menu.bench.y0, menu.bench.y1, menu.bench.front, menu.bench.cap, ""))), "the smith's bench still forges and dresses him")
	t.check(not texts.has("Shape it plate by plate") and not texts.has(Loc.t("Shape it plate by plate")), "but there is no plate by plate")
	# Training's armour.
	menu.show_screen("training_armour")
	await _steps(5)
	texts = []
	for b in menu.find_children("*", "Button", true, false):
		texts.append(String((b as Button).text))
	t.check(not texts.has(Loc.t("Make a piece at the bench (free)")), "training's armour has no bench to make a piece at")
	# The weapon forge: no Armour tab.
	menu._workshop_forge()
	await _steps(10)
	var forge = null
	for n in menu.find_children("*", "Control", true, false):
		if n.get_script() == load("res://scripts/ui/forge.gd"):
			forge = n
	t.check(forge != null, "the forge is open")
	if forge != null:
		var armour_tab := false
		for b in forge.find_children("*", "Button", true, false):
			if String((b as Button).text) == "Armour":
				armour_tab = true
		t.check(not armour_tab, "and it has no Armour tab")
		forge.queue_free()
	# Forge and Fight: no time to set for the armour, and no armour phase.
	var v := VBoxContainer.new()
	menu.add_child(v)
	menu._ff_setup(v)
	var said := []
	for l in v.find_children("*", "Label", true, false):
		said.append(String((l as Label).text).to_upper())
	t.check(not said.has("TIME TO MAKE THE ARMOUR") and not said.has(Loc.t("Time to make the armour").to_upper()), "Forge and Fight asks no time for armour")
	t.check(not (said.any(func(x): return x.contains("ARMOUR"))), "and does not say that armour is made (%s)" % [said])
	t.eq(int(menu.ff_times.armour), 0, "none is made")
	v.queue_free()
	# Kept: the way back is one switch.
	Armory.plate_bench_open = true
	menu.smith_tab = "bench"
	menu.show_screen("yard")
	await _steps(20)
	texts = []
	for b in menu.find_children("*", "Button", true, false):
		texts.append(String((b as Button).text))
	t.check(texts.has(Loc.t("Shape it plate by plate")), "with the switch on, the bench is back")
	Armory.plate_bench_open = false
	_gone(pair)
	await _steps(2)

func test_forging_armour_at_the_smith_earns_the_armourers_deed() -> void:
	Save.set_value("coins", 900)
	Save.set_value("stage", 13)
	Save.set_value("armor_worn", [])
	Save.set_value("achievements", {})
	var pair := _menu()
	var menu: Control = pair[0]
	t.check(not Achievements.unlocked("armourer"), "not yet")
	menu._forge_armour(Armory.design_piece("torso", "iron", 0.3, 1.0, false, true, "Test plate"))
	await _steps(5)
	t.check(menu.worn_armor().size() == 1, "the piece is made and worn")
	t.check(Achievements.unlocked("armourer"), "and it counts as armour of his own design")
	_gone(pair)
	await _steps(2)

# ---------- How many more of a ware a bag takes, and why none ----------

func _nine_kinds_but(id: String) -> Dictionary:
	var full := {}
	for k in (Data.shop.throwables.keys() as Array).filter(func(i): return i != id).slice(0, Throwables.BAG_KINDS):
		full[k] = 1
	return full

func test_a_bag_says_how_many_more_fit_and_why_not() -> void:
	var c := StationKit.carry_of({}, "thunderPot")
	t.eq([c.have, c.max, c.more, c.why], [0, 3, 3, ""], "an empty bag takes three pots")
	c = StationKit.carry_of({"thunderPot": 2}, "thunderPot")
	t.eq([c.have, c.max, c.more, c.why], [2, 3, 1, ""], "with two, one more")
	c = StationKit.carry_of({"thunderPot": 3}, "thunderPot")
	t.eq([c.more, c.why], [0, "most"], "with three, the most of them")
	c = StationKit.carry_of({"anvil": 1}, "anvil")
	t.eq([c.max, c.more, c.why], [1, 0, "most"], "a heavy thing: one is the most")
	c = StationKit.carry_of({"bread": 4}, "bread")
	t.eq([c.max, c.more, c.why], [5, 1, ""], "a light thing: five")
	var full := _nine_kinds_but("bread")
	t.eq(full.size(), Throwables.BAG_KINDS, "a bag with every slot taken")
	c = StationKit.carry_of(full, "bread")
	t.eq([c.more, c.why], [0, "slots"], "a new kind has no slot left")
	var held := ""
	for k in full:
		if Throwables.stack_max(k) > 1 and held == "":
			held = k
	c = StationKit.carry_of(full, held)
	t.eq(c.why, "", "but one he carries already has room")
	t.eq(StationKit.carry_line(StationKit.carry_of({"thunderPot": 2}, "thunderPot")), Loc.t("Carrying %d of %d · room for %d more") % [2, 3, 1], "the sentence says how many he carries and how many more fit")
	t.eq(StationKit.carry_short(StationKit.carry_of({"thunderPot": 2}, "thunderPot")), "", "and nothing short is said while some fit")
	t.eq(StationKit.carry_short(StationKit.carry_of({"thunderPot": 3}, "thunderPot")), Loc.t("Most you can hold (%d)") % 3, "the short word for the most")
	t.eq(StationKit.carry_short(StationKit.carry_of(full, "bread")), Loc.t("All %d slots are taken") % Throwables.BAG_KINDS, "and for every slot taken")

func test_the_market_tells_how_many_more_of_a_ware_he_can_buy() -> void:
	Save.set_value("coins", 900)
	Save.set_value("stage", 13)
	Save.set_value("kit", {"thunderPot": 2})
	var pair := _menu()
	var menu: Control = pair[0]
	menu.market_tab = "fire"
	menu.market_sel = "thunderPot"
	menu.show_screen("market")
	await _steps(10)
	var ms: MarketScreen = _screen(menu, MarketScreen)
	t.check(_texts(ms.detail_card).has(Loc.t("Carrying %d of %d · room for %d more") % [2, 3, 1]), "two of three: room for one more, said under the writing")
	t.check(_texts(ms.grid_host).has("2/3"), "and the ware's tile says 2/3")
	t.check(ms.buy_btn != null and not ms.buy_btn.disabled and ms.buy_btn.text == Loc.t("Buy · %d denarii") % ms._cost("thunderPot"), "he can buy it")
	# The most of it.
	Save.set_value("kit", {"thunderPot": 3})
	menu.show_screen("market")
	await _steps(10)
	ms = _screen(menu, MarketScreen)
	t.check(_texts(ms.detail_card).has(Loc.t("Carrying %d of %d · the most you can hold") % [3, 3]), "three of three: the most he can hold")
	t.check(ms.buy_btn.disabled and ms.buy_btn.text == Loc.t("Most you can hold (%d)") % 3, "and the button says so, not that the bag is full")
	# Every slot taken by other things: the ware itself has none in the bag.
	Save.set_value("kit", _nine_kinds_but("thunderPot"))
	menu.show_screen("market")
	await _steps(10)
	ms = _screen(menu, MarketScreen)
	t.check(_texts(ms.detail_card).has(Loc.t("All %d slots are taken · nothing new fits") % Throwables.BAG_KINDS), "nine kinds in the bag: no slot for a new one")
	t.check(ms.buy_btn.disabled and ms.buy_btn.text == Loc.t("All %d slots are taken") % Throwables.BAG_KINDS, "said on the button")
	t.check(_texts(ms.grid_host).has("0/3"), "and his tile says 0/3")
	# The physician's supplies tell it the same way.
	Save.set_value("body", Body.empty())
	menu.show_screen("physician")
	await _steps(10)
	var said := _texts(menu.panel)
	t.check(said.has(Loc.t("All %d slots are taken · nothing new fits") % Throwables.BAG_KINDS), "the supplies say why a new kind does not fit")
	var buttons := []
	for b in menu.panel.find_children("*", "Button", true, false):
		buttons.append(String((b as Button).text))
	t.check(buttons.has(Loc.t("All %d slots are taken") % Throwables.BAG_KINDS), "and so does a button")
	_gone(pair)
	await _steps(2)
