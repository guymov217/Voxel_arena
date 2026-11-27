class_name SmithScreen
extends VBoxContainer
## Vulcanus's smithy: the weapon on his anvil, turning in the light, the hammer over it (mend,
## hone, temper are struck out); his rack of wares, his masterworks of the bout and what the
## player's own designs would cost, as tiles to pick. The armour (bought, or made at the bench)
## is the next two tabs. Drawing and asking only: what is mended, bought or sold is Arms' and
## Menu's, as it was.

const GROUPS := [["arms", "Your arms"], ["sale", "For sale"], ["works", "Masterworks"], ["designs", "Your designs"]]

var menu: Control
var tab := "weapons"
var sel: Dictionary = {}
var group := "arms"
var inner := Vector2(1392, 768)
var compact := false
var left_w := 520.0
var right_w := 800.0
var purse: StationKit.Purse
var stage: Stage3D
var frame: Control
var detail_card: PanelContainer
var pills_host: VBoxContainer
var list_host: VBoxContainer
var stats_host: VBoxContainer
var hammer: Node3D = null
var busy := false
var a: Dictionary = {}

static func build(m: Control, v: VBoxContainer) -> SmithScreen:
	var s := SmithScreen.new()
	s.menu = m
	var leave: Button = null
	if v.get_child_count() > 0 and v.get_child(0) is Button:
		leave = v.get_child(0)
		v.remove_child(leave)
	# (Whatever Menu says over the screen, "Not enough denarii", is shown as a warning.)
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
	a = menu.arms()
	tab = menu.smith_tab
	_header(leave)
	if tab == "armour":
		ArmourShop.build(menu, self)
		return
	if tab == "bench":
		ArmourBench.build(menu, self)
		return
	group = menu.smith_group
	sel = menu.smith_sel
	if not _valid(sel):
		sel = {"kind": "arm", "side": "R"}
		menu.smith_sel = sel
	left_w = clampf(inner.x * 0.4, 300.0, 600.0)
	right_w = inner.x - left_w - 18.0
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 18)
	add_child(body)
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = left_w
	left.add_theme_constant_override("separation", 8)
	body.add_child(left)
	stage = Stage3D.new()
	stage.spin = 0.25
	frame = StationKit.stage_frame(stage, "", "Drag to turn the anvil")
	frame.size_flags_stretch_ratio = 5.0
	frame.custom_minimum_size.y = 120.0 if compact else 200.0
	left.add_child(frame)
	detail_card = StationKit.card(UIStyle.BRONZE_DARK, 1, 12, 8)
	detail_card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail_card.size_flags_stretch_ratio = 6.0
	detail_card.custom_minimum_size.y = 170.0
	left.add_child(detail_card)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 8)
	body.add_child(right)
	pills_host = VBoxContainer.new()
	right.add_child(pills_host)
	list_host = VBoxContainer.new()
	list_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(list_host)
	stats_host = VBoxContainer.new()
	right.add_child(stats_host)
	_pills()
	_list()
	_show()
	var note: Dictionary = menu.station_note
	menu.station_note = {}
	StationKit.show_note(menu, purse, note)

# ---------- The head and the tabs ----------

func _header(leave: Button) -> void:
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 16)
	add_child(head)
	var names := VBoxContainer.new()
	names.add_theme_constant_override("separation", 0)
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	names.add_child(UIStyle.label("THE LUDUS YARD", 13, UIStyle.BRONZE))
	names.add_child(UIStyle.title("The smith", 28 if compact else 36))
	head.add_child(names)
	var right := HFlowContainer.new()
	right.alignment = FlowContainer.ALIGNMENT_END
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_stretch_ratio = 2.5
	right.add_theme_constant_override("h_separation", 12)
	right.add_theme_constant_override("v_separation", 6)
	head.add_child(right)
	var tabs: Array = []
	for t in [["weapons", "Weapons"], ["armour", "Armour"], ["bench", "Design armour"]]:
		tabs.append([t[0], t[1], ""])
	for b in StationKit.pill_buttons(tabs, tab, func(id: String):
		menu.smith_tab = id
		menu.show_screen("yard"), compact):
		right.add_child(b)
	var all_: Dictionary = Armory.mend_all(menu.armor_wear(), menu.worn_armor())
	if int(all_.cost) > 0:
		var mend_all := StationKit.button(Loc.t("Mend all armour · %d denarii") % int(all_.cost), menu._mend_all_armour, true)
		mend_all.disabled = int(all_.cost) > menu.coins()
		mend_all.autowrap_mode = TextServer.AUTOWRAP_OFF
		mend_all.tooltip_text = Loc.t("The armourer puts back every plate your armour has lost.") + (Loc.t(" Purse after: %d") % (menu.coins() - int(all_.cost)) if int(all_.cost) <= menu.coins() else Loc.t(" %d more needed") % (int(all_.cost) - menu.coins()))
		if compact:
			StationKit.shrink(mend_all, 13, 10.0, 4.0)
		right.add_child(mend_all)
	purse = StationKit.Purse.new(menu.coins(), 24)
	purse.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	right.add_child(purse)
	if leave != null:
		leave.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		right.add_child(leave)
	if not menu.last_result.is_empty():
		var l := UIStyle.label(String(menu.last_result.get("text", "")), 14, UIStyle.MUTED)
		l.autowrap_mode = TextServer.AUTOWRAP_OFF
		l.clip_text = true
		l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		l.tooltip_text = l.text
		add_child(l)

