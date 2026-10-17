extends Control
## The forge (editor.js): two ways to make a weapon, the weapon live on the anvil in the middle.
##  - Cards: pick a base (a gladius, an axe, a bow...), then up to two twists dealt from the deck
##    (longer, serrated, ice, a fish...); the smith builds it.
##  - Voxels: build it block by block: build on a face, paint, erase, draw a line or a box, with
##    mirror symmetry, undo, auto-sharpen, auto-grip and "surprise me".
## Its speed, damage and reach are shown as three bars, with the smith's opinion and what the
## training dummy would say. In the campaign every voxel costs its material's price (taken off,
## refunded); in training it is free. Take it from the smith when you are done.

var design: Dictionary
var original_value := 0
var purse := 0
var done: Callable
var free_build := false   # training: nothing costs anything
var workshop := false     # the main menu's forge: design and save to My designs, nothing taken or paid
var scratch := false      # at the smith, a new weapon from nothing (any kind), paid for as made
var family := ""          # the smith reshapes a weapon within its kind (Arms.family): "" = anything goes
const FAMILY_NAMES := {"blade": "a blade", "axe": "an axe", "spear": "a spear", "blunt": "a hammer or a mace", "shield": "a shield", "bow": "a bow", "crossbow": "a crossbow", "chain": "a chain weapon", "other": "what it is"}

var mat := "steel"
var job := "edge"
var tool := "build"
var mirror := true          # left and right alike (across the blade's flat)
var mirror_z := false        # front and back alike (across its edge)
const ERASE_EVERY := 0.18    # a held right button takes a block off no faster than this (s)
var mode := "cards"
var base_key := ""
var picks: Array = []
var dealt: Array = []
var rng := RandomNumberGenerator.new()
var undo_stack: Array = []
var redo_stack: Array = []
var stroke := {}   # the mouse held down in the voxel view: {erase, done: cells, undo}
var line_from = null       # the first cell of a line or a box being drawn

var viewport: SubViewport
var cam: Camera3D
var weapon_root: Node3D
var anvil: MeshInstance3D
var floor_: MeshInstance3D
var ghost: MeshInstance3D
var framed := false
var cells := {}                 # Vector3i -> [mat, job]
var orbit := Vector2(0.6, 0.35)
var dist := 1.6
var dragging := false
var idle_t := 0.0
var swing_t := -1.0

var side_box: VBoxContainer
var mode_row: HBoxContainer
var mode_box: VBoxContainer
var tool_bar: PanelContainer
var name_edit: LineEdit
var bars: Control
var bar_vals := {"speed": 0.0, "damage": 0.0, "reach": 0.0}
var says: Label
var verdict: Label
var cost_label: Label

## The smith's stock, each for its own job: two metals for edges, three weights from light to
## dense for hafts and heads, gold for the crowd, four tricks and three gem sockets.
const MATS := ["steel", "iron", "wood", "stone", "lead", "gold", "explosive", "spring", "glue", "magnet", "ruby", "sapphire", "emerald"]
const JOBS := ["edge", "point", "blunt", "grip"]
const TOOLS := [["build", "Build", "Click a face: a voxel goes on it"], ["paint", "Paint", "Click voxels: give them this material and job"], ["erase", "Erase", "Click voxels: take them off (right click erases too)"], ["line", "Line", "Click one end, then the other: a haft, a blade"], ["box", "Box", "Click two corners: a block"]]

func open(d: Dictionary, coins: int, cb: Callable) -> void:
	design = d.duplicate(true)
	purse = coins
	done = cb
	rng.randomize()
	original_value = Arms.value(design)
	family = "" if free_build or scratch else Arms.family(design)
	if family == "blunt":
		job = "blunt"
	_load_cells(design)
	_build_ui()
	_show_mode(mode)
	_rebuild()

func _load_cells(d: Dictionary) -> void:
	cells.clear()
	for v in d.voxels:
		cells[Vector3i(v[0], v[1], v[2])] = [v[3], v[4]]

func _design_now() -> Dictionary:
	var out := design.duplicate(true)
	var vox := []
	for k in cells:
		vox.append([k.x, k.y, k.z, cells[k][0], cells[k][1]])
	out.voxels = vox
	out.erase("stats")
	if name_edit and name_edit.text.strip_edges() != "":
		out.name = name_edit.text.strip_edges().substr(0, 32)
	return out

# ---------- UI ----------

