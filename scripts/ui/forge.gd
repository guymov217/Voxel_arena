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
var lesson: ForgeLesson = null      # the guided lesson the tutorial leads into (start_lesson)
var flown := 0.0                    # how far the walking keys have flown the view (m, the lesson reads it)
var saves := 0                      # designs saved since the forge opened (the lesson reads it)
var view_box: Control               # the anvil's view (the lesson's card lies over its foot)
var dummy_fights := false
var try_result: Label               # what the last "Try it in the arena" came to (show_try_result)
var try_text := ""
var line_from = null       # the first cell of a line or a box being drawn
## The weapon pinned for comparison (kept while the game runs, so the forge's next opening shows it too): {name, design, vals}. The bars show the weapon on the anvil against it.
static var pinned := {}
var pin_button: Button
var undo_button: Button
var redo_button: Button
## The ratings made while the game runs, by the weapon's key (WeaponRating.key): what the anvil shows again when the same weapon comes back to it.
static var rated := {}
var rating := {}                # the rating under way, or the last made: {key, pid, job, out, state ("running", "done", "failed"), done, of, t, result}
var rating_button: Button
var rating_stop: Button
var rating_label: Label
var rating_strip: Control
var rate_alive := Callable()    # whether the game that fights the bouts is still there (a test's own answer; else the system's)
const RATE_POLL_S := 0.5        # how often the game that fights the bouts is asked how far it is (s)
var sel := {}                          # the Select tool's pick: Vector3i -> true (what Move, Turn, Flip and Make work on)
var sel_mi: MultiMeshInstance3D = null # its tint on the weapon
var sel_drag := {}                     # a box being dragged over the view: {from, to, moved, add, sub}
var sel_copy := false                  # Copy ticked: the next move leaves the picked blocks where they are and carries a copy
var marquee: Control = null            # draws the dragged box over the view

var viewport: SubViewport
var cam: Camera3D
var weapon_root: Node3D
var anvil: MeshInstance3D
var floor_: MeshInstance3D
var ghost: MeshInstance3D
var turn_ghost: MeshInstance3D    # a halo on the sharp block the mouse is on: the one R turns
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
var room_sides := {}           # the smithy's walls and roof by name (ROOM_SIDES): each put away while the camera is out beyond it
var decor: Array = []          # what stands on its floor: each put away while the camera is in it, or it hides the anvil
var fire_lights: Array = []    # the hearth's and the braziers' lights, flickering ([light, its energy])
var swing_t := -1.0
var swing_st := {}       # the swing preview's stats and grip, read once when it starts
# What is on the anvil, kept from one change to the next (each block put on or taken off only
# touches what changed: the whole weapon was built again for every block, and a big one made the
# forge stutter while a stroke was dragged).
var vox_mi: MultiMeshInstance3D = null
var pick_body: StaticBody3D = null
var pick_shapes := {}      # Vector3i -> its CollisionShape3D (what the mouse points at)
var pick_box: BoxShape3D = null
var ring_key := ""         # where the hands' rings were drawn (drawn again only when they move)
var ring_nodes: Array = []
# The taper of each sharp block (VoxelPart.taper_code) is most of what a change costs on a big
# weapon (33 ms of 38 for 1100 blocks): the blocks round a change are worked out at once, the
# rest kept, and the whole weapon again a moment after the hand stops (forgeperf.gd).
var taper_of := {}         # Vector3i -> its taper code as drawn
var drawn := {}            # Vector3i -> the cell as it was last drawn ([mat, job, face])
var inst_of := {}          # Vector3i -> its instance in the multimesh
var taper_t := -1.0        # until the whole weapon's taper is worked out again (s; -1: it is)
var texts_due := false     # the bars and words over the anvil to bring up to date this frame
const TAPER_NEAR := 2      # blocks this near a change have their taper worked out at once
const TAPER_SETTLE := 0.25 # s after the last change, the whole weapon's

var side_box: VBoxContainer
var mode_row: HBoxContainer
var mode_box: VBoxContainer
var tool_bar: PanelContainer
var name_edit: LineEdit
var bars: Control
var bar_vals := {"speed": 0.0, "damage": 0.0, "reach": 0.0, "armour": 0.0, "durability": 0.0}
# What a change did (user: see at once what each block does): the numbers before the latest run
# of changes, shown against now by the bars for a moment after the last of them.
var stat_now := {}
var stat_base := {}
var stat_delta := {}
var stat_t := -100.0       # when the numbers last changed (s, Time)
var weight_feel := ""      # "Balanced", "Head-heavy"... (ForgeLib.feel)
var com_mark: Node3D = null   # the balance point on the weapon
const DELTA_HOLD := 2.5    # how long a change's ▲ / ▼ stays by the bars (s)
const BAR_ROWS := [["speed", "Speed"], ["damage", "Damage"], ["reach", "Reach"], ["armour", "Vs armour"], ["durability", "Durability"]]
const DURABILITY_C := Color(0.56, 0.7, 0.8)   # (the durability bar: cold steel)
const UP_C := Color(0.5, 0.82, 0.42)
const DOWN_C := Color(0.92, 0.4, 0.3)
var says: Label
var verdict: Label
var cost_label: Label
var hover_at = null      # where the mouse is over the anvil (R turns the sharp block there)

## The smith's stock, each for its own job: three metals for edges (bronze the old soft one),
## bone for light quick blades, three weights from light to dense for hafts and heads, gold for the
## crowd and three gem sockets. (The four tricks, explosive, spring, glue and magnet, are set aside
## for now, user: ForgeLib.SET_ASIDE.)
const MATS := ["steel", "iron", "bronze", "wood", "bone", "stone", "lead", "gold", "ruby", "sapphire", "emerald"]
const JOBS := ["edge", "point", "blunt", "grip"]
const TOOLS := [["build", "Build", "Click a face: a voxel goes on it (hold and drag for more)  [B]"], ["erase", "Erase", "Click voxels: take them off (right click erases too)  [X]"], ["line", "Line", "Click where it starts, then where it ends, any way you like: the path shows as you aim  [L]"], ["hand", "Move hand", "Drag the gold ring (and the bronze one of a two-handed weapon) onto any block: the fighter holds it there  [H]"], ["select", "Select", "Click a block to pick it; drag a box round blocks to pick every block inside it, the ones behind too (Shift adds, Ctrl takes away); double-click picks the whole part, the blocks of one stuff joined together. Then move, copy, turn, flip or remake what is picked  [V]"]]
## The keys at the anvil (shown on the tools' tips and in the tutorial): a tool each, a job each,
## the two mirrors, and Q to take up the material and job of the block under the mouse.
const TOOL_KEYS := {KEY_B: "build", KEY_X: "erase", KEY_L: "line", KEY_H: "hand", KEY_V: "select"}
const JOB_KEYS := {KEY_1: "edge", KEY_2: "point", KEY_3: "blunt", KEY_4: "grip"}
## What each tool asks for, shown under the anvil while it is in hand.
const TOOL_HINT := {
	"build": "Build: click a face of the weapon, or hold and drag (an Edge or Point faces away from it; R turns one; Q takes up the block under the mouse)",
	"erase": "Erase: click blocks, or hold the right button anywhere",
	"line": "Line: click where it starts",
	"hand": "Move hand: click a block (or drag the gold ring): the main hand goes there; the bronze ring is the other hand",
	"select": "Select: click a block, or drag a box round blocks (Shift adds, Ctrl takes away, double-click picks the whole part, right click lets go)",
}

func open(d: Dictionary, coins: int, cb: Callable) -> void:
	add_to_group("bench")   # (the HUD keeps off it)
	if Sfx.music:
		Sfx.music.bench(true)   # (the forge's own tune; the one before it when it closes)
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
	# Armour is made at the same forge: plate by plate on the body part, its own bench (while it is open).
	if Armory.plate_bench_open and get_parent() and get_parent().has_method("armour_from_forge"):
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
	pin_button = UIStyle.button("Pin it", _pin_toggle)
	nr.add_child(pin_button)
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
	bars.custom_minimum_size = Vector2(420, 122)
	bars.draw.connect(_draw_bars)
	bars.tooltip_text = "Speed: how fast it swings and comes back. Damage: how hard a blow lands on bare skin. Reach: how far it hits from the hand. Vs armour: how hard it still lands through an iron plate (an edge skids off unless the blade is heavy; a point finds the joins; a heavy head carries through). The dot on the weapon is its balance point."
	col.add_child(bars)
	says = UIStyle.label("", 13, UIStyle.TEXT)
	says.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	says.custom_minimum_size = Vector2(420, 0)
	col.add_child(says)
	verdict = UIStyle.label("", 12, UIStyle.MUTED)
	verdict.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	verdict.custom_minimum_size = Vector2(420, 0)
	col.add_child(verdict)
	# What he has and what the job costs, always in sight (user: it covered the tools over the anvil, so
	# it is in the panel now, over what the smith says of the work, and out of the way of the work).
	var pb := PanelContainer.new()
	var pbs := StyleBoxFlat.new()
	pbs.bg_color = Color(0.07, 0.05, 0.035, 0.82)
	pbs.border_color = UIStyle.BRONZE_DARK
	pbs.set_border_width_all(1)
	pbs.set_corner_radius_all(8)
	pbs.content_margin_left = 12; pbs.content_margin_right = 12; pbs.content_margin_top = 5; pbs.content_margin_bottom = 5
	pb.add_theme_stylebox_override("panel", pbs)
	pb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	price_badge = UIStyle.label("", 17, UIStyle.GOLD)
	price_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	price_badge.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	price_badge.custom_minimum_size = Vector2(396, 0)
	pb.add_child(price_badge)
	pb.name = "PriceBadge"
	col.add_child(pb)
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
	try_result = UIStyle.label(try_text, 13, UIStyle.GOLD)
	try_result.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	try_result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	try_result.custom_minimum_size = Vector2(420, 0)
	try_result.visible = try_text != ""
	col.add_child(try_result)
	end.add_child(UIStyle.button("Save design", _save_design, workshop))
	end.add_child(UIStyle.button("Back" if workshop else "Leave it as it was", func(): done.call(null, 0)))
	col.add_child(end)
	var right := Control.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(right)
	view_box = right
	var svc := SubViewportContainer.new()
	svc.stretch = true
	svc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	svc.gui_input.connect(_on_view_input)
	svc.mouse_exited.connect(func(): view_mouse = Vector2(-1, -1))
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
	tool_bar.theme = _compact_theme()
	right.add_child(tool_bar)
	# (The box dragged with the Select tool: drawn over the view, never in the mouse's way.)
	marquee = Control.new()
	marquee.mouse_filter = Control.MOUSE_FILTER_IGNORE
	marquee.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	marquee.draw.connect(_draw_marquee)
	right.add_child(marquee)
	viewport = SubViewport.new()
	viewport.own_world_3d = true
	svc.add_child(viewport)
	viewport.msaa_3d = Viewport.MSAA_4X
	_build_smithy()
	_pin_refresh()

