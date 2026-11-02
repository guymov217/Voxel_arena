extends Node
## Two-handed swings as in the user's video (1026): a longsword swept round in wide strokes
## with the button held, and how often both hands are on the haft, how long the off hand is off
## it, and whether the blade runs through his own head. Cases (CASES): "start" (the bout begins
## with it, both hands on), "pickup" (taken up off the sand with G and swung at once), "pickup2"
## (taken up, swung two seconds later), "regrip" (H lets go, H again in the middle of the
## strokes). `-- --probe twohandvid`. WEAPON (longsword), SWEEP_S (8).

var m: Match

func _seg_dist(p: Vector3, a: Vector3, b: Vector3) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(1e-6, ab.length_squared()), 0.0, 1.0)
	return p.distance_to(a + ab * t)

## The blade's line: from the main grip to the far end of the weapon.
func _blade(w: Weapon) -> Array:
	var box: AABB = w.local_box()
	return [w.global_transform * w.grip_main, w.global_transform * Vector3(w.grip_main.x, box.end.y, w.grip_main.z)]

## A wide stroke round and round, as a mouse sweeps it: out to the right low, up over the head,
## across to the left, down and back (the hand's mark as the input gives it).
func _sweep(t: float) -> Dictionary:
	var a := t * TAU / 2.2
	return {"x": 1.1 * cos(a), "y": 0.35 + 1.0 * sin(a)}

func _run(case_: String, design: Dictionary, sweep_s: float) -> void:
	m = Match.new()
	add_child(m)
	var start_with := case_ == "start" or case_ == "regrip" or case_ == "onehand"
	m.setup({"mode": "training", "training": {"enemy": "none", "respawn": false}, "headless": true, "seed": 2, "decrees": [], "hazards": [],
		"loadout": {"main": design if start_with else "", "off": ""}})
	var f: Fighter = m.me.f
	var st := {"t": 0.0, "sweep": false, "grab": false, "grip": false}
	m.me.drive = func(_e):
		var hand: Dictionary = _sweep(float(st.t)) if st.sweep else {"x": 0.1, "y": 0.15}
		var inp := {"main": hand, "off": {"x": -0.35, "y": 0.1}, "power": bool(st.sweep), "look": {"yaw": f.yaw, "pitch": 0.0}}
		if st.grab:
			inp["grab"] = true
			st.grab = false
		if st.grip:
			inp["grip"] = true
			st.grip = false
		return inp
	for i in 120:
		await get_tree().physics_frame
	if not start_with:
		var fwd := Vector3(sin(f.yaw), 0, cos(f.yaw))
		m.spawn_loose_weapon(design, f.torso.global_position + fwd * 0.7 + Vector3(0, 0.1, 0))
		for i in 60:
			await get_tree().physics_frame
		st.grab = true
		for i in 120 * 2:
			await get_tree().physics_frame
			if f.weapons.R != null:
				break
		if f.weapons.R == null:
			print("%-8s never took it up" % case_)
			m.queue_free()
			return
		if case_ == "pickup2":
			for i in 240:
				await get_tree().physics_frame
	if case_ == "onehand":
		st.grip = true    # H: one hand on it, the other free (the video: a long sword in one hand)
		for i in 30:
			await get_tree().physics_frame
	var two_at_start := f.two_handed
	st.sweep = true
	var frames := 0
	var two_frames := 0
	var off_runs := []
	var run := 0
	var head_hits := 0
	var worst_head := 9.0
	var gap_worst := 0.0
	for i in int(sweep_s * 120):
		await get_tree().physics_frame
		st.t = float(st.t) + 1.0 / 120.0
		if case_ == "regrip":
			if i == 120:
				st.grip = true    # H: let go
			if i == 360:
				st.grip = true    # H: take hold again, in the middle of the strokes
		var w: Weapon = f.weapons.R
		if w == null:
			break
		frames += 1
		if f.two_handed:
			two_frames += 1
			if run > 0:
				off_runs.append(run)
			run = 0
			if w.grip_off != null:
				gap_worst = maxf(gap_worst, f.hand_world("L").distance_to(w.global_transform * w.grip_off))
		elif case_ != "onehand" and (case_ != "regrip" or i < 120 or i > 360):
			run += 1
		var bl: Array = _blade(w)
		var r: float = minf(f.head.half_ext.x, f.head.half_ext.z)
		var d := _seg_dist(f.head.global_position, bl[0], bl[1]) / r
		worst_head = minf(worst_head, d)
		if d < 0.9:
			head_hits += 1
	if run > 0:
		off_runs.append(run)
	var longest := 0
	for r in off_runs:
		longest = maxi(longest, int(r))
	print("%-8s two-handed at the start %s; both hands on %3.0f%% of %.1f s; off the haft %d times, longest %.2f s; blade through the head %d frames (closest %.2f head radii); off hand up to %.3f m from its place on the grip" % [
		case_, str(two_at_start), 100.0 * two_frames / maxi(1, frames), frames / 120.0, off_runs.size(), longest / 120.0, head_hits, worst_head, gap_worst])
	m.queue_free()
	await get_tree().physics_frame

func _ready() -> void:
	var cases: Array = Array((OS.get_environment("CASES") if OS.get_environment("CASES") != "" else "start,pickup,pickup2,regrip,onehand").split(","))
	var design := Data.preset(OS.get_environment("WEAPON") if OS.get_environment("WEAPON") != "" else "longsword")
	var sweep_s := float(OS.get_environment("SWEEP_S")) if OS.get_environment("SWEEP_S") != "" else 8.0
	for c in cases:
		await _run(String(c), design, sweep_s)
	get_tree().quit()
