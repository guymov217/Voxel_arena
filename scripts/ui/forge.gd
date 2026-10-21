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

var mat := "steel"
var job := "edge"
var tool := "build"
var hand_pick := ""         # Move hand: "main"/"off" picked with its button (a click puts it there)
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
var line_ghost: MultiMeshInstance3D   # the Line tool's path, shown while the end is picked
var dummy_pick := "gladiator"       # what "Try it in the arena" puts in front of the weapon
var dummy_fights := false
var line_from = null       # the first cell of a line or a box being drawn

var viewport: SubViewport
var cam: Camera3D
var weapon_root: Node3D
var anvil: MeshInstance3D
var floor_: MeshInstance3D
var ghost: MeshInstance3D
var framed := false
var fit_dist := 1.0   # how far back the camera must be for the whole weapon
var fit_ext := 0.0    # how far the weapon reaches from its middle (m)
const AIM_RISE := 0.08   # the camera aims this far above what it looks at, per metre back
var cells := {}                 # Vector3i -> [mat, job]
var orbit := Vector2(0.6, 0.35)
var dist := 1.6
var dragging := false
var focus := Vector3.ZERO     # what the camera looks at: set when a weapon is framed, then the player's
var moved := false            # the player has placed the camera: no more turning by itself
var idle_t := 0.0
var fog_env: Environment       # the smithy's: its haze is laid from the weapon back (_place_camera)
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
var hover_at = null      # where the mouse is over the anvil (R turns the sharp block there)

## The smith's stock, each for its own job: two metals for edges, three weights from light to
## dense for hafts and heads, gold for the crowd, four tricks and three gem sockets.
const MATS := ["steel", "iron", "wood", "stone", "lead", "gold", "explosive", "spring", "glue", "magnet", "ruby", "sapphire", "emerald"]
const JOBS := ["edge", "point", "blunt", "grip"]
const TOOLS := [["build", "Build", "Click a face: a voxel goes on it (hold and drag for more)"], ["erase", "Erase", "Click voxels: take them off (right click erases too)"], ["line", "Line", "Click where it starts, then where it ends, any way you like: the path shows as you aim"], ["hand", "✋ Move hand", "Drag the gold ring (and the bronze one of a two-handed weapon) onto any block: the fighter holds it there"]]
## What each tool asks for, shown under the anvil while it is in hand.
const TOOL_HINT := {
	"build": "Build: click a face of the weapon, or hold and drag (an Edge or Point faces away from it; R turns one)",
	"erase": "Erase: click blocks, or hold the right button anywhere",
	"line": "Line: click where it starts",
	"hand": "Move hand: click a block (or drag the gold ring): the main hand goes there; the bronze ring is the other hand",
}

func open(d: Dictionary, coins: int, cb: Callable) -> void:
	add_to_group("bench")   # (the HUD keeps off it)
	design = d.duplicate(true)
	purse = coins
	done = cb
	rng.randomize()
	original_value = Arms.value(design)
	# Any weapon may be made into any other (a stick into a sword): the smith charges what the
	# new one is worth over the old. A blunt one starts with the blunt job in hand.
	if Arms.family(design) == "blunt":
		job = "blunt"
	_load_cells(design)
	_build_ui()
	_show_mode(mode)
	_rebuild()

func _load_cells(d: Dictionary) -> void:
	cells.clear()
	for v in d.voxels:
		cells[Vector3i(v[0], v[1], v[2])] = [v[3], v[4], ForgeLib.face_of(v)]

