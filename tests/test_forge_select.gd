extends Node
## The forge's Select tool (user: select a region, then move, copy, rotate, flip it or remake it of another stuff): the pure part (ForgeLib: boxes, parts, quarter turns, flips, carrying blocks
## with the way sharp ones face, remaking) and the forge's own (the pick, its buttons and keys, one undo a step, nothing that tears the weapon in two, the hands going with the blocks they hold).

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

func _cells_of(d: Dictionary) -> Dictionary:
	var c := {}
	for v in d.voxels:
		c[Vector3i(v[0], v[1], v[2])] = [v[3], v[4], ForgeLib.face_of(v)]
	return c

func _forge(d: Dictionary, coins := 9999):
	var f = load("res://scripts/ui/forge.gd").new()
	add_child(f)
	f.free_build = true
	f.open(d.duplicate(true), coins, func(_d, _c): pass)
	f._show_mode("voxels")
	f.mirror = false
	f.mirror_z = false
	f.tool = "select"
	f._toolbar_ui()
	return f

# ---------- the pure part ----------

func test_a_box_takes_the_blocks_of_the_weapon_inside_it_whatever_the_corners() -> void:
	var cells := _cells_of(_axe())
	var box := ForgeLib.blocks_in_box(cells, Vector3i(2, 7, 0), Vector3i(-1, 6, 0))
	t.eq(box.size(), 8, "the head and its edge, the corners given in any order (%d)" % box.size())
	t.check(box.has(Vector3i(2, 6, 0)) and box.has(Vector3i(-1, 7, 0)), "both corners' blocks are in")
	t.check(not box.has(Vector3i(0, 5, 0)), "a block under the box is not")
	t.eq(ForgeLib.blocks_in_box(cells, Vector3i(5, 5, 5), Vector3i(9, 9, 9)).size(), 0, "a box in empty air takes nothing")

func test_a_double_click_takes_the_part_of_one_stuff_joined_together() -> void:
	var cells := _cells_of(_axe())
	var head := ForgeLib.part_of(cells, Vector3i(0, 6, 0))
	t.eq(head.size(), 6, "the steel head's blunt blocks: 3 x 2 (%d)" % head.size())
	t.check(not head.has(Vector3i(2, 6, 0)), "its edge is another job, so another part")
	var grip := ForgeLib.part_of(cells, Vector3i(0, 3, 0))
	t.eq(grip.size(), 6, "the grip is a part of its own (%d)" % grip.size())
	t.eq(ForgeLib.part_of(cells, Vector3i(9, 9, 9)).size(), 0, "nothing where there is no block")
	# Two blocks of one stuff that only meet at a corner are two parts.
	var two := {Vector3i(0, 0, 0): ["steel", "blunt", -1], Vector3i(1, 1, 0): ["steel", "blunt", -1]}
	t.eq(ForgeLib.part_of(two, Vector3i(0, 0, 0)).size(), 1, "joined face to face only, not by a corner")

func test_a_shift_carries_the_pick_and_leaves_nothing_behind_or_a_copy() -> void:
	var cells := _cells_of(_axe())
	var pick := ForgeLib.part_of(cells, Vector3i(0, 6, 0))
	var up := ForgeLib.carry(cells, pick, ForgeLib.shift_op(Vector3i(0, 1, 0)))
	t.eq(up.cells.size(), cells.size(), "as many blocks as before")
	t.check(up.cells.has(Vector3i(0, 8, 0)) and not up.cells.has(Vector3i(-1, 6, 0)), "the head went up one and left its place")
	t.check(up.sel.has(Vector3i(-1, 7, 0)) and up.sel.has(Vector3i(1, 8, 0)), "the pick is where the blocks are now")
	var copy := ForgeLib.carry(cells, pick, ForgeLib.shift_op(Vector3i(0, 1, 0)), true)
	t.check(copy.cells.has(Vector3i(-1, 6, 0)) and copy.cells.has(Vector3i(-1, 8, 0)), "a copy leaves the original and makes the other")
	t.eq(copy.cells.size(), cells.size() + 3, "three new blocks: the head's top row moved up, the rest laid over itself (%d)" % copy.cells.size())
	# What lands on a block takes its place.
	var onto := ForgeLib.carry(cells, {Vector3i(0, -1, 0): true}, ForgeLib.shift_op(Vector3i(0, 1, 0)))
	t.eq(String(onto.cells[Vector3i(0, 0, 0)][0]), "iron", "the pommel moved onto the grip's end and is what stands there")

