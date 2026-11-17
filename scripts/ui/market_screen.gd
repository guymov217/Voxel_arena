class_name MarketScreen
extends VBoxContainer
## The trader's table (Mercator) in the showcase layout: the ware on a stand that turns, what it
## does and its price with a Buy under it; the wares in tabs on the right, each tab's lit or
## dim by what the bosses have brought; the trader's road, a new ware after every boss; the bag
## along the foot. Drawing and asking only: what a ware costs and what the bag holds are Market's
## and Throwables', and what is bought goes through Menu as it always did.

var menu: Control
var tab := "fire"
var sel := ""
var qty := 1
var at := Vector2i(1, 1)
var open := 0
var table: Dictionary = {}
var kit: Dictionary = {}
var inner := Vector2(1392, 768)
var compact := false
var left_w := 520.0
var right_w := 800.0
var purse: StationKit.Purse
var stage: Stage3D
var frame: Control
var detail_card: PanelContainer
var pills_host: VBoxContainer
var grid_host: VBoxContainer
var road_host: VBoxContainer
var bag_host: VBoxContainer
var buy_btn: Button = null

## Builds the market into `v` (Menu's column for the screen).
static func build(m: Control, v: VBoxContainer) -> MarketScreen:
	var s := MarketScreen.new()
	s.menu = m
	# The way out Menu put first in the column goes up beside the purse.
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
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 6 if compact else 10)
	table = Data.shop.get("throwables", {})
	at = menu._market_at()
	open = Market.opened(Net.active(), at.x, at.y)
	kit = menu.kit()
	tab = menu.market_tab
	if Market.wares(tab).is_empty():
		tab = Market.TABS[0][0]
	sel = menu.market_sel
	if sel == "" or not Market.wares(tab).has(sel) or not table.has(sel):
		sel = _first_of(tab)
	# The head: the name of the stall, the purse, the way out.
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 16)
	add_child(head)
	var names := VBoxContainer.new()
	names.add_theme_constant_override("separation", 0)
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	names.add_child(UIStyle.label("THE LUDUS YARD", 13, UIStyle.BRONZE))
	names.add_child(UIStyle.title("The market", 28 if compact else 36))
	head.add_child(names)
	purse = StationKit.Purse.new(menu.coins(), 24)
	purse.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(purse)
	if leave != null:
		leave.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		head.add_child(leave)
	# The body: the stage and what it shows on the left, the table on the right.
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 18)
	add_child(body)
	left_w = clampf(inner.x * 0.37, 300.0, 560.0)
	right_w = inner.x - left_w - 18.0
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = left_w
	left.add_theme_constant_override("separation", 8)
	body.add_child(left)
	stage = Stage3D.new()
	frame = StationKit.stage_frame(stage, _tab_name(tab), "Drag to turn it")
	frame.size_flags_stretch_ratio = 3.0
	frame.custom_minimum_size.y = 120.0 if compact else 190.0
	left.add_child(frame)
	detail_card = StationKit.card(UIStyle.BRONZE_DARK, 1, 12, 8)
	detail_card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail_card.size_flags_stretch_ratio = 2.0
	detail_card.custom_minimum_size.y = 150.0
	left.add_child(detail_card)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 8)
	body.add_child(right)
	pills_host = VBoxContainer.new()
	right.add_child(pills_host)
	grid_host = VBoxContainer.new()
	grid_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(grid_host)
	road_host = VBoxContainer.new()
	right.add_child(road_host)
	# The foot: the bag.
	bag_host = VBoxContainer.new()
	add_child(bag_host)
	_pills()
	_grid()
	_road()
	_bag()
	_show_ware()
	var note: Dictionary = menu.station_note
	menu.station_note = {}
	StationKit.show_note(menu, purse, note)
	if menu.in_yard() == false:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		row.add_child(StationKit.button("Back to the smith", func(): menu.show_screen("yard")))
		row.add_child(StationKit.button("Main menu", func(): menu.show_screen("main")))
		add_child(row)

func _first_of(t: String) -> String:
	for id in Market.wares(t):
		if table.has(id):
			return id
	return ""

func _tab_name(t: String) -> String:
	for x in Market.TABS:
		if x[0] == t:
			return String(x[1])
	return ""

func _cost(id: String) -> int:
	return Market.price(id, int(table[id].price), at.x)

func _after(id: String) -> int:
	return 0 if Market.is_open(id, open) else Market.comes_after(id)

# ---------- The tabs ----------

