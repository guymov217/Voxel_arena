class_name Hud
extends CanvasLayer
const SHOW_CROWD := false
## The fight's overlay, in dark iron, blood red and aged gold: your body drawn voxel by voxel
## (every piece knocked off it, every limb gone, bruises, cuts, fire), BLOOD and BREATH as iron
## gauges with their icons and numbers that pulse when they run low, the kit in riveted slots,
## the enemy's plate with a trail on his health, where you are (the arena and the bout, the
## yard and its stall), what you can do right now (a keycap and a word: pick up, talk, throw),
## a feed of what happens, a banner for the big moments, the crowd's cheers for you rising off
## the screen, the red at the edges when you are hurt, and the panel knocked when you are hit.
## It scales with the window (a 1080p layout, kept legible from 720p to 4K).

# ---------- The palette ----------
const IRON := Color(0.075, 0.07, 0.065, 0.88)          # the plates
const IRON_DEEP := Color(0.035, 0.032, 0.03, 0.92)
const IRON_EDGE := Color(0.36, 0.32, 0.27, 0.9)        # the lip of a plate
const IRON_RIVET := Color(0.5, 0.45, 0.38)
const GOLD := Color(0.82, 0.66, 0.32)                  # aged gold: titles, numbers, keycaps
const GOLD_DIM := Color(0.58, 0.46, 0.22)
const GOLD_PALE := Color(0.95, 0.86, 0.6)
const BLOOD := Color(0.6, 0.06, 0.07)
const BLOOD_BRIGHT := Color(0.93, 0.2, 0.13)
const BREATH := Color(0.55, 0.62, 0.66)                # breath: cold steel grey-blue
const BREATH_BRIGHT := Color(0.85, 0.92, 0.95)
const TEXT := Color(0.93, 0.89, 0.8)                   # parchment
const MUTED := Color(0.6, 0.56, 0.5)
const TRACK := Color(0, 0, 0, 0.45)

## The figure: each part's box on a 72x132 canvas (voxels are drawn inside each box).
const LAYOUT := {
	"head": Rect2(25, 0, 22, 22), "torso": Rect2(17, 24, 38, 46),
	"upperArmR": Rect2(3, 25, 12, 24), "forearmR": Rect2(1, 51, 12, 24), "upperArmL": Rect2(57, 25, 12, 24), "forearmL": Rect2(59, 51, 12, 24),
	"thighR": Rect2(18, 72, 17, 28), "shinR": Rect2(18, 102, 17, 28), "thighL": Rect2(37, 72, 17, 28), "shinL": Rect2(37, 102, 17, 28),
}
const FIG_W := 72.0
const FIG_H := 132.0

var match_: Match
var root: Control
var body_panel: PanelContainer
var fig: Control
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
var plate_flash := 0.0
var decree_label: Label
var place_label: Label
var place_sub: Label
var tut_panel: PanelContainer
var tut_title: Label
var tut_text: Label
var tut_step: Label
var prompt_box: HBoxContainer
var prompt_keys: Array = []
var prompt_label: Label
var slots: Array = []
var held_label: Label
var vignette: TextureRect
var sight: TextureRect
var hurt := 0.0
var knock := 0.0            # the body plate knocked by a blow
var last_blood := 100.0
var popups: Control
var crosshair: Control
var blind := {}
var charge_bar: Control
var charge_hint: Label
var charge := 0.0
var font_title: Font
var font_ui: Font
var font_caps: Font
var columns := {}           # part -> {w, h, cells: PackedFloat32Array (alive share per column)}
var columns_t := 0.0
var columns_dirty := true
var ui_scale := 1.0
var hands_seen := []          # what was in each hand last frame, and when that changed
var hands_t := -100.0

func _init(m: Match) -> void:
	match_ = m

# ---------- Styles ----------

## An iron plate: dark, a lighter lip, square-shouldered (a small radius), a shadow under it.
static func _plate(bg: Color = IRON, edge: Color = IRON_EDGE, radius := 3, width := 1) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = edge
	s.set_border_width_all(width)
	s.set_corner_radius_all(radius)
	s.shadow_color = Color(0, 0, 0, 0.45)
	s.shadow_size = 10
	s.shadow_offset = Vector2(0, 3)
	s.anti_aliasing = true
	s.content_margin_left = 14; s.content_margin_right = 14; s.content_margin_top = 10; s.content_margin_bottom = 10
	return s

## Rivets in the corners of a plate, and a gold hairline inside the lip.
static func _rivets(c: Control, gold_line := true) -> void:
	var w := c.size.x
	var h := c.size.y
	if gold_line:
		c.draw_rect(Rect2(3.5, 3.5, w - 7.0, h - 7.0), Color(GOLD_DIM, 0.35), false, 1.0)
	for p in [Vector2(7, 7), Vector2(w - 7, 7), Vector2(7, h - 7), Vector2(w - 7, h - 7)]:
		c.draw_circle(p, 2.6, Color(0, 0, 0, 0.5))
		c.draw_circle(p, 2.0, IRON_RIVET)
		c.draw_circle(p + Vector2(-0.6, -0.6), 0.8, Color(1, 1, 1, 0.35))

