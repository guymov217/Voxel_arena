extends MeshInstance3D
## A blade's sweep through the air (drawing only): a faint ribbon from the root of what cuts to
## its tip over the last moment of a fast swing, fading as it goes, so the eye reads the speed
## and the arc of the blow. Nothing at all while the weapon moves slowly, lies on the sand or
## flies thrown; never made in a headless game (Weapon._build_mesh).

const LIFE := 0.16          # how long a stretch of the sweep stays, seconds
const MIN_SPEED := 5.5      # m/s at the tip before any of it shows
const FULL_SPEED := 15.0    # m/s at which it is as plain as it gets
const ALPHA := 0.5
const TINT := Color(1.0, 0.96, 0.88)

var w   # the Weapon whose sweep it draws
var tip_l := Vector3.ZERO    # the tip and the root of what cuts, in the weapon's own frame
var root_l := Vector3.ZERO
var samples: Array = []      # [time, root, tip, strength]
var im := ImmediateMesh.new()
var last_tip = null
var t := 0.0
var _drawn := false

static var _mat: StandardMaterial3D

func _init(weapon) -> void:
	w = weapon
	name = "SwingTrail"
	mesh = im
	top_level = true
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# (The kill cam plays the bout back with the rest paused: the sweep goes on with it.)
	process_mode = Node.PROCESS_MODE_ALWAYS
	if _mat == null:
		_mat = StandardMaterial3D.new()
		_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_mat.vertex_color_use_as_albedo = true
		_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_mat.disable_receive_shadows = true
	material_override = _mat
	_measure()

## The tip: the sharp voxel furthest from the grip (any voxel, a club); the root: the sharp one
## nearest it, or a stretch back from the tip when what cuts is short (a spear's head, a club).
func _measure() -> void:
	var sharp := []
	var every := []
	for v in w.vox:
		var p: Vector3 = Vector3(float(v[0]), float(v[1]), float(v[2])) * float(w.vs)
		every.append(p)
		if v[4] == "edge" or v[4] == "point":
			sharp.append(p)
	var pts: Array = sharp if sharp.size() >= 2 else every
	if pts.is_empty():
		return
	var far: Vector3 = pts[0]
	var near: Vector3 = pts[0]
	for p in pts:
		if (p as Vector3).length_squared() > far.length_squared():
			far = p
		if (p as Vector3).length_squared() < near.length_squared():
			near = p
	tip_l = far
	root_l = near if sharp.size() >= 2 and far.distance_to(near) > 4.0 * float(w.vs) else far * 0.72

func _process(dt: float) -> void:
	if not is_instance_valid(w) or w.vis == null or not is_instance_valid(w.vis):
		queue_free()
		return
	t += dt
	var xf: Transform3D = w.vis.global_transform
	var tip := xf * tip_l
	var root := xf * root_l
	var speed := 0.0
	if last_tip != null and dt > 0.0:
		speed = tip.distance_to(last_tip) / dt
	last_tip = tip
	var held: bool = w.holder != null and w.vis.visible
	var k := clampf((speed - MIN_SPEED) / (FULL_SPEED - MIN_SPEED), 0.0, 1.0) if held else 0.0
	samples.push_back([t, root, tip, k])
	while not samples.is_empty() and t - float(samples[0][0]) > LIFE:
		samples.pop_front()
	var any := false
	for s in samples:
		if float(s[3]) > 0.0:
			any = true
			break
	if _drawn:
		im.clear_surfaces()
		_drawn = false
	visible = any
	if not any or samples.size() < 2:
		return
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	for i in samples.size() - 1:
		var a: Array = samples[i]
		var b: Array = samples[i + 1]
		var fa := (1.0 - (t - float(a[0])) / LIFE) * float(a[3])
		var fb := (1.0 - (t - float(b[0])) / LIFE) * float(b[3])
		if fa <= 0.0 and fb <= 0.0:
			continue
		# Strongest at the tip, nothing at the root: a smear, not a sheet.
		var ta := Color(TINT.r, TINT.g, TINT.b, ALPHA * maxf(fa, 0.0))
		var tb := Color(TINT.r, TINT.g, TINT.b, ALPHA * maxf(fb, 0.0))
		var ra := Color(TINT.r, TINT.g, TINT.b, 0.0)
		verts.append_array(PackedVector3Array([a[1], a[2], b[2], a[1], b[2], b[1]]))
		cols.append_array(PackedColorArray([ra, ta, tb, ra, tb, ra]))
	if verts.is_empty():
		visible = false
		return
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in verts.size():
		im.surface_set_color(cols[j])
		im.surface_add_vertex(verts[j])
	im.surface_end()
	_drawn = true