func _pills() -> void:
	_empty(pills_host)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	pills_host.add_child(row)
	var items: Array = []
	for g in GROUPS:
		items.append([g[0], g[1], str(_count(g[0]))])
	var pills := StationKit.pills(items, group, func(id: String):
		group = id
		menu.smith_group = id
		_pills()
		_list(), compact)
	pills.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var forge := StationKit.button("Forge a new weapon from nothing", func(): menu._scratch_forge(), true)
	forge.autowrap_mode = TextServer.AUTOWRAP_OFF
	if compact:
		StationKit.shrink(forge, 13, 10.0, 4.0)
	forge.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	if compact:
		# (Room is short: the pills take the width, and the forge button goes on after them.)
		pills.add_child(forge)
		row.add_child(pills)
	else:
		row.add_child(pills)
		row.add_child(forge)

func _count(g: String) -> int:
	match g:
		"arms": return _arm_rows().size()
		"sale": return Arms.bases().size()
		"works": return Arms.oddities(menu.run_seed(), _stage()).size()
		"designs": return _design_rows().size()
	return 0

func _stage() -> int:
	return int(Save.get_value("coop_stage" if Net.active() else "stage", 1))

# ---------- What can be picked ----------

## His arms: the two hands, what hangs on the smith's rack, his prosthetics.
func _arm_rows() -> Array:
	var rows: Array = [{"kind": "arm", "side": "R"}, {"kind": "arm", "side": "L"}]
	for i in (a.rack as Array).size():
		rows.append({"kind": "rack", "i": i})
	var pros: Dictionary = Body.smith_prosthetics(menu.body())
	for part in pros:
		rows.append({"kind": "pro", "part": String(part)})
	return rows

func _design_rows() -> Array:
	var out: Array = []
	var designs: Array = load("res://scripts/ui/forge.gd").gallery()
	for i in designs.size():
		if not Arms.buy_design(a, designs[i]).has("error"):
			out.append({"kind": "design", "i": i})
	return out

func _valid(s: Dictionary) -> bool:
	match String(s.get("kind", "")):
		"arm": return ["R", "L"].has(String(s.get("side", "")))
		"rack": return int(s.get("i", -1)) >= 0 and int(s.get("i", -1)) < (a.rack as Array).size()
		"base": return not Arms.base(String(s.get("key", ""))).is_empty()
		"odd": return int(s.get("i", -1)) >= 0 and int(s.get("i", -1)) < Arms.oddities(menu.run_seed(), _stage()).size()
		"design": return int(s.get("i", -1)) >= 0 and int(s.get("i", -1)) < (load("res://scripts/ui/forge.gd").gallery() as Array).size()
		"pro": return Body.smith_prosthetics(menu.body()).has(String(s.get("part", "")))
	return false

## The weapon a pick stands for (null: an empty hand, or a prosthetic).
func _weapon_of(s: Dictionary) -> Variant:
	match String(s.kind):
		"arm": return a.main if String(s.side) == "R" else a.off
		"rack": return a.rack[int(s.i)]
		"base": return Data.preset(String(s.key))
		"odd": return Arms.oddities(menu.run_seed(), _stage())[int(s.i)]
		"design": return (load("res://scripts/ui/forge.gd").gallery() as Array)[int(s.i)]
	return null

func _pick(s: Dictionary) -> void:
	if busy or s == sel:
		return
	StationKit.tick()
	sel = s
	menu.smith_sel = s
	_list()
	_show()

# ---------- The list on the right ----------

