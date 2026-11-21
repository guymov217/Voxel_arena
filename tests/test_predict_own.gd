extends Node
## A guest's own man in the game, ahead of the host's word of him (Match._predict_own over MovePredictor): a host and a guest in one
## room, the guest's keys reaching the host `d1` steps late and the host's snapshots of his man `d2` steps late. What he sees of his
## man is where the model has him, all his bodies together, and where the host says once the keys are let go.

var t

## (The two games each in a world of their own: in one, the guest's copy of the man stands where the host's does and holds him up.)
func _world() -> SubViewport:
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.size = Vector2i(64, 64)
	add_child(vp)
	return vp

func _pair(pos := Vector3(0, 0, 0)) -> Array:
	var host := Match.new()
	_world().add_child(host)
	host.setup({"mode": "training", "training": {"enemy": "none"}, "headless": true, "seed": 3, "role": "host"})
	host.me.f.teleport(Vector3(0, 0, -10))   # (out of his way: a man spawned into another is thrown clear)
	var e = host.spawn_fighter({"kind": "remote", "peer": 2, "name": "Friend", "loadout": {"main": "gladius"}, "team": 0, "pos": pos, "yaw": 0.0})
	var guest := Match.new()
	_world().add_child(guest)
	guest.setup({"mode": "training", "training": {"enemy": "none"}, "headless": true, "seed": 3, "role": "guest"})
	guest.guest_spawn(host._spawn_msg(e))
	var ge = guest.entity_by_id(e.id)
	guest.me = ge
	return [host, guest, e, ge]

func _end(pair: Array) -> void:
	Net.inputs.erase(2)
	(pair[0] as Match).get_parent().queue_free()
	(pair[1] as Match).get_parent().queue_free()

func _xz(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)

## `ticks` physics steps of the pair. The guest's hands (`keys.call(step)` -> [mx, mz]) go every second step, the host's snapshot of
## his man every second step. Returns what the guest's man and the host's did, step by step.
func _drive(pair: Array, keys: Callable, ticks: int, d1 := 5, d2 := 5, each := Callable()) -> Dictionary:
	var host: Match = pair[0]
	var guest: Match = pair[1]
	var e = pair[2]
	var ge = pair[3]
	var up := []
	var down := []
	var g := []
	var h := []
	var t_press := -1
	var press_at := -1
	for k in ticks:
		await get_tree().physics_frame
		if each.is_valid():
			each.call(k, pair)
		if k % 2 == 0:
			var kk: Array = keys.call(k)
			var gs := {"mx": kk[0], "mz": kk[1], "look": {"yaw": float(kk[3]) if kk.size() > 3 else 0.0, "pitch": 0.0}, "sprint": kk.size() > 2 and kk[2], "jump": kk.size() > 4 and kk[4]}
			gs.seq = guest.predictor.sent(guest.time - 1.0 / 120.0, gs)
			up.append([k + d1, PlayerInput.pack(gs)])
		while not up.is_empty() and int(up[0][0]) <= k:
			Net.inputs[2] = PlayerInput.unpack(up.pop_front()[1])
		if k % 2 == 1:
			down.append([k + d2, host.snapshot(false, 1).filter(func(r): return r[0] == e.id)])
		while not down.is_empty() and int(down[0][0]) <= k:
			guest.apply_snapshot(down.pop_front()[1])
		if is_instance_valid(ge.f) and is_instance_valid(e.f):
			g.append(_xz(ge.f.torso.global_position))
			h.append(_xz(e.f.torso.global_position))
	return {"g": g, "h": h}

