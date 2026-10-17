class_name WeaponView
extends Control
## A weapon seen all round (the smith's wares, your own designs): it turns slowly by itself;
## drag it to turn it any way, the wheel brings it nearer. A click anywhere off it, or Close,
## puts it back on the counter.

var design: Dictionary
var vp: SubViewport
var cam: Camera3D
var pivot: Node3D
var turn := Vector2(0.6, 0.25)
var dist := 1.0
var fit_dist := 1.0   # the distance that shows the whole weapon
var dragging := false
var idle := 0.0

## Opens the viewer over `parent` for design `d`, titled with its name and `line` beneath.
static func show_for(parent: Node, d: Dictionary, line := "") -> WeaponView:
	var v := WeaponView.new()
	v.design = d
	parent.add_child(v)
	v._build(line)
	return v

func _build(line: String) -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UIStyle.theme()
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(e): if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT: queue_free())
	add_child(dim)
	var panel := PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.08, 0.06, 0.045, 0.97)
	st.border_color = UIStyle.BRONZE_DARK
	st.set_border_width_all(1)
	st.set_corner_radius_all(10)
	st.content_margin_left = 14; st.content_margin_right = 14; st.content_margin_top = 12; st.content_margin_bottom = 12
	panel.add_theme_stylebox_override("panel", st)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	panel.add_child(col)
	var head := HBoxContainer.new()
	var t := UIStyle.label(str(design.get("name", "Weapon")), 22, UIStyle.GOLD)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	head.add_child(UIStyle.button("Close", queue_free))
	col.add_child(head)
	if line != "":
		col.add_child(UIStyle.label(line, 13, UIStyle.MUTED))
	var svc := SubViewportContainer.new()
	svc.stretch = true
	svc.custom_minimum_size = Vector2(520, 520)
	svc.gui_input.connect(_on_input)
	col.add_child(svc)
	vp = SubViewport.new()
	vp.own_world_3d = true
	vp.transparent_bg = false
	vp.msaa_3d = Viewport.MSAA_4X
	svc.add_child(vp)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.11, 0.085, 0.065)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(1.0, 0.93, 0.82)
	e.ambient_light_energy = 0.75
	env.environment = e
	vp.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.light_energy = 1.5
	sun.rotation = Vector3(-0.8, 0.7, 0)
	vp.add_child(sun)
	var rim := DirectionalLight3D.new()
	rim.light_energy = 0.6
	rim.light_color = Color(1.0, 0.7, 0.45)
	rim.rotation = Vector3(-0.3, -2.4, 0)
	vp.add_child(rim)
	pivot = Node3D.new()
	vp.add_child(pivot)
	var model := Thumbs.model(design)
	pivot.add_child(model)
	# Its middle on the pivot, and the camera far enough for the whole of it, turned any way.
	var mi := model.get_child(0) as MultiMeshInstance3D
	var box: AABB = mi.custom_aabb if mi.custom_aabb.size != Vector3.ZERO else mi.multimesh.get_aabb()
	model.position = -box.get_center()
	cam = Camera3D.new()
	cam.fov = 32.0
	vp.add_child(cam)
	dist = maxf(0.3, box.size.length() * 0.5 / sin(deg_to_rad(cam.fov * 0.5)) * 1.12)
	fit_dist = dist
	col.add_child(UIStyle.label("Drag to turn it · wheel to bring it nearer", 12, UIStyle.MUTED))
	_place()

func _place() -> void:
	pivot.rotation = Vector3(turn.y, turn.x, 0.0)
	cam.position = Vector3(0, 0, dist)
	cam.look_at(Vector3.ZERO)

func _on_input(e: InputEvent) -> void:
	if e is InputEventMouseButton:
		if e.button_index == MOUSE_BUTTON_LEFT:
			dragging = e.pressed
		elif e.button_index == MOUSE_BUTTON_WHEEL_UP and e.pressed:
			dist = maxf(0.2, dist * 0.9)
		elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN and e.pressed:
			dist = minf(maxf(6.0, fit_dist * 2.0), dist * 1.1)   # a weapon of any size can be backed away from
		_place()
	elif e is InputEventMouseMotion and dragging:
		turn.x += e.relative.x * 0.01
		turn.y = clampf(turn.y + e.relative.y * 0.01, -1.5, 1.5)
		idle = 0.0
		_place()

func _process(dt: float) -> void:
	if pivot == null:
		return
	idle += dt
	# Left alone, it turns slowly round on the counter.
	if not dragging and idle > 1.0:
		turn.x += dt * 0.6
		_place()

func _unhandled_key_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and e.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		queue_free()