## A gauge from x0 to x1: a flat bar with a bevelled lip, its colour running ca -> cb.
static func _gauge(c: CanvasItem, x0: float, x1: float, y: float, h: float, ca: Color, cb: Color) -> void:
	if x1 - x0 < 0.5:
		return
	c.draw_polygon(PackedVector2Array([Vector2(x0, y), Vector2(x1, y), Vector2(x1, y + h), Vector2(x0, y + h)]), PackedColorArray([ca, cb, cb, ca]))
	c.draw_line(Vector2(x0, y + 1.0), Vector2(x1, y + 1.0), Color(1, 1, 1, 0.18), 1.0)
	c.draw_line(Vector2(x0, y + h - 1.0), Vector2(x1, y + h - 1.0), Color(0, 0, 0, 0.3), 1.0)

func _label(text: String, size: int, color := TEXT, title := false, caps := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
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

## A keycap: the key's name on a small iron cap with a gold face.
func _keycap(text: String) -> PanelContainer:
	var p := PanelContainer.new()
	var st := _plate(IRON_DEEP, GOLD_DIM, 4, 1)
	st.shadow_size = 4
	st.shadow_offset = Vector2(0, 2)
	st.content_margin_left = 8; st.content_margin_right = 8; st.content_margin_top = 2; st.content_margin_bottom = 3
	p.add_theme_stylebox_override("panel", st)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var l := _label(text, 14, GOLD_PALE, false, true)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.custom_minimum_size = Vector2(16, 0)
	p.add_child(l)
	p.set_meta("label", l)
	return p

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
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
	caps.variation_embolden = 0.3
	caps.spacing_glyph = 2
	font_caps = caps
	root = Control.new()
	# Pinned top left and sized by hand (_fit scales it to the window): full-rect anchors
	# fought the size set there, and Godot warned of it every round.
	root.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_build_vignette()
	_build_body_panel()
	_build_plate()
	_build_hotbar()
	_build_prompt()
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
	_fit()

## The layout is drawn for 1080p and scaled to the window, never smaller than three quarters.
func _fit() -> void:
	var vs := get_viewport().get_visible_rect().size
	var k := clampf(minf(vs.y / 1080.0, vs.x / 1920.0), 0.75, 1.6)
	if absf(k - ui_scale) > 0.01 or root.size != vs / k:
		ui_scale = k
		root.scale = Vector2(k, k)
		root.size = vs / k

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
	# Sight knocked about: the view closes in from the edges, as much as the eyes are hurt.
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

## A gauge row: the icon, the word, the number; the bar under them.
func _bar(key: String, word: String, ca: Color, cb: Color, col: VBoxContainer) -> void:
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	col.add_child(head)
	var icon := Control.new()
	icon.custom_minimum_size = Vector2(14, 14)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.draw.connect(func(): _draw_icon(icon, key, cb))
	head.add_child(icon)
	var lb := _label(word, 11, MUTED, false, true)
	lb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(lb)
	var num := _label("100", 15, GOLD_PALE)
	num.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	head.add_child(num)
	var c := Control.new()
	c.custom_minimum_size = Vector2(230, 14)
	c.set_meta("ca", ca)
	c.set_meta("cb", cb)
	c.set_meta("shown", 1.0)
	c.set_meta("trail", 1.0)
	c.set_meta("num", num)
	c.set_meta("word", lb)
	c.set_meta("icon", icon)
	c.draw.connect(func():
		var w := c.size.x
		var y := 2.0
		var h := 9.0
		var shown: float = c.get_meta("shown")
		var trail: float = c.get_meta("trail")
		var a: Color = c.get_meta("ca")
		var b: Color = c.get_meta("cb")
		var low: bool = shown < 0.25
		var pulse := 0.65 + 0.35 * sin(Time.get_ticks_msec() / 90.0) if low else 1.0
		# The channel the gauge runs in.
		c.draw_rect(Rect2(0, y - 1, w, h + 2), TRACK)
		c.draw_rect(Rect2(0, y - 1, w, h + 2), Color(IRON_EDGE, 0.5), false, 1.0)
		# What was just lost lingers, pale, before it runs out.
		if trail > shown + 0.002:
			_gauge(c, 0.0, w * trail, y, h, Color(1, 0.9, 0.8, 0.3), Color(1, 0.9, 0.8, 0.3))
		var tip := w * shown
		_gauge(c, 0.0, tip, y, h, a * Color(1, 1, 1, pulse), a.lerp(b, shown) * Color(1, 1, 1, pulse))
		# Quarter marks.
		for q in [0.25, 0.5, 0.75]:
			c.draw_line(Vector2(w * q, y), Vector2(w * q, y + h), Color(0, 0, 0, 0.4), 1.0)
		if low:
			c.draw_rect(Rect2(-1, y - 2, w + 2, h + 4), Color(BLOOD_BRIGHT if key == "blood" else GOLD, 0.5 * pulse), false, 1.5))
	col.add_child(c)
	bars[key] = c
	if key == "favor" and not SHOW_CROWD:
		head.visible = false
		c.visible = false

## The gauges' icons: a drop of blood; a pair of lungs for the breath; a laurel for the crowd.
func _draw_icon(c: Control, key: String, col: Color) -> void:
	match key:
		"blood":
			var pts := PackedVector2Array()
			for i in 16:
				var a := TAU * i / 16.0
				pts.append(Vector2(7.0 + 4.2 * sin(a), 9.0 - 3.8 * cos(a)))
			c.draw_colored_polygon(pts, col)
			c.draw_colored_polygon(PackedVector2Array([Vector2(7, 0), Vector2(10.6, 7), Vector2(3.4, 7)]), col)
			c.draw_circle(Vector2(5.4, 8.6), 1.1, Color(1, 1, 1, 0.45))
		"stamina":
			for s in [-1.0, 1.0]:
				var pts := PackedVector2Array()
				for i in 12:
					var a := PI * i / 11.0
					pts.append(Vector2(7.0 + s * (1.4 + 2.8 * sin(a)), 3.0 + 10.0 * (i / 11.0)))
				pts.append(Vector2(7.0 + s * 1.4, 13.0))
				c.draw_colored_polygon(pts, col)
			c.draw_line(Vector2(7, 0.5), Vector2(7, 7), col, 1.6)
		_:
			c.draw_arc(Vector2(7, 8), 5.5, PI * 0.1, PI * 0.9, 12, col, 2.0)
			c.draw_arc(Vector2(7, 8), 5.5, PI * 1.1, PI * 1.9, 12, col, 2.0)

func _build_body_panel() -> void:
	body_panel = PanelContainer.new()
	var st := _plate()
	st.content_margin_left = 16; st.content_margin_right = 18; st.content_margin_top = 12; st.content_margin_bottom = 12
	body_panel.add_theme_stylebox_override("panel", st)
	body_panel.anchor_top = 1.0
	body_panel.anchor_bottom = 1.0
	body_panel.offset_left = 22
	body_panel.offset_top = -170
	body_panel.offset_bottom = -22
	body_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	body_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body_panel.draw.connect(func(): _rivets(body_panel))
	root.add_child(body_panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	body_panel.add_child(row)
	fig = Control.new()
	fig.custom_minimum_size = Vector2(72, 132)
	fig.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	fig.draw.connect(_draw_body)
	row.add_child(fig)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 3)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(col)
	_bar("blood", "BLOOD", BLOOD, BLOOD_BRIGHT, col)
	_bar("stamina", "BREATH", BREATH, BREATH_BRIGHT, col)
	_bar("favor", "THE CROWD", GOLD_DIM, GOLD, col)
	var status := _label("", 11, MUTED, false, true)
	status.name = "Status"
	col.add_child(status)
	bars["status"] = status

## The columns of each part: for every (x, y) of its fine grid, the share of voxels still
## there through its depth (1 whole, 0 a hole right through). Rebuilt when he loses voxels.
func _rebuild_columns(f) -> void:
	columns.clear()
	for k in LAYOUT:
		var p = f.by_name.get(k)
		if p == null:
			continue
		var w: int = p.grid.x
		var h: int = p.grid.y
		var tot := PackedInt32Array()
		var live := PackedInt32Array()
		tot.resize(w * h)
		live.resize(w * h)
		for i in p.fx.size():
			var ci: int = p.fy[i] * w + p.fx[i]
			tot[ci] += 1
			if p.alive[i]:
				live[ci] += 1
		var cells := PackedFloat32Array()
		cells.resize(w * h)
		for ci in w * h:
			cells[ci] = (float(live[ci]) / float(tot[ci])) if tot[ci] > 0 else -1.0
		columns[k] = {"w": w, "h": h, "cells": cells}

## The figure: every part drawn as its own voxels (seen from the front, each column of them a
## cell: whole, chipped, or a hole), so every piece knocked off him shows where it was. A part
## cut off lies a little apart from its stump, outlined in red; a lost one is an empty outline;
## one hanging by a thread is drawn askew; fire flickers over a burning one.
func _draw_body() -> void:
	var me = match_.me
	var f = me.f if me and is_instance_valid(me.f) else null
	var t := Time.get_ticks_msec() / 1000.0
	var shake := Vector2(sin(t * 60.0), cos(t * 47.0)) * knock * 3.0
	for k in LAYOUT:
		var r: Rect2 = LAYOUT[k]
		var p = f.by_name.get(k) if f else null
		var base := Color(0.3, 0.28, 0.26)
		var gone := false
		var missing := false
		var hanging := false
		var burning := false
		var fn := 1.0
		if p:
			fn = p.function()
			gone = p.severed
			missing = p.missing
			hanging = p.hanging
			burning = p.spots.any(func(s): return s.kind == "fire" and s.t > 0.0)
			# Whole: parchment; hurt: through gold to blood red.
			base = BLOOD_BRIGHT.lerp(GOLD, clampf(fn * 2.0, 0.0, 1.0)).lerp(Color(0.86, 0.82, 0.74), clampf(fn * 2.0 - 1.0, 0.0, 1.0))
			if p.bleed > 0.8:
				base = base.lerp(BLOOD, 0.3 + 0.2 * sin(t * 8.0))
		var off := shake
		if gone and not missing:
			# Cut off: it lies out from the body, a little apart, where it fell.
			var side := -1.0 if r.position.x + r.size.x * 0.5 < FIG_W * 0.5 else 1.0
			off += Vector2(side * 6.0, 5.0)
		var rr := Rect2(r.position + off, r.size)
		if missing:
			fig.draw_rect(rr.grow(-1.0), Color(1, 1, 1, 0.03))
			fig.draw_rect(rr.grow(-1.0), Color(BLOOD_BRIGHT, 0.5), false, 1.5)
			continue
		var col = columns.get(k)
		if col == null or p == null:
			fig.draw_rect(rr.grow(-1.0), base)
			continue
		var w: int = col.w
		var h: int = col.h
		var cw := rr.size.x / float(w)
		var ch := rr.size.y / float(h)
		var cells: PackedFloat32Array = col.cells
		var tilt := 0.0
		if hanging:
			tilt = 0.25 + 0.08 * sin(t * 5.0)
		for y in h:
			for x in w:
				var v := cells[y * w + x]
				if v < 0.0:
					continue
				var c := base
				if v <= 0.0:
					c = Color(0.12, 0.02, 0.02)          # a hole right through
				elif v < 0.999:
					c = base.darkened(0.25 + 0.45 * (1.0 - v))   # chipped
				if gone:
					c = Color(c.r * 0.55, c.g * 0.35, c.b * 0.35, 0.8)
				var px := rr.position.x + x * cw + (float(h - 1 - y) * tilt)
				var py := rr.position.y + (h - 1 - y) * ch
				fig.draw_rect(Rect2(px, py, cw + 0.4, ch + 0.4), c)
		if gone:
			fig.draw_rect(rr, Color(BLOOD_BRIGHT, 0.75), false, 1.0)
		elif burning:
			fig.draw_rect(rr.grow(-1.0), Color(1.0, 0.55, 0.12, 0.35 + 0.25 * sin(t * 14.0)))
		else:
			fig.draw_rect(rr, Color(0, 0, 0, 0.35), false, 1.0)

func _build_plate() -> void:
	plate = PanelContainer.new()
	var st := _plate()
	st.content_margin_left = 24; st.content_margin_right = 24; st.content_margin_top = 8; st.content_margin_bottom = 12
	plate.add_theme_stylebox_override("panel", st)
	plate.anchor_left = 0.5
	plate.anchor_right = 0.5
	plate.offset_left = -240
	plate.offset_right = 240
	plate.offset_top = 18
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.draw.connect(func(): _rivets(plate))
	root.add_child(plate)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	plate.add_child(v)
	plate_name = _label("", 16, GOLD, true)
	plate_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(plate_name)
	plate_bar = Control.new()
	plate_bar.custom_minimum_size = Vector2(432, 10)
	plate_bar.draw.connect(func():
		var w := plate_bar.size.x
		plate_bar.draw_rect(Rect2(0, 0, w, 9), TRACK)
		_gauge(plate_bar, 0.0, w * plate_trail, 1.0, 7.0, Color(1, 0.9, 0.8, 0.35), Color(1, 0.9, 0.8, 0.35))
		var fl := Color(1, 1, 1, plate_flash * 0.5)
		_gauge(plate_bar, 0.0, w * plate_val, 1.0, 7.0, BLOOD.lerp(Color.WHITE, plate_flash * 0.5), BLOOD.lerp(BLOOD_BRIGHT, plate_val).lerp(Color.WHITE, plate_flash * 0.5))
		for q in [0.25, 0.5, 0.75]:
			plate_bar.draw_line(Vector2(w * q, 1), Vector2(w * q, 8), Color(0, 0, 0, 0.4), 1.0)
		plate_bar.draw_rect(Rect2(0, 0, w, 9), Color(IRON_EDGE, 0.6), false, 1.0)
		if plate_flash > 0.0:
			plate_bar.draw_rect(Rect2(0, 0, w, 9), fl, false, 1.0))
	v.add_child(plate_bar)
	plate.visible = false

func _build_hotbar() -> void:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	h.anchor_left = 0.5
	h.anchor_right = 0.5
	h.anchor_top = 1.0
	h.anchor_bottom = 1.0
	h.offset_left = -260
	h.offset_right = 260
	h.offset_top = -78
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(h)
	for i in 9:
		var p := PanelContainer.new()
		p.custom_minimum_size = Vector2(56, 56)
		var sst := _plate(IRON_DEEP, IRON_EDGE, 3)
		sst.shadow_size = 6
		sst.content_margin_left = 6; sst.content_margin_right = 6; sst.content_margin_top = 4; sst.content_margin_bottom = 4
		p.add_theme_stylebox_override("panel", sst)
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var pic := TextureRect.new()
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		pic.custom_minimum_size = Vector2(42, 42)
		pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		p.add_child(pic)
		var num := _label(str(i + 1), 10, GOLD, false, true)
		num.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		num.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		p.add_child(num)
		var cnt := _label("", 12, GOLD_PALE)
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
	held_label = _label("", 13, GOLD, false, true)
	held_label.anchor_left = 0.5
	held_label.anchor_right = 0.5
	held_label.anchor_top = 1.0
	held_label.anchor_bottom = 1.0
	held_label.offset_left = -300
	held_label.offset_right = 300
	held_label.offset_top = -104
	held_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(held_label)

## The prompt: what the nearest thing lets you do, as keycaps and a word, above the hotbar.
func _build_prompt() -> void:
	prompt_box = HBoxContainer.new()
	prompt_box.add_theme_constant_override("separation", 8)
	prompt_box.anchor_left = 0.5
	prompt_box.anchor_right = 0.5
	prompt_box.anchor_top = 1.0
	prompt_box.anchor_bottom = 1.0
	prompt_box.offset_left = -300
	prompt_box.offset_right = 300
	prompt_box.offset_top = -140
	prompt_box.offset_bottom = -108
	prompt_box.alignment = BoxContainer.ALIGNMENT_CENTER
	prompt_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(prompt_box)
	for i in 3:
		var kc := _keycap("G")
		kc.visible = false
		prompt_box.add_child(kc)
		prompt_keys.append(kc)
	prompt_label = _label("", 15, TEXT)
	prompt_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	prompt_box.add_child(prompt_label)
	prompt_box.visible = false

func _build_feed() -> void:
	feed_box = VBoxContainer.new()
	feed_box.anchor_left = 1.0
	feed_box.anchor_right = 1.0
	feed_box.offset_left = -480
	feed_box.offset_right = -20
	feed_box.offset_top = 20
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
	banner_label = _label("", 56, GOLD_PALE, true)
	banner_label.add_theme_color_override("font_outline_color", Color(0.1, 0.02, 0.02, 0.8))
	banner_label.add_theme_constant_override("outline_size", 7)
	banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	banner_box.add_child(banner_label)
	var rule := Control.new()
	rule.custom_minimum_size = Vector2(0, 12)
	rule.draw.connect(func():
		var cx := rule.size.x * 0.5
		var hw := 190.0
		rule.draw_polygon(PackedVector2Array([Vector2(cx - hw, 5), Vector2(cx, 5), Vector2(cx, 7), Vector2(cx - hw, 7)]), PackedColorArray([Color(BLOOD_BRIGHT, 0.0), BLOOD_BRIGHT, BLOOD_BRIGHT, Color(BLOOD_BRIGHT, 0.0)]))
		rule.draw_polygon(PackedVector2Array([Vector2(cx, 5), Vector2(cx + hw, 5), Vector2(cx + hw, 7), Vector2(cx, 7)]), PackedColorArray([BLOOD_BRIGHT, Color(BLOOD_BRIGHT, 0.0), Color(BLOOD_BRIGHT, 0.0), BLOOD_BRIGHT]))
		rule.draw_circle(Vector2(cx, 6), 3.0, GOLD))
	banner_box.add_child(rule)
	banner_sub = _label("", 17, GOLD, false, true)
	banner_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	banner_box.add_child(banner_sub)
	banner_box.modulate.a = 0.0

## Top left: where you are and what this fight is, and the Emperor's decrees under it.
func _build_corner() -> void:
	var v := VBoxContainer.new()
	v.position = Vector2(22, 18)
	v.add_theme_constant_override("separation", 2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(v)
	place_label = _label("", 18, GOLD, true)
	v.add_child(place_label)
	place_sub = _label("", 12, MUTED, false, true)
	v.add_child(place_sub)
	decree_label = _label("", 12, BLOOD_BRIGHT, false, true)
	v.add_child(decree_label)

## The tutorial's card at the top: the step, what to do, a tick when it is done.
func _build_tutorial() -> void:
	tut_panel = PanelContainer.new()
	var tst := _plate(IRON, IRON_EDGE, 3)
	tst.border_width_left = 4
	tst.border_color = GOLD
	tst.content_margin_left = 22; tst.content_margin_right = 22; tst.content_margin_top = 14; tst.content_margin_bottom = 14
	tut_panel.add_theme_stylebox_override("panel", tst)
	tut_panel.anchor_left = 0.5
	tut_panel.anchor_right = 0.5
	tut_panel.offset_left = -330
	tut_panel.offset_right = 330
	tut_panel.offset_top = 100
	tut_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tut_panel.visible = false
	root.add_child(tut_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	tut_panel.add_child(v)
	tut_step = _label("", 11, GOLD, false, true)
	v.add_child(tut_step)
	tut_title = _label("", 22, GOLD_PALE, true)
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
			crosshair.draw_line(d * 5.0, d * 12.0, Color(0, 0, 0, 0.5), 4.0, true)
			crosshair.draw_line(d * 5.0, d * 12.0, Color(GOLD_PALE, 0.9), 2.0, true)
		crosshair.draw_circle(Vector2.ZERO, 2.4, Color(0, 0, 0, 0.5))
		crosshair.draw_circle(Vector2.ZERO, 1.4, Color(1, 1, 1, 0.95)))
	root.add_child(crosshair)
	charge_bar = Control.new()
	charge_bar.set_anchors_preset(Control.PRESET_CENTER)
	charge_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	charge_bar.position.y += 60
	charge_bar.draw.connect(func():
		charge_bar.draw_rect(Rect2(-70, 0, 140, 7), TRACK)
		_gauge(charge_bar, -70.0, -70.0 + 140.0 * charge, 0.0, 7.0, GOLD_DIM, GOLD.lerp(BLOOD_BRIGHT, charge))
		charge_bar.draw_rect(Rect2(-70, 0, 140, 7), Color(IRON_EDGE, 0.6), false, 1.0))
	charge_bar.visible = false
	root.add_child(charge_bar)
	charge_hint = Label.new()
	charge_hint.set_anchors_preset(Control.PRESET_CENTER)
	charge_hint.position = Vector2(-150, 70)
	charge_hint.size = Vector2(300, 20)
	charge_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	charge_hint.add_theme_font_size_override("font_size", 12)
	charge_hint.add_theme_color_override("font_color", Color(0.85, 0.8, 0.7, 0.85))
	charge_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	charge_hint.visible = false
	root.add_child(charge_hint)

# ---------- Events ----------

func add_feed(text: String) -> void:
	var p := PanelContainer.new()
	var announcer := text.contains("!") and (text.to_upper() == text or text.begins_with("FIRST") or text.contains("BOOM"))
	var fst := _plate(Color(0.05, 0.045, 0.04, 0.72), Color(0, 0, 0, 0), 3, 0)
	fst.shadow_size = 5
	fst.content_margin_left = 12; fst.content_margin_right = 12; fst.content_margin_top = 5; fst.content_margin_bottom = 5
	fst.border_width_right = 3
	fst.border_color = BLOOD_BRIGHT if announcer else GOLD_DIM
	p.add_theme_stylebox_override("panel", fst)
	p.size_flags_horizontal = Control.SIZE_SHRINK_END
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := _label(text, 14, GOLD_PALE if announcer else TEXT, false, announcer)
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
	tw.tween_callback(p.queue_free)   # (a bound call: dropped with p if it goes first, no error)

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
	var l := _label(text, 22, GOLD_PALE, true)
	l.position = root.size * Vector2(0.5, 0.62) + Vector2(randf_range(-60, 40), 0)
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
	var low := v < 0.25
	if num:
		num.text = str(roundi(clampf(v, 0.0, 1.0) * 100.0))
		num.add_theme_color_override("font_color", BLOOD_BRIGHT if low else GOLD_PALE)
	var word: Label = b.get_meta("word", null)
	if word:
		var crit := "BLOOD · CRITICAL" if key == "blood" else "WINDED"
		var base := "BLOOD" if key == "blood" else ("BREATH" if key == "stamina" else "THE CROWD")
		word.text = crit if low and key != "favor" else base
		word.add_theme_color_override("font_color", BLOOD_BRIGHT if low and key != "favor" else MUTED)
	b.queue_redraw()
	var icon: Control = b.get_meta("icon", null)
	if icon:
		icon.queue_redraw()

## The key for an action, as the player has it bound.
func _key(id: String) -> String:
	var code := ""
	if match_.input and match_.input.bindings.has(id):
		code = str(match_.input.bindings[id])
	else:
		code = str(Data.controls.get("defaults", {}).get(id, ""))
	return PlayerInput.label_of(code) if code != "" else id.to_upper()

## What the nearest thing lets you do right now: a man in your hands, a pot readied, a stall,
## a weapon or a limb lying within reach.
func _prompt_for(f) -> Array:
	if not f.alive:
		return []
	if f.dying > 0.0:
		return [[], "At death's door: a friend can lift you · %d s" % ceili(f.dying)]
	var me_e = match_.entity_of(f)
	var dying_friend = match_.dying_friend_of(me_e) if me_e else null
	if dying_friend != null:
		return [["revive"], "Hold to lift %s" % dying_friend.f.display_name]
	var mnd = match_.social.mind_of(me_e) if me_e and match_.social else null
	if mnd != null:
		return [["throw"], "%s hangs in your grip · hurl him where you look · %d s" % [mnd.t.display_name, ceili(float(mnd.left))]]
	var croc = f.get_meta("rolled_by") if f.has_meta("rolled_by") else null
	if croc != null and is_instance_valid(croc) and croc.hug != null and croc.hug.get("target") == f:
		return [["back", "forward"], "Pull away to prise its jaws open · strike its head"]
	if f.holding != null:
		if f.holding.limb != null:
			return [["throw"], "Throw the %s" % String(f.holding.limb.label).to_lower()]
		return [["throw", "shove", "grab"], "Throw · slam · let go"]
	if f.held_item != null:
		return [["throw"], "Hold to aim, let go to throw the %s · its number again puts it away" % String(f.held_item.type).trim_prefix("pot_").replace("_", " ")]
	var pos: Vector3 = f.torso.global_position
	if match_.yard:
		var at := Yard.station_at(pos)
		if at != "":
			var st: Dictionary = Yard.STATIONS[at]
			if st.has("npc"):
				return [["kick"], "Talk to %s" % String(st.npc.name)]
			if at == "gate":
				return [["kick"], "Into the arena: the next fight"]
			return [["kick"], String(st.label)]
	var hand_r: Vector3 = f.hand_world("R")
	var hand_l: Vector3 = f.hand_world("L")
	var best = null
	var bd := 1.1
	for w in match_.combat.loose_weapons:
		if not is_instance_valid(w) or w.holder != null:
			continue
		var d := minf(w.global_position.distance_to(hand_r), w.global_position.distance_to(hand_l))
		if d < bd:
			bd = d
			best = w
	if best != null and (f.weapons.R == null or f.weapons.L == null):
		return [["grab"], "Pick up the %s" % String(best.design.get("name", "weapon")).to_lower()]
	for o in match_.entities:
		for part in o.f.parts:
			if part.severed and not part.missing and part.wielder == null and part.alive_count > 0 and part.part_name != "torso":
				var d := minf(part.global_position.distance_to(hand_r), part.global_position.distance_to(hand_l))
				if d < 0.9:
					return [["grab"], "Grab the %s" % String(part.label).to_lower()]
	# A weapon just taken in hand: for a few seconds, how to put both hands on it or change hands.
	# (Not the weapons a fighter walks in with: only a change in his hands.)
	var now_held := [f, f.weapons.R, f.weapons.L, f.two_handed]
	if now_held != hands_seen:
		if not hands_seen.is_empty() and hands_seen[0] == f:
			hands_t = Time.get_ticks_msec() / 1000.0
		hands_seen = now_held
	if Time.get_ticks_msec() / 1000.0 - hands_t < 6.0:
		var w = f.weapons.R if f.weapons.R else f.weapons.L
		if w and not w.is_shield and w.design.get("chain") == null:
			if f.two_handed:
				return [["grip"], "One hand"]
			return [["grip", "swap"], "Both hands · swap hands"]
	return []

func _set_prompt(p: Array) -> void:
	if p.is_empty():
		prompt_box.visible = false
		return
	prompt_box.visible = true
	var keys: Array = p[0]
	for i in prompt_keys.size():
		var kc: PanelContainer = prompt_keys[i]
		if i < keys.size():
			kc.visible = true
			(kc.get_meta("label") as Label).text = _key(keys[i])
		else:
			kc.visible = false
	prompt_label.text = String(p[1])

## Where you are: the arena and the bout, the yard and the stall you stand at, the training ground.
func _place() -> void:
	var m := match_
	match m.mode:
		"campaign":
			place_label.text = "THE ARENA"
			var sub := ""
			if m.stage_info.get("duel", false):
				sub = "%sBOUT %d · %s" % ["CO-OP · " if m.coop else "", m.stage, String(m.stage_info.get("foe_name", "")).to_upper()]
			else:
				sub = "STAGE %d · ROUND %d OF 3" % [m.stage, m.round + 1]
			place_sub.text = sub
		"yard":
			place_label.text = "THE LUDUS YARD"
			var at := Yard.station_at(m.me.f.torso.global_position) if m.me and is_instance_valid(m.me.f) else ""
			place_sub.text = String(Yard.STATIONS[at].label).to_upper() if at != "" else "THE GATE LEADS TO THE ARENA"
		"training":
			place_label.text = "THE TRAINING GROUND"
			place_sub.text = ""
		"circus":
			place_label.text = "THE ARENA"
			place_sub.text = m.circus_status().to_upper()
		_:
			place_label.text = "THE ARENA"
			place_sub.text = (m.modes.status() if m.modes else m.mode.capitalize()).to_upper()

var bench_hid := false   # hidden while a forge was open, to come back when it goes

func _process(dt: float) -> void:
	if not is_instance_valid(match_):
		return
	# Never over the forge or the armour bench (back from trying a weapon in the arena, the yard's
	# HUD came up again over the forge, hid it and took the keys).
	# Nor over the kill cam: the replay is seen as it was, not through the eyes of the man in it
	# (a blow to the head left his blinded eye and swimming sight over the whole clip).
	var bench_up: bool = match_.get("killcam") != null and is_instance_valid(match_.killcam) and match_.killcam.playing
	for b in get_tree().get_nodes_in_group("bench"):
		if b is CanvasItem and (b as CanvasItem).is_visible_in_tree():
			bench_up = true
			break
	if bench_up:
		if visible:
			visible = false
			bench_hid = true
		return
	if bench_hid:
		bench_hid = false
		visible = true
	if get_tree().paused:
		return   # (it runs through a pause only to keep off the forge; the rest waits as before)
	_fit()
	var ch := float(match_.last_local_inp.get("charging", 0.0)) if match_.last_local_inp is Dictionary else 0.0
	charge_bar.visible = ch > 0.0
	charge_hint.visible = ch > 0.0
	if ch > 0.0 and match_.me and is_instance_valid(match_.me.f):
		var fh = match_.me.f
		var hand := ""
		if fh.held_item != null:
			hand = String(fh.held_item.type).trim_prefix("pot_").replace("_", " ")
		else:
			var side: String = Social.throw_side(fh, match_.last_local_inp)
			var w = fh.weapons.get(side)
			hand = ("%s hand: %s" % ["right" if side == "R" else "left", String(w.design.get("name", "weapon")).to_lower()]) if w else "nothing in hand"
		charge_hint.text = "%s · left click: the other hand · right click: call it off" % hand
	if ch != charge:
		charge = ch
		charge_bar.queue_redraw()
	if banner_t > 0.0:
		banner_t -= dt
		if banner_t < 0.6:
			banner_box.modulate.a = clampf(banner_t / 0.6, 0.0, 1.0)
	knock = maxf(0.0, knock - dt * 4.0)
	plate_flash = maxf(0.0, plate_flash - dt * 3.0)
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
		# Hurt: the red at the edges flares with every loss of blood and beats when it runs low;
		# the body plate is knocked.
		if f.blood < last_blood - 0.4:
			hurt = minf(1.0, hurt + (last_blood - f.blood) * 0.08 + 0.15)
			knock = minf(1.0, knock + 0.5 + (last_blood - f.blood) * 0.05)
			columns_dirty = true
		last_blood = f.blood
		hurt = maxf(0.0, hurt - dt * 1.2)
		var low := clampf((35.0 - f.blood) / 35.0, 0.0, 1.0)
		var beat := low * (0.35 + 0.25 * maxf(0.0, sin(Time.get_ticks_msec() / 1000.0 * 6.0)))
		vignette.modulate.a = clampf(maxf(hurt * 0.8, beat) + (0.6 if not f.alive else 0.0), 0.0, 1.0)
		sight.modulate.a = clampf(float(f.eye_hurt) * 0.95 + float(f.concussion) * 0.3, 0.0, 0.95)
		# The figure's voxels: rebuilt when he loses some, and now and then regardless.
		columns_t -= dt
		if columns_dirty or columns_t <= 0.0:
			_rebuild_columns(f)
			columns_dirty = false
			columns_t = 0.5
		fig.queue_redraw()
		body_panel.queue_redraw()
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
				s.name.text = "" if s.pic.texture else String(Data.shop.throwables[id].name)
				s.panel.tooltip_text = String(Data.shop.throwables[id].name)
				s.panel.visible = true
			else:
				s.panel.visible = false
		var held = f.held_item
		held_label.text = ("IN HAND: %s" % String(held.type).trim_prefix("pot_").replace("_", " ").to_upper()) if held else ""
		_set_prompt(_prompt_for(f))
	else:
		vignette.modulate.a = 0.0
		sight.modulate.a = 0.0
		for s in slots:
			s.panel.visible = false
		_set_prompt([])
	match_.spectacle.events.clear()
	_place()
	var status: Label = bars.status
	status.text = ""   # (the yard's place is in the corner and what to do there in the prompt: the plate stays the fight's size)
	decree_label.text = ("DECREES: " + " · ".join(match_.dec.names)).to_upper() if not match_.dec.names.is_empty() else ""
	if match_.tut:
		if tut_panel == null:
			_build_tutorial()
		var tv: Dictionary = match_.tut.view()
		tut_panel.visible = true
		tut_step.text = "TUTORIAL · STEP %d OF %d" % [mini(int(tv.step) + 1, int(tv.total)), int(tv.total)]
		tut_title.text = ("✔ " if tv.get("ok", false) else "") + String(tv.title)
		tut_title.add_theme_color_override("font_color", Color(0.6, 0.95, 0.5) if tv.get("ok", false) else GOLD_PALE)
		tut_text.text = String(tv.text)
	# The enemy in front of you.
	var t = match_.nearest_enemy(me) if me else null
	if t and is_instance_valid(t.f):
		plate.visible = true
		var val: float = t.f.vitality()
		if plate_target != t.f:
			plate_target = t.f
			plate_trail = val
		if val < plate_val - 0.01:
			plate_flash = 1.0
		plate_val = val
		plate_trail = maxf(plate_val, plate_trail - dt * 0.25)
		plate_name.text = ("☠ " if t.get("boss", false) else "") + t.f.display_name.to_upper()
		plate_name.add_theme_color_override("font_color", BLOOD_BRIGHT if t.get("boss", false) else GOLD)
		plate_bar.queue_redraw()
		plate.queue_redraw()
	else:
		plate.visible = false
