class_name ArmourShop
extends HBoxContainer
## The smith's rack of armour: the gladiator, in the new look, turning in the light in what he
## wears, and in what he is thinking of buying, a piece at a time; the pieces on the right, by
## the part of the body they are for; what a piece does, what it costs and what it takes off him
## on the left. Asking and drawing only: what is bought, mended or taken off is Armory's and
## Menu's, as it was.

const REGIONS := [["all", "All"], ["Head", "Head"], ["Body", "Body"], ["Arms", "Arms"], ["Legs", "Legs"], ["My designs", "My designs"]]

var menu: Control
var smith: Control
var sel := ""
var region := "all"
var worn: Array = []
var ids: Array = []
var stage: ArmourStage
var detail_card: PanelContainer
var pills_host: VBoxContainer
var list_host: VBoxContainer
var total_host: VBoxContainer
var compact := false
var left_w := 520.0
var right_w := 800.0

static func build(m: Control, s: Control) -> ArmourShop:
	var a := ArmourShop.new()
	a.menu = m
	a.smith = s
	s.add_child(a)
	a.setup()
	return a

func setup() -> void:
	compact = smith.compact
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 18)
	worn = menu.worn_armor()
	var designs: Dictionary = Save.get_value("armor_designs", {})
	ids = designs.keys().filter(func(i): return Armory.custom(String(i))) + Armory.SHOP.map(func(r): return r[0])
	ids = ids.filter(func(i): return not (Data.armor.get(i, {}) as Dictionary).is_empty())
	sel = menu.armour_sel
	if not ids.has(sel):
		sel = String(worn[0]) if not worn.is_empty() and ids.has(worn[0]) else (String(ids[0]) if not ids.is_empty() else "")
	region = menu.armour_region
	left_w = clampf(smith.inner.x * 0.38, 300.0, 580.0)
	right_w = smith.inner.x - left_w - 18.0
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = left_w
	left.add_theme_constant_override("separation", 8)
	add_child(left)
	stage = ArmourStage.make("")
	add_child(stage)
	stage.frame.size_flags_stretch_ratio = 9.0
	stage.frame.custom_minimum_size.y = 150.0 if compact else 280.0
	left.add_child(stage.frame)
	detail_card = StationKit.card(UIStyle.BRONZE_DARK, 1, 12, 8)
	detail_card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail_card.size_flags_stretch_ratio = 6.0
	detail_card.custom_minimum_size.y = 170.0
	left.add_child(detail_card)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 8)
	add_child(right)
	pills_host = VBoxContainer.new()
	right.add_child(pills_host)
	list_host = VBoxContainer.new()
	list_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(list_host)
	total_host = VBoxContainer.new()
	right.add_child(total_host)
	_pills()
	_list()
	_pick_done(true)

func _region_of(id: String) -> String:
	var designs: Dictionary = Save.get_value("armor_designs", {})
	return "My designs" if designs.has(id) else String(menu._armour_region(id))

func _empty(c: Node) -> void:
	for x in c.get_children():
		c.remove_child(x)
		x.queue_free()

func _pills() -> void:
	_empty(pills_host)
	var items: Array = []
	var designs: Dictionary = Save.get_value("armor_designs", {})
	for r in REGIONS:
		if r[0] == "My designs" and designs.is_empty():
			continue
		var n := ids.size() if r[0] == "all" else ids.filter(func(i): return _region_of(String(i)) == r[0]).size()
		items.append([r[0], r[1], str(n)])
	pills_host.add_child(StationKit.pills(items, region, func(id: String):
		region = id
		menu.armour_region = id
		_pills()
		_list(), compact))

func _list() -> void:
	_empty(list_host)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size.y = 110.0
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	list_host.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = clampi(int(right_w / (170.0 if compact else 190.0)), 2, 5)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	scroll.add_child(grid)
	for id in ids:
		if region == "all" or _region_of(String(id)) == region:
			grid.add_child(_tile(String(id)))
	_total()

