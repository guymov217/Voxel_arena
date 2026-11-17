class_name StationKit
extends RefCounted
## What the yard's stalls are built from (the trader's table, the smith, the trainer, the
## physician): cards and a dark stage to show a thing on, the purse with its coins, a stat bar,
## the strip of the bag, a ware flying into it, the price that rises from the purse and the short
## red word when a deed cannot be done. Drawing only: what is bought, mended or taught is Menu's,
## as it was.

const CARD_BG := Color(0.1, 0.075, 0.055, 0.95)
const INSET_BG := Color(0.05, 0.04, 0.03, 0.92)
const GOOD := Color(0.62, 0.8, 0.45)
const BAD := Color(1.0, 0.55, 0.45)
const BLUE := Color(0.55, 0.72, 0.9)

## A framed panel: a card for a ware, a tile, a list's row.
static func card(border := UIStyle.BRONZE_DARK, width := 1, pad := 10, radius := 6, bg := CARD_BG) -> PanelContainer:
	var c := PanelContainer.new()
	c.add_theme_stylebox_override("panel", plate(border, width, pad, radius, bg))
	return c

static func plate(border := UIStyle.BRONZE_DARK, width := 1, pad := 10, radius := 6, bg := CARD_BG) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(width)
	s.set_corner_radius_all(radius)
	s.content_margin_left = pad
	s.content_margin_right = pad
	s.content_margin_top = pad
	s.content_margin_bottom = pad
	return s

## A small heading in bronze capitals (the serif of the inscriptions, UIStyle.label).
static func kicker(text: String, color := UIStyle.BRONZE, size := 12, shrink := false) -> Label:
	var l := UIStyle.label(Loc.t(text).to_upper(), size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	if shrink:
		# (It takes what width there is and is cut off with dots, never widening what it is in.)
		l.clip_text = true
		l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l

## A ware's or a weapon's name in gold.
static func heading(text: String, size := 28) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", UIStyle.serif(2, 700))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", UIStyle.GOLD)
	l.add_theme_color_override("font_outline_color", UIStyle.INK)
	l.add_theme_constant_override("outline_size", maxi(2, int(size / 12)))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l

static func spacer(h := false) -> Control:
	var s := Control.new()
	if h:
		s.size_flags_vertical = Control.SIZE_EXPAND_FILL
	else:
		s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return s

## The dark stage a 3D view stands on: a warm glow behind it, the thing, a tag in the corner and a
## hint on turning it. Returns the frame; `stage` is the view.
static func stage_frame(stage: Stage3D, tag := "", hint := "Drag to turn it") -> Control:
	var frame := PanelContainer.new()
	var st := plate(UIStyle.BRONZE_DARK, 1, 0, 8, INSET_BG)
	frame.add_theme_stylebox_override("panel", st)
	frame.clip_contents = true
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	frame.custom_minimum_size = Vector2(240, 170)
	var layer := Control.new()
	layer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(layer)
	var glow := TextureRect.new()
	var g := Gradient.new()
	g.set_color(0, Color(0.34, 0.22, 0.1, 0.62))
	g.set_color(1, Color(0.34, 0.22, 0.1, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.58)
	gt.fill_to = Vector2(1.0, 0.0)
	gt.width = 256
	gt.height = 256
	glow.texture = gt
	glow.stretch_mode = TextureRect.STRETCH_SCALE
	glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(glow)
	stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(stage)
	if tag != "":
		var t := UIStyle.label(Loc.t(tag).to_upper(), 11, UIStyle.BRONZE)
		t.autowrap_mode = TextServer.AUTOWRAP_OFF
		var tp := PanelContainer.new()
		tp.add_theme_stylebox_override("panel", plate(UIStyle.BRONZE_DARK, 1, 6, 3, Color(0.05, 0.04, 0.03, 0.85)))
		tp.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tp.add_child(t)
		tp.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 10)
		tp.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		layer.add_child(tp)
		frame.set_meta("tag", t)
	if hint != "":
		var h := UIStyle.label(Loc.t(hint), 12, UIStyle.MUTED)
		h.autowrap_mode = TextServer.AUTOWRAP_OFF
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 10)
		h.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		h.grow_vertical = Control.GROW_DIRECTION_BEGIN
		layer.add_child(h)
	frame.set_meta("layer", layer)
	return frame