func _pills() -> void:
	_empty(pills_host)
	var items: Array = []
	for t in Market.TABS:
		var list: Array = (t[2] as Array).filter(func(i): return table.has(i))
		var here: int = list.filter(func(i): return Market.is_open(i, open)).size()
		items.append([t[0], t[1], "%d/%d" % [here, list.size()]])
	pills_host.add_child(StationKit.pills(items, tab, func(id: String):
		tab = id
		menu.market_tab = id
		sel = _first_of(id)
		menu.market_sel = sel
		qty = 1
		_pills()
		_grid()
		_show_ware(), compact))

# ---------- The wares ----------

func _grid() -> void:
	_empty(grid_host)
	var scroll := ScrollContainer.new()
	scroll.follow_focus = true
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size.y = 110.0
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	grid_host.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = clampi(int(right_w / (150.0 if compact else 176.0)), 2, 5)
	var rows := ceili(float(Market.wares(tab).size()) / float(grid.columns))
	# (What height the table has, less the tabs and the road, shared by its rows.)
	var avail := inner.y - 66.0 - (46.0 if compact else 70.0) - 2.0 * (6.0 if compact else 10.0) - (40.0 if compact else 46.0) * 2.0 - (100.0 if compact else 150.0) - 16.0
	var tile_h := clampf((avail - 10.0 * float(rows - 1)) / float(rows), 118.0 if compact else 168.0, 250.0)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	scroll.add_child(grid)
	var newest := String(Market.AFTER_BOSS[open - 1]) if open > 0 else ""
	for id in Market.wares(tab):
		if table.has(id):
			grid.add_child(_tile(id, tile_h, id == newest))

func _tile(id: String, h: float, fresh: bool) -> Control:
	var it: Dictionary = table[id]
	var have := int(kit.get(id, 0))
	var after := _after(id)
	var on := id == sel
	var t := StationKit.card(UIStyle.GOLD if on else (UIStyle.BRONZE if have > 0 else UIStyle.BRONZE_DARK), 2 if on else 1, 8, 8)
	t.custom_minimum_size = Vector2(0, h)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t.mouse_filter = Control.MOUSE_FILTER_STOP
	t.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t.add_child(col)
	var pic := Control.new()
	pic.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pic.custom_minimum_size.y = 40.0 if compact else 70.0
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(pic)
	var tex := TextureRect.new()
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if after > 0:
		tex.modulate = Color(0.45, 0.4, 0.38, 0.8)
	pic.add_child(tex)
	tex.tree_entered.connect(func(): Thumbs.item(tex, id), CONNECT_ONE_SHOT)
	var carry := StationKit.carry_of(kit, id)
	if after <= 0 or have > 0:
		# (What he carries of it, of the most he can hold: red when no more fits.)
		var badge_col: Color = StationKit.BAD if String(carry.why) != "" else (UIStyle.GOLD if have > 0 else UIStyle.MUTED)
		StationKit.corner(pic, UIStyle.label("%d/%d" % [have, int(carry.max)], 13, badge_col), "tl", 2.0, 40.0, 18.0)
	if after <= 0:
		t.tooltip_text = StationKit.carry_line(carry)
	if after > 0 or fresh:
		var tag := UIStyle.label("LOCKED" if after > 0 else "NEW", 12, UIStyle.INK if after <= 0 else UIStyle.MUTED)
		tag.autowrap_mode = TextServer.AUTOWRAP_OFF
		tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var tp := PanelContainer.new()
		tp.add_theme_stylebox_override("panel", StationKit.plate(UIStyle.GOLD if after <= 0 else UIStyle.BRONZE_DARK, 1, 3, 3, UIStyle.GOLD if after <= 0 else Color(0.05, 0.04, 0.03, 0.85)))
		tp.add_child(tag)
		StationKit.corner(pic, tp, "tr", 0.0, 58.0, 20.0)
	var nm := UIStyle.label(Loc.t(String(it.name)), 14 if not compact else 13, UIStyle.TEXT if after <= 0 else UIStyle.MUTED)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nm.autowrap_mode = TextServer.AUTOWRAP_OFF
	nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(nm)
	var cost := _cost(id)
	var sub: Label
	if after > 0:
		sub = UIStyle.label(Loc.t("after bout %d") % after, 12, UIStyle.MUTED)
	else:
		sub = StationKit.price(cost, cost <= menu.coins(), 14)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.autowrap_mode = TextServer.AUTOWRAP_OFF
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(sub)
	StationKit.pickable(t, func(): _pick(id), "tile:" + id)
	if on:
		t.set_meta("start", true)
	return t

func _pick(id: String) -> void:
	if id == sel:
		return
	StationKit.tick()
	sel = id
	menu.market_sel = id
	qty = 1
	_grid()
	_show_ware()

# ---------- The ware on the stage ----------

