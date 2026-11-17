class_name Stage3D
extends SubViewportContainer
## A live 3D view inside a menu, the showcase of the stalls: a thing on a stand under warm light,
## turning slowly by itself. Drag it to turn it, the wheel brings it nearer. It is drawn only
## while it is on the screen (SubViewport.UPDATE_WHEN_VISIBLE), in a world of its own.
##
## show_model(node, {...}) puts a thing on it: a weapon (Thumbs.model), a ware (Items.visual), the
## gladiator in his armour (a Fighter built like the armour bench's). opts: `box` its bounds if it
## is not made of plain meshes, `yaw`, `pitch`, `spin` (rad/s), `centre` (false: leave it where it
## stands, the way the man is), `stand` ("plinth", "anvil", "none"), `look` the point looked at,
## `k` how much room round it, `exact` (framed for the way it is turned now, and again as it is
## turned: for a long low thing that stands still and is looked at from the side, an anvil).

const WARM := Color(1.0, 0.93, 0.82)

var vp: SubViewport
var cam: Camera3D
var pivot: Node3D          # what turns: the model and its stand
var model: Node3D = null
var yaw := 0.6
var pitch := 0.24
var dist := 1.0
var fit := 1.0             # the distance that shows all of it
var zoom := 1.0            # how near the wheel has brought it (1: all of it)
var spin := 0.45           # rad/s when left alone (0: it stands)
var idle := 0.0
var dragging := false
var shake := 0.0           # a knock's tremor, 0..1, dying out (bump)
var look := Vector3.ZERO   # the point the camera looks at, in the pivot's space
var box := AABB()
var whole := AABB()        # the thing and its stand: what the view is framed on
var orbit := false         # the view goes round the thing instead of the thing turning (a man, whose drawing stays where he stands)
var _key: DirectionalLight3D
var _rim: DirectionalLight3D

func _init() -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_DRAG
	clip_contents = true
	vp = SubViewport.new()
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	# (The game eases what it draws between physics steps; a view set up here is drawn where its
	# camera was just put: Thumbs.)
	vp.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	vp.audio_listener_enable_3d = false
	vp.physics_object_picking = false
	add_child(vp)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_CLEAR_COLOR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = WARM
	e.ambient_light_energy = 0.72
	env.environment = e
	vp.add_child(env)
	_key = DirectionalLight3D.new()
	_key.light_energy = 1.55
	_key.light_color = WARM
	_key.rotation = Vector3(-0.85, 0.6, 0.0)
	_key.shadow_enabled = true
	_key.shadow_bias = 0.03
	vp.add_child(_key)
	# A rim from behind and above, in forge-light: the edge of a dark thing stands off the dark.
	_rim = DirectionalLight3D.new()
	_rim.light_energy = 0.8
	_rim.light_color = Color(1.0, 0.68, 0.42)
	_rim.rotation = Vector3(-0.35, -2.5, 0.0)
	vp.add_child(_rim)
	pivot = Node3D.new()
	vp.add_child(pivot)
	cam = Camera3D.new()
	cam.fov = 30.0
	cam.near = 0.02
	cam.far = 60.0
	vp.add_child(cam)
	gui_input.connect(_on_input)

## What to show: the old thing goes, the new one is framed whole.
func show_model(m: Node3D, opts := {}) -> void:
	# (One already stood under the pivot, a man, is kept: the old things go.)
	clear(m)
	model = m
	if m.get_parent() != pivot:
		pivot.add_child(m)
	box = opts.get("box", _box_of(m))
	if opts.get("centre", true):
		m.position -= box.get_center()
		box.position -= box.get_center()
	yaw = float(opts.get("yaw", 0.6))
	pitch = float(opts.get("pitch", 0.24))
	spin = float(opts.get("spin", 0.45))
	idle = 0.0
	# The stand under it, and the picture framed on both.
	whole = box
	var stand := String(opts.get("stand", "plinth"))
	if stand != "none":
		var st := stand_for(stand, box)
		pivot.add_child(st)
		whole = whole.merge(st.get_meta("box"))
	orbit = bool(opts.get("orbit", false))
	_exact = bool(opts.get("exact", false))
	_k = float(opts.get("k", 1.08))
	_lift = float(opts.get("lift", 0.04))
	_frame(opts.get("look", null))

## Framed again to take in more (`extra`, in the pivot's space): what stands over the thing, the
## smith's hammer.
func refit(extra: AABB) -> void:
	whole = whole.merge(extra)
	_frame(null)

var _k := 1.08
var _lift := 0.04
var _exact := false

func _frame(at) -> void:
	look = at if at != null else whole.get_center() - Vector3(0.0, whole.size.y * _lift, 0.0)
	zoom = 1.0
	_place()

