extends Node
## What the HUD costs a frame (the diagnostic test's first report: the figure's columns counted over again every half second,
## 6 ms of one frame, and the figure drawn anew every frame): counted again only for a part that changed, drawn 20 times a second.

var t

func _hud() -> Array:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "duel", "headless": true, "seed": 4, "decrees": [], "hazards": []})
	var hud := Hud.new(m)
	add_child(hud)
	for i in 6:
		await get_tree().physics_frame
	await get_tree().process_frame
	return [m, hud]

func test_the_figures_columns_are_counted_again_only_for_a_part_that_changed() -> void:
	var mh: Array = await _hud()
	var m = mh[0]
	var hud = mh[1]
	var f = m.me.f
	t.check(hud.columns.has("torso") and hud.columns.has("head"), "the figure has its columns")
	var before: PackedFloat32Array = hud.columns["torso"].cells.duplicate()
	hud.columns["torso"]["mark"] = 1
	hud.columns["head"]["mark"] = 1
	hud._rebuild_columns(f)
	t.check(hud.columns["torso"].has("mark") and hud.columns["head"].has("mark"), "nothing changed: the columns are the ones held")
	# A voxel of the torso knocked off: its columns are counted again, the head's are not.
	var p = f.by_name["torso"]
	var gone := -1
	for i in p.alive.size():
		if p.alive[i] == 1:
			gone = i
			break
	t.check(gone >= 0, "the torso has a voxel to lose")
	p.alive[gone] = 0
	hud._rebuild_columns(f)
	t.check(not hud.columns["torso"].has("mark") and hud.columns["head"].has("mark"), "a voxel lost: the torso's columns are counted again, the head's are held")
	var after: PackedFloat32Array = hud.columns["torso"].cells
	var ci: int = p.fy[gone] * p.grid.x + p.fx[gone]
	t.check(after[ci] < before[ci], "and the column it was in is less full (%.2f of %.2f)" % [after[ci], before[ci]])
	# The same counts as a whole count gives (the held ones thrown away, every part counted anew).
	var held: Dictionary = hud.columns.duplicate(true)
	hud._col_sig.clear()
	hud._rebuild_columns(f)
	var same := true
	for k in held:
		same = same and hud.columns.has(k) and hud.columns[k].cells == held[k].cells and hud.columns[k].w == held[k].w and hud.columns[k].h == held[k].h
	t.check(same and hud.columns.size() == held.size(), "every part's columns are what a whole count gives")
	hud.queue_free()
	m.queue_free()

func test_the_figure_is_drawn_twenty_times_a_second() -> void:
	var mh: Array = await _hud()
	var m = mh[0]
	var hud = mh[1]
	var draws := [0]
	hud.fig.draw.connect(func(): draws[0] += 1)
	hud.knock = 0.0
	for i in 120:   # a second of frames at 120 a second (--fixed-fps)
		hud.knock = 0.0
		await get_tree().process_frame
	t.check(draws[0] >= 1 and draws[0] <= 70, "a hundred and twenty frames draw the figure %d times, not a hundred and twenty" % draws[0])
	# Knocked about it is drawn at once, every frame.
	draws[0] = 0
	for i in 12:
		hud.knock = 1.0
		await get_tree().process_frame
	t.check(draws[0] >= 10, "while he is knocked it is drawn every frame (%d of 12)" % draws[0])
	hud.queue_free()
	m.queue_free()
