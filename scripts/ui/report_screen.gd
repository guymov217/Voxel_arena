class_name ReportScreen
extends ScrollContainer
## The bout's report on the menu's panel (user, #346: an eye-catching statistics report at the end of every fight): what BoutReport made of the bout, drawn in the menus' imperial look.
## A party (two men or more): the awards as medals with the most valuable man's crown, then a table, a column to a man and a row to each measure, every figure a bar that fills and
## counts up, the leader of each row in gold, the money each won from the crowd at the foot. Alone: a tile to each measure, the figures counting up. The purse under it.
## Drawing only: the numbers are BoutReport's. The screen plays itself (rows come up one after another) when it enters the tree.

## A colour to each man of the party, in the order they are listed (not gold: that is the leader's).
const COLORS := [Color("d9675f"), Color("5fa8d9"), Color("78c97f"), Color("b58ad9"), Color("e08f5a"), Color("5fcfc4"), Color("d96fb0"), Color("a9a59a")]
const ICON_OF := {"kills": "skull", "dmg": "sword", "big": "hammer", "cut": "slash", "hurt": "shield", "limbs": "bone", "lifts": "cross", "fav": "star", "earned": "coin"}
const AWARD_ICON := {"kills": "skull", "dmg": "sword", "big": "hammer", "cut": "slash", "hurt": "shield", "lifts": "cross", "fav": "star", "earned": "coin"}
const ALWAYS := ["kills", "dmg", "hurt"]   # (the rows kept when nobody did any of it: the rest are left out)
const LABEL_W := 200
const ROW_GAP := 0.08    # (s) between one row's coming up and the next's
const MEDAL_GAP := 0.07  # (s) and one medal's and the next's
const FILL_S := 0.85     # (s) a bar takes to fill

const RESERVE := 330.0   # (px of the window's height left to the rest of the screen: the title, the button, the panel's margins)

var report: Dictionary = {}
var me := ""
var body := VBoxContainer.new()   # everything on the report; it scrolls when the window is too low for it
var _rows: Array = []     # [control, ...] each revealed in turn (the table's rows, the tiles, the purse)
var _medal_rows: Array = []   # the medals, each revealed in turn beside the table's rows
var _bars: Array = []     # the StatBars, filled as their row comes up
var _counts: Array = []   # the CountLabels

func _init(rep: Dictionary, my_name := "") -> void:
	report = rep
	me = my_name
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 12)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(body)
	_build()

func _ready() -> void:
	_play()
	_fit()

## As high as what is on it, or as high as the window leaves room for (and then it scrolls): once the rows have their width and their lines are counted.
func _fit() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var room := maxf(260.0, get_viewport_rect().size.y - RESERVE)
	custom_minimum_size.y = minf(body.get_combined_minimum_size().y + 4.0, room)

# ---------- Building ----------

func _build() -> void:
	var rows: Array = report.get("rows", []) if report.get("rows") is Array else []
	var purse: Dictionary = report.get("purse", {}) if report.get("purse") is Dictionary else {}
	if rows.is_empty():
		return
	var line := UIStyle.label(Loc.t("Bout time %s") % BoutReport.clock(float(report.get("secs", 0.0))), 15, UIStyle.MUTED)
	line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(line)
	if rows.size() >= 2:
		_party(rows)
	else:
		_alone(rows[0])
	if bool(report.get("won", false)) and int(purse.get("each", 0)) > 0:
		var p := UIStyle.label(_purse_text(purse, rows.size()), 18, UIStyle.GOLD_LIGHT)
		p.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		body.add_child(p)
		_rows.append(p)

## What every man takes home, and what it is made of (as the banner said it at the bout's end).
func _purse_text(purse: Dictionary, men: int) -> String:
	var s := (Loc.t("%d denarii to each of you") if men > 1 else Loc.t("%d denarii")) % int(purse.get("each", 0))
	if int(purse.get("crowd", 0)) > 0:
		s += Loc.t(", %d of them the crowd's") % int(purse.crowd)
	if int(purse.get("fav", 0)) > 0 and String(purse.get("favourite", "")) != "":
		s += Loc.t(", %d for its favourite, %s") % [int(purse.fav), String(purse.favourite)]
	return s

