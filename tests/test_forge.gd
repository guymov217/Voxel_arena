extends Node
## The workshop's logic (forge.js): stats from voxels match the web game's exported stats, the
## drawing helpers, auto-sharpen and auto-grip, the guided cards, "surprise me".

var t

func test_stats_match_the_web_game() -> void:
	var bad := []
	var n := 0
	for k in Data.presets:
		var d: Dictionary = Data.preset(k)
		var want: Dictionary = d.get("stats", {})
		if want.is_empty() or d.get("chain") != null:
			continue
		n += 1
		var got := ForgeLib.compute_stats(d)
		for f in ["mass", "reach", "swingSpeed", "cut", "pierce", "inertia"]:
			if absf(float(got[f]) - float(want[f])) > 1e-3 + absf(float(want[f])) * 1e-3:
				bad.append("%s %s %.4f vs %.4f" % [k, f, got[f], want[f]])
	t.check(n > 10, "checked %d presets" % n)
	t.check(bad.is_empty(), "stats as the web game computes them %s" % str(bad.slice(0, 4)))

func test_drawing_sharpening_and_grip() -> void:
	t.eq(ForgeLib.line_cells(Vector3i(0, 0, 0), Vector3i(0, 4, 0)).size(), 5, "a line of five")
	t.eq(ForgeLib.box_cells(Vector3i(0, 0, 0), Vector3i(1, 2, 0)).size(), 6, "a box of six")
	var d := ForgeLib.empty_design("t")
	ForgeLib.box(d, 0, 0, 0, 4, 0, 0, "wood", "blunt")
	ForgeLib.box(d, -1, 1, 5, 15, 0, 0, "steel", "blunt")
	ForgeLib.box(d, 0, 0, 16, 17, 0, 0, "steel", "blunt")
	t.check(ForgeLib.auto_sharpen(d) > 0, "auto-sharpen finds edges")
	t.check(d.voxels.any(func(v): return v[4] == "edge") and d.voxels.any(func(v): return v[4] == "point"), "an edge along the sides and a point at the tip")
	t.eq(ForgeLib.auto_grip(d), 5, "a five-voxel handle on the wood")
	t.check(ForgeLib.compute_stats(d).hasGrip, "now it can be held")

func test_cards_build_real_weapons() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4
	for b in ForgeLib.BASES:
		var deal := ForgeLib.deal_modifiers(b, rng)
		t.check(deal.size() >= 3 and deal.all(func(k): return ForgeLib.mod_fits(k, b)), "%s: cards that fit it (%s)" % [b, str(deal)])
		var d := ForgeLib.build_from_cards(b, deal.slice(0, 2), rng)
		var st := ForgeLib.compute_stats(d)
		t.check(st.hasGrip and d.voxels.size() > 4, "%s with %s is a weapon you can hold (%s, %d voxels)" % [b, str(deal.slice(0, 2)), d.name, d.voxels.size()])
	var s := ForgeLib.surprise_weapon(rng)
	t.check(ForgeLib.compute_stats(s).hasGrip and s.name != "", "surprise: " + s.name)
	t.check(ForgeLib.blacksmith_says(s) != "", "and the smith has an opinion")

func test_a_dragged_stroke_builds_many_voxels_with_one_undo() -> void:
	var f = load("res://scripts/ui/forge.gd").new()
	add_child(f)
	f.open(Data.preset("gladius"), 9999, func(_d, _c): pass)
	f.mode = "voxels"
	f.mirror = false
	f.mirror_z = false
	var keys: Array = f.cells.keys().filter(func(c): return not f.cells.has(c + Vector3i(0, 0, 1)))
	keys.sort_custom(func(a, b): return a.y < b.y)
	f.tool = "build"
	f.mat = "gold"
	var undo0: int = f.undo_stack.size()
	f.stroke = {"erase": false, "done": {}, "undo": false}
	for c in keys.slice(0, 12):
		f._apply({"hit": c, "place": c + Vector3i(0, 0, 1)})
		f._apply({"hit": c, "place": c + Vector3i(0, 0, 1)})   # the mouse lingers on a cell
	f.stroke = {}
	var gold := 0
	for c in keys.slice(0, 12):
		if f.cells.get(c + Vector3i(0, 0, 1), ["", ""])[0] == "gold":
			gold += 1
	t.check(gold >= 10, "the stroke built on the faces it passed over (%d)" % gold)
	t.eq(f.undo_stack.size() - undo0, 1, "one undo takes the whole stroke back")
	t.check(not ["paint", "box"].any(func(k): return f.TOOLS.any(func(td): return td[0] == k)), "no Paint, no Box: Build does it")
	# Built in a stroke, a cell is not built on again (no tower toward the eye).
	f.tool = "build"
	var n0: int = f.cells.size()
	var base: Vector3i = keys[0]
	f.stroke = {"erase": false, "done": {}, "undo": false}
	f._apply({"hit": base, "place": base + Vector3i(0, 0, 1)})
	f._apply({"hit": base + Vector3i(0, 0, 1), "place": base + Vector3i(0, 0, 2)})
	f.stroke = {}
	t.check(f.cells.size() - n0 <= 2, "a build stroke does not stack on itself (%d added)" % (f.cells.size() - n0))
	f.queue_free()

