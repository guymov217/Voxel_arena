extends Node
## J with both hands on a two-hander: the hands change over and he holds it from his left side,
## the left hand at the guard and the right below it (user: hold the weapon in both hands from the
## left side too, the hands placed as on a real grip, both ways); the weapon goes across to the
## mirror of where it stood and follows the mouse there; J again, and it is back on the right.
## The camera goes over the left shoulder with it, and the marks of the mouse go across too.

var t

func _steps(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

## Where the hands are on the haft, and where the weapon is on him (his own frame: +x his left).
func _grip(f: Fighter, w: Weapon) -> Dictionary:
	var g := f.two_side
	var o := f.two_off()
	var at_main: Vector3 = w.global_transform * w.grip_main
	var at_off: Vector3 = w.global_transform * w.grip_off
	var blade: Vector3 = PD.quat_of(w) * Vector3.UP
	var yq := Quaternion(Vector3.UP, f.yaw)
	var tip: Vector3 = w.global_transform * (w.center_of_mass + Vector3(0, float(w.reach) * 0.5 / maxf(0.1, w.vs), 0))
	var aim = f.aim_q[g]
	return {
		"main": f.hand_world(g).distance_to(at_main),
		"off": f.hand_world(o).distance_to(at_off),
		# The guard hand above the other along the blade (nearer the blade, the other at the pommel).
		"order": (f.hand_world(g) - f.hand_world(o)).dot(blade),
		"tip_x": (yq.inverse() * (tip - f.torso.global_position)).x,
		"blade_l": yq.inverse() * blade,
		"off_aim": rad_to_deg(blade.angle_to((aim as Quaternion) * Vector3.UP)) if aim is Quaternion else 999.0,
	}

func test_j_holds_a_two_hander_from_the_other_side() -> void:
	for preset in ["longsword", "zweihander", "warhammer"]:
		var m := Match.new()
		add_child(m)
		m.setup({"mode": "training", "training": {"enemy": "none"}, "headless": true, "seed": 3, "decrees": [], "hazards": [], "loadout": {"main": preset, "off": ""}})
		var f: Fighter = m.me.f
		f.teleport(Vector3(5, 0, 0))
		# Out to his right, the mouse held there, the button down (a guard on that side).
		var pose := {"main": {"x": 0.9, "y": 0.4}, "off": {"x": -0.35, "y": 0.1}, "power": true, "look": {"yaw": f.yaw, "pitch": 0.0}, "mx": 0.0, "mz": 0.0}
		var once := []
		m.me.drive = func(_e):
			var p: Dictionary = pose.duplicate(true)
			if not once.is_empty():
				p.merge(once.pop_front(), true)
			return p
		await _steps(180)
		var w: Weapon = f.weapons.R
		if not t.check(f.two_handed and w != null and f.two_side == "R", "%s: in both hands, the right at the guard" % preset):
			m.queue_free()
			await _steps(2)
			continue
		var a := _grip(f, w)
		print("%s right: guard hand %.3f off its place, other %.3f, order %.3f, tip x %.2f, %.0f deg off aim" % [preset, a.main, a.off, a.order, a.tip_x, a.off_aim])
		t.check(a.tip_x < -0.1, "%s: held out to his right (tip x %.2f)" % [preset, a.tip_x])
		# J: the hands change over; the mouse's mark goes across with them (PlayerInput.set_two_side).
		once.append({"swap": true})
		await _steps(1)
		pose.main.x = -float(pose.main.x)
		t.check(f.two_side == "L" and f.weapons.L == w and f.weapons.R == null and f.two_handed, "%s: J, the left hand at the guard (side %s, L %s, R %s, two %s)" % [preset, f.two_side, f.weapons.L == w, f.weapons.R, f.two_handed])
		var jl = f.weapon_joints.L
		var jr = f.weapon_joints.R
		t.check(jl != null and is_instance_valid(jl) and jr != null and is_instance_valid(jr), "%s: both hands still hold it" % preset)
		var b0: Vector3 = a.blade_l
		var b1: Vector3 = _grip(f, w).blade_l
		# The mirror at once (the step J was pressed in): the blade as it stood, across his chest's
		# middle, seen from his chest. (Within the step his trunk has begun to turn its twist the
		# other way and a heavy blade to settle in the new grips: 10 to 19 degrees from the mirror,
		# against some 70 from where it stood. Where it comes to rest is checked below.)
		var mir := Vector3(-b0.x, b0.y, b0.z)
		print("%s switched: blade %s -> %s, mirror off %.0f deg" % [preset, b0, b1, rad_to_deg(b1.angle_to(mir))])
		t.check(rad_to_deg(b1.angle_to(mir)) < 25.0, "%s: the weapon goes to the mirror of where it stood (%.0f deg off)" % [preset, rad_to_deg(b1.angle_to(mir))])
		await _steps(180)
		var c := _grip(f, w)
		print("%s left: guard hand %.3f off its place, other %.3f, order %.3f, tip x %.2f, %.0f deg off aim" % [preset, c.main, c.off, c.order, c.tip_x, c.off_aim])
		t.check(f.two_handed and f.weapons.L == w, "%s: still in both hands, from the left" % preset)
		t.check(c.main < 0.06 and c.off < 0.1, "%s: the left hand at the guard (%.3f), the right below it on the grip (%.3f)" % [preset, c.main, c.off])
		t.check(c.order > 0.05, "%s: the left hand above the right along the haft (%.3f)" % [preset, c.order])
		t.check(c.tip_x > 0.1, "%s: held out to his left (tip x %.2f)" % [preset, c.tip_x])
		t.check(c.off_aim < 20.0, "%s: on the mouse from the left (%.0f deg off)" % [preset, c.off_aim])
		# As far out to the left as it was to the right.
		t.check(absf(c.tip_x + a.tip_x) < 0.25, "%s: as far to the left as it was to the right (%.2f, %.2f)" % [preset, c.tip_x, a.tip_x])
		# H lets go with the right and takes it again: still from the left.
		once.append({"grip": true})
		await _steps(30)
		t.check(not f.two_handed and f.weapons.L == w and f.two_side == "L", "%s: H, one hand, still the left" % preset)
		once.append({"grip": true})
		await _steps(120)
		t.check(f.two_handed and f.weapons.L == w and f.two_side == "L", "%s: H again, both hands, from the left" % preset)
		# J again: back to the right.
		once.append({"swap": true})
		await _steps(1)
		pose.main.x = -float(pose.main.x)
		await _steps(180)
		var d := _grip(f, w)
		print("%s back: guard hand %.3f off its place, other %.3f, order %.3f, tip x %.2f, %.0f deg off aim" % [preset, d.main, d.off, d.order, d.tip_x, d.off_aim])
		t.check(f.two_side == "R" and f.weapons.R == w and f.two_handed, "%s: J again, the right at the guard" % preset)
		t.check(d.main < 0.06 and d.off < 0.1 and d.order > 0.05, "%s: back on the right as it was (%.3f, %.3f, %.3f)" % [preset, d.main, d.off, d.order])
		t.check(d.tip_x < -0.1, "%s: out to his right again (tip x %.2f)" % [preset, d.tip_x])
		m.queue_free()
		await _steps(2)

func test_the_camera_and_the_marks_go_across() -> void:
	var pi := PlayerInput.new()
	add_child(pi)
	pi.main = {"x": 0.7, "y": 0.4}
	pi.set_two_side("L")
	t.check(is_equal_approx(float(pi.main.x), -0.7), "the main mark across with the hands (%.2f)" % float(pi.main.x))
	pi.set_two_side("L")
	t.check(is_equal_approx(float(pi.main.x), -0.7), "and only once (%.2f)" % float(pi.main.x))
	pi.reset_hands()
	t.check(pi.two_side == "R", "a new man: the right again")
	pi.queue_free()
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none"}, "headless": true, "seed": 3, "decrees": [], "hazards": [], "loadout": {"main": "zweihander", "off": ""}})
	var f: Fighter = m.me.f
	f.teleport(Vector3(5, 0, 0))
	m.me.drive = func(_e): return {"main": {"x": 0.3, "y": 0.3}, "look": {"yaw": f.yaw, "pitch": 0.0}}
	await _steps(60)
	var cam := CameraRig.new()
	m.add_child(cam)
	var side_of := func() -> float:
		var yq := Quaternion(Vector3.UP, f.yaw)
		return (yq.inverse() * (cam.eye - f.torso.global_position)).x
	for i in 240:
		cam.view_side = -1.0 if f.two_side == "L" else 1.0
		cam.follow(f, f.yaw, 0.0, 1.0 / 120.0)
		await get_tree().physics_frame
	var right_x: float = side_of.call()
	t.check(f.switch_two_side(), "the hands change over")
	for i in 240:
		cam.view_side = -1.0 if f.two_side == "L" else 1.0
		cam.follow(f, f.yaw, 0.0, 1.0 / 120.0)
		await get_tree().physics_frame
	var left_x: float = side_of.call()
	print("camera: %.2f across with the right at the guard, %.2f with the left" % [right_x, left_x])
	t.check(right_x < -0.2, "over his right shoulder (%.2f)" % right_x)
	t.check(left_x > 0.2, "over his left shoulder once he holds it from the left (%.2f)" % left_x)
	m.queue_free()
	await _steps(2)

## Both hands on the haft, the guard hand's arm is drawn turned about the line from its shoulder
## to its fist (Fighter._swivel_drawing): the forearm drawn well off the blade's line, so the grip
## below the fist is clear for the other hand, the fist drawn where the hand is and the arm
## still whole at the shoulder and the elbow. From either side. (Drawing only: the bodies are as
## they were.)
func test_both_hands_are_drawn_on_the_grip() -> void:
	for side in ["R", "L"]:
		for preset in ["longsword", "warhammer"]:
			var m := Match.new()
			add_child(m)
			m.setup({"mode": "training", "training": {"enemy": "none"}, "headless": true, "seed": 3, "decrees": [], "hazards": [], "loadout": {"main": preset, "off": ""}})
			var f: Fighter = m.me.f
			f.teleport(Vector3(5, 0, 0))
			var pose := {"main": {"x": 0.2, "y": 0.2}, "power": true, "look": {"yaw": f.yaw, "pitch": 0.0}}
			m.me.drive = func(_e): return pose
			await _steps(150)
			if side == "L":
				f.switch_two_side()
				pose.main = {"x": -0.2, "y": 0.2}
				await _steps(150)
			var g := f.two_side
			var up: VoxelPart = f.arm[g].upper
			var fo: VoxelPart = f.arm[g].fore
			var w: Weapon = f.weapons[g]
			var hand_body: Vector3 = f.hand_world(g)
			var blade: Vector3 = PD.quat_of(w) * Vector3.UP
			f.draw_now()
			var du := Transform3D(up.draw_turn.basis, up.draw_turn.origin + up.draw_shift) * up.global_transform
			var df := Transform3D(fo.draw_turn.basis, fo.draw_turn.origin + fo.draw_shift) * fo.global_transform
			var hand_drawn: Vector3 = df * f.hand_point
			var elbow_up: Vector3 = du * fo.pa
			var elbow_fo: Vector3 = df * fo.ca
			var fore_dir: Vector3 = (hand_drawn - elbow_fo).normalized()
			var bend := rad_to_deg(fore_dir.angle_to(blade))
			var off_body: Vector3 = (Transform3D(w.draw_turn.basis, w.draw_turn.origin + w.draw_shift) * w.global_transform) * w.grip_main
			print("drawn %s %s: forearm %.0f deg off the blade, fist %.3f off the hand, elbow %.3f apart, the weapon drawn %.3f off its body" % [side, preset, bend, hand_drawn.distance_to(hand_body), elbow_up.distance_to(elbow_fo), off_body.distance_to(w.global_transform * w.grip_main)])
			t.check(bend > 25.0, "%s %s: the forearm drawn off the blade's line, the grip below the fist clear (%.0f deg)" % [side, preset, bend])
			t.check(hand_drawn.distance_to(hand_body) < 0.03, "%s %s: the fist drawn where the hand is (%.3f)" % [side, preset, hand_drawn.distance_to(hand_body)])
			t.check(elbow_up.distance_to(elbow_fo) < 0.03, "%s %s: the arm drawn whole at the elbow (%.3f)" % [side, preset, elbow_up.distance_to(elbow_fo)])
			t.check(off_body.distance_to(w.global_transform * w.grip_main) < 0.03, "%s %s: the weapon drawn where it is (%.3f)" % [side, preset, off_body.distance_to(w.global_transform * w.grip_main)])
			m.queue_free()
			await _steps(2)