func _build_ui() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UIStyle.theme()
	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.045, 0.035)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var h := HBoxContainer.new()
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(h)
	var frame := PanelContainer.new()
	frame.custom_minimum_size = Vector2(470, 0)
	h.add_child(frame)
	# Three parts, top to bottom: what you are making and how (fixed), the tools for it
	# (scrolls), and what it comes to and the way out (fixed: never scrolled off the screen).
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	frame.add_child(col)
	var head := HBoxContainer.new()
	var t := UIStyle.title("THE FORGE", 34)
	t.add_theme_font_override("font", UIStyle.serif(3))
	t.add_theme_color_override("font_color", UIStyle.GOLD)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	col.add_child(head)
	mode_row = HBoxContainer.new()
	mode_row.add_theme_constant_override("separation", 4)
	for m in [["cards", "1 · Quick start", "Pick a base weapon and up to two twists: done in two clicks."], ["voxels", "2 · Shape by hand", "Add, paint and take off single blocks on the anvil."], ["gallery", "My designs", "Weapons you saved as templates: load one onto the anvil."]]:
		var key: String = m[0]
		var b := UIStyle.button(m[1], func(): _show_mode(key))
		b.toggle_mode = true
		b.tooltip_text = m[2]
		b.set_meta("mode", key)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mode_row.add_child(b)
	col.add_child(mode_row)
	var nr := HBoxContainer.new()
	var nl := UIStyle.label("Name", 14, UIStyle.MUTED)
	nl.autowrap_mode = TextServer.AUTOWRAP_OFF
	nr.add_child(nl)
	name_edit = LineEdit.new()
	name_edit.placeholder_text = "Name it"
	name_edit.max_length = 32
	name_edit.text = str(design.get("name", ""))
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nr.add_child(name_edit)
	col.add_child(nr)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(scroll)
	side_box = VBoxContainer.new()
	side_box.add_theme_constant_override("separation", 8)
	side_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(side_box)
	mode_box = VBoxContainer.new()
	mode_box.add_theme_constant_override("separation", 6)
	mode_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side_box.add_child(mode_box)
	col.add_child(HSeparator.new())
	bars = Control.new()
	bars.custom_minimum_size = Vector2(400, 62)
	bars.draw.connect(_draw_bars)
	col.add_child(bars)
	says = UIStyle.label("", 13, UIStyle.TEXT)
	says.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	says.custom_minimum_size = Vector2(420, 0)
	col.add_child(says)
	verdict = UIStyle.label("", 12, UIStyle.MUTED)
	verdict.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	verdict.custom_minimum_size = Vector2(420, 0)
	col.add_child(verdict)
	cost_label = UIStyle.label("", 15, UIStyle.BRONZE)
	cost_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cost_label.custom_minimum_size = Vector2(420, 0)
	col.add_child(cost_label)
	var end := HBoxContainer.new()
	end.add_theme_constant_override("separation", 6)
	if not workshop:
		end.add_child(UIStyle.button("Take it" if free_build else "Pay and take it", _take, true))
	end.add_child(UIStyle.button("Swing it", func(): swing_t = 0.0))
	end.add_child(UIStyle.button("Save design", _save_design, workshop))
	end.add_child(UIStyle.button("Back" if workshop else "Leave it as it was", func(): done.call(null, 0)))
	col.add_child(end)
	var right := Control.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(right)
	var svc := SubViewportContainer.new()
	svc.stretch = true
	svc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	svc.gui_input.connect(_on_view_input)
	svc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	right.add_child(svc)
	tool_bar = PanelContainer.new()
	var tbs := StyleBoxFlat.new()
	tbs.bg_color = Color(0.07, 0.05, 0.035, 0.88)
	tbs.border_color = UIStyle.BRONZE_DARK
	tbs.set_border_width_all(1)
	tbs.set_corner_radius_all(8)
	tbs.content_margin_left = 8; tbs.content_margin_right = 8; tbs.content_margin_top = 6; tbs.content_margin_bottom = 6
	tool_bar.add_theme_stylebox_override("panel", tbs)
	tool_bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	tool_bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	tool_bar.position.y = 12
	right.add_child(tool_bar)
	viewport = SubViewport.new()
	viewport.own_world_3d = true
	svc.add_child(viewport)
	viewport.msaa_3d = Viewport.MSAA_4X
	_build_smithy()

## A smithy at night: a dark room, the forge's orange glow from one side, a cool rim light from
## behind, and the weapon standing over a stone anvil.
func _build_smithy() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.09, 0.06, 0.05)
	sm.sky_horizon_color = Color(0.42, 0.2, 0.08)
	sm.ground_horizon_color = Color(0.3, 0.15, 0.06)
	sm.ground_bottom_color = Color(0.05, 0.03, 0.02)
	sm.sun_angle_max = 0.0
	sky.sky_material = sm
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.55, 0.45, 0.4)
	e.ambient_light_energy = 0.9
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	e.glow_enabled = true
	e.glow_intensity = 0.7
	e.glow_bloom = 0.08
	e.ssao_enabled = true
	e.fog_enabled = true
	e.fog_light_color = Color(0.2, 0.14, 0.1)
	e.fog_density = 0.12
	e.fog_sky_affect = 0.9
	env.environment = e
	viewport.add_child(env)
	var light := DirectionalLight3D.new()
	light.rotation = Vector3(-0.75, 0.7, 0)
	light.light_color = Color(1.0, 0.95, 0.88)
	light.light_energy = 1.5
	light.shadow_enabled = true
	viewport.add_child(light)
	var glow := OmniLight3D.new()
	glow.light_color = Color(1.0, 0.45, 0.15)
	glow.light_energy = 1.8
	glow.omni_range = 4.0
	glow.position = Vector3(-1.2, 0.2, 0.6)
	viewport.add_child(glow)
	var rim := OmniLight3D.new()
	rim.light_color = Color(0.55, 0.7, 1.0)
	rim.light_energy = 1.6
	rim.omni_range = 4.0
	rim.position = Vector3(0.6, 1.2, -1.4)
	viewport.add_child(rim)
	cam = Camera3D.new()
	cam.fov = 50.0
	viewport.add_child(cam)
	weapon_root = Node3D.new()
	viewport.add_child(weapon_root)
	anvil = MeshInstance3D.new()
	var am := BoxMesh.new()
	am.size = Vector3(0.5, 0.22, 0.3)
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color(0.22, 0.2, 0.19)
	stone.roughness = 0.6
	stone.metallic = 0.4
	am.material = stone
	anvil.mesh = am
	viewport.add_child(anvil)
	floor_ = MeshInstance3D.new()
	var fp := PlaneMesh.new()
	fp.size = Vector2(60, 60)
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.3, 0.24, 0.2)
	fm.roughness = 0.95
	fp.material = fm
	floor_.mesh = fp
	viewport.add_child(floor_)
	_dress_smithy()
	ghost = MeshInstance3D.new()
	var gb := BoxMesh.new()
	gb.size = Vector3.ONE * Data.weapon_voxel * 1.02
	var gm := StandardMaterial3D.new()
	gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gm.albedo_color = Color(1, 1, 1, 0.35)
	gb.material = gm
	ghost.mesh = gb
	ghost.visible = false
	viewport.add_child(ghost)