## The kinds of weapon are told apart, a blunt one is not honed, and the smith makes any weapon
## into any other: a hammer into a blade, for what the blade is worth over the hammer.
func test_reshaping_into_another_kind_costs_the_difference() -> void:
	var want := {"gladius": "blade", "longsword": "blade", "zweihander": "blade", "dagger": "blade", "axe": "axe", "executionerAxe": "axe",
		"spear": "spear", "javelin": "spear", "trident": "spear", "mace": "blunt", "warhammer": "blunt", "hammer": "blunt",
		"roundShield": "shield", "scutum": "shield", "bow": "bow", "crossbow": "crossbow", "flail": "chain"}
	for k in want:
		t.eq(Arms.family(Data.preset(k)), want[k], k)
	var rng := RandomNumberGenerator.new()
	for b in Arms.BASE_FAMILY:
		for mods in [[], ["longer"], ["shorter"], ["heavyHead"], ["longHandle"]]:
			if mods.all(func(m): return ForgeLib.mod_fits(m, b)):
				rng.seed = 3
				var d := ForgeLib.build_from_cards(b, mods, rng)
				t.eq(Arms.family(d), Arms.BASE_FAMILY[b], "%s %s" % [b, str(mods)])
	t.check(not Arms.can_upgrade("whetstone", Data.preset("mace")) and not Arms.can_upgrade("whetstone", Data.preset("warhammer")), "no honing a mace or a hammer")
	t.check(Arms.can_upgrade("whetstone", Data.preset("gladius")), "a sword is honed")
	var f = load("res://scripts/ui/forge.gd").new()
	add_child(f)
	f.open(Data.preset("warhammer"), 5000, func(_d, _c): pass)
	t.eq(f.job, "blunt", "a hammer starts with the blunt job in hand")
	var bases := []
	for c in f.find_children("*", "Button", true, false):
		for k in ForgeLib.BASES:
			if c.text == ForgeLib.BASES[k].label:
				bases.append(k)
	f._show_mode("cards")
	for c in f.find_children("*", "Button", true, false):
		for k in ForgeLib.BASES:
			if c.text == ForgeLib.BASES[k].label and not bases.has(k):
				bases.append(k)
	t.check(bases.has("gladius"), "a sword base for a hammer too (%s)" % str(bases))
	# Paint an edge on it: the smith hands it over as a blade, for the difference.
	var taken := []
	f.done = func(d, c): taken.append([d, c])
	for k in f.cells.keys():
		f.cells[k] = ["steel", "edge"] if k.y > 0 else ["wood", "grip"]
	f._take()
	t.eq(taken.size(), 1, "a hammer made into a blade is taken")
	if taken.size() == 1:
		t.check(int(taken[0][1]) == f._value_now() - f.original_value, "charged what it is worth over the hammer (%d)" % int(taken[0][1]))
	f.queue_free()

