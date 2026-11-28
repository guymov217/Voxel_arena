extends Node
## Training's screen (Menu._training): the bag of things to try in the arena is changed in place, so a + or a − does not build the screen again and the list stays where the player had
## scrolled it to (user: every pick put it back at the top).

var t

func _all(n: Node, pred: Callable, out: Array) -> void:
	if pred.call(n):
		out.append(n)
	for c in n.get_children():
		_all(c, pred, out)

func test_picking_for_the_bag_leaves_the_list_where_it_was() -> void:
	var menu = load("res://scripts/ui/menu.gd").new()
	menu.backdrop_off = true
	add_child(menu)
	await get_tree().process_frame
	menu.show_screen("training")
	await get_tree().process_frame
	await get_tree().process_frame
	var pluses := []
	_all(menu, func(n): return n is Button and (n as Button).text == "+", pluses)
	var minuses := []
	_all(menu, func(n): return n is Button and (n as Button).text == "−", minuses)
	t.check(pluses.size() == (Data.shop.throwables as Dictionary).size() and minuses.size() == pluses.size(), "a tile for every kind of thing on sale (%d)" % pluses.size())
	var plus: Button = pluses.back()
	var minus: Button = minuses.back()
	var scroll: ScrollContainer = null
	var up: Node = plus
	while up != null and scroll == null:
		up = up.get_parent()
		if up is ScrollContainer:
			scroll = up
	t.check(scroll != null, "the bag's list scrolls")
	if scroll == null:
		menu.queue_free()
		return
	scroll.scroll_vertical = 100000
	await get_tree().process_frame
	var at := scroll.scroll_vertical
	t.check(at > 0, "the list is scrolled down to the last tile (%d)" % at)
	var row: Node = plus.get_parent()
	var count: Label = row.get_child(3)
	t.eq(count.text, "0", "none of it in the bag")
	plus.pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	t.check(is_instance_valid(scroll) and scroll.is_inside_tree(), "the list is the very one: the screen was not built again")
	t.eq(scroll.scroll_vertical, at, "and it stands where it stood")
	t.eq(count.text, "1", "the tile counts one")
	t.eq((menu.training.bag as Dictionary).size(), 1, "and the bag has one kind in it")
	t.check(not minus.disabled, "it can be taken out again")
	minus.pressed.emit()
	await get_tree().process_frame
	t.eq(count.text, "0", "taken out: none")
	t.check(minus.disabled and (menu.training.bag as Dictionary).is_empty(), "and the bag is empty")
	t.eq(scroll.scroll_vertical, at, "the list has not moved")
	menu.queue_free()
	await get_tree().process_frame

## The bag takes nine kinds at the most: once it has them every + but those of the kinds in it is off, and a − makes room again.
func test_a_full_bag_closes_the_other_pluses_in_place() -> void:
	var menu = load("res://scripts/ui/menu.gd").new()
	menu.backdrop_off = true
	add_child(menu)
	await get_tree().process_frame
	menu.show_screen("training")
	await get_tree().process_frame
	var pluses := []
	_all(menu, func(n): return n is Button and (n as Button).text == "+", pluses)
	var minuses := []
	_all(menu, func(n): return n is Button and (n as Button).text == "−", minuses)
	for i in Throwables.BAG_KINDS:
		(pluses[i] as Button).pressed.emit()
	await get_tree().process_frame
	t.eq((menu.training.bag as Dictionary).size(), Throwables.BAG_KINDS, "the bag is full of kinds")
	t.check((pluses[Throwables.BAG_KINDS] as Button).disabled, "a tenth kind cannot be added")
	t.check(not (pluses[0] as Button).disabled, "one of the kinds in it can have more")
	(minuses[0] as Button).pressed.emit()
	await get_tree().process_frame
	t.check(not (pluses[Throwables.BAG_KINDS] as Button).disabled, "one kind out, and the tenth can come in")
	menu.queue_free()
	await get_tree().process_frame
