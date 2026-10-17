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

func test_a_dragged_stroke_paints_many_voxels_with_one_undo() -> void:
	var f = load("res://scripts/ui/forge.gd").new()
	add_child(f)
	f.open(Data.preset("gladius"), 9999, func(_d, _c): pass)
	f.mode = "voxels"
	var keys: Array = f.cells.keys()
	keys.sort_custom(func(a, b): return a.y < b.y)
	f.tool = "paint"
	f.mat = "gold"
	var undo0: int = f.undo_stack.size()
	f.stroke = {"erase": false, "done": {}, "undo": false}
	for c in keys.slice(0, 12):
		f._apply({"hit": c, "place": c + Vector3i(0, 0, 1)})
		f._apply({"hit": c, "place": c + Vector3i(0, 0, 1)})   # the mouse lingers on a cell
	f.stroke = {}
	var gold := 0
	for c in keys.slice(0, 12):
		if f.cells[c][0] == "gold":
			gold += 1
	t.check(gold >= 10, "the stroke painted the voxels it passed over (%d)" % gold)
	t.eq(f.undo_stack.size() - undo0, 1, "one undo takes the whole stroke back")
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

## The smith reshapes a weapon within its kind: a hammer stays a hammer, and a blunt one is not honed.
func test_reshaping_keeps_the_kind_of_weapon() -> void:
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
	t.eq(f.family, "blunt", "the warhammer on the anvil")
	t.eq(f.job, "blunt", "nothing to put an edge on")
	var bases := []
	for c in f.find_children("*", "Button", true, false):
		for k in ForgeLib.BASES:
			if c.text == ForgeLib.BASES[k].label:
				bases.append(k)
	t.check(not bases.has("gladius") and not bases.has("silly"), "no sword base for a hammer (%s)" % str(bases))
	# Paint an edge on it: the smith will not hand it over as a blade.
	var taken := []
	f.done = func(d, _c): taken.append(d)
	for k in f.cells.keys():
		f.cells[k] = ["steel", "edge"]
	f._take()
	t.eq(taken.size(), 0, "a hammer made into a blade is refused")
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
	t.check(load_btn != null and load_btn.disabled, "an axe design cannot be loaded onto a hammer at the smith")
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
	t.check(has_blank.call(sc) and sc.family == "", "from nothing: any kind, blank anvil there")
	sc.queue_free()

## The Hand tool: the builder says where the hand holds the grip (both hands on a two-handed
## weapon), the fighter holds it there, and a click off the grip moves no hand.
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
	t.check(ForgeLib.grip_points(f._design_now()).main.distance_to(Vector3(low)) < 0.01, "a click on the blade moves no hand")
	f.design.twoHanded = true
	var high: Vector3i = grip[grip.size() - 1]
	f._set_hand(high)
	f._set_hand(low)
	g = ForgeLib.grip_points(f._design_now())
	t.check(g.main.distance_to(Vector3(high)) < 0.01 and g.off.distance_to(Vector3(low)) < 0.01, "two-handed: one hand, then the other")
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