## Which measures are shown: every one somebody has any of, and the ALWAYS ones.
func _shown(rows: Array) -> Array:
	var out := []
	for m in BoutReport.MEASURES:
		var any := false
		for r in rows:
			if int(r.get(m[0], 0)) > 0:
				any = true
		if any or ALWAYS.has(m[0]):
			out.append(m)
	return out

func _color_of(i: int) -> Color:
	return COLORS[i % COLORS.size()]

# ---------- A party: medals, then the table ----------

func _party(rows: Array) -> void:
	var mvp := BoutReport.mvp(rows)
	var awards := BoutReport.awards(rows)
	if mvp != "" or not awards.is_empty():
		body.add_child(_medals(mvp, awards))
	var shown := _shown(rows)
	var n := rows.size()
	var g := GridContainer.new()
	g.columns = n + 1
	g.add_theme_constant_override("h_separation", 10)
	g.add_theme_constant_override("v_separation", 6)
	g.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(g)
	var col_w := clampi(int(820.0 / float(n)), 96, 210)
	# The men's names along the top.
	g.add_child(Control.new())
	for i in n:
		g.add_child(_header(rows[i], i, col_w, String(rows[i].name) == mvp))
	# A row to each measure: its name, then a bar for each of them.
	for m in shown:
		var key: String = m[0]
		var top := 1.0
		for r in rows:
			top = maxf(top, float(r.get(key, 0)))
		var lead := BoutReport.leaders(rows, key)
		var label := _measure_label(key, m[1])
		g.add_child(label)
		var cells := [label]
		for i in n:
			var v := float(rows[i].get(key, 0))
			var bar := StatBar.new(v, top, _color_of(i), lead.has(String(rows[i].name)), "+" if key == "earned" else "")
			bar.custom_minimum_size = Vector2(col_w, 28)
			g.add_child(bar)
			_bars.append(bar)
			cells.append(bar)
		_rows.append(cells)

func _measure_label(key: String, text: String) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	h.custom_minimum_size = Vector2(LABEL_W, 28)
	h.add_child(Icon.new(ICON_OF.get(key, "star"), UIStyle.BRONZE, 22))
	var l := UIStyle.label(Loc.t(text), 16, UIStyle.MUTED)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(l)
	return h

## A man's name over his column: a stripe of his colour, his name, whether he is still standing; the crown on the most valuable.
func _header(r: Dictionary, i: int, w: int, crowned: bool) -> Control:
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(w, 50)
	box.add_theme_constant_override("separation", 2)
	var stripe := ColorRect.new()
	stripe.color = _color_of(i)
	stripe.custom_minimum_size = Vector2(w, 4)
	box.add_child(stripe)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 6)
	if crowned:
		top.add_child(Icon.new("crown", UIStyle.GOLD_LIGHT, 22))
	var name_l := UIStyle.label(String(r.name), 17, UIStyle.TEXT if String(r.name) != me else UIStyle.GOLD_LIGHT)
	name_l.autowrap_mode = TextServer.AUTOWRAP_OFF
	name_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_l.custom_minimum_size.x = w - (28 if crowned else 0)
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(name_l)
	box.add_child(top)
	var st := UIStyle.label(Loc.t("Standing") if bool(r.get("alive", false)) else Loc.t("Fallen"), 13, UIStyle.MUTED if bool(r.get("alive", false)) else Color(0.85, 0.45, 0.4))
	st.autowrap_mode = TextServer.AUTOWRAP_OFF
	box.add_child(st)
	return box

## The awards: the crown of the most valuable man first, then a medal for each measure's leader.
func _medals(mvp: String, awards: Array) -> Control:
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 8)
	flow.add_theme_constant_override("v_separation", 6)
	flow.alignment = FlowContainer.ALIGNMENT_CENTER
	flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var items := []
	if mvp != "":
		items.append(Medal.new("crown", Loc.t("MVP"), [mvp], true))
	for a in awards:
		items.append(Medal.new(AWARD_ICON.get(a[0], "star"), Loc.t(String(a[1])), a[2], false))
	for it in items:
		flow.add_child(it)
		_medal_rows.append([it])
	return flow

