class_name Hud
extends CanvasLayer
## The fight's overlay: your body drawn part by part (bruised, cut, burning, gone), blood,
## breath and the crowd's favour as framed bars that ease and pulse, the kit in eight slots,
## the enemy's name plate with a trail on his health, the decrees, a feed of what happens, a
## banner for the big moments, the crowd's cheers for you rising off the screen, and the red at
## the edges when you are hurt.

const BRONZE := Color(0.79, 0.64, 0.35)
const BRONZE_DIM := Color(0.45, 0.32, 0.16)
const PANEL_BG := Color(0.07, 0.05, 0.035, 0.82)
const TEXT := Color(0.96, 0.91, 0.82)
const MUTED := Color(0.72, 0.65, 0.55)
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
var hurt := 0.0
var last_blood := 100.0
var popups: Control
var crosshair: Control
var blind := {}
var charge_bar: Control
var charge := 0.0
var font_title: Font

func _init(m: Match) -> void:
	match_ = m

static func _style(bg: Color, border: Color, radius := 10, width := 1) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(width)
	s.set_corner_radius_all(radius)
	s.shadow_color = Color(0, 0, 0, 0.45)
	s.shadow_size = 6
	s.content_margin_left = 14; s.content_margin_right = 14; s.content_margin_top = 10; s.content_margin_bottom = 10
	return s

func _label(text: String, size: int, color := TEXT, title := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 2)
	if title and font_title:
		l.add_theme_font_override("font", font_title)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _ready() -> void:
	var sf := SystemFont.new()
	sf.font_names = PackedStringArray(["Cinzel", "Trajan Pro", "Cormorant Garamond", "Georgia", "DejaVu Serif", "serif"])
	sf.font_weight = 700
	font_title = sf
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

func _bar(color: Color, width := 210) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(width, 14)
	c.set_meta("color", color)
	c.set_meta("value", 1.0)
	c.set_meta("shown", 1.0)
	c.draw.connect(func():
		var w := c.size.x
		var h := c.size.y
		c.draw_rect(Rect2(0, 0, w, h), Color(0.05, 0.035, 0.025, 0.9))
		var shown: float = c.get_meta("shown")
		var col: Color = c.get_meta("color")
		var low: bool = shown < 0.3
		var pulse := 0.75 + 0.25 * sin(Time.get_ticks_msec() / 120.0) if low else 1.0
		c.draw_rect(Rect2(2, 2, (w - 4) * shown, h - 4), col * pulse)
		c.draw_rect(Rect2(2, 2, (w - 4) * shown, (h - 4) * 0.4), Color(1, 1, 1, 0.12))
		for i in range(1, 10):
			c.draw_line(Vector2(w * i / 10.0, 2), Vector2(w * i / 10.0, h - 2), Color(0, 0, 0, 0.35), 1.0)
		c.draw_rect(Rect2(0, 0, w, h), BRONZE_DIM, false, 1.0))
	return c

func _build_body_panel() -> void:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _style(PANEL_BG, BRONZE_DIM, 12))
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = 18
	panel.offset_top = -190
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	panel.add_child(row)
	var fig := Control.new()
	fig.custom_minimum_size = Vector2(72, 132)
	fig.draw.connect(func(): _draw_body(fig))
	row.add_child(fig)
	body_rects["fig"] = fig
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 3)
	row.add_child(col)
	for k in [["blood", "BLOOD", Color(0.72, 0.1, 0.08)], ["stamina", "BREATH", Color(0.86, 0.68, 0.28)], ["favor", "THE CROWD", Color(0.95, 0.82, 0.4)]]:
		col.add_child(_label(k[1], 11, MUTED))
		var b := _bar(k[2])
		col.add_child(b)
		bars[k[0]] = b
	status_label = _label("", 13, MUTED)
	col.add_child(status_label)

func _draw_body(fig: Control) -> void:
	var me = match_.me
	var f = me.f if me and is_instance_valid(me.f) else null
	var t := Time.get_ticks_msec() / 1000.0
	for k in LAYOUT:
		var r: Rect2 = LAYOUT[k]
		var col := Color(0.3, 0.3, 0.3)
		var gone := false
		var burning := false
		if f:
			var p = f.by_name.get(k)
			if p:
				var hp: float = p.function()
				gone = p.severed
				col = Color(0.85, 0.2, 0.12).lerp(Color(0.92, 0.78, 0.3), clampf(hp * 2.0, 0.0, 1.0)).lerp(Color(0.35, 0.72, 0.32), clampf(hp * 2.0 - 1.0, 0.0, 1.0))
				burning = p.spots.any(func(s): return s.kind == "fire" and s.t > 0.0)
				if p.bleed > 0.8:
					col = col.lerp(Color(0.6, 0.0, 0.0), 0.25 + 0.2 * sin(t * 8.0))
		fig.draw_rect(r.grow(1.5), Color(0, 0, 0, 0.7))
		if gone:
			fig.draw_rect(r, Color(0.12, 0.1, 0.09))
			fig.draw_line(r.position, r.end, Color(0.6, 0.1, 0.08), 2.0)
			fig.draw_line(Vector2(r.end.x, r.position.y), Vector2(r.position.x, r.end.y), Color(0.6, 0.1, 0.08), 2.0)
		else:
			fig.draw_rect(r, col)
			fig.draw_rect(Rect2(r.position, Vector2(r.size.x, r.size.y * 0.35)), Color(1, 1, 1, 0.15))
			if burning:
				fig.draw_rect(r, Color(1.0, 0.5, 0.1, 0.35 + 0.25 * sin(t * 14.0)))

