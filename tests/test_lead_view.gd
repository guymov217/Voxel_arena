extends Node
## The others on a guest's screen (Match._lead_for over Lead): a host and a guest in one room, a friend walking on the host's and the
## host's snapshots of him `d2` steps late. The guest draws him ahead of the snapshot by his pace over the round trip and a snapshot's
## wait, so that a blow of the guest's, which reaches the host `d1` steps late, meets him nearer to where the picture has him; his own
## man (what the guest plays) and a man who lies on the sand are drawn as the host's snapshots have them.

var t

func _world() -> SubViewport:
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.size = Vector2i(64, 64)
	add_child(vp)
	return vp

## A host with two friends (peers 2 and 3) and a guest that has built both: his own is the first, the other the second.
func _pair() -> Array:
	var host := Match.new()
	_world().add_child(host)
	host.setup({"mode": "training", "training": {"enemy": "none"}, "headless": true, "seed": 3, "role": "host"})
	host.me.f.teleport(Vector3(0, 0, -10))
	var e1 = host.spawn_fighter({"kind": "remote", "peer": 2, "name": "Me", "loadout": {"main": "gladius"}, "team": 0, "pos": Vector3(-6, 0, 0), "yaw": 0.0})
	var e2 = host.spawn_fighter({"kind": "remote", "peer": 3, "name": "Friend", "loadout": {"main": "gladius"}, "team": 0, "pos": Vector3(4, 0, -6), "yaw": 0.0})
	var guest := Match.new()
	_world().add_child(guest)
	guest.setup({"mode": "training", "training": {"enemy": "none"}, "headless": true, "seed": 3, "role": "guest"})
	guest.guest_spawn(host._spawn_msg(e1))
	guest.guest_spawn(host._spawn_msg(e2))
	var g1 = guest.entity_by_id(e1.id)
	guest.me = g1
	return [host, guest, e1, e2, g1, guest.entity_by_id(e2.id)]

func _end(pair: Array) -> void:
	Net.inputs.erase(2)
	Net.inputs.erase(3)
	(pair[0] as Match).get_parent().queue_free()
	(pair[1] as Match).get_parent().queue_free()

func _xz(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)

## `ticks` physics steps: the friend (peer 3) walks along z by `keys.call(step)` (mz); every second step the host's snapshot of him is on
## its way, `d2` steps late. Returns the host's man and the guest's picture of him, step by step.
func _walk(pair: Array, keys: Callable, ticks: int, d2 := 5) -> Dictionary:
	var host: Match = pair[0]
	var guest: Match = pair[1]
	var e2 = pair[3]
	var g2 = pair[5]
	var look := {"yaw": 0.0, "pitch": 0.0}
	var down := []
	var g := []
	var h := []
	for k in ticks:
		await get_tree().physics_frame
		var mz: float = keys.call(k)
		Net.inputs[3] = PlayerInput.unpack(PlayerInput.pack({"mx": 0.0, "mz": mz, "look": look, "sprint": false, "jump": false}))
		if k % 2 == 1:
			down.append([k + d2, host.snapshot(false, 1).filter(func(r): return r[0] == e2.id)])
		while not down.is_empty() and int(down[0][0]) <= k:
			guest.apply_snapshot(down.pop_front()[1])
		if is_instance_valid(g2.f) and is_instance_valid(e2.f):
			g.append(_xz(g2.f.torso.global_position))
			h.append(_xz(e2.f.torso.global_position))
	return {"g": g, "h": h}

## How far the picture of the man is, while he walks, from where he is `ahead` steps on (a blow of the guest's reaching the host then).
func _off(r: Dictionary, from: int, to: int, ahead := 5) -> float:
	var g: Array = r.g
	var h: Array = r.h
	var tot := 0.0
	var n := 0
	for k in range(from, mini(to, g.size() - ahead)):
		tot += ((g[k] as Vector2) - (h[k + ahead] as Vector2)).length()
		n += 1
	return tot / maxf(1.0, float(n))