func _list() -> void:
	_empty(list_host)
	var scroll := ScrollContainer.new()
	scroll.follow_focus = true
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size.y = 110.0
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	list_host.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 8)
	scroll.add_child(box)
	match group:
		"arms":
			for r in _arm_rows():
				box.add_child(_row(r))
		"sale":
			var grid := _grid()
			box.add_child(grid)
			for b in Arms.bases():
				grid.add_child(_sale_tile(b))
		"works":
			box.add_child(StationKit.kicker("Vulcanus's masterworks · this bout only, one of each", UIStyle.GOLD, 12, true))
			var grid := _grid()
			box.add_child(grid)
			var key := "%d:%d" % [menu.run_seed(), _stage()]
			var sold: Array = (Save.get_value("oddities_sold", {}) as Dictionary).get(key, [])
			var list := Arms.oddities(menu.run_seed(), _stage())
			for i in list.size():
				grid.add_child(_odd_tile(list[i], i, sold.has(int(list[i].oddity.i))))
		"designs":
			var rows := _design_rows()
			if rows.is_empty():
				var none := UIStyle.label("You have made no designs yet: draw one at the forge and the smith will make it to order.", 14, UIStyle.MUTED)
				none.custom_minimum_size.x = right_w - 40.0
				box.add_child(none)
			box.add_child(StationKit.kicker("Your designs · made to order", UIStyle.BRONZE, 12, true))
			var grid := _grid()
			box.add_child(grid)
			for r in rows:
				grid.add_child(_design_tile(r))
	_stats()

func _grid() -> GridContainer:
	var g := GridContainer.new()
	g.columns = clampi(int(right_w / (150.0 if compact else 170.0)), 2, 5)
	g.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	g.add_theme_constant_override("h_separation", 10)
	g.add_theme_constant_override("v_separation", 10)
	return g

## What names a thing of the smith's (an arm, a rack's place, a ware) for the focus to find it again.
func _key_of(r: Dictionary) -> String:
	return "%s:%s" % [r.get("kind", ""), r.get("key", r.get("i", r.get("side", r.get("part", ""))))]

## One of his arms as a row: a picture, what it is, how sound.
func _row(r: Dictionary) -> Control:
	var on := r == sel
	var d: Variant = _weapon_of(r)
	var kind := String(r.kind)
	var card := StationKit.card(UIStyle.GOLD if on else UIStyle.BRONZE_DARK, 2 if on else 1, 8, 8)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(row)
	var pic := 48 if compact else 72
	var tex := TextureRect.new()
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex.custom_minimum_size = Vector2(pic, pic)
	tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(tex)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	col.add_theme_constant_override("separation", 2)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(col)
	var title := ""
	var name_ := ""
	var sub := ""
	var cond := -1.0
	match kind:
		"arm":
			title = "Main hand" if String(r.side) == "R" else "Off hand"
			if d == null:
				name_ = Loc.t("Empty")
				sub = Loc.t("Nothing in this hand")
			else:
				name_ = str(d.get("name", "?"))
				cond = Arms.condition(a, String(r.side))
				sub = Loc.t("%d voxels") % (d.voxels as Array).size()
				tex.tree_entered.connect(func(): Thumbs.weapon(tex, d, "arm:%s:%s" % [r.side, str(d.hash())]), CONNECT_ONE_SHOT)
		"rack":
			title = "Kept for you"
			name_ = str(d.get("name", "?"))
			sub = Loc.t("%d voxels") % (d.voxels as Array).size()
			tex.tree_entered.connect(func(): Thumbs.weapon(tex, d, "rack:%d:%s" % [r.i, str(d.hash())]), CONNECT_ONE_SHOT)
		"pro":
			var part := String(r.part)
			var pk: String = Body.smith_prosthetics(menu.body())[part]
			var lv := Body.pro_level(menu.body(), part)
			title = Body.label(part)
			name_ = Loc.t(String(Body.PROSTHETICS[pk].name))
			sub = Loc.t("%s · works %d%% as well as a limb of your own") % [Loc.t(String(Body.PRO_STEPS[lv - 1].label)) if lv > 0 else Loc.t("As the physician made it"), int(round(Body.pro_fn(pk, lv) * 100.0))]
			tex.tree_entered.connect(func(): Thumbs.prosthetic(tex, pk, part, lv), CONNECT_ONE_SHOT)
	col.add_child(StationKit.kicker(title, UIStyle.BRONZE, 12, true))
	var n := UIStyle.label(name_, 16 if compact else 18, UIStyle.TEXT)
	n.autowrap_mode = TextServer.AUTOWRAP_OFF
	n.clip_text = true
	n.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	col.add_child(n)
	var sl := UIStyle.label(sub, 12, UIStyle.MUTED)
	sl.autowrap_mode = TextServer.AUTOWRAP_OFF
	sl.clip_text = true
	sl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	col.add_child(sl)
	if cond >= 0.0:
		var bar := StationKit.Bar.new(6.0, UIStyle.GOLD if cond >= 0.8 else (UIStyle.BRONZE if cond >= 0.4 else StationKit.BAD))
		bar.value = cond
		col.add_child(bar)
	StationKit.pickable(card, func(): _pick(r), "row:" + _key_of(r))
	if on:
		card.set_meta("start", true)
	return card