## A design saved goes into My designs and loads back onto the anvil.
func test_a_saved_design_loads_back() -> void:
	var keep = Save.get_value("forge_gallery", [])
	Save.set_value("forge_gallery", [])
	var f = load("res://scripts/ui/forge.gd").new()
	add_child(f)
	f.free_build = true
	f.open(Data.preset("axe"), 0, func(_d, _c): pass)
	f.name_edit.text = "My Axe"
	f._save_design()
	var g: Array = f.gallery()
	t.eq(g.size(), 1, "one design saved")
	t.eq(str(g[0].name), "My Axe", "under its name")
	f._load_cells(Data.preset("gladius"))
	f._load_design(g[0])
	t.eq(f.cells.size(), Data.preset("axe").voxels.size(), "the saved axe is back on the anvil")
	f.queue_free()
	var r = load("res://scripts/ui/forge.gd").new()
	add_child(r)
	r.open(Data.preset("warhammer"), 0, func(_d, _c): pass)
	r._show_mode("gallery")
	var load_btn = null
	for c in r.find_children("*", "Button", true, false):
		if c.text == "Load":
			load_btn = c
	t.check(load_btn != null and not load_btn.disabled, "an axe design loads onto a hammer at the smith too (paid for the difference)")
	r.queue_free()
	Save.set_value("forge_gallery", keep)

## Nothing is set in the air: a new block must touch the weapon (a line or a box only where it
## does), and a cut through the weapon drops the piece without the grip.
func test_no_block_hangs_in_the_air() -> void:
	var f = load("res://scripts/ui/forge.gd").new()
	add_child(f)
	f.free_build = true
	f.mirror = false
	f.open(Data.preset("gladius"), 0, func(_d, _c): pass)
	var n0: int = f.cells.size()
	var top := Vector3i(0, -99, 0)
	for c in f.cells:
		if c.y > top.y:
			top = c
	f._place([top + Vector3i(0, 5, 0)])
	t.eq(f.cells.size(), n0, "a block in the air is refused")
	# A line from the tip out into the air goes on whole: each block holds on to the one before.
	f._place(ForgeLib.line_cells(top + Vector3i(0, 1, 0), top + Vector3i(0, 4, 0)))
	t.eq(f.cells.size(), n0 + 4, "a line grown from the tip goes on")
	# A line that starts in the air and never touches it: nothing.
	f._place(ForgeLib.line_cells(top + Vector3i(6, 0, 0), top + Vector3i(8, 0, 0)))
	t.eq(f.cells.size(), n0 + 4, "a line out in the air is refused")
	# Cut through the blade near the guard: the blade above falls away, the grip stays.
	var lo_y := 99
	var hi_y := -99
	for c in f.cells:
		lo_y = mini(lo_y, c.y)
		hi_y = maxi(hi_y, c.y)
	var cut_y := (lo_y + hi_y) / 2
	var row := []
	for c in f.cells:
		if c.y == cut_y:
			row.append(c)
	f._remove(row)
	t.check(f.cells.keys().all(func(c): return c.y < cut_y), "what was above the cut fell off")
	t.check(f.cells.values().any(func(v): return v[1] == "grip"), "the grip stays on the anvil")
	t.eq(ForgeLib.pieces(f.cells).size(), 1, "one piece")
	f.queue_free()

## A blank anvil: one block of grip, and a weapon built up from it block by block; at the smith
## every block put on is paid for. The stock is the short list, each stuff for its own job.
func test_a_weapon_from_a_blank_anvil() -> void:
	t.check(not ForgeLib.SIMPLE_MATERIALS.has("fish") and not load("res://scripts/ui/forge.gd").MATS.has("bronze"), "the stock is the short list")
	t.check(load("res://scripts/ui/forge.gd").MATS.has("ruby") and load("res://scripts/ui/forge.gd").MATS.has("lead"), "gems and lead kept")
	var f = load("res://scripts/ui/forge.gd").new()
	add_child(f)
	f.open(Data.preset("gladius"), 1000, func(_d, _c): pass)
	f._blank()
	t.eq(f.cells.size(), 1, "one block on the anvil")
	t.eq(String(f.cells.values()[0][1]), "grip", "and it is the grip")
	f.mirror = false
	f.mat = "wood"
	f.job = "grip"
	f._place(ForgeLib.line_cells(Vector3i(0, 1, 0), Vector3i(0, 4, 0)))
	f.mat = "steel"
	f.job = "edge"
	f._place(ForgeLib.line_cells(Vector3i(0, 5, 0), Vector3i(0, 20, 0)))
	f._place([Vector3i(-1, 10, 0), Vector3i(1, 10, 0)])
	t.check(f.cells.size() >= 21, "built up from it (%d blocks)" % f.cells.size())
	t.check(f._value_now() > 0, "and at the smith it costs (%d)" % f._value_now())
	var got := []
	f.done = func(d, c): got.append([d, c])
	f._take()
	t.check(not got.is_empty() and Arms.family(got[0][0]) == "blade", "a blade made from nothing is still a blade (%s)" % [Arms.family(got[0][0]) if not got.is_empty() else "refused"])
	f.queue_free()

