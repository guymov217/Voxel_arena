extends Node
## A man against a giant (user: the giant kept knocking him down with nothing touching him, and
## an arm came off with nothing touching it). The champion on autopilot fights each foe in FOES
## for BOUT_S seconds; every time he goes down, what happened to him in the half second before
## (a blow on him and from what, a blow on his weapon or shield, a grab or a throw, nothing at
## all), and every part of his that comes off, with the blow that took it if there was one.
## `-- --probe giantcontact`. FOES (foe:cyclops,foe:giant,foe:troll,foe:titan), BOUT_S (60), SEED.

func _ready() -> void:
	var foes: Array = Array((OS.get_environment("FOES") if OS.get_environment("FOES") != "" else "foe:cyclops,foe:giant,foe:troll,foe:titan").split(","))
	var secs := float(OS.get_environment("BOUT_S")) if OS.get_environment("BOUT_S") != "" else 60.0
	seed(int(OS.get_environment("SEED")) if OS.get_environment("SEED") != "" else 5)
	Fighter.trace_falls = true
	Fighter.unground_on = OS.get_environment("NO_UNGROUND") == ""
	for foe in foes:
		var m := Match.new()
		add_child(m)
		m.setup({"mode": "training", "training": {"enemy": foe, "immortal": true, "respawn": false, "difficulty": 0.8}, "autopilot": true, "headless": true, "seed": 5, "decrees": [], "hazards": [],
			"loadout": {"main": "gladius", "off": "roundShield", "armor": ["helmet", "manica", "greaves"]}})
		var me: Fighter = m.me.f
		var g: Fighter = m.enemies()[0].f
		var log := []   # [t, what]
		m.combat.hit.connect(func(h):
			var att = h.get("attacker")
			var vic = h.get("char")
			var w = h.get("weapon")
			if vic == me:
				var src := "?"
				if w != null and is_instance_valid(w):
					src = "weapon of " + (String(w.holder.display_name) if w.holder and is_instance_valid(w.holder) else "nobody")
				elif att != null and is_instance_valid(att):
					src = "body of " + String(att.display_name if "display_name" in att else att.name)
				var res = h.get("res", {})
				var sev: Array = (res.get("severed", []) as Array).map(func(p): return String(p.part_name)) if res is Dictionary else []
				log.append([m.time, "HIT %s J=%.0f on %s%s" % [src, float(h.get("J", 0.0)), String(h.part.part_name) if h.get("part") else "?", (" SEVERED " + str(sev)) if not sev.is_empty() else ""]])
			elif h.get("kind", "") == "clang" or (att == g and vic != me):
				log.append([m.time, "CLANG/other %s J=%.0f" % [str(h.get("kind", "")), float(h.get("J", 0.0))]]))
		var was_state := me.state
		var had := {}
		for p in me.parts:
			had[p] = p.severed
		var touch_log := []   # [t, giant part, my part] whenever a part of his touches a part of mine
		var downs := 0
		var unexplained := 0
		var cut_untouched := 0
		for i in int(secs * 120):
			await get_tree().physics_frame
			if not is_instance_valid(me) or not is_instance_valid(g):
				break
			me.blood = maxf(me.blood, 50.0)
			var t := m.time
			for gp in g.parts:
				var mp = m.combat.touch_by(gp, me, 0.01)
				if mp != null:
					touch_log.append([t, String(gp.part_name), String(mp.part_name)])
			while not touch_log.is_empty() and t - float(touch_log[0][0]) > 1.0:
				touch_log.pop_front()
			# Thrown or held by the giant, on record too.
			if me.thrown_t > 0.0 and (log.is_empty() or not String(log[log.size() - 1][1]).begins_with("THROWN")):
				log.append([t, "THROWN"])
			if g.get("holding") != null and g.holding is Dictionary and g.holding.get("f") == me and (log.is_empty() or not String(log[log.size() - 1][1]).begins_with("HELD")):
				log.append([t, "HELD"])
			if me.state == "down" and was_state != "down":
				downs += 1
				var recent: Array = log.filter(func(r): return t - float(r[0]) < 0.6)
				var gap: float = me.torso.global_position.distance_to(g.torso.global_position)
				var near := INF
				for gp in g.parts:
					for mp in me.parts:
						near = minf(near, (gp as Node3D).global_position.distance_to((mp as Node3D).global_position))
				var gw = g.weapons.get("R")
				var wnear := INF
				if gw:
					for mp in me.parts:
						wnear = minf(wnear, (gw as Node3D).global_position.distance_to((mp as Node3D).global_position))
				if recent.is_empty():
					unexplained += 1
				var why: Array = me.fall_stack.map(func(fr): return "%s:%d" % [String(fr.function), int(fr.line)])
				print("         fell by %s; touching in the last second: %s" % [str(why.slice(0, 4)), str(touch_log.map(func(r): return "%.2f %s>%s" % [r[0], r[1], r[2]]).slice(maxi(0, touch_log.size() - 8)))])
				var myw = me.weapons.get("R")
				if myw:
					print("         his own blade's lowest point %.3f m (the sand at 0)" % Fighter.lowest_of(myw))
				print("  %6.2f DOWN (trunk %.1f m from his, nearest parts %.2f m, his weapon %.2f m; stagger %.2f, stamina %.0f) after: %s" % [t, gap, near, wnear, me.stagger, me.stamina, str(recent.map(func(r): return "%.2f %s" % [r[0], r[1]]))])
			was_state = me.state
			for p in me.parts:
				if p.severed and not had[p]:
					had[p] = true
					var cause: Array = log.filter(func(r): return t - float(r[0]) < 0.25 and String(r[1]).contains("SEVERED") and String(r[1]).contains(String(p.part_name)))
					if cause.is_empty():
						cut_untouched += 1
						print("  %6.2f %s CAME OFF with no blow taking it (hanging %s); last: %s" % [t, p.part_name, str(p.hanging), str(log.slice(maxi(0, log.size() - 4)).map(func(r): return "%.2f %s" % [r[0], r[1]]))])
					else:
						print("  %6.2f %s cut off by %s" % [t, p.part_name, cause[0][1]])
		print("%-12s %d knockdowns, %d with nothing on record in the half second before; %d parts off with no blow" % [foe, downs, unexplained, cut_untouched])
		m.queue_free()
		await get_tree().physics_frame
	get_tree().quit()