## He presses forward: his man on the guest's screen is moving 2 cm before the host has even had the key (5 steps, 42 ms), and he
## is ahead of the host's picture of him while he walks, as far as the round trip.
func test_he_moves_at_once_and_is_ahead_of_the_host_while_he_walks() -> void:
	var pair := _pair()
	var guest: Match = pair[1]
	for i in 90:
		await get_tree().physics_frame   # (he settles on his feet)
	var keys := func(k: int) -> Array: return [0.0, 1.0] if k >= 100 else [0.0, 0.0]
	var r := await _drive(pair, keys, 300)
	var g: Array = r.g
	var h: Array = r.h
	var p0: Vector2 = g[99]
	var at := -1
	for k in range(100, g.size()):
		if ((g[k] as Vector2) - p0).length() > 0.02:
			at = k - 100
			break
	t.check(at >= 0 and at <= 5, "his man is 2 cm on %d steps after the key (%.0f ms; the host has it after 5 steps)" % [at, at * 8.33])
	var lead := ((g[250] as Vector2) - (h[250] as Vector2)).length()
	t.check(lead > 0.06 and lead < 0.2, "walking, he is %.0f cm ahead of the host's man (what the keys' way to the host is worth in walking: 5 steps)" % (lead * 100.0))
	var ahead: Vector2 = (g[250] as Vector2) - (h[250] as Vector2)
	t.check(ahead.y > 0.0 and absf(ahead.x) < 0.05, "ahead along the way he walks, not off to the side (%.2f, %.2f)" % [ahead.x, ahead.y])
	# (his whole man is shifted together: the head over the torso as the host has them)
	var ge = pair[3]
	var host_e = pair[2]
	var d_gap: float = (ge.f.head.global_position - ge.f.torso.global_position).length()
	var d_host: float = (host_e.f.head.global_position - host_e.f.torso.global_position).length()
	t.check(absf(d_gap - d_host) < 0.1, "and he is whole: the head is as far from the torso as the host has it (%.2f, %.2f)" % [d_gap, d_host])
	_end(pair)

## He lets go of the key: his man stops, and is where the host has him within a centimetre once it has come to rest.
func test_when_he_lets_go_he_ends_where_the_host_has_him() -> void:
	var pair := _pair()
	for i in 90:
		await get_tree().physics_frame
	var keys := func(k: int) -> Array: return [0.0, 1.0] if k >= 100 and k < 220 else [0.0, 0.0]
	var r := await _drive(pair, keys, 460)
	var g: Array = r.g
	var h: Array = r.h
	var end_d := ((g[g.size() - 1] as Vector2) - (h[h.size() - 1] as Vector2)).length()
	t.check(end_d < 0.01, "at rest he is %.1f mm from where the host has him" % (end_d * 1000.0))
	# he never goes back on his tracks: the man steps on every step he is walking, and after the key is let go he does not
	# overshoot the stop by more than a hand's breadth then come back
	var back := 0.0
	for k in range(120, 215):
		back = maxf(back, ((g[k - 1] as Vector2).y - (g[k] as Vector2).y))
	t.check(back < 0.003, "walking, he never steps back (%.1f mm at worst)" % (back * 1000.0))
	var top := 0.0
	for k in range(g.size()):
		top = maxf(top, (g[k] as Vector2).y)
	var over: float = top - (g[g.size() - 1] as Vector2).y
	t.check(over < 0.12, "and runs on at most %.0f cm past where he stops" % (over * 100.0))
	_end(pair)

## A wall (the arena's): the host's man is stopped by it, and the guest's is not shown into it more than a hand's breadth,
## nor does his picture jump about as it learns the wall is there.
func test_a_wall_holds_his_man_on_the_guests_screen_too() -> void:
	var pair := _pair()
	for i in 90:
		await get_tree().physics_frame
	var keys := func(k: int) -> Array: return [0.0, 1.0] if k >= 60 else [0.0, 0.0]
	var r := await _drive(pair, keys, 1100)
	var g: Array = r.g
	var h: Array = r.h
	var last_h: Vector2 = h[h.size() - 1]
	var last_g: Vector2 = g[g.size() - 1]
	var stopped := ((h[h.size() - 1] as Vector2) - (h[h.size() - 40] as Vector2)).length() < 0.05
	t.check(stopped, "the host's man was stopped (the wall, or the rim of the arena) at %.1f m" % last_h.length())
	if stopped:
		var into := (last_g - last_h).length()
		t.check(into < 0.06, "and on the guest's screen he is %.1f cm from where the host has him, pushing on it" % (into * 100.0))
		var jump := 0.0
		for k in range(1, g.size()):
			jump = maxf(jump, ((g[k] as Vector2) - (g[k - 1] as Vector2)).length())
		t.check(jump < 0.03, "and he never stepped more than %.1f cm in one step (a walk is 1.8)" % (jump * 100.0))
	_end(pair)