## The voxel smithy round the anvil (art/voxel): a stone anvil block in place of the plain box,
## a flagstone floor, and in the gloom behind it the hearth, a rack of arms, jars and crates.
## They ride on the floor, which follows the weapon's height.
func _dress_smithy() -> void:
	var block := VoxelArt.make("forge_anvil")
	if block:
		anvil.mesh = null
		anvil.add_child(block)
	var tex := Arena.load_texture("res://art/textures/flagstone_voxel.png")
	if tex:
		var fm := StandardMaterial3D.new()
		fm.albedo_texture = tex
		fm.uv1_triplanar = true
		fm.uv1_world_triplanar = true
		fm.uv1_scale = Vector3.ONE / 6.4
		fm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS_ANISOTROPIC
		fm.roughness = 0.92
		(floor_.mesh as PlaneMesh).material = fm
	# Far enough out that the orbiting camera (up to 3 m away) never ends up inside them.
	VoxelArt.place(floor_, "smithy", Vector3(-3.1, 0, 2.7), deg_to_rad(130))
	VoxelArt.place(floor_, "weapon_rack", Vector3(3.3, 0, 2.7), deg_to_rad(-130))
	VoxelArt.place(floor_, "amphora", Vector3(2.0, 0, 3.6), 0.4)
	VoxelArt.place(floor_, "amphora_wide", Vector3(2.5, 0, 3.4), 1.2)
	VoxelArt.place(floor_, "crate", Vector3(-1.6, 0, 3.7), 0.3)
	VoxelArt.place(floor_, "crate", Vector3(-0.9, 0, 4.0), 1.0)
	VoxelArt.place(floor_, "crate", Vector3(-1.6, 0.6, 3.7), 0.9)

func _show_mode(m: String) -> void:
	mode = m
	for c in mode_box.get_children():
		c.queue_free()
	for b in mode_row.get_children():
		b.button_pressed = b.get_meta("mode") == m
	match m:
		"cards":
			_cards_ui()
		"gallery":
			_gallery_ui()
		_:
			_voxels_ui()
	ghost.visible = false
	line_from = null
	if tool_bar:
		_toolbar_ui()
	_update_texts()

func _cards_ui() -> void:
	if family == "":   # (reshaping a weapon at the smith keeps it what it is: no blank anvil there)
		mode_box.add_child(UIStyle.button("Blank anvil · build from nothing", _blank))
	mode_box.add_child(UIStyle.label("1 · PICK A BASE", 13, UIStyle.BRONZE))
	var grid := GridContainer.new()
	grid.columns = 3
	mode_box.add_child(grid)
	for k in ForgeLib.BASES:
		var key: String = k
		if family != "" and Arms.BASE_FAMILY.get(key, "") != family:
			continue
		var b := UIStyle.button(ForgeLib.BASES[k].label, func(): _pick_base(key))
		b.tooltip_text = ForgeLib.BASES[k].blurb
		b.toggle_mode = true
		b.button_pressed = key == base_key
		b.custom_minimum_size = Vector2(135, 0)
		grid.add_child(b)
	if family != "" and not Arms.BASE_FAMILY.values().has(family):
		mode_box.add_child(UIStyle.label("No base for this one: Vulcanus reshapes it voxel by voxel.", 13, UIStyle.MUTED))
	if base_key == "":
		mode_box.add_child(UIStyle.label("Or switch to Voxels and reshape what is on the anvil." + ("" if family == "" else " It stays %s." % FAMILY_NAMES.get(family, "what it is")), 13, UIStyle.MUTED))
		return
	mode_box.add_child(UIStyle.label("2 · ADD UP TO %d TWISTS" % ForgeLib.MAX_PICKS, 13, UIStyle.BRONZE))
	var cards := GridContainer.new()
	cards.columns = 2
	mode_box.add_child(cards)
	var seed_ := rng.seed
	var now := ForgeLib.three_bars(ForgeLib.compute_stats(_trial(picks, seed_)))
	for k in dealt:
		var key: String = k
		var mdef: Dictionary = ForgeLib.MODIFIERS[k]
		# What it would do to the three bars, as arrows.
		var trial := picks.duplicate()
		if not trial.has(key):
			trial = (trial + [key]).slice(-ForgeLib.MAX_PICKS)
		var after := ForgeLib.three_bars(ForgeLib.compute_stats(_trial(trial, seed_)))
		var arrows := ""
		for bk in ["speed", "damage", "reach"]:
			var dv: float = after[bk] - now[bk]
			arrows += ("▲" if dv > 0.03 else ("▼" if dv < -0.03 else "·"))
		var b := UIStyle.button("%s  %s" % [mdef.label, "✔" if picks.has(key) else arrows], func(): _toggle_pick(key))
		b.tooltip_text = mdef.blurb
		b.toggle_mode = true
		b.button_pressed = picks.has(key)
		b.custom_minimum_size = Vector2(205, 0)
		cards.add_child(b)
	var row := HBoxContainer.new()
	row.add_child(UIStyle.button("Deal again", func():
		dealt = ForgeLib.deal_modifiers(base_key, rng)
		picks = picks.filter(func(p): return dealt.has(p))
		_from_cards()
		_show_mode("cards")))
	row.add_child(UIStyle.button("Customize the voxels", func(): _show_mode("voxels")))
	mode_box.add_child(row)

