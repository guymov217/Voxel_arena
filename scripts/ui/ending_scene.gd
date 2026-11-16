class_name EndingScene
extends Node
## The campaign's end in the arena (user: a short scene, skippable): the last beast down and the
## crowd on its feet; the Emperor rises in his box and gives the thumb; the rudis put in the
## gladiator's hand, held up while the crowd roars; then the rudis screen. Any key or click ends it
## at once. Drawing only: nothing in the save changes here (the menu gives the rudis: _grant_rudis).

signal done

const LENGTH := 26.0
const BOX := Vector3(0, 3.6, 17.45)   # where the Emperor stands, before his throne (Arena)
const ARM_UP := 2.0                   # how far his right arm swings up and forward (rad)
const CAM_R := 0.45                   # the room the camera keeps from anything solid
const CAM_LOW := 1.0                   # and the least height it stands at (not under a fallen wing)
var cam_shape := SphereShape3D.new()

var m                    # the Match, its fight over
var f: Fighter = null    # the gladiator
var cam: Camera3D
var emperor: Fighter = null
var t := 0.0
var shot := -1
var arm_k := 0.0
var given := false
var finished := false
var crowd_t := 0.0
var mine: Array[RID] = []   # his own bodies: the camera's clearance is judged against the rest
var turn_a := 0.0         # how far the camera has been turned about him to stand clear of a fallen foe
var layer: CanvasLayer
var title: Label
var sub: Label
var fade: ColorRect
var pose := {"main": {"x": 0.3, "y": 0.2}, "off": {"x": -0.35, "y": 0.15}, "power": false, "thrust": 0.0, "look": {"yaw": 0.0, "pitch": 0.0}, "mx": 0.0, "mz": 0.0}

## Plays the scene over `match_` (its fight over), the HUD `hud` hidden meanwhile; await `done`.
static func play(match_, hud = null) -> EndingScene:
	var s := EndingScene.new()
	match_.add_child(s)
	s.start(match_, hud)
	return s

func start(match_, hud) -> void:
	m = match_
	process_mode = Node.PROCESS_MODE_ALWAYS
	if hud and is_instance_valid(hud):
		hud.visible = false
	if m.me and is_instance_valid(m.me.f):
		f = m.me.f
		var tp: Vector3 = f.torso.global_position
		pose.look.yaw = atan2(BOX.x - tp.x, BOX.z - tp.z)
		m.me["drive"] = func(_e): return pose
		for p in f.parts:
			mine.append(p.get_rid())
		for side in ["R", "L"]:
			var w = f.weapons[side]
			if w != null and is_instance_valid(w):
				mine.append((w as Weapon).get_rid())
	cam_shape.radius = CAM_R
	cam = Camera3D.new()
	cam.fov = 50.0
	m.add_child(cam)
	cam.make_current()
	_build_emperor()
	_build_layer()
	_aim(0.0)

func _build_layer() -> void:
	layer = CanvasLayer.new()
	layer.layer = 20
	add_child(layer)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	box.anchor_left = 0.0
	box.anchor_right = 1.0
	box.offset_top = -190.0
	box.offset_bottom = -60.0
	box.alignment = BoxContainer.ALIGNMENT_END
	layer.add_child(box)
	title = UIStyle.title("", 46)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	sub = UIStyle.label("", 20, UIStyle.TEXT)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(sub)
	var skip := UIStyle.label("Any key: skip", 14, UIStyle.MUTED)
	skip.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	skip.offset_left = -220.0
	skip.offset_top = -40.0
	layer.add_child(skip)
	fade = ColorRect.new()
	fade.color = Color(0, 0, 0, 0)
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(fade)

## The Emperor before his throne, held still as the armourer's bench holds a man (ArmourForge:
## every part frozen where it sits on him at rest), facing the sand: purple, laurel, red cloak.
func _build_emperor() -> void:
	var e := Fighter.new()
	m.add_child(e)
	var opts := {"name": "The Emperor", "slot": 8, "team": 9, "bot": false, "team_color": Color(0.36, 0.1, 0.38),
		"skin": int(Fighter.SKINS[0]), "build": FineBody.BUILDS[0], "mods": {}}
	e.build(BOX, PI, {"main": "", "off": "", "armor": ["hat_laurel", "cape", "beard_short"]}, opts)
	for p in e.parts:
		p.freeze = true
		p.collision_layer = 0
		p.collision_mask = 0
	e.set_physics_process(false)
	emperor = e
	_pose_emperor()