## A man who is down is the host's picture alone: his man is not walked on by the keys he holds.
func test_a_man_who_is_down_is_the_hosts_picture_alone() -> void:
	var pair := _pair()
	var host: Match = pair[0]
	var guest: Match = pair[1]
	var e = pair[2]
	for i in 90:
		await get_tree().physics_frame
	var keys := func(_k: int) -> Array: return [0.0, 1.0]
	await _drive(pair, keys, 60)
	e.f.fall(3.0, true)
	var r := await _drive(pair, keys, 120)
	var g: Array = r.g
	var h: Array = r.h
	var gap := ((g[g.size() - 1] as Vector2) - (h[h.size() - 1] as Vector2)).length()
	t.check(String(e.f.state) == "down" and gap < 0.1, "down on the sand he is where the host has him (%.1f cm), keys held or not" % (gap * 100.0))
	t.check(guest.pred_w < 0.01, "the prediction is eased right out (%.2f)" % guest.pred_w)
	_end(pair)

## What the host says of his guest's man: the input he walks by, the steps, where he goes and how fast, his yaw and pace.
func test_the_snapshot_of_a_guests_man_carries_the_word() -> void:
	var pair := _pair()
	var host: Match = pair[0]
	var e = pair[2]
	for i in 90:
		await get_tree().physics_frame
	Net.inputs[2] = PlayerInput.unpack(PlayerInput.pack({"mz": 1.0, "seq": 42, "look": {"yaw": 0.0, "pitch": 0.0}}))
	for i in 12:
		await get_tree().physics_frame
	var rows: Array = host.snapshot(true, 1).filter(func(r): return r[0] == e.id)
	var row: Array = rows[0]
	t.check(row.size() == 6 and row[5] is PackedFloat32Array and (row[5] as PackedFloat32Array).size() == 7, "his row has the word as its last element")
	var w: PackedFloat32Array = row[5]
	t.check(int(w[0]) == 42 and int(w[1]) >= 10, "it names input 42 and the steps he has walked by it (%d)" % int(w[1]))
	t.check(w[3] > 0.5 and w[5] > 0.5, "he is going forward (%.2f m/s) at a pace (%.2f)" % [w[3], w[5]])
	# the host's own man has no such word
	var mine: Array = host.snapshot(true, 1).filter(func(r): return r[0] == host.me.id)
	t.check(mine.size() == 1 and (mine[0] as Array).size() == 5, "and the host's own man's row has no word (he is not walked by another)")
	_end(pair)

## A host's man is knocked down while he walks: his picture is eased to the host's, with no jump, and no step against the way
## the host's man went.
func test_a_man_knocked_down_is_eased_to_the_hosts_picture() -> void:
	var pair := _pair()
	Net.inputs[2] = PlayerInput.unpack(PlayerInput.pack({"seq": 1, "look": {"yaw": 0.0, "pitch": 0.0}}))
	for i in 120:
		await get_tree().physics_frame
	var keys := func(k: int) -> Array: return [0.0, 1.0] if k >= 60 and k < 400 else [0.0, 0.0]
	var each := func(k: int, p: Array) -> void:
		if k == 140:
			p[2].f.fall(2.0, true)
	var r := await _drive(pair, keys, 600, 5, 5, each)
	var g: Array = r.g
	var h: Array = r.h
	var worst_step := 0.0
	var worst_back := 0.0
	for k in range(62, g.size()):
		var st: Vector2 = (g[k] as Vector2) - (g[k - 1] as Vector2)
		var sh: Vector2 = (h[k] as Vector2) - (h[k - 1] as Vector2)
		worst_step = maxf(worst_step, st.length())
		if sh.length() > 0.004 and st.dot(sh) < -0.002:
			worst_back = maxf(worst_back, -st.dot(sh.normalized()))
	t.check(worst_step < 0.04, "no step of his man is more than %.1f cm, in the fall too" % (worst_step * 100.0))
	t.check(worst_back < 0.005, "and none goes against the way the host's man went (%.1f mm)" % (worst_back * 1000.0))
	t.check(((g[g.size() - 1] as Vector2) - (h[h.size() - 1] as Vector2)).length() < 0.02, "and he ends where the host has him")
	_end(pair)