func _build_plate() -> void:
	plate = PanelContainer.new()
	plate.add_theme_stylebox_override("panel", _style(PANEL_BG, BRONZE_DIM, 10))
	plate.anchor_left = 0.5
	plate.anchor_right = 0.5
	plate.offset_left = -190
	plate.offset_right = 190
	plate.offset_top = 14
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(plate)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	plate.add_child(v)
	plate_name = _label("", 18, TEXT, true)
	plate_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(plate_name)
	plate_bar = Control.new()
	plate_bar.custom_minimum_size = Vector2(350, 10)
	plate_bar.draw.connect(func():
		var w := plate_bar.size.x
		plate_bar.draw_rect(Rect2(0, 0, w, 10), Color(0.05, 0.035, 0.025, 0.9))
		plate_bar.draw_rect(Rect2(1, 1, (w - 2) * plate_trail, 8), Color(0.95, 0.9, 0.8, 0.8))
		plate_bar.draw_rect(Rect2(1, 1, (w - 2) * plate_val, 8), Color(0.75, 0.12, 0.08))
		plate_bar.draw_rect(Rect2(0, 0, w, 10), BRONZE_DIM, false, 1.0))
	v.add_child(plate_bar)
	plate.visible = false

func _build_hotbar() -> void:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	h.anchor_left = 0.5
	h.anchor_right = 0.5
	h.anchor_top = 1.0
	h.anchor_bottom = 1.0
	h.offset_left = -340
	h.offset_right = 340
	h.offset_top = -84
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(h)
	for i in 9:
		var p := PanelContainer.new()
		p.custom_minimum_size = Vector2(68, 68)
		p.add_theme_stylebox_override("panel", _style(Color(0.07, 0.05, 0.035, 0.72), BRONZE_DIM, 8))
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var pic := TextureRect.new()
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		pic.custom_minimum_size = Vector2(56, 56)
		pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		p.add_child(pic)
		var num := _label(str(i + 1), 12, BRONZE)
		num.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		num.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		p.add_child(num)
		var cnt := _label("", 12, TEXT)
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
	held_label = _label("", 14, BRONZE)
	held_label.anchor_left = 0.5
	held_label.anchor_right = 0.5
	held_label.anchor_top = 1.0
	held_label.anchor_bottom = 1.0
	held_label.offset_left = -300
	held_label.offset_right = 300
	held_label.offset_top = -100
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
	banner_label = _label("", 54, BRONZE, true)
	banner_label.add_theme_color_override("font_outline_color", Color(0.12, 0.07, 0.03))
	banner_label.add_theme_constant_override("outline_size", 8)
	banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	banner_box.add_child(banner_label)
	banner_sub = _label("", 20, TEXT)
	banner_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	banner_box.add_child(banner_sub)
	banner_box.modulate.a = 0.0

func _build_corner() -> void:
	var v := VBoxContainer.new()
	v.position = Vector2(18, 16)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(v)
	decree_label = _label("", 14, BRONZE)
	v.add_child(decree_label)

## The tutorial's card at the top: the step, what to do, a tick when it is done.
func _build_tutorial() -> void:
	tut_panel = PanelContainer.new()
	tut_panel.add_theme_stylebox_override("panel", _style(Color(0.07, 0.05, 0.035, 0.86), BRONZE, 10))
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
	tut_step = _label("", 12, BRONZE)
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
		crosshair.draw_arc(Vector2.ZERO, 7.0, 0, TAU, 24, Color(1, 1, 1, 0.55), 1.5)
		crosshair.draw_circle(Vector2.ZERO, 1.5, Color(1, 1, 1, 0.8)))
	root.add_child(crosshair)
	charge_bar = Control.new()
	charge_bar.set_anchors_preset(Control.PRESET_CENTER)
	charge_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	charge_bar.position.y += 60
	charge_bar.draw.connect(func():
		charge_bar.draw_rect(Rect2(-60, 0, 120, 8), Color(0, 0, 0, 0.55))
		charge_bar.draw_rect(Rect2(-60, 0, 120.0 * charge, 8), Color(1.0, 0.84 - 0.5 * charge, 0.42 - 0.2 * charge))
		charge_bar.draw_rect(Rect2(-60, 0, 120, 8), Color(1, 1, 1, 0.4), false, 1.0))
	charge_bar.visible = false
	root.add_child(charge_bar)

# ---------- Events ----------

func add_feed(text: String) -> void:
	var p := PanelContainer.new()
	var announcer := text.contains("!") and (text.to_upper() == text or text.begins_with("FIRST") or text.contains("BOOM"))
	p.add_theme_stylebox_override("panel", _style(Color(0.06, 0.04, 0.03, 0.62), BRONZE_DIM if announcer else Color(0, 0, 0, 0), 6))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := _label(text, 15, BRONZE if announcer else TEXT)
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
		for s in slots:
			s.panel.visible = false
	match_.spectacle.events.clear()
	status_label.text = ("Stage %d · round %d of 3" % [match_.stage, match_.round + 1]) if match_.mode == "campaign" else (match_.circus_status() if match_.mode == "circus" else (match_.yard.hint if match_.yard else (match_.modes.status() if match_.modes else match_.mode.capitalize())))
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