func _design_now() -> Dictionary:
	var out := design.duplicate(true)
	var vox := []
	for k in cells:
		var f := _face(k)
		vox.append([k.x, k.y, k.z, cells[k][0], cells[k][1], f] if f >= 0 else [k.x, k.y, k.z, cells[k][0], cells[k][1]])
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
	# Armour is made at the same forge: plate by plate on the body part, its own bench.
	if get_parent() and get_parent().has_method("armour_from_forge"):
		var ab := UIStyle.button("Armour", func(): get_parent().armour_from_forge(self))
		ab.tooltip_text = "Make a piece of armour, plate by plate: where it goes, what it is made of"
		ab.set_meta("mode", "armour")
		ab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mode_row.add_child(ab)
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
	var fresh := _from_nothing_button()
	if fresh:
		col.add_child(fresh)
	var end := HBoxContainer.new()
	end.add_theme_constant_override("separation", 6)
	if not workshop:
		end.add_child(UIStyle.button("Take it" if free_build else "Pay and take it", _take, true))
	end.add_child(UIStyle.button("Swing it", func(): swing_t = 0.0))
	col.add_child(_try_row())
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
	# The price of the job, always in sight at the foot of the view, out of the way of the work.
	var pb := PanelContainer.new()
	var pbs := StyleBoxFlat.new()
	pbs.bg_color = Color(0.07, 0.05, 0.035, 0.82)
	pbs.border_color = UIStyle.BRONZE_DARK
	pbs.set_border_width_all(1)
	pbs.set_corner_radius_all(8)
	pbs.content_margin_left = 14; pbs.content_margin_right = 14; pbs.content_margin_top = 6; pbs.content_margin_bottom = 6
	pb.add_theme_stylebox_override("panel", pbs)
	pb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pb.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	pb.grow_horizontal = Control.GROW_DIRECTION_BOTH
	pb.grow_vertical = Control.GROW_DIRECTION_BEGIN
	pb.position.y -= 14
	price_badge = UIStyle.label("", 19, UIStyle.GOLD)
	price_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	price_badge.autowrap_mode = TextServer.AUTOWRAP_OFF
	pb.add_child(price_badge)
	pb.name = "PriceBadge"
	right.add_child(pb)
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
	e.ambient_light_energy = 0.7
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	e.tonemap_exposure = 0.9
	e.glow_enabled = true
	e.glow_intensity = 0.7
	e.glow_bloom = 0.08
	e.ssao_enabled = true
	# The haze thickens from the weapon back, not from the camera: drawn in close or backed far
	# off, the smithy behind the anvil is seen the same.
	e.fog_enabled = true
	e.fog_mode = Environment.FOG_MODE_DEPTH
	e.fog_light_color = Color(0.2, 0.14, 0.1)
	e.fog_density = 0.8
	e.fog_depth_curve = 1.4
	e.fog_sky_affect = 0.9
	env.environment = e
	fog_env = e
	viewport.add_child(env)
	var light := DirectionalLight3D.new()
	light.rotation = Vector3(-0.75, 0.7, 0)
	light.light_color = Color(1.0, 0.95, 0.88)
	light.light_energy = 1.2
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
	line_ghost = MultiMeshInstance3D.new()
	var lmm := MultiMesh.new()
	lmm.transform_format = MultiMesh.TRANSFORM_3D
	lmm.mesh = gb
	line_ghost.multimesh = lmm
	viewport.add_child(line_ghost)

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
	# Behind the anvil as the camera first looks at it, so the smithy is the weapon's backdrop.
	VoxelArt.place(floor_, "smithy", Vector3(-3.1, 0, -2.7), deg_to_rad(50))
	VoxelArt.place(floor_, "weapon_rack", Vector3(3.3, 0, -2.7), deg_to_rad(-50))
	VoxelArt.place(floor_, "amphora", Vector3(2.0, 0, -3.6), PI - 0.4)
	VoxelArt.place(floor_, "amphora_wide", Vector3(2.5, 0, -3.4), PI - 1.2)
	VoxelArt.place(floor_, "crate", Vector3(-1.6, 0, -3.7), PI - 0.3)
	VoxelArt.place(floor_, "crate", Vector3(-0.9, 0, -4.0), PI - 1.0)
	VoxelArt.place(floor_, "crate", Vector3(-1.6, 0.6, -3.7), PI - 0.9)

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
	_show_line([])
	if tool_bar:
		_toolbar_ui()
	_update_texts()

## Try it in the arena: the weapon in hand, in front of a dummy of the player's choosing (a
## man or a beast; standing still, or fighting back), and back to the anvil afterwards with
## everything as it was.
func _try_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var who := OptionButton.new()
	var keys: Array = ["gladiator"]
	var names: Array = ["A gladiator"]
	for k in Data.campaign.get("enemies", {}):
		if Edition.foe_open("foe:" + k):
			keys.append("foe:" + k)
			names.append(String(Data.campaign.enemies[k].get("label", k)))
	for k in Data.beasts:
		if Edition.foe_open(k) and k != "goat":
			keys.append(k)
			names.append(String(Data.beasts[k].get("name", k)))
	for n in names:
		who.add_item(n)
	who.select(maxi(0, keys.find(dummy_pick)))
	who.item_selected.connect(func(i): dummy_pick = keys[i])
	who.tooltip_text = "What stands in front of the weapon"
	row.add_child(who)
	var fb := CheckBox.new()
	fb.text = "Fights back"
	fb.button_pressed = dummy_fights
	fb.toggled.connect(func(x): dummy_fights = x)
	row.add_child(fb)
	row.add_child(UIStyle.button("Try it in the arena", func():
		var d := _design_now()
		if not ForgeLib.compute_stats(d).hasGrip:
			cost_label.text = "It needs somewhere to be held: build a Grip block, or ✋ Move hand"
			return
		if ForgeLib.too_heavy(d) != "":
			cost_label.text = ForgeLib.too_heavy(d)
			return
		if get_parent() and get_parent().has_method("try_from_forge"):
			get_parent().try_from_forge(self, d, dummy_pick, dummy_fights)))
	return row

func _cards_ui() -> void:
	mode_box.add_child(UIStyle.label("1 · PICK A BASE", 13, UIStyle.BRONZE))
	var grid := GridContainer.new()
	grid.columns = 3
	mode_box.add_child(grid)
	for k in ForgeLib.BASES:
		var key: String = k
		var b := UIStyle.button(ForgeLib.BASES[k].label, func(): _pick_base(key))
		b.tooltip_text = ForgeLib.BASES[k].blurb
		b.toggle_mode = true
		b.button_pressed = key == base_key
		b.custom_minimum_size = Vector2(135, 0)
		grid.add_child(b)
	if base_key == "":
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

## What a block does, in the words a player thinks in: it cuts, it stabs, it crushes, it is
## held. (The job names stay the game's own: edge, point, blunt, grip.)
const JOB_PICK := [["edge", "Cut", "sharp edge"], ["point", "Stab", "point"], ["blunt", "Crush", "head, body"], ["grip", "Hold", "grip"]]
## The materials in four rows, the way a smith sorts them.
const MAT_GROUPS := [["Metals", ["steel", "iron", "gold", "lead"]], ["Wood and stone", ["wood", "stone"]], ["Tricks", ["explosive", "spring", "glue", "magnet"]], ["Gems", ["ruby", "sapphire", "emerald"]]]
const KEEN := 0.5   # a material softer than this holds no edge worth the name

static func _swatch(c: Color, px := 18) -> ImageTexture:
	var img := Image.create(px, px, false, Image.FORMAT_RGBA8)
	img.fill(c)
	for i in px:
		for e in [0, px - 1]:
			img.set_pixel(i, e, c.darkened(0.45))
			img.set_pixel(e, i, c.darkened(0.45))
	for i in range(2, px - 2):
		img.set_pixel(i, 2, c.lightened(0.35))
	return ImageTexture.create_from_image(img)

