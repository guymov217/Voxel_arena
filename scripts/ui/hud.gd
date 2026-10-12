class_name Hud
extends CanvasLayer
const SHOW_CROWD := false
## The fight's overlay: your body drawn part by part (bruised, cut, burning, gone), blood,
## breath and the crowd's favour as framed bars that ease and pulse, the kit in eight slots,
## the enemy's name plate with a trail on his health, the decrees, a feed of what happens, a
## banner for the big moments, the crowd's cheers for you rising off the screen, and the red at
## the edges when you are hurt.

# A clean, modern look: dark glass panels with a hairline edge, soft shadows, rounded pill
# bars filled with a gradient, a warm gold accent.
const BRONZE := Color(1.0, 0.77, 0.38)          # the accent
const BRONZE_DIM := Color(1, 1, 1, 0.09)        # hairline edges
const PANEL_BG := Color(0.035, 0.04, 0.05, 0.58)
const TEXT := Color(0.97, 0.96, 0.94)
const MUTED := Color(0.7, 0.72, 0.76)
const TRACK := Color(1, 1, 1, 0.08)
const BLOOD_A := Color(0.78, 0.07, 0.16)
const BLOOD_B := Color(1.0, 0.36, 0.3)
const BREATH_A := Color(0.95, 0.55, 0.12)
const BREATH_B := Color(1.0, 0.86, 0.42)
const LAYOUT := {
	"head": Rect2(25, 0, 22, 22), "torso": Rect2(17, 24, 38, 46),
	"upperArmR": Rect2(3, 25, 12, 24), "forearmR": Rect2(1, 51, 12, 24), "upperArmL": Rect2(57, 25, 12, 24), "forearmL": Rect2(59, 51, 12, 24),
	"thighR": Rect2(18, 72, 17, 28), "shinR": Rect2(18, 102, 17, 28), "thighL": Rect2(37, 72, 17, 28), "shinL": Rect2(37, 102, 17, 28),
}

var match_: Match
var root: Control
var body_rects := {}
var bars := {}
var feed_box: VBoxContainer
var banner_box: VBoxContainer
var banner_label: Label
var banner_sub: Label
var banner_t := 0.0
var plate: PanelContainer
var plate_name: Label
var plate_bar: Control
var plate_trail := 1.0
var plate_val := 1.0
var plate_target = null
var decree_label: Label
var tut_panel: PanelContainer
var tut_title: Label
var tut_text: Label
var tut_step: Label
var status_label: Label
var slots: Array = []
var held_label: Label
var vignette: TextureRect
var sight: TextureRect
var hurt := 0.0
var last_blood := 100.0
var popups: Control
var crosshair: Control
var blind := {}
var charge_bar: Control
var charge := 0.0
var font_title: Font
var font_ui: Font
var font_caps: Font

func _init(m: Match) -> void:
	match_ = m

static func _style(bg: Color, border: Color, radius := 10, width := 1) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(width)
	s.set_corner_radius_all(radius)
	s.shadow_color = Color(0, 0, 0, 0.3)
	s.shadow_size = 14
	s.shadow_offset = Vector2(0, 4)
	s.anti_aliasing = true
	s.content_margin_left = 14; s.content_margin_right = 14; s.content_margin_top = 10; s.content_margin_bottom = 10
	return s

## A pill (a bar with round ends) from x0 to x1, its colour running from ca to cb.
static func _pill(c: CanvasItem, x0: float, x1: float, y: float, h: float, ca: Color, cb: Color) -> void:
	var r := h * 0.5
	if x1 - x0 < h:
		if x1 - x0 > 0.5:
			c.draw_circle(Vector2((x0 + x1) * 0.5, y + r), (x1 - x0) * 0.5, ca)
		return
	var a := x0 + r
	var b := x1 - r
	c.draw_polygon(PackedVector2Array([Vector2(a, y), Vector2(b, y), Vector2(b, y + h), Vector2(a, y + h)]), PackedColorArray([ca, cb, cb, ca]))
	c.draw_circle(Vector2(a, y + r), r, ca)
	c.draw_circle(Vector2(b, y + r), r, cb)

