extends Node
## The fight tools/ir_profile counts in instructions under valgrind: the diagnostic test's eight in the endless arena, effects off, a step a frame, the same every run.
## IR_AT: the second of the game the counting starts at (1). For whole functions, IR_SECS: how long it goes on (1). For statements, IR_LIST: the regions counted in turn,
## and IR_B: the steps each one gets (4). IR_DRAW: the men are drawn as with a screen (their per-frame work is done, one frame a step). IR_FX: the match is not a
## headless one (a fight's effects are made as in play). IR_SAY: the men and the blows of each second are printed (to pick a second to count). With a library that has no
## counting calls in it the fight just runs.
func _ready() -> void:
	var at := (int(OS.get_environment("IR_AT")) if OS.get_environment("IR_AT") != "" else 1) * 120
	var secs := (int(OS.get_environment("IR_SECS")) if OS.get_environment("IR_SECS") != "" else 1) * 120
	var per := int(OS.get_environment("IR_B")) if OS.get_environment("IR_B") != "" else 4
	var list := OS.get_environment("IR_LIST").split(",", false)
	Fighter.process_in_headless = OS.get_environment("IR_DRAW") != ""
	seed(7)
	var lo := {"main": "gladius", "off": "scutum", "armor": DiagPhase.ARMOUR}
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "endless", "role": "host", "headless": OS.get_environment("IR_FX") == "", "autopilot": true, "seed": 7, "decrees": [], "hazards": [], "loadout": lo})
	m.gate_cost_ms = 0.0
	DiagPhase.new()._party(m, lo)
	var nc := Greedy.core()
	var counts: bool = nc != null and nc.has_method("ir_select")
	var say := OS.get_environment("IR_SAY") != ""
	var hits := [0]
	var said_us := [Time.get_ticks_usec()]
	if say:
		m.combat.hit.connect(func(_h): hits[0] += 1)
	for s in at + (list.size() * per if not list.is_empty() else secs) + 1:
		await get_tree().physics_frame
		if say and s % 120 == 119:
			var alive := m.entities.filter(func(e): return is_instance_valid(e.f) and e.f.alive)
			# (And what the fight has left on them and on the sand by then: the parts cut off, hanging and bleeding, the wounds' drips, the bodies awake.)
			var cut := 0
			var hang := 0
			var bled := 0
			var hurt := 0
			var drips := 0
			for e in m.entities:
				if not is_instance_valid(e.f):
					continue
				for p in e.f.parts:
					cut += 1 if p.severed else 0
					hang += 1 if p.hanging else 0
					bled += 1 if p.bleed > 0.0 or p.artery > 0.0 else 0
					hurt += 1 if p.alive_count < p.fx.size() else 0
					drips += p.drips.size() + p.spurts.size() + p.runs.size()
			# (And the things lying about that every step asks of each: the items by kind, the debris chunks, the gut ropes.)
			var kinds := {}
			for it in m.items.list:
				kinds[String(it.type) + (" grounded" if it.grounded else " flying")] = int(kinds.get(String(it.type) + (" grounded" if it.grounded else " flying"), 0)) + 1
			var ropes := 0
			for e in m.entities:
				if is_instance_valid(e.f) and e.f.get("gut_rope") != null and is_instance_valid(e.f.gut_rope):
					ropes += 1
			print("IRSAY items %s; %d chunks; %d gut ropes" % [kinds, Chunk.all.size(), ropes])
			var now_us := Time.get_ticks_usec()
			print("IRSAY second %d: %d alive (%d foes), %d blows; parts cut off %d, hanging %d, bleeding %d, with voxels gone %d, drips and runs %d; %d nodes, %d bodies awake, %d pairs; the second took %d ms" % [s / 120, alive.size(),
				alive.filter(func(e): return int(e.team) == Match.ENEMY_TEAM).size(), hits[0], cut, hang, bled, hurt, drips, int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
				int(Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS)), int(Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS)), (now_us - said_us[0]) / 1000])
			said_us[0] = now_us
			hits[0] = 0
		if not counts:
			continue
		if list.is_empty():
			if s == at:
				nc.ir_zero()
		elif s >= at and (s - at) % per == 0:
			var k: int = (s - at) / per
			nc.ir_select(int(list[k]) if k < list.size() else -1)
	get_tree().quit()