## A picture of each job, drawn: a blade's edge, a point, a block, a bound grip.
static func _job_icon(j: String, px := 26) -> ImageTexture:
	var img := Image.create(px, px, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var g := UIStyle.GOLD_LIGHT
	var d := UIStyle.GOLD.darkened(0.3)
	for y in px:
		for x in px:
			var u := float(x) / (px - 1)
			var v := float(y) / (px - 1)
			var on := false
			var dark := false
			match j:
				"edge":
					# A blade seen flat, its keen side a bright line.
					on = u > 0.15 and u < 0.85 and v > 0.38 + (u - 0.15) * 0.1 and v < 0.62
					dark = on and v > 0.47
				"point":
					on = absf(v - 0.5) < (u - 0.1) * 0.45 and u > 0.1 and u < 0.92
					dark = on and v > 0.5
				"blunt":
					on = u > 0.2 and u < 0.8 and v > 0.2 and v < 0.8
					dark = on and (u > 0.62 or v > 0.62)
				"grip":
					on = u > 0.38 and u < 0.62 and v > 0.08 and v < 0.92
					dark = on and int(v * 8.0) % 2 == 0
			if on:
				img.set_pixel(x, y, d if dark else g)
	return ImageTexture.create_from_image(img)

## Building from nothing, under Quick start and Shape by hand alike: a blank anvil where the
## weapon is new anyway (training, the workshop, a new one at the smith); reshaping your own
## weapon at the smith, a new weapon of its own (yours is left as it was, the new one paid for
## as made). Null where neither can be.
func _from_nothing_button() -> Button:
	if free_build or scratch:
		return UIStyle.button("Blank anvil · build from nothing", _blank)
	if get_parent() and get_parent().has_method("scratch_from_forge"):
		return UIStyle.button("Forge a new weapon from nothing", func(): get_parent().scratch_from_forge(self))
	return null

## The slider's reading: how sharp, and what each Cut or Stab block costs at that.
## The Cut and Stab blocks on the anvil (the only ones honed).
func _sharp_blocks() -> int:
	var n := 0
	for c in cells.values():
		if String(c[1]) == "edge" or String(c[1]) == "point":
			n += 1
	return n

## The sharpness set and what the honing of the blade comes to at it.
func _sharp_note(k: float) -> String:
	var n := _sharp_blocks()
	if free_build:
		return "%d%%" % roundi(k * 100.0)
	return "%d%% · honing %d (%d Cut/Stab block%s)" % [roundi(k * 100.0), Arms.honing(_jobs_now(), k), n, "" if n == 1 else "s"]

func _jobs_now() -> Array:
	return cells.values().map(func(c): return String(c[1]))

func _voxels_ui() -> void:
	# 1. What the next blocks do: a big choice of four.
	mode_box.add_child(UIStyle.label("1 · WHAT THE BLOCK DOES", 13, UIStyle.BRONZE))
	var jr := GridContainer.new()
	jr.columns = 4
	jr.add_theme_constant_override("h_separation", 6)
	for jp in JOB_PICK:
		var key: String = jp[0]
		var b := UIStyle.button(jp[1], func():
			job = key
			# A cutting or stabbing block of a soft stuff would be no edge at all: the smith
			# reaches for steel.
			if (key == "edge" or key == "point") and float(Data.material(mat).get("hardness", 0.5)) < KEEN:
				mat = "steel"
			if tool == "erase":
				tool = "build"
			_show_mode("voxels"))
		b.icon = _job_icon(key)
		b.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.expand_icon = false
		b.tooltip_text = JOB_USE[key]
		b.toggle_mode = true
		b.button_pressed = job == key
		b.custom_minimum_size = Vector2(98, 46)
		jr.add_child(b)
	mode_box.add_child(jr)
	# 2. What they are made of: swatches by kind, the price on each.
	mode_box.add_child(UIStyle.label("2 · MATERIAL" + ("" if free_build else " · DENARII A BLOCK"), 13, UIStyle.BRONZE))
	var mg := GridContainer.new()
	mg.columns = 2
	mg.add_theme_constant_override("h_separation", 8)
	mg.add_theme_constant_override("v_separation", 4)
	for grp in MAT_GROUPS:
		var gl := UIStyle.label(String(grp[0]), 14, UIStyle.MUTED)
		gl.autowrap_mode = TextServer.AUTOWRAP_OFF
		gl.custom_minimum_size = Vector2(92, 0)
		mg.add_child(gl)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		for m in grp[1]:
			if not MATS.has(m):
				continue
			var key: String = m
			var b := Button.new()
			b.text = m.capitalize() + ("" if free_build else " %d" % Arms.voxel_price(m))
			b.icon = _swatch(Weapon.voxel_color(m, "blunt"))
			b.tooltip_text = material_text(m)
			b.toggle_mode = true
			b.button_pressed = mat == key
			b.add_theme_font_override("font", UIStyle.body("medium"))
			b.add_theme_font_size_override("font_size", 15)
			b.add_theme_constant_override("h_separation", 6)
			# A soft stuff cannot be an edge: dimmed while Cut or Stab is chosen.
			if (job == "edge" or job == "point") and float(Data.material(m).get("hardness", 0.5)) < KEEN:
				b.modulate = Color(1, 1, 1, 0.45)
				b.tooltip_text += "  (soft: a poor edge)"
			b.pressed.connect(func():
				mat = key
				_show_mode("voxels"))
			row.add_child(b)
		mg.add_child(row)
	mode_box.add_child(mg)
	var md := UIStyle.label(material_stats(mat), 14, UIStyle.TEXT)
	md.tooltip_text = material_text(mat)
	md.mouse_filter = Control.MOUSE_FILTER_PASS
	mode_box.add_child(md)
	# How it is held, and where: one hand or two, and each hand put on its block with a click
	# (the gold ring is the main hand, the bronze one the other).
	var held := HBoxContainer.new()
	held.add_theme_constant_override("separation", 4)
	var hl := UIStyle.label("Held in", 14, UIStyle.MUTED)
	hl.autowrap_mode = TextServer.AUTOWRAP_OFF
	held.add_child(hl)
	var two_now: bool = design.get("twoHanded", false)
	for hk in [[false, "One hand"], [true, "Two hands"]]:
		var want: bool = hk[0]
		var hb := UIStyle.button(hk[1], func():
			if bool(design.get("twoHanded", false)) == want:
				return
			if want:
				var two_d := _design_now()
				two_d.twoHanded = true
				if ForgeLib.two_hand_points(two_d) == null:
					cost_label.text = "The grip is too short for two hands: two fists need a grip of 5 blocks or more"
					return
			design.twoHanded = want
			hand_pick = "main" if not want and hand_pick == "off" else hand_pick
			_rebuild()
			_update_texts()
			_show_mode("voxels"))
		hb.toggle_mode = true
		hb.button_pressed = two_now == want
		hb.tooltip_text = "Swung in both hands: slower to start, much more behind each blow" if want else "In one hand: quick, the other hand free for a shield"
		held.add_child(hb)
	held.add_child(VSeparator.new())
	var hands := [["main", "✋ Main hand", UIStyle.GOLD]]
	if two_now:
		hands.append(["off", "✋ Other hand", UIStyle.BRONZE])
	for hd in hands:
		var which: String = hd[0]
		var pb := UIStyle.button(hd[1], func():
			tool = "hand"
			hand_pick = which
			line_from = null
			_show_line([])
			_toolbar_ui()
			_show_mode("voxels")
			cost_label.text = "Click the block where the %s hand holds it (its ring: %s)" % ["main" if which == "main" else "other", "gold" if which == "main" else "bronze"])
		pb.toggle_mode = true
		pb.button_pressed = tool == "hand" and (hand_pick if hand_pick != "" else "main") == which
		pb.add_theme_color_override("font_color", hd[2])
		pb.add_theme_color_override("font_pressed_color", hd[2])
		pb.tooltip_text = "Put the %s hand on a block: click it on the weapon" % ("main" if which == "main" else "other")
		held.add_child(pb)
	mode_box.add_child(held)
	var opts := HBoxContainer.new()
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
	var sr := HBoxContainer.new()
	# Not wrapped: in a row a wrapping label is squeezed to one letter a line.
	var sl_l := UIStyle.label("Sharpness", 14, UIStyle.MUTED)
	sl_l.autowrap_mode = TextServer.AUTOWRAP_OFF
	sl_l.custom_minimum_size = Vector2(90, 0)
	sr.add_child(sl_l)
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sr.add_child(sl)
	# What the honing costs, by the block, at the sharpness set (Cut and Stab blocks only).
	var sl_v := UIStyle.label(_sharp_note(sl.value), 13, UIStyle.GOLD)
	sl_v.autowrap_mode = TextServer.AUTOWRAP_OFF
	sr.add_child(sl_v)
	var tip := "Sharpness: how easily the Cut and Stab blocks get into flesh and how deep they wound. Crush and Hold blocks have no edge: it does nothing for them and they cost no honing.\nHoning each Cut or Stab block costs, by the sharpness set:\n%s" % "\n".join([0.25, 0.5, 0.75, 1.0].map(func(k): return "  %d%%: %.1f denarii a block" % [roundi(k * 100.0), Arms.sharp_cost("edge", k)]))
	for c in [sl_l, sl, sl_v]:
		c.tooltip_text = tip
		c.mouse_filter = Control.MOUSE_FILTER_STOP
	sl.value_changed.connect(func(x):
		design.sharpness = x
		_update_texts())
	sr.set_meta("sharp_row", true)
	sl_v.set_meta("sharp_note", true)
	mode_box.add_child(sr)
	# With nothing on it to hone, the slider has nothing to do: a note says so instead.
	var no_edge := UIStyle.label("Sharpness: only for Cut and Stab blocks (none on it yet)", 13, UIStyle.MUTED)
	no_edge.set_meta("sharp_none", true)
	mode_box.add_child(no_edge)
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
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 4)
	tool_bar.add_child(rows)
	var trow := HBoxContainer.new()
	trow.add_theme_constant_override("separation", 4)
	for td in TOOLS:
		var key: String = td[0]
		var b := UIStyle.button(td[1], func():
			tool = key
			hand_pick = ""
			line_from = null
			_show_line([])
			_toolbar_ui()
			cost_label.text = TOOL_HINT.get(key, ""))
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
	var turn := UIStyle.button("Turn sharp block (R)", func():
		cost_label.text = "Point at an Edge or a Point block and press R: it turns to face each way in turn")
	turn.tooltip_text = "An Edge or Point block faces away from the face you put it on; R turns the one under the mouse"
	ar.add_child(turn)
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
	if ForgeLib.too_heavy(d) != "":
		cost_label.text = ForgeLib.too_heavy(d)
		return
	if not ForgeLib.compute_stats(d).hasGrip:
		cost_label.text = "Say where it is held before you save it: build a Grip block, or ✋ Move hand"
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
		row.add_child(UIStyle.button("Load", func(): _load_design(d)))
		if scratch:
			# At the smith: have it made as it is, for what it is worth.
			var price := Arms.design_price(d)
			var buy := UIStyle.button("Buy · %d" % price, func():
				_load_design(d)
				_take())
			buy.disabled = price > purse
			row.add_child(buy)
		row.add_child(UIStyle.button("Delete", func():
			var all := gallery()
			all.remove_at(idx)
			Save.set_value("forge_gallery", all)
			_show_mode("gallery")))
		UIStyle.push_down(card)
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
	"sapphire": "A gem socket of frost: a blow may freeze the limb it strikes stiff and give it frostbite: the flesh there whitens, blackens and dies away, bloodless. More sapphires, a deeper frost. Costly.",
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
	cost_label.text = price_text(d)
	var sharp := _sharp_blocks() > 0 or job == "edge" or job == "point"
	for c in mode_box.get_children():
		if c.has_meta("sharp_row"):
			c.visible = sharp
			for k in c.get_children():
				if k.has_meta("sharp_note"):
					k.text = _sharp_note(float(design.get("sharpness", 0.8)))
		elif c.has_meta("sharp_none"):
			c.visible = not sharp
	_price_badge()
	var heavy := ForgeLib.too_heavy(d, st)
	if heavy != "":
		cost_label.text = heavy

