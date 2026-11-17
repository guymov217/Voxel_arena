class_name PhysicianScreen
extends VBoxContainer
## Galen's table: the gladiator himself, in the new look, stripped and standing in the light, with
## what the arena left on him marked on his body in numbered pins, and the same numbers down the
## right with what the physician can do for each, and for how much (the one chosen opens, with its
## treatments in it); one button that sees to it all; the supplies for the fight along the foot.
## Drawing and asking only: what is treated and what it costs are Body's, the purse and the bag
## Menu's, as they were.

## A numbered mark on the body (and the same badge in the list): lit when its group is the one in hand.
class Pin extends Control:
	signal picked
	var n := 1
	var on := false
	var dim := false
	var hot := false    # the list's row for it is under the mouse

	func _init(num := 1, hit := true) -> void:
		n = num
		custom_minimum_size = Vector2(30, 30)
		size = Vector2(30, 30)
		mouse_filter = Control.MOUSE_FILTER_STOP if hit else Control.MOUSE_FILTER_IGNORE
		if hit:
			mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	func _draw() -> void:
		var c := size * 0.5
		var a := 0.5 if dim else 1.0
		if on:
			draw_circle(c, 15.0, Color(UIStyle.GOLD, 0.35 * a))
		if hot:
			draw_arc(c, 14.5, 0.0, TAU, 28, Color(1, 1, 1, 0.9 * a), 2.0, true)
		draw_circle(c, 12.0, Color(UIStyle.INK, a))
		draw_circle(c, 10.5, Color(UIStyle.GOLD_LIGHT if on else Color(0.82, 0.25, 0.18), a))
		var f := UIStyle.serif(0, 700)
		var t := str(n)
		var w := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		draw_string(f, Vector2(c.x - w * 0.5, c.y + 5.0), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UIStyle.INK if on else Color(1, 0.95, 0.88, a))

	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			picked.emit()

var menu: Control
var panel: Control          # the panel it is drawn in: the yard's, or the visit's own
var b: Dictionary = {}
var news: Array = []
var stage_n := 1
var done: Callable
var done_text := ""
var changed: Callable
var supplies := false       # the stall in the yard also sells the supplies for the fight
var inner := Vector2(1392, 768)
var compact := false
var k := 1.0                # the writing a little larger where there is room
var left_w := 520.0
var right_w := 800.0
var groups: Array = []      # what can be done, by the part of him it is for: {key, part, title, offers}
var sel := ""
var man_stage: ArmourStage
var pins: Dictionary = {}
var list_col: VBoxContainer
var list_scroll: ScrollContainer
var purse: StationKit.Purse
var _layer: Control

## Builds the physician into `v` (inside `panel_`). `o`: body, news (what the fight left on him
## since), stage, done(body), done_text, changed(body), supplies. The yard's stall gives its leave
## button as v's first child; the visit between rounds (`done_text`) has a button of its own at the foot.
static func build(m: Control, v: VBoxContainer, panel_: Control, o: Dictionary) -> PhysicianScreen:
	var s := PhysicianScreen.new()
	s.menu = m
	s.panel = panel_
	s.b = o.body
	s.news = o.get("news", [])
	s.stage_n = int(o.get("stage", 1))
	s.done = o.done
	s.done_text = String(o.get("done_text", ""))
	s.changed = o.changed
	s.supplies = bool(o.get("supplies", false))
	var leave: Button = null
	if v.get_child_count() > 0 and v.get_child(0) is Button:
		leave = v.get_child(0)
		v.remove_child(leave)
	StationKit.take_msg(m, v)
	v.add_child(s)
	s.setup(leave)
	return s

func _fs(n: int) -> int:
	return int(round(n * k))

