class_name ArmourForge
extends Control
## The armourer's bench, plate by plate: the body part in the round, and the plates put on it
## one voxel at a time as a weapon is built at the forge (left click puts a plate on the face it
## points at, right click takes one off, held down and dragged it goes on doing it). A pair of
## limbs is plated alike. Its stuff sets how well it keeps a blow out and what it weighs; the
## weight drains the breath and slows the pace (Armory.burden).

const CELL := 0.07                 # a plate on the bench (m)
const TURN := 0.6

var def: Dictionary                # {name, mat, parts: {part: [[x, y, z], ...]}}
var region := "torso"
var worn_kg := 0.0                 # what else he wears, for the burden
var purse := -1                    # the denarii to hand (-1: no buying, only designing)
var done: Callable                 # done.call(def) when it is made, done.call(null) to leave

var cells := {}                    # Vector3i -> true: the plates on the first part of the region
var dims := Vector3i(4, 4, 4)
var undo: Array = []
var mirror := true                 # left and right of the part alike
var mirror_z := false              # front and back alike
var paint := -1                    # the paint on the plates put on next (-1: the bare stuff); a click on a plate paints it
## The bench's paints: a plate in any of these over the stuff it is made of (0xRRGGBB).
const PAINTS := [["Red", 0x9b1c1c], ["Blue", 0x1f3f8f], ["Gold", 0xd4a640], ["White", 0xe8e2d4], ["Black", 0x1a1816], ["Green", 0x2f6b2e], ["Purple", 0x5b2a73], ["Bronze", 0xa5702b]]
var vp: SubViewport
var cam: Camera3D
var root: Node3D
var ghost: MeshInstance3D
var orbit := Vector2(0.5, 0.25)
var dist := 1.4
var focus := Vector3.ZERO           # what the camera looks at: between the part and the man's middle
var dragging := false
var stroke := {}
var info: VBoxContainer
var name_edit: LineEdit

## Opens the bench for `d` (Armory.design_piece's shape) on `reg` (Armory.REGIONS).
func open(d: Dictionary, reg: String, cb: Callable, kg_worn := 0.0, coins := -1) -> void:
	add_to_group("bench")   # (the HUD keeps off it)
	def = d.duplicate(true)
	region = reg if Armory.REGIONS.has(reg) else "torso"
	done = cb
	worn_kg = kg_worn
	purse = coins
	var first: String = Armory.REGIONS[region].parts[0]
	var dd := Armory._dims(first)
	dims = Vector3i(int(dd[0]), int(dd[1]), int(dd[2]))
	cells.clear()
	for c in def.get("parts", {}).get(first, []):
		cells[Vector3i(int(c[0]), int(c[1]), int(c[2]))] = int(c[3]) if c.size() > 3 else -1
	if not Armory.BENCH_MATS.has(String(def.get("mat", ""))):
		def.mat = "iron"
	_build_ui()
	_rebuild()

## Another part of the body on the bench: its own plates, from nothing (the stuff and the name
## kept).
func switch_region(reg: String) -> void:
	if reg == region or not Armory.REGIONS.has(reg):
		return
	var d := def.duplicate(true)
	d.parts = {}
	# A name of the player's own stays; the bench's own ("Iron body") follows the part.
	var typed := name_edit.text.strip_edges() if name_edit else ""
	d.name = typed if typed != "" and typed != String(def.get("name", "")) else String(Armory.design_piece(reg, String(d.get("mat", "iron")), 0.0, 1.0, false, true, "").name)
	undo.clear()
	for c in get_children():
		remove_child(c)
		c.queue_free()
	open(d, reg, done, worn_kg, purse)