## What the weapon on the anvil comes to, spelled out: what it is made of and the smith's work,
## what is paid now, and what is left in the purse after (or how much is missing).
func price_text(d: Dictionary) -> String:
	if free_build and not scratch and not workshop:
		return "Free in training"
	if workshop:
		return "Kept in My designs, free. Made at the smith in the campaign it would cost %d denarii." % Arms.design_price(d)
	var pay: int
	var lines: Array = []
	if scratch:
		var mat := maxi(0, Arms.value(d) - 1)
		var work := Arms.labour(d)
		var harm := Arms.power_price(d)
		pay = Arms.design_price(d)
		lines.append("Blocks %d + the smith's work %d = %d" % [mat, work, mat + work])
		if harm > mat + work:
			lines.append("A weapon that hits this hard costs at least %d" % harm)
	else:
		var now := _value_now()
		pay = now - original_value
		lines.append("Its blocks were worth %d, now %d" % [original_value, now])
	if pay < 0:
		lines.append("He pays you back %d · purse %d → %d" % [-pay, purse, purse - pay])
	elif pay > purse:
		lines.append("You pay %d · you have %d: %d more needed" % [pay, purse, pay - purse])
	else:
		lines.append("You pay %d · purse %d → %d" % [pay, purse, purse - pay])
	return "\n".join(lines)