## The weapon as a shape: every block as it stands from the low corner of its box, with its stuff, job and way (where it stands in the grid is left out).
func _shape(cells: Dictionary) -> Dictionary:
	var all := {}
	for k in cells:
		all[k] = true
	var lo: Vector3i = ForgeLib.pick_box(all)[0]
	var out := {}
	for k in cells:
		out[k - lo] = "%s|%s|%d" % [cells[k][0], cells[k][1], int(cells[k][2])]
	return out

func test_four_quarter_turns_bring_the_shape_home_and_a_turn_trades_the_axes() -> void:
	var cells := _cells_of(_axe())
	var pick := {}
	for k in cells:
		pick[k] = true
	for axis in 3:
		var now := cells
		var sel := pick
		for i in 4:
			var r := ForgeLib.carry(now, sel, ForgeLib.turn_op(sel, axis))
			now = r.cells
			sel = r.sel
		t.eq(now.size(), cells.size(), "axis %d: no block lost in four turns" % axis)
		# (A middle that falls between two cells puts the pick a cell off in a turn: where it stands is not the question, its shape is.)
		t.check(_shape(now) == _shape(cells), "axis %d: four quarter turns bring the shape, and the way each sharp block faces, home" % axis)
	# About z, a 2-wide, 4-tall bar lies down 4 wide and 2 tall.
	var bar := {}
	for x in 2:
		for y in 4:
			bar[Vector3i(x, y, 0)] = ["steel", "blunt", -1]
	var lay := ForgeLib.carry(bar, bar, ForgeLib.turn_op(bar, 2))
	var bx := ForgeLib.pick_box(lay.sel)
	t.eq(bx[1] - bx[0], Vector3i(3, 1, 0), "the bar turned about z is 4 wide and 2 tall")
	t.eq(lay.sel.size(), 8, "and has all its blocks")
	# The other way round is the way back.
	var there := ForgeLib.carry(bar, bar, ForgeLib.turn_op(bar, 2, 1))
	var back := ForgeLib.carry(there.cells, there.sel, ForgeLib.turn_op(there.sel, 2, -1))
	t.check(_shape(back.cells) == _shape(bar), "a turn and the turn the other way leave the shape as it was")

func test_a_sharp_block_faces_the_way_its_block_was_turned_or_flipped() -> void:
	var one := {Vector3i(0, 0, 0): ["steel", "edge", 0]}   # facing right (+x)
	var s := {Vector3i(0, 0, 0): true}
	var up := ForgeLib.carry(one, s, ForgeLib.turn_op(s, 2, 1))
	t.eq(int(up.cells[up.sel.keys()[0]][2]), 2, "turned a quarter about z it faces up")
	var back := ForgeLib.carry(one, s, ForgeLib.turn_op(s, 1, 1))
	t.eq(int(back.cells[back.sel.keys()[0]][2]), 5, "turned about y it faces back (-z)")
	var left := ForgeLib.carry(one, s, ForgeLib.flip_op(s, 0))
	t.eq(int(left.cells[left.sel.keys()[0]][2]), 1, "flipped left for right it faces left")
	var same := ForgeLib.carry(one, s, ForgeLib.flip_op(s, 1))
	t.eq(int(same.cells[same.sel.keys()[0]][2]), 0, "flipped upside down it still faces right")
	var shaped := {Vector3i(0, 0, 0): ["steel", "edge", -1]}
	var r := ForgeLib.carry(shaped, s, ForgeLib.turn_op(s, 2, 1))
	t.eq(int(r.cells[r.sel.keys()[0]][2]), -1, "a block that faces as its shape has it goes on doing")

func test_a_flip_turns_the_pick_over_inside_its_own_box() -> void:
	var cells := _cells_of(_axe())
	var pick := ForgeLib.blocks_in_box(cells, Vector3i(-1, 6, 0), Vector3i(2, 7, 0))
	var r := ForgeLib.carry(cells, pick, ForgeLib.flip_op(pick, 0))
	t.eq(r.cells.size(), cells.size(), "no block lost")
	t.eq(String(r.cells[Vector3i(-1, 6, 0)][1]), "edge", "the edge that was on the right is on the left")
	t.eq(int(r.cells[Vector3i(-1, 6, 0)][2]), 1, "and faces left")
	t.eq(String(r.cells[Vector3i(2, 6, 0)][1]), "blunt", "where it was, a blunt block now")
	var back := ForgeLib.carry(r.cells, r.sel, ForgeLib.flip_op(r.sel, 0))
	var same := true
	for k in cells:
		if not back.cells.has(k) or String(back.cells[k][1]) != String(cells[k][1]) or int(back.cells[k][2]) != int(cells[k][2]):
			same = false
	t.check(same, "flipped twice, it is as it was")

