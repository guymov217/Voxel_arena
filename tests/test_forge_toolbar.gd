extends Node
## The forge's toolbar after the clear-out (user: far too many buttons, it frightens players away; fewer, merged, friendlier): one row of the tools, one pull-down for both mirrors, Undo and
## Redo (dimmed while they have nothing to do), one "More" for what is asked for seldom, and a row under them only while the tool in hand has more to ask (the pick, the two hands).

var t

## A little axe: a grip of wood up the middle, a steel head of 3 x 2 x 1 on top with an edge on its right, and a pommel.
func _axe() -> Dictionary:
	var d := {"name": "Test axe", "kind": "weapon", "twoHanded": false, "sharpness": 0.8, "voxels": []}
	for y in range(0, 6):
		d.voxels.append([0, y, 0, "wood", "grip"])
	for x in range(-1, 2):
		for y in range(6, 8):
			d.voxels.append([x, y, 0, "steel", "blunt"])
	d.voxels.append([2, 6, 0, "steel", "edge", 0])
	d.voxels.append([2, 7, 0, "steel", "edge", 0])
	d.voxels.append([0, -1, 0, "iron", "blunt"])
	return d

func _forge(d: Dictionary, free := true):
	var f = load("res://scripts/ui/forge.gd").new()
	add_child(f)
	f.free_build = free
	f.open(d.duplicate(true), 9999, func(_d, _c): pass)
	f._show_mode("voxels")
	return f

func _find_button(n: Node, text: String) -> Button:
	if n is Button and (n as Button).text == text:
		return n
	for c in n.get_children():
		var r := _find_button(c, text)
		if r != null:
			return r
	return null

## Every control in the tool bar that takes a click.
func _controls(f) -> Array:
	return f.tool_bar.find_children("*", "BaseButton", true, false)

func _texts(f) -> Array:
	return _controls(f).map(func(b): return (b as Button).text)

func test_the_toolbar_is_one_row_of_few_buttons() -> void:
	var f = _forge(Data.preset("gladius"))
	await get_tree().process_frame
	var cs := _controls(f)
	t.check(cs.size() <= 9, "a click each for the five tools, the mirror, undo, redo and more: no more than 9 (%d: %s)" % [cs.size(), _texts(f)])
	t.eq(f.tool_bar.find_children("*", "CheckBox", true, false).size(), 0, "no tick boxes in it: the two mirrors are one pull-down")
	var texts := _texts(f)
	for gone in ["Turn sharp block (R)", "Select none", "Select all", "Flip ⟷", "Make them Steel"]:
		t.check(not texts.has(gone), "no %s in it while the tool in hand does not need it" % gone)
	t.eq(f.tool_bar.get_child(0).get_child_count(), 1, "one row, nothing under the tools")
	f.queue_free()
	await get_tree().process_frame

func test_with_the_select_tool_and_a_pick_it_is_still_a_short_list() -> void:
	var f = _forge(Data.preset("gladius"))
	f.tool = "select"
	f._sel_all()
	await get_tree().process_frame
	var cs := _controls(f)
	t.check(cs.size() <= 20, "the tools' nine and the pick's eleven (none, copy, six moves and three lists): no more than 20 (%d)" % cs.size())
	t.eq(f.tool_bar.get_child(0).get_child_count(), 2, "a row under the tools")
	f._set_sel({})
	await get_tree().process_frame
	t.eq(_controls(f).size(), 9 + 1, "with nothing picked the row has only the one button (%d)" % _controls(f).size())
	f.queue_free()
	await get_tree().process_frame

