extends Node
## What the host's steps cost in the Ludus yard with N men in it (the host's own and N-1 more, as a room's friends are), standing (idle),
## walking about (walk) or fighting each other (brawl) (`-- --probe lobby298`, headless; with `--fixed-fps 120` the steps run back to back
## and their wall time is their cost). Prints the steps' wall time (mean, median, the worst hundredth, the worst), how many of the 120 a
## second the host could keep up, how much of a step the scripts and how much the engine take, and a fingerprint of every body at the end:
## two builds that print the same one have played it the same way, to the last bit (as tools/replay_check.sh).
## env: N (men, 8), BEHAVIOR (idle|walk|brawl|huddle: standing in a close ring, two paces from one another, the host's man in the middle|mixed: each man stands one to three seconds, walks about as long, and so on), SECS (game seconds, 6), SNAP (1: also pack the snapshot rows as the host's frame does),
## ARM_NATIVE (0: the arms kept out of the body by the script instead of the C++ core), ARM_LOD, IDLE (0: the arms at rest seen to every step / the men standing still not let sleep), ARMOR (1: helmet, lorica, manica, greaves; 0: bare), OFF (the left hand: scutum), MAIN (the right hand: gladius), NONPC (1: the yard's
## keepers sent away: their idle ways are not the same from run to run, and a fingerprint is to be).

var last_us := 0
var times := PackedInt32Array()
var snap_us := 0
var snap_n := 0
var snap_bytes := 0   # what the rows come to on the wire (as the engine packs a value), for a guest

func _env(k: String, d: String) -> String:
	var v := OS.get_environment(k)
	return v if v != "" else d

var a_us := 0   # the scripts' step: from this first node's step to the last node's
var b_us := 0   # the engine's: from the last node's step to the next first
var b_at := 0
var n_steps := 0
class EndMark extends Node:
	var owner_: Node
	func _physics_process(_dt: float) -> void:
		var now := Time.get_ticks_usec()
		owner_.a_us += now - owner_.last_us
		owner_.b_at = now

func _physics_process(_dt: float) -> void:
	var now := Time.get_ticks_usec()
	if b_at > 0:
		b_us += now - b_at
		b_at = 0
	if last_us > 0:
		times.append(now - last_us)
	last_us = now
	n_steps += 1

