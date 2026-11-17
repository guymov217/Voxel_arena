class_name TrainerScreen
extends VBoxContainer
## Doctore's yard: the six abilities as a radar (what he has taught, what the bout lets him teach,
## what the next session would add when a card is pointed at) and a card for each with its session
## to buy; Virtus, the Unbroken's, on a card of its own. Drawing and asking only: what a session
## costs and gives is Training's, bought through Menu as it always was.

## The six abilities on a hexagon: rings, the limit of each, the cap this bout, what he has, and
## what one more session would give (`ghost`).
class Radar extends Control:
	var ids: Array = []
	var names: Array = []
	var titles: Array = []
	var maxes: Array = []
	var levels: Array = []      # the polygon as drawn (tweened)
	var target: Array = []
	var caps: Array = []
	var ghost: Array = []       # the next session, per axis (-1: none)
	var scale_max := 45.0
	var pulse_i := -1
	var pulse_t := 0.0
	var _tw: Tween = null

	func _init() -> void:
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		size_flags_vertical = Control.SIZE_EXPAND_FILL
		custom_minimum_size = Vector2(240, 220)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_target(values: Array, animate := true) -> void:
		target = values.duplicate()
		if levels.is_empty():
			levels = values.duplicate()
		if not animate or not is_inside_tree():
			levels = values.duplicate()
			queue_redraw()
			return
		var from := levels.duplicate()
		if _tw != null and _tw.is_valid():
			_tw.kill()
		_tw = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_tw.tween_method(func(t: float):
			for i in from.size():
				levels[i] = lerpf(float(from[i]), float(target[i]), t)
			queue_redraw(), 0.0, 1.0, 0.7)

	func pulse(i: int) -> void:
		pulse_i = i
		pulse_t = 0.0
		var tw := create_tween()
		tw.tween_method(func(t: float):
			pulse_t = t
			queue_redraw(), 0.0, 1.0, 0.8)
		tw.tween_callback(func(): pulse_i = -1)

	func _pt(i: int, frac: float, radius: float, c: Vector2) -> Vector2:
		var a := -PI * 0.5 + TAU * float(i) / float(ids.size())
		return c + Vector2(cos(a), sin(a)) * radius * frac

	func _draw() -> void:
		var n := ids.size()
		if n < 3:
			return
		var c := size * 0.5
		var margin_x := 92.0
		var margin_y := 40.0
		var radius := maxf(40.0, minf(size.x * 0.5 - margin_x, size.y * 0.5 - margin_y))
		var ring := Color(UIStyle.BRONZE_DARK, 0.55)
		for k in [0.25, 0.5, 0.75, 1.0]:
			var pts := PackedVector2Array()
			for i in n:
				pts.append(_pt(i, k, radius, c))
			pts.append(pts[0])
			draw_polyline(pts, ring if k < 1.0 else Color(UIStyle.BRONZE, 0.5), 1.0)
		for i in n:
			draw_line(c, _pt(i, 1.0, radius, c), Color(UIStyle.BRONZE_DARK, 0.5), 1.0)
		# each ability's own limit
		var lim := PackedVector2Array()
		for i in n:
			lim.append(_pt(i, float(maxes[i]) / scale_max, radius, c))
		lim.append(lim[0])
		draw_polyline(lim, Color(UIStyle.BRONZE, 0.45), 1.5)
		# what this bout lets him have
		var capp := PackedVector2Array()
		for i in n:
			capp.append(_pt(i, float(caps[i]) / scale_max, radius, c))
		for i in n:
			draw_dashed_line(capp[i], capp[(i + 1) % n], Color(UIStyle.GOLD, 0.7), 1.5, 5.0)
		# what he has
		var poly := PackedVector2Array()
		for i in n:
			poly.append(_pt(i, clampf(float(levels[i]) / scale_max, 0.0, 1.0), radius, c))
		if poly.size() >= 3 and Geometry2D.triangulate_polygon(poly).size() >= 3:
			draw_colored_polygon(poly, Color(UIStyle.GOLD, 0.28))
		var closed := poly.duplicate()
		closed.append(poly[0])
		draw_polyline(closed, UIStyle.GOLD, 2.5, true)
		# the next session
		if not ghost.is_empty():
			var gp := PackedVector2Array()
			for i in n:
				var gv := float(ghost[i]) if float(ghost[i]) >= 0.0 else float(levels[i])
				gp.append(_pt(i, clampf(gv / scale_max, 0.0, 1.0), radius, c))
			gp.append(gp[0])
			draw_polyline(gp, StationKit.GOOD, 2.0, true)
		for i in n:
			draw_circle(poly[i], 4.5, UIStyle.INK)
			draw_circle(poly[i], 3.2, UIStyle.GOLD_LIGHT)
		if pulse_i >= 0:
			draw_arc(poly[pulse_i], 6.0 + 26.0 * pulse_t, 0.0, TAU, 32, Color(UIStyle.GOLD_LIGHT, 1.0 - pulse_t), 2.5)
		# the names
		var font := UIStyle.serif(2, 700)
		var body := UIStyle.body("medium")
		for i in n:
			var p := _pt(i, 1.0, radius, c)
			var dir := (p - c).normalized()
			var head: String = String(names[i]).to_upper()
			var sub: String = "%s · %d%%" % [Loc.t(String(titles[i])), int(round(float(levels[i])))]
			var hw := font.get_string_size(head, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
			var sw := body.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
			var at := p + dir * 14.0
			var ox := -hw * 0.5 + dir.x * hw * 0.5
			var ox2 := -sw * 0.5 + dir.x * sw * 0.5
			var oy := 4.0 if dir.y > 0.3 else (-16.0 if dir.y < -0.3 else -6.0)
			draw_string(font, at + Vector2(ox, oy + 4.0), head, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UIStyle.TEXT)
			draw_string(body, at + Vector2(ox2, oy + 20.0), sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UIStyle.MUTED)

var menu: Control
var inner := Vector2(1392, 768)
var compact := false
var stage_n := 1
var st: Dictionary = {}
var purse: StationKit.Purse
var radar: Radar
var left_w := 560.0
var right_w := 800.0
var cards: Array = []

static func build(m: Control, v: VBoxContainer) -> TrainerScreen:
	var s := TrainerScreen.new()
	s.menu = m
	var leave: Button = null
	if v.get_child_count() > 0 and v.get_child(0) is Button:
		leave = v.get_child(0)
		v.remove_child(leave)
	StationKit.take_msg(m, v)
	v.add_child(s)
	s.setup(leave)
	return s

func setup(leave: Button) -> void:
	var vp: Vector2 = menu.get_viewport_rect().size
	menu.panel.custom_minimum_size = Vector2(maxf(640.0, vp.x - 144.0), maxf(420.0, minf(vp.y - 80.0, vp.x * 0.62)))
	inner = menu.panel.custom_minimum_size - Vector2(64.0, 52.0)
	compact = inner.y < 640.0
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 6 if compact else 10)
	stage_n = int(Save.get_value("coop_stage" if Net.active() else "stage", 1))
	st = menu.training_stats()
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 16)
	add_child(head)
	var names := VBoxContainer.new()
	names.add_theme_constant_override("separation", 0)
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	names.add_child(UIStyle.label("THE LUDUS YARD", 13, UIStyle.BRONZE))
	names.add_child(UIStyle.title("The trainer", 28 if compact else 36))
	head.add_child(names)
	var cap_any := maxi(0, stage_n - 1) * Training.CAP_PER_STAGE
	cap_any -= cap_any % Training.STEP
	var cap_l := UIStyle.label(Loc.t("Bout %d: up to %d%% an ability") % [stage_n, cap_any], 14, UIStyle.BRONZE)
	cap_l.autowrap_mode = TextServer.AUTOWRAP_OFF
	cap_l.clip_text = true
	cap_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	cap_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(cap_l)
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
	left_w = clampf(inner.x * 0.36, 280.0, 560.0)
	right_w = inner.x - left_w - 18.0
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = left_w
	left.add_theme_constant_override("separation", 8)
	body.add_child(left)
	# The radar, on a dark card.
	var radar_host := StationKit.card(UIStyle.BRONZE_DARK, 1, 0, 8, StationKit.INSET_BG)
	radar_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(radar_host)
	var layer := Control.new()
	layer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	radar_host.add_child(layer)
	radar = Radar.new()
	radar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for id in Training.ORDER:
		var a: Dictionary = Training.ABILITIES[id]
		radar.ids.append(id)
		radar.names.append(a.name)
		radar.titles.append(a.title)
		radar.maxes.append(int(a.max))
		radar.caps.append(Training.cap(id, stage_n))
	layer.add_child(radar)
	var prev: Dictionary = menu.trainer_prev
	if not prev.is_empty():
		var before: Array = []
		for id in Training.ORDER:
			before.append(float(Training.level(prev, id)))
		radar.levels = before
		menu.trainer_prev = {}
	var now: Array = []
	for id in Training.ORDER:
		now.append(float(Training.level(st, id)))
	radar.set_target(now, true)
	var note := UIStyle.label("Doctore sells sessions, a per cent at a time; the arena teaches nothing, and a death takes it all with the purse.", 13, UIStyle.MUTED)
	note.custom_minimum_size.x = left_w - 20.0
	left.add_child(note)
	var legend := UIStyle.label("Gold is what you have, the dashed line what this bout lets you teach, the faint line each ability's own limit. Point at a card to see the next session.", 12, UIStyle.MUTED)
	legend.custom_minimum_size.x = left_w - 20.0
	left.add_child(legend)
	var sum_l := UIStyle.label(Training.summary(st).capitalize(), 13, UIStyle.BRONZE)
	sum_l.custom_minimum_size.x = left_w - 20.0
	left.add_child(sum_l)
	# The cards.
	var sc := ScrollContainer.new()
	sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(sc)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 8)
	sc.add_child(col)
	var grid := GridContainer.new()
	grid.columns = 2 if right_w >= 520.0 else 1
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	col.add_child(grid)
	for i in Training.ORDER.size():
		grid.add_child(_card(String(Training.ORDER[i]), i))
	col.add_child(_card("virtus", -1))
	var line: Dictionary = menu.station_note
	menu.station_note = {}
	StationKit.show_note(menu, purse, line)
	if int(line.get("axis", -1)) >= 0:
		radar.pulse(int(line.axis))
	if not menu.in_yard():
		var row := HBoxContainer.new()
		row.add_child(UIStyle.button("Back", func(): menu.show_screen("yard")))
		add_child(row)