func _label(text: String, size: int, color := TEXT, title := false, caps := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", 1)
	l.add_theme_constant_override("shadow_outline_size", 4)
	if title and font_title:
		l.add_theme_font_override("font", font_title)
	elif caps and font_caps:
		l.add_theme_font_override("font", font_caps)
	elif font_ui:
		l.add_theme_font_override("font", font_ui)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _ready() -> void:
	var sf := SystemFont.new()
	sf.font_names = PackedStringArray(["Cinzel", "Trajan Pro", "Cormorant Garamond", "Georgia", "DejaVu Serif", "serif"])
	sf.font_weight = 700
	font_title = sf
	var sans := SystemFont.new()
	sans.font_names = PackedStringArray(["Inter", "Segoe UI Variable Display", "Segoe UI", "SF Pro Display", "Helvetica Neue", "Roboto", "Noto Sans", "Liberation Sans", "DejaVu Sans", "Sans-Serif"])
	sans.font_weight = 600
	sans.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	font_ui = sans
	var caps := FontVariation.new()
	caps.base_font = sans
	caps.variation_embolden = 0.35
	caps.spacing_glyph = 2
	font_caps = caps
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_build_vignette()
	_build_body_panel()
	_build_plate()
	_build_hotbar()
	_build_feed()
	_build_banner()
	_build_corner()
	_build_crosshair()
	popups = Control.new()
	popups.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	popups.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(popups)
	match_.feed.connect(add_feed)
	match_.banner.connect(show_banner)

# ---------- Building ----------

func _build_vignette() -> void:
	var g := Gradient.new()
	g.set_color(0, Color(0.5, 0.0, 0.0, 0.0))
	g.add_point(0.55, Color(0.5, 0.0, 0.0, 0.0))
	g.set_color(g.get_point_count() - 1, Color(0.55, 0.0, 0.0, 0.85))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.05, 0.5)
	gt.width = 256
	gt.height = 256
	vignette = TextureRect.new()
	vignette.texture = gt
	vignette.stretch_mode = TextureRect.STRETCH_SCALE
	vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vignette.modulate.a = 0.0
	root.add_child(vignette)
	# Sight knocked about (a blow across the eyes, the head cut or crushed): the view closes
	# in from the edges, as much as the eyes are hurt.
	var sg := Gradient.new()
	sg.set_color(0, Color(0, 0, 0, 0.0))
	sg.add_point(0.35, Color(0, 0, 0, 0.0))
	sg.set_color(sg.get_point_count() - 1, Color(0, 0, 0, 0.97))
	var st := GradientTexture2D.new()
	st.gradient = sg
	st.fill = GradientTexture2D.FILL_RADIAL
	st.fill_from = Vector2(0.5, 0.5)
	st.fill_to = Vector2(0.95, 0.5)
	st.width = 256
	st.height = 256
	sight = TextureRect.new()
	sight.texture = st
	sight.stretch_mode = TextureRect.STRETCH_SCALE
	sight.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sight.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sight.modulate.a = 0.0
	root.add_child(sight)
	# A lost eye: that side of the world goes dark (a glass eye gives most of it back).
	for side in ["R", "L"]:
		var bg := Gradient.new()
		bg.set_color(0, Color(0, 0, 0, 0.0))
		bg.add_point(0.45, Color(0, 0, 0, 0.0))
		bg.set_color(bg.get_point_count() - 1, Color(0, 0, 0, 0.96))
		var bt := GradientTexture2D.new()
		bt.gradient = bg
		bt.fill_from = Vector2(0.0 if side == "R" else 1.0, 0.5)
		bt.fill_to = Vector2(1.0 if side == "R" else 0.0, 0.5)
		var r := TextureRect.new()
		r.texture = bt
		r.stretch_mode = TextureRect.STRETCH_SCALE
		r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		r.visible = false
		root.add_child(r)
		blind[side] = r