## Mirror works across both planes (left-right, front-back); a held right button takes blocks
## off one at a time, not the whole weapon in a sweep; the blank anvil is for building from
## nothing, not for reshaping a weapon at the smith.
func test_mirror_both_ways_slow_erase_and_blank_only_from_scratch() -> void:
	var f = load("res://scripts/ui/forge.gd").new()
	add_child(f)
	f.free_build = true
	f.open(Data.preset("gladius"), 0, func(_d, _c): pass)
	f.mirror = true
	f.mirror_z = true
	t.eq(f._mirrored([Vector3i(2, 5, 1)]).size(), 4, "both planes: four alike")
	f.mirror_z = false
	t.eq(f._mirrored([Vector3i(2, 5, 1)]).size(), 2, "left-right only: two")
	f.stroke = {"erase": true, "done": {}, "undo": false}
	var first: bool = f._erase_ready()
	var second: bool = f._erase_ready()
	t.check(first and not second, "a held button waits between blocks")
	f.stroke = {}
	f.queue_free()
	var has_blank := func(fg) -> bool:
		return fg.find_children("*", "Button", true, false).any(func(b): return b.text.begins_with("Blank anvil"))
	var r = load("res://scripts/ui/forge.gd").new()
	add_child(r)
	r.open(Data.preset("gladius"), 500, func(_d, _c): pass)
	r._show_mode("cards")
	t.check(not has_blank.call(r), "reshaping at the smith: no blank anvil")
	r.queue_free()
	var sc = load("res://scripts/ui/forge.gd").new()
	add_child(sc)
	sc.scratch = true
	sc.open({"name": "New weapon", "voxels": [[0, 0, 0, "wood", "grip"]]}, 500, func(_d, _c): pass)
	sc._show_mode("cards")
	t.check(has_blank.call(sc), "from nothing: any kind, blank anvil there")
	sc.queue_free()

## Move hand: the builder drags the hand onto any block (both hands on a two-handed weapon,
## each from its own ring), and the fighter holds it there.
func test_the_builder_picks_where_the_hand_holds() -> void:
	var f = load("res://scripts/ui/forge.gd").new()
	add_child(f)
	f.open(Data.preset("gladius"), 1000, func(_d, _c): pass)
	var grip: Array = f.cells.keys().filter(func(k): return f.cells[k][1] == "grip")
	grip.sort_custom(func(a, b): return a.y < b.y)
	var low: Vector3i = grip[0]
	f._set_hand(low)
	var g = ForgeLib.grip_points(f._design_now())
	t.check(g != null and g.main.distance_to(Vector3(low)) < 0.01, "the hand where it was put (%s)" % [g.main if g else null])
	var w := Weapon.new()
	w.setup(f._design_now())
	t.check(w.grip_main.distance_to(Vector3(low) * Data.weapon_voxel) < 1e-4, "and the fighter holds it there")
	w.free()
	var blade = f.cells.keys().filter(func(k): return f.cells[k][1] != "grip")[0]
	f._set_hand(blade)
	t.check(ForgeLib.grip_points(f._design_now()).main.distance_to(Vector3(blade)) < 0.01, "any block will do: the hand goes onto the blade")
	f._set_hand(Vector3i(40, 40, 0))
	t.check(ForgeLib.grip_points(f._design_now()).main.distance_to(Vector3(blade)) < 0.01, "but not into thin air")
	# Dragged: pressed on the ring, the hand follows the mouse from block to block.
	f.tool = "hand"
	f.stroke = {"erase": false, "done": {}, "undo": false}
	for c in grip:
		f._apply({"hit": c, "place": c})
	f.stroke = {}
	t.check(ForgeLib.grip_points(f._design_now()).main.distance_to(Vector3(grip[grip.size() - 1])) < 0.01, "dragged along the grip, it ends where the mouse let go")
	f.design.twoHanded = true
	var high: Vector3i = grip[grip.size() - 1]
	f._set_hand(high, "main")
	f._set_hand(low, "off")
	g = ForgeLib.grip_points(f._design_now())
	t.check(g.main.distance_to(Vector3(high)) < 0.01 and g.off.distance_to(Vector3(low)) < 0.01, "two-handed: each hand where it was put")
	t.eq(f._nearest_hand(low + Vector3i(0, 1, 0)), "off", "pressed nearer the bronze ring, the other hand is taken up")
	f.queue_free()

