extends Node
## Open fractures, close up (`-- --probe fractureshot`, needs a display): a forearm and a shin
## broken out through the skin, the splinter of bone standing out of the wound. PNGs go to
## SHOT_DIR: fracture_arm.png, fracture_leg.png, fracture_hud.png (the HUD's figure).

var m
var cam: Camera3D

func _snap(out: String, name: String, pos: Vector3, look: Vector3, fov := 30.0) -> void:
	cam.global_position = pos
	cam.look_at(look, Vector3.UP)
	cam.fov = fov
	for i in 24:
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
	m.me.drive = func(_e): return {"main": {"x": 0.6, "y": -0.2}, "off": {"x": -0.3, "y": 0.1}}
	for i in 60:
		await get_tree().physics_frame
	var yq := Quaternion(Vector3.UP, f.yaw)
	# The right forearm broken open by a blow from in front, the left shin from the side.
	for k in [["forearmR", Vector3(0, 0, 1)], ["shinL", Vector3(1, 0, 0)]]:
		var p: VoxelPart = f.by_name[k[0]]
		var lp: Vector3 = (k[1] as Vector3) * p.half_ext
		var ld: Vector3 = -(k[1] as Vector3)
		f._fracture(p, lp, 52.0, {}, 3, ld)
	for i in 90:
		await get_tree().physics_frame
	var arm: VoxelPart = f.by_name["forearmR"]
	var shin: VoxelPart = f.by_name["shinL"]
	for k in [[arm, "fracture_arm.png"], [shin, "fracture_leg.png"]]:
		var part: VoxelPart = k[0]
		if part.bone_out == null:
			print("no bone out on ", part.part_name)
			continue
		var mid: Vector3 = part.global_transform * part.bone_at
		var bd: Vector3 = (part.global_transform.basis * part.bone_dir).normalized()
		# From outside him, on the side the bone stands out of, a little above it.
		var away: Vector3 = mid - f.torso.global_position
		away.y = 0.0
		var look_from: Vector3 = (away.normalized() * 0.6 + Vector3(bd.x, 0.0, bd.z) * 0.6).normalized()
		var cp: Vector3 = mid + look_from * 0.42 + Vector3(0, 0.12, 0)
		cp.y = maxf(cp.y, 0.3)
		await _snap(out, k[1], cp, mid, 38.0)
	# The whole man, the HUD's figure in the corner.
	var hud := Hud.new(m)
	add_child(hud)
	var t: Vector3 = f.torso.global_position
	await _snap(out, "fracture_hud.png", t + yq * Vector3(0.6, 0.15, 1.5), t + Vector3(0, -0.3, 0), 50.0)
	get_tree().quit()
