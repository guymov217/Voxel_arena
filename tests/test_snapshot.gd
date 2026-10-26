extends Node
## The snapshot the host sends its guests: every body to within 2 mm and a hair of its turn in
## half the bytes; a fighter's state only now and then; the dead lying still sent once a second;
## and a guest's puppet ends up where the host's fighter is.

var t

func _steps(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func test_a_body_packs_to_within_two_millimetres() -> void:
	var b := PackedByteArray()
	b.resize(14)
	for k in 50:
		var tr := Transform3D(Basis(Quaternion(Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5).normalized(), randf() * TAU)), Vector3(randf_range(-20, 20), randf_range(-2, 30), randf_range(-20, 20)))
		Match.pack_xf(b, 0, tr)
		var back := Match.unpack_xf(b, 0)
		t.check(back.origin.distance_to(tr.origin) < 0.002, "place within 2 mm (%.4f m)" % back.origin.distance_to(tr.origin))
		var dq: float = back.basis.get_rotation_quaternion().angle_to(tr.basis.get_rotation_quaternion())
		t.check(dq < 0.002, "turn within 0.1 degree (%.4f rad)" % dq)
		if k > 3:
			break

func test_less_on_the_wire_and_the_still_left_out() -> void:
	seed(6)   # the game's dice (randf) the same whatever tests ran before
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none"}, "headless": true, "seed": 3})
	var e = m.spawn_fighter({"kind": "bot", "name": "V", "loadout": {"main": "gladius", "off": "roundShield"}, "team": 1, "pos": Vector3(2, 0, 2), "yaw": 0.0})
	e.erase("bot")
	e.drive = func(_e): return {}
	await _steps(120)
	var ow := []
	for side in ["R", "L"]:
		var wp = e.f.weapons.get(side)
		if wp:
			var q: Quaternion = wp.global_transform.basis.get_rotation_quaternion()
			ow.append([side, wp.global_position.x, wp.global_position.y, wp.global_position.z, q.x, q.y, q.z, q.w])
	var old := [e.id, e.f.snapshot(), ow, e.f.status(), []]
	var full: Array = m.snapshot(true)
	var row: Array = full.filter(func(r): return r[0] == e.id)[0]
	t.check(var_to_bytes(row).size() < var_to_bytes(old).size() * 0.6, "a fighter's row is much smaller (%d bytes, was %d)" % [var_to_bytes(row).size(), var_to_bytes(old).size()])
	# Standing still: after the first, he is not sent again until a second has gone by.
	e.f.die("test")
	# Down and come to rest (how long the fall and the shield take to settle is dice; a corpse
	# at rest is the case): at most ten seconds for every part to lie still.
	await _steps(120)
	for k in 100:
		var moving := false
		for p in e.f.parts:
			if p.linear_velocity.length() > 0.02 or p.angular_velocity.length() > 0.05:
				moving = true
				break
		if not moving:
			break
		await _steps(12)
	await _steps(120)
	var sent := 0
	var with_status := 0
	for i in 120:
		m.tick += 1
		for r in m.snapshot(false):
			if r[0] == e.id:
				sent += 1
				if r[3] != null:
					with_status += 1
		await get_tree().physics_frame
	t.check(sent <= 12, "a dead man settled on the sand is hardly sent at all (%d of 120 snapshots)" % sent)
	m.queue_free()

func test_status_comes_a_few_times_a_second() -> void:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none"}, "headless": true, "seed": 3})
	var e = m.spawn_fighter({"kind": "bot", "name": "V", "loadout": {}, "team": 1, "pos": Vector3(2, 0, 2), "yaw": 0.0})
	e.erase("bot")
	e.drive = func(_e): return {"mz": 1.0}
	await _steps(30)
	var rows := 0
	var st := 0
	for i in 120:
		await get_tree().physics_frame
		if m.tick % Match.SNAP_EVERY == 0:
			for r in m.snapshot(false):
				if r[0] == e.id:
					rows += 1
					if r[3] != null:
						st += 1
	t.check(rows >= 35, "a moving fighter goes out every snapshot (%d)" % rows)
	t.check(st >= 6 and st <= 12, "his state about 8 times a second (%d)" % st)
	m.queue_free()

func test_a_guest_puppet_follows_the_snapshot() -> void:
	var host := Match.new()
	add_child(host)
	host.setup({"mode": "training", "training": {"enemy": "none"}, "headless": true, "seed": 3})
	var e = host.spawn_fighter({"kind": "bot", "name": "V", "loadout": {}, "team": 1, "pos": Vector3(2, 0, 2), "yaw": 0.0})
	e.erase("bot")
	e.drive = func(_e): return {"mz": 1.0}
	await _steps(60)
	var guest := Match.new()
	add_child(guest)
	guest.setup({"mode": "training", "training": {"enemy": "none"}, "headless": true, "seed": 3, "role": "guest"})
	guest.guest_spawn(host._spawn_msg(e))
	var ge = guest.entity_by_id(e.id)
	t.check(ge != null, "the guest has him")
	if ge == null:
		host.queue_free(); guest.queue_free()
		return
	var at := Vector3.ZERO
	for i in 60:
		await get_tree().physics_frame
		if i % 3 == 0:
			guest.apply_snapshot(host.snapshot(false).filter(func(r): return r[0] == e.id))
			at = e.f.torso.global_position
	await _steps(4)
	var d: float = ge.f.torso.global_position.distance_to(at)
	t.check(d < 0.03, "the guest's puppet comes to where the host's man was in the last snapshot (%.2f m off)" % d)
	host.queue_free()
	guest.queue_free()

## A beast's status goes out packed like a man's (with its jaw), and a guest takes it in.
func test_a_beasts_packed_status_comes_through() -> void:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none"}, "headless": true, "seed": 3})
	var e = m.spawn_beast({"beast": "crocodile", "team": Match.ENEMY_TEAM, "pos": Vector3(3, 0.1, 3), "yaw": 0.0})
	var b: Beast = e.f
	await get_tree().physics_frame
	b.jaw_t = 0.3
	b.torso.hp = 42.0
	var packed: Array = b.status_packed()
	t.eq(packed.size(), 7, "blood, breath, state, the parts' hp, death's door, the grip and the jaw")
	b.jaw_t = 0.0
	b.torso.hp = 100.0
	b.apply_status(packed)
	t.check(absf(b.torso.hp - 42.0) < 0.01, "the hp came through (%.1f)" % b.torso.hp)
	t.check(b.jaw_t > 0.2, "and the jaw (%.2f)" % b.jaw_t)
	# A man's: whether both his hands are on one haft goes to his guest (its input reads it).
	var me: Fighter = m.me.f
	me.equip("R", Data.preset("warhammer"))
	me.toggle_grip()
	var g: Fighter = m.spawn_fighter({"kind": "bot", "name": "Copy", "loadout": {"main": "", "off": ""}, "team": 0, "pos": Vector3(-3, 0.1, 3), "yaw": 0.0}).f
	g.apply_status(me.status_packed())
	t.check(me.two_handed and g.net_two_handed, "the grip on the haft comes through to the guest's copy")
	m.queue_free()