## The theme of the tools over the view: the buttons' slabs cut close, so that a row of them is no wider than the view in a language that spells its words long.
static func _compact_theme() -> Theme:
	var t: Theme = UIStyle.theme().duplicate()
	for kind in ["Button", "OptionButton", "MenuButton"]:
		for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
			var sb := t.get_stylebox(state, kind)
			if sb is StyleBoxFlat:
				var c: StyleBoxFlat = (sb as StyleBoxFlat).duplicate()
				c.content_margin_left = 8
				c.content_margin_right = 8
				c.content_margin_top = 6
				c.content_margin_bottom = 6
				t.set_stylebox(state, kind, c)
	t.set_font_size("font_size", "Button", 15)
	# (The pull-downs read like the buttons beside them.)
	for kind in ["OptionButton", "MenuButton"]:
		t.set_font("font", kind, t.get_font("font", "Button"))
		t.set_font_size("font_size", kind, 15)
		t.set_constant("outline_size", kind, 2)
	return t

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
	# (On the weapon, the anvil and the floor they stand on: the room round them is lit by its
	# own fires, _dress_smithy.)
	light.light_cull_mask = 1
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
	# The ground the smithy stands on: trodden earth out to the dark (seen through its door and
	# its windows, and round it from outside), a little under its own floor.
	floor_ = MeshInstance3D.new()
	var fp := PlaneMesh.new()
	fp.size = Vector2(60, 60)
	fp.center_offset = Vector3(0, -0.04, 0)
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.17, 0.13, 0.1)
	fm.roughness = 1.0
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
	turn_ghost = MeshInstance3D.new()
	var tb := BoxMesh.new()
	tb.size = Vector3.ONE * Data.weapon_voxel * 1.16
	var tm := StandardMaterial3D.new()
	tm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tm.albedo_color = Color(1.0, 0.82, 0.3, 0.3)
	tb.material = tm
	turn_ghost.mesh = tb
	turn_ghost.visible = false
	viewport.add_child(turn_ghost)
	line_ghost = MultiMeshInstance3D.new()
	var lmm := MultiMesh.new()
	lmm.transform_format = MultiMesh.TRANSFORM_3D
	lmm.mesh = gb
	line_ghost.multimesh = lmm
	viewport.add_child(line_ghost)

## The smithy the anvil stands in (art/voxel, tools/gen_voxel_art.py: the room's numbers are the
## same there): a room of tufa, brick and smoked plaster under a roof of beams, its floor laid in
## basalt round the anvil and in brick out to the walls; the hearth against the north wall with a
## blade heating in its coals, the bellows and the charcoal by it, the quenching trough under the
## smith's tools, his own anvil on its stump, a rack of arms and a banner on the west wall, the
## bench and the grindstone under the south windows, the way out to the yard in the east wall
## between two braziers (user: there was only a huge tiled floor without end; the forge's
## background should fit the game and a smithy, and its floor too). All of it rides on the floor,
## which follows the weapon's height. Drawing only: nothing in it is touched by the mouse.
const ROOM := Vector3(4.8, 4.0, 4.4)   # half its width (x), the height of its beams, half its depth (z)
const ROOM_SIDES := ["n", "s", "e", "w", "roof"]
const ROOM_EDGE := 0.45                # a side is put away from this far inside it
const ROOM_LAYER := 2                  # the room's own layer: its fires light it and not the weapon
func _dress_smithy() -> void:
	var block := VoxelArt.make("forge_anvil")
	if block:
		anvil.mesh = null
		anvil.add_child(block)
	var room := VoxelArt.make("forge_room")
	if room == null:
		return
	floor_.add_child(room)
	for k in ROOM_SIDES:
		var side := Node3D.new()
		side.name = "side_" + k
		floor_.add_child(side)
		room_sides[k] = side
	for c in room.find_children("*", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		var nm := String(mi.name).to_lower()
		# (The floor in the anvil's own light as well, the weapon's shadow on it. The room throws
		# no shadow of its own: the anvil stands in the light it always stood in.)
		mi.layers = ROOM_LAYER | (1 if nm == "floor" else 0)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for k in ROOM_SIDES:
			if nm == k or nm == "wall_" + k:
				mi.reparent(room_sides[k])
	_hang("w", "banner", Vector3(-ROOM.x + 0.08, 0.95, 1.3), PI * 0.5)
	# North: the hearth, the bellows at its side, the trough under the tools, jars under the niche.
	var hx := -2.4
	_stand("forge_hearth", Vector3(hx, 0, -ROOM.z + 0.6), 0.0)
	_stand("forge_bellows", Vector3(hx - 1.08 - 0.63, 0, -ROOM.z + 0.5), 0.0)
	_stand("forge_trough", Vector3(0.15, 0, -ROOM.z + 0.34), 0.0)
	_stand("forge_stump", Vector3(-1.45, 0, -2.55), 0.6)
	_stand("amphora", Vector3(1.85, 0, -ROOM.z + 0.4), 0.4)
	_stand("amphora_wide", Vector3(2.45, 0, -ROOM.z + 0.45), 1.2)
	_stand("amphora", Vector3(3.0, 0, -ROOM.z + 0.38), 2.0)
	_stand("crate", Vector3(3.95, 0, -ROOM.z + 0.42), 0.2)
	# West: the charcoal, the rack of arms.
	_stand("forge_coal", Vector3(-ROOM.x + 0.5, 0, -2.75), PI * 0.5)
	_stand("weapon_rack", Vector3(-ROOM.x + 0.3, 0, -1.3), PI * 0.5)
	_stand("crate", Vector3(-ROOM.x + 0.45, 0, 3.95), 0.1)
	_stand("crate", Vector3(-ROOM.x + 1.15, 0, 4.0), -0.25)
	_stand("crate", Vector3(-ROOM.x + 0.5, 0.6, 3.95), 0.5)
	# South: the bench under one window, the grindstone under the other, crates between.
	_stand("forge_bench", Vector3(-2.4, 0, ROOM.z - 0.37), PI)
	_stand("forge_grindstone", Vector3(2.4, 0, ROOM.z - 0.75), PI)
	_stand("crate", Vector3(-0.45, 0, ROOM.z - 0.4), 0.15)
	_stand("amphora_wide", Vector3(0.35, 0, ROOM.z - 0.4), 0.7)
	_stand("forge_sacks", Vector3(4.2, 0, ROOM.z - 0.45), PI)
	# East: a brazier either side of the way out, a barrel of blanks.
	_stand("brazier", Vector3(ROOM.x - 0.6, 0, -1.95), 0.0)
	_stand("brazier", Vector3(ROOM.x - 0.6, 0, 1.95), 0.0)
	_stand("forge_barrel", Vector3(ROOM.x - 0.45, 0, -3.45), 0.3)
	_stand("amphora", Vector3(ROOM.x - 0.4, 0, 3.4), 2.6)
	# Out in the yard, seen through the door: a marble gladiator on his pedestal, a brazier by him.
	_stand("statue", Vector3(ROOM.x + 5.2, 0, 0.5), -PI * 0.5)
	_stand("brazier", Vector3(ROOM.x + 3.8, 0, -1.5), 0.0)
	# The fires' light, on the room alone: the hearth's (on what is in it, and spilt out before
	# it), the braziers', the torches' on the south and west walls.
	_fire(Vector3(hx - 0.2, 1.45, -ROOM.z + 0.75), Color(1.0, 0.5, 0.19), 2.4, 3.5)
	_fire(Vector3(hx, 1.35, -ROOM.z + 1.9), Color(1.0, 0.52, 0.22), 2.4, 7.5, 0.3)
	_fire(Vector3(ROOM.x - 0.6, 1.8, -1.95), Color(1.0, 0.6, 0.28), 1.6, 5.0)
	_fire(Vector3(ROOM.x - 0.6, 1.8, 1.95), Color(1.0, 0.6, 0.28), 1.6, 5.0)
	_fire(Vector3(0.0, 2.5, ROOM.z - 0.9), Color(1.0, 0.62, 0.3), 1.1, 5.5, 0.3)
	_fire(Vector3(-ROOM.x + 0.9, 2.5, 2.8), Color(1.0, 0.62, 0.3), 0.9, 4.5, 0.3)
	_fire(Vector3(ROOM.x + 3.8, 1.8, -1.5), Color(1.0, 0.6, 0.28), 2.2, 6.0)

## A model stood on the smithy's floor (`at`: in the room, the anvil at its middle), turned `yaw`.
func _stand(model: String, at: Vector3, yaw: float) -> Node3D:
	var n := VoxelArt.place(floor_, model, at, yaw)
	if n == null:
		return null
	var box := AABB()
	var first := true
	for c in n.find_children("*", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		mi.layers = ROOM_LAYER
		var b: AABB = (n.transform * mi.transform) * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	n.set_meta("decor_box", box)
	decor.append(n)
	return n

## A model hung on a wall: put away with it.
func _hang(side: String, model: String, at: Vector3, yaw: float) -> void:
	var n := VoxelArt.place(room_sides[side], model, at, yaw)
	if n:
		for c in n.find_children("*", "MeshInstance3D", true, false):
			(c as MeshInstance3D).layers = ROOM_LAYER

func _fire(at: Vector3, col: Color, energy: float, reach: float, shine := 0.5) -> void:
	var l := OmniLight3D.new()
	l.light_color = col
	l.light_energy = energy
	l.light_specular = shine
	l.omni_range = reach
	l.omni_attenuation = 1.2
	l.light_cull_mask = ROOM_LAYER
	floor_.add_child(l)
	l.position = at
	fire_lights.append([l, energy])

## Whether a side of the room (ROOM_SIDES) is put away for a camera at `lp` (in the room: the
## anvil's foot at its middle): the camera is out beyond it, or all but in it.
static func room_side_hidden(side: String, lp: Vector3) -> bool:
	match side:
		"n":
			return lp.z < -ROOM.z + ROOM_EDGE
		"s":
			return lp.z > ROOM.z - ROOM_EDGE
		"w":
			return lp.x < -ROOM.x + ROOM_EDGE
		"e":
			return lp.x > ROOM.x - ROOM_EDGE
		"roof":
			return lp.y > ROOM.y - ROOM_EDGE
	return false

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
	if m != "gallery":
		_rating_ui()
	ghost.visible = false
	turn_ghost.visible = false
	line_from = null
	sel_drag = {}
	_show_line([])
	if tool_bar:
		_toolbar_ui()
	_update_texts()

## The guided lesson (ForgeLesson): its card over the foot of the view, one thing to do at a
## time, Next on a page to read, and a way out of it.
var lesson_card: PanelContainer = null
var lesson_bits := {}
var lesson_key := ""
func start_lesson() -> void:
	lesson = ForgeLesson.new(self)
	lesson_card = PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.07, 0.05, 0.035, 0.93)
	st.border_color = UIStyle.GOLD
	st.set_border_width_all(1)
	st.border_width_left = 4
	st.set_corner_radius_all(8)
	st.content_margin_left = 18; st.content_margin_right = 18; st.content_margin_top = 12; st.content_margin_bottom = 12
	lesson_card.add_theme_stylebox_override("panel", st)
	lesson_card.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	lesson_card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	lesson_card.grow_vertical = Control.GROW_DIRECTION_BEGIN
	lesson_card.offset_bottom = -16
	view_box.add_child(lesson_card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	lesson_card.add_child(v)
	lesson_bits.step = UIStyle.label("", 11, UIStyle.BRONZE)
	lesson_bits.title = UIStyle.label("", 22, UIStyle.GOLD_LIGHT)
	lesson_bits.text = UIStyle.label("", 15, UIStyle.TEXT)
	lesson_bits.text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lesson_bits.text.custom_minimum_size = Vector2(540, 0)
	for k in ["step", "title", "text"]:
		v.add_child(lesson_bits[k])
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.alignment = BoxContainer.ALIGNMENT_END
	lesson_bits.next = UIStyle.button("Next", func():
		if lesson.finished:
			_end_lesson()
		else:
			lesson.next(), true)
	lesson_bits.skip = UIStyle.button("Skip the lesson", func():
		lesson.skip()
		_end_lesson())
	row.add_child(lesson_bits.skip)
	row.add_child(lesson_bits.next)
	v.add_child(row)
	_lesson_show()

func _end_lesson() -> void:
	if lesson_card:
		lesson_card.queue_free()
	lesson_card = null
	lesson = null

func _lesson_show() -> void:
	if lesson == null or lesson_card == null:
		return
	var lv := lesson.view()
	var key := "%s|%s|%s" % [lv.step, lv.ok, lv.get("done", false)]
	if key == lesson_key:
		return
	lesson_key = key
	lesson_bits.step.text = Loc.t("FORGE LESSON · STEP %d OF %d") % [mini(int(lv.step) + 1, int(lv.total)), int(lv.total)]
	lesson_bits.title.text = Loc.t(String(lv.title))
	lesson_bits.title.add_theme_color_override("font_color", Color(0.6, 0.95, 0.5) if lv.ok else UIStyle.GOLD_LIGHT)
	lesson_bits.text.text = String(lv.text)
	lesson_bits.next.text = Loc.t("Close") if lv.get("done", false) else Loc.t("Next")
	lesson_bits.next.visible = lv.get("done", false) or lv.get("read", false)
	lesson_bits.skip.visible = not lv.get("done", false)

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
			names.append(Loc.t(String(Data.campaign.enemies[k].get("label", k))))
	for k in Data.beasts:
		if Edition.foe_open(k) and k != "goat":
			keys.append(k)
			names.append(Loc.t(String(Data.beasts[k].get("name", k))))
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
			cost_label.text = "It needs somewhere to be held: build a Grip block, or Move hand"
			return
		if get_parent() and get_parent().has_method("try_from_forge"):
			get_parent().try_from_forge(self, d, dummy_pick, dummy_fights, String(names[maxi(0, keys.find(dummy_pick))]))))
	return row