func _tile(id: String) -> Control:
	var a: Dictionary = Data.armor.get(id, {})
	var on := worn.has(id)
	var chosen := id == sel
	var t := StationKit.card(UIStyle.GOLD if chosen else (UIStyle.BRONZE if on else UIStyle.BRONZE_DARK), 2 if chosen else 1, 8, 8)
	t.custom_minimum_size = Vector2(0, 92.0 if compact else 112.0)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t.mouse_filter = Control.MOUSE_FILTER_STOP
	t.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t.add_child(row)
	var cov := {}
	for k in Armory.parts_of(id):
		cov[k] = menu._armour_colour(id)
	var fig: Control = menu._armour_figure(cov, 40.0 if compact else 52.0)
	fig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fig.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(fig)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	col.add_theme_constant_override("separation", 2)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(col)
	var nm := UIStyle.label(Loc.t(String(a.get("name", id))), 14 if compact else 16, UIStyle.GOLD if on else UIStyle.TEXT)
	nm.autowrap_mode = TextServer.AUTOWRAP_OFF
	nm.clip_text = true
	nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(nm)
	var sub := UIStyle.label(Loc.t(String(a.get("mat", "iron")).capitalize()) + " · " + menu._dots(Armory.protection(id)), 12, UIStyle.MUTED)
	sub.autowrap_mode = TextServer.AUTOWRAP_OFF
	sub.clip_text = true
	sub.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(sub)
	var tag: Label
	if on:
		tag = UIStyle.label(Loc.t("WORN"), 12, UIStyle.GOLD)
	else:
		var cost: int = int(Armory.buy(worn, id).get("cost", Armory.price(id)))
		tag = StationKit.price(cost if cost > 0 else -cost, cost <= menu.coins(), 14)
		if cost <= 0:
			tag.text = Loc.t("Swap · %d denarii back") % -cost
	tag.autowrap_mode = TextServer.AUTOWRAP_OFF
	tag.clip_text = true
	tag.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(tag)
	t.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			_pick(id))
	t.mouse_entered.connect(func(): t.modulate = Color(1.1, 1.06, 1.0))
	t.mouse_exited.connect(func(): t.modulate = Color.WHITE)
	return t

func _pick(id: String) -> void:
	if id == sel:
		return
	StationKit.tick()
	sel = id
	menu.armour_sel = id
	_list()
	_pick_done(false)

## What he is shown in: what he wears, and the piece he is looking at in place of what it clashes with.
func _preview() -> Array:
	if sel == "" or worn.has(sel):
		return worn
	var t: Dictionary = Armory.buy(worn, sel)
	return t.get("worn", worn)

func _pick_done(first: bool) -> void:
	_detail()
	stage.dress(_preview())
	if first:
		var note: Dictionary = menu.station_note
		menu.station_note = {}
		StationKit.show_note(menu, smith.purse, note)