# ---------- Alone: a tile to each measure ----------

func _alone(r: Dictionary) -> void:
	var name_l := UIStyle.label(String(r.name), 22, UIStyle.GOLD_LIGHT)
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(name_l)
	var shown := _shown([r])
	var g := GridContainer.new()
	g.columns = 3
	g.add_theme_constant_override("h_separation", 14)
	g.add_theme_constant_override("v_separation", 14)
	g.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(g)
	for m in shown:
		var key: String = m[0]
		var tile := _tile(key, Loc.t(m[1]), float(r.get(key, 0)), "+" if key == "earned" else "")
		tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		g.add_child(tile)
		_rows.append([tile, _counts[_counts.size() - 1]])

func _tile(key: String, text: String, value: float, prefix: String) -> Control:
	var pc := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0.045)
	sb.border_color = Color(UIStyle.BRONZE_DARK, 0.9)
	sb.set_border_width_all(1)
	sb.border_width_left = 4
	sb.border_color = UIStyle.GOLD
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	pc.add_theme_stylebox_override("panel", sb)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	pc.add_child(h)
	h.add_child(Icon.new(ICON_OF.get(key, "star"), UIStyle.GOLD, 40))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	var num := CountLabel.new(value, prefix)
	num.add_theme_font_override("font", UIStyle.serif(1, 700))
	num.add_theme_font_size_override("font_size", 34)
	num.add_theme_color_override("font_color", UIStyle.GOLD_LIGHT)
	num.add_theme_color_override("font_outline_color", UIStyle.INK)
	num.add_theme_constant_override("outline_size", 4)
	v.add_child(num)
	_counts.append(num)
	var cap := UIStyle.label(text, 14, UIStyle.MUTED)
	cap.autowrap_mode = TextServer.AUTOWRAP_OFF
	v.add_child(cap)
	h.add_child(v)
	return pc

# ---------- The playing of it ----------

## The medals come up one after another, and beside them the rows of the table; the bars fill and count up as their row comes.
func _play() -> void:
	if _rows.is_empty() and _medal_rows.is_empty():
		return
	var tw := create_tween().set_parallel(true)
	var tm := 0.1
	for cells in _medal_rows:
		_reveal(tw, cells, tm)
		tm += MEDAL_GAP
	var t := 0.25
	for cells in _rows:
		_reveal(tw, cells, t)
		t += ROW_GAP

func _reveal(tw: Tween, cells, at: float) -> void:
	var list: Array = cells if cells is Array else [cells]
	for c in list:
		if c is CanvasItem and not (c is CountLabel):
			(c as CanvasItem).modulate.a = 0.0
			tw.tween_property(c, "modulate:a", 1.0, 0.22).set_delay(at)
		if c is StatBar or c is CountLabel:
			tw.tween_property(c, "progress", 1.0, FILL_S).set_delay(at + 0.1).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

## At once, whole: the report as it ends (a click on it, a hurry).
func finish() -> void:
	for b in _bars:
		(b as StatBar).progress = 1.0
	for k in _counts:
		(k as CountLabel).progress = 1.0
	for cells in _rows + _medal_rows:
		for c in (cells if cells is Array else [cells]):
			if c is CanvasItem:
				(c as CanvasItem).modulate.a = 1.0

# ---------- Drawn things ----------

## A figure that counts up to its value as `progress` goes to 1.
class CountLabel extends Label:
	var value := 0.0
	var prefix := ""
	var progress := 0.0:
		set(v):
			progress = clampf(v, 0.0, 1.0)
			text = prefix + str(int(round(value * progress)))
	func _init(v := 0.0, pre := "") -> void:
		value = v
		prefix = pre
		text = pre + "0"