## A clean start: one block of grip on the anvil, everything else yours to put on it (and, at
## the smith, to pay for, block by block).
func _blank() -> void:
	_push_undo()
	for k in ["kind", "twoHanded", "throwable", "spins", "shoots", "serrated", "gem", "stats", "chain", "balance", "grips", "imbue"]:
		design.erase(k)
	design.sharpness = 0.8
	cells = {Vector3i(0, 0, 0): ["wood", "grip"]}
	base_key = ""
	picks = []
	name_edit.text = "New weapon"
	mat = "wood"
	job = "grip"
	tool = "build"
	framed = false
	_rebuild()
	_show_mode("voxels")

## The weapon these cards would make (the same dice for a silly base, so the arrows compare).
func _trial(mods: Array, seed_: int) -> Dictionary:
	var r := RandomNumberGenerator.new()
	r.seed = seed_
	return ForgeLib.build_from_cards(base_key, mods, r)

func _pick_base(k: String) -> void:
	base_key = k
	picks = []
	dealt = ForgeLib.deal_modifiers(k, rng)
	rng.seed = randi()
	_from_cards()
	_show_mode("cards")

func _toggle_pick(k: String) -> void:
	if picks.has(k):
		picks.erase(k)
	else:
		picks.append(k)
		if picks.size() > ForgeLib.MAX_PICKS:
			picks.pop_front()
	_from_cards()
	_show_mode("cards")

func _from_cards() -> void:
	_push_undo()
	var d := _trial(picks, rng.seed)
	for k in ["kind", "twoHanded", "throwable", "spins", "shoots", "sharpness", "serrated", "gem", "name", "stats", "chain", "balance", "grips", "imbue"]:
		design.erase(k)
	design.merge(d, true)
	_load_cells(d)
	name_edit.text = d.name
	framed = false
	_rebuild()

func _voxels_ui() -> void:
	mode_box.add_child(UIStyle.label("MATERIAL" + ("" if free_build else " · price per voxel"), 13, UIStyle.BRONZE))
	var mg := GridContainer.new()
	mg.columns = 5
	for m in MATS:
		var key: String = m
		var b := Button.new()
		b.text = m.capitalize() + ("" if free_build else " %d" % Arms.voxel_price(m))
		b.tooltip_text = material_text(m)
		b.toggle_mode = true
		b.button_pressed = mat == key
		b.add_theme_color_override("font_color", Weapon.voxel_color(m, "blunt").lightened(0.25))
		b.add_theme_font_size_override("font_size", 13)
		b.pressed.connect(func():
			mat = key
			_show_mode("voxels"))
		mg.add_child(b)
	mode_box.add_child(mg)
	var md := UIStyle.label(material_stats(mat), 13, UIStyle.MUTED)
	md.tooltip_text = material_text(mat)
	md.mouse_filter = Control.MOUSE_FILTER_PASS
	mode_box.add_child(md)
	mode_box.add_child(UIStyle.label("JOB", 13, UIStyle.BRONZE))
	var jr := HBoxContainer.new()
	var blunt := family == "blunt"
	for j in JOBS:
		var key: String = j
		if blunt and (key == "edge" or key == "point"):
			continue
		var b := UIStyle.button(j.capitalize(), func():
			job = key
			_show_mode("voxels"))
		b.toggle_mode = true
		b.button_pressed = job == key
		b.tooltip_text = JOB_USE[key]
		jr.add_child(b)
	mode_box.add_child(jr)
	var opts := HBoxContainer.new()
	var two := CheckBox.new()
	two.text = "Two-handed"
	two.button_pressed = design.get("twoHanded", false)
	two.toggled.connect(func(x):
		design.twoHanded = x
		_update_texts())
	opts.add_child(two)
	var thr := CheckBox.new()
	thr.text = "Throwable"
	thr.button_pressed = design.get("throwable", false)
	thr.toggled.connect(func(x):
		design.throwable = x
		_update_texts())
	opts.add_child(thr)
	mode_box.add_child(opts)
	var sl := HSlider.new()
	sl.min_value = 0.0
	sl.max_value = 1.0
	sl.step = 0.05
	sl.value = float(design.get("sharpness", 0.8))
	sl.custom_minimum_size = Vector2(220, 0)
	sl.value_changed.connect(func(x):
		design.sharpness = x
		_update_texts())
	var sr := HBoxContainer.new()
	# Not wrapped: in a row a wrapping label is squeezed to one letter a line.
	var sl_l := UIStyle.label("Sharpness", 14, UIStyle.MUTED)
	sl_l.autowrap_mode = TextServer.AUTOWRAP_OFF
	sl_l.custom_minimum_size = Vector2(90, 0)
	sr.add_child(sl_l)
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sr.add_child(sl)
	if not blunt:
		mode_box.add_child(sr)
	var cl := UIStyle.label("", 13, UIStyle.MUTED)
	cl.set_meta("checklist", true)
	cl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mode_box.add_child(cl)