func test_remaking_changes_the_stuff_or_the_job_and_what_a_sharp_block_faces() -> void:
	var cells := _cells_of(_axe())
	var pick := ForgeLib.part_of(cells, Vector3i(0, 6, 0))
	var gold := ForgeLib.remade(cells, pick, "gold", "")
	t.eq(String(gold[Vector3i(0, 6, 0)][0]), "gold", "the stuff is changed")
	t.eq(String(gold[Vector3i(0, 6, 0)][1]), "blunt", "the job is not")
	t.eq(String(gold[Vector3i(2, 6, 0)][0]), "steel", "what is not picked is not")
	var edge := {Vector3i(2, 6, 0): true, Vector3i(2, 7, 0): true}
	var hard := ForgeLib.remade(cells, edge, "", "blunt")
	t.eq(int(hard[Vector3i(2, 6, 0)][2]), -1, "an edge made blunt forgets its way to face")
	var keen := ForgeLib.remade(cells, pick, "", "point")
	t.eq(int(keen[Vector3i(0, 6, 0)][2]), -1, "a blunt block made a point faces as its shape has it")
	var swap := ForgeLib.remade(cells, edge, "", "point")
	t.eq(int(swap[Vector3i(2, 6, 0)][2]), 0, "an edge made a point keeps its way")

func test_a_weapon_that_holds_is_one_piece_on_the_grid() -> void:
	var cells := _cells_of(_axe())
	t.eq(ForgeLib.fault(cells), "", "the axe holds")
	var torn := cells.duplicate()
	torn.erase(Vector3i(0, 3, 0))
	t.eq(ForgeLib.fault(torn), "pieces", "a gap in the grip tears it in two")
	var off := cells.duplicate()
	off[Vector3i(0, ForgeLib.GRID.maxY + 1, 0)] = ["steel", "blunt", -1]
	t.eq(ForgeLib.fault(off), "grid", "a block off the grid")

# ---------- the forge ----------

func test_the_select_tool_is_one_of_the_tools_with_a_key() -> void:
	var f = _forge(_axe())
	t.check(f.TOOLS.any(func(td): return td[0] == "select"), "a Select tool")
	t.eq(f.TOOL_KEYS.get(KEY_V), "select", "on V")
	var key := InputEventKey.new()
	key.pressed = true
	key.keycode = KEY_UNKNOWN
	key.physical_keycode = KEY_V
	f.tool = "build"
	f._unhandled_key_input(key)
	t.eq(f.tool, "select", "V takes it up")
	f.queue_free()

func test_a_pick_is_moved_with_one_undo_and_comes_back_with_it() -> void:
	var f = _forge(_axe())
	var undo0: int = f.undo_stack.size()
	f._set_sel(ForgeLib.blocks_in_box(f.cells, Vector3i(-1, 6, 0), Vector3i(2, 7, 0)))
	t.eq(f.sel.size(), 8, "the head and its edge are picked")
	f._sel_move(Vector3i(1, 0, 0))
	t.eq(f.undo_stack.size() - undo0, 1, "one step to undo")
	t.check(f.cells.has(Vector3i(3, 6, 0)) and not f.cells.has(Vector3i(-1, 6, 0)), "the head went right one")
	t.check(f.sel.has(Vector3i(3, 7, 0)) and not f.sel.has(Vector3i(-1, 7, 0)), "and the pick went with it")
	t.eq(f.cells.size(), _cells_of(_axe()).size(), "no block gained or lost")
	f._undo()
	t.check(f.cells.has(Vector3i(-1, 6, 0)) and not f.cells.has(Vector3i(3, 6, 0)), "undone, the head is back")
	t.check(f.sel.has(Vector3i(-1, 6, 0)) and f.sel.size() == 8, "and so is the pick")
	f._redo()
	t.check(f.cells.has(Vector3i(3, 6, 0)), "redone, to the right again")
	f.queue_free()