## A button cut down to fit tight: the font and the padding smaller (the theme's own plates).
static func shrink(b: Button, font := 13, mx := 9.0, my := 4.0) -> void:
	for st in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		var base: StyleBox = b.get_theme_stylebox(st) if b.has_theme_stylebox_override(st) else UIStyle.theme().get_stylebox(st, "Button")
		if base is StyleBoxFlat:
			var c := (base as StyleBoxFlat).duplicate() as StyleBoxFlat
			c.content_margin_left = mx
			c.content_margin_right = mx
			c.content_margin_top = my
			c.content_margin_bottom = my
			b.add_theme_stylebox_override(st, c)
	b.add_theme_font_size_override("font_size", font)

## Tabs as pill buttons, ready to go into any container (a flow of the header's, a row).
## `items`: [[id, name, count_text]]. The current one is lit.
static func pill_buttons(items: Array, current: String, cb: Callable, small := false) -> Array:
	var out: Array = []
	for it in items:
		var id: String = it[0]
		var text := Loc.t(String(it[1]))
		if it.size() > 2 and String(it[2]) != "":
			text += "  " + String(it[2])
		var b := UIStyle.button(text, cb.bind(id), id == current)
		b.autowrap_mode = TextServer.AUTOWRAP_OFF
		if small:
			shrink(b)
		out.append(b)
	return out

## The pills in a flow of their own.
static func pills(items: Array, current: String, cb: Callable, small := false) -> HFlowContainer:
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 6 if small else 8)
	row.add_theme_constant_override("v_separation", 6 if small else 8)
	for b in pill_buttons(items, current, cb, small):
		row.add_child(b)
	return row

## A coin: a gold disc with a rim, as the small purse sign.
class Coin extends Control:
	func _init(px := 20) -> void:
		custom_minimum_size = Vector2(px, px)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5 - 1.0
		draw_circle(c, r, UIStyle.INK)
		draw_circle(c, r - 1.5, UIStyle.GOLD)
		draw_arc(c, r - 4.5, 0.0, TAU, 28, Color(0.55, 0.38, 0.1), 1.4)
		draw_circle(c, r * 0.28, Color(0.55, 0.38, 0.1))

## The purse: a coin and the denarii he has. A number that changes counts to it, and flashes red
## (less) or green (more).
class Purse extends HBoxContainer:
	var value := 0
	var shown := 0.0
	var num: Label
	var unit: Label
	var _tw: Tween = null

	func _init(n := 0, px := 22) -> void:
		add_theme_constant_override("separation", 8)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var c := StationKit.Coin.new(px + 4)
		add_child(c)
		num = UIStyle.label(str(n), px, UIStyle.GOLD)
		num.autowrap_mode = TextServer.AUTOWRAP_OFF
		add_child(num)
		unit = UIStyle.label(Loc.t("denarii"), maxi(11, px - 8), UIStyle.MUTED)
		unit.autowrap_mode = TextServer.AUTOWRAP_OFF
		unit.size_flags_vertical = Control.SIZE_SHRINK_END
		add_child(unit)
		value = n
		shown = float(n)

	func set_value(n: int, animate := true) -> void:
		if n == value:
			return
		var up := n > value
		value = n
		if not animate or not is_inside_tree():
			shown = float(n)
			num.text = str(n)
			return
		if _tw != null and _tw.is_valid():
			_tw.kill()
		_tw = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_tw.tween_method(func(x: float):
			shown = x
			num.text = str(int(round(x))), shown, float(n), 0.45)
		num.add_theme_color_override("font_color", GOOD if up else BAD)
		_tw.parallel().tween_property(num, "theme_override_colors/font_color", UIStyle.GOLD, 0.7)