## The tools over the view (shaping by hand only): what a click does, Mirror, and the fix-ups.
func _toolbar_ui() -> void:
	for c in tool_bar.get_children():
		c.queue_free()
	tool_bar.visible = mode == "voxels"
	if mode != "voxels":
		return
	var blunt := family == "blunt"
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 4)
	tool_bar.add_child(rows)
	var trow := HBoxContainer.new()
	trow.add_theme_constant_override("separation", 4)
	for td in TOOLS:
		var key: String = td[0]
		var b := UIStyle.button(td[1], func():
			tool = key
			line_from = null
			_toolbar_ui())
		b.toggle_mode = true
		b.button_pressed = tool == key
		b.tooltip_text = td[2]
		trow.add_child(b)
	var mir := CheckBox.new()
	mir.text = "Mirror ⟷"
	mir.tooltip_text = "Left and right alike"
	mir.button_pressed = mirror
	mir.toggled.connect(func(x): mirror = x)
	var mirz := CheckBox.new()
	mirz.text = "Mirror ⇅"
	mirz.tooltip_text = "Front and back alike"
	mirz.button_pressed = mirror_z
	mirz.toggled.connect(func(x): mirror_z = x)
	trow.add_child(VSeparator.new())
	trow.add_child(mir)
	trow.add_child(mirz)
	rows.add_child(trow)
	var ar := HBoxContainer.new()
	ar.add_theme_constant_override("separation", 4)
	ar.add_child(UIStyle.button("Undo", _undo))
	ar.add_child(UIStyle.button("Redo", _redo))
	ar.add_child(UIStyle.button("Clear", func():
		_push_undo()
		var keep: Dictionary = {}
		for k in cells:
			if cells[k][1] == "grip":
				keep[k] = cells[k]
		if keep.is_empty() and not cells.is_empty():
			var first = cells.keys()[0]
			keep[first] = cells[first]
		cells = keep
		_rebuild()))
	if not blunt:
		ar.add_child(UIStyle.button("Auto-sharpen", func():
			_push_undo()
			var d := _design_now()
			ForgeLib.auto_sharpen(d)
			_load_cells(d)
			_rebuild()))
	ar.add_child(UIStyle.button("Auto-grip", func():
		_push_undo()
		var d := _design_now()
		ForgeLib.auto_grip(d)
		_load_cells(d)
		_rebuild()))
	if free_build:
		ar.add_child(UIStyle.button("Surprise me", func():
			_push_undo()
			var d := ForgeLib.surprise_weapon(rng)
			for k in ["kind", "shoots", "stats", "chain", "balance", "grips"]:
				design.erase(k)
			design.merge(d, true)
			_load_cells(d)
			name_edit.text = d.name
			framed = false
			_rebuild()))
	rows.add_child(ar)

# ---------- My designs: weapons saved as templates ----------

const GALLERY_MAX := 24

## The designs this player saved (newest first), each a weapon design as the forge makes it.
static func gallery() -> Array:
	var out := []
	var g = Save.get_value("forge_gallery", [])
	if g is Array:
		for d in g:
			if d is Dictionary and d.get("voxels") is Array and not d.voxels.is_empty() and d.voxels.size() <= ForgeLib.MAX_VOXELS:
				out.append(d)
	return out.slice(0, GALLERY_MAX)

func _save_design() -> void:
	var d := _design_now()
	if not ForgeLib.compute_stats(d).hasGrip:
		cost_label.text = "Give it a grip before you save it (Auto-grip finds one)"
		return
	var g := gallery().filter(func(o): return str(o.get("name", "")) != str(d.get("name", "")))
	d.erase("imbue")
	g.push_front(d)
	Save.set_value("forge_gallery", g.slice(0, GALLERY_MAX))
	cost_label.text = "Saved to My designs: \"%s\"" % str(d.get("name", "?"))
	if mode == "gallery":
		_show_mode("gallery")

func _gallery_ui() -> void:
	mode_box.add_child(UIStyle.label("MY DESIGNS", 13, UIStyle.BRONZE))
	var g := gallery()
	if g.is_empty():
		mode_box.add_child(UIStyle.label("Nothing saved yet", 14, UIStyle.MUTED))
		return
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	mode_box.add_child(grid)
	for i in g.size():
		var d: Dictionary = g[i]
		var idx := i
		var card := VBoxContainer.new()
		card.custom_minimum_size = Vector2(205, 0)
		var tex := TextureRect.new()
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex.custom_minimum_size = Vector2(0, 84)
		card.add_child(tex)
		var nm := UIStyle.label(str(d.get("name", "?")), 14, UIStyle.TEXT)
		nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		card.add_child(nm)
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		var fits := family == "" or Arms.family(d) == family
		var ld := UIStyle.button("Load", func(): _load_design(d))
		ld.disabled = not fits
		ld.tooltip_text = "" if fits else "Not %s: Vulcanus reshapes yours within its kind" % FAMILY_NAMES.get(family, "the same kind")
		row.add_child(ld)
		row.add_child(UIStyle.button("Delete", func():
			var all := gallery()
			all.remove_at(idx)
			Save.set_value("forge_gallery", all)
			_show_mode("gallery")))
		card.add_child(row)
		grid.add_child(card)
		Thumbs.weapon(tex, d, "gallery:%d" % d.hash())

func _load_design(d: Dictionary) -> void:
	_push_undo()
	for k in ["kind", "twoHanded", "throwable", "spins", "shoots", "sharpness", "serrated", "gem", "name", "stats", "chain", "balance", "grips"]:
		design.erase(k)
	var nd: Dictionary = d.duplicate(true)
	nd.erase("imbue")
	design.merge(nd, true)
	_load_cells(nd)
	name_edit.text = str(nd.get("name", ""))
	framed = false
	_rebuild()
	_show_mode("voxels")