func setup(leave: Button) -> void:
	var vp: Vector2 = menu.get_viewport_rect().size
	panel.custom_minimum_size = Vector2(maxf(640.0, vp.x - 144.0), maxf(420.0, minf(vp.y - 80.0, vp.x * 0.62)))
	inner = panel.custom_minimum_size - Vector2(64.0, 52.0)
	compact = inner.y < 640.0
	k = 1.0 if compact else clampf(inner.y / 768.0, 1.0, 1.3)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 6 if compact else 10)
	_groups()
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 16)
	add_child(head)
	var names := VBoxContainer.new()
	names.add_theme_constant_override("separation", 0)
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if supplies:
		names.add_child(UIStyle.label("THE LUDUS YARD", 13, UIStyle.BRONZE))
	names.add_child(UIStyle.title("The physician", 28 if compact else 36))
	head.add_child(names)
	purse = StationKit.Purse.new(menu.coins(), 24)
	purse.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(purse)
	if leave != null:
		leave.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		head.add_child(leave)
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 18)
	add_child(body)
	left_w = clampf(inner.x * 0.36, 280.0, 540.0)
	right_w = inner.x - left_w - 18.0
	# The man, and under him how he stands.
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = left_w
	left.add_theme_constant_override("separation", 6)
	body.add_child(left)
	man_stage = ArmourStage.make("")
	man_stage.body = b
	man_stage.spin = 0.0
	man_stage.stage.spin = 0.0
	add_child(man_stage)
	man_stage.frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	man_stage.frame.custom_minimum_size.y = 190.0 if compact else 320.0
	left.add_child(man_stage.frame)
	_layer = man_stage.frame.get_meta("layer")
	var state := Body.summary(b)
	if not news.is_empty():
		state = ", ".join(news.map(func(n): return str(n)))
	state = state.left(1).to_upper() + state.substr(1)
	var sl := UIStyle.label(state, 14, StationKit.BAD if not news.is_empty() else UIStyle.TEXT)
	sl.custom_minimum_size.x = left_w - 20.0
	left.add_child(sl)
	# What can be done: the one button, the list by the part of him, the elixir.
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 6 if compact else 8)
	body.add_child(right)
	right.add_child(StationKit.kicker("What the sand left on you"))
	var offers: Array = Body.offers(b, stage_n)
	var all := offers.filter(func(o): return String(o.id) == "heal:all")
	if not all.is_empty():
		var p_all := int(all[0].price)
		var big := UIStyle.button(Loc.t("Treat everything · it costs %d") % p_all, func(): _treat("heal:all", p_all), true)
		big.disabled = p_all > menu.coins()
		big.autowrap_mode = TextServer.AUTOWRAP_OFF
		big.tooltip_text = Loc.t(String(all[0].desc)) + ("" if p_all <= menu.coins() else Loc.t("  (%d more needed)") % (p_all - menu.coins()))
		if compact:
			StationKit.shrink(big, 15, 10.0, 6.0)
		right.add_child(big)
	list_scroll = ScrollContainer.new()
	list_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	list_scroll.custom_minimum_size.y = 90.0 if compact else 120.0
	right.add_child(list_scroll)
	list_col = VBoxContainer.new()
	list_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_col.add_theme_constant_override("separation", 5 if compact else 7)
	list_scroll.add_child(list_col)
	var el := offers.filter(func(o): return String(o.id) == "elixir:all")
	if not el.is_empty():
		right.add_child(_elixir(el[0]))
	_rows()
	# The foot: the supplies for the fight (the stall; a man with nothing to treat has them in the
	# list's place), the way back to the arena (the visit).
	if (supplies and not groups.is_empty()) or done_text != "":
		var foot := HBoxContainer.new()
		foot.add_theme_constant_override("separation", 16)
		add_child(foot)
		if supplies and not groups.is_empty():
			var sup := _supplies(false)
			sup.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			foot.add_child(sup)
		else:
			foot.add_child(StationKit.spacer())
		if done_text != "":
			var back := UIStyle.button(done_text, func(): done.call(b), true)
			back.size_flags_vertical = Control.SIZE_SHRINK_END
			foot.add_child(back)
	man_stage.built.connect(_pins_on, CONNECT_ONE_SHOT)
	man_stage.dress([])
	var line: Dictionary = menu.station_note
	menu.station_note = {}
	StationKit.show_note(panel, purse, line)

func _empty(c: Node) -> void:
	for x in c.get_children():
		c.remove_child(x)
		x.queue_free()

# ---------- What can be done, by the part of the body ----------

func _groups() -> void:
	groups = []
	var by_key := {}
	var offers: Array = Body.offers(b, stage_n)
	for o in offers:
		var id := String(o.id)
		if id == "heal:all" or id == "elixir:all":
			continue
		var bits := id.split(":")
		var kind := bits[0]
		var n := bits[1] if bits.size() > 1 else ""
		var key := id
		var part := "torso"
		var title := Loc.t(String(o.name))
		match kind:
			"peg", "hook", "blade":
				key = "lost:" + n
				part = n
				title = Loc.t("%s lost") % Body.label(n)
			"glassEye":
				key = "eye:" + n
				part = "eye" + n
			"set":
				key = "bone:" + n
				part = n
			"stitch":
				key = "wounds"
				part = "wounds"
			"medicine":
				key = "scar:" + n
				part = n
		title = title.left(1).to_upper() + title.substr(1)
		if not by_key.has(key):
			var g := {"key": key, "part": part, "title": title, "offers": []}
			by_key[key] = g
			groups.append(g)
		by_key[key].offers.append(o)
	if sel == "" or not by_key.has(sel):
		sel = String(groups[0].key) if not groups.is_empty() else ""