## A bar of a value 0..1, with the part about to be added drawn lighter after it (`ghost`), and a
## tick at `cap` (what is allowed): the abilities, a weapon's four numbers.
class Bar extends Control:
	var value := 0.0
	var ghost := -1.0
	var cap := -1.0
	var fill := UIStyle.GOLD
	var back := Color(0, 0, 0, 0.55)
	var _tw: Tween = null

	func _init(h := 8.0, colour := UIStyle.GOLD) -> void:
		custom_minimum_size = Vector2(40, h)
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		fill = colour

	func set_value(v: float, animate := true) -> void:
		v = clampf(v, 0.0, 1.0)
		if not animate or not is_inside_tree():
			value = v
			queue_redraw()
			return
		if _tw != null and _tw.is_valid():
			_tw.kill()
		_tw = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_tw.tween_method(func(x: float):
			value = x
			queue_redraw(), value, v, 0.5)

	func _draw() -> void:
		var h := size.y
		draw_rect(Rect2(Vector2.ZERO, size), back)
		if ghost > value:
			draw_rect(Rect2(0, 0, size.x * clampf(ghost, 0.0, 1.0), h), Color(fill, 0.38))
		draw_rect(Rect2(0, 0, size.x * clampf(value, 0.0, 1.0), h), fill)
		if cap >= 0.0:
			var x := size.x * clampf(cap, 0.0, 1.0)
			draw_rect(Rect2(x - 1.0, -2.0, 2.0, h + 4.0), Color(UIStyle.TEXT, 0.85))

## A label pinned to a corner ("tl", "tr", "bl", "br") of a control, at a fixed size so it never
## depends on the text's own: a count on a picture, a tag.
static func corner(parent: Control, l: Control, where: String, pad := 3.0, w := 60.0, h := 18.0) -> void:
	var right := where.ends_with("r")
	var bottom := where.begins_with("b")
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.anchor_left = 1.0 if right else 0.0
	l.anchor_right = l.anchor_left
	l.anchor_top = 1.0 if bottom else 0.0
	l.anchor_bottom = l.anchor_top
	l.offset_left = -pad - w if right else pad
	l.offset_right = -pad if right else pad + w
	l.offset_top = -pad - h if bottom else pad
	l.offset_bottom = -pad if bottom else pad + h
	if l is Label:
		(l as Label).autowrap_mode = TextServer.AUTOWRAP_OFF
		(l as Label).horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if right else HORIZONTAL_ALIGNMENT_LEFT
		(l as Label).vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM if bottom else VERTICAL_ALIGNMENT_TOP
	parent.add_child(l)

## A line a ware's price: "30 denarii" in gold, in red when he cannot pay.
static func price(n: int, can: bool, size := 20) -> Label:
	var l := UIStyle.label("%d %s" % [n, Loc.t("denarii")], size, UIStyle.GOLD if can else BAD)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	return l

## A text that rises from a point and fades (a price paid, a gain): over the whole menu.
static func rise(host: Control, at: Vector2, text: String, colour := UIStyle.GOLD, size := 20) -> void:
	var l := UIStyle.label(text, size, colour)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.top_level = true
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.z_index = 50
	l.add_theme_color_override("font_outline_color", UIStyle.INK)
	l.add_theme_constant_override("outline_size", 5)
	host.add_child(l)
	l.global_position = at
	var tw := l.create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "global_position:y", at.y - 46.0, 0.9)
	tw.tween_property(l, "modulate:a", 0.0, 0.9).set_delay(0.35)
	tw.chain().tween_callback(l.queue_free)

## The frames a screen just built needs before its places are known (the containers sort at the
## end of the frame): after them every control is where the player sees it.
static func _laid_out(host: Control) -> void:
	for i in 2:
		await host.get_tree().process_frame

## A text that rises from under a control (the purse), once the screen has been laid out.
static func rise_from(host: Control, anchor: Control, text: String, colour := BAD, size := 20) -> void:
	await _laid_out(host)
	if is_instance_valid(host) and is_instance_valid(anchor) and anchor.is_inside_tree():
		rise(host, anchor.get_global_position() + Vector2(0, 40), text, colour, size)