## The distance that shows all of `whole`, turned any way, in the view as wide and tall as it is
## now: the height it needs at this tilt, or the width of what turns, whichever asks for more.
func _fit_dist() -> float:
	var asp := maxf(0.4, size.x / maxf(1.0, size.y))
	var hz := Vector2(whole.size.x, whole.size.z).length()
	var rv := 0.5 * (whole.size.y * cos(pitch) + hz * sin(pitch))
	var rh := 0.5 * hz
	if _exact:
		# Only the way it is turned now: its width across the picture, its depth into it.
		var sy := absf(sin(yaw))
		var cy := absf(cos(yaw))
		var across := whole.size.x * cy + whole.size.z * sy
		var into := whole.size.x * sy + whole.size.z * cy
		rv = 0.5 * (whole.size.y * cos(pitch) + into * sin(pitch))
		rh = 0.5 * across
	var t := tan(deg_to_rad(cam.fov * 0.5))
	return maxf(maxf(rv / t, rh / (t * asp)), 0.1) * _k

func clear(keep: Node = null) -> void:
	for c in pivot.get_children():
		if c == keep:
			continue
		pivot.remove_child(c)
		if c.is_inside_tree():
			c.queue_free()
		else:
			c.free()
	model = null

## A weapon (Thumbs.model: its voxels, the blade along +y) laid on the anvil: the longest way
## along x, the thinnest up, so a blade lies flat and not on its edge, the point to the right.
static func lay_flat(root: Node3D) -> void:
	var mi: Node3D = root.get_child(0)
	var b: AABB = (mi as GeometryInstance3D).custom_aabb
	var sp := [b.size.x, b.size.y, b.size.z]
	var long_i := 0
	var thin_i := 0
	for i in 3:
		if sp[i] > sp[long_i]:
			long_i = i
		if sp[i] < sp[thin_i]:
			thin_i = i
	if long_i == thin_i:
		thin_i = (long_i + 1) % 3
	var mid_i := 3 - long_i - thin_i
	var img := [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
	img[long_i] = Vector3.RIGHT
	img[thin_i] = Vector3.UP
	img[mid_i] = Vector3.BACK
	var bs := Basis(img[0], img[1], img[2])
	if bs.determinant() < 0.0:
		img[mid_i] = Vector3.FORWARD
		bs = Basis(img[0], img[1], img[2])
	# (The tip along +x: the blade grows from the grip toward +y, the long way for most.)
	mi.basis = bs

## The smith's hammer, its hand at the origin, the head up the handle (`s`: its length).
static func hammer_node(s: float) -> Node3D:
	var root := Node3D.new()
	_slab(root, Vector3(0.07 * s, s, 0.07 * s), Vector3(0, s * 0.5, 0), Color(0.42, 0.27, 0.13), 0.0, 0.85)
	_slab(root, Vector3(0.22 * s, 0.2 * s, 0.2 * s), Vector3(0, s * 1.0, 0), Color(0.24, 0.25, 0.28), 0.55, 0.45)
	_slab(root, Vector3(0.3 * s, 0.1 * s, 0.1 * s), Vector3(0, s * 1.0, 0), Color(0.3, 0.31, 0.34), 0.6, 0.4)
	return root

## A spray of sparks where the hammer struck (in the pivot's space), gone in a second.
func sparks(at: Vector3, n := 22) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = n
	p.lifetime = 0.6
	p.explosiveness = 1.0
	p.direction = Vector3.UP
	p.spread = 75.0
	var u := maxf(0.2, whole.size.length() * 0.5)
	p.initial_velocity_min = u * 0.9
	p.initial_velocity_max = u * 2.2
	p.gravity = Vector3(0.0, -u * 4.5, 0.0)
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE * u * 0.02
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1.0, 0.78, 0.3)
	bm.material = m
	p.mesh = bm
	p.position = at
	pivot.add_child(p)
	p.emitting = true
	get_tree().create_timer(1.2).timeout.connect(p.queue_free)

## A knock: the thing shakes a moment (the hammer's blow).
func bump(k := 1.0) -> void:
	shake = clampf(maxf(shake, k), 0.0, 1.5)

## The bounds of a thing made of plain meshes, in its parent's space.
static func _box_of(m: Node3D) -> AABB:
	var got = _merge(m, Transform3D.IDENTITY, null)
	return got if got != null else AABB(Vector3(-0.1, -0.1, -0.1), Vector3(0.2, 0.2, 0.2))

## `acc` (null: nothing yet) with the meshes of `n` and below merged in; `xf` the way down to `n`'s parent.
static func _merge(n: Node, xf: Transform3D, acc):
	var got = acc
	var here := xf
	if n is Node3D:
		here = xf * (n as Node3D).transform
	if n is MeshInstance3D or n is MultiMeshInstance3D:
		var gi := n as GeometryInstance3D
		var own: AABB = gi.custom_aabb
		if own.size == Vector3.ZERO:
			own = gi.multimesh.get_aabb() if gi is MultiMeshInstance3D and gi.multimesh != null else (gi.get_aabb() if gi is MeshInstance3D else AABB())
		if own.size != Vector3.ZERO:
			var b: AABB = here * own
			got = b if got == null else (got as AABB).merge(b)
	for c in n.get_children():
		got = _merge(c, here, got)
	return got