func _show_ware() -> void:
	var it: Dictionary = table[sel]
	var type = Thumbs.item_type(sel)
	var g: Node3D = Items.visual(type) if type != null else null
	if g != null:
		Thumbs.lay_across(g)
		stage.show_model(g, {"stand": "plinth", "yaw": 0.5, "pitch": 0.3})
	if frame.has_meta("tag"):
		(frame.get_meta("tag") as Label).text = Loc.t(_tab_name(tab)).to_upper()
	_detail()

func _detail() -> void:
	_empty(detail_card)
	var it: Dictionary = table[sel]
	var after := _after(sel)
	var have := int(kit.get(sel, 0))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	detail_card.add_child(col)
	col.add_child(StationKit.kicker(_tab_name(tab)))
	col.add_child(StationKit.heading(Loc.t(String(it.name)), 22 if compact else 26))
	var sc := ScrollContainer.new()
	sc.follow_focus = true
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.custom_minimum_size.y = 36.0
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(sc)
	var tv := VBoxContainer.new()
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.add_theme_constant_override("separation", 4)
	sc.add_child(tv)
	var d := UIStyle.label(String(it.get("desc", "")), 14, UIStyle.TEXT)
	d.custom_minimum_size.x = left_w - 50.0
	tv.add_child(d)
	var use := UIStyle.label(menu.MARKET_USE[menu.kit_use(sel)], 12, UIStyle.BRONZE)
	use.custom_minimum_size.x = left_w - 50.0
	tv.add_child(use)
	if menu.FRIENDLY_FIRE.has(sel):
		tv.add_child(UIStyle.label("Hurts friends too", 12, StationKit.BAD))
	if sel == "telekinesis":
		var hj := UIStyle.label("Its price follows the purses: nine tenths of the best a bout has paid by now.", 12, UIStyle.MUTED)
		hj.custom_minimum_size.x = left_w - 50.0
		tv.add_child(hj)
	# How many he carries of it and how many more fit (or why none): not in the scroll, always in view.
	var carry := StationKit.carry_of(kit, sel)
	if after <= 0:
		var cl := UIStyle.label(StationKit.carry_line(carry), 13, StationKit.BAD if String(carry.why) != "" else UIStyle.TEXT)
		cl.custom_minimum_size.x = left_w - 50.0
		col.add_child(cl)
	# The buy row.
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	col.add_child(row)
	buy_btn = null
	if after > 0:
		row.add_child(StationKit.spacer())
		var later := StationKit.button(Loc.t("After the boss of bout %d") % after, func(): pass)
		later.disabled = true
		row.add_child(later)
		return
	var unit := _cost(sel)
	var most := mini(int(carry.more), 9)
	qty = clampi(qty, 1, maxi(1, most))
	if most > 1:
		row.add_child(_stepper(most))
	var total := unit * qty
	var can_pay: bool = total <= int(menu.coins())
	row.add_child(StationKit.price(total, can_pay, 22))
	row.add_child(StationKit.spacer())
	var label := Loc.t("Buy · %d denarii") % total
	if most <= 0:
		label = StationKit.carry_short(carry)
	buy_btn = StationKit.button(label, _buy, can_pay and most > 0)
	buy_btn.set_meta("key", "buy")
	buy_btn.disabled = not can_pay or most <= 0
	if most <= 0:
		buy_btn.tooltip_text = StationKit.carry_line(carry)
	buy_btn.autowrap_mode = TextServer.AUTOWRAP_OFF
	row.add_child(buy_btn)

func _stepper(most: int) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	var minus := StationKit.button("−", func():
		qty = maxi(1, qty - 1)
		_detail())
	minus.disabled = qty <= 1
	minus.set_meta("key", "minus")
	row.add_child(minus)
	var n := UIStyle.label("%d" % qty, 18, UIStyle.TEXT)
	n.custom_minimum_size.x = 28.0
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	n.autowrap_mode = TextServer.AUTOWRAP_OFF
	row.add_child(n)
	var plus := StationKit.button("+", func():
		qty = mini(most, qty + 1)
		_detail())
	plus.disabled = qty >= most
	plus.set_meta("key", "plus")
	row.add_child(plus)
	return row

