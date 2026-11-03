extends Node
## A fight's fingerprint: the player on autopilot, a gladiator and a lion, every die seeded,
## fought for a while; where everyone is, his blood and what is left of him printed at fixed
## ticks. Run it headless and steady (`--headless --fixed-fps 60 --path . -- --probe logicprint`):
## nothing is drawn, but the match's drawing side is on (its options do not say headless), so all
## the code of the looks runs as in a game. Run on two builds, the prints are the same when what
## changed between them is only how things look (LOGIC_SKY picks a time of day).

func _ready() -> void:
	seed(4242)
	var m := Match.new()
	add_child(m)
	var sky := OS.get_environment("LOGIC_SKY")
	m.setup({"mode": "training", "training": {"enemy": "gladiator", "difficulty": 0.8}, "seed": 4242, "decrees": [], "hazards": [], "autopilot": true, "sky": sky if sky != "" else "noon"})
	m.spawn_beast({"beast": "lion", "team": Match.ENEMY_TEAM, "pos": Vector3(4, 0.1, 4), "yaw": PI})
	for sec in 24:
		for i in 30:
			await get_tree().physics_frame
		var line := "t%02d" % sec
		for e in m.entities:
			var f = e.f
			if not is_instance_valid(f):
				line += " | gone"
				continue
			var vox := 0
			for p in f.parts:
				if is_instance_valid(p):
					vox += int(p.alive_count)
			var at: Vector3 = f.torso.global_position if f.torso and is_instance_valid(f.torso) else Vector3.ZERO
			line += " | %s %s blood=%.3f vox=%d %s" % [f.display_name, str(at.snapped(Vector3.ONE * 0.001)), float(f.get("blood") if f.get("blood") != null else 0.0), vox, f.state]
		print(line)
	get_tree().quit()