## The piece as it stands: the plates of the first part, and the same mirrored on its pair.
func design_now() -> Dictionary:
	var out := def.duplicate(true)
	var parts := {}
	var names: Array = Armory.REGIONS[region].parts
	var list := []
	for c in cells:
		list.append([c.x, c.y, c.z] if int(cells[c]) < 0 else [c.x, c.y, c.z, int(cells[c])])
	parts[names[0]] = list
	if names.size() > 1:
		var other := []
		for c in cells:
			other.append([dims.x - 1 - c.x, c.y, c.z] if int(cells[c]) < 0 else [dims.x - 1 - c.x, c.y, c.z, int(cells[c])])
		parts[names[1]] = other
	out.parts = parts
	if name_edit and name_edit.text.strip_edges() != "":
		out.name = name_edit.text.strip_edges().substr(0, 24)
	return out

## A plate may sit on the outside of the part only: round it, on top, or a crest above that.
func can_hold(c: Vector3i) -> bool:
	var o := Armory.DESIGN_OUT
	if c.x < -o or c.x >= dims.x + o or c.y < -o or c.y >= dims.y + o or c.z < -o or c.z >= dims.z + o:
		return false
	return not _inside(c)

func _inside(c: Vector3i) -> bool:
	return c.x >= 0 and c.x < dims.x and c.y >= 0 and c.y < dims.y and c.z >= 0 and c.z < dims.z

## Held on: touching the part or a plate already on (no plate hangs in the air).
func _held(c: Vector3i) -> bool:
	for d in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
		if _inside(c + d) or cells.has(c + d):
			return true
	return false

func _mirrored(c: Vector3i) -> Array:
	var out := [c]
	var more := []
	if mirror:
		more.append(Vector3i(dims.x - 1 - c.x, c.y, c.z))
	if mirror_z:
		more.append(Vector3i(c.x, c.y, dims.z - 1 - c.z))
	if mirror and mirror_z:
		more.append(Vector3i(dims.x - 1 - c.x, c.y, dims.z - 1 - c.z))
	for m in more:
		if not out.has(m):
			out.append(m)
	return out

func _cells_total() -> int:
	return cells.size() * Armory.REGIONS[region].parts.size()

func add_plate(c: Vector3i) -> bool:
	var put := false
	for m in _mirrored(c):
		if not cells.has(m) and can_hold(m) and _held(m) and _cells_total() < Armory.DESIGN_MAX_CELLS:
			if not put and stroke.get("undo", true):
				_push_undo()
			cells[m] = paint
			put = true
	if put:
		_rebuild()
	return put

## The paint on a plate already on (and its mirror): the colour chosen, or -1 for the bare stuff.
func paint_plate(c: Vector3i, colour: int) -> bool:
	var did := false
	for m in _mirrored(c):
		if cells.has(m) and int(cells[m]) != colour:
			if not did and stroke.get("undo", true):
				_push_undo()
			cells[m] = colour
			did = true
	if did:
		_rebuild()
	return did

func remove_plate(c: Vector3i) -> bool:
	var took := false
	for m in _mirrored(c):
		if cells.has(m):
			if not took and stroke.get("undo", true):
				_push_undo()
			cells.erase(m)
			took = true
	if took:
		_rebuild()
	return took

