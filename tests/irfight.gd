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
	if say:
		m.combat.hit.connect(func(_h): hits[0] += 1)
	for s in at + (list.size() * per if not list.is_empty() else secs) + 1:
		await get_tree().physics_frame
		if say and s % 120 == 119:
			var alive := m.entities.filter(func(e): return is_instance_valid(e.f) and e.f.alive)
			print("IRSAY second %d: %d alive (%d foes), %d blows" % [s / 120, alive.size(), alive.filter(func(e): return int(e.team) == Match.ENEMY_TEAM).size(), hits[0]])
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
