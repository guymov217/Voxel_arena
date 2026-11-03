extends Node
## How a fight against a gladiator ends, and how fast (user: the bouts end too fast, there is no
## long struggle, one of the two always bleeds to death quickly). Campaign bouts, the player on
## autopilot, headless; for every man in the bout: when he died and of what, the blows he took,
## and the blood he lost by where it ran from (the wounds, a cut artery, a stump), with the time
## from his first wound to his death. `-- --probe bleedbout`.
## STAGES (1,3,5,7,11,14,17,19,23); SEEDS per stage (3); BOUT_S (150); MAIN, OFF (gladius, "").

func _ready() -> void:
	var stages := []
	for s in (OS.get_environment("STAGES") if OS.get_environment("STAGES") != "" else "1,3,5,7,11,14,17,19,23").split(",", false):
		stages.append(int(s))
	var seeds := int(OS.get_environment("SEEDS")) if OS.get_environment("SEEDS") != "" else 3
	var secs := float(OS.get_environment("BOUT_S")) if OS.get_environment("BOUT_S") != "" else 150.0
	var lo := {"main": OS.get_environment("MAIN") if OS.get_environment("MAIN") != "" else "gladius", "off": OS.get_environment("OFF")}
	var all_len := []
	var all_bleed := 0
	var all_deaths := 0
	for stage in stages:
		for k in seeds:
			var m := Match.new()
			add_child(m)
			m.setup({"mode": "campaign", "stage": stage, "headless": true, "autopilot": true, "seed": 101 + k * 13 + stage, "decrees": [], "hazards": [], "loadout": lo})
			var log := {}     # Fighter -> stats
			var order := []
			var t := [0.0]
			m.combat.hit.connect(func(h):
				var c = h.get("char")
				if c is Fighter and log.has(c):
					var L: Dictionary = log[c]
					L.hits += 1
					var res: Dictionary = h.get("res", {})
					L.dmg += float(res.get("dmg", 0.0))
					if res.get("artery", false):
						L.arteries += 1
					if L.first < 0.0 and float(res.get("dmg", 0.0)) > 0.5:
						L.first = t[0])
			var steps := int(secs * 120.0)
			for i in steps:
				await get_tree().physics_frame
				t[0] += 1.0 / 120.0
				for e in m.entities:
					var f = e.f
					if not (f is Fighter) or f is Beast:
						continue
					if not log.has(f):
						log[f] = {"name": ("YOU" if e == m.me else String(f.name)), "hits": 0, "dmg": 0.0, "arteries": 0, "first": -1.0, "died": -1.0, "cause": "", "wounds": 0.0, "artery": 0.0, "stump": 0.0, "blood": [], "peak": 0.0}
						order.append(f)
						f.died.connect(func(_f, cause):
							log[f].died = t[0]
							log[f].cause = str(cause))
					var L: Dictionary = log[f]
					if not f.alive:
						continue
					var w := 0.0
					var a := 0.0
					var s := 0.0
					for p in f.parts:
						w += p.bleed
						a += p.artery
						if p.stump:
							s += 2.5 * maxf(0.0, 1.0 - p.stump_t / 12.0)
					var k2: float = Fighter.BLEED_RATE * float(f.mods.bleed) / (f.S * f.S) / 120.0
					L.wounds += w * k2
					L.artery += a * k2
					L.stump += s * k2
					L.peak = maxf(L.peak, (w + a + s) * k2 * 120.0)
					if i % (120 * 15) == 0:
						(L.blood as Array).append(int(round(f.blood)))
				var you: Fighter = m.me.f
				var foes_left := m.entities.any(func(e): return e.team != m.me.team and e.f is Fighter and e.f.alive)
				if not you.alive or (not foes_left and t[0] > 5.0):
					break
			print("stage %2d seed %d  (%.0f s)" % [stage, k, t[0]])
			for f in order:
				var L: Dictionary = log[f]
				var fought: float = (L.died if L.died >= 0.0 else t[0]) - maxf(0.0, L.first)
				print("   %-14s %s  %2d blows (%4.0f harm, %d arteries)  lost to wounds %3.0f  artery %3.0f  stump %3.0f  worst %.1f/s  first wound %4.1f s, %s  blood %s" % [
					L.name, ("died at %5.1f s of %-6s" % [L.died, L.cause]) if L.died >= 0.0 else "alive              ", L.hits, L.dmg, L.arteries,
					L.wounds, L.artery, L.stump, L.peak, L.first, ("then %.1f s to death" % fought) if L.died >= 0.0 else "", str(L.blood)])
				if L.died >= 0.0:
					all_deaths += 1
					all_len.append(fought)
					if L.cause == "bleed":
						all_bleed += 1
			m.queue_free()
			await get_tree().physics_frame
	all_len.sort()
	print("BLEED %d deaths, %d of them bled out; first wound to death: median %.1f s, shortest %s" % [all_deaths, all_bleed, all_len[all_len.size() / 2] if not all_len.is_empty() else 0.0, str(all_len.slice(0, 5))])
	get_tree().quit()