func _push_undo() -> void:
	undo.append(cells.duplicate())
	if undo.size() > 60:
		undo.pop_front()
	if not stroke.is_empty():
		stroke.undo = false   # one undo for a whole stroke

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
	h.offset_left = 16; h.offset_right = -16; h.offset_top = 16; h.offset_bottom = -16
	h.add_theme_constant_override("separation", 18)
	add_child(h)
	# The part in the round, the tools over it.
	var view := VBoxContainer.new()
	view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	view.add_theme_constant_override("separation", 8)
	h.add_child(view)
	var tools := HFlowContainer.new()
	tools.add_theme_constant_override("h_separation", 6)
	tools.add_theme_constant_override("v_separation", 6)
	view.add_child(tools)
	tools.add_child(UIStyle.button("Undo", func():
		if not undo.is_empty():
			cells = undo.pop_back()
			_rebuild()))
	tools.add_child(UIStyle.button("Clear", func():
		_push_undo()
		cells.clear()
		_rebuild()))
	tools.add_child(UIStyle.button("Cover all round", func():
		_push_undo()
		for c in Armory._wrap([dims.x, dims.y, dims.z], 0, dims.y - 1, "all"):
			if _cells_total() < Armory.DESIGN_MAX_CELLS:
				cells[Vector3i(c[0], c[1], c[2])] = paint
		_rebuild()))
	var mx := CheckBox.new()
	mx.text = "Mirror ⟷"
	mx.button_pressed = mirror
	mx.toggled.connect(func(x): mirror = x)
	tools.add_child(mx)
	var mz := CheckBox.new()
	mz.text = "Mirror ⇅"
	mz.button_pressed = mirror_z
	mz.toggled.connect(func(x): mirror_z = x)
	tools.add_child(mz)
	# The paints: pick one and the plates put on come in it, a click on a plate paints it;
	# "Plain" is the bare stuff again.
	var pots := HFlowContainer.new()
	pots.add_theme_constant_override("h_separation", 4)
	pots.add_theme_constant_override("v_separation", 4)
	var pick := func(colour: int) -> void:
		paint = colour
		for pb in pots.get_children():
			pb.button_pressed = int(pb.get_meta("paint")) == colour
	var plain := UIStyle.button("Plain", func(): pick.call(-1))
	plain.toggle_mode = true
	plain.button_pressed = true
	plain.set_meta("paint", -1)
	pots.add_child(plain)
	for p in PAINTS:
		var colour: int = p[1]
		var pb := Button.new()
		pb.custom_minimum_size = Vector2(30, 30)
		pb.tooltip_text = String(p[0])
		pb.toggle_mode = true
		pb.set_meta("paint", colour)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color.hex((colour << 8) | 0xff)
		sb.set_corner_radius_all(4)
		sb.border_width_bottom = 2
		sb.border_color = Color(0.1, 0.08, 0.06)
		pb.add_theme_stylebox_override("normal", sb)
		var sbp := sb.duplicate()
		sbp.border_color = UIStyle.GOLD
		sbp.set_border_width_all(2)
		pb.add_theme_stylebox_override("pressed", sbp)
		pb.add_theme_stylebox_override("hover", sb)
		pb.pressed.connect(func(): pick.call(colour))
		pots.add_child(pb)
	tools.add_child(pots)
	tools.add_child(UIStyle.button("◀ Turn", func():
		orbit.x -= TURN
		_place_camera()))
	tools.add_child(UIStyle.button("Turn ▶", func():
		orbit.x += TURN
		_place_camera()))
	var svc := SubViewportContainer.new()
	svc.stretch = true
	svc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	svc.custom_minimum_size = Vector2(420, 360)
	svc.gui_input.connect(_on_input)
	view.add_child(svc)
	vp = SubViewport.new()
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	svc.add_child(vp)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.11, 0.085, 0.065)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(1.0, 0.93, 0.82)
	e.ambient_light_energy = 0.7
	env.environment = e
	vp.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.light_energy = 1.4
	sun.rotation = Vector3(-0.8, 0.7, 0)
	vp.add_child(sun)
	var rim := DirectionalLight3D.new()
	rim.light_energy = 0.5
	rim.rotation = Vector3(-0.3, -2.4, 0)
	vp.add_child(rim)
	root = Node3D.new()
	vp.add_child(root)
	ghost = MeshInstance3D.new()
	var gm := BoxMesh.new()
	gm.size = Vector3.ONE * CELL
	var gmat := StandardMaterial3D.new()
	gmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gm.material = gmat
	ghost.mesh = gm
	ghost.visible = false
	vp.add_child(ghost)
	cam = Camera3D.new()
	cam.fov = 38.0
	vp.add_child(cam)
	# Far enough back to see the whole man, the part nearer the middle of the shot.
	focus = _part_origin("torso", Armory.REGIONS[region].parts[0]) * 0.55
	dist = 3.6
	view.add_child(UIStyle.label("Left click: a plate on (in the paint picked; on a plate, it paints it) · right click: off · middle drag or Turn: round him · Shift + middle drag: slide · wheel: nearer · plates may stand out from the body, up and wide (each one weighs)", 12, UIStyle.MUTED))
	# The stuff, the name, and what it comes to.
	var side := VBoxContainer.new()
	side.custom_minimum_size = Vector2(340, 0)
	side.add_theme_constant_override("separation", 8)
	h.add_child(side)
	side.add_child(UIStyle.title("Armourer's bench", 28))
	side.add_child(UIStyle.label("WHERE" + ("  (both sides alike)" if Armory.REGIONS[region].parts.size() > 1 else ""), 13, UIStyle.BRONZE))
	var regs := HFlowContainer.new()
	regs.add_theme_constant_override("h_separation", 6)
	regs.add_theme_constant_override("v_separation", 6)
	for r in Armory.REGIONS:
		var rk: String = r
		var rb := UIStyle.button(String(Armory.REGIONS[rk].label), func(): switch_region(rk))
		rb.toggle_mode = true
		rb.button_pressed = rk == region
		regs.add_child(rb)
	side.add_child(regs)
	side.add_child(UIStyle.label("MATERIAL", 13, UIStyle.BRONZE))
	var mats := HFlowContainer.new()
	mats.add_theme_constant_override("h_separation", 6)
	mats.add_theme_constant_override("v_separation", 6)
	for m in Armory.BENCH_MATS:
		var key: String = m
		var b := UIStyle.button(key.capitalize(), func():
			def.mat = key
			for c in mats.get_children():
				c.button_pressed = c.text == key.capitalize()
			_rebuild())
		b.toggle_mode = true
		b.button_pressed = key == def.mat
		mats.add_child(b)
	side.add_child(mats)
	name_edit = LineEdit.new()
	name_edit.max_length = 24
	name_edit.text = String(def.get("name", ""))
	name_edit.placeholder_text = "Name it"
	side.add_child(name_edit)
	info = VBoxContainer.new()
	info.add_theme_constant_override("separation", 6)
	side.add_child(info)
	var sp := Control.new()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_child(sp)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.add_child(UIStyle.button("Leave the bench", func(): done.call(null)))
	row.add_child(UIStyle.button("Forge and wear" if purse >= 0 else "Keep it", func():
		if cells.is_empty():
			return
		done.call(design_now()), true))
	side.add_child(row)