func _detail() -> void:
	_empty(detail_card)
	if sel == "":
		return
	# (What he does with it is pinned under the writing, which scrolls if it is long: the buttons
	# are never cut off.)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 8)
	detail_card.add_child(outer)
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.custom_minimum_size.y = 60.0
	outer.add_child(sc)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 6)
	sc.add_child(col)
	var a: Dictionary = Data.armor.get(sel, {})
	var on := worn.has(sel)
	var kick := _region_of(sel)
	col.add_child(StationKit.kicker(kick + ("  ·  " + Loc.t("WORN") if on else ""), UIStyle.BRONZE, 12, true))
	col.add_child(StationKit.heading(Loc.t(String(a.get("name", sel))), 22 if compact else 26))
	var where := []
	for k in Armory.parts_of(sel):
		if not where.has(menu.ARMOUR_PARTS.get(k, k)):
			where.append(menu.ARMOUR_PARTS.get(k, k))
	var l1 := UIStyle.label("%s · %s" % [Loc.t(String(a.get("mat", "iron")).capitalize()), ", ".join(where.map(func(w): return Loc.t(String(w))))], 13, UIStyle.BRONZE)
	l1.custom_minimum_size.x = left_w - 50.0
	col.add_child(l1)
	var l2 := UIStyle.label(Loc.t("Protection %s · %.1f kg") % [menu._dots(Armory.protection(sel)), Armory.kg(sel)], 14, UIStyle.TEXT)
	l2.custom_minimum_size.x = left_w - 50.0
	col.add_child(l2)
	var blurb := UIStyle.label(String(Armory.BLURB.get(sel, "Your own design, from the bench.")), 13, UIStyle.MUTED)
	blurb.custom_minimum_size.x = left_w - 50.0
	col.add_child(blurb)
	if not on:
		var swaps: Array = worn.filter(func(o): return Armory.clashes(o, sel))
		if not swaps.is_empty():
			var sw := UIStyle.label(Loc.t("Replaces your %s") % Loc.t(String(Data.armor[swaps[0]].name)), 13, UIStyle.MUTED)
			sw.custom_minimum_size.x = left_w - 50.0
			col.add_child(sw)
	var acts := HFlowContainer.new()
	acts.add_theme_constant_override("h_separation", 8)
	acts.add_theme_constant_override("v_separation", 8)
	outer.add_child(acts)
	var price := Armory.price(sel)
	if on:
		var aw: Dictionary = menu.armor_wear()
		var lost: Array = Armory.plates_lost(sel, aw)
		if int(lost[0]) > 0:
			var mc_ := Armory.mend_cost(sel, aw)
			var dmg := UIStyle.label(Loc.t("%d of %d plates knocked off · condition %d%%") % [lost[0], lost[1], int(Armory.condition(sel, aw) * 100.0)], 13, StationKit.BAD)
			dmg.custom_minimum_size.x = left_w - 50.0
			col.add_child(dmg)
			var mend := UIStyle.button(Loc.t("Mend · %d denarii") % mc_, func():
				var m: Dictionary = Armory.mend(menu.armor_wear(), sel)
				if int(m.cost) > menu.coins():
					menu.show_screen("yard", "Not enough denarii")
					return
				menu.add_coins(-int(m.cost))
				menu.set_armor_wear(m.wear)
				menu._armour_on_him()
				menu.station_note = {"rise": "−%d" % int(m.cost)}
				menu.show_screen("yard"), true)
			mend.disabled = mc_ > menu.coins()
			mend.tooltip_text = "The armourer puts back every plate it has lost." + (Loc.t(" Purse after: %d") % (menu.coins() - mc_) if mc_ <= menu.coins() else Loc.t(" %d more needed") % (mc_ - menu.coins()))
			acts.add_child(mend)
		var off := UIStyle.button(Loc.t("Take off · %d denarii back") % (price / 2), func():
			var t: Dictionary = Armory.take_off(menu.worn_armor(), sel)
			if not t.has("error"):
				menu.add_coins(-int(t.cost))
				menu.set_worn_armor(t.worn)
			menu.show_screen("yard"))
		acts.add_child(off)
	else:
		var b: Dictionary = Armory.buy(worn, sel)
		var cost: int = int(b.get("cost", price))
		var btn := UIStyle.button((Loc.t("Buy · %d denarii") % cost) if cost > 0 else (Loc.t("Swap · %d denarii back") % -cost), func():
			var t: Dictionary = Armory.buy(menu.worn_armor(), sel)
			if t.has("error"):
				menu.show_screen("yard", t.error)
			elif int(t.cost) > menu.coins():
				menu.show_screen("yard", "Not enough denarii")
			else:
				menu.add_coins(-int(t.cost))
				menu.set_worn_armor(t.worn)
				menu.station_note = {"rise": ("−%d" % int(t.cost)) if int(t.cost) > 0 else ""}
				menu.show_screen("yard"), true)
		btn.disabled = cost > menu.coins()
		btn.tooltip_text = (Loc.t("Purse after: %d") % (menu.coins() - cost)) if cost <= menu.coins() else (Loc.t("%d more needed") % (cost - menu.coins()))
		acts.add_child(btn)

## What he wears, as a whole, on the right: the weight, and what it costs him in breath and pace.
func _total() -> void:
	_empty(total_host)
	var card := StationKit.card(UIStyle.BRONZE_DARK, 1, 10, 8)
	total_host.add_child(card)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	card.add_child(col)
	col.add_child(StationKit.kicker("You wear"))
	if worn.is_empty():
		var e := UIStyle.label("You wear no armour. What you buy here goes with you into every bout of the campaign.", 13, UIStyle.MUTED)
		e.custom_minimum_size.x = right_w - 50.0
		col.add_child(e)
		return
	var kg := 0.0
	for id in worn:
		kg += Armory.kg(id)
	var with: Dictionary = Armory.burden(kg)
	var l := UIStyle.label(Loc.t("%d piece · %.1f kg" if worn.size() == 1 else "%d pieces · %.1f kg") % [worn.size(), kg], 14, UIStyle.TEXT)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	col.add_child(l)
	var l2 := UIStyle.label(Loc.t("Breath ×%.2f · pace %d%%") % [float(with.breath), int(round(float(with.pace) * 100.0))], 13, UIStyle.MUTED)
	l2.autowrap_mode = TextServer.AUTOWRAP_OFF
	col.add_child(l2)