func test_both_mirrors_are_one_pull_down() -> void:
	var f = _forge(Data.preset("gladius"))
	await get_tree().process_frame
	var ob: OptionButton = f.tool_bar.find_children("*", "OptionButton", true, false)[0]
	t.eq(ob.item_count, 4, "off, left and right, front and back, both")
	t.eq(ob.selected, 1, "left and right alike to begin with (%d)" % ob.selected)
	f.mirror = true
	f.mirror_z = false
	ob.item_selected.emit(3)
	t.check(f.mirror and f.mirror_z, "the last line: both")
	ob.item_selected.emit(0)
	t.check(not f.mirror and not f.mirror_z, "the first: neither")
	ob.item_selected.emit(2)
	t.check(not f.mirror and f.mirror_z, "front and back only")
	# The keys still turn them one at a time, and the pull-down shows it.
	var m := InputEventKey.new()
	m.pressed = true
	m.physical_keycode = KEY_M
	m.keycode = KEY_M
	f._shortcut(m)
	await get_tree().process_frame
	ob = f.tool_bar.find_children("*", "OptionButton", true, false)[0]
	t.check(f.mirror and f.mirror_z and ob.selected == 3, "M turns the left-right mirror on: both now (%d)" % ob.selected)
	m.shift_pressed = true
	f._shortcut(m)
	await get_tree().process_frame
	ob = f.tool_bar.find_children("*", "OptionButton", true, false)[0]
	t.check(f.mirror and not f.mirror_z and ob.selected == 1, "Shift+M the front-back one off (%d)" % ob.selected)
	f.queue_free()
	await get_tree().process_frame

func test_more_holds_clear_and_surprise_me() -> void:
	var f = _forge(Data.preset("gladius"))
	await get_tree().process_frame
	var more := _find_button(f.tool_bar, "More ▾") as MenuButton
	t.check(more != null, "one button for what is asked for seldom")
	if more == null:
		f.queue_free()
		return
	var pm := more.get_popup()
	t.eq(pm.item_count, 2, "two lines")
	t.eq(pm.get_item_text(0), "Clear", "Clear")
	t.eq(pm.get_item_text(1), "Surprise me", "and Surprise me")
	t.check(f.cells.size() > 5, "a weapon on the anvil")
	pm.id_pressed.emit(0)
	await get_tree().process_frame
	t.check(f.cells.size() >= 1 and f.cells.values().all(func(c): return c[1] == "grip"), "Clear leaves the grip and nothing else (%d blocks)" % f.cells.size())
	t.check(not f.undo_stack.is_empty(), "and can be taken back")
	pm.id_pressed.emit(1)
	await get_tree().process_frame
	t.check(f.cells.size() > 3, "Surprise me puts a weapon on the anvil (%d blocks)" % f.cells.size())
	f.queue_free()
	await get_tree().process_frame

func test_where_there_is_no_surprise_clear_is_a_button_of_its_own() -> void:
	var f = _forge(Data.preset("gladius"), false)
	await get_tree().process_frame
	t.check(_find_button(f.tool_bar, "More ▾") == null, "no list for the one line")
	var clear := _find_button(f.tool_bar, "Clear")
	t.check(clear != null, "Clear, a button")
	if clear:
		clear.pressed.emit()
		t.check(f.cells.values().all(func(c): return c[1] == "grip"), "and it clears")
	f.queue_free()
	await get_tree().process_frame

func test_undo_and_redo_are_dimmed_while_there_is_nothing_for_them_to_do() -> void:
	var f = _forge(Data.preset("gladius"))
	await get_tree().process_frame
	t.check(f.undo_button.disabled and f.redo_button.disabled, "at the start neither can do anything")
	f.mirror = false
	f.mirror_z = false
	var top: Vector3i = f.cells.keys().reduce(func(a, b): return a if a.y > b.y else b)
	f._place([top + Vector3i(0, 1, 0)])
	t.check(not f.undo_button.disabled and f.redo_button.disabled, "a block put on: Undo can")
	f._undo()
	t.check(f.undo_button.disabled and not f.redo_button.disabled, "taken back: only Redo can")
	f._redo()
	t.check(not f.undo_button.disabled and f.redo_button.disabled, "put back: only Undo can")
	f.tool = "select"
	f._toolbar_ui()
	await get_tree().process_frame
	t.check(not f.undo_button.disabled and f.redo_button.disabled, "and the same after the tool bar is made again")
	f.queue_free()
	await get_tree().process_frame