func _update_info() -> void:
	if info == null:
		return
	for c in info.get_children():
		c.queue_free()
	var d := design_now()
	var mat := String(d.mat)
	var kg := Armory.design_kg(d)
	var with := Armory.burden(worn_kg + kg)
	var prot := float(Data.material(mat).get("hardness", 0.5))
	info.add_child(UIStyle.label("%d plates" % _cells_total(), 15, UIStyle.TEXT))
	info.add_child(UIStyle.label("Protection %d%%" % int(round(prot * 100.0)), 15, UIStyle.TEXT))
	info.add_child(UIStyle.label("Weight %.1f kg  (all you wear: %.1f kg)" % [kg, worn_kg + kg], 15, UIStyle.TEXT))
	info.add_child(UIStyle.label("Breath when running and swinging ×%.2f · pace %d%%" % [float(with.breath), int(round(float(with.pace) * 100.0))], 13, UIStyle.MUTED))
	var price := Armory.design_price(d)
	info.add_child(UIStyle.label(("Made at the smith: %d denarii" % price) + (("  (purse %d)" % purse) if purse >= 0 else ""), 15, UIStyle.GOLD if purse < 0 or price <= purse else UIStyle.RED))

# ---------- The part on the bench ----------

func _pos(c: Vector3) -> Vector3:
	return (c - (Vector3(dims) - Vector3.ONE) * 0.5) * CELL