## A bar of a table: a slab, filled in his colour to `value` of `top` (gold when he leads), the figure on it.
class StatBar extends Control:
	var value := 0.0
	var top := 1.0
	var color := Color.WHITE
	var lead := false
	var prefix := ""
	var progress := 0.0:
		set(v):
			progress = clampf(v, 0.0, 1.0)
			queue_redraw()
	func _init(v := 0.0, t := 1.0, c := Color.WHITE, l := false, pre := "") -> void:
		value = v
		top = maxf(1.0, t)
		color = c
		lead = l
		prefix = pre
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r, Color(1, 1, 1, 0.055))
		draw_rect(r, Color(UIStyle.BRONZE_DARK, 0.55), false, 1.0)
		var frac := clampf(value / top, 0.0, 1.0) * progress
		if frac > 0.0:
			var f := Rect2(r.position + Vector2(1, 1), Vector2(maxf(0.0, (r.size.x - 2.0) * frac), r.size.y - 2.0))
			var base := UIStyle.GOLD if lead else color.darkened(0.18)
			draw_rect(f, Color(base, 0.92 if lead else 0.78))
			draw_rect(Rect2(f.position, Vector2(f.size.x, f.size.y * 0.42)), Color(1, 1, 1, 0.16 if lead else 0.09))
			if lead:
				draw_rect(Rect2(f.position + Vector2(f.size.x - 3.0, 0), Vector2(3.0, f.size.y)), Color(UIStyle.GOLD_LIGHT, 1.0))
		var font := UIStyle.body("bold")
		var txt := prefix + str(int(round(value * progress)))
		var at := Vector2(10.0, size.y * 0.5 + 7.0)
		draw_string_outline(font, at, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 19, 4, UIStyle.INK)
		draw_string(font, at, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 19, Color(1.0, 0.96, 0.86))

## A medal: a gold ring with the picture of what it is for, its title in the inscription face, the one or the ones who took it.
class Medal extends VBoxContainer:
	func _init(kind := "star", title := "", names: Array = [], crown := false) -> void:
		add_theme_constant_override("separation", 3)
		custom_minimum_size = Vector2(108, 0)
		var ring := MedalRing.new(kind, crown)
		ring.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		add_child(ring)
		var t := UIStyle.label(title, 12, UIStyle.GOLD)
		t.add_theme_font_override("font", UIStyle.serif(1, 700))
		t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		add_child(t)
		var n := UIStyle.label(" & ".join(PackedStringArray(names)), 14, UIStyle.TEXT)
		n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		add_child(n)

class MedalRing extends Control:
	var kind := "star"
	var crown := false
	func _init(k := "star", c := false) -> void:
		kind = k
		crown = c
		custom_minimum_size = Vector2(48, 48)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		var c := size * 0.5
		var rad := minf(size.x, size.y) * 0.5 - 2.0
		draw_circle(c, rad, Color(UIStyle.STONE, 1.0))
		draw_arc(c, rad, 0.0, TAU, 48, UIStyle.GOLD_LIGHT if crown else UIStyle.GOLD, 3.0 if crown else 2.5, true)
		draw_arc(c, rad - 5.0, 0.0, TAU, 48, Color(UIStyle.BRONZE_DARK, 0.9), 1.0, true)
		ReportScreen.draw_icon(self, kind, Rect2(c - Vector2.ONE * rad * 0.56, Vector2.ONE * rad * 1.12), UIStyle.GOLD_LIGHT if crown else UIStyle.GOLD)

## A small picture of a measure.
class Icon extends Control:
	var kind := "star"
	var color := Color.WHITE
	func _init(k := "star", c := Color.WHITE, px := 22) -> void:
		kind = k
		color = c
		custom_minimum_size = Vector2(px, px)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		ReportScreen.draw_icon(self, kind, Rect2(Vector2.ZERO, size), color)

