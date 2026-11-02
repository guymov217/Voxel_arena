extends Node
## What sends a part of the champion faster than any blow throws one (the sweep: a giant's
## bout, a shin at 31 m/s; a rhino's, his trunk two metres up on his feet): the sweep's bout
## played again, and every step a part of him passes FAST m/s, what was going on: the part, its
## speed and his trunk's, his state, whether he was thrown or held, how long since a weapon or a
## beast last struck him, the last blow on him, and what the foe's bot was doing.
## `-- --probe flungprobe`. FOE (foe:giant), MINE (zweihander), SEED (3), BOUT_S (16), FAST (20).
## TRACE=1: after each blow of J 40 or more on him, ten steps of his trunk's and head's speed as
## the step left them and after his own control (Fighter._no_fling) has had its say.
## IDLE=1: twice a second while the foe stands close by (the sweep's 2.8 x its scale) and has
## landed nothing for three seconds, what it and its bot are doing and how the champion lies.

## Runs after the match's own step (added after it): what control left the bodies at.
class After extends Node:
	var cb: Callable
	func _physics_process(_dt: float) -> void:
		cb.call()

func _ready() -> void:
	var foe := OS.get_environment("FOE") if OS.get_environment("FOE") != "" else "foe:giant"
	var mine := (OS.get_environment("MINE") if OS.get_environment("MINE") != "" else "zweihander").split("+")
	var sd := int(OS.get_environment("SEED")) if OS.get_environment("SEED") != "" else 3
	var secs := float(OS.get_environment("BOUT_S")) if OS.get_environment("BOUT_S") != "" else 16.0
	var fast := float(OS.get_environment("FAST")) if OS.get_environment("FAST") != "" else 20.0
	seed(sd)
	var m := Match.new()
	add_child(m)
	m.setup({"mode": "training", "training": {"enemy": foe, "immortal": false, "respawn": false, "difficulty": 0.7}, "autopilot": true, "headless": true, "seed": sd, "decrees": [], "hazards": [], "loadout": {"main": mine[0], "off": mine[1] if mine.size() > 1 else ""}})
	var me: Fighter = m.me.f
	var last := ["-"]
	m.combat.hit.connect(func(h):
		if h.get("char") == me:
			var att = h.get("attacker")
			last[0] = "%.2f %s on %s J %.0f%s%s" % [m.time, String(att.name) if att else "?", String(h.part.part_name) if h.get("part") else "?", float(h.get("J", 0.0)), " (severed)" if not (h.get("res", {}) as Dictionary).get("severed", []).is_empty() else "", " (lodged)" if (h.get("res", {}) as Dictionary).get("lodged", false) else ""])
	var told := 0
	var air := 0.0
	var trace := OS.get_environment("TRACE") == "1"
	var idle := OS.get_environment("IDLE") == "1"
	var landed := [0.0]
	m.combat.hit.connect(func(h):
		if h.get("char") == me:
			landed[0] = m.time)
	var watch := [0]
	if trace:
		m.combat.hit.connect(func(h):
			if h.get("char") == me and float(h.get("J", 0.0)) >= 40.0:
				watch[0] = 10)
		var a := After.new()
		a.cb = func():
			if watch[0] > 0 and is_instance_valid(me) and me.torso:
				var fastest := ""
				var fv := 0.0
				for p in me.parts:
					if is_instance_valid(p) and not p.severed and p.linear_velocity.length() > fv:
						fv = p.linear_velocity.length()
						fastest = p.part_name
				var ws := ""
				for hand in me.weapons:
					var w = me.weapons[hand]
					if w and is_instance_valid(w):
						ws += " %s %s %.1f" % [hand, str(w.linear_velocity.snapped(Vector3.ONE * 0.1)), w.linear_velocity.length()]
				print("   after control %.3f: trunk %s (%.1f) head %.1f fastest %s %.1f, v_free %s, weapons%s" % [m.time, str(me.torso.linear_velocity.snapped(Vector3.ONE * 0.1)), me.torso.linear_velocity.length(), me.head.linear_velocity.length() if is_instance_valid(me.head) else -1.0, fastest, fv, str(me.v_free.snapped(Vector3.ONE * 0.1)), ws])
		add_child(a)
	for i in int(secs * 120):
		await get_tree().physics_frame
		if not is_instance_valid(me) or me.torso == null:
			break
		var now := Engine.get_physics_frames()
		if trace and watch[0] > 0:
			watch[0] -= 1
			var touch := ""
			for p in me.parts:
				if is_instance_valid(p) and p.contact_monitor:
					for o in p.get_colliding_bodies():
						touch += " %s>%s%s%s" % [p.part_name, String(o.name), ("(" + String(o.fighter.name) + ")") if o is VoxelPart and o.fighter and o.fighter != me else "", (" [chunk %.1f kg]" % o.mass) if o is Chunk else ""]
			print("  before step %.3f: trunk %s (%.1f) head %.1f  weapon %d beast %d frames ago thrown %.2f held %s state %s  touching:%s" % [m.time, str(me.torso.linear_velocity.snapped(Vector3.ONE * 0.1)), me.torso.linear_velocity.length(), me.head.linear_velocity.length() if is_instance_valid(me.head) else -1.0, now - me.struck_frame, now - me.beast_frame, me.thrown_t, str(is_instance_valid(me.grabbed_by)), me.state, touch])
		var e = m.enemies()[0] if not m.enemies().is_empty() else null
		var bot = e.get("bot") if e else null
		var bs := "%s/%s" % [String(bot.state), String(bot.get("giant_kind")) if bot.get("giant_kind") != null else "-"] if bot else "-"
		if idle and e and is_instance_valid(e.f) and e.f.alive and i % 60 == 0:
			var gf: Fighter = e.f
			var dd: float = gf.torso.global_position.distance_to(me.torso.global_position)
			if dd < 2.8 * gf.S and gf.state == "stand" and m.time - landed[0] > 3.0:
				var legs := []
				for p in me.parts:
					if is_instance_valid(p) and p.severed:
						legs.append(p.part_name)
				var gi: Dictionary = e.get("input") if e.get("input") is Dictionary else {}
				print("%.1f idle? gap %.1f (x S %.2f) foe bot %s think %s stamina %.0f input mz %s mx %s %s  champion %s alive %s up %.2f cut off %s" % [m.time, dd, dd / gf.S, bs, str(bot.get("think")) if bot else "-", gf.stamina, str(gi.get("mz")), str(gi.get("mx")), str(gi.keys()), me.state, str(me.alive), me.torso.global_position.y - me.ground_level, str(legs)])
		for p in me.parts:
			if not is_instance_valid(p) or not p.is_inside_tree():
				continue
			var v: float = p.linear_velocity.length()
			if v > fast and told < 40:
				told += 1
				print("%.2f %s %.1f m/s%s  trunk %.1f m/s up %.2f  state %s thrown %.2f held %s  weapon %d beast %d frames ago  last blow: %s  foe bot %s" % [m.time, p.part_name, v, " (severed)" if p.severed else "", me.torso.linear_velocity.length(), me.torso.global_position.y - me.ground_level, me.state, me.thrown_t, str(is_instance_valid(me.grabbed_by)), now - me.struck_frame, now - me.beast_frame, last[0], bs])
		if me.state == "stand" and not me.on_ground and me.thrown_t <= 0.0 and me.grabbed_by == null:
			air += 1.0 / 120.0
			if air > 0.5 and int(air * 120) % 30 == 0:
				print("%.2f off the sand on his feet %.2f s, trunk %.2f m up, v %s, weapon %d beast %d frames ago, last blow: %s, foe bot %s" % [m.time, air, me.torso.global_position.y - me.ground_level, str(me.torso.linear_velocity.snapped(Vector3.ONE * 0.1)), now - me.struck_frame, now - me.beast_frame, last[0], bs])
		else:
			air = 0.0
	print("done at %.1f" % m.time)
	get_tree().quit()