func _tile_frame(r: Dictionary, border: Color, width := 1) -> PanelContainer:
	var on := r == sel
	var t := StationKit.card(UIStyle.GOLD if on else border, 2 if on else width, 8, 8)
	t.custom_minimum_size = Vector2(0, 110.0 if compact else 150.0)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t.mouse_filter = Control.MOUSE_FILTER_STOP
	t.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	StationKit.pickable(t, func(): _pick(r), "tile:" + _key_of(r))
	if on:
		t.set_meta("start", true)
	return t

func _tile_body(t: PanelContainer, d: Dictionary, key: String, name_: String, sub: String, sub_color: Color) -> TextureRect:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t.add_child(col)
	var pic := Control.new()
	pic.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pic.custom_minimum_size.y = 44.0 if compact else 78.0
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(pic)
	var tex := TextureRect.new()
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pic.add_child(tex)
	tex.tree_entered.connect(func(): Thumbs.weapon(tex, d, key), CONNECT_ONE_SHOT)
	var nm := UIStyle.label(name_, 14 if not compact else 13, UIStyle.TEXT)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nm.autowrap_mode = TextServer.AUTOWRAP_OFF
	nm.clip_text = true
	nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(nm)
	var sb := UIStyle.label(sub, 13, sub_color)
	sb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sb.autowrap_mode = TextServer.AUTOWRAP_OFF
	sb.clip_text = true
	sb.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	sb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(sb)
	return tex

func _sale_tile(b: Dictionary) -> Control:
	var key: String = b.key
	var r := {"kind": "base", "key": key}
	var cost := _base_cost(key)
	var t := _tile_frame(r, UIStyle.BRONZE_DARK)
	_tile_body(t, Data.preset(key), "base:" + key, str(b.name), "%d %s" % [Arms.base_price(b), Loc.t("denarii")], UIStyle.GOLD if cost.afford else StationKit.BAD)
	return t

## What a base costs him now: whether he can pay, the trade-in on what he hands over.
func _base_cost(key: String) -> Dictionary:
	var b := Arms.base(key)
	var pre := Arms.buy(a, key)
	var choose: bool = pre.has("choose")
	var trade := 0
	if choose:
		for sd in pre.choose:
			trade = maxi(trade, Arms.value(a.main if sd == "R" else a.off) / 2)
	else:
		trade = int(pre.get("trade_in", 0))
	return {"pre": pre, "choose": choose, "trade": trade, "afford": Arms.base_price(b) <= menu.coins() + trade}

func _odd_tile(d: Dictionary, i: int, sold: bool) -> Control:
	var tier := int(d.oddity.get("tier", 1))
	var r := {"kind": "odd", "i": i}
	var t := _tile_frame(r, Masterworks.colour(tier), 2 if tier < 4 else 3)
	var price := Arms.oddity_price(d)
	var sub := Loc.t("Sold") if sold else "%d %s" % [price, Loc.t("denarii")]
	_tile_body(t, d, "odd:%d:%d:%d" % [menu.run_seed(), _stage(), int(d.oddity.i)], str(d.get("name", "?")), sub, UIStyle.MUTED if sold else UIStyle.GOLD)
	if sold:
		t.modulate = Color(1, 1, 1, 0.55)
	return t

func _design_tile(r: Dictionary) -> Control:
	var d: Dictionary = (load("res://scripts/ui/forge.gd").gallery() as Array)[int(r.i)]
	var t := _tile_frame(r, UIStyle.BRONZE_DARK)
	_tile_body(t, d, "gallery:%d" % d.hash(), str(d.get("name", "?")), "%d %s" % [Arms.design_price(d), Loc.t("denarii")], UIStyle.GOLD)
	return t

# ---------- What it does ----------

func _stats() -> void:
	_empty(stats_host)
	var d: Variant = _weapon_of(sel) if String(sel.kind) != "pro" else null
	if d == null or not (d is Dictionary) or (d.get("voxels", []) as Array).is_empty() or compact:
		return
	var card := StationKit.card(UIStyle.BRONZE_DARK, 1, 10, 8)
	stats_host.add_child(card)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 5)
	card.add_child(col)
	col.add_child(StationKit.kicker("What it does"))
	var bars: Dictionary = ForgeLib.five_bars(d)
	for r in ForgeLib.bar_rows(d):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var l := UIStyle.label(r[1], 13, UIStyle.MUTED)
		l.custom_minimum_size.x = 96.0
		l.autowrap_mode = TextServer.AUTOWRAP_OFF
		row.add_child(l)
		var colr: Color = Color(0.85, 0.32, 0.2) if r[0] == "damage" else (UIStyle.BRONZE if r[0] == "armour" else (Color(0.56, 0.7, 0.8) if r[0] == "durability" else UIStyle.GOLD))
		var bar := StationKit.Bar.new(9.0, colr)
		bar.value = float(bars.get(r[0], 0.0))
		row.add_child(bar)
		var v := UIStyle.label("%d" % int(round(float(bars.get(r[0], 0.0)) * 100.0)), 13, UIStyle.TEXT)
		v.custom_minimum_size.x = 30.0
		v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		v.autowrap_mode = TextServer.AUTOWRAP_OFF
		row.add_child(v)
		col.add_child(row)

