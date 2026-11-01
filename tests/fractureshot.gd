extends Node
## Open fractures, close up (`-- --probe fractureshot`, needs a display): broken out through the
## skin where each was struck, the broken end of the bone standing out of the wound. PNGs go to
## SHOT_DIR: fracture_arm.png (a forearm struck in front), fracture_leg.png (a shin low, by the
## ankle, struck from the side), fracture_thigh.png (a thigh above its middle, struck in front),
## fracture_far.png (the broken shin from where the fight's camera would be), fracture_leg_side.png
## (the whole leg from its outer side), fracture_hud.png
## (the HUD's figure; SKIP_HUD=1 leaves it out).

var m
var cam: Camera3D

func _snap(out: String, name: String, pos: Vector3, look: Vector3, fov := 30.0) -> void:
	cam.global_position = pos
	cam.look_at(look, Vector3.UP)
	cam.fov = fov
	for i in 14:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(out.path_join(name))
	print("saved ", name)

func _ready() -> void:
	var out := OS.get_environment("SHOT_DIR")
	m = Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none"}, "decrees": [], "hazards": [], "seed": 3, "loadout": {"main": "", "off": ""}})
	if m.cam:
		m.cam.set_process(false)
	cam = Camera3D.new()
	m.add_child(cam)
	cam.make_current()
	var f: Fighter = m.me.f
	# (The right arm out to his side, clear of the body, its forearm to be seen broken.)
	m.me.drive = func(_e): return {"main": {"x": 0.9, "y": 0.35}, "off": {"x": -0.3, "y": 0.1}}
	# Nothing drawn until the shots (a machine without a graphics card spends seconds a frame).
	get_viewport().disable_3d = true
	var full := get_window().size
	get_window().size = Vector2i(160, 90)
	for i in 60:
		await get_tree().physics_frame
	var yq := Quaternion(Vector3.UP, f.yaw)
	# Held where he stands (frozen), so the breaks are seen in daylight as on a man on his feet, not
	# under him in the sand.
	for p in f.parts:
		p.freeze = true
	# The right forearm broken open by a blow from in front, the left shin low by the ankle from
	# the side, the right thigh above its middle from in front: [part, the side struck, how far up
	# it (of its half length)].
	for k in [["forearmR", Vector3(0, 0, 1), 0.0], ["shinL", Vector3(1, 0, 0), -0.4], ["thighR", Vector3(0, 0, 1), 0.3]]:
		var p: VoxelPart = f.by_name[k[0]]
		var ax: int = p._root_axis()[0]
		var lp: Vector3 = (k[1] as Vector3) * p.half_ext
		lp[ax] = float(k[2]) * p.half_ext[ax]
		var ld: Vector3 = -(k[1] as Vector3)
		f._fracture(p, lp, 52.0, {}, 3, ld)
	for i in 90:
		await get_tree().physics_frame
	get_window().size = full
	get_viewport().disable_3d = false
	var arm: VoxelPart = f.by_name["forearmR"]
	var shin: VoxelPart = f.by_name["shinL"]
	var thigh: VoxelPart = f.by_name["thighR"]
	for k in [[arm, "fracture_arm.png"], [shin, "fracture_leg.png"], [thigh, "fracture_thigh.png"]]:
		var part: VoxelPart = k[0]
		if part.bone_out == null:
			print("no bone out on ", part.part_name)
			continue
		# Where along the bone it broke out, of its half length from the middle (0: the middle).
		var ex := part.break_exit()
		if not ex.is_empty():
			var ax: int = part.kink[0]
			print("%s broke out at %+.2f of its half length from its middle" % [part.part_name, (ex[0] as Vector3)[ax] / part.half_ext[ax]])
		var mid: Vector3 = part.global_transform * part.bone_at
		var bd: Vector3 = (part.global_transform.basis * part.bone_dir).normalized()
		# From the side the bone stands out of, half across it (seen standing out, not end on), and
		# from outside him.
		var away: Vector3 = mid - f.torso.global_position
		away.y = 0.0
		var across: Vector3 = bd.cross(Vector3.UP)
		if across.length() < 0.2:
			across = away
		across = across.normalized()
		if across.dot(away) < 0.0:
			across = -across
		var look_from: Vector3 = (bd * 0.7 + across * 0.6 + Vector3.UP * 0.15).normalized()
		var cp: Vector3 = mid + look_from * 0.6
		cp.y = maxf(cp.y, 0.3)
		await _snap(out, k[1], cp, mid, 38.0)
	# How high up the shin it broke out, between the knee and the sole (world heights), and the
	# whole leg from its outer side.
	var exs := shin.break_exit()
	if not exs.is_empty():
		var axs: int = shin._root_axis()[0]
		var top := Vector3.ZERO
		top[axs] = shin.half_ext[axs]
		var bot := -top
		var yk: float = (shin.global_transform * top).y
		var ys: float = (shin.global_transform * bot).y
		if yk < ys:
			var sw := yk
			yk = ys
			ys = sw
		var yb: float = (shin.global_transform * (exs[0] as Vector3)).y
		print("shinL: knee end %.2f m, sole end %.2f m, broke out at %.2f m: %.0f%% of the way up from the sole" % [yk, ys, yb, (yb - ys) / maxf(1e-3, yk - ys) * 100.0])
		var side: Vector3 = (shin.global_position - f.torso.global_position)
		side.y = 0.0
		var sc: Vector3 = shin.global_position + Vector3(0, 0.15, 0)
		await _snap(out, "fracture_leg_side.png", sc + side.normalized() * 1.5 + Vector3(0, 0.25, 0), sc, 40.0)
	# The broken shin as the fight's camera sees it, a couple of metres off.
	var sh: Vector3 = shin.global_transform * shin.bone_at if shin.bone_out else shin.global_position
	var aw: Vector3 = sh - f.torso.global_position
	aw.y = 0.0
	await _snap(out, "fracture_far.png", sh + aw.normalized() * 2.6 + Vector3(0, 1.3, 0), sh + Vector3(0, 0.3, 0), 55.0)
	# The whole man, the HUD's figure in the corner (SKIP_HUD=1: not; it takes long to draw).
	if OS.get_environment("SKIP_HUD") == "1":
		get_tree().quit()
		return
	var hud := Hud.new(m)
	add_child(hud)
	var t: Vector3 = f.torso.global_position
	await _snap(out, "fracture_hud.png", t + yq * Vector3(0.6, 0.15, 1.5), t + Vector3(0, -0.3, 0), 50.0)
	get_tree().quit()
