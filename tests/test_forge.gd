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