# ---------- The anvil ----------

func _show() -> void:
	var kind := String(sel.kind)
	var d: Variant = _weapon_of(sel)
	var root: Node3D
	# (Standing still, seen from the side and above: its length across the picture.)
	var opts := {"stand": "anvil", "yaw": 0.3, "pitch": 0.42, "spin": 0.0, "exact": true, "k": 1.12}
	if kind == "pro":
		var part := String(sel.part)
		var pk: String = Body.smith_prosthetics(menu.body())[part]
		root = Thumbs.prosthetic_model(pk, part, Body.pro_level(menu.body(), part))
	elif d is Dictionary and not (d.get("voxels", []) as Array).is_empty():
		root = Thumbs.model(d)
		Stage3D.lay_flat(root)
	else:
		root = Node3D.new()
		opts["box"] = AABB(Vector3(-0.5, -0.04, -0.06), Vector3(1.0, 0.08, 0.12))
	stage.show_model(root, opts)
	_hammer()
	_detail()

const HAMMER_UP := 1.3      # the hammer raised: the head out to the side and back
const HAMMER_HIT := 2.4     # and struck: the head down on the blade

func _aim() -> Vector3:
	var s: float = hammer.get_meta("s", 0.3)
	return Vector3(stage.box.size.x * 0.12, stage.box.position.y + stage.box.size.y + s * 0.1, 0.0)

func _hammer() -> void:
	var s := clampf(maxf(stage.box.size.x, stage.box.size.z) * 0.5, 0.2, 0.6)
	hammer = Stage3D.hammer_node(s)
	stage.pivot.add_child(hammer)
	hammer.set_meta("s", s)
	# Held over the blade from the right, the head up till it falls.
	var aim := _aim()
	hammer.position = aim + Vector3(0.675 * s, 0.737 * s, 0.0)
	hammer.rotation.z = HAMMER_UP
	stage.refit(AABB(aim + Vector3(-0.3 * s, 0.0, -0.2 * s), Vector3(1.6 * s, 1.2 * s, 0.4 * s)))

func _work(then: Callable, strikes := 3, cost := 0) -> void:
	if busy:
		return
	busy = true
	var aim := _aim()
	var tw := create_tween()
	for i in strikes:
		tw.tween_property(hammer, "rotation:z", HAMMER_UP, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(hammer, "rotation:z", HAMMER_HIT, 0.09).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_callback(func():
			stage.bump(0.9)
			stage.sparks(aim + Vector3(randf_range(-0.04, 0.04), 0.0, 0.0))
			if Sfx:
				Sfx.play("clang", Vector3.ZERO, 0.8))
	tw.tween_property(hammer, "rotation:z", HAMMER_UP, 0.2)
	tw.tween_callback(func():
		busy = false
		menu.station_note = {"rise": ("−%d" % cost) if cost > 0 else ""}
		then.call())

# ---------- The detail ----------

func _detail() -> void:
	_empty(detail_card)
	var sc := ScrollContainer.new()
	sc.follow_focus = true
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.custom_minimum_size.y = 60.0
	detail_card.add_child(sc)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 6)
	sc.add_child(col)
	match String(sel.kind):
		"arm": _detail_arm(col)
		"rack": _detail_rack(col)
		"base": _detail_base(col)
		"odd": _detail_odd(col)
		"design": _detail_design(col)
		"pro": _detail_pro(col)

func _head(col: VBoxContainer, kicker: String, name_: String, sub: String) -> void:
	col.add_child(StationKit.kicker(kicker, UIStyle.BRONZE, 12, true))
	col.add_child(StationKit.heading(name_, 22 if compact else 26))
	if sub != "":
		var l := UIStyle.label(sub, 13, UIStyle.MUTED)
		l.custom_minimum_size.x = left_w - 50.0
		col.add_child(l)

func _wide(c: Control) -> Control:
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return c

func _flow() -> HFlowContainer:
	var f := HFlowContainer.new()
	f.add_theme_constant_override("h_separation", 8)
	f.add_theme_constant_override("v_separation", 8)
	return f