## A picture in `rect` of `ci`, in one colour (what the measure is of: a skull for the kills, a sword for the damage...). Plain shapes, no glyphs: the fonts have none of them.
static func draw_icon(ci: CanvasItem, kind: String, rect: Rect2, col: Color) -> void:
	var s := rect.size
	var p := func(x: float, y: float) -> Vector2: return rect.position + Vector2(x * s.x, y * s.y)
	var w := maxf(1.5, minf(s.x, s.y) * 0.1)
	var bg := Color(UIStyle.STONE, 1.0)
	match kind:
		"skull":
			ci.draw_circle(p.call(0.5, 0.42), 0.36 * s.x, col)
			ci.draw_rect(Rect2(p.call(0.32, 0.62), Vector2(0.36 * s.x, 0.26 * s.y)), col)
			ci.draw_circle(p.call(0.37, 0.44), 0.09 * s.x, bg)
			ci.draw_circle(p.call(0.63, 0.44), 0.09 * s.x, bg)
			ci.draw_rect(Rect2(p.call(0.45, 0.82), Vector2(0.025 * s.x, 0.1 * s.y)), bg)
			ci.draw_rect(Rect2(p.call(0.53, 0.82), Vector2(0.025 * s.x, 0.1 * s.y)), bg)
		"sword":
			ci.draw_line(p.call(0.2, 0.8), p.call(0.82, 0.18), col, w * 1.4, true)
			ci.draw_line(p.call(0.3, 0.52), p.call(0.5, 0.72), col, w * 1.1, true)
			ci.draw_circle(p.call(0.18, 0.84), 0.07 * s.x, col)
		"hammer":
			ci.draw_line(p.call(0.28, 0.88), p.call(0.64, 0.34), col, w * 1.3, true)
			ci.draw_colored_polygon(PackedVector2Array([p.call(0.42, 0.2), p.call(0.64, 0.1), p.call(0.92, 0.38), p.call(0.8, 0.56), p.call(0.5, 0.48)]), col)
		"slash":
			for i in 3:
				var o := 0.2 * float(i)
				ci.draw_line(p.call(0.12 + o, 0.12), p.call(0.38 + o, 0.9), col, w * 1.2, true)
		"shield":
			ci.draw_colored_polygon(PackedVector2Array([p.call(0.18, 0.12), p.call(0.82, 0.12), p.call(0.82, 0.5), p.call(0.5, 0.92), p.call(0.18, 0.5)]), col)
			ci.draw_line(p.call(0.5, 0.2), p.call(0.5, 0.72), bg, w * 0.8, true)
		"bone":
			ci.draw_line(p.call(0.26, 0.74), p.call(0.74, 0.26), col, w * 1.5, true)
			for e in [[0.2, 0.62], [0.38, 0.8], [0.62, 0.2], [0.8, 0.38]]:
				ci.draw_circle(p.call(e[0], e[1]), 0.1 * s.x, col)
		"cross":
			ci.draw_rect(Rect2(p.call(0.38, 0.14), Vector2(0.24 * s.x, 0.72 * s.y)), col)
			ci.draw_rect(Rect2(p.call(0.14, 0.38), Vector2(0.72 * s.x, 0.24 * s.y)), col)
		"star":
			var pts := PackedVector2Array()
			for i in 10:
				var a := -PI / 2.0 + float(i) * PI / 5.0
				var rr := 0.44 if i % 2 == 0 else 0.19
				pts.append(rect.position + s * 0.5 + Vector2(cos(a), sin(a)) * rr * s.x)
			ci.draw_colored_polygon(pts, col)
		"coin":
			ci.draw_circle(p.call(0.5, 0.5), 0.4 * s.x, col)
			ci.draw_circle(p.call(0.5, 0.5), 0.27 * s.x, bg)
			ci.draw_circle(p.call(0.5, 0.5), 0.17 * s.x, col)
		"crown":
			ci.draw_colored_polygon(PackedVector2Array([p.call(0.1, 0.78), p.call(0.1, 0.3), p.call(0.3, 0.52), p.call(0.5, 0.18), p.call(0.7, 0.52), p.call(0.9, 0.3), p.call(0.9, 0.78)]), col)
			ci.draw_rect(Rect2(p.call(0.1, 0.8), Vector2(0.8 * s.x, 0.12 * s.y)), col)
		_:
			ci.draw_circle(p.call(0.5, 0.5), 0.3 * s.x, col)