func _rebuild() -> void:
	# (Gone at once, not at the end of the frame: the old man and the new were drawn together
	# for a frame and fought for the pixels, a flicker on every change of part: user.)
	for c in root.get_children():
		root.remove_child(c)
		c.free()
	var names: Array = Armory.REGIONS[region].parts
	var first: String = names[0]
	# The whole man, in the player's own skin and cloth, the part on the bench where it sits on
	# him: the rest of him a shade darker, so it is plain what is being plated.
	var body := _body_mesh(first)
	root.add_child(body)
	# Which way he faces: FRONT before him (where his face and chest look), BACK behind him,
	# and a gold line down the front of the part.
	var mid := (Vector3(dims) - Vector3.ONE) * 0.5
	for side in [[1.0, "FRONT", UIStyle.GOLD], [-1.0, "BACK", UIStyle.MUTED]]:
		var tag := Label3D.new()
		tag.text = side[1]
		tag.modulate = side[2]
		tag.outline_size = 10
		tag.font_size = 48
		tag.pixel_size = CELL * 0.012
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.no_depth_test = true
		# (before and behind the man's chest, whichever part is on the bench)
		var td: Array = Armory._dims("torso")
		tag.position = _part_origin("torso", names[0]) + Vector3(0, CELL * 2.0, float(side[0]) * (float(td[2]) * 0.5 + Armory.DESIGN_OUT + 2.0) * CELL)
		root.add_child(tag)
	var line := MeshInstance3D.new()
	var lm := BoxMesh.new()
	lm.size = Vector3(CELL * 0.25, CELL * dims.y, CELL * 0.05)
	var lmat := StandardMaterial3D.new()
	lmat.albedo_color = UIStyle.GOLD
	lmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lm.material = lmat
	line.mesh = lm
	line.position = _pos(Vector3(mid.x, mid.y, dims.z - 0.45))
	root.add_child(line)
	# The plates, in the stuff they are made of.
	var pm := BoxMesh.new()
	pm.size = Vector3.ONE * CELL * 0.96
	var pmat := StandardMaterial3D.new()
	var bare := Weapon.voxel_color(String(def.mat), "blunt")
	pmat.vertex_color_use_as_albedo = true   # (each plate its own paint, or the bare stuff)
	pmat.metallic = 0.6 if ["iron", "steel", "bronze", "gold"].has(String(def.mat)) else 0.0
	pmat.roughness = 0.45
	pm.material = pmat
	var pmm := MultiMesh.new()
	pmm.transform_format = MultiMesh.TRANSFORM_3D
	pmm.use_colors = true
	pmm.mesh = pm
	# On the part on the bench and, mirrored, on its pair (design_now).
	var shown := design_now().parts as Dictionary
	var at := []
	var cols := []
	for part in names:
		var dd := Armory._dims(part)
		var pd := Vector3i(int(dd[0]), int(dd[1]), int(dd[2]))
		for c in shown.get(part, []):
			at.append(_part_origin(part, first) + (Vector3(float(c[0]), float(c[1]), float(c[2])) - (Vector3(pd) - Vector3.ONE) * 0.5) * CELL)
			cols.append(Color.hex((int(c[3]) << 8) | 0xff) if c.size() > 3 else bare)
	pmm.instance_count = at.size()
	for i in at.size():
		pmm.set_instance_transform(i, Transform3D(Basis(), at[i]))
		pmm.set_instance_color(i, cols[i])
	var pi := MultiMeshInstance3D.new()
	pi.multimesh = pmm
	root.add_child(pi)
	# For the mouse: a box for every cell of the part and every plate.
	var sb := StaticBody3D.new()
	root.add_child(sb)
	var add_box := func(c: Vector3i, plate: bool) -> void:
		var cs := CollisionShape3D.new()
		var b := BoxShape3D.new()
		b.size = Vector3.ONE * CELL
		cs.shape = b
		cs.position = _pos(Vector3(c))
		cs.set_meta("cell", c)
		cs.set_meta("plate", plate)
		sb.add_child(cs)
	for x in dims.x:
		for y in dims.y:
			for z in dims.z:
				add_box.call(Vector3i(x, y, z), false)
	for c in cells:
		add_box.call(c, true)
	_place_camera()
	_update_info()

