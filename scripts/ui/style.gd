class_name UIStyle
## The look of the menus: an imperial one. Inscribed Roman capitals (Cinzel) on dark stone
## plates framed in gold, a warm humanist sans (Alegreya Sans) for everything read, crimson for
## the one thing to press, laurel and gold rules for ornament. Every screen takes its controls
## from theme(), so the forge, the smith, the training ground and the options all match the
## title screen.

const BG := Color(0.08, 0.06, 0.045, 0.94)
const PANEL := Color(0.075, 0.058, 0.045, 0.9)
const STONE := Color(0.115, 0.088, 0.064)
const BRONZE := Color(0.79, 0.64, 0.35)
const BRONZE_DARK := Color(0.45, 0.32, 0.16)
const TEXT := Color(0.95, 0.9, 0.8)
const MUTED := Color(0.74, 0.67, 0.56)
const RED := Color(0.55, 0.13, 0.09)
const GOLD := Color(0.88, 0.71, 0.38)
const GOLD_LIGHT := Color(1.0, 0.86, 0.55)
const INK := Color(0.14, 0.08, 0.025)

static var _theme: Theme
static var _cinzel: FontFile
static var _body := {}
static var _hooked := false

## The Roman capitals: Cinzel at weight `weight`, spaced out like an inscription. (Its small
## letters are small capitals, so "The forge" reads as an inscription too.)
static func serif(spacing := 2, weight := 700) -> Font:
	if _cinzel == null:
		_cinzel = load("res://art/fonts/Cinzel.ttf") as FontFile
	var v := FontVariation.new()
	if _cinzel:
		v.base_font = _cinzel
		v.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): weight}
	else:
		var sf := SystemFont.new()
		sf.font_names = PackedStringArray(["Cinzel", "Trajan Pro", "Times New Roman", "Liberation Serif", "Serif"])
		sf.font_weight = weight
		v.base_font = sf
	v.spacing_glyph = spacing
	return v

## The face for reading: Alegreya Sans ("regular", "medium" or "bold").
static func body(cut := "regular") -> Font:
	if not _body.has(cut):
		var f := load("res://art/fonts/AlegreyaSans-%s.ttf" % cut.capitalize()) as FontFile
		_body[cut] = f if f else ThemeDB.fallback_font
	return _body[cut]

static func _plate(bg: Color, border: Color, bw := 2) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(3)
	s.shadow_color = Color(0, 0, 0, 0.5)
	s.shadow_size = 6
	s.shadow_offset = Vector2(0, 3)
	s.content_margin_left = 22; s.content_margin_right = 22; s.content_margin_top = 12; s.content_margin_bottom = 12
	return s

## A plate for the theme's buttons: stone in a thin bronze frame, a little heavier along the
## top (light catching the edge of a carved slab).
static func _slab(bg: Color, border: Color, bw := 1) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.border_width_top = bw + 1
	s.set_corner_radius_all(2)
	s.shadow_color = Color(0, 0, 0, 0.35)
	s.shadow_size = 3
	s.shadow_offset = Vector2(0, 2)
	s.content_margin_left = 16; s.content_margin_right = 16; s.content_margin_top = 9; s.content_margin_bottom = 9
	return s

