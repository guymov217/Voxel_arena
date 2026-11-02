extends Node
## Probe: a man with a blade in each hand (Bot.dual) against a sturdy man; between blows, where
## his hands are (the right's guard and the left's), by whether the man before him stands.

func _ready() -> void:
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": "none"}, "headless": true, "seed": 7, "decrees": [], "hazards": [], "loadout": {"main": "gladius", "off": ""}})
	var man: Fighter = m.me.f
	man.teleport(Vector3(0, 0, 0))
	man.mods.toughness = 4.0
	var e = m.spawn_fighter({"kind": "bot", "name": "Dimachaerus", "loadout": {"main": "gladius", "off": "dagger"}, "team": Match.ENEMY_TEAM, "pos": Vector3(0, 0.1, 2.0), "yaw": PI, "diff": 0.8, "personality": "standard"})
	var f: Fighter = e.f
	var rows := {}
	for i in 120 * 25:
		man.blood = 100.0
		man.head.hp = maxf(man.head.hp, 60.0)
		man.torso.hp = maxf(man.torso.hp, 60.0)
		await get_tree().physics_frame
		if e.bot.state == "attack":
			continue
		var k := "%s/%s/%s" % [e.bot.state, man.state, f.state]
		if not rows.has(k):
			rows[k] = {"n": 0, "up": 0, "ly": 0.0, "ry": 0.0, "rest": 0.0}
		var r: Dictionary = rows[k]
		r.n += 1
		var ly := float(f.hand_input.L.get("y", 0.0))
		r.up += 1 if ly > 0.0 else 0
		r.ly += ly
		r.ry += float(f.hand_input.R.get("y", 0.0))
		r.rest += float(e.bot.hand_rest.y)
	for k in rows:
		var r: Dictionary = rows[k]
		print("%-34s n %4d  up %4d  L.y %.2f  R.y %.2f  rest %.2f" % [k, r.n, r.up, r.ly / r.n, r.ry / r.n, r.rest / r.n])
	get_tree().quit()