## A man walking on the host's is drawn nearer to where his blows will meet him with the lead than without it.
func test_a_man_walking_is_drawn_nearer_to_where_a_blow_meets_him() -> void:
	var was := Net.ping_ms
	Net.ping_ms = 5.0 * 2.0 * 8.33   # (the keys' way and the snapshots' way, five steps each)
	var keys := func(k: int) -> float: return 1.0 if k >= 40 else 0.0
	var pair := _pair()
	for i in 90:
		await get_tree().physics_frame
	(pair[1] as Match).lead_on = false
	var off := await _walk(pair, keys, 260)
	_end(pair)
	pair = _pair()
	for i in 90:
		await get_tree().physics_frame
	var on := await _walk(pair, keys, 260)
	var a := _off(off, 150, 255)
	var b := _off(on, 150, 255)
	t.check(a > 0.08, "without the lead the picture of a walking man is %.0f cm from where a blow of his meets him" % (a * 100.0))
	t.check(b < a * 0.6, "with it %.0f cm (%.0f%% of that)" % [b * 100.0, b / maxf(a, 1e-6) * 100.0])
	# (a man's own picture along his way: the lead is along the way he walks, not off to the side)
	var g: Array = on.g
	var h: Array = on.h
	var side := absf((g[240] as Vector2).x - (h[240] as Vector2).x)
	t.check(side < 0.03, "and along his way, not off to the side (%.1f cm across)" % (side * 100.0))
	# (the whole man: the head over the torso as the host has them)
	var g2 = pair[5]
	var e2 = pair[3]
	var dg: float = (g2.f.head.global_position - g2.f.torso.global_position).length()
	var dh: float = (e2.f.head.global_position - e2.f.torso.global_position).length()
	t.check(absf(dg - dh) < 0.1, "and he is whole: the head as far from the torso as the host has it (%.2f, %.2f)" % [dg, dh])
	Net.ping_ms = was
	_end(pair)

## He stops: the picture does not run on past where he stops by more than the lead's most, and is where the host has him once he is still.
func test_a_man_who_stops_is_not_drawn_past_his_stop() -> void:
	var was := Net.ping_ms
	Net.ping_ms = 5.0 * 2.0 * 8.33
	var pair := _pair()
	for i in 90:
		await get_tree().physics_frame
	var keys := func(k: int) -> float: return 1.0 if k >= 40 and k < 200 else 0.0
	var r := await _walk(pair, keys, 520)
	var g: Array = r.g
	var h: Array = r.h
	var top := -1e9
	for k in range(g.size()):
		top = maxf(top, (g[k] as Vector2).y)
	var stop_y: float = (h[h.size() - 1] as Vector2).y
	t.check(top - stop_y < Lead.MAX + 0.04, "he is drawn no more than %.0f cm past where he stops (%.1f cm)" % [(Lead.MAX + 0.04) * 100.0, (top - stop_y) * 100.0])
	var end_d := ((g[g.size() - 1] as Vector2) - (h[h.size() - 1] as Vector2)).length()
	t.check(end_d < 0.01, "at rest he is %.1f mm from where the host has him" % (end_d * 1000.0))
	Net.ping_ms = was
	_end(pair)

## The man the guest plays is not led (MovePredictor has him), and a man down on the sand is drawn where the host has him.
func test_his_own_man_and_a_man_down_are_not_led() -> void:
	var was := Net.ping_ms
	Net.ping_ms = 5.0 * 2.0 * 8.33
	var pair := _pair()
	for i in 90:
		await get_tree().physics_frame
	var guest: Match = pair[1]
	var l = (pair[4] as Dictionary).get("lead")
	t.check(l == null, "the guest's own man has no lead kept")
	var keys := func(k: int) -> float: return 1.0 if k >= 40 else 0.0
	var e2 = pair[3]
	var g2 = pair[5]
	await _walk(pair, keys, 160)
	var lead2: Lead = (g2 as Dictionary).get("lead")
	t.check(lead2 != null and lead2.cur.length() > 0.02, "a man walking has one (%.1f cm)" % ((lead2.cur.length() * 100.0) if lead2 != null else -1.0))
	# He is felled on the host's and the guest hears of it: the picture is the host's from here (the lead eases away).
	e2.f.fall(4.0, true)
	var r := await _walk(pair, func(_k: int) -> float: return 0.0, 120)
	var lead_left: float = lead2.cur.length() if lead2 != null else 0.0
	t.check(lead_left < 0.005, "a man down is drawn as the host has him (%.1f cm left)" % (lead_left * 100.0))
	Net.ping_ms = was
	_end(pair)
