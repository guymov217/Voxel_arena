extends Node
## The tournament's tree as it is drawn (BracketView): its geometry is plain data, read here: every bout has its box, the boxes of a column do not touch, the lines go from a bout to
## the one its winner goes to, the bout being fought and the viewer's own name are marked, the winner is lit and the one put out dimmed, the small tree and the large one.

var t

func _e(key: String, name: String, peer := -1, bot := true) -> Dictionary:
	return {"key": key, "name": name, "peer": peer, "bot": bot}

func _eight() -> Tourney:
	var list := [_e("p1", "Aulus", 1, false)]
	for i in 7:
		list.append(_e("b%d" % i, "Crixus%d" % i))
	return Tourney.make(list, 7)

func _view(tr: Tourney, mine: String, big := false) -> BracketView:
	var v := BracketView.new()
	add_child(v)
	v.set_state(tr, mine, big)
	return v

func test_the_tree_has_a_box_to_every_bout_and_a_line_to_every_winners_next() -> void:
	var v := _view(_eight(), "p1")
	var d := v.layout()
	t.eq((d.boxes as Array).size(), 7, "four bouts, two, one")
	t.eq((d.lines as Array).size(), 6, "a line from each of the first six to the bout its winner goes to")
	t.eq((d.titles as Array).size(), 3, "a title to each round")
	var size_: Vector2 = d.size
	var mg: float = BracketView.MARGIN[0]
	t.check(size_.x > 0.0 and size_.y > 0.0 and v.custom_minimum_size == size_ + Vector2(mg, mg) * 2.0, "it asks the room it needs, and the plate round it (%s)" % str(size_))
	for b in d.boxes:
		var r: Rect2 = b.rect
		t.check(r.position.x >= 0.0 and r.position.y >= 0.0 and r.end.x <= size_.x + 0.01 and r.end.y <= size_.y + 0.01, "every box is inside the tree (%s of %s)" % [str(r), str(size_)])
	for round_ in 3:
		var col: Array = (d.boxes as Array).filter(func(b): return b.round == round_)
		for a in col.size():
			for b2 in range(a + 1, col.size()):
				t.check(not (col[a].rect as Rect2).intersects(col[b2].rect), "round %d: two boxes do not touch" % round_)
	var open: Array = (d.boxes as Array).filter(func(b): return b.open)
	t.eq(open.size(), 1, "the bout being fought is marked, one")
	t.check(open[0].round == 0, "the first round's")
	v.queue_free()

func test_a_name_is_lit_dimmed_or_the_viewers_own() -> void:
	var tr := _eight()
	var m := tr.open_match()
	tr.report(m, String(m.b))
	var v := _view(tr, String(m.a))   # (the viewer is the one put out)
	var d := v.layout()
	var first: Dictionary = (d.boxes as Array)[0]
	t.check(first.done, "the bout is done")
	t.eq(first.names[1].state, "won", "the winner is lit")
	t.eq(first.names[0].state, "out", "the one put out is dimmed, though he is the viewer")
	var nxt: Array = (d.boxes as Array).filter(func(b): return b.round == 1)
	t.eq(nxt[0].names[0].text, tr.name_of(String(m.b)), "the winner stands in the next round")
	t.eq(nxt[0].names[1].state, "empty", "the other place waits")
	var open: Array = (d.boxes as Array).filter(func(b): return b.open)
	t.check(open.size() == 1 and open[0].index == 1, "and the mark has moved to the next bout")
	v.queue_free()
	var v2 := _view(tr, String(m.b))   # (the viewer is the winner)
	var d2 := v2.layout()
	t.eq((d2.boxes as Array)[0].names[1].state, "mine", "his own name is marked")
	v2.queue_free()

func test_the_crowned_one_is_named_and_the_odd_one_out_is_through() -> void:
	var list := [_e("p1", "Aulus", 1, false), _e("bA", "A"), _e("bB", "B")]
	var tr := Tourney.make(list, 3)
	var v := _view(tr, "p1")
	var d := v.layout()
	t.eq((d.boxes as Array).size(), 3, "three: two bouts, one of them a bye, and the final")
	var byes: Array = (d.boxes as Array).filter(func(b): return b.names[1].state == "bye")
	t.eq(byes.size(), 1, "the odd one is shown with a bye")
	t.eq(d.champion, "", "nobody is crowned")
	while not tr.finished():
		var m := tr.open_match()
		if m.is_empty():
			tr.advance()
			continue
		tr.report(m, String(m.a))
	v.set_state(tr, "p1", false)
	t.check(String(v.layout().champion) != "", "the champion is named")
	v.queue_free()

func test_the_large_tree_is_larger() -> void:
	var small := _view(_eight(), "p1", false)
	var large := _view(_eight(), "p1", true)
	t.check((large.layout().size as Vector2).x > (small.layout().size as Vector2).x and (large.layout().size as Vector2).y > (small.layout().size as Vector2).y, "larger in both ways (%s against %s)" % [str(large.layout().size), str(small.layout().size)])
	t.check((small.layout().size as Vector2).x < 420.0 and (small.layout().size as Vector2).y < 200.0, "and the small one is small enough for a corner (%s)" % str(small.layout().size))
	small.queue_free()
	large.queue_free()

func test_nothing_to_draw_is_nothing() -> void:
	var v := BracketView.new()
	add_child(v)
	v.set_state(null, "", false)
	t.eq(v.layout().size, Vector2.ZERO, "no bracket: no size")
	v.set_state(Tourney.new(), "", false)
	t.check((v.layout().boxes as Array).is_empty(), "an empty one: no boxes")
	v.queue_free()