## Buys what is asked: one after another while he can pay and the bag has room, as the old card
## did one at a time.
func _buy() -> void:
	var from := buy_btn.get_global_rect() if buy_btn != null else Rect2()
	var id := sel
	var unit := _cost(id)
	var k2: Dictionary = menu.kit()
	var got := 0
	var why := ""
	for i in qty:
		if unit > menu.coins():
			why = "Not enough denarii"
			break
		if not Throwables.bag_has_room(k2, id):
			why = StationKit.carry_short(StationKit.carry_of(k2, id))
			break
		menu.add_coins(-unit)
		k2[id] = int(k2.get(id, 0)) + 1
		got += 1
	if got == 0:
		StationKit.warn(menu, purse, why)
		if buy_btn != null:
			StationKit.pulse(buy_btn)
		return
	menu.set_kit(k2)
	if Sfx:
		Sfx.play("pickup", Vector3.ZERO, 0.6)
	kit = menu.kit()
	StationKit.rise(menu, from.get_center() - Vector2(20, 24), "−%d" % (unit * got), StationKit.BAD)
	purse.set_value(menu.coins())
	qty = 1
	_grid()
	_detail()
	_bag()
	if why != "":
		StationKit.warn(menu, purse, why)
	var tex: Texture2D = Thumbs.cache.get("item:" + id)
	await get_tree().process_frame
	var bar: Array = bag_host.get_child(0).get_meta("order", []) if bag_host.get_child_count() > 0 else []
	var slots: Array = bag_host.get_child(0).get_meta("slots", []) if bag_host.get_child_count() > 0 else []
	var k := bar.find(id)
	if k >= 0 and k < slots.size():
		var slot: Control = slots[k]
		StationKit.fly(menu, tex, from, slot.get_global_rect(), func(): StationKit.pulse(slot))

# ---------- The trader's road ----------

func _road() -> void:
	_empty(road_host)
	var card := StationKit.card(UIStyle.BRONZE_DARK, 1, 10, 8)
	road_host.add_child(card)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	card.add_child(col)
	var road: Array = Market.road(open)
	var head := HBoxContainer.new()
	head.add_child(StationKit.kicker("The trader's road · a new ware after every boss", UIStyle.BRONZE, 12, true))
	var brought := UIStyle.label(Loc.t("%d of %d brought") % [open, road.size()], 12, UIStyle.MUTED)
	brought.autowrap_mode = TextServer.AUTOWRAP_OFF
	head.add_child(brought)
	col.add_child(head)
	var px := 34.0 if compact else 46.0
	var scroll := ScrollContainer.new()
	scroll.follow_focus = true
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size.y = px + 18.0 + 10.0
	col.add_child(scroll)
	var strip := HBoxContainer.new()
	strip.add_theme_constant_override("separation", 6)
	scroll.add_child(strip)
	var next_tile: Control = null
	for r in road:
		var t := _road_tile(r, px)
		strip.add_child(t)
		if bool(r.next):
			next_tile = t
	var nxt := ""
	for r in road:
		if bool(r.next):
			nxt = Loc.t("Next: %s after the boss of bout %d.") % [Loc.t(String(table.get(r.id, {}).get("name", r.id))), int(r.bout)]
	if nxt != "" and not compact:
		col.add_child(UIStyle.label(nxt, 12, UIStyle.BRONZE))
	if next_tile != null:
		_show_in(scroll, next_tile)

## A strip scrolled so that `c` is in it (after the frame that lays it out).
func _show_in(scroll: ScrollContainer, c: Control) -> void:
	await get_tree().process_frame
	if is_instance_valid(scroll) and is_instance_valid(c):
		scroll.ensure_control_visible(c)

func _road_tile(r: Dictionary, px: float) -> Control:
	var id := String(r.id)
	var brought := bool(r.brought)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	var slot := StationKit.card(UIStyle.GOLD if bool(r.next) else (UIStyle.BRONZE_DARK if brought else Color(UIStyle.BRONZE_DARK, 0.45)), 2 if bool(r.next) else 1, 2, 5, Color(0.09, 0.07, 0.05, 0.95) if brought else Color(0.04, 0.03, 0.025, 0.85))
	slot.custom_minimum_size = Vector2(px, px)
	slot.tooltip_text = Loc.t(String(table.get(id, {}).get("name", id))) + ("" if brought else " · " + Loc.t("after bout %d") % int(r.bout))
	var tex := TextureRect.new()
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex.modulate = Color.WHITE if brought else Color(0.3, 0.26, 0.23, 0.95)
	slot.add_child(tex)
	tex.tree_entered.connect(func(): Thumbs.item(tex, id), CONNECT_ONE_SHOT)
	box.add_child(slot)
	var n := UIStyle.label(str(int(r.bout)), 12, UIStyle.GOLD if bool(r.next) else UIStyle.MUTED)
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	n.autowrap_mode = TextServer.AUTOWRAP_OFF
	box.add_child(n)
	return box

# ---------- The bag ----------

func _bag() -> void:
	_empty(bag_host)
	bag_host.add_child(StationKit.bag_strip(kit, 40 if compact else 54))

func _empty(c: Node) -> void:
	StationKit.keep_focus(c)
	for x in c.get_children():
		c.remove_child(x)
		x.queue_free()