func _value_now() -> int:
	var s := 0
	var sh := clampf(float(design.get("sharpness", 0.8)), 0.0, 1.0)
	for c in cells.values():
		s += Arms.voxel_price(c[0])
	return s + Arms.honing(_jobs_now(), sh)

## What the job comes to now and the purse after it, in one line: always on show over the anvil.
func _price_now() -> Array:
	if scratch:
		return [Arms.design_price(_design_now()), purse]
	return [_value_now() - original_value, purse]

var price_badge: Label
func _price_badge() -> void:
	if price_badge == null or not is_instance_valid(price_badge):
		return
	var panel := price_badge.get_parent() as Control
	if free_build and not scratch and not workshop:
		panel.visible = false
		return
	panel.visible = true
	if workshop:
		price_badge.text = "At the smith: %d denarii" % Arms.design_price(_design_now())
		price_badge.add_theme_color_override("font_color", UIStyle.GOLD)
		return
	var pr := _price_now()
	var pay: int = pr[0]
	if pay < 0:
		price_badge.text = "He pays you %d  ·  purse %d → %d" % [-pay, purse, purse - pay]
		price_badge.add_theme_color_override("font_color", UIStyle.GOLD)
	elif pay > purse:
		price_badge.text = "Price %d  ·  you have %d: %d short" % [pay, purse, pay - purse]
		price_badge.add_theme_color_override("font_color", Color(1, 0.55, 0.45))
	else:
		price_badge.text = "Price %d  ·  purse %d → %d" % [pay, purse, purse - pay]
		price_badge.add_theme_color_override("font_color", UIStyle.GOLD)

# ---------- The weapon on the anvil ----------

