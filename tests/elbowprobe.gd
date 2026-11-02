extends Node
## The off arm in the first moments of a bout with a two-hander (the sweep: forearmL a hand's
## breadth off the upper arm at the start): frame by frame, the elbow's gap, the shoulder's, the
## hand's distance from the haft, the haft's from the shoulder against the arm's length, whether
## both hands are on, and where the off hand is in the trunk's frame (+z is in front).
## `-- --probe elbowprobe`. MINE (zweihander), FRAMES (80).

func _ready() -> void:
	var mine := OS.get_environment("MINE") if OS.get_environment("MINE") != "" else "zweihander"
	var frames := int(OS.get_environment("FRAMES")) if OS.get_environment("FRAMES") != "" else 80
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none"}, "headless": true, "seed": 3, "loadout": {"main": mine, "off": ""}})
	var f: Fighter = m.me.f
	var up: VoxelPart = f.arm.L.upper
	var fore: VoxelPart = f.arm.L.fore
	var w: Weapon = f.weapons.R
	print("two-handed %s, arm %.3f + %.3f" % [str(f.two_handed), (fore.pa - up.ca).length(), (f.hand_point - fore.ca).length()])
	for i in frames:
		var sh: Vector3 = up.parent_part.global_transform * up.pa
		var at: Vector3 = w.global_transform * w.grip_off
		var elbow := (up.global_transform * fore.pa).distance_to(fore.global_transform * fore.ca)
		var shoulder := sh.distance_to(up.global_transform * up.ca)
		var lh: Vector3 = f.torso.global_transform.affine_inverse() * f.hand_world("L")
		print("%2d elbow %.3f shoulder %.3f hand-haft %.3f haft from shoulder %.3f two %s grip_wait %.2f off hand (%.2f, %.2f, %.2f)" % [i, elbow, shoulder, f.hand_world("L").distance_to(at), sh.distance_to(at), str(f.two_handed), f.grip_wait, lh.x, lh.y, lh.z])
		await get_tree().physics_frame
	get_tree().quit()