## What a material does in a weapon, for the smith's customer: what it is good for, what it
## does that no other does, and how hard (edge, chipping) and heavy (blow, swing) it is.
const JOB_USE := {
	"edge": "Edge: cuts. Put it along the side of a blade or an axe head.",
	"point": "Point: stabs and pierces armour. Put it at the tip.",
	"blunt": "Blunt: the body of the weapon. It crushes and bruises, and holds the rest together.",
	"grip": "Grip: where the hands hold it. Every weapon needs a few in a row at the bottom.",
}
const MAT_USE := {
	"steel": "The blade metal: the keenest edge and point, holds them longest, rarely chips. Costs twice iron.",
	"iron": "The cheap strong metal: a fair edge that dulls sooner than steel's, a little heavier; good for guards and heads.",
	"bronze": "Softer and heavier: a fair edge that dulls sooner; good weight for a head.",
	"gold": "Heavy, soft and dazzling: the crowd roars at every blow it lands, the more gold the louder. A poor edge.",
	"stone": "Heavy and brittle: a crushing hammer or mace head; an edge of it chips away.",
	"bone": "Light and fairly hard: quick little blades and points, but they chip and snap.",
	"wood": "Light and cheap: fast handles and long shafts that keep the weight out of the hand; no edge.",
	"leather": "Next to weightless and soft: wraps a grip; hurts no one by itself.",
	"lead": "The densest: a few blocks in a head give it a crushing weight and pull the balance out to it; in a pommel they balance a long blade.",
	"rubber": "Light, soft and squeaky: bounces off and barely hurts. For laughs.",
	"fish": "Soft and slappy: knocks a man about with a loud slap, cuts nothing.",
	"ice": "Hard and sharp, and chills whoever it cuts (he slows down); but it shatters fast.",
	"explosive": "Goes off when it strikes hard: a blast that hurts everyone close, you as well.",
	"spring": "Bouncy: a blow springs back hard and knocks the man away. Boing.",
	"glue": "Sticks to what it hits: the weapon stays in him, or he stays on it.",
	"feather": "Weighs nothing, hurts no one: it tickles, and a laughing man drops his guard.",
	"magnet": "Pulls iron and steel to it: blades and armour are dragged in.",
	"ruby": "A gem socket of fire: a blow may set the part it strikes alight. More rubies, surer and fiercer flames. Costly.",
	"sapphire": "A gem socket of frost: a blow may freeze the limb it strikes stiff and slow the whole body. More sapphires, a deeper frost. Costly.",
	"emerald": "A gem socket of venom: a blow may poison the wound, which festers and eats into the flesh. More emeralds, a stronger venom. Costly.",
}
## The chosen material in a line: its name, how hard and how heavy (the dots), and its price.
static func material_stats(m: String) -> String:
	var d: Dictionary = Data.material(m)
	var h := clampi(int(round(float(d.get("hardness", 0.5)) * 5.0)), 0, 5)
	var w := clampi(int(round(log(maxf(0.0008, float(d.get("mass", 0.02))) / 0.0008) / log(0.22 / 0.0008) * 5.0)), 0, 5)
	return "%s   Hardness %s   Weight %s" % [str(d.get("name", m)).get_slice(" (", 0), "●".repeat(h) + "○".repeat(5 - h), "●".repeat(w) + "○".repeat(5 - w)]

static func material_text(m: String) -> String:
	var d: Dictionary = Data.material(m)
	var h := clampi(int(round(float(d.get("hardness", 0.5)) * 5.0)), 0, 5)
	var w := clampi(int(round(log(maxf(0.0008, float(d.get("mass", 0.02))) / 0.0008) / log(0.22 / 0.0008) * 5.0)), 0, 5)
	return "%s: %s  Hardness %s  Weight %s" % [str(d.get("name", m)).get_slice(" (", 0), MAT_USE.get(m, ""), "●".repeat(h) + "○".repeat(5 - h), "●".repeat(w) + "○".repeat(5 - w)]

func _draw_bars() -> void:
	var y := 2.0
	var font := UIStyle.serif(1)
	for k in ["speed", "damage", "reach"]:
		bars.draw_string(font, Vector2(0, y + 14), k.capitalize(), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UIStyle.MUTED)
		bars.draw_rect(Rect2(80, y + 3, 300, 12), Color(0, 0, 0, 0.5))
		bars.draw_rect(Rect2(80, y + 3, 300.0 * float(bar_vals[k]), 12), Color(0.85, 0.32, 0.2) if k == "damage" else UIStyle.GOLD)
		y += 20.0

func _update_texts() -> void:
	if bars == null:
		return
	var d := _design_now()
	var st := ForgeLib.compute_stats(d)
	bar_vals = ForgeLib.three_bars(st)
	bars.queue_redraw()
	says.text = "The smith: \"%s\"" % ForgeLib.blacksmith_says(d, st)
	verdict.text = "The dummy: %s  ·  %.1f kg, %d voxels" % [ForgeLib.dummy_verdict(d, st), st.mass, cells.size()]
	for c in mode_box.get_children():
		if c.has_meta("checklist"):
			c.text = "\n".join(ForgeLib.checklist(d, st).map(func(i): return ("✔ " if i.done else "○ ") + i.text))
	var delta := _value_now() - original_value
	cost_label.text = ("Cost: %d denarii" % delta) if delta >= 0 else ("Refund: %d denarii" % -delta)
	cost_label.text += "  (purse %d)" % purse
	if workshop or scratch:
		cost_label.text = "Made at the smith: %d denarii" % Arms.design_price(_design_now()) + ("  (purse %d)" % purse if scratch else "")
	elif free_build:
		cost_label.text = "Free in training"

func _value_now() -> int:
	var s := 0
	for c in cells.values():
		s += Arms.voxel_price(c[0])
	return s

# ---------- The weapon on the anvil ----------

func _rebuild() -> void:
	for c in weapon_root.get_children():
		c.queue_free()
	var vs := Data.weapon_voxel
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE * vs * 0.96
	var mat_ := StandardMaterial3D.new()
	mat_.vertex_color_use_as_albedo = true
	mat_.vertex_color_is_srgb = true
	bm.material = mat_
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = bm
	mm.instance_count = cells.size()
	var i := 0
	var centre := Vector3.ZERO
	for k in cells:
		mm.set_instance_transform(i, Transform3D(Basis(), Vector3(k) * vs))
		mm.set_instance_color(i, Weapon.voxel_color(cells[k][0], cells[k][1]))
		centre += Vector3(k) * vs
		i += 1
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	weapon_root.add_child(mi)
	# Pickable boxes for the mouse: one static body per voxel.
	var sb := StaticBody3D.new()
	weapon_root.add_child(sb)
	for k in cells:
		var cs := CollisionShape3D.new()
		var b := BoxShape3D.new()
		b.size = Vector3.ONE * vs
		cs.shape = b
		cs.position = Vector3(k) * vs
		cs.set_meta("cell", k)
		sb.add_child(cs)
	if cells.size():
		centre /= cells.size()
	weapon_root.set_meta("centre", centre)
	var low := INF
	for k in cells:
		low = minf(low, float(k.y) * vs)
	anvil.position = Vector3(centre.x, (low if low < INF else 0.0) - vs * 0.5 - 0.11, centre.z)
	floor_.position = anvil.position - Vector3(0, 0.11, 0)
	if not framed and cells.size():
		framed = true
		var ext := 0.0
		for k in cells:
			ext = maxf(ext, (Vector3(k) * vs - centre).length())
		dist = clampf(ext * 2.3 + 0.15, 0.4, 3.5)   # the whole of it in view, clear of the toolbar
	_place_camera()
	_update_texts()

