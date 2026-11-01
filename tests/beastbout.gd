extends Node
## How much of a beast a real fight takes off it: a training bout per species, the player on
## autopilot with an axe, headless; every blow that lands on the beast counted, with the voxels
## it took off (`-- --probe beastbout`). BEASTS: the species (boar,lion,wolf,bear,bull);
## BOUT_S: seconds of fight each (40).

func _ready() -> void:
	var list := OS.get_environment("BEASTS").split(",", false)
	if list.is_empty():
		list = PackedStringArray(["boar", "lion", "wolf", "bear", "bull"])
	var secs := float(OS.get_environment("BOUT_S")) if OS.get_environment("BOUT_S") != "" else 40.0
	Combat.canonical = true
	for sp in list:
		seed(7)
		var m := Match.new()
		add_child(m)
		m.setup({"mode": "training", "training": {"enemy": sp, "immortal": true}, "autopilot": true, "headless": true, "seed": 7, "decrees": [], "hazards": [], "loadout": {"main": "axe", "off": ""}})
		var st := {"n": 0, "J": 0.0, "vox": 0, "none": 0, "glance": 0, "by_type": {}, "parts": {}}
		var beast_total := [0]
		var bst := {"strikes": 0, "modes": {}, "near_idle": 0.0, "worst_idle": 0.0}
		m.combat.hit.connect(func(h):
			var c = h.get("char")
			if h.get("attacker") is Beast and c is Fighter and not (c is Beast):
				bst.strikes += 1
			if not (c is Beast):
				return
			var res: Dictionary = h.get("res", {})
			var n: int = 0
			for r in res.get("removed", []):
				n += (r.indices as Array).size()
			st.n += 1
			st.J += float(h.J)
			st.vox += n
			if n == 0:
				st.none += 1
			if res.get("glance", false):
				st.glance += 1
			var ty := String(h.type)
			st.by_type[ty] = int(st.by_type.get(ty, 0)) + 1
			var pn := String(h.part.part_name) if h.get("part") else "?"
			st.parts[pn] = int(st.parts.get(pn, 0)) + n)
		var steps := int(secs * 120.0)
		var since_strike := [0.0, 0]
		for i in steps:
			await get_tree().physics_frame
			for e in m.entities:
				if e.f is Beast and e.f.alive:
					var md := String(e.f.ai.get("mode", "?"))
					bst.modes[md] = int(bst.modes.get(md, 0)) + 1
					var d: float = e.f.torso.global_position.distance_to(m.me.f.torso.global_position)
					if d < 2.6 * e.f.S and bst.strikes == since_strike[1]:
						since_strike[0] += 1.0 / 120.0
						bst.worst_idle = maxf(bst.worst_idle, since_strike[0])
					else:
						since_strike[0] = 0.0
						since_strike[1] = bst.strikes
		var b: Beast = null
		for e in m.entities:
			if e.f is Beast:
				b = e.f
		if b:
			for p in b.parts:
				beast_total[0] += p.fx.size()
		var mean: float = float(st.J) / maxf(1.0, float(st.n))
		print("BEAST %-9s strikes on him %3d  longest close without one %.1f s  modes %s" % [sp, bst.strikes, bst.worst_idle, str(bst.modes)])
		print("BEAST %-9s hits %3d meanJ %5.1f voxels %5d (%.1f%% of %d) per-hit %.1f  none %d glance %d  types %s  parts %s  alive %s" % [sp, st.n, mean, st.vox, 100.0 * st.vox / maxf(1.0, float(beast_total[0])), beast_total[0], float(st.vox) / maxf(1.0, float(st.n)), st.none, st.glance, str(st.by_type), str(st.parts), str(b.alive) if b else "?"])
		m.queue_free()
		for i in 5:
			await get_tree().physics_frame
	get_tree().quit()