## A job of the smith as a card to press: the hammer works, then it is done and paid.
func _job(title: String, desc: String, price: String, ok: bool, why: String, cb: Callable) -> Control:
	if compact:
		# (Room is short: a button, what it is for in its tip.)
		var b := StationKit.button(Loc.t(title) + "  ·  " + (price.get_slice(" ", 0) if ok else Loc.t(why)), cb, ok)
		b.disabled = not ok
		b.autowrap_mode = TextServer.AUTOWRAP_OFF
		b.tooltip_text = Loc.t(desc)
		StationKit.shrink(b, 13, 10.0, 5.0)
		b.set_meta("job", title)
		b.set_meta("ok", ok)
		b.set_meta("cb", cb)
		return b
	var card := StationKit.card(UIStyle.BRONZE if ok else Color(UIStyle.BRONZE_DARK, 0.6), 1, 8, 6, Color(0.14, 0.1, 0.07, 0.97) if ok else Color(0.07, 0.055, 0.04, 0.9))
	card.custom_minimum_size = Vector2(120.0 if compact else 150.0, 0)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(v)
	var t := UIStyle.label(Loc.t(title).to_upper(), 12, UIStyle.GOLD if ok else UIStyle.MUTED)
	t.autowrap_mode = TextServer.AUTOWRAP_OFF
	t.add_theme_font_override("font", UIStyle.serif(1, 700))
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(t)
	if not compact:
		var d := UIStyle.label(Loc.t(desc), 12, UIStyle.MUTED if ok else Color(UIStyle.MUTED, 0.75))
		d.custom_minimum_size.x = 120.0
		d.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(d)
	var p := UIStyle.label(price if ok else Loc.t(why), 14, UIStyle.GOLD if ok else Color(UIStyle.MUTED, 0.75))
	p.autowrap_mode = TextServer.AUTOWRAP_OFF
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(p)
	card.set_meta("job", title)
	card.set_meta("ok", ok)
	card.set_meta("cb", cb)
	if ok:
		StationKit.pickable(card, cb, "job:" + title)
	return card

func _detail_arm(col: VBoxContainer) -> void:
	var side := String(sel.side)
	var d = a.main if side == "R" else a.off
	var kicker := "Main hand" if side == "R" else "Off hand"
	if d == null:
		_head(col, kicker, Loc.t("Empty"), "")
		var e := UIStyle.label("Empty: buy a shield or a dagger from the rack, or have one made", 14, UIStyle.MUTED)
		e.custom_minimum_size.x = left_w - 50.0
		col.add_child(e)
		var mk := StationKit.button("Forge a weapon for the off hand", func(): menu._scratch_forge("L"))
		mk.tooltip_text = "Built block by block at the anvil, paid for at what it is worth"
		col.add_child(mk)
		return
	var cond := int(Arms.condition(a, side) * 100.0)
	var coat: String = Arms.COATING_NAMES.get(d.get("imbue", ""), "")
	_head(col, kicker, str(d.get("name", "?")), Loc.t("%s%d voxels") % [(Loc.t(coat) + " · ") if coat != "" else "", d.voxels.size()])
	var crow := HBoxContainer.new()
	crow.add_theme_constant_override("separation", 10)
	var bar := StationKit.Bar.new(10.0, UIStyle.GOLD if cond >= 80 else (UIStyle.BRONZE if cond >= 40 else StationKit.BAD))
	bar.value = float(cond) / 100.0
	crow.add_child(bar)
	var cl := UIStyle.label(Loc.t("condition %d%%") % cond, 13, UIStyle.TEXT)
	cl.autowrap_mode = TextServer.AUTOWRAP_OFF
	crow.add_child(cl)
	col.add_child(crow)
	var jobs := _flow()
	col.add_child(jobs)
	var rc := Arms.repair_cost(a, side)
	jobs.add_child(_job("Mend", "The smith puts back every voxel it has lost.", Loc.t("%d denarii") % rc, rc > 0 and rc <= menu.coins(), "Sound" if rc == 0 else Loc.t("%d more needed") % (rc - menu.coins()), func():
		_work(func(): menu._pay(Arms.repair(menu.arms(), side)), 3, rc)))
	for id in ["whetstone", "temper"]:
		var why := Arms.upgrade_why_not(id, d)
		var price := Arms.upgrade_price(id, d) if why == "" else 0
		var ok: bool = why == "" and price <= menu.coins()
		var shown_why: String = why if why != "" else Loc.t("%d more needed") % (price - menu.coins())
		var uid: String = id
		jobs.add_child(_job(String(Arms.UPGRADES[id].label), String(Arms.UPGRADES[id].desc), Loc.t("%d denarii") % price, ok, shown_why, func():
			_work(func(): menu._pay(Arms.upgrade(menu.arms(), side, uid)), 3, price)))
	# (On a small screen the jobs and the rest are one run of buttons.)
	var more := jobs
	if not compact:
		more = _flow()
		col.add_child(more)
	var rs := StationKit.button("Reshape in the forge", func(): menu.open_forge(side))
	StationKit.shrink(rs, 14, 12.0, 6.0)
	more.add_child(rs)
	var nw := StationKit.button("Forge a new one for this hand", func(): menu._scratch_forge(side))
	nw.tooltip_text = Loc.t("A new weapon from nothing for the %s: the one there now is traded in for half its worth") % Loc.t("main hand" if side == "R" else "off hand")
	StationKit.shrink(nw, 14, 12.0, 6.0)
	more.add_child(nw)
	var got := Arms.sale_price(d)
	var sl := StationKit.button((Loc.t("Sell · you get %d denarii") % got) if not Arms.is_stick(d) else "Sell · the stick fetches nothing", func(): menu._sell_confirm(side))
	sl.disabled = Arms.is_stick(d)
	sl.tooltip_text = Loc.t("Vulcanus buys it for half its worth: the main hand is left with the training stick" if side == "R" else "Vulcanus buys it for half its worth: the off hand is left empty")
	StationKit.shrink(sl, 14, 12.0, 6.0)
	more.add_child(sl)

