extends Node
## Why a man goes down with nothing to put him there (the sweep: a zweihander against a
## murmillo, the player on autopilot, down five times in a bout with no blow near it). One
## training bout, his trunk's tilt, stoop, legs and blade logged every tenth of a second, and
## each fall shown with the second before it. `-- --probe fallprobe`. MINE (zweihander), FOE
## (foe:murmillo), SEED (29), BOUT_S (30).

func _ready() -> void:
	var mine := OS.get_environment("MINE") if OS.get_environment("MINE") != "" else "zweihander"
	var foe := OS.get_environment("FOE") if OS.get_environment("FOE") != "" else "foe:murmillo"
	var sd := int(OS.get_environment("SEED")) if OS.get_environment("SEED") != "" else 29
	var secs := float(OS.get_environment("BOUT_S")) if OS.get_environment("BOUT_S") != "" else 30.0
	seed(sd)
	var arms := mine.split("+")
	var tr := {"immortal": false, "respawn": false, "difficulty": 0.7}
	if foe.begins_with("bot:"):
		tr.enemy = "gladiator"
		tr.weapon = foe.trim_prefix("bot:")
	else:
		tr.enemy = foe
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": tr, "autopilot": true, "headless": true, "seed": sd, "decrees": [], "hazards": [], "loadout": {"main": arms[0], "off": arms[1] if arms.size() > 1 else ""}})
	var f: Fighter = m.me.f
	var hist: Array = []
	var prev := f.state
	var falls := 0
	for i in int(secs * 120.0):
		await get_tree().physics_frame
		if not is_instance_valid(f):
			break
		var foe_f = null
		for e in m.enemies():
			if is_instance_valid(e.f) and e.f.alive:
				foe_f = e.f
		var up: Vector3 = f.torso.global_transform.basis.y.normalized()
		var tilt := rad_to_deg(acos(clampf(up.y, -1.0, 1.0)))
		var fwd := Vector3(sin(f.yaw), 0, cos(f.yaw))
		var lean := rad_to_deg(atan2(up.dot(fwd), up.y))   # + forward
		var w = f.weapons.get("R")
		var tip_y := -1.0
		if w and is_instance_valid(w) and w.has_method("tip_world"):
			tip_y = w.tip_world().y
		var row := "%5.1f %-6s tilt %5.1f lean %+6.1f tilt_t %4.2f stoop %.2f legs %.2f/%.2f can %s ground %s two %s jolt %4.1f trunk %.2f tip %.2f foe %s %.2f d %.1f" % [m.time, f.state, tilt, lean, f.tilt_t, f.stoop, f.leg_func("L"), f.leg_func("R"), str(f.can_stand()).left(1), str(f.on_ground).left(1), str(f.two_handed).left(1), f.time - f.jolt_t, f.torso.global_position.y, tip_y, String(foe_f.state).left(4) if foe_f else "-", foe_f.torso.global_position.y if foe_f else 0.0, foe_f.torso.global_position.distance_to(f.torso.global_position) if foe_f else 0.0]
		if i % 12 == 0:
			hist.append(row)
			if hist.size() > 12:
				hist.pop_front()
		if prev == "stand" and f.state == "down":
			falls += 1
			print("---- fall %d at %.1f s (jolt %.1f s ago, blood %.0f)" % [falls, m.time, f.time - f.jolt_t, f.blood])
			for h in hist:
				print("  " + h)
			print("  " + row)
		prev = f.state
		if not f.alive:
			break
	print("falls: %d" % falls)
	get_tree().quit()