func _cheapest(g: Dictionary) -> int:
	var low := 1 << 30
	for o in g.offers:
		low = mini(low, int(o.price))
	return low

# ---------- The list: each part of him, the one chosen opened ----------

func _rows() -> void:
	_empty(list_col)
	if groups.is_empty():
		var card := StationKit.card(StationKit.GOOD, 1, 14, 8)
		var l := UIStyle.label("Nothing he needs to see to.", _fs(18), StationKit.GOOD)
		l.custom_minimum_size.x = right_w - 70.0
		card.add_child(l)
		list_col.add_child(card)
		# (With nothing to treat, the supplies are what the table is for.)
		if supplies:
			list_col.add_child(StationKit.kicker("Supplies for the fight"))
			list_col.add_child(_supplies(true))
		return
	for i in groups.size():
		list_col.add_child(_group_row(i))

func _group_row(i: int) -> Control:
	var g: Dictionary = groups[i]
	var key := String(g.key)
	var on := key == sel
	var card := StationKit.card(UIStyle.GOLD if on else UIStyle.BRONZE_DARK, 2 if on else 1, (8 if compact else 10), 8, Color(0.15, 0.108, 0.075, 0.98) if on else StationKit.CARD_BG)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	if not on:
		card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(col)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(row)
	var num := Pin.new(i + 1, false)
	num.on = on
	num.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(num)
	if on:
		var h := StationKit.heading(String(g.title), 19 if compact else _fs(22))
		h.autowrap_mode = TextServer.AUTOWRAP_OFF
		h.clip_text = true
		h.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(h)
	else:
		var t := UIStyle.label(String(g.title), _fs(16), UIStyle.TEXT)
		t.autowrap_mode = TextServer.AUTOWRAP_OFF
		t.clip_text = true
		t.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(t)
		var low := _cheapest(g)
		var pr := StationKit.price(low, low <= menu.coins(), _fs(16))
		pr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(pr)
	if on:
		for o in g.offers:
			var d := UIStyle.label(Loc.t(String(o.desc)), 12 if compact else _fs(13), UIStyle.MUTED)
			d.custom_minimum_size.x = right_w - 90.0
			d.mouse_filter = Control.MOUSE_FILTER_IGNORE
			col.add_child(d)
			var price := int(o.price)
			var btn := UIStyle.button(Loc.t("%s · %d denarii") % [Loc.t(String(o.name)), price], func(): _treat(String(o.id), price), true)
			btn.disabled = price > menu.coins()
			btn.autowrap_mode = TextServer.AUTOWRAP_OFF
			btn.tooltip_text = "" if price <= menu.coins() else Loc.t("  (%d more needed)") % (price - menu.coins())
			if compact:
				StationKit.shrink(btn, 14, 10.0, 5.0)
			col.add_child(btn)
		card.set_meta("on", true)
	else:
		card.gui_input.connect(func(e: InputEvent):
			if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
				_pick(key))
		card.mouse_entered.connect(func(): _hot(key, true))
		card.mouse_exited.connect(func(): _hot(key, false))
	return card

## The row under the mouse lights its pin on the man.
func _hot(key: String, on: bool) -> void:
	var pin: Pin = pins.get(key)
	if pin != null and is_instance_valid(pin):
		pin.hot = on
		pin.queue_redraw()

## A part of him was chosen (in the list or by its pin): lit in both, opened in the list.
func _pick(key: String) -> void:
	if key == sel:
		return
	StationKit.tick()
	sel = key
	_rows()
	for g in groups:
		var pin: Pin = pins.get(String(g.key))
		if pin != null and is_instance_valid(pin):
			pin.on = String(g.key) == sel
			pin.hot = false
			pin.queue_redraw()
	for c in list_col.get_children():
		if c.has_meta("on"):
			list_scroll.call_deferred("ensure_control_visible", c)