func _place_camera() -> void:
	# Aimed a little above the weapon's middle: it sits low in the view, clear of the toolbar.
	var c: Vector3 = weapon_root.get_meta("centre", Vector3.ZERO) + Vector3(0, 0.08 * dist, 0)
	cam.global_position = c + Vector3(cos(orbit.y) * sin(orbit.x), sin(orbit.y), cos(orbit.y) * cos(orbit.x)) * dist
	cam.look_at(c)

func _process(dt: float) -> void:
	if viewport == null:
		return
	idle_t += dt
	if idle_t > 4.0 and not dragging and swing_t < 0.0:
		orbit.x += dt * 0.25   # left alone, it turns slowly on the anvil
		_place_camera()
	# Swing it: the weapon swept round its grip at the speed it would really swing.
	if swing_t >= 0.0:
		var d := _design_now()
		var st := ForgeLib.compute_stats(d)
		var dur := clampf(6.0 / maxf(1.0, float(st.swingSpeed)), 0.25, 1.6)
		swing_t += dt
		var k := minf(1.0, swing_t / dur)
		var g = ForgeLib.grip_points(d)
		var pivot: Vector3 = (g.main if g != null else Vector3.ZERO) * Data.weapon_voxel
		var ang := -1.6 + 2.8 * (k * k * (3.0 - 2.0 * k))
		var b := Basis(Vector3(1, 0, 0), ang)
		weapon_root.transform = Transform3D(b, pivot - b * pivot)
		if k >= 1.0:
			swing_t = -1.0
			weapon_root.transform = Transform3D.IDENTITY

func _on_view_input(e: InputEvent) -> void:
	idle_t = 0.0
	if e is InputEventMouseButton and e.pressed:
		if e.button_index == MOUSE_BUTTON_WHEEL_UP:
			dist = maxf(0.3, dist * 0.9)
			_place_camera()
		elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			dist = minf(5.0, dist * 1.1)
			_place_camera()
		elif e.button_index == MOUSE_BUTTON_LEFT and mode == "voxels":
			stroke = {"erase": false, "done": {}, "undo": false}
			_click(e.position)
		elif e.button_index == MOUSE_BUTTON_RIGHT and mode == "voxels":
			stroke = {"erase": true, "done": {}, "undo": false}
			_erase_at(e.position)
	if e is InputEventMouseButton and not e.pressed and (e.button_index == MOUSE_BUTTON_LEFT or e.button_index == MOUSE_BUTTON_RIGHT):
		stroke = {}
	if e is InputEventMouseButton and (e.button_index == MOUSE_BUTTON_MIDDLE or (e.button_index == MOUSE_BUTTON_LEFT and mode == "cards")):
		dragging = e.pressed
	if e is InputEventMouseMotion:
		if dragging:
			orbit.x -= e.relative.x * 0.01
			orbit.y = clampf(orbit.y + e.relative.y * 0.01, -1.4, 1.4)
			_place_camera()
		elif mode == "voxels":
			_hover(e.position)
			# Held down and dragged, the tool goes on working: a stroke of voxels built, painted
			# or cleared under the mouse (one undo for the whole stroke).
			if not stroke.is_empty() and tool != "line" and tool != "box":
				if stroke.erase:
					_erase_at(e.position)
				else:
					_click(e.position)

## Where the mouse points: the voxel under it and the empty cell on the face it points at (or,
## off the weapon, the cell on the weapon's own flat plane).
func _aim(at: Vector2) -> Dictionary:
	var from := cam.project_ray_origin(at)
	var dir := cam.project_ray_normal(at)
	var hit := viewport.find_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + dir * 20.0))
	var vs := Data.weapon_voxel
	if not hit.is_empty():
		var cs = hit.collider.shape_owner_get_owner(hit.collider.shape_find_owner(hit.shape))
		if cs != null and cs.has_meta("cell"):
			var cell: Vector3i = cs.get_meta("cell")
			var n: Vector3 = hit.normal
			return {"hit": cell, "place": cell + Vector3i(roundi(n.x), roundi(n.y), roundi(n.z))}
	if absf(dir.z) > 1e-4:
		var t := -from.z / dir.z
		if t > 0.0:
			var p := from + dir * t
			return {"hit": null, "place": Vector3i(roundi(p.x / vs), roundi(p.y / vs), 0)}
	return {}

func _hover(at: Vector2) -> void:
	var a := _aim(at)
	var c = null
	if not a.is_empty():
		c = a.get("hit") if tool == "paint" or tool == "erase" else a.get("place")
	ghost.visible = c != null
	if c != null:
		ghost.position = Vector3(c) * Data.weapon_voxel
		var col := Color(1, 0.3, 0.3, 0.45) if tool == "erase" else Weapon.voxel_color(mat, job)
		col.a = 0.5
		(ghost.mesh.material as StandardMaterial3D).albedo_color = col

