extends Control
## The forge (editor.js, paid mode): the weapon on the anvil, voxel by voxel. Left click adds a
## voxel of the chosen material and job against the face you point at, right click takes one
## off; each added voxel costs its material's price, each taken off refunds it. Take it from
## the smith when you are done.

var design: Dictionary
var original_value := 0
var purse := 0
var done: Callable
var mat := "steel"
var job := "edge"
var viewport: SubViewport
var cam: Camera3D
var weapon_root: Node3D
var anvil: MeshInstance3D
var floor_: MeshInstance3D
var framed := false
var cells := {}                 # Vector3i -> [mat, job]
var orbit := Vector2(0.6, 0.35)
var dist := 1.6
var cost_label: Label
var dragging := false
var free_build := false   # training: nothing costs anything
const MATS := ["steel", "iron", "bronze", "wood", "stone", "bone", "gold", "lead", "leather"]
const JOBS := ["edge", "point", "blunt", "grip"]

func open(d: Dictionary, coins: int, cb: Callable) -> void:
	design = d.duplicate(true)
	purse = coins
	done = cb
	original_value = Arms.value(design)
	for v in design.voxels:
		cells[Vector3i(v[0], v[1], v[2])] = [v[3], v[4]]
	_build_ui()
	_rebuild()

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
	frame.custom_minimum_size = Vector2(360, 0)
	h.add_child(frame)
	var side := VBoxContainer.new()
	side.add_theme_constant_override("separation", 10)
	frame.add_child(side)
	var t := UIStyle.title("THE FORGE", 40)
	t.add_theme_font_override("font", UIStyle.serif(3))
	t.add_theme_color_override("font_color", UIStyle.GOLD)
	side.add_child(t)
	side.add_child(UIStyle.label("Left click: add a voxel against the face you point at. Right click: take one off. Drag with the middle button to turn the weapon, wheel to zoom.", 13, UIStyle.MUTED))
	var m := OptionButton.new()
	for x in MATS:
		m.add_item("%s · %d" % [Data.material(x).get("name", x), Arms.voxel_price(x)])
	m.item_selected.connect(func(i): mat = MATS[i])
	side.add_child(UIStyle.label("Material", 14, UIStyle.MUTED))
	side.add_child(m)
	var j := OptionButton.new()
	for x in JOBS:
		j.add_item(x.capitalize())
	j.item_selected.connect(func(i): job = JOBS[i])
	side.add_child(UIStyle.label("Job", 14, UIStyle.MUTED))
	side.add_child(j)
	cost_label = UIStyle.label("", 16, UIStyle.BRONZE)
	side.add_child(cost_label)
	side.add_child(UIStyle.button("Pay and take it", _take, true))
	side.add_child(UIStyle.button("Leave it as it was", func(): done.call(null, 0)))
	var svc := SubViewportContainer.new()
	svc.stretch = true
	svc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	svc.gui_input.connect(_on_view_input)
	h.add_child(svc)
	viewport = SubViewport.new()
	viewport.own_world_3d = true
	svc.add_child(viewport)
	viewport.msaa_3d = Viewport.MSAA_4X
	# A smithy at night: a dark room, the forge's orange glow from one side, a cool rim light
	# from behind, and the weapon standing over a stone anvil.
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

func _value_now() -> int:
	var s := 0
	for c in cells.values():
		s += Arms.voxel_price(c[0])
	return s

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
	# The first time: back off just enough to see the whole weapon.
	if not framed and cells.size():
		framed = true
		var ext := 0.0
		for k in cells:
			ext = maxf(ext, (Vector3(k) * vs - centre).length())
		dist = clampf(ext * 1.75 + 0.12, 0.35, 3.0)
	_place_camera()
	var delta := _value_now() - original_value
	cost_label.text = ("Cost: %d denarii" % delta) if delta >= 0 else ("Refund: %d denarii" % -delta)
	cost_label.text += "  (purse %d) · %d voxels" % [purse, cells.size()]
	if free_build:
		cost_label.text = "%d voxels" % cells.size()

func _place_camera() -> void:
	var c: Vector3 = weapon_root.get_meta("centre", Vector3.ZERO)
	cam.global_position = c + Vector3(cos(orbit.y) * sin(orbit.x), sin(orbit.y), cos(orbit.y) * cos(orbit.x)) * dist
	cam.look_at(c)

func _on_view_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed:
		if e.button_index == MOUSE_BUTTON_WHEEL_UP:
			dist = maxf(0.4, dist * 0.9); _place_camera()
		elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			dist = minf(5.0, dist * 1.1); _place_camera()
		elif e.button_index == MOUSE_BUTTON_LEFT or e.button_index == MOUSE_BUTTON_RIGHT:
			_click(e.position, e.button_index == MOUSE_BUTTON_LEFT)
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_MIDDLE:
		dragging = e.pressed
	if e is InputEventMouseMotion and dragging:
		orbit.x -= e.relative.x * 0.01
		orbit.y = clampf(orbit.y + e.relative.y * 0.01, -1.4, 1.4)
		_place_camera()

func _click(at: Vector2, add: bool) -> void:
	var from := cam.project_ray_origin(at)
	var to := from + cam.project_ray_normal(at) * 20.0
	var hit := viewport.find_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from, to))
	if hit.is_empty():
		return
	var cs = hit.collider.shape_owner_get_owner(hit.collider.shape_find_owner(hit.shape))
	if cs == null or not cs.has_meta("cell"):
		return
	var cell: Vector3i = cs.get_meta("cell")
	if add:
		var n: Vector3 = hit.normal
		var nc := cell + Vector3i(roundi(n.x), roundi(n.y), roundi(n.z))
		if cells.has(nc) or cells.size() >= 400:
			return
		if _value_now() + Arms.voxel_price(mat) - original_value > purse:
			cost_label.text = "Not enough denarii for that"
			return
		cells[nc] = [mat, job]
	else:
		if cells.size() <= 1:
			return
		cells.erase(cell)
	_rebuild()

func _take() -> void:
	var has_grip := cells.values().any(func(c): return c[1] == "grip")
	if not has_grip:
		cost_label.text = "It needs a grip to be held"
		return
	var vox := []
	for k in cells:
		vox.append([k.x, k.y, k.z, cells[k][0], cells[k][1]])
	design.voxels = vox
	design.erase("stats")
	var cost := _value_now() - original_value
	done.call(design, cost)