func test_a_move_that_tears_the_weapon_is_not_made() -> void:
	var f = _forge(_axe())
	f._set_sel(ForgeLib.blocks_in_box(f.cells, Vector3i(-1, 6, 0), Vector3i(2, 7, 0)))
	var undo0: int = f.undo_stack.size()
	var before: Dictionary = f.cells.duplicate(true)
	f._sel_move(Vector3i(0, 1, 0))   # (a gap between the grip and the head)
	t.eq(f.cells, before, "the weapon is as it was")
	t.eq(f.undo_stack.size(), undo0, "no step to undo was made")
	t.check(String(f.cost_label.text).contains("tear"), "and the anvil says why (%s)" % f.cost_label.text)
	t.eq(f.sel.size(), 8, "the pick is still there")
	# Off the grid: refused too (the whole weapon walked down stops at the floor of the grid).
	f._sel_all()
	var n0: int = f.cells.size()
	for i in 30:
		f._sel_move(Vector3i(0, -1, 0))
	var low := 0
	for k in f.cells:
		low = mini(low, k.y)
	t.eq(low, ForgeLib.GRID.minY, "walked down, the weapon stops at the floor of the grid (%d)" % low)
	t.eq(f.cells.size(), n0, "and no block was lost on the way")
	t.eq(ForgeLib.fault(f.cells), "", "the weapon holds")
	f.queue_free()

func test_a_copy_is_made_by_the_next_move_and_leaves_the_original() -> void:
	var f = _forge(_axe())
	f._set_sel({Vector3i(2, 6, 0): true, Vector3i(2, 7, 0): true})
	f.sel_copy = true
	var n0: int = f.cells.size()
	f._sel_move(Vector3i(0, 0, 1))
	t.eq(f.cells.size(), n0 + 2, "two blocks more: the copy in front of the edge")
	t.check(f.cells.has(Vector3i(2, 6, 0)) and f.cells.has(Vector3i(2, 6, 1)), "the original stayed and the copy is beside it")
	t.check(not f.sel_copy, "the tick is spent")
	t.check(f.sel.has(Vector3i(2, 6, 1)) and not f.sel.has(Vector3i(2, 6, 0)), "the copy is what is picked now")
	# A copy that touches nothing is refused.
	var n1: int = f.cells.size()
	f._set_sel({Vector3i(0, -1, 0): true})
	f.sel_copy = true
	f._sel_move(Vector3i(0, -3, 0))
	t.eq(f.cells.size(), n1, "a copy that hangs in the air is not made")
	f.queue_free()

func test_a_turn_trades_the_pick_for_its_quarter_turn_and_the_hand_goes_with_it() -> void:
	var d := _axe()
	d.grips = {"main": [0, 7, 0], "off": [0, 5, 0]}   # (the hand holds the head: any block will do)
	var f = _forge(d)
	var n0: int = f.cells.size()
	f._set_sel(ForgeLib.part_of(f.cells, Vector3i(0, 6, 0)))
	f._sel_turn(2)
	t.eq(f.cells.size(), n0, "no block lost")
	t.eq(ForgeLib.fault(f.cells), "", "one piece still")
	var g = f.design.get("grips")
	var hand := Vector3i(roundi(g.main[0]), roundi(g.main[1]), roundi(g.main[2]))
	t.check(f.cells.has(hand), "the hand is on a block still (%s)" % str(hand))
	t.check(f.sel.has(hand), "the one it went to with its block")
	f.queue_free()

func test_a_flip_and_a_remake_each_take_one_step_and_the_remake_is_paid_for() -> void:
	var f = _forge(_axe())
	f._set_sel(ForgeLib.blocks_in_box(f.cells, Vector3i(-1, 6, 0), Vector3i(2, 7, 0)))
	var undo0: int = f.undo_stack.size()
	f._sel_flip(0)
	t.eq(f.undo_stack.size() - undo0, 1, "a flip is one step")
	t.eq(String(f.cells[Vector3i(-1, 6, 0)][1]), "edge", "and the edge is on the left")
	f._sel_make("gold", "")
	t.eq(f.undo_stack.size() - undo0, 2, "a remake is another")
	t.eq(String(f.cells[Vector3i(0, 6, 0)][0]), "gold", "the head is gold")
	f.queue_free()
	# Not paid for: a gold head costs more than a poor purse holds.
	var g := {"name": "Poor", "kind": "weapon", "twoHanded": false, "sharpness": 0.8, "voxels": [[0, 0, 0, "wood", "grip"], [0, 1, 0, "wood", "grip"], [0, 2, 0, "wood", "grip"], [0, 3, 0, "iron", "blunt"]]}
	var h = load("res://scripts/ui/forge.gd").new()
	add_child(h)
	h.open(g.duplicate(true), 0, func(_d, _c): pass)
	h._show_mode("voxels")
	h.tool = "select"
	h._set_sel({Vector3i(0, 3, 0): true})
	h._sel_make("gold", "")
	t.eq(String(h.cells[Vector3i(0, 3, 0)][0]), "iron", "with an empty purse the gold is not bought")
	h._sel_make("wood", "")
	t.eq(String(h.cells[Vector3i(0, 3, 0)][0]), "wood", "while a stuff that costs no more is")
	h.queue_free()