func _rebuild() -> void:
	for c in weapon_root.get_children():
		c.queue_free()
	var vs := Data.weapon_voxel
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE * vs * 0.96
	# Drawn as in the arena (shaders/voxel_body.gdshader: steel shines as steel, wood is grained),
	# not as chalk-white blocks in the forge light.
	bm.material = VoxelPart.body_material()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = bm
	mm.instance_count = cells.size()
	var i := 0
	var centre := Vector3.ZERO
	# Sharp voxels drawn tapered, as on the weapon in the arena.
	var jobs := {}
	for k in cells:
		jobs[k] = str(cells[k][1])
	for k in cells:
		mm.set_instance_transform(i, Transform3D(Basis(), Vector3(k) * vs))
		mm.set_instance_color(i, Weapon.voxel_color(cells[k][0], cells[k][1]))
		mm.set_instance_custom_data(i, VoxelPart.kind_data(VoxelPart.kind_of_material(str(cells[k][0])), 0, VoxelPart.taper_code(jobs, k, _face(k))))
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
	# Where the hands hold it: a gold ring for the main hand, a bronze one for the other.
	var g = ForgeLib.grip_points(_design_now())
	if g != null:
		var hands := [[g.main, UIStyle.GOLD]]
		if design.get("twoHanded", false):
			hands.append([g.off, UIStyle.BRONZE])
		for hd in hands:
			var ring := MeshInstance3D.new()
			var tm := TorusMesh.new()
			tm.inner_radius = vs * 0.75
			tm.outer_radius = vs * 1.05
			var rm := StandardMaterial3D.new()
			rm.albedo_color = hd[1]
			rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			rm.no_depth_test = true
			tm.material = rm
			ring.mesh = tm
			ring.position = (hd[0] as Vector3) * vs
			weapon_root.add_child(ring)
			var tag := Label3D.new()
			tag.text = "MAIN" if hd[1] == UIStyle.GOLD else "OTHER"
			tag.modulate = hd[1]
			tag.outline_size = 8
			tag.font_size = 36
			tag.pixel_size = vs * 0.03
			tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			tag.no_depth_test = true
			tag.position = (hd[0] as Vector3) * vs + Vector3(vs * 2.2, 0, 0)
			weapon_root.add_child(tag)
	var low := INF
	for k in cells:
		low = minf(low, float(k.y) * vs)
	anvil.position = Vector3(centre.x, (low if low < INF else 0.0) - vs * 0.5 - 0.11, centre.z)
	floor_.position = anvil.position - Vector3(0, 0.11, 0)
	if cells.size():
		var ext := 0.0
		for k in cells:
			ext = maxf(ext, (Vector3(k) * vs - centre).length())
		# The whole of it in view, turned any way, clear of the toolbar: framed once, when it is
		# put on the anvil (or with F). After that the camera stays where the player put it,
		# however the weapon grows.
		# (The camera aims a little above the middle, _place_camera: that much of the view's
		# half-angle is spent before the weapon's own size.)
		fit_ext = ext + vs
		_fit()
		if not framed:
			_frame()
	_place_camera()
	_update_texts()

## The narrower of the camera's two angles of view (a tall narrow window is narrow sideways).
## How far back the camera must stand for all of it, for the view as big as it is now (the
## view is laid out after the weapon is put on: framed again, F uses its size then).
func _fit() -> void:
	var half := deg_to_rad(_view_fov() * 0.5) - atan(AIM_RISE)
	fit_dist = maxf(0.4, fit_ext / sin(half) * 1.1 + 0.1)

func _view_fov() -> float:
	var sz := Vector2(viewport.size) if viewport else Vector2(16, 9)
	var aspect := sz.x / maxf(1.0, sz.y)
	var h := rad_to_deg(2.0 * atan(tan(deg_to_rad(cam.fov * 0.5)) * aspect))
	return minf(cam.fov, h)

## The smithy round the anvil (the hearth, the racks, the jars) stands about 3 m off, and stays
## in view behind the weapon however far the camera is drawn in or backed off; only a piece the
## camera has backed into, or one standing between it and the weapon, is put away while it is.
func _decor_update() -> void:
	var cp := cam.global_position
	var seg := focus - cp
	for c in floor_.get_children():
		if not (c is Node3D):
			continue
		if not c.has_meta("decor_r"):
			var box := AABB()
			var first := true
			for vi in c.find_children("*", "VisualInstance3D", true, false):
				var b: AABB = (vi as VisualInstance3D).global_transform * (vi as VisualInstance3D).get_aabb()
				box = b if first else box.merge(b)
				first = false
			c.set_meta("decor_c", box.get_center())
			c.set_meta("decor_r", box.size.length() * 0.5)
		var cc: Vector3 = c.get_meta("decor_c")
		var r: float = c.get_meta("decor_r")
		var t := clampf((cc - cp).dot(seg) / maxf(seg.length_squared(), 1e-6), 0.0, 1.0)
		var in_way := t > 0.0 and t < 1.0 and (cp + seg * t).distance_to(cc) < r * 0.85
		c.visible = cp.distance_to(cc) > r + 0.3 and not in_way

## The whole weapon in view: the camera aimed at its middle and backed off to take it all in.
func _frame() -> void:
	framed = true
	if fit_ext > 0.0:
		_fit()
	dist = fit_dist
	focus = weapon_root.get_meta("centre", Vector3.ZERO)
	_place_camera()

func _place_camera() -> void:
	# Aimed a little above the point it looks at: the weapon sits low in the view, clear of the
	# toolbar.
	var c: Vector3 = focus + Vector3(0, AIM_RISE * dist, 0)
	cam.global_position = c + Vector3(cos(orbit.y) * sin(orbit.x), sin(orbit.y), cos(orbit.y) * cos(orbit.x)) * dist
	cam.look_at(c)
	if fog_env:
		fog_env.fog_depth_begin = dist + 1.0
		fog_env.fog_depth_end = dist + 16.0
	_decor_update()

## The camera slid sideways and up or down in its own plane (a pan), as far as the mouse moved:
## what was under the mouse stays under it.
func _pan(rel: Vector2) -> void:
	var px := 2.0 * dist * tan(deg_to_rad(cam.fov * 0.5)) / maxf(1.0, float(viewport.size.y))
	var b := cam.global_transform.basis
	focus += (-b.x * rel.x + b.y * rel.y) * px
	_place_camera()