## Every part where it sits on him at rest, his right arm swung up by `arm_k` about the shoulder.
func _pose_emperor() -> void:
	if emperor == null or not is_instance_valid(emperor):
		return
	var b := Basis(Vector3.UP, PI)
	var s: float = emperor.S
	var up_def: Dictionary = Data.body_def(String(emperor.arm.R.upper.part_name))
	var ua: Array = up_def.get("pos", [0, 0, 0])
	var half_up := float((up_def.get("dims", [3, 7, 3]) as Array)[1]) * Data.body_voxel * 0.5
	var shoulder: Vector3 = BOX + b * (Vector3(float(ua[0]), float(ua[1]) + half_up, float(ua[2])) * s)
	var r := Basis((b * Vector3(-1, 0, 0)).normalized(), arm_k * ARM_UP)
	var arm := [emperor.arm.R.upper, emperor.arm.R.fore]
	for p in emperor.parts:
		var pos: Array = Data.body_def(String(p.part_name)).get("pos", [0, 0, 0])
		var tr := Transform3D(b, BOX + b * (Vector3(float(pos[0]), float(pos[1]), float(pos[2])) * s))
		if arm.has(p):
			tr = Transform3D(r * b, shoulder + r * (tr.origin - shoulder))
		p.global_transform = tr
		p.reset_physics_interpolation()
	for p in emperor.parts:
		if p.has_method("snap_drawing"):
			p.snap_drawing()

func _caption(i: int, a: String, b := "") -> void:
	if shot == i:
		return
	shot = i
	title.text = Loc.t(a)
	sub.text = Loc.t(b)

## The crowd on its feet: cheers all round, confetti and petals over the stands and, once he
## holds the rudis, over him.
func _crowd(dt: float, tp: Vector3) -> void:
	crowd_t -= dt
	if crowd_t > 0.0:
		return
	crowd_t = 0.45
	var a := randf() * TAU
	var stands := Vector3(cos(a) * 19.0, 6.0 + randf() * 3.0, sin(a) * 19.0)
	m.sfx("cheer", stands, 0.8)
	if m.fx:
		m.fx.burst("confetti", stands, 60, Vector3.UP, 1.1)
		if given:
			m.fx.burst("confetti", tp + Vector3(randf_range(-1.5, 1.5), 3.5, randf_range(-1.5, 1.5)), 50, Vector3.DOWN, 0.6)

## The rudis into his hand, with a gold flash and the crowd's roar.
func _give_rudis() -> void:
	given = true
	if f == null or not is_instance_valid(f):
		return
	f.rearm(Data.preset("rudis"), null)
	var hp := f.hand_world("R")
	if m.fx:
		m.fx.burst("sparks", hp, 50, Vector3.UP, 1.2, Color(1.0, 0.85, 0.4, 1.0))
		m.fx.flash(hp, Color(1.0, 0.85, 0.5), 6.0, 4.0)
	m.sfx("cheer", hp, 1.0)

## Nothing solid within a camera's reach of `p` but his own body (a fallen giant, a pillar).
func _clear_at(p: Vector3) -> bool:
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = cam_shape
	q.transform = Transform3D(Basis(), p)
	q.exclude = mine
	q.collide_with_areas = false
	return m.get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty()

## Where the camera may stand for a shot meant for `p` round him at `tp`: there, or turned about
## him by the least angle (the way it was turned last first), or drawn in toward him, or lifted
## over it, where nothing solid is in the way. (The Dragon lies where it fell, and a shot that would stand inside
## its body stands beside it.)
func _place(p: Vector3, tp: Vector3) -> Vector3:
	var off := p - tp
	var flat := Vector3(off.x, 0.0, off.z)
	var order := [0.0, turn_a, 0.5, -0.5, 1.0, -1.0, 1.6, -1.6, 2.4, -2.4, PI]
	for rise in [0.0, 2.5, 5.0]:
		for s in [1.0, 0.7, 0.45]:
			for a in order:
				var q: Vector3 = tp + Vector3(0.0, off.y + float(rise), 0.0) + Basis(Vector3.UP, float(a)) * (flat * float(s))
				q.y = maxf(q.y, CAM_LOW)
				if _clear_at(q):
					turn_a = float(a)
					return q
	return p