func _mirrored(list: Array) -> Array:
	var out := list.duplicate()
	for c in list:
		var more := []
		if mirror and c.x != 0:
			more.append(Vector3i(-c.x, c.y, c.z))
		if mirror_z and c.z != 0:
			more.append(Vector3i(c.x, c.y, -c.z))
		if mirror and mirror_z and c.x != 0 and c.z != 0:
			more.append(Vector3i(-c.x, c.y, -c.z))
		for m in more:
			if not out.has(m):
				out.append(m)
	return out

## A block off now? A click always; a held button only every ERASE_EVERY, so a drag cannot
## sweep the weapon away before the hand can stop.
func _erase_ready() -> bool:
	if stroke.is_empty():
		return true
	var now := Time.get_ticks_msec() * 0.001
	if now - float(stroke.get("erase_t", -9.0)) < ERASE_EVERY:
		return false
	stroke["erase_t"] = now
	return true

## Already done in this stroke: a cell built, painted or cleared once is left alone while the
## mouse stays down (built on, a drag would stack voxels up toward the eye).
func _stroked(c) -> bool:
	return not stroke.is_empty() and c != null and stroke.done.has(c)

func _mark(list: Array) -> void:
	if not stroke.is_empty():
		for c in list:
			stroke.done[c] = true

func _click(at: Vector2) -> void:
	_apply(_aim(at))

## The tool used on what the mouse points at (`a` as _aim gives it).
func _apply(a: Dictionary) -> void:
	if a.is_empty():
		return
	match tool:
		"build":
			if _stroked(a.place) or _stroked(a.get("hit")):
				return
			var list := _mirrored([a.place])
			_place(list)
			_mark(list)
		"paint":
			if a.hit != null and not _stroked(a.hit):
				var list := _mirrored([a.hit]).filter(func(c): return cells.has(c) and cells[c] != [mat, job])
				_mark(_mirrored([a.hit]))
				if list.is_empty():
					return
				_push_undo()
				for c in list:
					cells[c] = [mat, job]
				_rebuild()
		"erase":
			if a.hit != null and not _stroked(a.hit) and _erase_ready():
				var list := _mirrored([a.hit])
				_remove(list)
				_mark(list)
		"line", "box":
			var c: Vector3i = a.place
			if line_from == null:
				line_from = c
				cost_label.text = "Now click the other end"
			else:
				var list := ForgeLib.line_cells(line_from, c) if tool == "line" else ForgeLib.box_cells(line_from, c)
				line_from = null
				_place(_mirrored(list))

func _erase_at(at: Vector2) -> void:
	var a := _aim(at)
	if not a.is_empty() and a.hit != null and not _stroked(a.hit) and _erase_ready():
		var list := _mirrored([a.hit])
		_remove(list)
		_mark(list)

func _place(list: Array) -> void:
	var want := list.filter(func(c): return not cells.has(c) and ForgeLib.in_grid(c.x, c.y, c.z))
	if want.is_empty():
		return
	# Only what holds on to the weapon goes on: no block hangs in the air.
	var add := ForgeLib.attached(cells, want)
	if add.is_empty():
		cost_label.text = "A new block must touch the weapon"
		return
	if cells.size() + add.size() > ForgeLib.MAX_VOXELS:
		cost_label.text = "That is the most the anvil holds (%d voxels)" % ForgeLib.MAX_VOXELS
		return
	if not free_build and _value_now() + Arms.voxel_price(mat) * add.size() - original_value > purse:
		cost_label.text = "Not enough denarii for that"
		return
	_push_undo()
	for c in add:
		cells[c] = [mat, job]
	_rebuild()

func _remove(list: Array) -> void:
	var gone := list.filter(func(c): return cells.has(c))
	if gone.is_empty() or cells.size() - gone.size() < 1:
		return
	_push_undo()
	for c in gone:
		cells.erase(c)
	# Cut through, the piece without the grip falls off the anvil (Undo puts it back).
	var keep := ForgeLib.kept_piece(cells)
	if keep.size() < cells.size():
		var kept := {}
		for c in keep:
			kept[c] = cells[c]
		cost_label.text = "Cut through: %d blocks fall away" % (cells.size() - keep.size())
		cells = kept
	_rebuild()

func _push_undo() -> void:
	if not stroke.is_empty():
		if stroke.undo:
			return
		stroke.undo = true
	undo_stack.append([cells.duplicate(true), design.duplicate(true)])
	if undo_stack.size() > 80:
		undo_stack.pop_front()
	redo_stack.clear()

func _undo() -> void:
	if undo_stack.is_empty():
		return
	redo_stack.append([cells.duplicate(true), design.duplicate(true)])
	var s: Array = undo_stack.pop_back()
	cells = s[0]
	design = s[1]
	_rebuild()

func _redo() -> void:
	if redo_stack.is_empty():
		return
	undo_stack.append([cells.duplicate(true), design.duplicate(true)])
	var s: Array = redo_stack.pop_back()
	cells = s[0]
	design = s[1]
	_rebuild()

func _unhandled_key_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and e.ctrl_pressed and e.keycode == KEY_Y:
		_redo()
	elif e is InputEventKey and e.pressed and e.ctrl_pressed and e.keycode == KEY_Z:
		if e.shift_pressed:
			_redo()
		else:
			_undo()

func _take() -> void:
	var d := _design_now()
	var st := ForgeLib.compute_stats(d)
	if not st.hasGrip:
		cost_label.text = "It needs a grip to be held (Auto-grip finds one)"
		return
	if family != "" and Arms.family(d) != family:
		cost_label.text = "Vulcanus reshapes it, he does not make it something else: it must stay %s" % FAMILY_NAMES.get(family, "what it is")
		return
	d.stats = st
	var cost := 0 if free_build else _value_now() - original_value
	done.call(d, cost)