func _bar(ca: Color, cb: Color, width := 210, height := 8) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(width, height + 6)
	c.set_meta("ca", ca)
	c.set_meta("cb", cb)
	c.set_meta("value", 1.0)
	c.set_meta("shown", 1.0)
	c.set_meta("trail", 1.0)
	c.draw.connect(func():
		var w := c.size.x
		var y := 3.0
		var h := float(height)
		var shown: float = c.get_meta("shown")
		var trail: float = c.get_meta("trail")
		var a: Color = c.get_meta("ca")
		var b: Color = c.get_meta("cb")
		var low: bool = shown < 0.3
		var pulse := 0.7 + 0.3 * sin(Time.get_ticks_msec() / 110.0) if low else 1.0
		_pill(c, 0.0, w, y, h, TRACK, TRACK)
		# What was just lost lingers a moment, pale, before it runs out.
		if trail > shown + 0.002:
			_pill(c, 0.0, w * trail, y, h, Color(1, 1, 1, 0.32), Color(1, 1, 1, 0.32))
		var tip := w * shown
		_pill(c, 0.0, tip, y, h, a * Color(1, 1, 1, pulse), a.lerp(b, shown) * Color(1, 1, 1, pulse))
		if tip > h:
			c.draw_line(Vector2(h * 0.5, y + 1.5), Vector2(tip - h * 0.5, y + 1.5), Color(1, 1, 1, 0.22), 1.0, true)
			c.draw_circle(Vector2(tip - h * 0.5, y + h * 0.5), h * 0.95, Color(b.r, b.g, b.b, 0.22 * pulse)))
	return c

func _build_body_panel() -> void:
	var panel := PanelContainer.new()
	var st := _style(PANEL_BG, BRONZE_DIM, 18)
	st.content_margin_left = 16; st.content_margin_right = 18; st.content_margin_top = 12; st.content_margin_bottom = 12
	panel.add_theme_stylebox_override("panel", st)
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = 20
	panel.offset_top = -128
	panel.offset_bottom = -20
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	panel.add_child(row)
	var fig := Control.new()
	fig.custom_minimum_size = Vector2(50, 92)
	fig.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	fig.draw.connect(func(): _draw_body(fig))
	row.add_child(fig)
	body_rects["fig"] = fig
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(col)
	for k in [["blood", "BLOOD", BLOOD_A, BLOOD_B], ["stamina", "BREATH", BREATH_A, BREATH_B], ["favor", "THE CROWD", BREATH_A, BREATH_B]]:
		var head := HBoxContainer.new()
		col.add_child(head)
		var dot := Control.new()
		dot.custom_minimum_size = Vector2(10, 10)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var dc: Color = k[3]
		dot.draw.connect(func(): dot.draw_circle(Vector2(4, 5), 3.5, dc))
		head.add_child(dot)
		var lb := _label(k[1], 11, MUTED, false, true)
		lb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(lb)
		var num := _label("100", 13, TEXT)
		num.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		head.add_child(num)
		var b := _bar(k[2], k[3])
		b.set_meta("num", num)
		col.add_child(b)
		bars[k[0]] = b
		# The crowd's favour meter is kept off the screen (the crowd still cheers and pays).
		if k[0] == "favor" and not SHOW_CROWD:
			head.visible = false
			b.visible = false
	status_label = _label("", 12, MUTED)
	col.add_child(status_label)

func _draw_body(fig: Control) -> void:
	fig.draw_set_transform(Vector2.ZERO, 0.0, Vector2(50.0 / 72.0, 92.0 / 132.0))   # the figure drawn small
	var me = match_.me
	var f = me.f if me and is_instance_valid(me.f) else null
	var t := Time.get_ticks_msec() / 1000.0
	for k in LAYOUT:
		var r: Rect2 = LAYOUT[k]
		var col := Color(0.35, 0.37, 0.4)
		var gone := false
		var burning := false
		if f:
			var p = f.by_name.get(k)
			if p:
				var hp: float = p.function()
				gone = p.severed
				col = Color(0.95, 0.2, 0.25).lerp(Color(1.0, 0.72, 0.3), clampf(hp * 2.0, 0.0, 1.0)).lerp(Color(0.86, 0.9, 0.95), clampf(hp * 2.0 - 1.0, 0.0, 1.0))
				burning = p.spots.any(func(s): return s.kind == "fire" and s.t > 0.0)
				if p.bleed > 0.8:
					col = col.lerp(Color(0.6, 0.0, 0.0), 0.25 + 0.2 * sin(t * 8.0))
		var sb := StyleBoxFlat.new()
		sb.set_corner_radius_all(int(minf(r.size.x, r.size.y) * 0.35) if k != "head" else 11)
		sb.anti_aliasing = true
		if gone:
			# Gone: only its outline is left, in red.
			sb.bg_color = Color(1, 1, 1, 0.03)
			sb.border_color = Color(1.0, 0.3, 0.32, 0.65)
			sb.set_border_width_all(2)
		else:
			sb.bg_color = col
			sb.border_color = Color(1, 1, 1, 0.18)
			sb.set_border_width_all(1)
		fig.draw_style_box(sb, r.grow(-1.0))
		if not gone and burning:
			var fl := sb.duplicate()
			fl.bg_color = Color(1.0, 0.5, 0.1, 0.35 + 0.25 * sin(t * 14.0))
			fig.draw_style_box(fl, r.grow(-1.0))