func _detail_rack(col: VBoxContainer) -> void:
	var i := int(sel.i)
	var d: Dictionary = a.rack[i]
	_head(col, "Kept for you", str(d.get("name", "?")), Loc.t("%d voxels") % d.voxels.size())
	var hands: Dictionary = Arms.hands_of(menu.body())
	var racts := _flow()
	col.add_child(racts)
	for hs in ["R", "L"]:
		var side_: String = hs
		var tb := StationKit.button("Take it in the main hand" if hs == "R" else "Take it in the off hand", func(): menu._pay(Arms.take_from_rack(menu.arms(), i, side_)))
		tb.disabled = not hands[hs]
		tb.tooltip_text = Loc.t("Your right hand cannot hold it" if hs == "R" else "Your left hand cannot hold it") if not hands[hs] else Loc.t("Off the rack into that hand; what the hand holds now goes up in its place")
		racts.add_child(tb)

func _detail_pro(col: VBoxContainer) -> void:
	var part := String(sel.part)
	var b: Dictionary = menu.body()
	var kind: String = Body.smith_prosthetics(b)[part]
	var lv := Body.pro_level(b, part)
	_head(col, Body.label(part), Loc.t(String(Body.PROSTHETICS[kind].name)), "")
	var made := Loc.t(String(Body.PRO_STEPS[lv - 1].label)) if lv > 0 else Loc.t("As the physician made it")
	var info := UIStyle.label(Loc.t("%s · works %d%% as well as a limb of your own") % [made, int(round(Body.pro_fn(kind, lv) * 100.0))], 13, UIStyle.GOLD if lv > 0 else UIStyle.MUTED)
	info.custom_minimum_size.x = left_w - 50.0
	col.add_child(info)
	var jobs := _flow()
	col.add_child(jobs)
	if lv < Body.PRO_STEPS.size():
		var step: Dictionary = Body.PRO_STEPS[lv]
		var price := Body.pro_step_price(kind, lv)
		jobs.add_child(_job(String(step.label), String(step.desc), Loc.t("%d denarii") % price, price <= menu.coins(), Loc.t("%d more needed") % (price - menu.coins()), func():
			_work(func(): menu._pay_body(Body.upgrade_prosthetic(menu.body(), part)), 3, price)))
	else:
		jobs.add_child(_job("Nothing finer can be made", "", "", false, "Nothing finer can be made", func(): pass))

## The price he pays for a thing, and what he would have in his purse after, as lines.
func _cost_lines(col: VBoxContainer, price: int, trade := 0, trade_what := "") -> void:
	var pay := maxi(0, price - trade)
	var short: int = pay - int(menu.coins())
	var l := UIStyle.label((Loc.t("Costs %d · you have %d") % [pay, menu.coins()]) + ((Loc.t(" (%d more needed)") % short) if short > 0 else ""), 15, UIStyle.GOLD if short <= 0 else StationKit.BAD)
	l.custom_minimum_size.x = left_w - 50.0
	if trade > 0:
		l.tooltip_text = Loc.t("%d, less %d for %s") % [price, trade, Loc.t(trade_what)]
	col.add_child(l)

