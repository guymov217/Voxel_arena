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
var vp: SubViewport
var cam: Camera3D
var root: Node3D
var ghost: MeshInstance3D
var orbit := Vector2(0.5, 0.25)
var dist := 1.4
var dragging := false
var stroke := {}
var info: VBoxContainer
var name_edit: LineEdit

## Opens the bench for `d` (Armory.design_piece's shape) on `reg` (Armory.REGIONS).
func open(d: Dictionary, reg: String, cb: Callable, kg_worn := 0.0, coins := -1) -> void:
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
		cells[Vector3i(int(c[0]), int(c[1]), int(c[2]))] = true
	if not Armory.BENCH_MATS.has(String(def.get("mat", ""))):
		def.mat = "iron"
	_build_ui()
	_rebuild()

## The piece as it stands: the plates of the first part, and the same mirrored on its pair.
func design_now() -> Dictionary:
	var out := def.duplicate(true)
	var parts := {}
	var names: Array = Armory.REGIONS[region].parts
	var list := []
	for c in cells:
		list.append([c.x, c.y, c.z])
	parts[names[0]] = list
	if names.size() > 1:
		var other := []
		for c in cells:
			other.append([dims.x - 1 - c.x, c.y, c.z])
		parts[names[1]] = other
	out.parts = parts
	if name_edit and name_edit.text.strip_edges() != "":
		out.name = name_edit.text.strip_edges().substr(0, 24)
	return out

## A plate may sit on the outside of the part only: round it, on top, or a crest above that.
func can_hold(c: Vector3i) -> bool:
	if c.x < -1 or c.x > dims.x or c.y < 0 or c.y > dims.y + 1 or c.z < -1 or c.z > dims.z:
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
			cells[m] = true
			put = true
	if put:
		_rebuild()
	return put

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
				cells[Vector3i(c[0], c[1], c[2])] = true
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
	dist = clampf(Vector3(dims).length() * CELL * 2.2, 0.6, 3.0)
	view.add_child(UIStyle.label("Left click: a plate on · right click: off · middle drag or Turn: round it · wheel: nearer", 12, UIStyle.MUTED))
	# The stuff, the name, and what it comes to.
	var side := VBoxContainer.new()
	side.custom_minimum_size = Vector2(340, 0)
	side.add_theme_constant_override("separation", 8)
	h.add_child(side)
	side.add_child(UIStyle.title("Armourer's bench", 28))
	side.add_child(UIStyle.label(String(Armory.REGIONS[region].label).to_upper() + ("  (both sides alike)" if Armory.REGIONS[region].parts.size() > 1 else ""), 14, UIStyle.BRONZE))
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
	for c in root.get_children():
		c.queue_free()
	var first: String = Armory.REGIONS[region].parts[0]
	# The part itself, its own voxels in the flesh.
	var bp: Dictionary = {}
	for p in Data.body_parts:
		if String(p.name) == first:
			bp = p
	var res := float(Data.body_res)
	var fine: Array = bp.get("voxels", [])
	var skin := Color(0.6, 0.42, 0.31)
	var fm := BoxMesh.new()
	fm.size = Vector3.ONE * CELL / res * 0.98
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	fm.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = fm
	mm.instance_count = fine.size()
	for i in fine.size():
		var v: Array = fine[i]
		var at := Vector3((float(v[0]) + 0.5) / res - 0.5, (float(v[1]) + 0.5) / res - 0.5, (float(v[2]) + 0.5) / res - 0.5)
		mm.set_instance_transform(i, Transform3D(Basis(), _pos(at)))
		var col := skin * clampf(float(v[4]), 0.4, 1.2) if int(v[3]) != 0 else Color.hex((int(v[4]) << 8) | 0xff)
		col.a = 1.0
		mm.set_instance_color(i, col)
	var bi := MultiMeshInstance3D.new()
	bi.multimesh = mm
	root.add_child(bi)
	# The plates, in the stuff they are made of.
	var pm := BoxMesh.new()
	pm.size = Vector3.ONE * CELL * 0.96
	var pmat := StandardMaterial3D.new()
	pmat.albedo_color = Weapon.voxel_color(String(def.mat), "blunt")
	pmat.metallic = 0.6 if ["iron", "steel", "bronze", "gold"].has(String(def.mat)) else 0.0
	pmat.roughness = 0.45
	pm.material = pmat
	var pmm := MultiMesh.new()
	pmm.transform_format = MultiMesh.TRANSFORM_3D
	pmm.mesh = pm
	pmm.instance_count = cells.size()
	var i := 0
	for c in cells:
		pmm.set_instance_transform(i, Transform3D(Basis(), _pos(Vector3(c))))
		i += 1
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

func _place_camera() -> void:
	if cam == null:
		return
	cam.position = Vector3(cos(orbit.y) * sin(orbit.x), sin(orbit.y), cos(orbit.y) * cos(orbit.x)) * dist
	cam.look_at(Vector3.ZERO)

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
			dist = minf(4.0, dist * 1.1)
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
		if dragging:
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
		var col := Weapon.voxel_color(String(def.mat), "blunt")
		col.a = 0.5
		(ghost.mesh.material as StandardMaterial3D).albedo_color = col

func _unhandled_key_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and e.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		done.call(null)
