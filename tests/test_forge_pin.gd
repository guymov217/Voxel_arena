extends Node
## The forge's pinned weapon (user: pin the weapon on the anvil, or one of My designs, and see the bars' differences against it all the time, not only the last change's): what a design comes to
## on the bars, the per cent a figure is over or under the pin's, the pin kept while the game runs and shown on the next forge, the buttons that pin and unpin.

var t

func _forge(d: Dictionary):
	var f = load("res://scripts/ui/forge.gd").new()
	add_child(f)
	f.free_build = true
	f.open(d.duplicate(true), 9999, func(_d, _c): pass)
	return f

func _find_button(n: Node, text: String) -> Button:
	if n is Button and (n as Button).text == text:
		return n
	for c in n.get_children():
		var r := _find_button(c, text)
		if r != null:
			return r
	return null

## (The runner has no set-up: each test begins and ends with nothing pinned, the pin being kept for as long as the game runs.)
func _reset() -> void:
	load("res://scripts/ui/forge.gd").pinned = {}

func test_a_design_on_the_bars_is_what_the_forge_shows_of_the_weapon_on_the_anvil() -> void:
	_reset()
	var F = load("res://scripts/ui/forge.gd")
	for k in ["gladius", "warhammer", "dagger"]:
		var d := Data.preset(k)
		var f = _forge(d)
		await get_tree().process_frame
		await get_tree().process_frame
		var v: Dictionary = F.bars_of(f._design_now())
		for b in ["speed", "damage", "reach", "armour", "durability"]:
			t.check(is_equal_approx(float(v.bars[b]), float(f.bar_vals[b])), "%s: the %s bar is the anvil's (%.3f, %.3f)" % [k, b, float(v.bars[b]), float(f.bar_vals[b])])
		for b in ["speed", "damage", "reach", "armour", "durability", "mass"]:
			t.check(is_equal_approx(float(v.now[b]), float(f.stat_now[b])), "%s: the %s figure is the anvil's" % [k, b])
		f.queue_free()
	_reset()

func test_a_figure_is_so_many_per_cent_over_or_under_the_pinned() -> void:
	_reset()
	var F = load("res://scripts/ui/forge.gd")
	t.check(is_equal_approx(F.pin_delta(110.0, 100.0), 10.0), "a tenth more")
	t.check(is_equal_approx(F.pin_delta(90.0, 100.0), -10.0), "a tenth less")
	t.check(is_equal_approx(F.pin_delta(5.0, 0.0), 100.0), "something where the pinned has nothing")
	t.check(is_equal_approx(F.pin_delta(0.0, 0.0), 0.0), "nothing against nothing")
	t.check(is_equal_approx(F.pin_delta(2.0, 2.0), 0.0), "the same")
	_reset()

func test_the_weapon_on_the_anvil_is_pinned_and_unpinned() -> void:
	_reset()
	var F = load("res://scripts/ui/forge.gd")
	var f = _forge(Data.preset("gladius"))
	t.check(F.pinned.is_empty(), "nothing is pinned at first")
	t.eq(f.pin_button.text, "Pin it", "the one button says Pin it")
	f.name_edit.text = "My blade"
	f._pin_now()
	t.eq(String(F.pinned.get("name", "")), "My blade", "pinned by the name it has on the anvil")
	t.eq(f.pin_button.text, "Unpin", "and Unpin once something is pinned")
	t.check(float(f.bars.custom_minimum_size.y) > 122.0, "the bars have room for the line that names it")
	var pinned_mass: float = float(F.pinned.vals.now.mass)
	# The weapon changed after the pin: the pin is as it was.
	f.mat = "gold"
	f.job = "blunt"
	f.mirror = false
	f.mirror_z = false
	f.tool = "build"
	var top: Vector3i = f.cells.keys().reduce(func(a, b): return a if a.y > b.y else b)
	f._place([top + Vector3i(0, 1, 0), top + Vector3i(0, 2, 0), top + Vector3i(0, 3, 0)])
	await get_tree().process_frame
	await get_tree().process_frame
	t.check(is_equal_approx(float(F.pinned.vals.now.mass), pinned_mass), "the pin keeps its own figures")
	var dk: float = float(f.stat_now.mass) - float(F.pinned.vals.now.mass)
	t.check(dk > 0.0, "the weapon on the anvil is heavier than the pin by %.2f kg" % dk)
	t.check(F.pin_delta(float(f.stat_now.mass), pinned_mass) > 0.0, "and so many per cent more")
	f._unpin()
	t.check(F.pinned.is_empty() and f.pin_button.text == "Pin it", "unpinned: nothing, and Pin it again")
	t.check(is_equal_approx(float(f.bars.custom_minimum_size.y), 122.0), "and the bars' room is as it was")
	f.queue_free()
	_reset()

## (One button where there were two: it pins, and with something pinned it takes the pin away.)
func test_the_one_button_pins_and_unpins() -> void:
	_reset()
	var F = load("res://scripts/ui/forge.gd")
	var f = _forge(Data.preset("gladius"))
	f.pin_button.pressed.emit()
	t.check(not F.pinned.is_empty() and f.pin_button.text == "Unpin", "pressed, it pins (%s)" % f.pin_button.text)
	f.pin_button.pressed.emit()
	t.check(F.pinned.is_empty() and f.pin_button.text == "Pin it", "pressed again, it lets go")
	f.queue_free()
	_reset()

func test_a_pin_outlives_the_forge_it_was_made_in() -> void:
	_reset()
	var F = load("res://scripts/ui/forge.gd")
	var a = _forge(Data.preset("longsword"))
	a._pin_now()
	a.queue_free()
	await get_tree().process_frame
	var b = _forge(Data.preset("dagger"))
	t.check(not F.pinned.is_empty() and String(F.pinned.name) == "Longsword", "the next forge shows what was pinned (%s)" % str(F.pinned.get("name")))
	t.eq(b.pin_button.text, "Unpin", "with its Unpin")
	t.check(float(F.pinned.vals.now.mass) > float(b.stat_now.get("mass", 0.0)), "a longsword is heavier than the dagger on the anvil")
	b.queue_free()
	_reset()

func test_one_of_my_designs_is_pinned_from_its_card() -> void:
	_reset()
	var F = load("res://scripts/ui/forge.gd")
	var d := Data.preset("axe").duplicate(true)
	d.name = "Chopper"
	Save.set_value("forge_gallery", [d])
	var f = _forge(Data.preset("gladius"))
	f._show_mode("gallery")
	await get_tree().process_frame
	var pin: Button = _find_button(f.mode_box, "Pin")
	t.check(pin != null, "a Pin button on the design's card")
	if pin:
		pin.pressed.emit()
		t.eq(String(F.pinned.get("name", "")), "Chopper", "it pins that design")
		t.check(float(F.pinned.vals.now.reach) > 0.0, "with its figures worked out")
		t.check(f.cost_label.text.contains("Chopper"), "and the anvil says so (%s)" % f.cost_label.text)
	f.queue_free()
	_reset()

func test_nothing_is_pinned_from_a_blank_anvil() -> void:
	_reset()
	var F = load("res://scripts/ui/forge.gd")
	var f = _forge({"name": "Nothing", "kind": "weapon", "twoHanded": false, "sharpness": 0.8, "voxels": []})
	f._pin_now()
	t.check(F.pinned.is_empty(), "there is nothing there to pin")
	f.queue_free()
	_reset()