func test_the_first_edge_made_on_a_dull_weapon_is_honed_to_a_working_one() -> void:
	var stick := {"name": "Stick", "kind": "weapon", "twoHanded": false, "sharpness": 0.1, "voxels": [[0, 0, 0, "wood", "grip"], [0, 1, 0, "wood", "grip"], [0, 2, 0, "iron", "blunt"], [0, 3, 0, "iron", "blunt"]]}
	var f = _forge(stick)
	f._set_sel({Vector3i(0, 3, 0): true})
	f._sel_make("", "edge")
	t.eq(String(f.cells[Vector3i(0, 3, 0)][1]), "edge", "made a blade")
	t.check(float(f.design.sharpness) >= f.WORKING_EDGE - 0.001, "and honed to a working edge (%.2f)" % float(f.design.sharpness))
	f._undo()
	t.check(float(f.design.sharpness) < 0.2, "undone, the honing is undone with it")
	f.queue_free()

func test_a_click_a_box_and_a_double_click_pick_blocks_and_the_right_button_lets_go() -> void:
	var f = _forge(_axe())
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().physics_frame
	var vs: float = Data.weapon_voxel
	var at := Vector3i(0, 3, 0)
	var px: Vector2 = f.cam.unproject_position(Vector3(at) * vs)
	# A click on a block picks it alone.
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = px
	f._on_view_input(down)
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = px
	f._on_view_input(up)
	t.eq(f.sel.size(), 1, "a click picks one block (%d)" % f.sel.size())
	t.check(f.sel.has(at), "the one under the mouse")
	# A box round the head picks every block whose middle lies in it.
	var head_a: Vector2 = f.cam.unproject_position(Vector3(-1, 8, 0) * vs)
	var head_b: Vector2 = f.cam.unproject_position(Vector3(3, 5, 0) * vs)
	down = InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = head_a - Vector2(4, 4)
	f._on_view_input(down)
	var mv := InputEventMouseMotion.new()
	mv.position = head_b + Vector2(4, 4)
	f._on_view_input(mv)
	t.check(f.marquee != null and bool(f.sel_drag.get("moved", false)), "dragged, a box is on its way")
	up = InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = head_b + Vector2(4, 4)
	f._on_view_input(up)
	t.check(f.sel.has(Vector3i(-1, 6, 0)) and f.sel.has(Vector3i(2, 7, 0)) and f.sel.has(Vector3i(0, 7, 0)), "the head is picked")
	t.check(not f.sel.has(Vector3i(0, 2, 0)) and not f.sel.has(Vector3i(0, -1, 0)), "the grip and the pommel are not")
	# Ctrl takes a block away, Shift adds one.
	var gp: Vector2 = f.cam.unproject_position(Vector3(0, 7, 0) * vs)
	down = InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.ctrl_pressed = true
	down.position = gp
	f._on_view_input(down)
	up = InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = gp
	f._on_view_input(up)
	t.check(not f.sel.has(Vector3i(0, 7, 0)) and f.sel.has(Vector3i(-1, 6, 0)), "Ctrl click takes one block out of the pick")
	var n1: int = f.sel.size()
	var pp: Vector2 = f.cam.unproject_position(Vector3(0, -1, 0) * vs)
	down = InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.shift_pressed = true
	down.position = pp
	f._on_view_input(down)
	up = InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = pp
	f._on_view_input(up)
	t.eq(f.sel.size(), n1 + 1, "Shift click adds one")
	# A double click picks the whole part.
	var dbl := InputEventMouseButton.new()
	dbl.button_index = MOUSE_BUTTON_LEFT
	dbl.pressed = true
	dbl.double_click = true
	dbl.position = px
	f._on_view_input(dbl)
	var rel := InputEventMouseButton.new()
	rel.button_index = MOUSE_BUTTON_LEFT
	rel.pressed = false
	rel.position = px
	f._on_view_input(rel)
	t.eq(f.sel.size(), 6, "a double click on the grip picks the grip (%d)" % f.sel.size())
	# The right button lets go.
	var rc := InputEventMouseButton.new()
	rc.button_index = MOUSE_BUTTON_RIGHT
	rc.pressed = true
	rc.position = px
	f._on_view_input(rc)
	t.eq(f.sel.size(), 0, "the right button lets go of the pick")
	t.eq(f.cells.size(), _cells_of(_axe()).size(), "and takes no block off (it is not Erase here)")
	f.queue_free()