func _build_plate() -> void:
	plate = PanelContainer.new()
	var st := _style(PANEL_BG, BRONZE_DIM, 16)
	st.content_margin_left = 22; st.content_margin_right = 22; st.content_margin_top = 10; st.content_margin_bottom = 12
	plate.add_theme_stylebox_override("panel", st)
	plate.anchor_left = 0.5
	plate.anchor_right = 0.5
	plate.offset_left = -230
	plate.offset_right = 230
	plate.offset_top = 18
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(plate)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	plate.add_child(v)
	plate_name = _label("", 15, TEXT, false, true)
	plate_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(plate_name)
	plate_bar = Control.new()
	plate_bar.custom_minimum_size = Vector2(416, 8)
	plate_bar.draw.connect(func():
		var w := plate_bar.size.x
		_pill(plate_bar, 0.0, w, 0.0, 7.0, TRACK, TRACK)
		_pill(plate_bar, 0.0, w * plate_trail, 0.0, 7.0, Color(1, 1, 1, 0.38), Color(1, 1, 1, 0.38))
		_pill(plate_bar, 0.0, w * plate_val, 0.0, 7.0, BLOOD_A, BLOOD_A.lerp(BLOOD_B, plate_val))
		for q in [0.25, 0.5, 0.75]:
			plate_bar.draw_line(Vector2(w * q, 1), Vector2(w * q, 6), Color(0, 0, 0, 0.35), 1.0))
	v.add_child(plate_bar)
	plate.visible = false

func _build_hotbar() -> void:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	h.anchor_left = 0.5
	h.anchor_right = 0.5
	h.anchor_top = 1.0
	h.anchor_bottom = 1.0
	h.offset_left = -250
	h.offset_right = 250
	h.offset_top = -74
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(h)
	for i in 9:
		var p := PanelContainer.new()
		p.custom_minimum_size = Vector2(54, 54)
		var sst := _style(PANEL_BG, BRONZE_DIM, 14)
		sst.content_margin_left = 6; sst.content_margin_right = 6; sst.content_margin_top = 4; sst.content_margin_bottom = 4
		p.add_theme_stylebox_override("panel", sst)
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var pic := TextureRect.new()
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		pic.custom_minimum_size = Vector2(40, 40)
		pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		p.add_child(pic)
		var num := _label(str(i + 1), 10, MUTED, false, true)
		num.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		num.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		p.add_child(num)
		var cnt := _label("", 12, BRONZE)
		cnt.size_flags_vertical = Control.SIZE_SHRINK_END
		cnt.size_flags_horizontal = Control.SIZE_SHRINK_END
		p.add_child(cnt)
		var nm := _label("", 10, TEXT)
		nm.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		p.add_child(nm)
		h.add_child(p)
		slots.append({"panel": p, "name": nm, "pic": pic, "count": cnt, "id": ""})
	held_label = _label("", 13, BRONZE, false, true)
	held_label.anchor_left = 0.5
	held_label.anchor_right = 0.5
	held_label.anchor_top = 1.0
	held_label.anchor_bottom = 1.0
	held_label.offset_left = -300
	held_label.offset_right = 300
	held_label.offset_top = -102
	held_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(held_label)

func _build_feed() -> void:
	feed_box = VBoxContainer.new()
	feed_box.anchor_left = 1.0
	feed_box.anchor_right = 1.0
	feed_box.offset_left = -470
	feed_box.offset_right = -18
	feed_box.offset_top = 18
	feed_box.add_theme_constant_override("separation", 4)
	feed_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(feed_box)