func _elixir(o: Dictionary) -> Control:
	var price := int(o.price)
	var card := StationKit.card(UIStyle.GOLD, 1, 10, 8, Color(0.16, 0.12, 0.06, 0.97))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	card.add_child(row)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 2)
	row.add_child(col)
	col.add_child(StationKit.kicker("The god's own cure", UIStyle.GOLD))
	col.add_child(StationKit.heading(Loc.t(String(o.name)), 17 if compact else _fs(20)))
	if not compact:
		var d := UIStyle.label(Loc.t(String(o.desc)), _fs(12), UIStyle.MUTED)
		d.custom_minimum_size.x = maxf(160.0, right_w - 300.0)
		col.add_child(d)
	var btn := UIStyle.button(Loc.t("%d denarii") % price, func(): _treat(String(o.id), price), true)
	btn.disabled = price > menu.coins()
	btn.autowrap_mode = TextServer.AUTOWRAP_OFF
	btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	btn.tooltip_text = Loc.t(String(o.desc))
	row.add_child(btn)
	return card

func _treat(id: String, price: int) -> void:
	if price > menu.coins():
		return
	menu.add_coins(-price)
	if Sfx:
		Sfx.play("pickup", Vector3.ZERO, 0.6)
	menu.station_note = {"rise": "−%d" % price}
	changed.call(Body.apply(b, id))

# ---------- The supplies for the fight ----------

## Bandages, bread, wine and the water skin, into the bag like the market's. `inline`: large, with
## what each does (a man with nothing to treat); else one row of tiles along the foot.
func _supplies(inline: bool) -> Control:
	var wrap := VBoxContainer.new()
	wrap.add_theme_constant_override("separation", 4)
	if not inline:
		wrap.add_child(StationKit.kicker("Supplies for the fight"))
	var holder: Container
	if inline:
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 10)
		grid.add_theme_constant_override("v_separation", 10)
		holder = grid
	else:
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 10)
		holder = hb
	wrap.add_child(holder)
	var kit: Dictionary = menu.kit()
	var table: Dictionary = Data.shop.get("throwables", {})
	var px := (44 if compact else _fs(88)) if inline else (40 if compact else 52)
	var tile_w := (right_w - 20.0) * 0.5
	for id in table:
		if menu.kit_use(id) != "self":
			continue
		var it: Dictionary = table[id]
		var have := int(kit.get(id, 0))
		var carry := StationKit.carry_of(kit, id)
		var none := String(carry.why) != ""
		var card := StationKit.card(UIStyle.BRONZE if have > 0 else UIStyle.BRONZE_DARK, 1, 6 if compact else (14 if inline else 8), 8)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 14 if inline and not compact else 10)
		card.add_child(h)
		var tex := TextureRect.new()
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex.custom_minimum_size = Vector2(px, px)
		tex.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(tex)
		tex.tree_entered.connect(func(): Thumbs.item(tex, id), CONNECT_ONE_SHOT)
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_theme_constant_override("separation", 2)
		h.add_child(col)
		var nm := UIStyle.label(Loc.t(String(it.name)), 14 if not inline else (16 if compact else _fs(20)), UIStyle.TEXT)
		nm.autowrap_mode = TextServer.AUTOWRAP_OFF
		nm.clip_text = true
		nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		col.add_child(nm)
		if inline:
			var d := UIStyle.label(String(it.get("desc", "")), 12 if compact else _fs(14), UIStyle.MUTED)
			d.custom_minimum_size.x = maxf(120.0, tile_w - px - 70.0)
			col.add_child(d)
		# How many he carries of it and how many more fit, or why none: under the name.
		var cl := UIStyle.label(StationKit.carry_line(carry), 12 if (compact or not inline) else _fs(13), StationKit.BAD if none else UIStyle.MUTED)
		if inline:
			cl.custom_minimum_size.x = maxf(120.0, tile_w - px - 70.0)
		else:
			cl.autowrap_mode = TextServer.AUTOWRAP_OFF
			cl.clip_text = true
			cl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			cl.tooltip_text = cl.text
		col.add_child(cl)
		var price := int(it.price)
		var buy := UIStyle.button(StationKit.carry_short(carry) if none else Loc.t("Buy · %d denarii") % price, func(): _buy_supply(id, price), price <= menu.coins() and not none)
		buy.disabled = price > menu.coins() or none
		buy.tooltip_text = StationKit.carry_line(carry)
		buy.autowrap_mode = TextServer.AUTOWRAP_OFF
		if not inline or compact:
			StationKit.shrink(buy, 13 if compact else 14, 8.0, 4.0 if compact else 6.0)
		col.add_child(buy)
		holder.add_child(card)
	return wrap