## Where `part` sits on the bench, with the part `on` (the one being plated) in the middle.
func _part_origin(part: String, on: String) -> Vector3:
	var a: Array = Data.body_def(part).get("pos", [0, 0, 0])
	var b: Array = Data.body_def(on).get("pos", [0, 0, 0])
	return (Vector3(float(a[0]), float(a[1]), float(a[2])) - Vector3(float(b[0]), float(b[1]), float(b[2]))) * CELL / Data.body_voxel

## The player's gladiator standing round the bench: every part's outer voxels coloured as he
## is in the arena (Fighter.build: skin, cloth, the shading and grain), those not of `on` dimmed.
func _body_mesh(on: String) -> MultiMeshInstance3D:
	var lk: Dictionary = Save.get_value("look", {}) if Save.get_value("look", {}) is Dictionary else {}
	var sk_lin := Color.hex(int(Fighter.SKINS[clampi(int(lk.get("skin", 0)), 0, Fighter.SKINS.size() - 1)]) << 8 | 0xff).srgb_to_linear()
	var cloths: Array = load("res://scripts/ui/menu.gd").CLOTH   # (the player's cloth colours)
	var tm_lin := Color.hex(int(cloths[clampi(int(lk.get("cloth", 0)), 0, cloths.size() - 1)]) << 8 | 0xff).srgb_to_linear()
	var res := float(Data.body_res)
	var at := []
	var cols := []
	for d in Data.body_parts:
		var g: Array = d.grid
		var dd: Array = d.dims
		var origin := _part_origin(String(d.name), on)
		var half := (Vector3(float(dd[0]), float(dd[1]), float(dd[2])) - Vector3.ONE) * 0.5
		var full := {}
		for v in d.voxels:
			full[Vector3i(int(v[0]), int(v[1]), int(v[2]))] = true
		var dim := 1.0 if String(d.name) == on or Armory.REGIONS[region].parts.has(String(d.name)) else 0.62
		for v in d.voxels:
			var k := Vector3i(int(v[0]), int(v[1]), int(v[2]))
			var shut := true
			for n in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
				if not full.has(k + n):
					shut = false
					break
			if shut:
				continue   # (nobody sees the inside: the organs, the bone)
			var c: Color
			var t := int(v[3])
			if t == 1 or t == 2:
				c = ((sk_lin if t == 1 else tm_lin) * float(v[4])).linear_to_srgb()
				var lin := c.srgb_to_linear()
				var sh := Fighter.style_shade(String(d.name), k.x, k.y, k.z, g, t)
				c = Fighter._grain(Color(lin.r * sh, lin.g * sh, lin.b * sh).linear_to_srgb(), String(d.name), k.x, k.y, k.z, t)
				if t == 1 and String(d.name).begins_with("shin") and Fighter._strap(k.x, k.y, k.z, g):
					c = Fighter._grain(Color.hex(0x5c3b22ff), String(d.name), k.x, k.y, k.z, 0)
			else:
				c = Color.hex(int(v[4]) << 8 | 0xff)
			c = Color(c.r * dim, c.g * dim, c.b * dim, 1.0)
			at.append(origin + (Vector3((float(k.x) + 0.5) / res - 0.5, (float(k.y) + 0.5) / res - 0.5, (float(k.z) + 0.5) / res - 0.5) - half) * CELL)
			cols.append(c)
	var fm := BoxMesh.new()
	fm.size = Vector3.ONE * CELL / res * 0.98
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	fm.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = fm
	mm.instance_count = at.size()
	for i in at.size():
		mm.set_instance_transform(i, Transform3D(Basis(), at[i]))
		mm.set_instance_color(i, cols[i])
	var bi := MultiMeshInstance3D.new()
	bi.name = "Body"
	bi.multimesh = mm
	return bi

