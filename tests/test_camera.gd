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

## His own head or arm in the way of the blow is seen through, and solid again once it is out of
## the way (user: sometimes the player's own body hides where his weapon lands on the foe); but
## never his trunk or legs, never for his own blade's point, a foe low on the sand or the camera
## pressed into him (user: sometimes the player turns transparent for no reason).
func test_his_own_arm_in_the_way_of_the_blow_is_seen_through() -> void:
	await get_tree().physics_frame
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none"}, "headless": true, "seed": 3, "decrees": [], "hazards": []})
	var me: Fighter = m.me.f
	await get_tree().physics_frame
	var arm: VoxelPart = me.by_name["upperArmR"]
	var fwd := Vector3(sin(me.yaw), 0, cos(me.yaw))
	var at := arm.global_position
	var eye: Vector3 = at - fwd * 2.5
	var struck: Vector3 = at + fwd * 1.2
	var far := me.torso.global_position + Vector3(0, 9, 0)
	var hid: Dictionary = CameraRig._hiders(me, eye, [far, far, far, struck])
	t.check(hid.has(arm), "his arm is on the line to the spot struck in front of it")
	t.check(not hid.has(me.torso), "his trunk never fades")
	t.check(not hid.has(me.by_name["shinL"]), "nor his legs")
	var low := me.torso.global_position + fwd * 1.0 + Vector3(0, -0.6, 0)
	t.check(CameraRig._hiders(me, me.torso.global_position - fwd * 2.5 + Vector3(0, 0.6, 0), [low, low, low, low]).is_empty(), "a foe low on the sand fades nothing")
	t.check(CameraRig._hiders(me, eye, [far, far, far, far, struck], 4).is_empty(), "nor his own blade's point")
	t.check(CameraRig._hiders(me, arm.global_position, [struck, struck, far, struck]).is_empty(), "nor anything with the camera pressed into him")
	var cam := CameraRig.new()
	m.add_child(cam)
	cam.hiders = hid
	for i in 30:
		cam._fade(me, 1.0 / 60.0)
	t.check(absf(arm.see_through - CameraRig.SEE_THROUGH) < 0.01, "in the way, it is seen through (%.2f)" % arm.see_through)
	t.check(arm.mmi == null or absf(arm.mmi.transparency - CameraRig.SEE_THROUGH) < 0.01, "drawn so")
	t.eq(me.torso.see_through, 0.0, "what is not in the way stays solid")
	cam.hiders = {}
	for i in 60:
		cam._fade(me, 1.0 / 60.0)
	t.eq(arm.see_through, 0.0, "out of the way, solid again")
	cam.hiders = hid
	for i in 30:
		cam._fade(me, 1.0 / 60.0)
	cam.clear_fade()
	t.eq(arm.see_through, 0.0, "and solid at once for a kill cam")
	m.queue_free()

## In a real fight (a bot duel, the camera following the player as in play) his trunk and legs are
## never seen through, and his head and arms only now and then. Over three fights: in one fight
## alone the share runs from an eighth to more than half, by how much of it is fought chest to
## chest (one fight, the share went over the mark when an earlier test changed how it went).
func test_in_a_fight_he_stays_solid() -> void:
	var all_frames := 0
	var all_any := 0
	for sd in [5, 1, 2]:
		var m := Match.new()
		add_child(m)
		m.setup({"mode": "training", "training": {"enemy": "gladiator", "difficulty": 0.8}, "seed": sd, "decrees": [], "hazards": [], "autopilot": true})
		var me: Fighter = m.me.f
		var body_faded := 0
		var any_faded := 0
		var frames := 0
		for i in 120 * 12:
			await get_tree().physics_frame
			if not me.alive:
				break
			frames += 1
			var b := false
			for n in ["torso", "thighL", "thighR", "shinL", "shinR"]:
				var p = me.by_name.get(n)
				b = b or (p != null and p.see_through > 0.0)
			if b:
				body_faded += 1
			for p in me.parts:
				if p.see_through > 0.0:
					any_faded += 1
					break
		t.eq(body_faded, 0, "his trunk and legs never seen through (fight %d, of %d frames)" % [sd, frames])
		all_frames += frames
		all_any += any_faded
		m.queue_free()
		await get_tree().physics_frame
	t.check(float(all_any) / maxf(1, all_frames) < 0.35, "his head or an arm seen through %d of %d frames in three fights" % [all_any, all_frames])

## The view goes where the mouse points, whatever the foe: a giant's head high over the frame does
## not turn it up to his face, nor does it go round him close in (user: stop the camera moving by
## itself and locking onto the giant's face; the player controls the camera always, only a corner
## of the arena moves it).
func test_the_view_goes_where_the_mouse_points() -> void:
	await get_tree().physics_frame
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none"}, "headless": true, "seed": 3, "decrees": [], "hazards": []})
	var me: Fighter = m.me.f
	await get_tree().physics_frame
	var cam := CameraRig.new()
	m.add_child(cam)
	var c := me.torso.global_position
	var fwd := Vector3(sin(me.yaw), 0, cos(me.yaw))
	# A giant a stride in front of him: his middle, his head four metres up, his feet.
	var pts := [c + fwd * 1.6 + Vector3(0, 1.0, 0), c + fwd * 1.6 + Vector3(0, 4.0, 0), c + fwd * 1.6 - Vector3(0, c.y, 0)]
	for i in 240:
		cam.follow(me, me.yaw, 0.0, 1.0 / 60.0, false, pts)
	var d := (cam.look - cam.eye).normalized()
	var off := wrapf(atan2(d.x, d.z) - me.yaw, -PI, PI)
	t.check(absf(off) < 0.03, "it looks the way he faces (off by %.3f rad)" % off)
	t.check(d.y < 0.0, "as low as the mouse has it, not up at the giant's face (%.2f)" % d.y)
	t.check(cam.shift.length() < 0.001, "and it has not gone round him (%s)" % str(cam.shift))
	m.queue_free()
