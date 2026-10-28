extends Node
## The fight camera with a fighter pinned to the arena wall: it holds still (no shake through the
## wall and back), never goes behind the wall, never sits inside his own body, and keeps the foe
## in sight. And it does not bob with his own blade.

var t

func _inside(f, eye: Vector3, pad: float) -> bool:
	for p in f.parts:
		if p.severed:
			continue
		var a: Vector3 = p.global_transform.affine_inverse() * eye
		var e: Vector3 = p.half_ext + Vector3.ONE * pad
		if absf(a.x) < e.x and absf(a.y) < e.y and absf(a.z) < e.z:
			return true
	return false

## He stands at `me_pos` facing `me_yaw` and looks along `look_yaw`, the foe shoving him into
## the wall and knocking him about; what the camera did, frame by frame.
func _pinned(me_pos: Vector3, me_yaw: float, foe_pos: Vector3, look_yaw: float) -> Dictionary:
	await get_tree().physics_frame
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none"}, "headless": true, "seed": 3, "decrees": [], "hazards": []})
	var me: Fighter = m.me.f
	me.teleport(me_pos)
	me.yaw = me_yaw
	me.mods.toughness = 5.0
	m.me.drive = func(_e): return {"look": {"yaw": me_yaw, "pitch": 0.0}}
	var e = m.spawn_fighter({"kind": "bot", "name": "Foe", "loadout": {"main": "gladius", "off": ""}, "team": Match.ENEMY_TEAM, "pos": foe_pos, "yaw": me_yaw + PI, "diff": 0.9})
	var of: Fighter = e.f
	of.yaw = me_yaw + PI
	of.mods.toughness = 5.0
	var cam := CameraRig.new()
	m.add_child(cam)
	var dt := 1.0 / 120.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var out := {"jumps": [], "turn": 0.0, "inside": 0, "behind_wall": 0, "hidden": 0, "n": 0}
	var prev_p := Vector3.ZERO
	var prev_d := Vector3.ZERO
	for i in 120 * 5:
		me.blood = 100.0
		of.blood = 100.0
		var into := Vector3(me.torso.global_position.x, 0, me.torso.global_position.z).normalized()
		of.torso.apply_central_force(into * 900.0)
		if i % 30 == 0:
			me.torso.apply_central_impulse(Vector3(rng.randf_range(-1, 1), 0.2, rng.randf_range(-1, 1)) * 25.0)
		await get_tree().physics_frame
		var low := of.torso.global_position
		for p in of.parts:
			if not p.severed and p.global_position.y < low.y:
				low = p.global_position
		var foe := [of.torso.global_position + Vector3(0, 0.25, 0), of.head.global_position + Vector3(0, 0.15 * of.S, 0), low]
		cam.follow(me, look_yaw, 0.0, dt, false, foe)
		var cp := cam.global_position
		var cd := -cam.global_basis.z
		if i > 120:
			out.n += 1
			out.jumps.append(cp.distance_to(prev_p))
			out.turn += rad_to_deg(cd.angle_to(prev_d))
			if _inside(me, cp, 0.07):
				out.inside += 1
			if Vector2(cp.x, cp.z).length() > Arena.RADIUS:
				out.behind_wall += 1
			if CameraRig._blocked(me, cp, foe) > 0.0:
				out.hidden += 1
		prev_p = cp
		prev_d = cd
	out.jumps.sort()
	m.queue_free()
	return out

func test_pinned_to_the_wall_the_camera_holds_still_and_sees() -> void:
	for sc in [["his back to the wall", Vector3(0, 0, 14.3), PI, Vector3(0, 0, 13.3), PI], ["flat against it", Vector3(0, 0, 14.65), PI, Vector3(0, 0, 13.7), PI], ["looking along the wall", Vector3(0, 0, 14.3), PI, Vector3(0, 0, 13.3), PI * 0.5]]:
		var r: Dictionary = await _pinned(sc[1], sc[2], sc[3], sc[4])
		var p95: float = r.jumps[int(r.jumps.size() * 0.95)]
		# (It shook a quarter of a metre a frame and turned 3 to 5 degrees a frame: 2,400 degrees
		# in seven seconds.)
		t.check(p95 < 0.05, "%s: no shake (%.3f m a frame)" % [sc[0], p95])
		t.check(r.turn < 300.0, "%s: the view holds (%.0f degrees in all)" % [sc[0], r.turn])
		t.check(r.behind_wall == 0, "%s: never behind the wall (%d frames)" % [sc[0], r.behind_wall])
		t.check(r.inside == 0, "%s: never inside his own body (%d frames)" % [sc[0], r.inside])
		t.check(r.hidden < r.n * 0.1, "%s: the foe in sight (hidden %d of %d frames)" % [sc[0], r.hidden, r.n])

func test_the_point_of_your_own_blade_does_not_lift_the_camera() -> void:
	await get_tree().physics_frame
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none"}, "headless": true, "seed": 3, "decrees": [], "hazards": []})
	var me: Fighter = m.me.f
	await get_tree().physics_frame
	# A point right behind his own trunk, as seen from behind him: hidden, but it is the blade's.
	var eye: Vector3 = me.torso.global_position - Vector3(sin(me.yaw), 0, cos(me.yaw)) * 2.5
	var behind: Vector3 = me.torso.global_position + Vector3(sin(me.yaw), 0, cos(me.yaw)) * 0.4
	var far := me.torso.global_position + Vector3(0, 9, 0)
	var pts := [far, far, far, behind]
	t.check(CameraRig._blocked(me, eye, pts) > 0.0, "a struck spot behind him counts as hidden")
	t.eq(CameraRig._blocked(me, eye, pts, 3), 0.0, "the point of his own blade does not")
	m.queue_free()