## A stand under the thing, as wide as it is: a plinth of oak, or the smith's anvil.
static func stand_for(kind: String, b: AABB) -> Node3D:
	var root := Node3D.new()
	var w := clampf(maxf(b.size.x, b.size.z) * 0.78, 0.32, 3.0)
	var top := b.position.y
	if kind == "anvil":
		_slab(root, Vector3(w * 1.15, 0.07 * w, w * 0.5), Vector3(0, top - 0.035 * w, 0), Color(0.30, 0.31, 0.34), 0.35, 0.55)    # the face
		_slab(root, Vector3(w * 0.5, 0.05 * w, w * 0.3), Vector3(w * 0.78, top - 0.045 * w, 0), Color(0.27, 0.28, 0.31), 0.35, 0.55)    # the horn
		_slab(root, Vector3(w * 0.5, 0.2 * w, w * 0.34), Vector3(0, top - 0.17 * w, 0), Color(0.21, 0.22, 0.25), 0.3, 0.6)             # the waist
		_slab(root, Vector3(w * 0.85, 0.07 * w, w * 0.6), Vector3(0, top - 0.3 * w, 0), Color(0.19, 0.2, 0.23), 0.3, 0.6)             # the foot
		_slab(root, Vector3(w * 1.1, 0.16 * w, w * 0.7), Vector3(0, top - 0.43 * w, 0), Color(0.34, 0.21, 0.11), 0.0, 0.85)               # the block of oak
		root.set_meta("box", AABB(Vector3(-w * 0.65, top - 0.51 * w, -w * 0.4), Vector3(w * 1.5, 0.51 * w, w * 0.8)))
	else:
		_slab(root, Vector3(w, 0.05 * w, w), Vector3(0, top - 0.025 * w, 0), Color(0.46, 0.30, 0.15), 0.0, 0.8)
		_slab(root, Vector3(w * 1.12, 0.07 * w, w * 1.12), Vector3(0, top - 0.085 * w, 0), Color(0.34, 0.21, 0.11), 0.0, 0.85)
		_slab(root, Vector3(w * 1.3, 0.1 * w, w * 1.3), Vector3(0, top - 0.17 * w, 0), Color(0.26, 0.16, 0.08), 0.0, 0.9)
		root.set_meta("box", AABB(Vector3(-w * 0.65, top - 0.22 * w, -w * 0.65), Vector3(w * 1.3, 0.22 * w, w * 1.3)))
	return root

static func _slab(parent: Node3D, size: Vector3, at: Vector3, colour: Color, metal: float, rough: float) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	var m := StandardMaterial3D.new()
	m.albedo_color = colour
	m.metallic = metal
	m.roughness = rough
	bm.material = m
	mi.mesh = bm
	mi.position = at
	parent.add_child(mi)

func _place() -> void:
	fit = _fit_dist()
	dist = fit * zoom
	if orbit:
		# The camera goes round him, the lights with it.
		pivot.rotation = Vector3.ZERO
		cam.position = look + Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * dist
		cam.look_at(look, Vector3.UP)
		_key.rotation = Vector3(-0.85, 0.6 + yaw, 0.0)
		_rim.rotation = Vector3(-0.35, -2.5 + yaw, 0.0)
		return
	pivot.rotation = Vector3(0.0, yaw, 0.0)
	var at := pivot.transform * look
	cam.position = at + Vector3(0.0, sin(pitch), cos(pitch)) * dist
	cam.look_at(at, Vector3.UP)

func _process(dt: float) -> void:
	if model == null or not is_visible_in_tree():
		return
	idle += dt
	if spin != 0.0 and not dragging and idle > 1.0:
		yaw += dt * spin
	if shake > 0.01:
		shake = maxf(0.0, shake - dt * 5.0)
		var s := shake * 0.012 * fit
		pivot.position = Vector3(randf_range(-s, s), randf_range(-s, s), randf_range(-s, s))
	elif pivot.position != Vector3.ZERO:
		pivot.position = Vector3.ZERO
	_place()

func _on_input(e: InputEvent) -> void:
	if e is InputEventMouseButton:
		if e.button_index == MOUSE_BUTTON_LEFT:
			dragging = e.pressed
			idle = 0.0
		elif e.button_index == MOUSE_BUTTON_WHEEL_UP and e.pressed:
			zoom = maxf(0.45, zoom * 0.92)
		elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN and e.pressed:
			zoom = minf(1.6, zoom * 1.08)
	elif e is InputEventMouseMotion and dragging:
		yaw += e.relative.x * 0.011
		pitch = clampf(pitch + e.relative.y * 0.006, 0.0, 1.2)
		idle = 0.0