func test_what_is_picked_and_taken_off_is_not_picked_any_more() -> void:
	var f = _forge(_axe())
	f._set_sel({Vector3i(0, -1, 0): true, Vector3i(0, 5, 0): true})
	f._remove([Vector3i(0, -1, 0)])
	t.eq(f.sel.size(), 1, "the pommel went and is not picked")
	t.check(f.sel.has(Vector3i(0, 5, 0)), "the other still is")
	f.queue_free()

func test_the_pick_is_shown_with_the_tool_and_the_buttons_follow_it() -> void:
	var f = _forge(_axe())
	await get_tree().process_frame
	f._set_sel(ForgeLib.part_of(f.cells, Vector3i(0, 6, 0)))
	await get_tree().process_frame
	t.eq(f.sel_mi.multimesh.instance_count, 6, "a tint on each picked block")
	t.check(f.sel_mi.visible, "shown while the tool is in hand")
	t.check(_find_button(f.tool_bar, "Turn ▾") != null and _moves(f).size() == 6, "a pick brings the buttons to work on it (the six arrows, the lists)")
	f.tool = "build"
	await get_tree().process_frame
	t.check(not f.sel_mi.visible, "and it is not shown when another tool is in hand")
	f.tool = "select"
	f._set_sel({})
	await get_tree().process_frame
	t.check(_find_button(f.tool_bar, "Turn ▾") == null and _moves(f).is_empty(), "with nothing picked there is nothing to do with it, and no buttons for it")
	t.check(_find_button(f.tool_bar, "Select all") != null and _find_button(f.tool_bar, "Select none") == null, "only the way to pick everything")
	f.queue_free()

func test_the_arrow_keys_nudge_the_pick_while_the_mouse_is_over_the_anvil() -> void:
	var f = _forge(_axe())
	f._sel_all()
	var key := InputEventKey.new()
	key.pressed = true
	key.keycode = KEY_UP
	f.view_mouse = Vector2(-1, -1)
	f._input(key)
	t.check(f.cells.has(Vector3i(0, -1, 0)) and not f.cells.has(Vector3i(0, 8, 0)), "with the mouse elsewhere the key does nothing")
	f.view_mouse = Vector2(300, 300)
	f._input(key)
	t.check(f.cells.has(Vector3i(0, 8, 0)) and not f.cells.has(Vector3i(0, -1, 0)), "over the anvil Up moves the whole weapon up one")
	key = InputEventKey.new()
	key.pressed = true
	key.keycode = KEY_LEFT
	f._input(key)
	t.check(f.cells.has(Vector3i(-2, 8, 0)) and not f.cells.has(Vector3i(2, 8, 0)), "and Left to the left")
	key = InputEventKey.new()
	key.pressed = true
	key.keycode = KEY_PAGEDOWN
	f._input(key)
	t.check(f.cells.has(Vector3i(-2, 8, 1)), "and Page Down toward the front")
	# A key with Ctrl held, or an echo, is none of its business.
	var n0: int = f.undo_stack.size()
	key = InputEventKey.new()
	key.pressed = true
	key.keycode = KEY_UP
	key.ctrl_pressed = true
	f._input(key)
	key = InputEventKey.new()
	key.pressed = true
	key.echo = true
	key.keycode = KEY_UP
	f._input(key)
	t.eq(f.undo_stack.size(), n0, "Ctrl and Up, or a held key's echo, move nothing")
	f.queue_free()

## The pad's six arrows (drawn on their buttons, which have no words).
func _moves(f) -> Array:
	return f.tool_bar.find_children("*", "Button", true, false).filter(func(b): return b.has_meta("move"))

func _find_button(n: Node, text: String) -> Button:
	if n is Button and (n as Button).text == text:
		return n
	for c in n.get_children():
		var r := _find_button(c, text)
		if r != null:
			return r
	return null
