extends Node
## What a beast does in a training bout against the player on autopilot (the sweep: a dragon
## close by the player for half a minute without a blow): its mode every half second, the time
## it spends in each, its strikes and breaths, the player's blood and what hurt him.
## `-- --probe beastlog`. FOE (dragon), MINE (spear), SEED (57), BOUT_S (40).

func _ready() -> void:
	var foe := OS.get_environment("FOE") if OS.get_environment("FOE") != "" else "dragon"
	var mine := OS.get_environment("MINE") if OS.get_environment("MINE") != "" else "spear"
	var sd := int(OS.get_environment("SEED")) if OS.get_environment("SEED") != "" else 57
	var secs := float(OS.get_environment("BOUT_S")) if OS.get_environment("BOUT_S") != "" else 40.0
	seed(sd)
	var arms := mine.split("+")
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": foe, "immortal": false, "respawn": false, "difficulty": 0.7}, "autopilot": true, "headless": true, "seed": sd, "decrees": [], "hazards": [], "loadout": {"main": arms[0], "off": arms[1] if arms.size() > 1 else ""}})
	var me: Fighter = m.me.f
	var b = null
	for e in m.enemies():
		b = e.f
	var modes := {}
	var hurt := {}
	m.combat.hit.connect(func(h):
		if h.get("char") == me:
			var who := "beast" if h.get("attacker") == b else ("none" if h.get("attacker") == null else "other")
			var k := "%s %s" % [who, String(h.get("type", "?"))]
			hurt[k] = int(hurt.get(k, 0)) + 1)
	var last_mode := ""
	var blood0 := me.blood
	for i in int(secs * 120.0):
		await get_tree().physics_frame
		if b == null or not is_instance_valid(b) or not b.alive or not me.alive:
			break
		var md := String(b.ai.get("mode", "?"))
		modes[md] = float(modes.get(md, 0.0)) + 1.0 / 120.0
		if md != last_mode:
			last_mode = md
		if i % 60 == 0:
			var d: float = b.torso.global_position.distance_to(me.torso.global_position)
			print("%5.1f %-9s d %4.1f (%.1f S) bite_cool %.1f breath_cool %.1f fly_cool %.1f  me %s blood %.0f burning %s  beast y %.1f" % [m.time, md, d, d / b.S, float(b.ai.get("bite_cool", 0.0)), float(b.ai.get("breath_cool", 0.0)), float(b.ai.get("fly_cool", 0.0)), me.state, me.blood, str(me.parts.any(func(p): return p.burning > 0.0) if me.parts.size() > 0 and me.parts[0].get("burning") != null else "?"), b.torso.global_position.y])
	var ms := []
	for k in modes:
		ms.append("%s %.1f" % [k, modes[k]])
	print("modes (s): " + ", ".join(ms))
	print("what hit the player: %s; blood %.0f -> %.0f; beast %s" % [str(hurt), blood0, me.blood, "alive" if b and b.alive else "dead"])
	get_tree().quit()