func test_the_hands_buttons_come_with_the_hand_tool_of_a_two_handed_weapon() -> void:
	var f = _forge(Data.preset("gladius"))
	f.tool = "hand"
	f._toolbar_ui()
	await get_tree().process_frame
	t.check(not _texts(f).has("Main hand"), "a one-handed weapon has one hand: nothing to choose")
	f.queue_free()
	await get_tree().process_frame
	f = _forge(Data.preset("longsword"))
	t.check(bool(f.design.get("twoHanded", false)), "a longsword is two-handed")
	f._toolbar_ui()
	await get_tree().process_frame
	t.check(not _texts(f).has("Other hand"), "with the build tool in hand there are no hands' buttons")
	f.tool = "hand"
	f._toolbar_ui()
	await get_tree().process_frame
	var other := _find_button(f.tool_bar, "Other hand")
	t.check(other != null and _find_button(f.tool_bar, "Main hand") != null, "with the hand tool, a button for each hand")
	if other:
		other.pressed.emit()
		t.eq(f.hand_pick, "off", "the other hand is the one the next click moves")
		await get_tree().process_frame
		other = _find_button(f.tool_bar, "Other hand")
		t.check(other.button_pressed, "and its button shows it")
		other.pressed.emit()
		t.eq(f.hand_pick, "", "pressed again, the nearest ring is taken up again")
	f.queue_free()
	await get_tree().process_frame

func test_the_picks_lists_turn_flip_and_change_do_what_their_lines_say() -> void:
	var f = _forge(_axe())
	f.mirror = false
	f.mirror_z = false
	f.tool = "select"
	f._set_sel(ForgeLib.part_of(f.cells, Vector3i(0, 6, 0)))
	await get_tree().process_frame
	var turn := _find_button(f.tool_bar, "Turn ▾") as MenuButton
	var flip := _find_button(f.tool_bar, "Flip ▾") as MenuButton
	var change := _find_button(f.tool_bar, "Change ▾") as MenuButton
	t.check(turn != null and flip != null and change != null, "three lists")
	if turn == null or flip == null or change == null:
		f.queue_free()
		return
	t.eq(turn.get_popup().item_count, 3, "Turn: the three ways round")
	t.eq(flip.get_popup().item_count, 3, "Flip: the three ways over")
	t.eq(change.get_popup().item_count, 2, "Change: the stuff, and what it does")
	t.eq(change.get_popup().get_item_text(0), "Make them Steel", "the stuff picked on the left")
	var was: Dictionary = f.cells.duplicate(true)
	var picked: int = f.sel.size()
	turn.get_popup().id_pressed.emit(0)
	await get_tree().process_frame
	t.check(f.cells.hash() != was.hash() and f.sel.size() == picked, "a line of Turn turns the pick (%d blocks stay picked)" % f.sel.size())
	f._undo()
	await get_tree().process_frame
	flip = _find_button(f.tool_bar, "Flip ▾") as MenuButton
	flip.get_popup().id_pressed.emit(1)
	await get_tree().process_frame
	t.check(f.cells.hash() != was.hash(), "a line of Flip flips it")
	f._undo()
	await get_tree().process_frame
	f.mat = "gold"
	f._show_mode("voxels")
	await get_tree().process_frame
	change = _find_button(f.tool_bar, "Change ▾") as MenuButton
	t.eq(change.get_popup().get_item_text(0), "Make them Gold", "the line follows the stuff picked on the left")
	change.get_popup().id_pressed.emit(0)
	await get_tree().process_frame
	var all_gold := true
	for k in f.sel:
		all_gold = all_gold and f.cells[k][0] == "gold"
	t.check(all_gold, "and makes the pick gold")
	f.job = "blunt"
	f._show_mode("voxels")
	await get_tree().process_frame
	change = _find_button(f.tool_bar, "Change ▾") as MenuButton
	change.get_popup().id_pressed.emit(1)
	var all_crush := true
	for k in f.sel:
		all_crush = all_crush and f.cells[k][1] == "blunt"
	t.check(all_crush, "the other line gives the pick the job picked there")
	f.queue_free()
	await get_tree().process_frame