const WALK_KEYS := {"forward": KEY_W, "back": KEY_S, "left": KEY_A, "right": KEY_D, "jump": KEY_SPACE, "crouch": KEY_CTRL, "sprint": KEY_SHIFT}
## W A S D (the walking keys, as bound in Controls) move the camera over the anvil: forward and
## back the way it looks, sideways across; Space and Ctrl (jump, crouch) up and down; Shift
## (run) faster. It goes at a pace for how far back it stands. Not while a name is typed in.
func _walk_camera(dt: float) -> void:
	if not is_visible_in_tree() or cam == null:
		return
	var fo := get_viewport().gui_get_focus_owner()
	if fo is LineEdit or fo is TextEdit:
		return
	var v := Vector3.ZERO
	var held := func(id: String) -> bool:
		if InputMap.has_action("va_" + id):
			return Input.is_action_pressed("va_" + id)
		# Not yet bound (no fight started since the game opened): the default keys.
		return Input.is_physical_key_pressed(WALK_KEYS[id])
	if held.call("forward"): v.z -= 1.0
	if held.call("back"): v.z += 1.0
	if held.call("left"): v.x -= 1.0
	if held.call("right"): v.x += 1.0
	if held.call("jump"): v.y += 1.0
	if held.call("crouch"): v.y -= 1.0
	if v == Vector3.ZERO:
		return
	moved = true
	idle_t = 0.0
	var b := cam.global_transform.basis
	var speed := maxf(0.5, dist * 0.9) * (2.5 if held.call("sprint") else 1.0)
	var step := (b.x * v.x + Vector3.UP * v.y + b.z * v.z).normalized() * speed * dt
	# What it looks at goes along sideways and up; moving in or out along the view brings the
	# camera nearer or farther (never through it: it stops a hand's breadth short).
	var ahead := -b.z
	focus += step - ahead * step.dot(ahead)
	dist = clampf(dist - step.dot(ahead), 0.15, maxf(8.0, fit_dist * 2.0))
	_place_camera()

## The wheel draws the camera in toward what is under the mouse (or out from it).
func _zoom(at: Vector2, k: float) -> void:
	var a := _aim(at)
	var cell = a.get("hit") if a.get("hit") != null else a.get("place")
	var nd := clampf(dist * k, 0.15, maxf(8.0, fit_dist * 2.0))
	if cell != null and k < 1.0:
		focus = focus.lerp(Vector3(cell) * Data.weapon_voxel, 1.0 - nd / dist)
	dist = nd
	_place_camera()

func _process(dt: float) -> void:
	if viewport == null:
		return
	idle_t += dt
	_walk_camera(dt)
	if idle_t > 4.0 and not dragging and not moved and swing_t < 0.0:
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
			moved = true
			_zoom(e.position, 0.88)
		elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			moved = true
			_zoom(e.position, 1.0 / 0.88)
		elif e.button_index == MOUSE_BUTTON_LEFT and mode == "voxels":
			stroke = {"erase": false, "done": {}, "undo": false}
			_click(e.position)
		elif e.button_index == MOUSE_BUTTON_RIGHT and mode == "voxels" and tool == "line" and line_from != null:
			line_from = null
			_show_line([])
			cost_label.text = TOOL_HINT.line
		elif e.button_index == MOUSE_BUTTON_RIGHT and mode == "voxels":
			stroke = {"erase": true, "done": {}, "undo": false}
			_erase_at(e.position)
	if e is InputEventMouseButton and not e.pressed and (e.button_index == MOUSE_BUTTON_LEFT or e.button_index == MOUSE_BUTTON_RIGHT):
		stroke = {}
	# The middle button turns the camera round the weapon; with Shift held it slides it instead.
	if e is InputEventMouseButton and (e.button_index == MOUSE_BUTTON_MIDDLE or (e.button_index == MOUSE_BUTTON_LEFT and mode == "cards")):
		dragging = e.pressed
		if e.pressed:
			moved = true
	if e is InputEventMouseMotion:
		if dragging and e.shift_pressed:
			_pan(e.relative)
		elif dragging:
			orbit.x -= e.relative.x * 0.01
			orbit.y = clampf(orbit.y + e.relative.y * 0.01, -1.4, 1.4)
			_place_camera()
		elif mode == "voxels":
			hover_at = e.position
			_hover(e.position)
			# Held down and dragged, the tool goes on working: a stroke of voxels built, painted
			# or cleared under the mouse (one undo for the whole stroke).
			if not stroke.is_empty() and tool != "line":
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
		c = a.get("hit") if tool == "erase" or tool == "hand" else a.get("place")
	# The line from where it starts to where the mouse is: every block it would put down.
	if tool == "line" and line_from != null and c != null:
		_show_line(_mirrored(ForgeLib.line_path(line_from, c)))
	ghost.visible = c != null
	if c != null:
		ghost.position = Vector3(c) * Data.weapon_voxel
		var col := Color(1, 0.3, 0.3, 0.45) if tool == "erase" else Weapon.voxel_color(mat, job)
		col.a = 0.5
		(ghost.mesh.material as StandardMaterial3D).albedo_color = col

func _show_line(list: Array) -> void:
	if line_ghost == null:
		return
	var mm := line_ghost.multimesh
	mm.instance_count = list.size()
	for i in list.size():
		mm.set_instance_transform(i, Transform3D(Basis(), Vector3(list[i]) * Data.weapon_voxel))
	(line_ghost.multimesh.mesh.material as StandardMaterial3D).albedo_color = Color(Weapon.voxel_color(mat, job), 0.4)

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
			_place(list, ForgeLib.face_index(a.place - a.hit) if a.get("hit") != null else -1, a.place)
			_mark(list)
		"erase":
			if a.hit != null and not _stroked(a.hit) and _erase_ready():
				var list := _mirrored([a.hit])
				_remove(list)
				_mark(list)
		"hand":
			# Pressed: the hand whose ring is nearest is taken up; dragged, it follows the mouse
			# from block to block.
			if a.hit == null or stroke.get("at") == a.hit:
				return
			if not stroke.has("which"):
				# The hand picked with its button, else the one whose ring is nearest.
				stroke["which"] = hand_pick if hand_pick != "" and (hand_pick == "main" or design.get("twoHanded", false)) else _nearest_hand(a.hit)
			stroke["at"] = a.hit
			_set_hand(a.hit, String(stroke.which))
		"line":
			var c: Vector3i = a.place
			if line_from == null:
				line_from = c
				_show_line(_mirrored([c]))
				cost_label.text = "Line: now click where it ends (right click: start again)"
			else:
				var list := ForgeLib.line_path(line_from, c)
				line_from = null
				_show_line([])
				_place(_mirrored(list))
				cost_label.text = TOOL_HINT.line