func _ready() -> void:
	var n_men := int(_env("N", "8"))
	var behavior := _env("BEHAVIOR", "idle")
	var secs := float(_env("SECS", "6"))
	var snap := _env("SNAP", "1") != "0"
	seed(7)
	# (The two ways of sparing the host in the yard are on, as in the game; ARM_LOD=0 / IDLE=0 for a build held to the bit.)
	Fighter.arm_lod_on = _env("ARM_LOD", "1") != "0"
	Match.human_idle_on = _env("IDLE", "1") != "0"
	# (ARM_NATIVE=0: the arms kept out of the body by the script, not the C++ core: the two to set side by side.)
	if _env("ARM_NATIVE", "1") == "0":
		Greedy.core()
		Greedy.arm_ok = false
	var m := Match.new()
	add_child(m)
	var lo := {"main": _env("MAIN", "gladius"), "off": _env("OFF", "scutum"), "armor": ["helmet", "lorica", "manica", "greaves"] if _env("ARMOR", "1") != "0" else []}
	m.setup({"mode": "yard", "headless": _env("HEADLESS", "1") == "1", "seed": 7, "decrees": [], "hazards": [], "loadout": lo, "role": "host"})
	m.me.drive = func(_e): return {}
	if _env("NONPC", "0") == "1":
		# (The keepers at their work are not the same from run to run: for the fingerprint they are sent away.)
		for e in m.entities.duplicate():
			if e.kind == "npc":
				m._remove_entity(e)
	var heading := {}
	var rng := RandomNumberGenerator.new()   # (the men's own: the keepers draw on the game's, and not at the same steps from run to run)
	rng.seed = 7
	var ring := 3.0
	if behavior == "huddle":
		# (A close ring: neighbours 1.8 m apart, the host's man in the middle of it: a room of friends stood round the gate.)
		ring = 1.8 / (2.0 * sin(PI / float(maxi(2, n_men - 1))))
		m.me.f.teleport(Vector3(0.0, 0.0, 4.0))
	for i in n_men - 1:
		var a := TAU * float(i) / float(maxi(1, n_men - 1))
		var spec := {"kind": "bot", "name": "F%d" % i, "loadout": lo.duplicate(true), "team": 10 + i, "pos": Vector3(cos(a) * ring, 0.1, sin(a) * ring + 4.0), "yaw": a + PI}
		var e = m.spawn_fighter(spec)
		if behavior != "brawl":
			e.erase("bot")
			heading[e.id] = rng.randf() * TAU
			if behavior == "idle" or behavior == "huddle":
				e.drive = func(_e): return {}
			elif behavior == "mixed":
				# (Friends as they are in a room: each stands for one to three seconds, walks about for as long, and so on.)
				var phase := [bool(rng.randf() < 0.5), int((1.0 + rng.randf() * 2.0) * 120.0)]
				e.drive = func(en):
					var id: int = en.id
					if n_steps >= int(phase[1]):
						phase[0] = not bool(phase[0])
						phase[1] = n_steps + int((1.0 + rng.randf() * 2.0) * 120.0)
						heading[id] = rng.randf() * TAU
					if bool(phase[0]):
						if rng.randf() < 0.01:
							heading[id] = rng.randf() * TAU
						return {"mz": 1.0, "look": {"yaw": heading[id], "pitch": 0.0}}
					return {}
			else:
				e.drive = func(en):
					var id: int = en.id
					if rng.randf() < 0.01:
						heading[id] = rng.randf() * TAU
					return {"mz": 1.0, "look": {"yaw": heading[id], "pitch": 0.0}}
	print("men: %d (%d fighters in the yard), behavior %s" % [n_men, m.entities.size(), behavior])
	var em := EndMark.new()
	em.name = "EndMark"
	em.owner_ = self
	em.process_physics_priority = 100000
	process_physics_priority = -100000
	add_child(em)
	for i in int(_env("WARM", "360")):
		await get_tree().physics_frame
	a_us = 0
	b_us = 0
	n_steps = 0
	times.clear()
	snap_us = 0
	snap_n = 0
	snap_bytes = 0
	var t0 := Time.get_ticks_usec()
	var steps := int(secs * 120.0)
	var last_pos := {}
	var path := {}
	var min_y := 9.0
	for e in m.entities:
		if e.kind != "npc" and is_instance_valid(e.f):
			last_pos[e.id] = e.f.torso.global_position
			path[e.id] = 0.0
	var mon := 0.0
	for i in steps:
		await get_tree().physics_frame
		mon += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
		if i % 12 == 0:
			for e in m.entities:
				if e.kind != "npc" and is_instance_valid(e.f):
					var pnow: Vector3 = e.f.torso.global_position
					path[e.id] += Vector2(pnow.x - last_pos[e.id].x, pnow.z - last_pos[e.id].z).length()
					last_pos[e.id] = pnow
					min_y = minf(min_y, pnow.y)
		if snap and i % 2 == 1:
			var a := Time.get_ticks_usec()
			var rows: Array = m.snapshot(false, 1)
			var rows2: Array = m.snapshot(false, 2) if i % 6 == 1 else []
			snap_us += Time.get_ticks_usec() - a
			snap_bytes += var_to_bytes(rows).size() + var_to_bytes(rows2).size()
			snap_n += 1
			# (The rows are the frame's work, not the step's: the clocks of the step go on from where the rows were done.)
			var spent := Time.get_ticks_usec() - a
			last_us += spent
			b_at += spent
	var wall := float(Time.get_ticks_usec() - t0) / 1000.0
	var s := Array(times)
	s.sort()
	var mean := 0.0
	for v in s:
		mean += float(v)
	mean /= maxf(1.0, float(s.size()))
	print("LOBBY n=%d %s: a step %.2f ms (median %.2f, p99 %.2f, worst %.2f) -> the host keeps up %.0f/120 steps; snapshot rows %.2f ms a frame (%d frames)" % [
		n_men, behavior, mean / 1000.0, s[s.size() / 2] / 1000.0, s[int(s.size() * 0.99)] / 1000.0, s[s.size() - 1] / 1000.0,
		minf(120.0, 1000000.0 / maxf(1.0, mean)), snap_us / 1000.0 / maxf(1.0, snap_n), snap_n])
	if snap:
		print("   WIRE: the rows a guest is sent come to %.1f KB a second" % (snap_bytes / 1024.0 / secs))
	print("   MONITOR: the engine counts %.2f ms a physics frame" % (mon / maxf(1.0, float(steps)) * 1000.0))
	print("   SPLIT: the scripts' step %.2f ms, the engine's %.2f ms (a step in all %.2f ms of wall time with the rest)" % [a_us / 1000.0 / maxf(1.0, n_steps), b_us / 1000.0 / maxf(1.0, n_steps), wall / maxf(1.0, n_steps)])
	var up_n := 0
	var tot_path := 0.0
	for e in m.entities:
		if e.kind != "npc" and is_instance_valid(e.f):
			up_n += 1 if e.f.state == "stand" else 0
			tot_path += float(path[e.id])
	print("STAND %d of %d on their feet, lowest torso %.2f m, the men walked %.2f m each" % [up_n, path.size(), min_y, tot_path / maxf(1.0, float(path.size()))])
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_MD5)
	var alive := 0
	for e in m.entities:
		if not is_instance_valid(e.f):
			continue
		alive += 1 if e.f.alive else 0
		if e.kind == "npc" and _env("HASHALL", "0") != "1":
			continue   # (the keepers' idle ways are not the same from run to run: only the men are held to the bit)
		if _env("HASHALL", "0") == "1":
			var c1 := HashingContext.new()
			c1.start(HashingContext.HASH_MD5)
			c1.update(Match.pack_parts(e.f.parts))
			print("   ENT %s %s %s" % [str(e.get("name", e.id)), str(e.kind), c1.finish().hex_encode().substr(0, 8)])
		ctx.update(Match.pack_parts(e.f.parts))
		var hp := PackedFloat32Array()
		for p in e.f.parts:
			hp.append(p.hp)
			hp.append(float(p.alive_count))
		ctx.update(hp.to_byte_array())
		for side in ["R", "L"]:
			var w = e.f.weapons.get(side)
			if w:
				ctx.update(Match.pack_parts([w]))
	print("LOBBYHASH n=%d %s alive=%d %s" % [n_men, behavior, alive, ctx.finish().hex_encode()])
	get_tree().quit()