## Little drawn pictures for the theme: a check box (empty and ticked), a slider's grabber (a
## gold diamond) and the arrow of a drop-down.
static func _icon(kind: String, px := 18) -> ImageTexture:
	var img := Image.create(px, px, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c := float(px - 1) * 0.5
	for y in px:
		for x in px:
			var dx := x - c
			var dy := y - c
			match kind:
				"box", "ticked":
					if absf(dx) > c - 2.0 or absf(dy) > c - 2.0:
						img.set_pixel(x, y, GOLD if kind == "ticked" else BRONZE_DARK.lightened(0.2))
					else:
						img.set_pixel(x, y, Color(0.06, 0.045, 0.035))
					if kind == "ticked" and absf(dx) + absf(dy) < c - 3.5:
						img.set_pixel(x, y, GOLD_LIGHT)
				"diamond", "diamond_hi":
					var d := absf(dx) + absf(dy)
					if d < c:
						img.set_pixel(x, y, (GOLD_LIGHT if kind == "diamond_hi" else GOLD) if d < c - 1.5 else INK)
				"arrow":
					# A small chevron pointing down.
					if dy > -3.0 and dy < 3.0 and absf(absf(dx) - (3.0 - dy)) < 1.2:
						img.set_pixel(x, y, GOLD)
	return ImageTexture.create_from_image(img)

static func theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font = body("regular")
	t.default_font_size = 18
	# Buttons: carved stone slabs, Roman capitals; a toggled one (a chosen tab, a picked base)
	# is gilded.
	var btn := _slab(Color(STONE, 0.94), Color(0.42, 0.31, 0.16))
	var hov := _slab(Color(0.19, 0.14, 0.09, 0.97), GOLD)
	var prs := _slab(Color(0.36, 0.25, 0.1, 0.97), GOLD, 2)
	var dis := _slab(Color(0.09, 0.075, 0.06, 0.85), Color(0.25, 0.2, 0.14))
	var foc := StyleBoxFlat.new()
	foc.draw_center = false
	foc.border_color = Color(GOLD_LIGHT, 0.7)
	foc.set_border_width_all(1)
	foc.set_corner_radius_all(2)
	foc.set_expand_margin_all(2)
	var none := StyleBoxEmpty.new()
	for kind in ["Button", "OptionButton", "MenuButton", "CheckBox", "CheckButton"]:
		var plated: bool = kind == "Button" or kind == "OptionButton" or kind == "MenuButton"
		t.set_stylebox("normal", kind, btn if plated else none)
		t.set_stylebox("hover", kind, hov if plated else none)
		t.set_stylebox("pressed", kind, prs if plated else none)
		t.set_stylebox("hover_pressed", kind, prs if plated else none)
		t.set_stylebox("disabled", kind, dis if plated else none)
		t.set_stylebox("focus", kind, foc)
		t.set_color("font_color", kind, TEXT)
		t.set_color("font_hover_color", kind, Color(1, 0.96, 0.86))
		t.set_color("font_pressed_color", kind, GOLD_LIGHT)
		t.set_color("font_hover_pressed_color", kind, GOLD_LIGHT)
		t.set_color("font_focus_color", kind, Color(1, 0.96, 0.86))
		t.set_color("font_disabled_color", kind, Color(MUTED, 0.45))
		t.set_color("font_outline_color", kind, Color(0, 0, 0, 0.55))
	t.set_font("font", "Button", serif(1, 700))
	t.set_font_size("font_size", "Button", 16)
	t.set_constant("outline_size", "Button", 2)
	# Drop-downs and check boxes carry values to read: the reading face.
	t.set_font("font", "OptionButton", body("medium"))
	t.set_font_size("font_size", "OptionButton", 17)
	t.set_icon("arrow", "OptionButton", _icon("arrow", 14))
	t.set_constant("arrow_margin", "OptionButton", 10)
	for kind in ["CheckBox", "CheckButton"]:
		t.set_font("font", kind, body("medium"))
		t.set_font_size("font_size", kind, 17)
		t.set_constant("h_separation", kind, 10)
	t.set_icon("unchecked", "CheckBox", _icon("box"))
	t.set_icon("checked", "CheckBox", _icon("ticked"))
	var cb_hover := StyleBoxFlat.new()
	cb_hover.bg_color = Color(GOLD, 0.08)
	cb_hover.set_corner_radius_all(2)
	t.set_stylebox("hover", "CheckBox", cb_hover)
	t.set_stylebox("hover_pressed", "CheckBox", cb_hover)
	# The pop-up list of a drop-down, and tooltips: dark, framed in bronze.
	var pop := StyleBoxFlat.new()
	pop.bg_color = Color(0.07, 0.054, 0.04, 0.98)
	pop.border_color = BRONZE_DARK
	pop.set_border_width_all(1)
	pop.border_width_top = 2
	pop.set_corner_radius_all(2)
	pop.content_margin_left = 8; pop.content_margin_right = 8; pop.content_margin_top = 6; pop.content_margin_bottom = 6
	t.set_stylebox("panel", "PopupMenu", pop)
	var pop_hover := StyleBoxFlat.new()
	pop_hover.bg_color = Color(GOLD, 0.18)
	t.set_stylebox("hover", "PopupMenu", pop_hover)
	t.set_font("font", "PopupMenu", body("medium"))
	t.set_font_size("font_size", "PopupMenu", 17)
	t.set_color("font_color", "PopupMenu", TEXT)
	t.set_color("font_hover_color", "PopupMenu", GOLD_LIGHT)
	t.set_icon("radio_checked", "PopupMenu", _icon("diamond", 12))
	t.set_icon("checked", "PopupMenu", _icon("diamond", 12))
	t.set_stylebox("panel", "TooltipPanel", pop)
	t.set_font("font", "TooltipLabel", body("regular"))
	t.set_font_size("font_size", "TooltipLabel", 16)
	t.set_color("font_color", "TooltipLabel", TEXT)
	t.set_color("font_color", "Label", TEXT)
	# Sliders: a sunk groove, gold where it is filled, a gold diamond to drag.
	var groove := StyleBoxFlat.new()
	groove.bg_color = Color(0.04, 0.03, 0.02, 0.9)
	groove.border_color = Color(0.32, 0.23, 0.12)
	groove.set_border_width_all(1)
	groove.set_corner_radius_all(2)
	groove.content_margin_top = 3; groove.content_margin_bottom = 3
	var fill := groove.duplicate()
	fill.bg_color = Color(0.62, 0.47, 0.22)
	fill.border_color = GOLD
	t.set_stylebox("slider", "HSlider", groove)
	t.set_stylebox("grabber_area", "HSlider", fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", fill)
	t.set_icon("grabber", "HSlider", _icon("diamond", 20))
	t.set_icon("grabber_highlight", "HSlider", _icon("diamond_hi", 22))
	# Panels: a dark slab, a gold rule along the top.
	var panel := StyleBoxFlat.new()
	panel.bg_color = PANEL
	panel.border_color = BRONZE_DARK
	panel.set_border_width_all(1)
	panel.border_width_top = 3
	panel.set_corner_radius_all(4)
	panel.shadow_color = Color(0, 0, 0, 0.45)
	panel.shadow_size = 14
	panel.content_margin_left = 28; panel.content_margin_right = 28; panel.content_margin_top = 22; panel.content_margin_bottom = 22
	t.set_stylebox("panel", "PanelContainer", panel)
	var edit := StyleBoxFlat.new()
	edit.bg_color = Color(0.05, 0.04, 0.03, 0.95)
	edit.border_color = Color(0.4, 0.29, 0.15)
	edit.set_border_width_all(1)
	edit.set_corner_radius_all(2)
	edit.content_margin_left = 10; edit.content_margin_right = 10; edit.content_margin_top = 7; edit.content_margin_bottom = 7
	var edit_focus := edit.duplicate()
	edit_focus.border_color = GOLD
	t.set_stylebox("normal", "LineEdit", edit)
	t.set_stylebox("focus", "LineEdit", edit_focus)
	t.set_font("font", "LineEdit", body("medium"))
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_color("font_placeholder_color", "LineEdit", Color(MUTED, 0.6))
	t.set_color("caret_color", "LineEdit", GOLD_LIGHT)
	t.set_color("selection_color", "LineEdit", Color(GOLD, 0.35))
	# Scroll bars: a thin gold bar in a dark groove.
	for sb in ["VScrollBar", "HScrollBar"]:
		var track := StyleBoxFlat.new()
		track.bg_color = Color(0, 0, 0, 0.3)
		track.set_corner_radius_all(3)
		track.content_margin_left = 3; track.content_margin_right = 3; track.content_margin_top = 3; track.content_margin_bottom = 3
		var bar := StyleBoxFlat.new()
		bar.bg_color = Color(0.55, 0.42, 0.22, 0.9)
		bar.set_corner_radius_all(3)
		var bar_hi := bar.duplicate()
		bar_hi.bg_color = GOLD
		t.set_stylebox("scroll", sb, track)
		t.set_stylebox("grabber", sb, bar)
		t.set_stylebox("grabber_highlight", sb, bar_hi)
		t.set_stylebox("grabber_pressed", sb, bar_hi)
	var sep := StyleBoxLine.new()
	sep.color = Color(BRONZE_DARK, 0.7)
	sep.thickness = 1
	t.set_stylebox("separator", "HSeparator", sep)
	var vsep := StyleBoxLine.new()
	vsep.color = Color(BRONZE_DARK, 0.7)
	vsep.thickness = 1
	vsep.vertical = true
	t.set_stylebox("separator", "VSeparator", vsep)
	_theme = t
	return t

## A screen's heading: Roman capitals in gold over a gold rule with a diamond.
static func title(text: String, size := 44) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", serif(3, 700))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", GOLD)
	l.add_theme_color_override("font_outline_color", INK)
	l.add_theme_constant_override("outline_size", maxi(3, int(size / 9)))
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	l.add_theme_constant_override("shadow_offset_y", 3)
	l.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	l.custom_minimum_size.y = size * 1.3 + 12.0
	var rule := Ornament.new("rule", Vector2(minf(320.0, size * 7.0), 12))
	rule.anchor_top = 1.0
	rule.anchor_bottom = 1.0
	rule.offset_top = -12.0
	rule.offset_bottom = 0.0
	rule.offset_right = rule.custom_minimum_size.x
	rule.color = Color(GOLD, 0.85)
	l.add_child(rule)
	return l

## A label. One set in capitals in bronze is a section's heading ("THE ENEMY", "1 · PICK A
## BASE"): it is cut in the inscription face, spaced out, in gold.
## A gap that takes what height is left in a card, so the buttons below it sit along one line
## in every card of a row, whatever is written above them.
static func push_down(box: Container) -> void:
	var gap := Control.new()
	gap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(gap)

static func label(text: String, size := 16, color := TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if color == BRONZE and text == text.to_upper() and text.strip_edges() != "":
		l.add_theme_font_override("font", serif(3, 700))
		l.add_theme_color_override("font_color", GOLD)
		l.add_theme_font_size_override("font_size", size + 1)
	return l

static func button(text: String, cb: Callable, primary := false) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	if primary:
		# The one to press: crimson, framed in gold.
		var s := _slab(RED, GOLD)
		s.content_margin_left = 18; s.content_margin_right = 18; s.content_margin_top = 11; s.content_margin_bottom = 11
		b.add_theme_stylebox_override("normal", s)
		var h := s.duplicate()
		h.bg_color = RED.lightened(0.16)
		h.border_color = GOLD_LIGHT
		b.add_theme_stylebox_override("hover", h)
		var p := s.duplicate()
		p.bg_color = RED.darkened(0.2)
		b.add_theme_stylebox_override("pressed", p)
		b.add_theme_color_override("font_color", Color(1, 0.94, 0.82))
	return b

## The title screen's buttons: dark stone plates framed in gold; the first one is gilded and
## marked with a diamond, the others get the diamond while the mouse is on them.
static func menu_button(text: String, cb: Callable, primary := false) -> Button:
	var b := Button.new()
	var cap := text.to_upper()
	b.text = ("◆   " + cap) if primary else cap
	b.pressed.connect(cb)
	b.custom_minimum_size = Vector2(420, 56)
	b.add_theme_font_override("font", serif(3, 700))
	b.add_theme_font_size_override("font_size", 22)
	var normal := _plate(Color(0.42, 0.29, 0.11, 0.95) if primary else Color(0.075, 0.062, 0.05, 0.9), GOLD if primary else Color(0.55, 0.42, 0.22), 2)
	var hover := _plate(Color(0.52, 0.37, 0.14, 0.97) if primary else Color(0.16, 0.12, 0.08, 0.94), Color(1.0, 0.84, 0.5), 2)
	var press := _plate(Color(0.3, 0.2, 0.08, 0.97), GOLD, 2)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", press)
	b.add_theme_stylebox_override("focus", hover)
	b.add_theme_color_override("font_color", Color(1.0, 0.93, 0.78) if primary else Color(0.93, 0.86, 0.72))
	b.add_theme_color_override("font_hover_color", Color(1, 0.96, 0.85))
	b.add_theme_color_override("font_outline_color", Color(0.12, 0.07, 0.02))
	b.add_theme_constant_override("outline_size", 3)
	if not primary:
		b.mouse_entered.connect(func(): b.text = "◆   " + cap)
		b.mouse_exited.connect(func(): b.text = cap)
	return b

## The title screen's lesser entries: no plate, Roman capitals set left like a line cut in a
## list; under the mouse a band of gold light runs in from a gilded edge on the left, and a
## diamond marks it. `size` small (16) for the foot of the list (Settings, Quit).
static func menu_entry(text: String, cb: Callable, size := 22) -> Button:
	var b := Button.new()
	var cap := text.to_upper()
	b.text = cap
	b.pressed.connect(cb)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(0, 30 + size)
	b.add_theme_font_override("font", serif(3, 700))
	b.add_theme_font_size_override("font_size", size)
	var rest := StyleBoxEmpty.new()
	rest.content_margin_left = 26
	rest.content_margin_right = 18
	var band := StyleBoxTexture.new()
	band.texture = _band()
	band.content_margin_left = 26
	band.content_margin_right = 18
	for st in ["normal", "disabled"]:
		b.add_theme_stylebox_override(st, rest)
	for st in ["hover", "pressed", "hover_pressed", "focus"]:
		b.add_theme_stylebox_override(st, band)
	b.add_theme_color_override("font_color", Color(0.9, 0.84, 0.72) if size >= 20 else MUTED)
	b.add_theme_color_override("font_hover_color", GOLD_LIGHT)
	b.add_theme_color_override("font_focus_color", GOLD_LIGHT)
	b.add_theme_color_override("font_pressed_color", Color(1, 0.95, 0.8))
	b.add_theme_color_override("font_outline_color", Color(0.06, 0.035, 0.015))
	b.add_theme_constant_override("outline_size", 4)
	b.mouse_entered.connect(func(): b.text = "◆  " + cap)
	b.mouse_exited.connect(func(): b.text = cap)
	return b

static var _band_tex: GradientTexture2D
## A gilded edge on the left and gold light fading out to the right.
static func _band() -> GradientTexture2D:
	if _band_tex:
		return _band_tex
	var g := Gradient.new()
	g.set_color(0, Color(GOLD_LIGHT, 1.0))
	g.add_point(0.008, Color(GOLD_LIGHT, 1.0))
	g.add_point(0.011, Color(GOLD, 0.34))
	g.add_point(0.45, Color(GOLD, 0.12))
	g.set_color(g.get_point_count() - 1, Color(GOLD, 0.0))
	_band_tex = GradientTexture2D.new()
	_band_tex.gradient = g
	_band_tex.width = 512
	_band_tex.height = 2
	return _band_tex

## The great button of the title screen: a gilded plate, the thing to do in big capitals and,
## under it, where it leads in small ("Bout 5 · Legionary").
static func hero_button(text: String, sub: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text.to_upper()
	b.pressed.connect(cb)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(440, 84)
	b.add_theme_font_override("font", serif(3, 700))
	b.add_theme_font_size_override("font_size", 26)
	var mk := func(bg: Color, edge: Color) -> StyleBoxFlat:
		var s := _plate(bg, edge, 2)
		s.border_width_left = 6
		s.content_margin_left = 30
		s.content_margin_top = 8
		s.content_margin_bottom = 26
		s.set_corner_radius_all(2)
		return s
	b.add_theme_stylebox_override("normal", mk.call(Color(0.42, 0.27, 0.09, 0.96), GOLD))
	b.add_theme_stylebox_override("hover", mk.call(Color(0.54, 0.36, 0.12, 0.98), GOLD_LIGHT))
	b.add_theme_stylebox_override("focus", mk.call(Color(0.54, 0.36, 0.12, 0.98), GOLD_LIGHT))
	b.add_theme_stylebox_override("pressed", mk.call(Color(0.3, 0.19, 0.07, 0.98), GOLD))
	b.add_theme_color_override("font_color", Color(1.0, 0.94, 0.8))
	b.add_theme_color_override("font_hover_color", Color(1, 0.98, 0.9))
	b.add_theme_color_override("font_outline_color", Color(0.14, 0.07, 0.02))
	b.add_theme_constant_override("outline_size", 4)
	if sub != "":
		var l := Label.new()
		l.text = sub.to_upper()
		l.add_theme_font_override("font", serif(3, 700))
		l.add_theme_font_size_override("font_size", 13)
		l.add_theme_color_override("font_color", Color(1.0, 0.86, 0.6, 0.85))
		l.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
		l.offset_left = 31
		l.offset_top = -30
		l.offset_bottom = -10
		l.offset_right = 420
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(l)
	return b

## A frame laid over a panel: a gold hairline inset from its edge, a bracket at each corner with
## a diamond in it. Drawing only (Ornament "frame"); added as the panel's last child, ignored by
## its layout.
static func frame_over(p: Control, pad := Vector2(28, 22)) -> void:
	var f := Ornament.new("frame", Vector2.ZERO)
	f.pad = pad
	f.name = "Frame"
	p.add_child(f)

## Every button anywhere in the game lifts a little under the mouse and ticks when pressed.
## Hooked once, on the tree: buttons made later are caught as they are added.
static func hook(tree: SceneTree) -> void:
	if _hooked:
		return
	_hooked = true
	tree.node_added.connect(_on_node_added)

static func _on_node_added(n: Node) -> void:
	if not (n is BaseButton) or n.has_meta("ui_hooked"):
		return
	var b: BaseButton = n
	b.set_meta("ui_hooked", true)
	b.mouse_entered.connect(func(): _lift(b, 1.03))
	b.mouse_exited.connect(func(): _lift(b, 1.0))
	b.pressed.connect(func():
		Sfx.ui("tick")
		_lift(b, 0.97, 0.06))

static func _lift(b: BaseButton, to: float, back_after := 0.0) -> void:
	if not is_instance_valid(b) or not b.is_inside_tree() or b.disabled:
		return
	b.pivot_offset = b.size * 0.5
	var tw := b.create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(b, "scale", Vector2.ONE * to, 0.12 if back_after <= 0.0 else back_after)
	if back_after > 0.0:
		tw.tween_property(b, "scale", Vector2.ONE * (1.03 if b.is_hovered() else 1.0), 0.1)