## Move hand: hand `which` ("main" or "off") goes onto block `c`, any block of the weapon. The
## fighter holds the weapon there.
func _set_hand(c: Vector3i, which := "main") -> void:
	if not cells.has(c):
		return
	var at := [c.x, c.y, c.z]
	var two: bool = design.get("twoHanded", false)
	var g = ForgeLib.grip_points(_design_now())
	var now := {"main": [c.x, c.y, c.z], "off": [c.x, c.y - 2, c.z]}
	if g != null:
		now = {"main": [roundi(g.main.x), roundi(g.main.y), roundi(g.main.z)], "off": [roundi(g.off.x), roundi(g.off.y), roundi(g.off.z)]}
	if not two:
		design.grips = {"main": at, "off": [c.x, c.y - 2, c.z]}
	else:
		var other: Array = now["off" if which == "main" else "main"]
		if Vector3(c).distance_to(Vector3(other[0], other[1], other[2])) < ForgeLib.HANDS_APART - 0.01:
			cost_label.text = "Too close to the other hand: two fists need 3 blocks between them"
			return
		now[which] = at
		design.grips = now
	_rebuild()
	cost_label.text = ("The %s hand holds it here" % ("main" if which == "main" else "other")) if two else "The hand holds it here"

## The hand whose ring is nearest block `c` (one-handed: the only one).
func _nearest_hand(c: Vector3i) -> String:
	if not design.get("twoHanded", false):
		return "main"
	var g = ForgeLib.grip_points(_design_now())
	if g == null:
		return "main"
	return "off" if Vector3(c).distance_to(g.off) < Vector3(c).distance_to(g.main) else "main"

func _erase_at(at: Vector2) -> void:
	var a := _aim(at)
	if not a.is_empty() and a.hit != null and not _stroked(a.hit) and _erase_ready():
		var list := _mirrored([a.hit])
		_remove(list)
		_mark(list)

## The way a sharp block faces, as the smith set it (-1: read off the weapon's shape).
func _face(k: Vector3i) -> int:
	var c: Array = cells.get(k, [])
	return int(c[2]) if c.size() > 2 and (str(c[1]) == "edge" or str(c[1]) == "point") else -1

## Turns the sharp block `k` to face the next way: each of the six in turn, then back to as the
## weapon's shape has it.
func turn_face(k: Vector3i) -> void:
	if not cells.has(k) or not (str(cells[k][1]) == "edge" or str(cells[k][1]) == "point"):
		cost_label.text = "Only an Edge or a Point block turns: point at one and press R"
		return
	_push_undo()
	var f := _face(k) + 1
	if f > 5:
		f = -1
	var c: Array = cells[k].duplicate()
	c.resize(3)
	c[2] = f
	cells[k] = c
	cost_label.text = ("This %s faces %s (R: turn it again)" % [str(c[1]), ForgeLib.FACE_NAMES[f]]) if f >= 0 else "This %s faces as the weapon's shape has it (R: turn it)" % str(c[1])
	_rebuild()

func _place(list: Array, face := -1, origin = null) -> void:
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
	if not free_build and _value_now() + Arms.voxel_price(mat) * add.size() + roundi(Arms.sharp_cost(job, float(design.get("sharpness", 0.8))) * add.size()) - original_value > purse:
		cost_label.text = "Not enough denarii for that"
		return
	_push_undo()
	for c in add:
		# A sharp block faces away from the face it was put on (out from the weapon); a mirrored
		# one the mirrored way.
		var f := face
		if f >= 0 and origin is Vector3i:
			if c.x != (origin as Vector3i).x and f < 2:
				f = 1 - f
			if c.z != (origin as Vector3i).z and f >= 4:
				f = 9 - f
		cells[c] = [mat, job, f if (job == "edge" or job == "point") else -1]
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
	if e is InputEventKey and e.pressed and not e.ctrl_pressed and e.keycode == KEY_F and viewport:
		_frame()   # the whole weapon back in view
	elif e is InputEventKey and e.pressed and not e.ctrl_pressed and e.keycode == KEY_R and viewport and mode == "voxels" and hover_at != null:
		var a := _aim(hover_at)
		if not a.is_empty() and a.get("hit") != null:
			turn_face(a.hit)
	elif e is InputEventKey and e.pressed and e.ctrl_pressed and e.keycode == KEY_Y:
		_redo()
	elif e is InputEventKey and e.pressed and e.ctrl_pressed and e.keycode == KEY_Z:
		if e.shift_pressed:
			_redo()
		else:
			_undo()

func _take() -> void:
	var d := _design_now()
	var st := ForgeLib.compute_stats(d)
	if ForgeLib.too_heavy(d, st) != "":
		cost_label.text = ForgeLib.too_heavy(d, st)
		return
	if not st.hasGrip:
		cost_label.text = "It needs somewhere to be held: build a Grip block, or ✋ Move hand"
		return
	d.stats = st
	var cost := 0 if free_build else _value_now() - original_value
	if not (workshop or scratch or free_build) and cost > purse:
		cost_label.text = "Not enough denarii for that (a keener edge costs more)"
		return
	done.call(d, cost)
