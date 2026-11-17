class_name ArmourBench
extends HBoxContainer
## The smith's bench for armour of the player's own making: where it goes, what it is made of
## and how much of the part it covers, set on the right; the gladiator, in the new look, turning
## in what he wears and in the piece as it would fit him; what it keeps out, weighs and costs on
## the left. Made, paid for and worn (Menu._forge_armour); or, while its bench is open
## (Armory.plate_bench_open), shaped plate by plate (ArmourForge).
## Drawing and asking only.

var menu: Control
var smith: Control
var stage: ArmourStage
var detail_card: PanelContainer
var controls: VBoxContainer
var worn: Array = []
var compact := false
var left_w := 520.0
var right_w := 800.0

static func build(m: Control, s: Control) -> ArmourBench:
	var a := ArmourBench.new()
	a.menu = m
	a.smith = s
	s.add_child(a)
	a.setup()
	return a

func setup() -> void:
	menu.bench_mode = "smith"
	compact = smith.compact
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 18)
	worn = menu.worn_armor()
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
	detail_card.size_flags_stretch_ratio = 7.0
	detail_card.custom_minimum_size.y = 190.0
	left.add_child(detail_card)
	var sc := ScrollContainer.new()
	sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(sc)
	controls = VBoxContainer.new()
	controls.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	controls.add_theme_constant_override("separation", 10)
	sc.add_child(controls)
	_controls()
	_changed(true)

func _empty(c: Node) -> void:
	for x in c.get_children():
		c.remove_child(x)
		x.queue_free()

func _def() -> Dictionary:
	var b: Dictionary = menu.bench
	return Armory.design_piece(b.region, b.mat, b.y0, b.y1, b.front, b.cap, b.name)

## Something on the bench changed: the numbers are drawn again, and the man is dressed in the piece.
func _changed(first := false) -> void:
	var def := _def()
	_detail(def)
	var ids: Array = Armory.register([def])
	var wear: Array = worn
	if not ids.is_empty():
		var t: Dictionary = Armory.buy(worn, String(ids[0]))
		wear = t.get("worn", worn)
	stage.dress(wear)
	if first:
		var note: Dictionary = menu.station_note
		menu.station_note = {}
		StationKit.show_note(menu, smith.purse, note)

func _group(title: String) -> VBoxContainer:
	var g := VBoxContainer.new()
	g.add_theme_constant_override("separation", 6)
	g.add_child(StationKit.kicker(title))
	controls.add_child(g)
	return g

func _controls() -> void:
	var b: Dictionary = menu.bench
	var where := _group("Where")
	var wk: Array = []
	for k in Armory.REGIONS.keys():
		wk.append([k, Armory.REGIONS[k].label, ""])
	where.add_child(StationKit.pills(wk, String(b.region), func(id: String):
		b.region = id
		_redo(), compact))
	var mat := _group("Material")
	var mk: Array = []
	for k in Armory.BENCH_MATS:
		mk.append([k, String(k).capitalize(), ""])
	mat.add_child(StationKit.pills(mk, String(b.mat), func(id: String):
		b.mat = id
		_redo(), compact))
	var info := UIStyle.label("", 13, UIStyle.MUTED)
	info.text = Loc.t("%s   Protection %s   Weight %s") % [Loc.t(String(b.mat).capitalize()), menu._dots(float(Data.material(b.mat).get("hardness", 0.5))), menu._dots(clampf(float(Data.material(b.mat).get("mass", 0.03)) / 0.1, 0.0, 1.0))]
	mat.add_child(info)
	var covers := _group("Covers")
	for sl_def in [["From", "y0"], ["To", "y1"]]:
		var key: String = sl_def[1]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var l := UIStyle.label(Loc.t(sl_def[0]), 14, UIStyle.MUTED)
		l.autowrap_mode = TextServer.AUTOWRAP_OFF
		l.custom_minimum_size.x = 56.0
		row.add_child(l)
		var sl := HSlider.new()
		sl.min_value = 0.0
		sl.max_value = 1.0
		sl.step = 0.05
		sl.value = float(b[key])
		sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var pct := UIStyle.label("%d%%" % int(round(sl.value * 100.0)), 13, UIStyle.TEXT)
		pct.custom_minimum_size.x = 44.0
		pct.autowrap_mode = TextServer.AUTOWRAP_OFF
		sl.value_changed.connect(func(v: float): pct.text = "%d%%" % int(round(v * 100.0)))
		sl.drag_ended.connect(func(_c):
			b[key] = sl.value
			_redo())
		row.add_child(sl)
		row.add_child(pct)
		covers.add_child(row)
	var opts := _group("Shape")
	var fr := CheckBox.new()
	fr.text = Loc.t("Front and sides only")
	fr.button_pressed = b.front
	fr.toggled.connect(func(x):
		b.front = x
		_redo())
	opts.add_child(fr)
	var cp := CheckBox.new()
	cp.text = Loc.t("Cap the top")
	cp.button_pressed = b.cap
	cp.toggled.connect(func(x):
		b.cap = x
		_redo())
	opts.add_child(cp)
	var nm := _group("Its name")
	var edit := LineEdit.new()
	edit.placeholder_text = Loc.t(String(_def().name))
	edit.text = String(b.name)
	edit.max_length = 24
	edit.text_changed.connect(func(x): b.name = x)
	nm.add_child(edit)

## A control was changed: the controls are drawn again (the lit one moves), the numbers and the
## man are made again.
func _redo() -> void:
	_empty(controls)
	_controls()
	_changed()

func _detail(def: Dictionary) -> void:
	_empty(detail_card)
	# (The buttons are pinned under the writing, which scrolls if it is long: never cut off.)
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
	col.add_child(StationKit.kicker("Your own make"))
	col.add_child(StationKit.heading(Loc.t(String(def.name)), 22 if compact else 26))
	var kg := Armory.design_kg(def)
	var worn_kg := 0.0
	for id in worn:
		worn_kg += Armory.kg(id)
	var with: Dictionary = Armory.burden(worn_kg + kg)
	var price := Armory.design_price(def)
	var l1 := UIStyle.label(Loc.t("Protection %s") % menu._dots(float(Data.material(String(def.mat)).get("hardness", 0.5))), 14, UIStyle.TEXT)
	l1.autowrap_mode = TextServer.AUTOWRAP_OFF
	col.add_child(l1)
	var l2 := UIStyle.label(Loc.t("Weight %.1f kg  (all you wear: %.1f kg)") % [kg, worn_kg + kg], 14, UIStyle.TEXT)
	l2.custom_minimum_size.x = left_w - 50.0
	col.add_child(l2)
	var l3 := UIStyle.label(Loc.t("Breath when running and swinging: ×%.2f") % float(with.breath) + "  ·  " + Loc.t("Pace: %d%%") % int(round(float(with.pace) * 100.0)), 13, UIStyle.MUTED)
	l3.custom_minimum_size.x = left_w - 50.0
	col.add_child(l3)
	var acts := HFlowContainer.new()
	acts.add_theme_constant_override("h_separation", 8)
	acts.add_theme_constant_override("v_separation", 8)
	outer.add_child(acts)
	var make := UIStyle.button(Loc.t("Forge and wear · %d denarii") % price, func():
		menu._forge_armour(_def()), true)
	make.disabled = price > menu.coins()
	make.autowrap_mode = TextServer.AUTOWRAP_OFF
	acts.add_child(make)
	if Armory.plate_bench_open:
		var plate := UIStyle.button("Shape it plate by plate", func(): menu._plate_bench(_def(), worn_kg))
		StationKit.shrink(plate, 14, 12.0, 8.0)
		acts.add_child(plate)