func _buy_supply(id: String, price: int) -> void:
	var kit: Dictionary = menu.kit()
	if price > menu.coins():
		menu.show_screen("physician", "Not enough denarii")
		return
	if not Throwables.bag_has_room(kit, id):
		menu.show_screen("physician", StationKit.carry_short(StationKit.carry_of(kit, id)))
		return
	menu.add_coins(-price)
	kit[id] = int(kit.get(id, 0)) + 1
	menu.set_kit(kit)
	if Sfx:
		Sfx.play("pickup", Vector3.ZERO, 0.6)
	menu.station_note = {"rise": "−%d" % price}
	menu.show_screen("physician")

# ---------- The pins on the body ----------

## Where on him a group of treatments is for, in the world (the man stands at his build's own
## place, the camera goes round him): the part itself, or a spot on it (an eye, the ribs, the hip).
func _anchor(part: String) -> Vector3:
	var man := man_stage.man
	var fwd := Vector3.FORWARD
	var right := Vector3.RIGHT
	var have := man != null and is_instance_valid(man)
	if have:
		fwd = man.global_transform.basis.z
		right = man.global_transform.basis.x
	var p := part
	if p == "wounds" or p == "ribs" or p == "pelvis":
		p = "torso"
	elif p == "skull" or p.begins_with("eye"):
		p = "head"
	var at := Vector3.ZERO
	if have and man.by_name.has(p):
		at = (man.by_name[p] as Node3D).global_position
	else:
		var a: Array = Data.body_def(p).get("pos", [0, 1, 0])
		at = Vector3(float(a[0]), float(a[1]), float(a[2]))
	match part:
		"eyeL": at += right * 0.04 + Vector3.UP * 0.03 + fwd * 0.1
		"eyeR": at += right * -0.04 + Vector3.UP * 0.03 + fwd * 0.1
		"skull": at += Vector3.UP * 0.1 + fwd * 0.02
		"ribs": at += Vector3.UP * 0.14 + fwd * 0.12 + right * -0.07
		"pelvis": at += Vector3.UP * -0.2 + fwd * 0.1
		"wounds": at += Vector3.UP * 0.02 + fwd * 0.12 + right * 0.1
		"torso": at += fwd * 0.1
	return at

func _pins_on() -> void:
	for p in pins.values():
		if is_instance_valid(p):
			p.queue_free()
	pins = {}
	for i in groups.size():
		var g: Dictionary = groups[i]
		var pin := Pin.new(i + 1)
		pin.on = String(g.key) == sel
		var key := String(g.key)
		pin.picked.connect(func(): _pick(key))
		_layer.add_child(pin)
		pins[key] = pin
	_place_pins()

func _process(_dt: float) -> void:
	if not pins.is_empty():
		_place_pins()

func _place_pins() -> void:
	var stage: Stage3D = man_stage.stage
	var man := man_stage.man
	if stage.model == null or man == null or not is_instance_valid(man):
		return
	var cam := stage.cam
	# (Seen from behind the marks are dim: they are on his front.)
	var fwd := man.global_transform.basis.z
	var behind := fwd.dot(cam.global_position - man.global_position) < 0.0
	var at: Array = []
	var list: Array = []
	for g in groups:
		var pin: Pin = pins.get(String(g.key))
		if pin == null or not is_instance_valid(pin):
			continue
		list.append(pin)
		at.append(cam.unproject_position(_anchor(String(g.part))))
	# Marks that would lie on one another are moved apart (each keeps its place in the list).
	for pass_n in 8:
		var moved := false
		for i in at.size():
			for j in range(i + 1, at.size()):
				var d: Vector2 = at[j] - at[i]
				var gap := 34.0
				if d.length() < gap:
					var dir := d.normalized() if d.length() > 0.5 else Vector2(0.0, 1.0)
					var push := (gap - d.length()) * 0.5 + 0.5
					at[i] = (at[i] as Vector2) - dir * push
					at[j] = (at[j] as Vector2) + dir * push
					moved = true
		if not moved:
			break
	var box := man_stage.frame.size
	for i in list.size():
		var pin: Pin = list[i]
		var p: Vector2 = at[i]
		p.x = clampf(p.x, 18.0, maxf(18.0, box.x - 18.0))
		p.y = clampf(p.y, 18.0, maxf(18.0, box.y - 18.0))
		pin.position = p - pin.size * 0.5
		if pin.dim != behind:
			pin.dim = behind
			pin.queue_redraw()