func _build_banner() -> void:
	banner_box = VBoxContainer.new()
	banner_box.set_anchors_preset(Control.PRESET_CENTER)
	banner_box.offset_left = -520
	banner_box.offset_right = 520
	banner_box.offset_top = -190
	banner_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner_box.pivot_offset = Vector2(520, 40)
	root.add_child(banner_box)
	banner_label = _label("", 54, TEXT, true)
	banner_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.55))
	banner_label.add_theme_constant_override("outline_size", 6)
	banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	banner_box.add_child(banner_label)
	var rule := Control.new()
	rule.custom_minimum_size = Vector2(0, 10)
	rule.draw.connect(func():
		var cx := rule.size.x * 0.5
		var hw := 170.0
		rule.draw_polygon(PackedVector2Array([Vector2(cx - hw, 4), Vector2(cx, 4), Vector2(cx, 6), Vector2(cx - hw, 6)]), PackedColorArray([Color(BRONZE, 0.0), BRONZE, BRONZE, Color(BRONZE, 0.0)]))
		rule.draw_polygon(PackedVector2Array([Vector2(cx, 4), Vector2(cx + hw, 4), Vector2(cx + hw, 6), Vector2(cx, 6)]), PackedColorArray([BRONZE, Color(BRONZE, 0.0), Color(BRONZE, 0.0), BRONZE])))
	banner_box.add_child(rule)
	banner_sub = _label("", 17, BRONZE, false, true)
	banner_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	banner_box.add_child(banner_sub)
	banner_box.modulate.a = 0.0

func _build_corner() -> void:
	var v := VBoxContainer.new()
	v.position = Vector2(22, 20)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(v)
	decree_label = _label("", 12, BRONZE, false, true)
	v.add_child(decree_label)

