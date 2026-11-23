extends Node
## The contest's clock (UIStyle.clock_pill): one line however little room it is given, in the middle at the foot of the screen. It was a label of no width at the top,
## where UIStyle.label wraps at the control's width: "Weapons 1:37" stood a letter to a line, over the forge's own buttons (user's screenshot).

var t

func test_the_clock_stays_on_one_line() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var clock := UIStyle.clock_pill()
	layer.add_child(clock)
	t.check(not clock.visible, "hidden until it has something to say")
	clock.visible = true
	clock.text = "Weapons  1:37"
	for i in 3:
		await get_tree().process_frame
	t.check(clock.size.x > 3.0 * clock.size.y, "wider than it is tall, not a column of letters (%s)" % str(clock.size))
	t.check(clock.size.y < 120.0, "one line high (%.0f)" % clock.size.y)
	var vp := get_viewport().get_visible_rect().size
	var mid := clock.get_global_rect().get_center().x
	t.check(absf(mid - vp.x * 0.5) < 2.0, "in the middle (%.0f of %.0f)" % [mid, vp.x])
	t.check(clock.get_global_rect().end.y <= vp.y and clock.get_global_rect().position.y > vp.y * 0.5, "at the foot of the screen, inside it")
	clock.text = "Armour  0:09"
	for i in 2:
		await get_tree().process_frame
	t.check(clock.size.x > 3.0 * clock.size.y, "and so as the text changes (%s)" % str(clock.size))
	layer.queue_free()
	await get_tree().process_frame
