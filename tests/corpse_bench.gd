extends Node
## Probe: what the dead cost. Two men fighting with 0, 4, 8 and 12 bodies lying about (men and
## beasts killed where they stood): the time of a physics step with them (user: after about eight
## bodies the game slows right down). NS: JSON list of counts. Experiments, each an env flag:
## IDLE (the two stand still), NOPROC/PARTPROC (the dead's scripts off), SLEEP/FROZEN/NOJOINT/
## DISABLE (their physics), DETACH (not looked after at all), NOWEAP (no weapons left lying),
## GONE (freed), BOXES=n (plain boxes instead), DUMP (the node classes), DBG.

func _ready() -> void:
	for nn in (JSON.parse_string(OS.get_environment("NS")) if OS.get_environment("NS") != "" else [0, 4, 8, 12]):
		var n := int(nn)
		var m := Match.new()
		add_child(m)
		m.setup({"mode": "training", "training": {"enemy": "none", "respawn": false}, "headless": true, "seed": 7, "decrees": [], "hazards": []})
		m.me.f.teleport(Vector3(0, 0, -14))
		var ea = m.spawn_fighter({"kind": "bot", "name": "A", "loadout": {"main": "gladius"}, "team": 0, "pos": Vector3(-1.2, 0.1, 0), "yaw": PI * 0.5, "diff": 0.8})
		var eb = m.spawn_fighter({"kind": "bot", "name": "B", "loadout": {"main": "axe"}, "team": 1, "pos": Vector3(1.2, 0.1, 0), "yaw": -PI * 0.5, "diff": 0.8})
		if OS.get_environment("IDLE") != "":
			for x in [ea, eb]:
				x.erase("bot")
				x.drive = func(_e): return {}
		var dead := []
		for i in n:
			var a: float = TAU * i / maxf(1.0, float(n))
			var pos := Vector3(sin(a) * 6.0, 0.1, cos(a) * 6.0)
			if i % 3 == 2:
				dead.append(m.spawn_beast({"beast": ["wolf", "lion", "boar"][i % 3], "team": 1, "pos": pos, "yaw": a}))
			else:
				dead.append(m.spawn_fighter({"kind": "bot", "name": "D%d" % i, "loadout": {"main": "gladius"}, "team": 1, "pos": pos, "yaw": a}))
		var nb := int(OS.get_environment("BOXES")) if OS.get_environment("BOXES") != "" else 0
		for bi in nb:
			var rb := RigidBody3D.new()
			var cs := CollisionShape3D.new()
			var bs := BoxShape3D.new()
			bs.size = Vector3(0.2, 0.2, 0.2)
			cs.shape = bs
			rb.add_child(cs)
			m.add_child(rb)
			rb.global_position = Vector3(10 + (bi % 10) * 0.5, 0.11, -10 + (bi / 10) * 0.5)
			if OS.get_environment("BOXFROZEN") != "":
				rb.freeze = true
		for k in 30:
			await get_tree().physics_frame
		if OS.get_environment("NODIE") != "":
			for d in dead:
				m.entities.erase(d)
				m.combat.fighters.erase(d.f)
				d.f.free()
			dead = []
		for d in dead:
			d.erase("bot")
			if OS.get_environment("NOHANDLER") != "":
				for cn in d.f.died.get_connections():
					d.f.died.disconnect(cn.callable)
			d.f.set("spared", true)   # (no death's door: dead)
			d.f.die("bench")
			if OS.get_environment("DBG") != "":
				print("   after die: %s state %s alive %s" % [d.f.display_name, d.f.state, d.f.alive])
			if OS.get_environment("NOPROC") != "":
				d.f.set_physics_process(false)
				d.f.set_process(false)
		# Lying a while first, as the dead of a long fight do.
		for k in 360:
			await get_tree().physics_frame
		if OS.get_environment("DISABLE") != "":
			for d in dead:
				m.entities.erase(d)
				d.f.process_mode = Node.PROCESS_MODE_DISABLED
		if OS.get_environment("NOJOINT") != "":
			for d in dead:
				for j in d.f.find_children("*", "Joint3D", true, false):
					j.queue_free()
				for p in d.f.parts:
					if not p.severed:
						p.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
						p.freeze = true
		if OS.get_environment("NOWEAP") != "":
			for w in m.combat.loose_weapons.duplicate():
				if is_instance_valid(w):
					m.combat.loose_weapons.erase(w)
					w.queue_free()
		if OS.get_environment("GONE") != "":
			for d in dead:
				m.entities.erase(d)
				m.combat.fighters.erase(d.f)
				d.f.free()
		if OS.get_environment("DETACH") != "":
			for d in dead:
				m.entities.erase(d)
		if OS.get_environment("FROZEN") != "":
			for d in dead:
				for p in d.f.parts:
					if not p.severed:
						p.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
						p.freeze = true
		if OS.get_environment("PARTPROC") != "":
			for d in dead:
				for p in d.f.parts:
					p.set_physics_process(false)
					p.set_process(false)
		if OS.get_environment("SLEEP") != "":
			for d in dead:
				for p in d.f.parts:
					if not p.severed:
						p.can_sleep = true
						p.contact_monitor = false
		Engine.set_meta("prof", {})
		if OS.get_environment("DBG") != "":
			print("   entities: " + ", ".join(m.entities.map(func(x): return "%s/%s/%s" % [x.f.display_name, x.kind, x.f.state] if is_instance_valid(x.f) else "?")))
			for d in dead:
				if is_instance_valid(d.f):
					print("   later: %s state %s alive %s" % [d.f.display_name, d.f.state, d.f.alive])
		var t0 := Time.get_ticks_usec()
		var steps := 480
		var phys := 0.0
		var proc := 0.0
		var pure := 0
		for k in steps:
			await get_tree().physics_frame
			var tq := Time.get_ticks_usec()
			var acc := 0.0
			for q in 3000:
				acc += sin(float(q) * 0.01) * 1.0001
			pure += Time.get_ticks_usec() - tq
			phys += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
			proc += Performance.get_monitor(Performance.TIME_PROCESS)
		var ms := (Time.get_ticks_usec() - t0) / 1000.0 / steps
		var awake := 0
		var total := 0
		for d in dead:
			if not is_instance_valid(d.f):
				continue
			for p in d.f.parts:
				if not p.severed:
					total += 1
					if not p.sleeping and not p.freeze:
						awake += 1
		if OS.get_environment("DUMP") != "":
			var cnt := {}
			var walk := func(nd: Node, me: Callable) -> void:
				var k := "%s<%s" % [nd.get_class(), nd.get_parent().get_class() if nd.get_parent() else "-"]
				var sc = nd.get_script()
				if sc:
					k += " " + str(sc.resource_path.get_file())
				cnt[k] = cnt.get(k, 0) + 1
				for ch in nd.get_children():
					me.call(ch, me)
			walk.call(get_tree().root, walk)
			var ks := cnt.keys()
			ks.sort_custom(func(a, b): return cnt[a] > cnt[b])
			for k in ks.slice(0, 14):
				print("     %4d %s" % [cnt[k], k])
		print("   active %d pairs %d islands %d nodes %d objects %d" % [Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS), Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS), Performance.get_monitor(Performance.PHYSICS_3D_ISLAND_COUNT), Performance.get_monitor(Performance.OBJECT_NODE_COUNT), Performance.get_monitor(Performance.OBJECT_COUNT)])
		var pr: Dictionary = Engine.get_meta("prof", {})
		var line := ""
		for k in pr:
			line += "%s %.2f  " % [k, pr[k] / 1000.0 / steps]
		print("   over %s  ended %s" % [m.get("over"), m.get("ended")])
		print("   prof ms/step: " + line + " PURE %.3f" % (pure / 1000.0 / steps))
		print("CORPSES %2d: %.2f ms a step (physics process %.2f ms), dead parts awake %d of %d" % [n, ms, phys * 1000.0 / steps, awake, total])
		m.queue_free()
		for k in 10:
			await get_tree().physics_frame
	get_tree().quit()