func _place_camera() -> void:
	if cam == null:
		return
	cam.position = focus + Vector3(cos(orbit.y) * sin(orbit.x), sin(orbit.y), cos(orbit.y) * cos(orbit.x)) * dist
	cam.look_at(focus)

## What the mouse points at: the cell hit (a plate or the part) and the one on its face.
func _aim(at: Vector2) -> Dictionary:
	var from := cam.project_ray_origin(at)
	var dir := cam.project_ray_normal(at)
	var hit := vp.find_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + dir * 20.0))
	if hit.is_empty():
		return {}
	var cs = hit.collider.shape_owner_get_owner(hit.collider.shape_find_owner(hit.shape))
	if cs == null or not cs.has_meta("cell"):
		return {}
	var c: Vector3i = cs.get_meta("cell")
	var n: Vector3 = hit.normal
	return {"hit": c, "plate": cs.get_meta("plate"), "place": c + Vector3i(roundi(n.x), roundi(n.y), roundi(n.z))}

func _on_input(e: InputEvent) -> void:
	if e is InputEventMouseButton:
		if e.pressed and e.button_index == MOUSE_BUTTON_WHEEL_UP:
			dist = maxf(0.3, dist * 0.9)
			_place_camera()
		elif e.pressed and e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			dist = minf(6.0, dist * 1.1)
			_place_camera()
		elif e.button_index == MOUSE_BUTTON_MIDDLE:
			dragging = e.pressed
		elif e.button_index == MOUSE_BUTTON_LEFT or e.button_index == MOUSE_BUTTON_RIGHT:
			if e.pressed:
				stroke = {"erase": e.button_index == MOUSE_BUTTON_RIGHT, "undo": true, "done": {}}
				_use(e.position)
			else:
				stroke = {}
	elif e is InputEventMouseMotion:
		# The middle button turns the camera round him; with Shift held it slides it instead,
		# as at the weapon forge (user: the bench's camera could not be worked like the forge's).
		if dragging and e.shift_pressed:
			var px := 2.0 * dist * tan(deg_to_rad(cam.fov * 0.5)) / maxf(1.0, float(vp.size.y))
			var b := cam.global_transform.basis
			focus += (-b.x * e.relative.x + b.y * e.relative.y) * px
			_place_camera()
		elif dragging:
			orbit.x -= e.relative.x * 0.01
			orbit.y = clampf(orbit.y + e.relative.y * 0.01, -1.4, 1.4)
			_place_camera()
		else:
			_hover(e.position)
			if not stroke.is_empty():
				_use(e.position)

func _use(at: Vector2) -> void:
	var a := _aim(at)
	if a.is_empty():
		return
	if stroke.erase:
		if a.plate and not stroke.done.has(a.hit):
			stroke.done[a.hit] = true
			remove_plate(a.hit)
	elif a.plate and paint >= 0 and int(cells.get(a.hit, -1)) != paint and not stroke.done.has(a.hit):
		# A plate already on, under the brush: it takes the paint.
		stroke.done[a.hit] = true
		paint_plate(a.hit, paint)
	elif not stroke.done.has(a.place) and not stroke.done.has(a.hit):
		stroke.done[a.place] = true
		add_plate(a.place)

func _hover(at: Vector2) -> void:
	var a := _aim(at)
	var c = null
	if not a.is_empty():
		c = a.place if can_hold(a.place) else null
	ghost.visible = c != null
	if c != null:
		ghost.position = _pos(Vector3(c))
		var col := Color.hex((paint << 8) | 0xff) if paint >= 0 else Weapon.voxel_color(String(def.mat), "blunt")
		col.a = 0.5
		(ghost.mesh.material as StandardMaterial3D).albedo_color = col

func _unhandled_key_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and e.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		done.call(null)