## Back from the arena: what the weapon did there (Menu.back_to_forge, its tally of the blows of
## the weapon on what it was tried on), kept under the button until the next try.
func show_try_result(t: Dictionary, who: String) -> void:
	if int(t.get("hits", 0)) <= 0:
		try_text = Loc.t("Last try against %s: no blow landed") % Loc.t(who)
	else:
		try_text = Loc.t("Last try against %s: %d hits · best blow %d · %d limbs off · %d kills") % [Loc.t(who), int(t.hits), roundi(float(t.get("best", 0.0))), int(t.get("limbs", 0)), int(t.get("kills", 0))]
	if try_result and is_instance_valid(try_result):
		try_result.text = try_text
		try_result.visible = true

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
	mode_box.add_child(UIStyle.label(Loc.t("2 · ADD UP TO %d TWISTS") % ForgeLib.MAX_PICKS, 13, UIStyle.BRONZE))
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
		var b := UIStyle.button("%s  %s" % [Loc.t(String(mdef.label)), "●" if picks.has(key) else arrows], func(): _toggle_pick(key))
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
## The materials in three rows, the way a smith sorts them.
const MAT_GROUPS := [["Metals", ["steel", "iron", "bronze", "gold", "lead"]], ["Wood, bone, stone", ["wood", "bone", "stone"]], ["Gems", ["ruby", "sapphire", "emerald"]]]
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