## The reason a deed could not be done ("Not enough denarii"): a short red line that hangs under a
## control (the purse), stays a moment and goes. Nothing is said in it but the reason.
static func warn(host: Control, anchor: Control, text: String) -> void:
	if text == "":
		return
	if host.has_meta("warn") and is_instance_valid(host.get_meta("warn")):
		(host.get_meta("warn") as Control).queue_free()
	var p := PanelContainer.new()
	var st := plate(BAD, 1, 9, 6, Color(0.16, 0.05, 0.04, 0.97))
	st.shadow_color = Color(0, 0, 0, 0.45)
	st.shadow_size = 5
	p.add_theme_stylebox_override("panel", st)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.top_level = true
	p.z_index = 55
	p.modulate.a = 0.0
	var l := UIStyle.label(Loc.t(text), 14, BAD)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(l)
	host.add_child(p)
	host.set_meta("warn", p)
	await _laid_out(host)
	if not is_instance_valid(p) or not is_instance_valid(anchor) or not anchor.is_inside_tree():
		if is_instance_valid(p):
			p.queue_free()
		return
	# (Its right edge under the control's, and never off the screen; a long reason is broken into
	# lines rather than left to run off it.)
	var room: Vector2 = host.get_viewport_rect().size
	var r := anchor.get_global_rect()
	var wide := minf(460.0, room.x - 40.0)
	p.reset_size()
	if p.size.x > wide:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = wide - 18.0
		p.reset_size()
	p.global_position = Vector2(clampf(r.end.x - p.size.x, 8.0, maxf(8.0, room.x - p.size.x - 8.0)), minf(r.end.y + 4.0, maxf(8.0, room.y - p.size.y - 8.0)))
	var tw := p.create_tween()
	tw.tween_property(p, "modulate:a", 1.0, 0.12)
	tw.tween_interval(2.8)
	tw.tween_property(p, "modulate:a", 0.0, 0.5)
	tw.tween_callback(p.queue_free)

## What Menu put over a stall's screen when it was drawn again after a deed that failed ("Not
## enough denarii", a bag too full): taken off the column, for the stall to show as a warning.
static func take_msg(m: Control, v: VBoxContainer) -> void:
	if v.get_child_count() > 0 and v.get_child(0) is Label:
		var msg: Label = v.get_child(0)
		m.station_note = {"warn": msg.text}
		v.remove_child(msg)
		msg.queue_free()

## What a deed left to be shown when its screen is drawn again (Menu's station_note): the price
## that rises from the purse, or why it could not be done. Spent here.
static func show_note(host: Control, purse: Control, note: Dictionary) -> void:
	if String(note.get("rise", "")) != "":
		rise_from(host, purse, String(note.rise), BAD)
	if String(note.get("warn", "")) != "":
		warn(host, purse, String(note.warn))

## A picture flying from one place on the screen to another and shrinking into it (a ware into
## the bag): `then` is called when it lands.
static func fly(host: Control, tex: Texture2D, from: Rect2, to: Rect2, then := Callable()) -> void:
	if tex == null:
		if then.is_valid():
			then.call()
		return
	var t := TextureRect.new()
	t.texture = tex
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.top_level = true
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t.z_index = 60
	var sz := minf(64.0, maxf(32.0, minf(from.size.x, from.size.y)))
	t.size = Vector2(sz, sz)
	host.add_child(t)
	t.global_position = from.get_center() - t.size * 0.5
	var end := to.get_center() - t.size * 0.5
	var mid := (t.global_position + end) * 0.5 + Vector2(0, -70)
	var tw := t.create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(t, "global_position", mid, 0.22)
	tw.tween_property(t, "global_position", end, 0.26)
	tw.parallel().tween_property(t, "scale", Vector2(0.45, 0.45), 0.26)
	tw.tween_callback(func():
		t.queue_free()
		if then.is_valid():
			then.call())