## Which way the nearest foe lies from him on the sand (flat), or nothing.
func _foe_way(tp: Vector3) -> Vector3:
	var best := Vector3.ZERO
	var near := INF
	for e in m.enemies():
		if e.f == null or not is_instance_valid(e.f):
			continue
		var d: Vector3 = e.f.torso.global_position - tp
		d.y = 0.0
		if d.length() < near:
			near = d.length()
			best = d
	return best

func _tp() -> Vector3:
	return f.torso.global_position if f and is_instance_valid(f) else Vector3(0, 1.1, 0)

func _process(dt: float) -> void:
	if finished:
		return
	t += dt
	_crowd(dt, _tp())
	_aim(dt)

## The camera, the captions and the pose for the moment `t`. (Also once as the scene begins: the
## camera is made at the world's middle, ground level and under a fallen Dragon's wing, and the
## first frame was shot from there.)
func _aim(dt: float) -> void:
	var tp := _tp()
	var fw := Vector3(sin(float(pose.look.yaw)), 0, cos(float(pose.look.yaw)))
	var side := fw.cross(Vector3.UP)
	if t < 8.0:
		_caption(0, "THE DRAGON IS SLAIN", Loc.t("%d bouts. The crowd is on its feet.") % (Data.campaign.get("stages", []) as Array).size())
		var way := _foe_way(tp)
		var a0 := atan2(-way.x, -way.z) if way.length() > 0.5 else 1.4   # (the foe behind him in the frame)
		var a := a0 - 0.48 + t * 0.12
		cam.global_position = _place(tp + Vector3(sin(a) * 3.4, 0.35 + t * 0.05, cos(a) * 3.4), tp)
		cam.look_at(tp + Vector3(0, 0.25, 0))
	elif t < 14.0:
		_caption(1, "THE EMPEROR RISES", "He gives the thumb.")
		var k := (t - 8.0) / 6.0
		cam.global_position = Vector3(1.2 * k, 2.6 + 0.6 * k, 12.0 + 0.8 * k)
		cam.look_at(BOX + Vector3(0, 1.2, 0))
		if t > 9.5:
			arm_k = minf(1.0, arm_k + dt * 1.2)
			_pose_emperor()
	elif t < 21.0:
		if not given:
			_give_rudis()
		_caption(2, "THE RUDIS", "The wooden sword: you are free.")
		pose.main = {"x": 0.0, "y": 1.7}
		var k := (t - 14.0) / 7.0
		cam.global_position = _place(tp + fw * (2.7 - 0.7 * k) + side * 0.9 + Vector3(0, -0.25 + 0.35 * k, 0), tp)
		cam.look_at(tp + Vector3(0, 0.55, 0))
	elif t < LENGTH:
		_caption(3, "RUDIS! RUDIS!")
		var k := (t - 21.0) / (LENGTH - 21.0)
		cam.global_position = _place(tp + fw * (2.0 + 2.5 * k) - side * (0.6 + 0.8 * k) + Vector3(0, 0.6 + 2.2 * k, 0), tp)
		cam.look_at(tp + Vector3(0, 0.6, 0))
		fade.color.a = clampf((t - (LENGTH - 2.0)) / 2.0, 0.0, 1.0)
	else:
		finish()

func _unhandled_input(e: InputEvent) -> void:
	if finished or t < 0.5:
		return
	if (e is InputEventKey and e.pressed and not e.echo) or (e is InputEventMouseButton and e.pressed):
		get_viewport().set_input_as_handled()
		finish()

## The scene over (played out or skipped): the man's own camera back, and `done`.
func finish() -> void:
	if finished:
		return
	finished = true
	if m and is_instance_valid(m) and m.me:
		m.me.erase("drive")
	if emperor and is_instance_valid(emperor):
		emperor.queue_free()
	if cam and is_instance_valid(cam):
		cam.queue_free()
	if layer and is_instance_valid(layer):
		layer.queue_free()
	done.emit()
	queue_free()