## Running (the pace stays the host's word the whole way, a runner's stride never reads as off the sand) and a turn of the eyes
## while he walks: the same, with the model turning his body as the host does.
func test_running_and_turning_he_is_as_smooth_as_walking() -> void:
	var pair := _pair()
	Net.inputs[2] = PlayerInput.unpack(PlayerInput.pack({"seq": 1, "look": {"yaw": 0.0, "pitch": 0.0}}))
	for i in 120:
		await get_tree().physics_frame
	var keys := func(k: int) -> Array:
		var yaw := clampf(float(k - 140) / 60.0, 0.0, 1.0) * 1.5   # (a turn of 1.5 rad over half a second)
		return [0.0, 1.0, true, yaw] if k >= 60 and k < 300 else [0.0, 0.0, false, yaw]
	var r := await _drive(pair, keys, 520)
	var g: Array = r.g
	var h: Array = r.h
	var worst_step := 0.0
	var worst_back := 0.0
	for k in range(62, g.size()):
		var st: Vector2 = (g[k] as Vector2) - (g[k - 1] as Vector2)
		var sh: Vector2 = (h[k] as Vector2) - (h[k - 1] as Vector2)
		worst_step = maxf(worst_step, st.length())
		if sh.length() > 0.004 and st.dot(sh) < -0.002:
			worst_back = maxf(worst_back, -st.dot(sh.normalized()))
	t.check(worst_step < 0.045, "no step of his man is more than %.1f cm at a run (3.1 cm a step)" % (worst_step * 100.0))
	t.check(worst_back < 0.005, "none goes against the host's man's way (%.1f mm)" % (worst_back * 1000.0))
	t.check(((g[g.size() - 1] as Vector2) - (h[h.size() - 1] as Vector2)).length() < 0.02, "he ends where the host has him after the run and the turn (%.1f mm)" % (((g[g.size() - 1] as Vector2) - (h[h.size() - 1] as Vector2)).length() * 1000.0))
	_end(pair)

## A jump while he walks: nothing steers him in the air, and the model goes on as he was going, so his picture is not drawn back to
## the host's for the length of the jump and out again at the landing: no step of him is large, none goes the wrong way, and he
## is ahead of the host's man in the air as he was on the sand.
func test_a_jump_does_not_draw_him_back() -> void:
	var pair := _pair()
	Net.inputs[2] = PlayerInput.unpack(PlayerInput.pack({"seq": 1, "look": {"yaw": 0.0, "pitch": 0.0}}))
	for i in 120:
		await get_tree().physics_frame
	var keys := func(k: int) -> Array:
		return [0.0, 1.0, false, 0.0, k == 140 or k == 141] if k >= 60 and k < 400 else [0.0, 0.0]
	var airborne := []
	var each := func(_k: int, p: Array) -> void:
		airborne.append(p[2].f.in_air())
	var r := await _drive(pair, keys, 520, 5, 5, each)
	var g: Array = r.g
	var h: Array = r.h
	var first := airborne.find(true)
	var last := airborne.rfind(true)
	t.check(first >= 0 and last - first > 20, "he jumped (%d steps off the sand)" % (last - first))
	var worst_step := 0.0
	var worst_back := 0.0
	var lead_in_air := 0.0
	for k in range(62, g.size()):
		var st: Vector2 = (g[k] as Vector2) - (g[k - 1] as Vector2)
		var sh: Vector2 = (h[k] as Vector2) - (h[k - 1] as Vector2)
		worst_step = maxf(worst_step, st.length())
		if sh.length() > 0.004 and st.dot(sh) < -0.002:
			worst_back = maxf(worst_back, -st.dot(sh.normalized()))
	if first >= 0:
		lead_in_air = ((g[(first + last) / 2] as Vector2) - (h[(first + last) / 2] as Vector2)).y
	t.check(worst_step < 0.04, "no step of his man is more than %.1f cm, in the jump too" % (worst_step * 100.0))
	t.check(worst_back < 0.005, "none goes against the way the host's man went (%.1f mm)" % (worst_back * 1000.0))
	t.check(lead_in_air > 0.04, "and in the air he is %.0f cm ahead of the host's man, as on the sand" % (lead_in_air * 100.0))
	_end(pair)