## A small drawn arrow for a button that has no words (the pad that moves the pick, Undo, Redo): an arrow pointing `dir` (left, right, up, down, front or back: a diagonal), or a curved one over the top, its head at the left (undo) or the right (redo). Drawn here
## and not set in a font: no font has to have the glyph, and none can put a coloured picture in its place.
static func _arrow_icon(kind: String, px := 18) -> ImageTexture:
	var img := Image.create(px, px, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var col := UIStyle.GOLD_LIGHT
	var dir := Vector2.ZERO
	match kind:
		"left": dir = Vector2(-1, 0)
		"right": dir = Vector2(1, 0)
		"up": dir = Vector2(0, 1)
		"down": dir = Vector2(0, -1)
		"front": dir = Vector2(-1, -1).normalized()
		"back": dir = Vector2(1, 1).normalized()
	var c := float(px - 1) * 0.5
	for y in px:
		for x in px:
			# (The picture's own axes: x to the right, y up.)
			var p := Vector2((x - c) / c, (c - y) / c)
			var on := false
			if kind == "undo" or kind == "redo":
				var q := Vector2(p.x if kind == "undo" else -p.x, p.y)
				# A top semicircle from the right round to the left, its head at the left end pointing down.
				var r := (q - Vector2(0, -0.15)).length()
				var ang := rad_to_deg(atan2(q.y + 0.15, q.x))
				on = r > 0.42 and r < 0.7 and ang > -5.0 and ang < 175.0
				on = on or (q.y < -0.05 and q.y > -0.78 and absf(q.x + 0.56) < (q.y + 0.78) * 0.62)
			else:
				var a := p.dot(dir)
				var b := p.dot(Vector2(-dir.y, dir.x))
				# The head is a triangle, the shaft a short bar behind it.
				on = (a > 0.05 and a < 0.88 and absf(b) < (0.88 - a) * 0.95) or (a <= 0.05 and a > -0.8 and absf(b) < 0.2)
			if on:
				img.set_pixel(x, y, col)
	return ImageTexture.create_from_image(img)

## A button with a drawn arrow on it and no words (dimmed with the rest while it cannot be pressed).
func _icon_button(kind: String, cb: Callable) -> Button:
	var b := UIStyle.button("", cb)
	b.icon = _arrow_icon(kind)
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.expand_icon = false
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size.x = 34
	b.add_theme_color_override("icon_disabled_color", Color(1, 1, 1, 0.3))
	return b

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
	return Loc.t("%d%% · honing %d (%d Cut/Stab block)" if n == 1 else "%d%% · honing %d (%d Cut/Stab blocks)") % [roundi(k * 100.0), Arms.honing(_jobs_now(), k), n]

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
	mode_box.add_child(UIStyle.label("2 · MATERIAL", 13, UIStyle.BRONZE))
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
			b.text = m.capitalize()   # (no price a block on it: what the weapon costs is on show over the anvil, user)
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
	var tip := Loc.t("Sharpness: how easily the Cut and Stab blocks get into flesh and how deep they wound. Crush and Hold blocks have no edge: it does nothing for them and they cost no honing.\nHoning each Cut or Stab block costs, by the sharpness set:\n%s") % "\n".join([0.25, 0.5, 0.75, 1.0].map(func(k): return Loc.t("  %d%%: %.1f denarii a block") % [roundi(k * 100.0), Arms.sharp_cost("edge", k)]))
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
	# One row: the tools, the mirror, the way back and what is asked for seldom (user: far too many buttons). What belongs to one tool only,
	# the pick's or the two hands', comes in a row of its own under it while that tool is in hand, and not before.
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
	trow.add_child(VSeparator.new())
	trow.add_child(_mirror_menu())
	trow.add_child(VSeparator.new())
	# (Two drawn arrows, not the words: the words are long in some languages, and every editor's Undo and Redo are these.)
	undo_button = _icon_button("undo", _undo)
	undo_button.tooltip_text = "Take back the last change  [Ctrl+Z]"
	redo_button = _icon_button("redo", _redo)
	redo_button.tooltip_text = "Put back what was taken back  [Ctrl+Y]"
	trow.add_child(undo_button)
	trow.add_child(redo_button)
	_history_buttons()
	trow.add_child(_more_menu())
	rows.add_child(trow)
	var under := _tool_row()
	if under != null:
		rows.add_child(under)

## Both mirrors in one pull-down (they were two boxes): off, left and right alike, front and back alike, both. M and Shift+M turn them one at a time.
const MIRRORS := [["Mirror: off", false, false], ["Mirror ⟷", true, false], ["Mirror ⇅", false, true], ["Mirror ⟷ ⇅", true, true]]
func _mirror_index() -> int:
	return (1 if mirror else 0) + (2 if mirror_z else 0)

func _mirror_menu() -> OptionButton:
	var ob := OptionButton.new()
	for m in MIRRORS:
		ob.add_item(m[0])
	ob.select(_mirror_index())
	ob.focus_mode = Control.FOCUS_NONE
	ob.tooltip_text = "A block built on one side goes on the other side too: left and right (⟷), front and back (⇅), or both  [M, Shift+M]"
	ob.item_selected.connect(func(i):
		mirror = MIRRORS[i][1]
		mirror_z = MIRRORS[i][2]
		cost_label.text = Loc.t("Mirror ⟷ %s, mirror ⇅ %s") % [Loc.t("On") if mirror else Loc.t("Off"), Loc.t("On") if mirror_z else Loc.t("Off")])
	return ob

## What is asked for seldom, behind one button: Clear and, in training, Surprise me (Clear alone is a button of its own).
func _more_menu() -> Control:
	var items: Array = [["Clear", _clear_blocks]]
	if free_build:
		items.append(["Surprise me", _surprise_me])
	if items.size() == 1:
		var only := UIStyle.button(items[0][0], items[0][1])
		only.tooltip_text = "Take every block off but the grip"
		return only
	return _pull_menu("More", "Take every block off but the grip, or let the forge surprise you", items.map(func(it): return it[0]), func(id): (items[id][1] as Callable).call())

func _clear_blocks() -> void:
	_push_undo()
	var keep: Dictionary = {}
	for k in cells:
		if cells[k][1] == "grip":
			keep[k] = cells[k]
	if keep.is_empty() and not cells.is_empty():
		var first = cells.keys()[0]
		keep[first] = cells[first]
	cells = keep
	_rebuild()

func _surprise_me() -> void:
	_push_undo()
	var d := ForgeLib.surprise_weapon(rng)
	for k in ["kind", "shoots", "stats", "chain", "balance", "grips"]:
		design.erase(k)
	design.merge(d, true)
	_load_cells(d)
	name_edit.text = d.name
	framed = false
	_rebuild()

## A button that opens a short list: its caption (and a ▾), a tip and the lines; `pick` gets the number of the line chosen.
func _pull_menu(caption: String, tip: String, lines: Array, pick: Callable) -> MenuButton:
	var mb := MenuButton.new()
	mb.text = Loc.t(caption) + " ▾"
	mb.flat = false
	mb.focus_mode = Control.FOCUS_NONE
	mb.tooltip_text = tip
	var pm := mb.get_popup()
	for l in lines:
		pm.add_item(l)
	pm.id_pressed.connect(pick)
	return mb

## The row under the tools, for the tool in hand when it has more to ask: null for the rest.
func _tool_row() -> Control:
	if tool == "select":
		return _select_row()
	if tool == "hand" and bool(design.get("twoHanded", false)):
		return _hands_row()
	return null

## The two hands of a two-handed weapon (the Move hand tool): a button for each puts that hand on the next block clicked, wherever its ring is; neither pressed, the click takes the hand whose ring is nearest.
func _hands_row() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	for hd in [["main", "Main hand", UIStyle.GOLD], ["off", "Other hand", UIStyle.BRONZE]]:
		var which: String = hd[0]
		var pb := UIStyle.button(hd[1], func():
			hand_pick = "" if hand_pick == which else which
			line_from = null
			_show_line([])
			_toolbar_ui()
			cost_label.text = Loc.t("Click the block where the main hand holds it (its ring: gold)" if which == "main" else "Click the block where the other hand holds it (its ring: bronze)") if hand_pick == which else TOOL_HINT.hand)
		pb.toggle_mode = true
		pb.button_pressed = hand_pick == which
		pb.focus_mode = Control.FOCUS_NONE
		pb.add_theme_color_override("font_color", hd[2])
		pb.add_theme_color_override("font_pressed_color", hd[2])
		pb.tooltip_text = Loc.t("Put the main hand on a block: click it on the weapon" if which == "main" else "Put the other hand on a block: click it on the weapon")
		row.add_child(pb)
	return row

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
		cost_label.text = "Say where it is held before you save it: build a Grip block, or Move hand"
		return
	var g := gallery().filter(func(o): return str(o.get("name", "")) != str(d.get("name", "")))
	d.erase("imbue")
	g.push_front(d)
	Save.set_value("forge_gallery", g.slice(0, GALLERY_MAX))
	Achievements.unlock("smith")
	saves += 1
	cost_label.text = Loc.t("Saved to My designs: \"%s\"") % str(d.get("name", "?"))
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
		var pin_b := UIStyle.button("Pin", func(): _pin(d))
		pin_b.tooltip_text = "Pin this design: the bars show how the weapon on the anvil compares with it"
		row.add_child(pin_b)
		if scratch:
			# At the smith: have it made as it is, for what it is worth.
			var price := Arms.design_price(d)
			var buy := UIStyle.button(Loc.t("Buy · %d") % price, func():
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
	return Loc.t("%s   Hardness %s   Weight %s") % [Loc.t(str(d.get("name", m))).get_slice(" (", 0).get_slice("（", 0), "●".repeat(h) + "○".repeat(5 - h), "●".repeat(w) + "○".repeat(5 - w)]

static func material_text(m: String) -> String:
	var d: Dictionary = Data.material(m)
	var h := clampi(int(round(float(d.get("hardness", 0.5)) * 5.0)), 0, 5)
	var w := clampi(int(round(log(maxf(0.0008, float(d.get("mass", 0.02))) / 0.0008) / log(0.22 / 0.0008) * 5.0)), 0, 5)
	return Loc.t("%s: %s  Hardness %s  Weight %s") % [Loc.t(str(d.get("name", m))).get_slice(" (", 0).get_slice("（", 0), Loc.t(MAT_USE.get(m, "")), "●".repeat(h) + "○".repeat(5 - h), "●".repeat(w) + "○".repeat(5 - w)]

func _draw_bars() -> void:
	var font := UIStyle.serif(1)
	# (The names as wide as the language makes them.)
	var lw := 64.0
	for r in BAR_ROWS + [["", "Weight"]]:
		lw = maxf(lw, font.get_string_size(Loc.t(r[1]), HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x)
	var x0 := lw + 12.0
	# With a weapon pinned the figures against it take a column at the right of the bars, and its name a line over them.
	var pv: Dictionary = pinned.get("vals", {}) if not pinned.is_empty() else {}
	var pin_col := PIN_COL if not pv.is_empty() else 0.0
	var w := maxf(120.0, bars.size.x - x0 - 70.0 - pin_col)
	var fade := _delta_fade()
	var y := 2.0
	if not pv.is_empty():
		bars.draw_string(font, Vector2(0, y + 12), Loc.t("Pinned: %s") % str(pinned.get("name", "?")), HORIZONTAL_ALIGNMENT_LEFT, bars.size.x, 13, UIStyle.GOLD)
		y += PIN_LINE
	for r in BAR_ROWS:
		var k: String = r[0]
		bars.draw_string(font, Vector2(0, y + 14), Loc.t(r[1]), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UIStyle.MUTED)
		bars.draw_rect(Rect2(x0, y + 3, w, 12), Color(0, 0, 0, 0.5))
		var col: Color = Color(0.85, 0.32, 0.2) if k == "damage" else (UIStyle.BRONZE if k == "armour" else (DURABILITY_C if k == "durability" else UIStyle.GOLD))
		bars.draw_rect(Rect2(x0, y + 3, w * float(bar_vals.get(k, 0.0)), 12), col)
		# The pinned weapon's mark on the bar, and how far this one is from it: the whole time, not only after a change.
		if not pv.is_empty():
			bars.draw_rect(Rect2(x0 + w * float(pv.bars.get(k, 0.0)) - 1.0, y + 1, 2, 16), Color(0.96, 0.95, 0.9))
			var dp := pin_delta(float(stat_now.get(k, 0.0)), float(pv.now.get(k, 0.0)))
			var pc: Color = UIStyle.MUTED
			var pt := "="
			if absf(dp) >= 1.0:
				pc = UP_C if dp > 0.0 else DOWN_C
				pt = "%s %d%%" % ["▲" if dp > 0.0 else "▼", int(round(absf(dp)))]
			bars.draw_string(font, Vector2(bars.size.x - PIN_COL, y + 14), pt, HORIZONTAL_ALIGNMENT_RIGHT, PIN_COL, 13, pc)
		# What the last change did to it, for a moment: ▲ 6% or ▼ 4%.
		var dv := float(stat_delta.get(k, 0.0))
		if fade > 0.0 and absf(dv) >= 1.0:
			var c: Color = UP_C if dv > 0.0 else DOWN_C
			c.a = fade
			bars.draw_string(font, Vector2(x0 + w + 8.0, y + 14), "%s %d%%" % ["▲" if dv > 0.0 else "▼", int(round(absf(dv)))], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, c)
		y += 20.0
	# The weight, how it sits in the hand, and what the last change put on or took off.
	bars.draw_string(font, Vector2(0, y + 14), Loc.t("Weight"), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UIStyle.MUTED)
	var kg := Loc.t("%.2f kg") % float(stat_now.get("mass", 0.0))
	bars.draw_string(font, Vector2(x0, y + 14), kg, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UIStyle.TEXT)
	var xr := x0 + font.get_string_size(kg, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x + 10.0
	if weight_feel != "":
		var fs := "·  " + Loc.t(weight_feel)
		bars.draw_string(font, Vector2(xr, y + 14), fs, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UIStyle.GOLD)
		xr += font.get_string_size(fs, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x + 10.0
	if not pv.is_empty():
		var dk := float(stat_now.get("mass", 0.0)) - float(pv.now.get("mass", 0.0))
		bars.draw_string(font, Vector2(bars.size.x - PIN_COL, y + 14), Loc.t("%+.2f kg") % dk, HORIZONTAL_ALIGNMENT_RIGHT, PIN_COL, 13, UIStyle.MUTED)
	var dm := float(stat_delta.get("mass", 0.0))
	if fade > 0.0 and absf(dm) >= 0.005:
		var mc := UIStyle.MUTED
		mc.a = fade
		var mt := Loc.t("%+.2f kg") % dm
		var mx := maxf(xr, x0 + w + 8.0)
		# (With a weapon pinned, its figure has the right-hand end of the line: this one is left out where the two would meet.)
		if mx + font.get_string_size(mt, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x <= bars.size.x - pin_col - 4.0:
			bars.draw_string(font, Vector2(mx, y + 14), mt, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, mc)

## How much of a change's ▲ / ▼ is still shown: whole for DELTA_HOLD after it, then gone.
func _delta_fade() -> float:
	return clampf((DELTA_HOLD - (Time.get_ticks_msec() / 1000.0 - stat_t)) / 0.6, 0.0, 1.0)

const PIN_LINE := 16.0   # the line over the bars that names the pinned weapon (px)
const PIN_COL := 62.0    # the column at the right of the bars for its per cent (px)

## What a design comes to on the bars, as _update_texts counts the weapon on the anvil: the five bars (0 to 1) and the figures the changes are counted on (the swing speed, the reach in metres, the weight).
static func bars_of(d: Dictionary) -> Dictionary:
	var st := ForgeLib.compute_stats(d)
	var b := ForgeLib.three_bars(st)
	var dur := ForgeLib.durability_bar(d)
	return {
		"bars": {"speed": float(b.speed), "damage": float(b.damage), "reach": float(b.reach), "armour": float(b.armour), "durability": dur},
		"now": {"speed": float(st.swingSpeed), "damage": float(b.damage), "reach": float(st.reach), "armour": float(b.armour), "durability": dur, "mass": float(st.mass)},
	}

## How much more (or less, negative) this is than the pinned figure, in per cent (100 where the pinned is nothing and this is something).
static func pin_delta(now: float, was: float) -> float:
	if was > 0.001:
		return (now / was - 1.0) * 100.0
	return 100.0 if now > 0.001 else 0.0

## Pin a design for comparison (the weapon on the anvil, or one of My designs): the bars show the weapon on the anvil against it from now on.
func _pin(d: Dictionary, label := "") -> void:
	var dd := d.duplicate(true)
	dd.erase("stats")
	pinned = {"name": (label if label != "" else str(d.get("name", "?"))).substr(0, 32), "design": dd, "vals": bars_of(dd)}
	_pin_refresh()
	cost_label.text = Loc.t("Pinned: %s") % str(pinned.name)

func _pin_now() -> void:
	var d := _design_now()
	if (d.voxels as Array).is_empty():
		return
	_pin(d)

func _unpin() -> void:
	pinned = {}
	_pin_refresh()

## The one button: Pin it, and Unpin while something is pinned.
func _pin_toggle() -> void:
	if pinned.is_empty():
		_pin_now()
	else:
		_unpin()

const PIN_TIP := "Pin the weapon as it is now: the bars then show what you change against it (a white mark on each bar, ▲ better and ▼ worse at the right) until you unpin it"
const UNPIN_TIP := "Take the comparison away"

## The pin's button and the room for its line over the bars.
func _pin_refresh() -> void:
	if pin_button and is_instance_valid(pin_button):
		pin_button.text = "Pin it" if pinned.is_empty() else "Unpin"
		pin_button.tooltip_text = PIN_TIP if pinned.is_empty() else UNPIN_TIP
	if bars and is_instance_valid(bars):
		bars.custom_minimum_size.y = 122.0 + (PIN_LINE if not pinned.is_empty() else 0.0)
		bars.queue_redraw()

## The balance point on the weapon: a small white dot where its weight sits, seen through the
## blocks, named beside it (user: see where the weight is).
func _place_balance(st: Dictionary) -> void:
	if weapon_root == null:
		return
	var vs := Data.weapon_voxel
	if com_mark == null or not is_instance_valid(com_mark):
		com_mark = Node3D.new()
		var dot := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = vs * 0.42
		sm.height = vs * 0.84
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.96, 0.95, 0.9)
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.no_depth_test = true
		sm.material = mat
		dot.mesh = sm
		com_mark.add_child(dot)
		var tag := Label3D.new()
		tag.text = "BALANCE"
		tag.modulate = Color(0.96, 0.95, 0.9)
		tag.outline_size = 8
		tag.font_size = 30
		tag.pixel_size = vs * 0.03
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.no_depth_test = true
		# (Beside the dot on the far side from the hand's MAIN tag, its own width away in any language.)
		var fw: float = ThemeDB.fallback_font.get_string_size(Loc.t(tag.text), HORIZONTAL_ALIGNMENT_LEFT, -1, tag.font_size).x * tag.pixel_size
		tag.position = Vector3(-vs * 1.1 - fw * 0.5, 0, 0)
		com_mark.add_child(tag)
		weapon_root.add_child(com_mark)
	var c: Array = st.get("com", [0.0, 0.0, 0.0])
	com_mark.position = Vector3(float(c[0]), float(c[1]), float(c[2])) * vs
	com_mark.visible = not cells.is_empty() and weight_feel != ""

func _update_texts() -> void:
	if bars == null:
		return
	var d := _design_now()
	var st := ForgeLib.compute_stats(d)
	bar_vals = ForgeLib.three_bars(st)
	bar_vals["durability"] = ForgeLib.durability_bar(d)
	# What this change did, counted from before the run of changes it belongs to (a stroke, or
	# clicks close together): a quiet spell starts a new count.
	var now := {"speed": float(st.swingSpeed), "damage": float(bar_vals.damage), "reach": float(st.reach), "armour": float(bar_vals.armour), "durability": float(bar_vals.durability), "mass": float(st.mass)}
	var t_now := Time.get_ticks_msec() / 1000.0
	if stat_now.is_empty():
		stat_base = now
	elif now != stat_now:
		if t_now - stat_t > DELTA_HOLD:
			stat_base = stat_now
		stat_t = t_now
	stat_now = now
	stat_delta = {"mass": float(now.mass) - float(stat_base.mass)}
	for k in ["speed", "damage", "reach", "armour", "durability"]:
		var b0 := float(stat_base.get(k, 0.0))
		stat_delta[k] = (float(now[k]) / b0 - 1.0) * 100.0 if b0 > 0.001 else (100.0 if float(now[k]) > 0.001 else 0.0)
	weight_feel = ForgeLib.feel(d, st)
	_place_balance(st)
	bars.queue_redraw()
	says.text = Loc.t("The smith: \"%s\"") % Loc.t(ForgeLib.blacksmith_says(d, st))
	verdict.text = Loc.t("The dummy: %s  ·  %d voxels") % [Loc.t(ForgeLib.dummy_verdict(d, st)), cells.size()]
	for c in mode_box.get_children():
		if c.has_meta("checklist"):
			c.text = "\n".join(ForgeLib.checklist(d, st).map(func(i): return ("● " if i.done else "○ ") + Loc.t(String(i.text))))
	# (What he has and what it costs is the badge's, over this line: here only what the badge does not say.)
	cost_label.text = price_text(d) if (free_build and not scratch) or workshop else ""
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
	_rating_refresh(d, st)

## What the weapon on the anvil comes to, spelled out: what it is made of and the smith's work,
## what is paid now, and what is left in the purse after (or how much is missing).
func price_text(d: Dictionary) -> String:
	if free_build and not scratch and not workshop:
		return "Free in training"
	if workshop:
		return Loc.t("Kept in My designs, free. Made at the smith in the campaign it would cost %d denarii.") % Arms.design_price(d)
	# Just what he has and what it costs (user: the rest was more than anyone could follow).
	var pay: int = Arms.design_price(d) if scratch else _value_now() - original_value
	if pay < 0:
		return Loc.t("You have %d · you get %d back") % [purse, -pay]
	if pay > purse:
		return Loc.t("You have %d · this costs %d (%d more needed)") % [purse, pay, pay - purse]
	return Loc.t("You have %d · this costs %d") % [purse, pay]

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
		price_badge.text = Loc.t("At the smith: %d denarii") % Arms.design_price(_design_now())
		price_badge.add_theme_color_override("font_color", UIStyle.GOLD)
		return
	var pr := _price_now()
	var pay: int = pr[0]
	if pay < 0:
		price_badge.text = Loc.t("You have %d   ·   You get %d back") % [purse, -pay]
		price_badge.add_theme_color_override("font_color", UIStyle.GOLD)
	elif pay > purse:
		price_badge.text = Loc.t("You have %d   ·   This costs %d   (%d more needed)") % [purse, pay, pay - purse]
		price_badge.add_theme_color_override("font_color", Color(1, 0.55, 0.45))
	else:
		price_badge.text = Loc.t("You have %d   ·   This costs %d") % [purse, pay]
		price_badge.add_theme_color_override("font_color", UIStyle.GOLD)

# ---------- The weapon on the anvil ----------

func _rebuild() -> void:
	var vs := Data.weapon_voxel
	if vox_mi == null or not is_instance_valid(vox_mi):
		var bm := BoxMesh.new()
		bm.size = Vector3.ONE * vs * 0.96
		# Drawn as in the arena (shaders/voxel_body.gdshader: steel shines as steel, wood is grained),
		# not as chalk-white blocks in the forge light.
		bm.material = VoxelPart.body_material()
		var mm0 := MultiMesh.new()
		mm0.transform_format = MultiMesh.TRANSFORM_3D
		mm0.use_colors = true
		mm0.use_custom_data = true
		mm0.mesh = bm
		vox_mi = MultiMeshInstance3D.new()
		vox_mi.multimesh = mm0
		weapon_root.add_child(vox_mi)
	var mm := vox_mi.multimesh
	mm.instance_count = cells.size()
	var i := 0
	var centre := Vector3.ZERO
	# Sharp voxels drawn tapered, as on the weapon in the arena: worked out again only round what
	# changed (all of it when much changed at once: a weapon loaded, undone, cleared).
	var changed := []
	for k in cells:
		if not drawn.has(k) or drawn[k] != cells[k]:
			changed.append(k)
	for k in drawn:
		if not cells.has(k):
			changed.append(k)
	var redo_all := changed.size() > 48 or taper_of.is_empty()
	var near := {}
	if not redo_all:
		for c in changed:
			for dx in range(-TAPER_NEAR, TAPER_NEAR + 1):
				for dy in range(-TAPER_NEAR, TAPER_NEAR + 1):
					for dz in range(-TAPER_NEAR, TAPER_NEAR + 1):
						var q: Vector3i = c + Vector3i(dx, dy, dz)
						if cells.has(q):
							near[q] = true
		if not changed.is_empty():
			taper_t = TAPER_SETTLE
	var jobs := {}
	var faces := {}
	for k in cells:
		jobs[k] = str(cells[k][1])
		if _face(k) >= 0:
			faces[k] = _face(k)
	var memo := {}
	inst_of = {}
	for k in cells:
		if redo_all or near.has(k) or not taper_of.has(k):
			taper_of[k] = VoxelPart.taper_code(jobs, k, _face(k), faces, memo)
		mm.set_instance_transform(i, Transform3D(Basis(), Vector3(k) * vs))
		mm.set_instance_color(i, Weapon.voxel_color(cells[k][0], cells[k][1]))
		mm.set_instance_custom_data(i, VoxelPart.kind_data(VoxelPart.kind_of_material(str(cells[k][0])), 0, int(taper_of[k])))
		inst_of[k] = i
		centre += Vector3(k) * vs
		i += 1
	if redo_all:
		taper_t = -1.0
	for k in taper_of.keys():
		if not cells.has(k):
			taper_of.erase(k)
	drawn = cells.duplicate()
	# Pickable boxes for the mouse, one a voxel: only those of blocks put on or taken off change.
	if pick_body == null or not is_instance_valid(pick_body):
		pick_body = StaticBody3D.new()
		weapon_root.add_child(pick_body)
		pick_shapes = {}
	if pick_box == null:
		pick_box = BoxShape3D.new()
		pick_box.size = Vector3.ONE * vs
	for k in pick_shapes.keys():
		if not cells.has(k):
			(pick_shapes[k] as Node).free()   # (at once: a ray this frame must not find it)
			pick_shapes.erase(k)
	for k in cells:
		if not pick_shapes.has(k):
			var cs := CollisionShape3D.new()
			cs.shape = pick_box
			cs.position = Vector3(k) * vs
			cs.set_meta("cell", k)
			pick_body.add_child(cs)
			pick_shapes[k] = cs
	if cells.size():
		centre /= cells.size()
	weapon_root.set_meta("centre", centre)
	# Where the hands hold it: a gold ring for the main hand, a bronze one for the other (drawn
	# again only when a hand moves or the grip changes).
	var g = ForgeLib.grip_points(_design_now())
	var two_h: bool = design.get("twoHanded", false)
	var rk := "%s|%s|%s" % [str(g.main) if g != null else "-", str(g.off) if g != null else "-", str(two_h)]
	if rk != ring_key or ring_nodes.any(func(n): return not is_instance_valid(n)):
		ring_key = rk
		for n in ring_nodes:
			if is_instance_valid(n):
				n.queue_free()
		ring_nodes = []
	if g != null and ring_nodes.is_empty():
		var hands := [[g.main, UIStyle.GOLD]]
		if two_h:
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
			ring_nodes.append(ring)
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
			ring_nodes.append(tag)
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
	# What was picked and is gone (taken off, cut away, undone) is not picked any more.
	var picked := sel.size()
	for k in sel.keys():
		if not cells.has(k):
			sel.erase(k)
	_show_sel()
	if sel.size() != picked and tool == "select":
		_toolbar_ui()
	texts_due = true   # (once a frame, however many blocks a stroke put on in it: _process)

## Every block's taper worked out again and drawn (after a change, once the hand has stopped).
func _retaper() -> void:
	taper_t = -1.0
	if vox_mi == null or not is_instance_valid(vox_mi):
		return
	var mm := vox_mi.multimesh
	var jobs := {}
	var faces := {}
	for k in cells:
		jobs[k] = str(cells[k][1])
		if _face(k) >= 0:
			faces[k] = _face(k)
	var memo := {}
	for k in cells:
		var code := VoxelPart.taper_code(jobs, k, _face(k), faces, memo)
		if int(taper_of.get(k, -1)) != code and inst_of.has(k) and int(inst_of[k]) < mm.instance_count:
			mm.set_instance_custom_data(int(inst_of[k]), VoxelPart.kind_data(VoxelPart.kind_of_material(str(cells[k][0])), 0, code))
		taper_of[k] = code

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

## The smithy stands round the anvil whatever the camera does, and never in its way: a wall, or
## the roof, is put away while the camera is out beyond it (backed far off from a long weapon, it
## looks into the room as into a doll's house), and a thing standing on the floor while the camera
## is in it, or while it stands between the camera and what the camera looks at.
func _decor_update() -> void:
	var lp: Vector3 = cam.global_position - floor_.global_position   # (the room is never turned)
	var lf: Vector3 = focus - floor_.global_position
	for k in room_sides:
		(room_sides[k] as Node3D).visible = not room_side_hidden(k, lp)
	for c in decor:
		var box: AABB = (c as Node3D).get_meta("decor_box")
		(c as Node3D).visible = not (box.grow(0.8).has_point(lp) or box.grow(0.12).intersects_segment(lp, lf) != null)

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

## The walking keys fly the camera over the anvil (FlyCam): W toward what the mouse points at.
var view_mouse := Vector2(-1, -1)   # where the mouse is over the view (-1: off it)
func _walk_camera(dt: float) -> void:
	var aim := cam.project_ray_normal(view_mouse) if cam and view_mouse.x >= 0.0 else Vector3.ZERO
	var mv := FlyCam.step(self, cam, aim, maxf(0.5, dist * 0.9), dt)
	if mv == Vector3.ZERO:
		return
	moved = true
	idle_t = 0.0
	flown += mv.length()
	focus += mv
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
	if texts_due:
		texts_due = false
		_update_texts()
	if rating.get("state", "") == "running":
		rating["t"] = float(rating.get("t", 0.0)) + dt
		if float(rating.t) >= RATE_POLL_S:
			rating["t"] = 0.0
			_rate_poll()
	if sel_mi and is_instance_valid(sel_mi):
		sel_mi.visible = tool == "select"   # (the pick is shown while the tool is in hand)
	if bars and Time.get_ticks_msec() / 1000.0 - stat_t < DELTA_HOLD + 0.7:
		bars.queue_redraw()   # (a change's ▲ / ▼ fading out)
	# The whole weapon's taper once the hand has stopped (only that round each change was
	# worked out while it moved).
	if taper_t > 0.0:
		taper_t -= dt
		if taper_t <= 0.0 and stroke.is_empty():
			_retaper()
		elif taper_t <= 0.0:
			taper_t = 0.05
	idle_t += dt
	# (The fires breathe.)
	var ft := Time.get_ticks_msec() / 1000.0
	for i in fire_lights.size():
		(fire_lights[i][0] as OmniLight3D).light_energy = float(fire_lights[i][1]) * (0.9 + 0.1 * sin(ft * 9.0 + i * 1.7) + 0.05 * sin(ft * 21.0 + i * 0.6))
	_walk_camera(dt)
	if lesson:
		lesson.update(dt)
		_lesson_show()
	if idle_t > 4.0 and not dragging and not moved and swing_t < 0.0:
		orbit.x += dt * 0.25   # left alone, it turns slowly on the anvil
		_place_camera()
	# Swing it: the weapon swept round its grip at the speed it would really swing.
	if swing_t >= 0.0:
		# (What the weapon is, read once at the start of the swing, not every frame of it.)
		if swing_t == 0.0 or swing_st.is_empty():
			var d := _design_now()
			var g0 = ForgeLib.grip_points(d)
			swing_st = {"speed": float(ForgeLib.compute_stats(d).swingSpeed), "pivot": (g0.main if g0 != null else Vector3.ZERO) * Data.weapon_voxel}
		var dur := clampf(6.0 / maxf(1.0, float(swing_st.speed)), 0.25, 1.6)
		swing_t += dt
		var k := minf(1.0, swing_t / dur)
		var pivot: Vector3 = swing_st.pivot
		var ang := -1.6 + 2.8 * (k * k * (3.0 - 2.0 * k))
		var b := Basis(Vector3(1, 0, 0), ang)
		weapon_root.transform = Transform3D(b, pivot - b * pivot)
		if k >= 1.0:
			swing_t = -1.0
			swing_st = {}
			weapon_root.transform = Transform3D.IDENTITY

func _on_view_input(e: InputEvent) -> void:
	idle_t = 0.0
	if e is InputEventMouse:
		view_mouse = e.position
	if e is InputEventMouseButton and e.pressed:
		# A click on the anvil takes the keyboard back from a box typed in (W flies the camera).
		var fo := get_viewport().gui_get_focus_owner()
		if fo:
			fo.release_focus()
	if e is InputEventMouseButton and e.pressed:
		if e.button_index == MOUSE_BUTTON_WHEEL_UP:
			moved = true
			_zoom(e.position, 0.88)
		elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			moved = true
			_zoom(e.position, 1.0 / 0.88)
		elif e.button_index == MOUSE_BUTTON_LEFT and mode == "voxels" and not e.alt_pressed and tool == "select":
			_select_press(e)
		elif e.button_index == MOUSE_BUTTON_LEFT and mode == "voxels" and not e.alt_pressed:
			stroke = {"erase": false, "done": {}, "undo": false}
			_click(e.position)
		elif e.button_index == MOUSE_BUTTON_RIGHT and mode == "voxels" and tool == "line" and line_from != null:
			line_from = null
			_show_line([])
			cost_label.text = TOOL_HINT.line
		elif e.button_index == MOUSE_BUTTON_RIGHT and mode == "voxels" and tool == "select":
			sel_drag = {}
			_select_redraw()
			_set_sel({})
		elif e.button_index == MOUSE_BUTTON_RIGHT and mode == "voxels":
			stroke = {"erase": true, "done": {}, "undo": false}
			_erase_at(e.position)
	if e is InputEventMouseButton and not e.pressed and (e.button_index == MOUSE_BUTTON_LEFT or e.button_index == MOUSE_BUTTON_RIGHT):
		stroke = {}
		if e.button_index == MOUSE_BUTTON_LEFT and not sel_drag.is_empty():
			_select_release()
	# The middle button turns the camera round the weapon; with Shift held it slides it instead.
	# (Alt and the left button do the same: a touchpad has no middle button.)
	if e is InputEventMouseButton and (e.button_index == MOUSE_BUTTON_MIDDLE or (e.button_index == MOUSE_BUTTON_LEFT and (mode == "cards" or e.alt_pressed or (not e.pressed and dragging)))):
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
			if not sel_drag.is_empty():
				_select_drag(e.position)
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
	# The sharp block under the mouse is haloed: it is the one R turns.
	var under = a.get("hit") if not a.is_empty() else null
	turn_ghost.visible = under != null and cells.has(under) and _is_sharp(under)
	if turn_ghost.visible:
		turn_ghost.position = Vector3(under) * Data.weapon_voxel
	if not a.is_empty():
		c = a.get("hit") if tool == "erase" or tool == "hand" or tool == "select" else a.get("place")
	# The line from where it starts to where the mouse is: every block it would put down.
	if tool == "line" and line_from != null and c != null:
		_show_line(_mirrored(ForgeLib.line_path(line_from, c)))
	ghost.visible = c != null and not bool(sel_drag.get("moved", false))
	if c != null:
		ghost.position = Vector3(c) * Data.weapon_voxel
		var col := Color(1, 0.3, 0.3, 0.45) if tool == "erase" else (Color(0.35, 0.8, 1.0) if tool == "select" else Weapon.voxel_color(mat, job))
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
	cost_label.text = Loc.t("The main hand holds it here" if which == "main" else "The other hand holds it here") if two else Loc.t("The hand holds it here")

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

## What R says a sharp block now faces, a whole line for each (ForgeLib.FACE_NAMES' order, then
## "as the shape has it") so that every language can word it its own way.
const FACE_LINES := {
	"edge": ["This edge faces right (R: turn it again)", "This edge faces left (R: turn it again)", "This edge faces up (R: turn it again)", "This edge faces down (R: turn it again)", "This edge faces front (R: turn it again)", "This edge faces back (R: turn it again)", "This edge faces as the weapon's shape has it (R: turn it)"],
	"point": ["This point faces right (R: turn it again)", "This point faces left (R: turn it again)", "This point faces up (R: turn it again)", "This point faces down (R: turn it again)", "This point faces front (R: turn it again)", "This point faces back (R: turn it again)", "This point faces as the weapon's shape has it (R: turn it)"],
}

## Turns the sharp block `k` to face the next way: each of the six in turn, then back to as the
## weapon's shape has it.
func turn_face(k: Vector3i) -> void:
	if not cells.has(k) or not _is_sharp(k):
		cost_label.text = "Only a Cut or a Stab block turns: point at one and press R"
		return
	_push_undo()
	# From the way it faces as drawn (a block of a ready-made weapon has no way set, and R turning it to
	# the way it already faces looked like nothing done).
	var f := _look_face(k) + 1
	if f > 5:
		f = -1
	# The blocks the mirrors make of it turn with it, the mirrored way (as they were put on): a
	# blade turned on one side and left on the other is not what the mirror is for.
	for at in _mirrored([k]):
		if not cells.has(at) or not _is_sharp(at):
			continue
		var fa := f
		if fa >= 0:
			if at.x != k.x and fa < 2:
				fa = 1 - fa
			if at.z != k.z and fa >= 4:
				fa = 9 - fa
		var cc: Array = cells[at].duplicate()
		cc.resize(3)
		cc[2] = fa
		cells[at] = cc
	cost_label.text = Loc.t(FACE_LINES[str(cells[k][1])][f] if f >= 0 else FACE_LINES[str(cells[k][1])][6])
	_rebuild()

## The way the sharp block `k` is drawn facing: the way the smith set, else the one open side the
## weapon's shape has it narrow toward, else -1 (a tip, or a block with no one way).
func _look_face(k: Vector3i) -> int:
	if _face(k) >= 0:
		return _face(k)
	var jobs := {}
	var faces := {}
	for c in cells:
		jobs[c] = str(cells[c][1])
		if _face(c) >= 0:
			faces[c] = _face(c)
	var bits := VoxelPart.taper_code(jobs, k, -1, faces) & 63
	for i in 6:
		if bits == (1 << i):
			return i
	return -1

## An Edge or a Point block: the two that have a way to face.
func _is_sharp(k: Vector3i) -> bool:
	return cells.has(k) and (str(cells[k][1]) == "edge" or str(cells[k][1]) == "point")

const DULL := 0.2           # below it an edge cuts next to nothing
const WORKING_EDGE := 0.6   # what the smith hones a first edge to on a dull weapon

func _set_sharp_slider(v: float) -> void:
	for c in mode_box.get_children():
		if c.has_meta("sharp_row"):
			for k in c.get_children():
				if k is HSlider:
					k.set_value_no_signal(v)

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
		cost_label.text = Loc.t("That is the most the anvil holds (%d voxels)") % ForgeLib.MAX_VOXELS
		return
	# A first edge or point on a weapon honed to nothing (the training stick) would cut nothing:
	# the smith hones it to a working edge at once (the slider still sets it any way after).
	var sharp_new := (job == "edge" or job == "point") and float(design.get("sharpness", 0.8)) < DULL and _sharp_blocks() == 0
	var sh_after := WORKING_EDGE if sharp_new else float(design.get("sharpness", 0.8))
	if not free_build and _value_now() + Arms.voxel_price(mat) * add.size() + roundi(Arms.sharp_cost(job, sh_after) * add.size()) - original_value > purse:
		cost_label.text = "Not enough denarii for that"
		return
	_push_undo()
	if sharp_new:
		design.sharpness = WORKING_EDGE
		_set_sharp_slider(WORKING_EDGE)
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
		cost_label.text = Loc.t("Cut through: %d blocks fall away") % (cells.size() - keep.size())
		cells = kept
	_rebuild()

# ---------- The weapon's rating: duels against standard foes, ranked among the arsenal's ----------

## The rating's place at the foot of what is made on the anvil: a button to rate the weapon, how far the bouts have got, and what they came to.
func _rating_ui() -> void:
	mode_box.add_child(HSeparator.new())
	mode_box.add_child(UIStyle.label("RATING", 13, UIStyle.BRONZE))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	rating_button = UIStyle.button("Rate it", _rate_start)
	rating_button.tooltip_text = Loc.t("Fight it: a bot with this weapon duels standard gladiators (%d bouts, a few minutes) and it is ranked among the arsenal's weapons, which were rated the same way. It goes on in the background: go on forging.") % WeaponRating.battery().size()
	row.add_child(rating_button)
	rating_stop = UIStyle.button("Stop", _rate_stop)
	row.add_child(rating_stop)
	mode_box.add_child(row)
	rating_label = UIStyle.label("", 14, UIStyle.TEXT)
	rating_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mode_box.add_child(rating_label)
	rating_strip = RatingStrip.new()
	rating_strip.custom_minimum_size = Vector2(380, 38)
	mode_box.add_child(rating_strip)
	_rating_refresh()

## What the rating's place says, from what the rating is: nothing yet, under way, made (for this weapon or one it was), or not made.
func _rating_refresh(d: Dictionary = {}, st: Dictionary = {}) -> void:
	if rating_label == null or not is_instance_valid(rating_label) or rating_button == null or not is_instance_valid(rating_button):
		return
	if d.is_empty():
		d = _design_now()
	# A weapon rated before, in this game, comes back to the anvil with its rating.
	if rating.is_empty() and not rated.is_empty() and not (d.voxels as Array).is_empty():
		var seen := WeaponRating.key(d)
		if rated.has(seen):
			rating = (rated[seen] as Dictionary).duplicate(true)
	var state := str(rating.get("state", ""))
	var running := state == "running"
	var why := WeaponRating.unrateable(d, st)
	rating_button.disabled = running or why != ""
	rating_stop.visible = running
	var lines := []
	var res: Dictionary = rating.get("result", {})
	# A rating of the weapon that is on the anvil, or of one it has been changed from.
	var mine := not rating.is_empty() and not d.is_empty() and (d.voxels as Array).size() > 0 and str(rating.get("key", "")) == WeaponRating.key(d)
	var shown := false
	if running:
		lines.append(Loc.t("Rating: bout %d of %d") % [mini(int(rating.get("done", 0)) + 1, int(rating.get("of", 1))), int(rating.get("of", 1))])
	elif state == "failed":
		lines.append(Loc.t("The rating failed: %s") % Loc.t(str(res.get("error", "The rating stopped before it was done"))))
	elif state == "done" and res.get("summary") is Dictionary:
		shown = true
		if not mine:
			lines.append(Loc.t("For the weapon as it was, not as it is now: rate it again"))
		var sm: Dictionary = res.summary
		lines.append(Loc.t("Rated %d out of 100") % roundi(float(sm.score)))
		lines.append(Loc.t("Won %d of %d bouts · dealt %d damage, took %d") % [int(floor(float(sm.won))), int(sm.of), int(sm.dmg), int(sm.taken)])
		var rk: Dictionary = res.get("rank", {})
		if not rk.is_empty():
			lines.append(Loc.t("Better than %d of the arsenal's %d weapons") % [int(rk.better), int(rk.of)])
			if String(rk.below) != "" and String(rk.above) != "":
				lines.append(Loc.t("Between the %s and the %s") % [Loc.t(str(Data.presets.get(String(rk.below), {}).get("name", rk.below))), Loc.t(str(Data.presets.get(String(rk.above), {}).get("name", rk.above)))])
	if lines.is_empty() and why != "":
		lines.append(Loc.t(why))
	rating_label.text = "\n".join(lines)
	rating_label.add_theme_color_override("font_color", UIStyle.GOLD if shown and mine else UIStyle.TEXT)
	var strip := rating_strip as RatingStrip
	if strip:
		strip.arsenal = WeaponRating.scores()
		strip.score = float((res.get("summary", {}) as Dictionary).get("score", -1.0)) if shown else -1.0
		strip.stale = shown and not mine
		strip.visible = shown and not strip.arsenal.is_empty()
		strip.queue_redraw()

## Start the game that fights the bouts: the weapon as it is on the anvil, written to a job file, a headless game (this one's own executable) told to do it, the answer read from a file as it comes.
func _rate_start() -> void:
	if str(rating.get("state", "")) == "running":
		return
	var d := _design_now()
	var why := WeaponRating.unrateable(d)
	if why != "":
		cost_label.text = why
		return
	var dir := ProjectSettings.globalize_path("user://rating")
	DirAccess.make_dir_recursive_absolute(dir)
	var id := "%d_%d" % [OS.get_process_id(), Time.get_ticks_msec()]
	var job_path := dir.path_join("job_%s.json" % id)
	var out_path := dir.path_join("out_%s.json" % id)
	var f := FileAccess.open(job_path, FileAccess.WRITE)
	if f == null:
		cost_label.text = "The rating could not be started"
		return
	f.store_string(JSON.stringify({"design": d, "out": out_path}))
	f.close()
	var args := PackedStringArray(["--headless", "--fixed-fps", "120"])
	if OS.has_feature("editor"):
		args.append_array(["--path", ProjectSettings.globalize_path("res://")])   # (a game run from the editor's own program has to be told where it is)
	args.append_array(["--", "--rate", job_path])
	var pid := OS.create_process(OS.get_executable_path(), args)
	if pid <= 0:
		DirAccess.remove_absolute(job_path)
		cost_label.text = "The rating could not be started"
		return
	rating = {"key": WeaponRating.key(d), "pid": pid, "job": job_path, "out": out_path, "state": "running", "done": 0, "of": WeaponRating.battery().size(), "t": 0.0, "result": {}}
	_rating_refresh(d)

## The rating given up on (the button, or the forge closing): the game that fights it is ended and its files go.
func _rate_stop() -> void:
	if str(rating.get("state", "")) != "running":
		return
	if int(rating.get("pid", 0)) > 0 and _rate_running(int(rating.pid)):
		OS.kill(int(rating.pid))
	_rate_files_away()
	rating = {}
	_rating_refresh()

## How far the bouts have got, from the file the other game writes; done, failed, or gone without a word.
func _rate_poll() -> void:
	var res := {}
	var out_path := str(rating.get("out", ""))
	if out_path != "" and FileAccess.file_exists(out_path):
		res = WeaponRating.clean_result(JSON.parse_string(FileAccess.get_file_as_string(out_path)))
	if res.get("state", "") == "done" or res.get("state", "") == "failed":
		_rate_finish(res)
	elif not _rate_running(int(rating.get("pid", 0))):
		# (It may have written its last words between the two looks.)
		if out_path != "" and FileAccess.file_exists(out_path):
			var last := WeaponRating.clean_result(JSON.parse_string(FileAccess.get_file_as_string(out_path)))
			if last.state == "done" or last.state == "failed":
				_rate_finish(last)
				return
		_rate_finish({"state": "failed", "error": "The rating stopped before it was done", "bouts": []})
	else:
		if not res.is_empty():
			rating["done"] = int(res.done)
			rating["of"] = maxi(int(res.of), int(rating.get("of", 0)))
		_rating_refresh()

func _rate_finish(res: Dictionary) -> void:
	rating["state"] = str(res.get("state", "failed"))
	rating["result"] = res
	rating["done"] = int(res.get("done", 0))
	_rate_files_away()
	if rating.state == "done":
		rated[str(rating.key)] = rating.duplicate(true)
	_rating_refresh()

func _rate_running(pid: int) -> bool:
	if rate_alive.is_valid():
		return bool(rate_alive.call(pid))
	return pid > 0 and OS.is_process_running(pid)

func _rate_files_away() -> void:
	for k in ["job", "out"]:
		var p := str(rating.get(k, ""))
		if p != "" and FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)

## The arsenal's scores as ticks on a line, 0 to 100, and the weapon's own as a gold mark under it.
class RatingStrip extends Control:
	var arsenal: Array = []
	var score := -1.0
	var stale := false

	func _draw() -> void:
		if arsenal.is_empty() or score < 0.0:
			return
		var font := UIStyle.serif(1)
		var w := size.x - 2.0
		var y0 := 4.0
		draw_rect(Rect2(1, y0, w, 12), Color(0, 0, 0, 0.5))
		for sc in arsenal:
			var x := 1.0 + w * clampf(float(sc) / 100.0, 0.0, 1.0)
			draw_rect(Rect2(x - 0.5, y0 + 1, 1.5, 10), Color(UIStyle.MUTED, 0.75))
		var x := 1.0 + w * clampf(score / 100.0, 0.0, 1.0)
		var c := UIStyle.MUTED if stale else UIStyle.GOLD
		draw_rect(Rect2(x - 1.5, y0 - 3, 3, 18), c)
		draw_colored_polygon(PackedVector2Array([Vector2(x, y0 + 16), Vector2(x - 5, y0 + 23), Vector2(x + 5, y0 + 23)]), c)
		var t := "%d" % roundi(score)
		var tw := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		draw_string(font, Vector2(clampf(x - tw * 0.5, 0.0, size.x - tw), y0 + 36), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, c)

# ---------- Picked blocks: the Select tool ----------

## What the Select tool's buttons do: the six ways to move (the arrow drawn on its button, a step, a tip), the three quarter turns (a label, the axis, a tip), the three flips.
const MOVES := [
	["left", Vector3i(-1, 0, 0), "Move the picked blocks left  [←]"],
	["right", Vector3i(1, 0, 0), "Move the picked blocks right  [→]"],
	["up", Vector3i(0, 1, 0), "Move the picked blocks up  [↑]"],
	["down", Vector3i(0, -1, 0), "Move the picked blocks down  [↓]"],
	["front", Vector3i(0, 0, 1), "Move the picked blocks to the front  [Page Down]"],
	["back", Vector3i(0, 0, -1), "Move the picked blocks to the back  [Page Up]"],
]
const TURNS := [
	["Turn ↻", 2, "Turn the picked blocks a quarter, like a clock hand (Shift: the other way)"],
	["Roll", 1, "Roll the picked blocks a quarter round the weapon's length (Shift: the other way)"],
	["Tilt", 0, "Tilt the picked blocks a quarter toward you or away (Shift: the other way)"],
]
const FLIPS := [
	["Flip ⟷", 0, "Flip the picked blocks left for right"],
	["Flip ⇕", 1, "Flip the picked blocks upside down"],
	["Flip ⇅", 2, "Flip the picked blocks front for back"],
]
const MOVE_FAST := 5   # blocks a step with Shift held

## The Select tool's row under the tools: with nothing picked, only the way to pick everything; with blocks picked, what can be done with them (Copy and the six moves, then Turn, Flip and Change, each a short list).
func _select_row() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	if sel.is_empty():
		row.add_child(UIStyle.button("Select all", _sel_all))
		return row
	row.add_child(UIStyle.button("Select none", func(): _set_sel({})))
	row.add_child(VSeparator.new())
	var cp := CheckBox.new()
	cp.text = "Copy"
	cp.tooltip_text = "Leave the picked blocks where they are: the next move carries a copy of them"
	cp.button_pressed = sel_copy
	cp.toggled.connect(func(x): sel_copy = x)
	row.add_child(cp)
	var pad := HBoxContainer.new()
	pad.add_theme_constant_override("separation", 2)
	for mv in MOVES:
		var step: Vector3i = mv[1]
		var b := _icon_button(String(mv[0]), func(): _sel_move(step))
		b.tooltip_text = Loc.t(mv[2]) + "\n" + Loc.t("Shift: five blocks at a time")
		b.set_meta("move", step)
		pad.add_child(b)
	row.add_child(pad)
	row.add_child(VSeparator.new())
	var turn := _pull_menu("Turn", "Turn the picked blocks a quarter (Shift: the other way)", TURNS.map(func(tn): return tn[0]), func(id): _sel_turn(int(TURNS[id][1]), -1 if Input.is_key_pressed(KEY_SHIFT) else 1))
	var flip := _pull_menu("Flip", "Flip the picked blocks over: left for right, upside down or front for back", FLIPS.map(func(fl): return fl[0]), func(id): _sel_flip(int(FLIPS[id][1])))
	var change := _pull_menu("Change", "Remake the picked blocks: of the material picked on the left, or with the job picked there",
		[Loc.t("Make them %s") % Loc.t(mat.capitalize()), Loc.t("Make them %s") % Loc.t(_job_name(job))], _make_pick)
	for i in TURNS.size():
		turn.get_popup().set_item_tooltip(i, TURNS[i][2])
	for i in FLIPS.size():
		flip.get_popup().set_item_tooltip(i, FLIPS[i][2])
	change.get_popup().set_item_tooltip(0, Loc.t("Every picked block becomes %s, the material picked on the left") % Loc.t(mat.capitalize()))
	change.get_popup().set_item_tooltip(1, Loc.t("Every picked block gets the job %s, the one picked on the left") % Loc.t(_job_name(job)))
	for m in [turn, flip, change]:
		row.add_child(m)
	for c in row.get_children():
		if c is Button:
			(c as Button).focus_mode = Control.FOCUS_NONE
	return row

## Change, the line chosen: the picked blocks made of the material picked on the left, or given the job picked there.
func _make_pick(id: int) -> void:
	if id == 0:
		_sel_make(mat, "")
	else:
		_sel_make("", job)

## The blocks to pick, put together with what is picked: added (Shift), taken away from it (Ctrl), or instead of it.
func _pick_with(picked: Dictionary, add: bool, sub: bool) -> Dictionary:
	var out := {}
	if add or sub:
		out = sel.duplicate()
	for k in picked:
		if sub:
			out.erase(k)
		else:
			out[k] = true
	return out

func _set_sel(s: Dictionary) -> void:
	sel = s
	_show_sel()
	if tool != "select":
		return
	_toolbar_ui()
	if sel.is_empty():
		cost_label.text = TOOL_HINT.select
	else:
		cost_label.text = Loc.t("%d block picked" if sel.size() == 1 else "%d blocks picked") % sel.size()

func _sel_all() -> void:
	var all := {}
	for k in cells:
		all[k] = true
	_set_sel(all)

## The pick tinted on the weapon (a box a little over each block).
func _show_sel() -> void:
	if weapon_root == null:
		return
	if sel_mi == null or not is_instance_valid(sel_mi):
		var bm := BoxMesh.new()
		bm.size = Vector3.ONE * Data.weapon_voxel * 1.06
		var m := StandardMaterial3D.new()
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(0.35, 0.8, 1.0, 0.4)
		bm.material = m
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = bm
		sel_mi = MultiMeshInstance3D.new()
		sel_mi.multimesh = mm
		weapon_root.add_child(sel_mi)
	sel_mi.visible = tool == "select"
	var mm2 := sel_mi.multimesh
	mm2.instance_count = sel.size()
	var i := 0
	for k in sel:
		mm2.set_instance_transform(i, Transform3D(Basis(), Vector3(k) * Data.weapon_voxel))
		i += 1

## A press with the Select tool: a double-click picks the part under the mouse; otherwise a box begins (a click that goes nowhere picks the block under it, or lets go of the pick).
func _select_press(e: InputEventMouseButton) -> void:
	var add := e.shift_pressed
	var sub := e.ctrl_pressed or e.meta_pressed
	if e.double_click:
		var a := _aim(e.position)
		if not a.is_empty() and a.get("hit") != null:
			_set_sel(_pick_with(ForgeLib.part_of(cells, a.hit), add, sub))
			sel_drag = {"done": true}
			return
	sel_drag = {"from": e.position, "to": e.position, "moved": false, "add": add, "sub": sub}

func _select_drag(at: Vector2) -> void:
	if sel_drag.get("done", false) or not sel_drag.has("from"):
		return
	sel_drag["to"] = at
	if not sel_drag.moved and at.distance_to(sel_drag.from) > 5.0:
		sel_drag["moved"] = true
		ghost.visible = false
	_select_redraw()

func _select_release() -> void:
	var d := sel_drag
	sel_drag = {}
	_select_redraw()
	if d.is_empty() or d.get("done", false):
		return
	var picked := {}
	if d.moved:
		picked = _blocks_in_rect(Rect2(d.from, d.to - d.from).abs())
	else:
		var a := _aim(d.from)
		if not a.is_empty() and a.get("hit") != null:
			picked[a.hit] = true
	_set_sel(_pick_with(picked, d.add, d.sub))

func _select_redraw() -> void:
	if marquee and is_instance_valid(marquee):
		marquee.queue_redraw()

func _draw_marquee() -> void:
	if not bool(sel_drag.get("moved", false)):
		return
	var r := Rect2(sel_drag.from, sel_drag.to - sel_drag.from).abs()
	marquee.draw_rect(r, Color(0.35, 0.8, 1.0, 0.12))
	marquee.draw_rect(r, Color(0.55, 0.85, 1.0, 0.9), false, 1.5)

## The blocks whose middles lie inside the rectangle `r` of the view: every one of them, the ones behind others too.
func _blocks_in_rect(r: Rect2) -> Dictionary:
	var out := {}
	if cam == null or weapon_root == null:
		return out
	for k in cells:
		var w: Vector3 = weapon_root.to_global(Vector3(k) * Data.weapon_voxel)
		if not cam.is_position_behind(w) and r.has_point(cam.unproject_position(w)):
			out[k] = true
	return out

## What it costs to have `cs` as the weapon, honed at `sh` (the weapon's own price, as the smith counts it).
func _value_of(cs: Dictionary, sh: float) -> int:
	var s := 0
	var jobs := []
	for c in cs.values():
		s += Arms.voxel_price(c[0])
		jobs.append(String(c[1]))
	return s + Arms.honing(jobs, clampf(sh, 0.0, 1.0))

## The weapon `want` put on the anvil in place of the one there, as one step to undo, if it holds up (nothing off the grid, one piece, within the purse). The pick becomes `now`, the hands
## go where `hands` says (null: as they are), `extra` is set on the design with it. False (and a word under the anvil) when it would not hold.
func _commit_cells(want: Dictionary, now: Dictionary, hands = null, copy := false, extra := {}) -> bool:
	var why := ForgeLib.fault(want)
	if why == "pieces":
		cost_label.text = "A new block must touch the weapon" if copy else "That would tear the weapon in two"
		return false
	if why == "grid":
		cost_label.text = "That will not fit on the anvil"
		return false
	if why == "many":
		cost_label.text = Loc.t("That is the most the anvil holds (%d voxels)") % ForgeLib.MAX_VOXELS
		return false
	if not free_build:
		var sh := float(extra.get("sharpness", design.get("sharpness", 0.8)))
		var v := _value_of(want, sh)
		if v > _value_now() and v - original_value > purse:
			cost_label.text = "Not enough denarii for that"
			return false
	_push_undo()
	cells = want
	sel = now
	if hands != null:
		design.grips = hands
	for k in extra:
		design[k] = extra[k]
	_rebuild()
	if tool == "select":
		_toolbar_ui()
	return true

## Where the hands are once the picked blocks have gone through `op`: a hand that was on one goes with it (a copy leaves it where it was). Null when no hand moves.
func _carry_hands(op: Dictionary, keep: bool):
	var gs = design.get("grips")
	if keep or not (gs is Dictionary) or not gs.has("main") or not gs.has("off"):
		return null
	var out := {}
	var any := false
	for h in ["main", "off"]:
		var p := Vector3i(roundi(float(gs[h][0])), roundi(float(gs[h][1])), roundi(float(gs[h][2])))
		if sel.has(p):
			var q := ForgeLib.moved(op, p)
			out[h] = [q.x, q.y, q.z]
			any = true
		else:
			out[h] = gs[h]
	return out if any else null

## Move the pick a step (MOVE_FAST with Shift held); with Copy ticked, the original stays and the copy goes (the tick is spent).
func _sel_move(by: Vector3i) -> void:
	if sel.is_empty():
		return
	var op := ForgeLib.shift_op(by * (MOVE_FAST if Input.is_key_pressed(KEY_SHIFT) else 1))
	var keep := sel_copy
	var r := ForgeLib.carry(cells, sel, op, keep)
	if _commit_cells(r.cells, r.sel, _carry_hands(op, keep), keep) and keep:
		sel_copy = false
		_toolbar_ui()

## Turn the pick a quarter about the axis (0 x, 1 y, 2 z) through the middle of its box.
func _sel_turn(axis: int, dir := 1) -> void:
	if sel.is_empty():
		return
	var op := ForgeLib.turn_op(sel, axis, dir)
	var r := ForgeLib.carry(cells, sel, op)
	_commit_cells(r.cells, r.sel, _carry_hands(op, false))

## Flip the pick over across the middle of its box (axis 0 left for right, 1 upside down, 2 front for back).
func _sel_flip(axis: int) -> void:
	if sel.is_empty():
		return
	var op := ForgeLib.flip_op(sel, axis)
	var r := ForgeLib.carry(cells, sel, op)
	_commit_cells(r.cells, r.sel, _carry_hands(op, false))

## The pick made of `m` and/or doing `j` ("" leaves it): the first edge on a weapon honed to nothing is honed to a working one, as when it is built.
func _sel_make(m: String, j: String) -> void:
	if sel.is_empty():
		return
	var want := ForgeLib.remade(cells, sel, m, j)
	var extra := {}
	if (j == "edge" or j == "point") and float(design.get("sharpness", 0.8)) < DULL and _sharp_blocks() == 0:
		extra["sharpness"] = WORKING_EDGE
	if _commit_cells(want, sel.duplicate(), null, false, extra) and extra.has("sharpness"):
		_set_sharp_slider(WORKING_EDGE)

## The arrow keys and Page Up and Down nudge the pick while the mouse is over the anvil (the buttons are the same, for the mouse); Ctrl+A picks everything.
func _input(e: InputEvent) -> void:
	var k := e as InputEventKey
	if k == null or not k.pressed or k.echo or viewport == null or mode != "voxels" or tool != "select" or view_mouse.x < 0.0 or not visible:
		return
	if k.ctrl_pressed or k.alt_pressed or not FlyCam.keys_free(self):
		return
	var by := Vector3i.ZERO
	match k.keycode:
		KEY_LEFT: by = Vector3i(-1, 0, 0)
		KEY_RIGHT: by = Vector3i(1, 0, 0)
		KEY_UP: by = Vector3i(0, 1, 0)
		KEY_DOWN: by = Vector3i(0, -1, 0)
		KEY_PAGEDOWN: by = Vector3i(0, 0, 1)
		KEY_PAGEUP: by = Vector3i(0, 0, -1)
	if by != Vector3i.ZERO:
		get_viewport().set_input_as_handled()
		_sel_move(by)

func _push_undo() -> void:
	if not stroke.is_empty():
		if stroke.undo:
			return
		stroke.undo = true
	undo_stack.append([cells.duplicate(true), design.duplicate(true), sel.duplicate()])
	if undo_stack.size() > 80:
		undo_stack.pop_front()
	redo_stack.clear()
	_history_buttons()

## Undo and Redo dim while there is nothing to take back or put back.
func _history_buttons() -> void:
	if undo_button and is_instance_valid(undo_button):
		undo_button.disabled = undo_stack.is_empty()
	if redo_button and is_instance_valid(redo_button):
		redo_button.disabled = redo_stack.is_empty()

func _undo() -> void:
	if undo_stack.is_empty():
		return
	redo_stack.append([cells.duplicate(true), design.duplicate(true), sel.duplicate()])
	var s: Array = undo_stack.pop_back()
	cells = s[0]
	design = s[1]
	sel = s[2] if s.size() > 2 else {}
	_rebuild()
	if tool == "select":
		_toolbar_ui()
	_history_buttons()

func _redo() -> void:
	if redo_stack.is_empty():
		return
	undo_stack.append([cells.duplicate(true), design.duplicate(true), sel.duplicate()])
	var s: Array = redo_stack.pop_back()
	cells = s[0]
	design = s[1]
	sel = s[2] if s.size() > 2 else {}
	_rebuild()
	if tool == "select":
		_toolbar_ui()
	_history_buttons()

func _unhandled_key_input(e: InputEvent) -> void:
	var k := e as InputEventKey
	if k and k.pressed and not k.echo and not k.ctrl_pressed and not k.alt_pressed and viewport and mode == "voxels" and _shortcut(k):
		get_viewport().set_input_as_handled()
		return
	if e is InputEventKey and e.pressed and not e.ctrl_pressed and _is_key(e, KEY_F) and viewport:
		_frame()   # the whole weapon back in view
	elif e is InputEventKey and e.pressed and not e.ctrl_pressed and _is_key(e, KEY_R) and viewport and mode == "voxels" and hover_at != null:
		var a := _aim(hover_at)
		if not a.is_empty() and a.get("hit") != null:
			turn_face(a.hit)
	elif e is InputEventKey and e.pressed and e.ctrl_pressed and e.keycode == KEY_A and viewport and mode == "voxels" and tool == "select":
		_sel_all()
	elif e is InputEventKey and e.pressed and e.ctrl_pressed and e.keycode == KEY_Y:
		_redo()
	elif e is InputEventKey and e.pressed and e.ctrl_pressed and e.keycode == KEY_Z:
		if e.shift_pressed:
			_redo()
		else:
			_undo()

## Is this the key `code`: by what it says, or by where it is (a Hebrew or Russian layout says
## another letter there, and the other keys at the anvil already go by their place).
static func _is_key(k: InputEventKey, code: Key) -> bool:
	return k.keycode == code or k.physical_keycode == code

## A key at the anvil (TOOL_KEYS, JOB_KEYS, M and N for the mirrors, Q to take up a block's
## material and job): true if it did something.
func _shortcut(k: InputEventKey) -> bool:
	var code := k.physical_keycode if k.physical_keycode != KEY_NONE else k.keycode
	if TOOL_KEYS.has(code):
		tool = TOOL_KEYS[code]
		hand_pick = ""
		line_from = null
		_show_line([])
		_toolbar_ui()
		cost_label.text = TOOL_HINT.get(tool, "")
		return true
	if JOB_KEYS.has(code):
		job = JOB_KEYS[code]
		if (job == "edge" or job == "point") and float(Data.material(mat).get("hardness", 0.5)) < KEEN:
			mat = "steel"
		if tool == "erase":
			tool = "build"
		_show_mode("voxels")
		cost_label.text = Loc.t("Next blocks: %s, %s") % [Loc.t(_job_name(job)), Loc.t(mat.capitalize())]
		return true
	if code == KEY_M:
		if k.shift_pressed:
			mirror_z = not mirror_z
		else:
			mirror = not mirror
		_toolbar_ui()
		cost_label.text = Loc.t("Mirror ⟷ %s, mirror ⇅ %s") % [Loc.t("On") if mirror else Loc.t("Off"), Loc.t("On") if mirror_z else Loc.t("Off")]
		return true
	if code == KEY_Q and hover_at != null:
		var a := _aim(hover_at)
		if not a.is_empty() and a.get("hit") != null and cells.has(a.hit):
			mat = str(cells[a.hit][0])
			job = str(cells[a.hit][1])
			tool = "build"
			_show_mode("voxels")
			cost_label.text = Loc.t("Taken up: %s, %s (the next blocks are made of it)") % [_job_name(job), mat.capitalize()]
			return true
	return false

func _job_name(j: String) -> String:
	for jp in JOB_PICK:
		if jp[0] == j:
			return String(jp[1])
	return j

func _take() -> void:
	var d := _design_now()
	var st := ForgeLib.compute_stats(d)
	if not st.hasGrip:
		cost_label.text = "It needs somewhere to be held: build a Grip block, or Move hand"
		return
	d.stats = st
	var cost := 0 if free_build else _value_now() - original_value
	if not (workshop or scratch or free_build) and cost > purse:
		cost_label.text = "Not enough denarii for that (a keener edge costs more)"
		return
	done.call(d, cost)

## Closed: the music goes back to what played before the forge.
func _exit_tree() -> void:
	_rate_stop()
	if Sfx.music:
		Sfx.music.bench(false)
