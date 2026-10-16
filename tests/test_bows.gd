extends Node
## Bows and crossbows: an arrow strikes as hard as the bow was drawn and stays in point first;
## the bow is hard to shoot well (short draws, long holds, tired arms and moving all throw it
## off); arrows and bolts fly fast and near straight.

var t

func _match() -> Match:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none"}, "headless": true, "seed": 3})
	m.me.f.teleport(Vector3(0, 0, -10))
	return m

func _victim(m: Match, pos: Vector3) -> Fighter:
	var e = m.spawn_fighter({"kind": "bot", "name": "V", "loadout": {}, "team": 1, "pos": pos, "yaw": PI})
	e.erase("bot")
	e.drive = func(_e): return {}
	return e.f

func test_an_arrow_hurts_as_hard_as_the_bow_was_drawn() -> void:
	var m := _match()
	var lost := []
	for pw in [0.25, 1.0]:
		var v := _victim(m, Vector3(pw * 8.0, 0, 0))
		for i in 20:
			await get_tree().physics_frame
		var hp0 := v.total_hp()
		var p: Vector3 = v.torso.global_position + Vector3(0, 0, v.torso.half_ext.z * 0.5)
		m.throwables.explode("pot_arrow", p, m.me.f, Vector3(0, 0, 1), v, v.torso, pw)
		lost.append(hp0 - v.total_hp())
	t.check(lost[1] > lost[0] * 2.0, "a full draw hits much harder than a quarter one (%.1f vs %.1f hp)" % [lost[1], lost[0]])
	m.queue_free()

func test_a_stuck_arrow_is_point_first_in_the_wound() -> void:
	var m := _match()
	var v := _victim(m, Vector3(0, 0, 0))
	for i in 20:
		await get_tree().physics_frame
	var dir := Vector3(0, 0, -1)
	var p: Vector3 = v.torso.global_position + Vector3(0, 0.1, v.torso.half_ext.z * 0.7)
	m.throwables.explode("pot_arrow", p, m.me.f, dir, v, v.torso, 1.0)
	t.check(v.torso.stuck.size() == 1, "the arrow stays in him")
	if v.torso.stuck.size() == 1:
		var a: Node3D = v.torso.stuck[0]
		var tip_dir: Vector3 = a.global_transform.basis.z.normalized()
		t.check(tip_dir.dot(dir) > 0.9, "its point goes in first (%.2f)" % tip_dir.dot(dir))
		var tip_l: Vector3 = v.torso.global_transform.affine_inverse() * (a.global_transform * Vector3(0, 0, 0.32))
		var h: Vector3 = v.torso.half_ext
		t.check(absf(tip_l.x) < h.x and absf(tip_l.y) < h.y and absf(tip_l.z) < h.z, "the point is inside him")
		var tail_l: Vector3 = v.torso.global_transform.affine_inverse() * (a.global_transform * Vector3(0, 0, -0.26))
		t.check(absf(tail_l.z) > h.z, "and the fletching stands out of him")
	m.queue_free()

func test_the_bow_is_hard_to_shoot_well() -> void:
	var m := _match()
	var f: Fighter = m.me.f
	var th: Throwables = m.throwables
	var best := th._bow_wobble(f, 1.0, 0.5)
	t.check(th._bow_wobble(f, 0.4, 0.5) > best * 2.0, "a short draw scatters")
	t.check(th._bow_wobble(f, 1.0, 3.0) > best * 2.0, "so does a full draw held too long")
	f.stamina = 5.0
	t.check(th._bow_wobble(f, 1.0, 0.5) > best * 2.0, "and a tired arm")
	f.stamina = 100.0
	t.check(Throwables.ARROW_SPEED.x + Throwables.ARROW_SPEED.y > 50.0 and Throwables.BOLT_SPEED > 50.0, "arrows and bolts fly fast and flat")
	m.queue_free()

## A guest's archer is the host's own archer: the bow drawn on his button, and the arrow loosed
## at the point his crosshair is on, sent in his input packet (once he could not aim at all).
func test_a_guest_looses_at_his_own_crosshair() -> void:
	var m := _match()
	var e = m.spawn_fighter({"kind": "remote", "peer": 77, "name": "Guest", "loadout": {"main": "bow"}, "team": 0, "pos": Vector3(0, 0, 0), "yaw": 0.0})
	var mark := Vector3(6.0, 1.2, 10.0)   # off to his right, not where he faces
	var arrow = null
	var drew := 0.0
	for i in 220:
		var inp := {"look": {"yaw": atan2(mark.x, mark.z), "pitch": 0.0}, "main": {"x": 0.1, "y": 0.2}, "power": i < 150, "aimAt": mark}
		Net.inputs[77] = PlayerInput.unpack(PlayerInput.pack(inp))
		await get_tree().physics_frame
		var bow: Weapon = e.f.weapons.R
		if bow:
			drew = maxf(drew, float(bow.get_meta("draw", 0.0)))
		for it in m.items.list:
			if arrow == null and str(it.type).begins_with("pot_arrow") and it.owner == e.f:
				arrow = it.duplicate()
	t.check(drew > 0.5, "his button drew the bow (draw %.2f)" % drew)
	t.check(arrow != null, "an arrow was loosed")
	if arrow:
		var v: Vector3 = arrow.vel
		var want: Vector3 = mark - e.f.torso.global_position
		var ang := rad_to_deg(Vector2(v.x, v.z).angle_to(Vector2(want.x, want.z)))
		t.check(absf(ang) < 10.0, "toward his crosshair, not where he faced (%.1f degrees off)" % ang)
	Net.inputs.erase(77)
	m.queue_free()