## The hands said plainly: "Held in" One hand / Two hands, and a button for each hand puts it
## on the next block clicked (no hunting for the ring), its ring marked MAIN or OTHER.
func test_each_hand_has_its_own_button() -> void:
	var f = load("res://scripts/ui/forge.gd").new()
	add_child(f)
	f.open(Data.preset("longsword"), 1000, func(_d, _c): pass)
	f._show_mode("voxels")
	await get_tree().process_frame
	var texts := func() -> Array:
		var out := []
		var stack: Array = [f]
		while stack.size():
			var n: Node = stack.pop_back()
			if n is Button:
				out.append((n as Button).text)
			stack.append_array(n.get_children())
		return out
	var tx: Array = texts.call()
	t.check(tx.has("One hand") and tx.has("Two hands"), "held in one hand or two, said plainly")
	t.check(tx.has("✋ Main hand") and tx.has("✋ Other hand"), "a button for each hand of a two-handed weapon")
	var grip: Array = f.cells.keys().filter(func(k): return f.cells[k][1] == "grip")
	grip.sort_custom(func(a, b): return a.y < b.y)
	f.tool = "hand"
	f.hand_pick = "off"
	f.stroke = {"erase": false, "done": {}, "undo": false}
	f._apply({"hit": grip[0], "place": grip[0]})
	f.stroke = {}
	var g = ForgeLib.grip_points(f._design_now())
	t.check(g.off.distance_to(Vector3(grip[0])) < 0.01, "the other hand's button and a click: that hand goes there, wherever its ring was")
	f.hand_pick = "off"
	f.stroke = {"erase": false, "done": {}, "undo": false}
	f._apply({"hit": Vector3i(g.main), "place": Vector3i(g.main)})
	f.stroke = {}
	t.check(ForgeLib.grip_points(f._design_now()).off.distance_to(Vector3(grip[0])) < 0.01, "but not right against the main hand: two fists need room")
	var tags := []
	for c in f.weapon_root.get_children():
		if c is Label3D:
			tags.append((c as Label3D).text)
	t.check(tags.has("MAIN") and tags.has("OTHER"), "the rings are marked (%s)" % [tags])
	f.queue_free()

## Whatever the forge makes by itself (Something silly, any base card with any modifier cards,
## Surprise me) comes out in one piece: no voxel hangs in the air apart from the weapon.
func test_nothing_the_forge_makes_hangs_in_the_air() -> void:
	var cells_of := func(d: Dictionary) -> Dictionary:
		var c := {}
		for v in d.voxels:
			c[Vector3i(int(v[0]), int(v[1]), int(v[2]))] = [v[3], v[4]]
		return c
	var bad := []
	var made := 0
	var mods: Array = ForgeLib.MODIFIERS.keys()
	for seed in 400:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed
		var base: String = "silly" if seed % 2 == 0 else ForgeLib.BASES.keys()[seed % ForgeLib.BASES.size()]
		var picks := []
		for k in rng.randi_range(0, ForgeLib.MAX_PICKS):
			picks.append(mods[rng.randi_range(0, mods.size() - 1)])
		for d in [ForgeLib.build_from_cards(base, picks, rng), ForgeLib.surprise_weapon(rng)]:
			made += 1
			var n: int = ForgeLib.pieces(cells_of.call(d)).size()
			if n != 1 and bad.size() < 5:
				bad.append("%s %s: %d pieces" % [base, picks, n])
	t.check(bad.is_empty(), "%d weapons, every one in one piece %s" % [made, bad])

## The ready-made weapons too: every one is in one piece (loose bits are joined on, not lost).
func test_every_ready_made_weapon_is_one_piece() -> void:
	var bad := []
	for k in Data.presets:
		var d: Dictionary = Data.preset(k)
		if d.has("chain"):
			continue
		var c := {}
		for v in d.get("voxels", []):
			c[Vector3i(int(v[0]), int(v[1]), int(v[2]))] = [v[3], v[4]]
		if ForgeLib.pieces(c).size() > 1:
			bad.append(k)
	t.check(bad.is_empty(), "no ready-made weapon has a piece in the air %s" % [bad])
	var loose := {"voxels": [[0, 0, 0, "wood", "grip"], [0, 1, 0, "wood", "blunt"], [3, 1, 0, "gold", "blunt"]]}
	t.eq(ForgeLib.bridge(loose), 2, "a loose voxel three cells off is joined by two")
	t.eq(loose.voxels.size(), 5, "and nothing is taken away")