func _detail_base(col: VBoxContainer) -> void:
	var key := String(sel.key)
	var b := Arms.base(key)
	var c := _base_cost(key)
	var pre: Dictionary = c.pre
	_head(col, "For sale", str(b.name), "")
	var goes := "both hands full: you pick which one he takes" if c.choose else ("into both hands" if pre.get("sold", []).size() > 1 else ("into the main hand" if pre.get("side", "R") == "R" else "into the off hand"))
	var gl := UIStyle.label(goes, 13, UIStyle.MUTED)
	gl.custom_minimum_size.x = left_w - 50.0
	col.add_child(gl)
	_cost_lines(col, Arms.base_price(b), int(c.trade), "your old one" if c.choose else "what you hand in")
	var row := _flow()
	col.add_child(row)
	var buy := StationKit.button("Buy", func():
		var r := Arms.buy(menu.arms(), key)
		if r.has("choose"):
			menu._sell_choice(str(b.name), func(sd): return Arms.buy(menu.arms(), key, sd), r.choose)
		else:
			menu._pay(r), bool(c.afford))
	buy.disabled = not bool(c.afford)
	buy.tooltip_text = "" if c.afford else "Not enough in your purse"
	row.add_child(buy)
	if Arms.off_hand_ok(key):
		var pre_l := Arms.buy(a, key, "", "L")
		var afford_l: bool = Arms.base_price(b) <= menu.coins() + int(pre_l.get("trade_in", 0))
		var buy_l := StationKit.button("For the off hand", func(): menu._pay(Arms.buy(menu.arms(), key, "", "L")), afford_l)
		buy_l.disabled = not afford_l
		buy_l.tooltip_text = (Loc.t("Into the off hand, %s") % Loc.t("handing in what is there" if int(pre_l.get("trade_in", 0)) > 0 else "the main hand keeps its weapon")) if afford_l else "Not enough in your purse"
		row.add_child(buy_l)

func _detail_odd(col: VBoxContainer) -> void:
	var i := int(sel.i)
	var d: Dictionary = Arms.oddities(menu.run_seed(), _stage())[i]
	var idx := int(d.oddity.i)
	var tier := int(d.oddity.get("tier", 1))
	var key := "%d:%d" % [menu.run_seed(), _stage()]
	var sold: Array = (Save.get_value("oddities_sold", {}) as Dictionary).get(key, [])
	var price := Arms.oddity_price(d)
	_head(col, Masterworks.title(tier), str(d.get("name", "?")), "")
	var gems: Array = []
	for v in d.voxels:
		if Weapon.GEMS.has(v[3]) and not gems.has(v[3]):
			gems.append(v[3])
	if not gems.is_empty():
		var gl := UIStyle.label(Loc.t("Set with %s") % ", ".join(gems), 13, UIStyle.MUTED)
		gl.custom_minimum_size.x = left_w - 50.0
		col.add_child(gl)
	if sold.has(idx):
		col.add_child(UIStyle.label("Sold", 15, UIStyle.MUTED))
	else:
		_cost_lines(col, price)
	var row := _flow()
	col.add_child(row)
	if not sold.has(idx):
		var mark_sold := func():
			var all: Dictionary = Save.get_value("oddities_sold", {})
			var got: Array = all.get(key, [])
			if not got.has(idx):
				got.append(idx)
			all[key] = got
			Save.set_value("oddities_sold", all)
		var buy := StationKit.button("Buy", func():
			var r := Arms.buy_design(menu.arms(), d, "", price)
			if r.has("choose"):
				menu._sell_choice(str(d.get("name", "it")), func(sd): return Arms.buy_design(menu.arms(), d, sd, price), r.choose, mark_sold)
			else:
				if not (r.has("error") or int(r.get("cost", 0)) > menu.coins()):
					mark_sold.call()
				menu._pay(r), true)
		buy.disabled = price > menu.coins() + (Arms.value(a.main) + Arms.value(a.off)) / 2
		row.add_child(buy)
	var keep := d.duplicate(true)
	keep.erase("oddity")
	var saved: bool = load("res://scripts/ui/forge.gd").gallery().any(func(o): return o.get("voxels") == keep.voxels)
	var sv := StationKit.button("In My designs" if saved else "Save to My designs", func():
		var mine: Array = load("res://scripts/ui/forge.gd").gallery()
		if not mine.any(func(o): return o.get("voxels") == keep.voxels):
			mine.push_front(keep)
			Save.set_value("forge_gallery", mine.slice(0, 24))
		menu.show_screen("yard"))
	sv.disabled = saved
	row.add_child(sv)

func _detail_design(col: VBoxContainer) -> void:
	var d: Dictionary = (load("res://scripts/ui/forge.gd").gallery() as Array)[int(sel.i)]
	var price := Arms.design_price(d)
	_head(col, "Your design · made to order", str(d.get("name", "?")), Loc.t("%d blocks · made to order") % d.voxels.size())
	_cost_lines(col, price)
	var buy := StationKit.button("Have it made", func():
		var r := Arms.buy_design(menu.arms(), d)
		if r.has("choose"):
			menu._sell_choice(str(d.get("name", "it")), func(sd): return Arms.buy_design(menu.arms(), d, sd), r.choose)
		else:
			menu._pay(r), true)
	buy.disabled = price > menu.coins() + (Arms.value(a.main) + Arms.value(a.off)) / 2
	col.add_child(buy)

func _empty(c: Node) -> void:
	StationKit.keep_focus(c)
	for x in c.get_children():
		c.remove_child(x)
		x.queue_free()