## The tutorial's card at the top: the step, what to do, a tick when it is done.
func _build_tutorial() -> void:
	tut_panel = PanelContainer.new()
	var tst := _style(Color(0.035, 0.04, 0.05, 0.78), BRONZE_DIM, 16)
	tst.border_width_left = 4
	tst.border_color = BRONZE
	tst.content_margin_left = 22; tst.content_margin_right = 22; tst.content_margin_top = 14; tst.content_margin_bottom = 14
	tut_panel.add_theme_stylebox_override("panel", tst)
	tut_panel.anchor_left = 0.5
	tut_panel.anchor_right = 0.5
	tut_panel.offset_left = -330
	tut_panel.offset_right = 330
	tut_panel.offset_top = 96
	tut_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tut_panel.visible = false
	root.add_child(tut_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	tut_panel.add_child(v)
	tut_step = _label("", 11, BRONZE, false, true)
	v.add_child(tut_step)
	tut_title = _label("", 22, TEXT, true)
	v.add_child(tut_title)
	tut_text = _label("", 15, TEXT)
	tut_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tut_text.custom_minimum_size = Vector2(620, 0)
	v.add_child(tut_text)

func _build_crosshair() -> void:
	crosshair = Control.new()
	crosshair.set_anchors_preset(Control.PRESET_CENTER)
	crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	crosshair.draw.connect(func():
		# Four short ticks round a dot, each with a dark edge so it reads on sand and sky.
		for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
			crosshair.draw_line(d * 5.0, d * 12.0, Color(0, 0, 0, 0.45), 4.0, true)
			crosshair.draw_line(d * 5.0, d * 12.0, Color(1, 1, 1, 0.9), 2.0, true)
		crosshair.draw_circle(Vector2.ZERO, 2.4, Color(0, 0, 0, 0.45))
		crosshair.draw_circle(Vector2.ZERO, 1.4, Color(1, 1, 1, 0.95)))
	root.add_child(crosshair)
	charge_bar = Control.new()
	charge_bar.set_anchors_preset(Control.PRESET_CENTER)
	charge_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	charge_bar.position.y += 60
	charge_bar.draw.connect(func():
		_pill(charge_bar, -70.0, 70.0, 0.0, 6.0, Color(0, 0, 0, 0.45), Color(0, 0, 0, 0.45))
		_pill(charge_bar, -70.0, -70.0 + 140.0 * charge, 0.0, 6.0, BREATH_B, Color(1.0, 0.84 - 0.6 * charge, 0.42 - 0.25 * charge)))
	charge_bar.visible = false
	root.add_child(charge_bar)

# ---------- Events ----------

func add_feed(text: String) -> void:
	var p := PanelContainer.new()
	var announcer := text.contains("!") and (text.to_upper() == text or text.begins_with("FIRST") or text.contains("BOOM"))
	var fst := _style(Color(0.035, 0.04, 0.05, 0.5), Color(0, 0, 0, 0), 10)
	fst.shadow_size = 6
	fst.content_margin_left = 12; fst.content_margin_right = 12; fst.content_margin_top = 5; fst.content_margin_bottom = 5
	if announcer:
		fst.border_width_right = 3
		fst.border_color = BRONZE
	p.add_theme_stylebox_override("panel", fst)
	p.size_flags_horizontal = Control.SIZE_SHRINK_END
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := _label(text, 14, BRONZE if announcer else TEXT, false, announcer)
	l.size_flags_horizontal = Control.SIZE_SHRINK_END
	# One line, as wide as it needs; a long one wraps within the feed's width.
	if l.get_theme_font("font").get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x > 420.0:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(420, 0)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	p.add_child(l)
	feed_box.add_child(p)
	while feed_box.get_child_count() > 6:
		var old := feed_box.get_child(0)
		feed_box.remove_child(old)
		old.queue_free()
	p.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(p, "modulate:a", 1.0, 0.2)
	tw.tween_interval(5.0)
	tw.tween_property(p, "modulate:a", 0.0, 1.0)
	tw.tween_callback(func(): if is_instance_valid(p): p.queue_free())

func show_banner(text: String, sub: String) -> void:
	banner_label.text = text
	banner_sub.text = sub
	banner_t = 3.5
	banner_box.scale = Vector2(1.25, 1.25)
	banner_box.modulate.a = 0.0
	var tw := create_tween().set_parallel()
	tw.tween_property(banner_box, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(banner_box, "modulate:a", 1.0, 0.25)

func popup(text: String) -> void:
	var l := _label(text, 22, Color(1.0, 0.86, 0.45), true)
	l.position = get_viewport().get_visible_rect().size * Vector2(0.5, 0.62) + Vector2(randf_range(-60, 40), 0)
	popups.add_child(l)
	var tw := create_tween().set_parallel()
	tw.tween_property(l, "position:y", l.position.y - 90.0, 1.6)
	tw.tween_property(l, "modulate:a", 0.0, 1.6).set_delay(0.6)
	tw.chain().tween_callback(l.queue_free)

# ---------- Each frame ----------

func _ease_bar(key: String, v: float, dt: float) -> void:
	var b: Control = bars[key]
	var shown: float = b.get_meta("shown")
	shown += (clampf(v, 0.0, 1.0) - shown) * minf(1.0, dt * 6.0)
	b.set_meta("shown", shown)
	var trail: float = b.get_meta("trail")
	b.set_meta("trail", shown if shown > trail else maxf(shown, trail - dt * 0.35))
	var num: Label = b.get_meta("num", null)
	if num:
		num.text = str(roundi(clampf(v, 0.0, 1.0) * 100.0))
		num.add_theme_color_override("font_color", BLOOD_B if v < 0.3 else TEXT)
	b.queue_redraw()

func _process(dt: float) -> void:
	var ch := float(match_.last_local_inp.get("charging", 0.0)) if match_.last_local_inp is Dictionary else 0.0
	charge_bar.visible = ch > 0.0
	if ch != charge:
		charge = ch
		charge_bar.queue_redraw()
	if banner_t > 0.0:
		banner_t -= dt
		if banner_t < 0.6:
			banner_box.modulate.a = clampf(banner_t / 0.6, 0.0, 1.0)
	var me = match_.me
	var f = me.f if me and is_instance_valid(me.f) else null
	if f:
		_ease_bar("blood", f.blood / 100.0, dt)
		for s in blind:
			var ey: String = f.body.get("eyes", {}).get(s, "") if f.body is Dictionary else ""
			blind[s].visible = ey != ""
			blind[s].modulate.a = 1.0 if ey == "lost" else 0.25
		_ease_bar("stamina", f.stamina / 100.0, dt)
		_ease_bar("favor", match_.spectacle.get_favor(f) / 100.0, dt)
		# Hurt: the red at the edges flares with every loss of blood, and beats when it runs low.
		if f.blood < last_blood - 0.4:
			hurt = minf(1.0, hurt + (last_blood - f.blood) * 0.08 + 0.15)
		last_blood = f.blood
		hurt = maxf(0.0, hurt - dt * 1.2)
		var low := clampf((35.0 - f.blood) / 35.0, 0.0, 1.0)
		var beat := low * (0.35 + 0.25 * maxf(0.0, sin(Time.get_ticks_msec() / 1000.0 * 6.0)))
		vignette.modulate.a = clampf(maxf(hurt * 0.8, beat) + (0.6 if not f.alive else 0.0), 0.0, 1.0)
		sight.modulate.a = clampf(float(f.eye_hurt) * 0.95 + float(f.concussion) * 0.3, 0.0, 0.95)
		body_rects.fig.queue_redraw()
		# The crowd's cheers for you.
		for ev in match_.spectacle.events:
			if ev.f == f and ev.amount > 0:
				popup("+%d %s" % [ev.amount, ev.reason])
		var inv: Dictionary = me.get("inventory", {})
		var bar := Throwables.hotbar_of(inv)
		for i in slots.size():
			var s: Dictionary = slots[i]
			if i < bar.size():
				var id: String = bar[i]
				if s.id != id:
					s.id = id
					s.pic.texture = null
					Thumbs.item(s.pic, id)
				s.count.text = "×%d" % int(inv[id])
				# The name shows until the picture is made (and always without a renderer).
				s.name.text = "" if s.pic.texture else String(Data.shop.throwables[id].name)
				s.panel.tooltip_text = String(Data.shop.throwables[id].name)
				s.panel.visible = true
			else:
				s.panel.visible = false
		var held = f.held_item
		held_label.text = ("In hand: %s · hold F to aim, let go to throw" % String(held.type).trim_prefix("pot_").capitalize()) if held else ""
	else:
		vignette.modulate.a = 0.0
		sight.modulate.a = 0.0
		for s in slots:
			s.panel.visible = false
	match_.spectacle.events.clear()
	status_label.text = (("%sBout %d · %s" % ["Co-op · " if match_.coop else "", match_.stage, match_.stage_info.get("foe_name", "")]) if match_.stage_info.get("duel", false) else ("Stage %d · round %d of 3" % [match_.stage, match_.round + 1])) if match_.mode == "campaign" else (match_.circus_status() if match_.mode == "circus" else (match_.yard.hint if match_.yard else (match_.modes.status() if match_.modes else match_.mode.capitalize())))
	decree_label.text = ("Decrees: " + " · ".join(match_.dec.names)) if not match_.dec.names.is_empty() else ""
	if match_.tut:
		if tut_panel == null:
			_build_tutorial()
		var tv: Dictionary = match_.tut.view()
		tut_panel.visible = true
		tut_step.text = "TUTORIAL · STEP %d OF %d" % [mini(int(tv.step) + 1, int(tv.total)), int(tv.total)]
		tut_title.text = ("✔ " if tv.get("ok", false) else "") + String(tv.title)
		tut_title.add_theme_color_override("font_color", Color(0.6, 0.95, 0.5) if tv.get("ok", false) else TEXT)
		tut_text.text = String(tv.text)
	# The enemy in front of you.
	var t = match_.nearest_enemy(me) if me else null
	if t and is_instance_valid(t.f):
		plate.visible = true
		var val: float = t.f.vitality()
		if plate_target != t.f:
			plate_target = t.f
			plate_trail = val
		plate_val = val
		plate_trail = maxf(plate_val, plate_trail - dt * 0.25)
		plate_name.text = ("BOSS · " if t.get("boss", false) else "") + t.f.display_name
		plate_name.add_theme_color_override("font_color", Color(0.95, 0.6, 0.4) if t.get("boss", false) else TEXT)
		plate_bar.queue_redraw()
	else:
		plate.visible = false