## The line goes any way, from block to block, every cell joined face to face (no corner
## hanging), and its path shows while the end is picked.
func test_a_line_any_way_with_its_path_shown() -> void:
	var path := ForgeLib.line_path(Vector3i(0, 0, 0), Vector3i(4, 6, 0))
	t.eq(path[0], Vector3i(0, 0, 0), "from the start")
	t.eq(path[path.size() - 1], Vector3i(4, 6, 0), "to the end")
	var joined := true
	for i in range(1, path.size()):
		var d: Vector3i = path[i] - path[i - 1]
		if absi(d.x) + absi(d.y) + absi(d.z) != 1:
			joined = false
	t.check(joined, "slanting, still face to face all the way (%d cells)" % path.size())
	var f = load("res://scripts/ui/forge.gd").new()
	add_child(f)
	f.open(Data.preset("gladius"), 9999, func(_d, _c): pass)
	f._show_mode("voxels")
	f.mirror = false
	f.tool = "line"
	var top: Vector3i = f.cells.keys().reduce(func(a, b): return a if a.y > b.y else b)
	var n0: int = f.cells.size()
	f._apply({"hit": top, "place": top + Vector3i(0, 1, 0)})
	t.check(f.line_from != null and f.line_ghost.multimesh.instance_count >= 1, "the start is shown")
	f._show_line(f._mirrored(ForgeLib.line_path(f.line_from, top + Vector3i(5, 5, 0))))
	t.check(f.line_ghost.multimesh.instance_count >= 10, "and the path to where the mouse is")
	f._apply({"hit": null, "place": top + Vector3i(5, 5, 0)})
	t.check(f.cells.size() - n0 >= 10 and f.line_ghost.multimesh.instance_count == 0, "the slanting line is built (%d blocks)" % (f.cells.size() - n0))
	f.queue_free()

## At the smith, from nothing: a saved design can be bought straight from My designs.
func test_buy_a_saved_design_at_the_smith() -> void:
	var keep = Save.get_value("forge_gallery", [])
	var d: Dictionary = Data.preset("axe").duplicate(true)
	d.name = "My axe"
	Save.set_value("forge_gallery", [d])
	var f = load("res://scripts/ui/forge.gd").new()
	add_child(f)
	f.scratch = true
	var got := []
	f.open({"name": "New", "kind": "weapon", "voxels": [[0, 0, 0, "wood", "grip"]]}, 9999, func(dd, _c): got.append(dd))
	f._show_mode("gallery")
	var buy = _find_button(f, "Buy · %d" % Arms.design_price(d))
	t.check(buy != null, "a Buy button with its price on the saved design")
	if buy:
		buy.pressed.emit()
	t.check(not got.is_empty() and str(got[0].get("name", "")) == "My axe", "bought as it was designed")
	f.queue_free()
	Save.set_value("forge_gallery", keep)

func _find_button(n: Node, text: String) -> Button:
	if n is Button and (n as Button).text == text:
		return n
	for c in n.get_children():
		var b := _find_button(c, text)
		if b:
			return b
	return null