func _card(id: String, axis: int) -> Control:
	var a: Dictionary = Training.ABILITIES[id]
	var lv := Training.level(st, id)
	var cap := Training.cap(id, stage_n)
	var full := lv >= int(a.max)
	var virtus := id == "virtus"
	var card := StationKit.card(UIStyle.GOLD if full or virtus else (UIStyle.BRONZE if lv > 0 else UIStyle.BRONZE_DARK), 2 if virtus else 1, 10, 8, Color(0.16, 0.11, 0.05, 0.95) if virtus else StationKit.CARD_BG)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 5)
	card.add_child(col)
	var top := HBoxContainer.new()
	col.add_child(top)
	var name_l := UIStyle.label("%s · %s" % [a.name, Loc.t(String(a.title))], 16, UIStyle.GOLD if lv > 0 else UIStyle.TEXT)
	name_l.autowrap_mode = TextServer.AUTOWRAP_OFF
	name_l.clip_text = true
	name_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(name_l)
	var lv_l := UIStyle.label("%d / %d%%" % [lv, int(a.max)], 14, UIStyle.GOLD if lv > 0 else UIStyle.MUTED)
	lv_l.autowrap_mode = TextServer.AUTOWRAP_OFF
	top.add_child(lv_l)
	var bar := StationKit.Bar.new(8.0, UIStyle.GOLD)
	bar.value = float(lv) / float(a.max)
	bar.cap = float(cap) / float(a.max)
	var r: Dictionary = Training.buy(st, id, stage_n, menu.coins())
	if not r.has("error"):
		bar.ghost = float(lv + Training.step(id)) / float(a.max)
	col.add_child(bar)
	if not compact:
		var d := UIStyle.label(Loc.t(String(a.desc)), 12, UIStyle.MUTED)
		d.custom_minimum_size = Vector2(maxf(120.0, (right_w if axis < 0 else right_w * 0.5) - 60.0), 0)
		col.add_child(d)
	var nextl := UIStyle.label(Loc.t("Next session: +%d%% %s") % [Training.step(id), Loc.lower(String(a.title))], 12, StationKit.GOOD if not r.has("error") else Color(UIStyle.MUTED, 0.6))
	nextl.autowrap_mode = TextServer.AUTOWRAP_OFF
	nextl.clip_text = true
	nextl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	col.add_child(nextl)
	UIStyle.push_down(col)
	var b: Button
	if r.has("error"):
		var why := "Mastered" if full else (Loc.t("Wait for bout %d") % Training.bout_for(lv + Training.step(id)) if lv >= cap else Loc.t("Train · %d denarii") % Training.price(st, id))
		if virtus and not CampaignRun.unbroken():
			why = "Only for the Unbroken (Ironman)"
		b = UIStyle.button(why, func(): pass)
		b.disabled = true
		b.tooltip_text = String(r.error)
	else:
		b = UIStyle.button(Loc.t("Train · %d denarii") % int(r.cost), func():
			var r2: Dictionary = Training.buy(menu.training_stats(), id, stage_n, menu.coins())
			if r2.has("error"):
				menu.show_screen("trainer", r2.error)
				return
			menu.trainer_prev = menu.training_stats()
			menu.add_coins(-int(r2.cost))
			menu.set_training_stats(r2.stats)
			if int(r2.stats[id]) >= int(a.max):
				Achievements.unlock("trained")
			menu.station_note = {"rise": "−%d" % int(r2.cost), "axis": axis}
			if Sfx:
				Sfx.play("thump", Vector3.ZERO, 0.7)
			menu.show_screen("trainer"), true)
	b.autowrap_mode = TextServer.AUTOWRAP_OFF
	col.add_child(b)
	# Pointing at a card shows on the radar what one more session of it would give.
	card.mouse_filter = Control.MOUSE_FILTER_PASS
	card.mouse_entered.connect(func():
		if axis >= 0 and not r.has("error"):
			var g: Array = []
			for k in Training.ORDER.size():
				g.append(-1.0)
			g[axis] = float(lv + Training.step(id))
			radar.ghost = g
			radar.queue_redraw())
	card.mouse_exited.connect(func():
		radar.ghost = []
		radar.queue_redraw())
	return card