## A soft tick for a thing chosen from a list.
static func tick() -> void:
	if Sfx:
		Sfx.play("tick", Vector3.ZERO, 0.4)

## Lifts a control a moment and settles it (the slot that took a ware).
static func pulse(c: Control) -> void:
	if not c.is_inside_tree():
		return
	c.pivot_offset = c.size * 0.5
	var tw := c.create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(c, "scale", Vector2(1.18, 1.18), 0.1)
	tw.tween_property(c, "scale", Vector2.ONE, 0.18)

## What a bag takes of a ware, for the player to read: {have, max (the most of it he can hold),
## more (how many more fit now), why}. `why` is "" while some fit, "most" when he already holds the
## most of it, "slots" when it would be a new kind and every slot of the bag is taken.
static func carry_of(kit: Dictionary, id: String) -> Dictionary:
	var have := int(kit.get(id, 0))
	var most := Throwables.stack_max(id)
	var why := ""
	if have >= most:
		why = "most"
	elif not Throwables.bag_has_room(kit, id):
		why = "slots"
	return {"have": have, "max": most, "more": 0 if why != "" else most - have, "why": why}

## The sentence for it: how many he carries and how many more fit, or why none do.
static func carry_line(c: Dictionary) -> String:
	match String(c.why):
		"most":
			return Loc.t("Carrying %d of %d · the most you can hold") % [int(c.have), int(c.max)]
		"slots":
			return Loc.t("All %d slots are taken · nothing new fits") % Throwables.BAG_KINDS
	return Loc.t("Carrying %d of %d · room for %d more") % [int(c.have), int(c.max), int(c.more)]

## The short form, for a button or a warning, when none fit ("" when some do).
static func carry_short(c: Dictionary) -> String:
	match String(c.why):
		"most":
			return Loc.t("Most you can hold (%d)") % int(c.max)
		"slots":
			return Loc.t("All %d slots are taken") % Throwables.BAG_KINDS
	return ""

## The strip of the bag: nine slots in the order the keys take them in a fight, what is in each
## and how many (Throwables.hotbar_of). `kit` is {id: count}. The slots are in the strip's meta
## "slots" (by key order), for a ware to fly into.
static func bag_strip(kit: Dictionary, size := 54) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var head := kicker("Your bag", UIStyle.BRONZE, 12)
	head.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(head)
	var bar := Throwables.hotbar_of(kit)
	var slots: Array = []
	var table: Dictionary = Data.shop.get("throwables", {})
	for i in Throwables.BAG_KINDS:
		var id := String(bar[i]) if i < bar.size() else ""
		var slot := PanelContainer.new()
		slot.custom_minimum_size = Vector2(size, size)
		slot.add_theme_stylebox_override("panel", plate(UIStyle.BRONZE if id != "" else Color(UIStyle.BRONZE_DARK, 0.5), 1, 2, 6, Color(0.09, 0.07, 0.05, 0.95) if id != "" else Color(0.05, 0.04, 0.03, 0.7)))
		var holder := Control.new()
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(holder)
		if id != "":
			var tex := TextureRect.new()
			tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tex.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
			holder.add_child(tex)
			tex.tree_entered.connect(func(): Thumbs.item(tex, id), CONNECT_ONE_SHOT)
			corner(holder, UIStyle.label("×%d" % int(kit.get(id, 0)), 12, UIStyle.GOLD), "br", 3.0, 36.0, 16.0)
			slot.tooltip_text = Loc.t(String(table.get(id, {}).get("name", id)))
		corner(holder, UIStyle.label(str(i + 1), 10, Color(UIStyle.MUTED, 0.9)), "tl", 4.0, 20.0, 14.0)
		row.add_child(slot)
		slots.append(slot)
	var note := UIStyle.label("Keys 1 to 9 take a ware in hand in the fight.", 12, UIStyle.MUTED)
	note.custom_minimum_size.x = 150
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(note)
	row.set_meta("slots", slots)
	row.set_meta("order", bar)
	return row