## A weapon too heavy to lift is not let out of the forge (it lay on the sand, the hand dragged
## after it); the smith's oddities never come out that heavy; a weapon pushed through the sand
## comes back up on it rather than being lost.
func test_nothing_too_heavy_to_lift() -> void:
	var heavy := {"name": "Anvil on a stick", "voxels": [[0, 0, 0, "wood", "grip"], [0, 1, 0, "wood", "grip"]]}
	ForgeLib.box(heavy, -3, 3, 2, 8, -2, 2, "lead", "blunt")
	t.check(ForgeLib.too_heavy(heavy) != "", "a lead block of %.0f kg is too heavy" % ForgeLib.compute_stats(heavy).mass)
	t.eq(ForgeLib.too_heavy(Data.preset("warhammer")), "", "a warhammer is not")
	var f = load("res://scripts/ui/forge.gd").new()
	add_child(f)
	var got := []
	f.free_build = true
	f.open(heavy, 99999, func(d, _c): got.append(d))
	f._take()
	t.check(got.is_empty() and f.cost_label.text.begins_with("Too heavy"), "the forge will not let it out: %s" % f.cost_label.text)
	f.queue_free()
	for s in 6:
		for d in Arms.oddities(s * 13 + 1, 1 + s * 3):
			t.eq(ForgeLib.too_heavy(d), "", "oddity %s can be lifted" % d.name)
	var w := Weapon.new()
	w.setup(Data.preset("gladius"))
	add_child(w)
	w.global_position = Vector3(0, -5, 0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	t.check(w.global_position.y > 0.0, "a weapon through the sand is back on top (y %.2f)" % w.global_position.y)
	w.queue_free()

## Whatever its size, the whole weapon is in the forge's view: framed when it is put on the
## anvil, and the camera backs off as it is built bigger.
func test_the_whole_weapon_is_always_in_view() -> void:
	var pole := {"name": "Long pole", "voxels": []}
	for y in 86:
		pole.voxels.append([0, y, 0, "wood", "grip" if y < 8 else "blunt"])
	for d in [Data.preset("dagger"), Data.preset("zweihander"), pole]:
		var f = load("res://scripts/ui/forge.gd").new()
		add_child(f)
		f.free_build = true
		f.open(d.duplicate(true), 99999, func(_d, _c): pass)
		await get_tree().process_frame
		await get_tree().process_frame
		t.check(_all_in_view(f), "%s: all of it in view (camera %.2f m off)" % [d.name, f.dist])
		if d == pole:
			f.queue_free()
			continue
		# Built out to three metres long: the camera stays where the builder put it (it no longer
		# backs off at every block), and F frames the whole of it again.
		var dist0: float = f.dist
		var add := []
		for y in range(-14, 80):
			add.append(Vector3i(0, y, 0))
		for c in add:
			if not f.cells.has(c):
				f.cells[c] = ["wood", "blunt"]
		f._rebuild()
		await get_tree().process_frame
		t.check(is_equal_approx(f.dist, dist0), "%s built out long: the camera stayed put (%.2f m, was %.2f)" % [d.name, f.dist, dist0])
		f._frame()
		# (Two frames: the camera's frustum is brought up to date a frame late when another
		# view was taken down in the one before.)
		await get_tree().process_frame
		await get_tree().process_frame
		t.check(_all_in_view(f), "%s built out long: F brings all of it into view (camera %.2f m off)" % [d.name, f.dist])
		f.queue_free()

func _all_in_view(f) -> bool:
	var vs: float = Data.weapon_voxel
	for k in f.cells:
		var p: Vector3 = f.weapon_root.global_transform * (Vector3(k) * vs)
		if not f.cam.is_position_in_frustum(p):
			return false
	return true

func test_the_walking_keys_move_the_forge_camera() -> void:
	# The keys as bound in Controls (a fight sets them up; here, by hand).
	var pi_ = PlayerInput.new()
	add_child(pi_)
	var f = load("res://scripts/ui/forge.gd").new()
	add_child(f)
	f.free_build = true
	f.open(Data.preset("gladius").duplicate(true), 99999, func(_d, _c): pass)
	await get_tree().process_frame
	var d0: float = f.dist
	Input.action_press("va_forward")
	for i in 20:
		await get_tree().process_frame
	Input.action_release("va_forward")
	t.check(f.dist < d0 - 0.05, "W draws the camera in (%.2f → %.2f m)" % [d0, f.dist])
	var f0: Vector3 = f.focus
	var right: Vector3 = f.cam.global_transform.basis.x
	Input.action_press("va_right")
	for i in 20:
		await get_tree().process_frame
	Input.action_release("va_right")
	t.check((f.focus - f0).dot(right) > 0.02, "D slides it to the right")
	var y0: float = f.cam.global_position.y
	Input.action_press("va_jump")
	for i in 20:
		await get_tree().process_frame
	Input.action_release("va_jump")
	t.check(f.cam.global_position.y > y0 + 0.02, "Space lifts it")
	# Typing a name moves nothing.
	f.name_edit.grab_focus()
	var d1: float = f.dist
	Input.action_press("va_forward")
	for i in 10:
		await get_tree().process_frame
	Input.action_release("va_forward")
	t.check(is_equal_approx(f.dist, d1), "not while the name is being typed")
	f.queue_free()
	pi_.queue_free()
