extends Node
## What the host sends each guest in the Ludus yard with N men in it (the host's own and N-1 friends), standing (idle), walking about (walk) or fighting
## (brawl): the snapshot rows the Match's own loop sends, one fighter to a message, counted as the engine packs a value (`-- --probe wire298`,
## headless, one frame to a step). A room of four friends or more sends the players' fighters 40 times a second and the rest every other time
## (Match._physics_process); the rows are counted with that same rule, so it is the rate of a full room. The host's line carries as many copies
## as it has guests. env: N (men, 8), BEHAVIOR (idle|walk|brawl|huddle: standing in a close ring, two paces from one another, the host's man in the middle), SECS (6), IDLE (0: the men who stand are not let sleep), ARM_LOD, NONPC (1: no keepers).

class CountingMatch extends Match:
	var wire_bytes := 0
	var wire_rows := 0
	var fake_peers := 0
	func snapshot(all := true, who := 0) -> Array:
		var r: Array = super.snapshot(all, who)
		if all:
			return r
		var full := fake_peers >= 4 or entities.size() > 10
		var odd := (tick / SNAP_EVERY) % 2 == 1
		for row in r:
			if who != 1 and full and odd:
				var re = entity_by_id(int(row[0]))
				if re != null and re.kind != "remote" and re.kind != "local":
					continue
			wire_bytes += var_to_bytes([row]).size()
			wire_rows += 1
		return r

func _env(k: String, d: String) -> String:
	var v := OS.get_environment(k)
	return v if v != "" else d

func _ready() -> void:
	var n_men := int(_env("N", "8"))
	var behavior := _env("BEHAVIOR", "idle")
	var secs := float(_env("SECS", "6"))
	seed(7)
	Fighter.arm_lod_on = _env("ARM_LOD", "1") != "0"
	Match.human_idle_on = _env("IDLE", "1") != "0"
	var m := CountingMatch.new()
	m.fake_peers = n_men - 1
	add_child(m)
	var lo := {"main": "gladius", "off": "scutum", "armor": ["helmet", "lorica", "manica", "greaves"]}
	m.setup({"mode": "yard", "headless": true, "seed": 7, "decrees": [], "hazards": [], "loadout": lo, "role": "host"})
	m.me.drive = func(_e): return {}
	if _env("NONPC", "0") == "1":
		for e in m.entities.duplicate():
			if e.kind == "npc":
				m._remove_entity(e)
	var heading := {}
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var ring := 3.0
	if behavior == "huddle":
		ring = 1.8 / (2.0 * sin(PI / float(maxi(2, n_men - 1))))
		m.me.f.teleport(Vector3(0.0, 0.0, 4.0))
	for i in n_men - 1:
		var a := TAU * float(i) / float(maxi(1, n_men - 1))
		var e = m.spawn_fighter({"kind": "bot", "name": "F%d" % i, "loadout": lo.duplicate(true), "team": 10 + i, "pos": Vector3(cos(a) * ring, 0.1, sin(a) * ring + 4.0), "yaw": a + PI})
		if behavior != "brawl":
			e.erase("bot")
			heading[e.id] = rng.randf() * TAU
			if behavior == "idle" or behavior == "huddle":
				e.drive = func(_e): return {}
			else:
				e.drive = func(en):
					var id: int = en.id
					if rng.randf() < 0.01:
						heading[id] = rng.randf() * TAU
					return {"mz": 1.0, "look": {"yaw": heading[id], "pitch": 0.0}}
	for i in int(_env("WARM", "360")):
		await get_tree().physics_frame
	m.wire_bytes = 0
	m.wire_rows = 0
	for i in int(secs * 120.0):
		await get_tree().physics_frame
	var asleep := 0
	for e in m.entities:
		if e.kind != "npc" and (e.get("hidle", false) or e.get("idle", false)):
			asleep += 1
	print("WIRE n=%d %s: %.1f KB a second to each guest (%.0f rows a second, %.0f bytes a row); %d of %d men asleep at the end; the host's line %.0f KB a second to %d guests" % [
		n_men, behavior, m.wire_bytes / 1024.0 / secs, m.wire_rows / secs, float(m.wire_bytes) / maxf(1.0, float(m.wire_rows)), asleep, n_men,
		m.wire_bytes / 1024.0 / secs * float(n_men - 1), n_men - 1])
	get_tree().quit()
